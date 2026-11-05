import Foundation

// The CLI talks to the app over a unix socket at $TMPDIR/kex.sock (the per-user temp dir, the same
// for the app and a shell). One request per connection: the client writes a command line ending in
// "\n"; the app answers "ok\n" or "error\n" followed by the reply text, then closes the connection.

let socketPath = (NSTemporaryDirectory() as NSString).appendingPathComponent("kex.sock")

/// Listens on `socketPath` and answers each request with `handle`, which runs on the main queue.
/// Nil if the socket can't be set up. A stale socket file from a kex that did not quit cleanly is replaced.
final class SocketServer {
    private let source: DispatchSourceRead
    private let queue = DispatchQueue(label: "kex.socket")

    init?(handle: @escaping (String) -> Reply) {
        // A client that hangs up before the reply must fail the write, not kill the app.
        signal(SIGPIPE, SIG_IGN)
        unlink(socketPath)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0, withAddress(socketPath, { Darwin.bind(fd, $0, $1) }) == 0, listen(fd, 8) == 0 else {
            fputs("socket: can't listen on \(socketPath): \(String(cString: strerror(errno)))\n", stderr)
            if fd >= 0 { close(fd) }
            return nil
        }
        source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler {
            let client = accept(fd, nil, nil)
            guard client >= 0 else { return }
            var timeout = timeval(tv_sec: 2, tv_usec: 0)
            setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            let line = readAll(client, untilNewline: true).trimmingCharacters(in: .whitespacesAndNewlines)
            let reply = DispatchQueue.main.sync { handle(line) }
            writeAll(client, (reply.ok ? "ok\n" : "error\n") + reply.text)
            close(client)
        }
        source.setCancelHandler {
            close(fd)
            unlink(socketPath)
        }
        source.resume()
    }

    func stop() { source.cancel() }
}

/// True if a kex app answers on the socket.
func appIsRunning() -> Bool {
    guard let fd = connectSocket() else { return false }
    close(fd)
    return true
}

/// Sends one command line to the app. Nil if nothing is listening.
func sendToApp(_ line: String) -> Reply? {
    guard let fd = connectSocket() else { return nil }
    defer { close(fd) }
    signal(SIGPIPE, SIG_IGN)
    writeAll(fd, line + "\n")
    shutdown(fd, SHUT_WR)
    let response = readAll(fd, untilNewline: false)
    guard let newline = response.firstIndex(of: "\n") else { return .error("no reply from the app") }
    return Reply(ok: response[..<newline] == "ok", text: String(response[response.index(after: newline)...]))
}

private func connectSocket() -> Int32? {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return nil }
    guard withAddress(socketPath, { connect(fd, $0, $1) }) == 0 else {
        close(fd)
        return nil
    }
    return fd
}

private func withAddress(_ path: String, _ body: (UnsafePointer<sockaddr>, socklen_t) -> Int32) -> Int32 {
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutableBytes(of: &addr.sun_path) { buffer in
        buffer.copyBytes(from: path.utf8.prefix(buffer.count - 1))
    }
    return withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
}

private func readAll(_ fd: Int32, untilNewline: Bool) -> String {
    var data = [UInt8]()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while data.count < 1 << 20 {
        let n = read(fd, &buffer, buffer.count)
        guard n > 0 else { break }
        data += buffer[..<n]
        if untilNewline, buffer[..<n].contains(UInt8(ascii: "\n")) { break }
    }
    return String(decoding: data, as: UTF8.self)
}

private func writeAll(_ fd: Int32, _ string: String) {
    var bytes = Array(string.utf8)[...]
    while !bytes.isEmpty {
        let n = bytes.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        guard n > 0 else { return }
        bytes = bytes.dropFirst(n)
    }
}
