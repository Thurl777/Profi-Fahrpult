import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Schlanker UDP-Socket auf Basis von BSD-Sockets + GCD.
/// Bewusst ohne Network.framework, damit die App auch auf älteren iOS-Versionen läuft.
final class UDPSocket {

    enum SocketError: Error, CustomStringConvertible {
        case createFailed(Int32)
        case invalidAddress(String)
        case bindFailed(Int32)

        var description: String {
            switch self {
            case .createFailed(let e): return "Socket konnte nicht erstellt werden (\(e))"
            case .invalidAddress(let a): return "Ungültige IP-Adresse: \(a)"
            case .bindFailed(let e): return "Socket konnte nicht gebunden werden (\(e))"
            }
        }
    }

    /// Wird auf `callbackQueue` aufgerufen
    var onReceive: ((Data) -> Void)?

    private let callbackQueue: DispatchQueue
    private let ioQueue = DispatchQueue(label: "de.profifahrpult.udp")
    private var fd: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var remote = sockaddr_in()

    init(callbackQueue: DispatchQueue = .main) {
        self.callbackQueue = callbackQueue
    }

    deinit {
        close()
    }

    var isOpen: Bool { return fd >= 0 }

    func open(host: String, port: UInt16) throws {
        close()

        var addr = sockaddr_in()
        #if canImport(Darwin)
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        #endif
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &addr.sin_addr) == 1 else {
            throw SocketError.invalidAddress(host)
        }

        #if canImport(Darwin)
        let s = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        #else
        let s = socket(AF_INET, Int32(SOCK_DGRAM.rawValue), Int32(IPPROTO_UDP))
        #endif
        guard s >= 0 else { throw SocketError.createFailed(errno) }

        // An beliebigen lokalen Port binden; die Z21 antwortet an Absender-IP und -Port.
        var local = sockaddr_in()
        #if canImport(Darwin)
        local.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        #endif
        local.sin_family = sa_family_t(AF_INET)
        local.sin_port = 0
        local.sin_addr.s_addr = INADDR_ANY
        let bindResult = withUnsafePointer(to: &local) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                bind(s, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            let e = errno
            _ = closeFD(s)
            throw SocketError.bindFailed(e)
        }

        #if canImport(Darwin)
        var noSigPipe: Int32 = 1
        setsockopt(s, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        #endif

        let flags = fcntl(s, F_GETFL, 0)
        _ = fcntl(s, F_SETFL, flags | O_NONBLOCK)

        fd = s
        remote = addr

        let source = DispatchSource.makeReadSource(fileDescriptor: s, queue: ioQueue)
        source.setEventHandler { [weak self] in
            self?.readAvailable(fd: s)
        }
        source.setCancelHandler {
            _ = UDPSocket.closeFD(s)
        }
        readSource = source
        source.resume()
    }

    func close() {
        if let source = readSource {
            source.cancel()   // schließt den Deskriptor im Cancel-Handler
            readSource = nil
        } else if fd >= 0 {
            _ = UDPSocket.closeFD(fd)
        }
        fd = -1
    }

    @discardableResult
    func send(_ data: Data) -> Bool {
        guard fd >= 0 else { return false }
        let s = fd
        var addr = remote
        let sent: Int = data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Int in
            withUnsafePointer(to: &addr) { ptr -> Int in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa -> Int in
                    sendto(s, raw.baseAddress, raw.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        return sent == data.count
    }

    private func readAvailable(fd s: Int32) {
        var buffer = [UInt8](repeating: 0, count: 2048)
        while true {
            let n = buffer.withUnsafeMutableBytes { raw -> Int in
                recv(s, raw.baseAddress, raw.count, 0)
            }
            if n <= 0 { break }
            let data = Data(buffer[0..<n])
            callbackQueue.async { [weak self] in
                self?.onReceive?(data)
            }
        }
    }

    @discardableResult
    private static func closeFD(_ s: Int32) -> Int32 {
        #if canImport(Darwin)
        return Darwin.close(s)
        #else
        return Glibc.close(s)
        #endif
    }

    private func closeFD(_ s: Int32) -> Int32 {
        return UDPSocket.closeFD(s)
    }
}
