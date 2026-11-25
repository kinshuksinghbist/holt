import Darwin
import Foundation
import HoltCore

/// Listens on `~/Library/Application Support/Holt/holt.sock` for JSON events relayed by `holt-nm-host`.
final class NativeMessagingServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "holt.nm.socket", qos: .utility)
    private var serverFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private let onEvent: @MainActor @Sendable (BrowserTabEvent) -> Void

    init(onEvent: @escaping @MainActor @Sendable (BrowserTabEvent) -> Void) {
        self.onEvent = onEvent
    }

    func start() {
        queue.async { [weak self] in
            self?.startListening()
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.acceptSource?.cancel()
            self?.acceptSource = nil
            if let fd = self?.serverFD, fd >= 0 {
                Darwin.close(fd)
                self?.serverFD = -1
            }
        }
    }

    private func startListening() {
        guard serverFD < 0, let socketURL = try? HoltSocketPaths.socketURL() else { return }
        unlink(socketURL.path)

        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketURL.path.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            Darwin.close(fd)
            return
        }
        _ = withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dest in
                pathBytes.withUnsafeBufferPointer { src in
                    memcpy(dest, src.baseAddress!, pathBytes.count)
                }
            }
        }

        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.bind(fd, sockPtr, len)
            }
        }
        guard bound == 0, Darwin.listen(fd, 16) == 0 else {
            Darwin.close(fd)
            return
        }
        chmod(socketURL.path, 0o600)
        serverFD = fd

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let client = Darwin.accept(fd, nil, nil)
            guard client >= 0 else { return }
            self.handleClient(fd: client)
        }
        source.resume()
        acceptSource = source
    }

    private func handleClient(fd: Int32) {
        defer { Darwin.close(fd) }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = Darwin.read(fd, &buffer, buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
            if data.count > 262_144 { break }
        }
        guard let text = String(data: data, encoding: .utf8) else { return }
        for line in text.split(separator: "\n") {
            guard let lineData = line.data(using: .utf8),
                  let event = try? JSONDecoder().decode(BrowserTabEvent.self, from: lineData) else {
                continue
            }
            let callback = onEvent
            Task { @MainActor in
                callback(event)
            }
        }
    }
}
