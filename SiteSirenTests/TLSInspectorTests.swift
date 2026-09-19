import XCTest
@testable import SiteSiren

final class TLSInspectorTests: XCTestCase {
    
    func testHTTPHostExtraction() {
        let rawHTTP = "GET /index.html HTTP/1.1\r\nHost: www.youtube.com:443\r\nUser-Agent: curl/8.7.1\r\nAccept: */*\r\n\r\n"
        let data = Data(rawHTTP.utf8)
        let extracted = TLSInspector.extractHTTPHost(from: data)
        XCTAssertEqual(extracted, "www.youtube.com")
    }
    
    func testNonHTTPDataReturnsNil() {
        let arbitraryData = Data([0x01, 0x02, 0x03, 0x04])
        XCTAssertNil(TLSInspector.extractHTTPHost(from: arbitraryData))
    }
    
    func testTLSSNIExtraction() {
        // Construct a valid TLS 1.3 ClientHello packet containing SNI "reddit.com"
        var packet = Data()
        // Record Header: Handshake (0x16), Version TLS 1.0 (0x03, 0x01)
        packet.append(contentsOf: [0x16, 0x03, 0x01, 0x00, 0x00]) // length placeholder at [3..4]
        
        var handshake = Data()
        handshake.append(contentsOf: [0x01]) // ClientHello
        handshake.append(contentsOf: [0x00, 0x00, 0x00]) // Handshake length placeholder [1..3]
        handshake.append(contentsOf: [0x03, 0x03]) // Client version TLS 1.2
        handshake.append(Data(repeating: 0xAA, count: 32)) // Random (32 bytes)
        handshake.append(0x00) // Session ID length: 0
        handshake.append(contentsOf: [0x00, 0x02, 0x13, 0x01]) // Cipher suites (2 bytes len + 2 bytes suite)
        handshake.append(contentsOf: [0x01, 0x00]) // Compression: 1 byte len + null compression
        
        // Extensions
        var extensions = Data()
        // server_name extension: type 0x0000
        let hostBytes = Array("reddit.com".utf8)
        var serverNameList = Data()
        serverNameList.append(0x00) // NameType: host_name (0)
        serverNameList.append(contentsOf: [UInt8(hostBytes.count >> 8), UInt8(hostBytes.count & 0xFF)])
        serverNameList.append(contentsOf: hostBytes)
        
        var sniExt = Data()
        sniExt.append(contentsOf: [0x00, 0x00]) // ext type: 0
        let sniPayloadLen = serverNameList.count + 2
        sniExt.append(contentsOf: [UInt8(sniPayloadLen >> 8), UInt8(sniPayloadLen & 0xFF)])
        sniExt.append(contentsOf: [UInt8(serverNameList.count >> 8), UInt8(serverNameList.count & 0xFF)])
        sniExt.append(serverNameList)
        
        extensions.append(sniExt)
        
        // Append extensions length + extensions to handshake
        handshake.append(contentsOf: [UInt8(extensions.count >> 8), UInt8(extensions.count & 0xFF)])
        handshake.append(extensions)
        
        // Fix handshake length
        let hsLen = handshake.count - 4
        handshake[1] = UInt8((hsLen >> 16) & 0xFF)
        handshake[2] = UInt8((hsLen >> 8) & 0xFF)
        handshake[3] = UInt8(hsLen & 0xFF)
        
        // Assemble into record
        packet.append(handshake)
        let recordLen = handshake.count
        packet[3] = UInt8((recordLen >> 8) & 0xFF)
        packet[4] = UInt8(recordLen & 0xFF)
        
        let sni = TLSInspector.extractSNI(from: packet)
        XCTAssertEqual(sni, "reddit.com")
        XCTAssertEqual(TLSInspector.extractHostname(from: packet), "reddit.com")
    }
}
