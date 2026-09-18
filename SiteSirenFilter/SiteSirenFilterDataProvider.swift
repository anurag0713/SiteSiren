import Foundation
import NetworkExtension
import Network
import Darwin
import os.log

open class SiteSirenFilterDataProvider: NEFilterDataProvider {
    private let logger = Logger(subsystem: AppConstants.filterExtensionBundleIdentifier, category: "FilterDataProvider")
    private var blockedRules: [DomainRule] = []
    private let rulesLock = NSLock()
    private var isFilterActive: Bool = true
    
    // Darwin notification observer
    private var darwinObserver: UnsafeRawPointer?
    
    // MARK: - Lifecycle
    
    open override func startFilter(completionHandler: @escaping (Error?) -> Void) {
        logger.info("Starting SiteSirenFilterDataProvider...")
        
        reloadRules()
        registerDarwinObserver()
        
        // Filter outbound sockets by default so we can inspect and drop
        let filterSettings = NEFilterSettings(rules: [], defaultAction: .filterData)
        apply(filterSettings) { [weak self] error in
            if let error = error {
                self?.logger.error("Failed to apply filter settings: \(error.localizedDescription)")
                completionHandler(error)
            } else {
                self?.logger.info("Filter settings successfully applied.")
                completionHandler(nil)
            }
        }
    }
    
    open override func stopFilter(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        logger.info("Stopping filter data provider with reason: \(reason.rawValue)")
        unregisterDarwinObserver()
        completionHandler()
    }
    
    // MARK: - Rule Synchronization
    
    private func reloadRules() {
        rulesLock.lock()
        defer { rulesLock.unlock() }
        
        isFilterActive = SharedStore.shared.isProtectionEnabled()
        blockedRules = SharedStore.shared.loadBlockedDomains()
        logger.info("Reloaded rules: \(self.blockedRules.count) active rules, protectionEnabled = \(self.isFilterActive)")
    }
    
    private func registerDarwinObserver() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque())
        darwinObserver = observer
        
        CFNotificationCenterAddObserver(
            center,
            observer,
            { _, observer, name, _, _ in
                guard let observer = observer else { return }
                let provider = Unmanaged<SiteSirenFilterDataProvider>.fromOpaque(observer).takeUnretainedValue()
                provider.reloadRules()
            },
            AppConstants.rulesUpdatedDarwinNotification as CFString,
            nil,
            .deliverImmediately
        )
    }
    
    private func unregisterDarwinObserver() {
        if let observer = darwinObserver {
            let center = CFNotificationCenterGetDarwinNotifyCenter()
            CFNotificationCenterRemoveObserver(center, observer, nil, nil)
            darwinObserver = nil
        }
    }
    
    // MARK: - Flow Handling
    
    open override func handleNewFlow(_ flow: NEFilterFlow) -> NEFilterNewFlowVerdict {
        rulesLock.lock()
        let active = isFilterActive
        let currentRules = blockedRules
        rulesLock.unlock()
        
        guard active, !currentRules.isEmpty else {
            return .allow()
        }
        
        // 1. Check if URL/host is immediately available from flow metadata
        if let host = extractHostname(from: flow) {
            if let matchedRule = matchesBlockedDomain(candidate: host, rules: currentRules) {
                handleBlockedFlow(flow: flow, domain: host, matchedRule: matchedRule)
                return .drop()
            }
            // Host is known and not blocked -> allow immediately
            return .allow()
        }
        
        // 2. If host is not yet known (e.g. raw IP socket to port 80/443), peek outbound bytes for SNI/Host
        return .filterDataVerdict(
            withFilterInbound: false,
            peekInboundBytes: 0,
            filterOutbound: true,
            peekOutboundBytes: 1024
        )
    }
    
    open override func handleOutboundData(from flow: NEFilterFlow, readBytesStartOffset offset: Int, readBytes: Data) -> NEFilterDataVerdict {
        rulesLock.lock()
        let active = isFilterActive
        let currentRules = blockedRules
        rulesLock.unlock()
        
        guard active, !currentRules.isEmpty else {
            return .allow()
        }
        
        // Parse SNI or HTTP Host from first chunk of outbound traffic
        if let host = TLSInspector.extractHostname(from: readBytes) {
            if let matchedRule = matchesBlockedDomain(candidate: host, rules: currentRules) {
                handleBlockedFlow(flow: flow, domain: host, matchedRule: matchedRule)
                return .drop()
            }
            return .allow()
        }
        
        // If we have peeked enough bytes and found no matching host, pass remainder of flow
        if offset > 2048 {
            return .allow()
        }
        
        // Peek a bit more if needed
        return NEFilterDataVerdict(passBytes: 0, peekBytes: 1024)
    }
    
    // MARK: - Matching & Event Reporting
    
    private func extractHostname(from flow: NEFilterFlow) -> String? {
        if let url = flow.url, let host = url.host, !host.isEmpty {
            return host
        }
        
        if let socketFlow = flow as? NEFilterSocketFlow {
            if let hostname = socketFlow.remoteHostname, !hostname.isEmpty {
                return hostname
            }
            if let hostEndpoint = socketFlow.remoteEndpoint as? NWHostEndpoint {
                return hostEndpoint.hostname
            }
        }
        
        return nil
    }
    
    private func matchesBlockedDomain(candidate: String, rules: [DomainRule]) -> DomainRule? {
        for rule in rules {
            if DomainRule.matches(candidate: candidate, ruleDomain: rule.domain) {
                return rule
            }
        }
        return nil
    }
    
    private func extractProcessName(from flow: NEFilterFlow) -> String? {
        let auditData = flow.sourceAppAuditToken ?? flow.sourceProcessAuditToken
        guard let data = auditData, data.count == MemoryLayout<audit_token_t>.size else {
            return nil
        }
        
        var token = audit_token_t()
        _ = withUnsafeMutableBytes(of: &token) { data.copyBytes(to: $0) }
        let pid = pid_t(token.val.5)
        var buffer = [CChar](repeating: 0, count: 256)
        proc_name(pid, &buffer, 256)
        let name = String(cString: buffer)
        return name.isEmpty ? nil : name
    }
    
    private func handleBlockedFlow(flow: NEFilterFlow, domain: String, matchedRule: DomainRule) {
        let process = extractProcessName(from: flow)
        logger.notice("BLOCKED ACCESS ATTEMPT: domain=\(domain), rule=\(matchedRule.domain), process=\(process ?? "unknown")")
        
        let event = BlockEvent(
            domain: domain,
            timestamp: Date(),
            processName: process
        )
        
        // Record event in shared store and notify main application
        SharedStore.shared.recordBlockEvent(event)
        SharedStore.postBlockEventOccurred()
    }
}
