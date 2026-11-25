import Darwin
import Foundation
import HoltCore

/// Native-messaging host launched by browsers over stdin/stdout.
/// Protocol: 4-byte native-endian UInt32 length header followed by UTF-8 JSON.
/// Relays valid events as newline-delimited JSON to Holt's Unix domain socket.
enum NativeMessagingHost {
    static func run() {
        let stdinHandle = FileHandle.standardInput
        let stdoutHandle = FileHandle.standardOutput

        while true {
            guard let lengthData = readExact(4, from: stdinHandle), lengthData.count == 4 else {
                break
            }
            let length = lengthData.withUnsafeBytes { ptr -> UInt32 in
                ptr.load(as: UInt32.self)
            }
            guard length > 0, length <= 1_048_576 else {
                writeMessage(#"{"ok":false,"error":"invalid_length"}"#, to: stdoutHandle)
                break
            }
            guard let payload = readExact(Int(length), from: stdinHandle), payload.count == Int(length) else {
                break
            }

            let forwarded = forwardToHoltApp(payload: payload)
            writeMessage(forwarded ? #"{"ok":true}"# : #"{"ok":false}"#, to: stdoutHandle)
        }
    }

    private static func readExact(_ count: Int, from handle: FileHandle) -> Data? {
        var buffer = Data()
        buffer.reserveCapacity(count)
        while buffer.count < count {
            guard let chunk = try? handle.read(upToCount: count - buffer.count), !chunk.isEmpty else {
                return nil
            }
            buffer.append(chunk)
        }
        return buffer
    }

    private static func writeMessage(_ json: String, to handle: FileHandle) {
        guard let body = json.data(using: .utf8) else { return }
        var len = UInt32(body.count)
        let header = Data(bytes: &len, count: MemoryLayout<UInt32>.size)
        try? handle.write(contentsOf: header)
        try? handle.write(contentsOf: body)
    }

    private static func forwardToHoltApp(payload: Data) -> Bool {
        guard let socketURL = try? HoltSocketPaths.socketURL() else { return false }
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { Darwin.close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketURL.path.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else { return false }
        _ = withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dest in
                pathBytes.withUnsafeBufferPointer { src in
                    memcpy(dest, src.baseAddress!, pathBytes.count)
                }
            }
        }

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, addrLen)
            }
        }
        guard connected == 0 else { return false }

        var line = payload
        line.append(0x0A)
        return line.withUnsafeBytes { buf -> Bool in
            guard let base = buf.baseAddress else { return false }
            var sent = 0
            while sent < buf.count {
                let n = Darwin.write(fd, base.advanced(by: sent), buf.count - sent)
                if n <= 0 { return false }
                sent += n
            }
            return true
        }
    }
}

NativeMessagingHost.run()
