import Foundation
import Network
import os.log

/// High-performance local filtering engine that intercepts blocked domains
/// via macOS Proxy Auto-Configuration (PAC) without requiring paid Apple Developer ($99) entitlements.
/// All non-blocked traffic goes "DIRECT" (never touches the proxy, ensuring normal internet is never broken).
public final class LocalFilterEngine: @unchecked Sendable {
    public static let defaultPort: UInt16 = 8282

    public var onBlockDetected: ((_ domain: String) -> Void)?

    private let port: UInt16
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.personal.SiteSiren.LocalFilterEngine", qos: .userInitiated)
    private let logger = Logger(subsystem: AppConstants.appBundleIdentifier, category: "LocalFilterEngine")

    private var isRunning = false
    private let stateLock = NSLock()

    /// In-memory cache of the blocked-domain list.
    /// Updated at start() and refreshPAC() instead of reading from disk per-connection.
    private var cachedRules: [DomainRule] = []
    private let rulesLock = NSLock()

    public init(port: UInt16 = LocalFilterEngine.defaultPort) {
        self.port = port
    }
    
    // MARK: - Lifecycle

    public func start() {
        stateLock.lock()
        defer { stateLock.unlock() }

        guard !isRunning else { return }

        do {
            let params = NWParameters.tcp
            let nwPort = NWEndpoint.Port(rawValue: port)!
            let newListener = try NWListener(using: params, on: nwPort)

            newListener.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                switch state {
                case .ready:
                    self.logger.info("LocalFilterEngine listener ready on 127.0.0.1:\(self.port)")
                case .failed(let error):
                    self.logger.error("LocalFilterEngine listener failed: \(error.localizedDescription)")
                default:
                    break
                }
            }

            newListener.newConnectionHandler = { [weak self] clientConn in
                self?.handleIncomingConnection(clientConn)
            }

            newListener.start(queue: queue)
            self.listener = newListener
            self.isRunning = true

            // Load domain list into memory before enabling PAC
            reloadRulesCache()
            enableSystemPAC()
            logger.notice("LocalFilterEngine started on port \(self.port). PAC enabled on active network interfaces.")
        } catch {
            logger.error("Failed to start LocalFilterEngine: \(error.localizedDescription)")
        }
    }

    public func stop() {
        stateLock.lock()
        defer { stateLock.unlock() }

        guard isRunning else { return }

        listener?.cancel()
        listener = nil
        isRunning = false

        rulesLock.lock()
        cachedRules = []
        rulesLock.unlock()

        disableSystemPAC()
        logger.notice("LocalFilterEngine stopped. PAC disabled on active network interfaces.")
    }
    
    // MARK: - Connection Handling
    
    private func handleIncomingConnection(_ client: NWConnection) {
        client.start(queue: queue)
        
        client.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self = self else {
                client.cancel()
                return
            }
            
            if let error = error {
                self.logger.debug("Client receive error: \(error.localizedDescription)")
                client.cancel()
                return
            }
            
            guard let data = data, !data.isEmpty else {
                client.cancel()
                return
            }
            
            self.processInitialRequest(client: client, data: data)
        }
    }
    
    private func processInitialRequest(client: NWConnection, data: Data) {
        guard let requestString = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
            client.cancel()
            return
        }
        
        let lines = requestString.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else {
            client.cancel()
            return
        }
        
        // 1. Check if this is a request for the PAC configuration script
        if firstLine.contains("/proxy.pac") || firstLine.contains("/pac") {
            servePACScript(client: client)
            return
        }
        
        let tokens = firstLine.split(separator: " ")
        guard tokens.count >= 2 else {
            client.cancel()
            return
        }
        
        let method = String(tokens[0]).uppercased()
        let target = String(tokens[1])
        
        var targetHost: String = ""
        var targetPort: UInt16 = 80
        
        if method == "CONNECT" {
            // HTTPS Tunnel: target is "host:port" (e.g. "www.youtube.com:443")
            let parts = target.split(separator: ":")
            if let h = parts.first {
                targetHost = String(h)
            }
            if parts.count > 1, let p = UInt16(parts[1]) {
                targetPort = p
            } else {
                targetPort = 443
            }
        } else {
            // Standard HTTP: check URL or Host header
            if let url = URL(string: target), let h = url.host {
                targetHost = h
                targetPort = UInt16(url.port ?? 80)
            } else {
                for line in lines {
                    if line.lowercased().hasPrefix("host:") {
                        let parts = line.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: true)
                        if parts.count >= 2 {
                            targetHost = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                            if parts.count > 2, let p = UInt16(parts[2].trimmingCharacters(in: .whitespacesAndNewlines)) {
                                targetPort = p
                            }
                        }
                        break
                    }
                }
            }
        }
        
        guard !targetHost.isEmpty else {
            client.cancel()
            return
        }

        // Check if targetHost matches any blocked domain rule (uses in-memory cache — no disk I/O per connection)
        rulesLock.lock()
        let rules = cachedRules
        rulesLock.unlock()

        if let matchedRule = matchesBlockedDomain(candidate: targetHost, rules: rules) {
            handleBlockedRequest(client: client, domain: targetHost, rule: matchedRule)
            return
        }

        // Allowed: proxy connection to destination
        forwardConnection(client: client, targetHost: targetHost, targetPort: targetPort, isConnectMethod: method == "CONNECT", initialData: data)
    }
    
    // MARK: - Dynamic PAC Generation

    private func servePACScript(client: NWConnection) {
        rulesLock.lock()
        let rules = cachedRules
        rulesLock.unlock()

        let domainsJSON: String
        if let data = try? JSONEncoder().encode(rules.map { $0.domain }),
           let json = String(data: data, encoding: .utf8) {
            domainsJSON = json
        } else {
            domainsJSON = "[]"
        }

        let pacScript = """
        function FindProxyForURL(url, host) {
            var blocked = \(domainsJSON);
            var h = (host || "").toLowerCase();
            for (var i = 0; i < blocked.length; i++) {
                var d = blocked[i].toLowerCase();
                if (h === d || (h.length > d.length && h.slice(-d.length - 1) === ("." + d))) {
                    return "PROXY 127.0.0.1:\(self.port)";
                }
            }
            return "DIRECT";
        }
        """

        let header = "HTTP/1.1 200 OK\r\nContent-Type: application/x-ns-proxy-autoconfig\r\nCache-Control: no-cache, no-store, must-revalidate\r\nPragma: no-cache\r\nExpires: 0\r\nConnection: close\r\nContent-Length: \(pacScript.utf8.count)\r\n\r\n"
        let fullResponse = Data((header + pacScript).utf8)

        client.send(content: fullResponse, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed({ _ in
            client.cancel()
        }))
    }

    /// Atomically reloads the in-memory domain cache from persistent storage.
    /// Called by start() and refreshPAC() on the main/caller thread.
    private func reloadRulesCache() {
        let freshRules = SharedStore.shared.loadBlockedDomains()
        rulesLock.lock()
        cachedRules = freshRules
        rulesLock.unlock()
        logger.info("Domain cache reloaded: \(freshRules.count) rule(s)")
    }

    private func matchesBlockedDomain(candidate: String, rules: [DomainRule]) -> DomainRule? {
        for rule in rules {
            if DomainRule.matches(candidate: candidate, ruleDomain: rule.domain) {
                return rule
            }
        }
        return nil
    }
    
    private func handleBlockedRequest(client: NWConnection, domain: String, rule: DomainRule) {
        logger.notice("LOCAL FILTER BLOCKED: domain=\(domain), rule=\(rule.domain)")
        
        let response = "HTTP/1.1 403 Forbidden\r\nConnection: close\r\nContent-Type: text/plain\r\nContent-Length: 26\r\n\r\nBlocked by SiteSiren\n"
        let respData = Data(response.utf8)
        
        client.send(content: respData, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed({ _ in
            client.cancel()
        }))
        
        // Trigger block alert in main app
        DispatchQueue.main.async { [weak self] in
            self?.onBlockDetected?(domain)
        }
    }
    
    private func forwardConnection(
        client: NWConnection,
        targetHost: String,
        targetPort: UInt16,
        isConnectMethod: Bool,
        initialData: Data
    ) {
        guard let endpointPort = NWEndpoint.Port(rawValue: targetPort) else {
            client.cancel()
            return
        }
        
        let hostEndpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(targetHost), port: endpointPort)
        let server = NWConnection(to: hostEndpoint, using: .tcp)
        
        server.stateUpdateHandler = { [weak self, weak client, weak server] state in
            guard let self = self, let client = client, let server = server else { return }
            
            switch state {
            case .ready:
                if isConnectMethod {
                    let established = "HTTP/1.1 200 Connection Established\r\n\r\n"
                    client.send(content: Data(established.utf8), completion: .contentProcessed({ sendError in
                        if sendError != nil {
                            client.cancel()
                            server.cancel()
                            return
                        }
                        self.pipe(from: client, to: server)
                        self.pipe(from: server, to: client)
                    }))
                } else {
                    server.send(content: initialData, completion: .contentProcessed({ sendError in
                        if sendError != nil {
                            client.cancel()
                            server.cancel()
                            return
                        }
                        self.pipe(from: client, to: server)
                        self.pipe(from: server, to: client)
                    }))
                }
            case .failed, .cancelled:
                client.cancel()
            default:
                break
            }
        }
        
        server.start(queue: queue)
    }
    
    private func pipe(from source: NWConnection, to destination: NWConnection) {
        source.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self, weak source, weak destination] data, _, isComplete, error in
            guard let self = self, let source = source, let destination = destination else { return }
            
            if let data = data, !data.isEmpty {
                destination.send(content: data, completion: .contentProcessed({ sendError in
                    if sendError == nil && !isComplete {
                        self.pipe(from: source, to: destination)
                    } else {
                        source.cancel()
                        destination.cancel()
                    }
                }))
            } else if isComplete || error != nil {
                source.cancel()
                destination.cancel()
            }
        }
    }
    
    // MARK: - macOS Automatic Proxy (PAC) Configuration
    
    private func getActiveServices() -> [String] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        task.arguments = ["-listallnetworkservices"]
        let pipe = Pipe()
        task.standardOutput = pipe
        try? task.run()
        task.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return ["Wi-Fi", "Ethernet"] }
        
        let services = output.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("An asterisk") && !$0.hasPrefix("*") }
        
        return services.isEmpty ? ["Wi-Fi", "Ethernet"] : services
    }
    
    private func currentPACURL() -> String {
        return "http://127.0.0.1:\(port)/proxy.pac?v=\(Int(Date().timeIntervalSince1970))"
    }
    
    public func enableSystemPAC() {
        let pacURL = currentPACURL()
        let services = getActiveServices()
        for service in services {
            runNetworkSetup(["-setautoproxyurl", service, pacURL])
            runNetworkSetup(["-setautoproxystate", service, "on"])
        }
        logger.notice("PAC enabled across network services: \(pacURL)")
    }
    
    public func refreshPAC() {
        stateLock.lock()
        let active = isRunning
        stateLock.unlock()

        guard active else { return }

        // Refresh in-memory rules before updating the PAC URL
        reloadRulesCache()

        let pacURL = currentPACURL()
        let services = getActiveServices()
        for service in services {
            // Toggling state forces Chromium / WebKit to flush internal PAC cache and connection pools across all profiles
            runNetworkSetup(["-setautoproxystate", service, "off"])
            runNetworkSetup(["-setautoproxyurl", service, pacURL])
            runNetworkSetup(["-setautoproxystate", service, "on"])
        }
        logger.notice("PAC refreshed across network services: \(pacURL)")
    }
    
    public func disableSystemPAC() {
        let services = getActiveServices()
        for service in services {
            runNetworkSetup(["-setautoproxystate", service, "off"])
        }
    }
    
    private func runNetworkSetup(_ arguments: [String]) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        task.arguments = arguments
        try? task.run()
        task.waitUntilExit()
    }
}
