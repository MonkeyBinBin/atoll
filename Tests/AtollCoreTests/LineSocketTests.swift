import Foundation
import Testing
@testable import AtollCore

/// A listening Unix socket in the temporary directory (paths must stay under ~104 bytes).
private final class UnixServer {
    let path: String
    private let fd: Int32

    init() throws {
        path = FileManager.default.temporaryDirectory.appendingPathComponent("ls-\(Int.random(in: 1000...9999)).sock").path
        unlink(path)
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxLength = MemoryLayout.size(ofValue: addr.sun_path)
        withUnsafeMutablePointer(to: &addr.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: maxLength) { _ = strncpy($0, path, maxLength) }
        }
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, listen(fd, 1) == 0 else { throw HerdrError.unavailable("bind/listen failed") }
    }

    /// The server end of the next connection.
    func accept() -> Int32 { Darwin.accept(fd, nil, nil) }

    deinit {
        Darwin.close(fd)
        unlink(path)
    }
}

/// Runs `body` on its own thread; nil if it didn't finish within `timeout`.
private func onThread<T: Sendable>(timeout: TimeInterval, _ body: @escaping @Sendable () -> T) -> T? {
    let result = Locked<T?>(nil)
    let done = DispatchSemaphore(value: 0)
    Thread {
        result.value = body()
        done.signal()
    }.start()
    guard done.wait(timeout: .now() + timeout) == .success else { return nil }
    return result.value
}

@Suite("LineSocket", .serialized)
struct LineSocketTests {
    @Test("shutdown() from another thread ends a blocked readLine() with nil")
    func shutdownUnblocksRead() throws {
        let server = try UnixServer()
        let socket = try LineSocket(path: server.path)
        let peer = server.accept()
        defer { Darwin.close(peer) }
        let started = DispatchSemaphore(value: 0)
        let read = Locked<Data??>(nil)
        let done = DispatchSemaphore(value: 0)
        Thread {
            started.signal()
            read.value = .some(socket.readLine())
            done.signal()
        }.start()
        started.wait()
        Thread.sleep(forTimeInterval: 0.1)
        socket.shutdown()
        #expect(done.wait(timeout: .now() + 2) == .success)
        #expect(read.value == .some(nil))
        socket.close()
        socket.close()
    }

    @Test("lines split across reads come out whole, one per call")
    func splitLines() throws {
        let server = try UnixServer()
        let socket = try LineSocket(path: server.path)
        let peer = server.accept()
        defer {
            Darwin.close(peer)
            socket.close()
        }
        func send(_ text: String) {
            _ = text.utf8CString.withUnsafeBufferPointer { write(peer, $0.baseAddress, $0.count - 1) }
        }
        send("one\ntw")
        #expect(onThread(timeout: 2) { socket.readLine() } == Data("one".utf8))
        send("o\nthree\n")
        #expect(onThread(timeout: 2) { socket.readLine() } == Data("two".utf8))
        #expect(onThread(timeout: 2) { socket.readLine() } == Data("three".utf8))
        Darwin.shutdown(peer, SHUT_WR)
        #expect(onThread(timeout: 2) { socket.readLine() } == .some(nil))
    }
}
