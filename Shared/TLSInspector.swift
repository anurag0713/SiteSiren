import Foundation

/// Lightweight, high-performance packet inspector for extracting target hostnames
/// from raw outbound traffic (TLS ClientHello SNI or HTTP Host headers) without MITM or TLS decryption.
public enum TLSInspector {
    
    /// Extracts the Server Name Indication (SNI) from a TLS ClientHello packet.
    ///
    /// TLS Record Layer:
    /// [0]     = 0x16 (Handshake)
    /// [1..2] = TLS Version (e.g. 0x03 0x01, 0x03 0x03)
    /// [3..4] = Length of handshake payload
    /// [5]     = Handshake Type: 0x01 (ClientHello)
    /// [6..8] = Length of ClientHello
    /// [9..10]= Client version
    /// [11..42] = Random (32 bytes)
    /// [43]    = Session ID length (len)
    /// [44 + len ..] = Cipher Suites length (2 bytes) + suites
    /// [... next] = Compression Methods length (1 byte) + methods
    /// [... next] = Extensions length (2 bytes) + list of extensions
    public static func extractSNI(from data: Data) -> String? {
        guard data.count >= 44 else { return nil }
        
        // 1. Verify Handshake Record (0x16) and TLS Major Version 3 (0x03)
        guard data[0] == 0x16 && data[1] == 0x03 else { return nil }
        
        // 2. Verify Handshake Type is ClientHello (0x01)
        guard data[5] == 0x01 else { return nil }
        
        var offset = 9 // Skip Record Header (5 bytes) + Handshake Type & Length (4 bytes)
        
        // Skip client version (2 bytes) + random (32 bytes)
        offset += 2 + 32
        guard offset < data.count else { return nil }
        
        // Session ID
        let sessionIdLength = Int(data[offset])
        offset += 1 + sessionIdLength
        guard offset + 2 <= data.count else { return nil }
        
        // Cipher Suites
        let cipherSuitesLength = (Int(data[offset]) << 8) | Int(data[offset + 1])
        offset += 2 + cipherSuitesLength
        guard offset + 1 <= data.count else { return nil }
        
        // Compression Methods
        let compressionLength = Int(data[offset])
        offset += 1 + compressionLength
        guard offset + 2 <= data.count else { return nil }
        
        // Extensions
        let extensionsLength = (Int(data[offset]) << 8) | Int(data[offset + 1])
        offset += 2
        let extensionsEnd = min(offset + extensionsLength, data.count)
        
        while offset + 4 <= extensionsEnd {
            let extensionType = (Int(data[offset]) << 8) | Int(data[offset + 1])
            let extensionLength = (Int(data[offset + 2]) << 8) | Int(data[offset + 3])
            offset += 4
            
            // Extension 0x0000 = server_name
            if extensionType == 0x0000 {
                guard offset + extensionLength <= extensionsEnd, extensionLength >= 2 else { return nil }
                let serverNameListLength = (Int(data[offset]) << 8) | Int(data[offset + 1])
                var sniOffset = offset + 2
                let sniEnd = min(sniOffset + serverNameListLength, offset + extensionLength)
                
                while sniOffset + 3 <= sniEnd {
                    let nameType = data[sniOffset]
                    let nameLength = (Int(data[sniOffset + 1]) << 8) | Int(data[sniOffset + 2])
                    sniOffset += 3
                    
                    // NameType 0 = host_name
                    if nameType == 0 && sniOffset + nameLength <= sniEnd {
                        let nameData = data.subdata(in: sniOffset..<sniOffset + nameLength)
                        return String(data: nameData, encoding: .utf8)
                    }
                    sniOffset += nameLength
                }
            }
            offset += extensionLength
        }
        
        return nil
    }
    
    /// Extracts the Host header from an unencrypted HTTP request.
    public static func extractHTTPHost(from data: Data) -> String? {
        guard let text = String(data: data.prefix(1024), encoding: .ascii) else { return nil }
        
        let methods = ["GET ", "POST ", "HEAD ", "PUT ", "DELETE ", "CONNECT ", "OPTIONS "]
        guard methods.contains(where: { text.hasPrefix($0) }) else { return nil }
        
        let lines = text.components(separatedBy: "\r\n")
        for line in lines {
            if line.lowercased().hasPrefix("host:") {
                let parts = line.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: true)
                if parts.count >= 2 {
                    let hostCandidate = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    return hostCandidate
                }
            }
        }
        return nil
    }
    
    /// Attempts to extract the target hostname from either TLS or HTTP data.
    public static func extractHostname(from data: Data) -> String? {
        if let sni = extractSNI(from: data) {
            return sni
        }
        return extractHTTPHost(from: data)
    }
}
