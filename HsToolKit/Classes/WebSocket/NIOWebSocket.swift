import NIO
import NIOWebSocket
import NIOHTTP1
import NIOSSL
import Foundation
import NIOFoundationCompat

final class NIOWebSocket: INIOWebSocket {
    enum PeerType {
        case server
        case client
    }

    var eventLoop: EventLoop {
        channel.eventLoop
    }

    var isClosed: Bool {
        !channel.isActive
    }
    private(set) var closeCode: WebSocketErrorCode?

    var onClose: EventLoopFuture<Void> {
        channel.closeFuture
    }
    var waitingForClose: Bool

    private let channel: Channel
    private var onTextCallback: (NIOWebSocket, String) -> ()
    private var onBinaryCallback: (NIOWebSocket, ByteBuffer) -> ()
    private var onPongCallback: (NIOWebSocket) -> ()
    private var onPingCallback: (NIOWebSocket) -> ()
    private var onErrorCallback: (NIOWebSocketError) -> ()
    private var frameSequence: WebSocketFrameSequence?
    private let type: PeerType
    private var waitingForPong: Bool
    private var scheduledTimeoutTask: Scheduled<Void>?

    init(channel: Channel, type: PeerType) {
        self.channel = channel
        self.type = type
        onTextCallback = { _, _ in }
        onBinaryCallback = { _, _ in }
        onPongCallback = { _ in }
        onPingCallback = { _ in }
        onErrorCallback = { _ in }
        waitingForPong = false
        waitingForClose = false
        scheduledTimeoutTask = nil
    }

    func onText(_ callback: @escaping (NIOWebSocket, String) -> ()) {
        onTextCallback = callback
    }

    func onBinary(_ callback: @escaping (NIOWebSocket, ByteBuffer) -> ()) {
        onBinaryCallback = callback
    }

    func onPong(_ callback: @escaping (NIOWebSocket) -> ()) {
        onPongCallback = callback
    }

    func onPing(_ callback: @escaping (NIOWebSocket) -> ()) {
        onPingCallback = callback
    }

    func onError(_ callback: @escaping (NIOWebSocketError) -> ()) {
        onErrorCallback = callback
    }

    /// If set, this will trigger automatic pings on the connection. If ping is not answered before
    /// the next ping is sent, then the WebSocket will be presumed inactive and will be closed
    /// automatically.
    /// These pings can also be used to keep the WebSocket alive if there is some other timeout
    /// mechanism shutting down inactive connections, such as a Load Balancer deployed in
    /// front of the server.
    var pingInterval: TimeAmount? {
        didSet {
            if pingInterval != nil {
                if scheduledTimeoutTask == nil {
                    waitingForPong = false
                    pingAndScheduleNextTimeoutTask()
                }
            } else {
                scheduledTimeoutTask?.cancel()
            }
        }
    }

    private func send<S>(_ text: S, promise: EventLoopPromise<Void>? = nil)
            where S: Collection, S.Element == Character
    {
        let string = String(text)
        var buffer = channel.allocator.buffer(capacity: text.count)
        buffer.writeString(string)
        self.send(raw: buffer.readableBytesView, opcode: .text, fin: true, promise: promise)

    }

    private func send(_ binary: [UInt8], promise: EventLoopPromise<Void>? = nil) {
        self.send(raw: binary, opcode: .binary, fin: true, promise: promise)
    }

    private func convertToPromise(completionHandler: ((Error?) -> ())?) -> EventLoopPromise<Void>? {
        completionHandler.flatMap { handler in
            let promise: EventLoopPromise<Void> = channel.eventLoop.makePromise()
            promise.futureResult.whenComplete { result in
                switch result {
                case .success(_): handler(nil)
                case .failure(let error): handler(error)
                }
            }

            return promise
        }
    }

    private func send<Data>(
            raw data: Data,
            opcode: WebSocketOpcode,
            fin: Bool = true,
            promise: EventLoopPromise<Void>? = nil
    )
            where Data: DataProtocol
    {
        var buffer = channel.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)
        let frame = WebSocketFrame(
                fin: fin,
                opcode: opcode,
                maskKey: makeMaskKey(),
                data: buffer
        )

        channel.writeAndFlush(frame, promise: promise)
    }

    func sendPing(promise: EventLoopPromise<Void>? = nil) {
        self.send(
                raw: Data(),
                opcode: .ping,
                fin: true,
                promise: promise
        )
    }

    func send<Data2>(raw data: Data2, opcode: WebSocketOpcode, fin: Bool, completionHandler: ((Error?) -> ())?) where Data2: DataProtocol {
        send(raw: data, opcode: opcode, fin: fin, promise: convertToPromise(completionHandler: completionHandler))
    }

    func close(code: WebSocketErrorCode = .goingAway) -> EventLoopFuture<Void> {
        let promise = eventLoop.makePromise(of: Void.self)
        self.close(code: code, promise: promise)
        return promise.futureResult
    }

    func close(
            code: WebSocketErrorCode = .goingAway,
            promise: EventLoopPromise<Void>?
    ) {
        guard !isClosed else {
            promise?.succeed(())
            return
        }
        guard !waitingForClose else {
            promise?.succeed(())
            return
        }
        waitingForClose = true
        closeCode = code

        let codeAsInt = UInt16(webSocketErrorCode: code)
        let codeToSend: WebSocketErrorCode
        if codeAsInt == 1005 || codeAsInt == 1006 {
            /// Code 1005 and 1006 are used to report errors to the application, but must never be sent over
            /// the wire (per https://tools.ietf.org/html/rfc6455#section-7.4)
            codeToSend = .normalClosure
        } else {
            codeToSend = code
        }

        var buffer = channel.allocator.buffer(capacity: 2)
        buffer.write(webSocketErrorCode: codeToSend)

        self.send(raw: buffer.readableBytesView, opcode: .connectionClose, fin: true, promise: promise)
    }

    func makeMaskKey() -> WebSocketMaskingKey? {
        switch type {
        case .client:
            var bytes: [UInt8] = []
            for _ in 0..<4 {
                bytes.append(.random(in: .min ..< .max))
            }
            return WebSocketMaskingKey(bytes)
        case .server:
            return nil
        }
    }

    func handle(incoming frame: WebSocketFrame) {
        switch frame.opcode {
        case .connectionClose:
            if waitingForClose {
                // peer confirmed close, time to close channel
                channel.close(mode: .output, promise: nil)
            } else {
                // peer asking for close, confirm and close output side channel
                let promise = eventLoop.makePromise(of: Void.self)
                var data = frame.data
                let maskingKey = frame.maskKey
                if let maskingKey = maskingKey {
                    data.webSocketUnmask(maskingKey)
                }
                self.close(
                        code: data.readWebSocketErrorCode() ?? .unknown(1005),
                        promise: promise
                )
                promise.futureResult.whenComplete { _ in
                    self.channel.close(mode: .output, promise: nil)
                }
            }
        case .ping:
            if frame.fin {
                var frameData = frame.data
                let maskingKey = frame.maskKey
                if let maskingKey = maskingKey {
                    frameData.webSocketUnmask(maskingKey)
                }
                self.send(
                        raw: frameData.readableBytesView,
                        opcode: .pong,
                        fin: true,
                        promise: nil
                )
            } else {
                self.close(code: .protocolError, promise: nil)
            }
        case .text, .binary, .pong:
            // create a new frame sequence or use existing
            var frameSequence: WebSocketFrameSequence
            if let existing = self.frameSequence {
                frameSequence = existing
            } else {
                frameSequence = WebSocketFrameSequence(type: frame.opcode)
            }
            // append this frame and update the sequence
            frameSequence.append(frame)
            self.frameSequence = frameSequence
        case .continuation:
            // we must have an existing sequence
            if var frameSequence = self.frameSequence {
                // append this frame and update
                frameSequence.append(frame)
                self.frameSequence = frameSequence
            } else {
                self.close(code: .protocolError, promise: nil)
            }
        default:
            // We ignore all other frames.
            break
        }

        // if this frame was final and we have a non-nil frame sequence,
        // output it to the websocket and clear storage
        if let frameSequence = self.frameSequence, frame.fin {
            switch frameSequence.type {
            case .binary:
                onBinaryCallback(self, frameSequence.binaryBuffer)
            case .text:
                onTextCallback(self, frameSequence.textBuffer)
            case .pong:
                waitingForPong = false
                onPongCallback(self)
            case .ping:
                onPingCallback(self)
            default: break
            }
            self.frameSequence = nil
        }
    }

    private func pingAndScheduleNextTimeoutTask() {
        guard channel.isActive, let pingInterval = pingInterval else {
            return
        }

        if waitingForPong {
            // We never received a pong from our last ping, so the connection has timed out
            let promise = eventLoop.makePromise(of: Void.self)
            self.close(code: .unknown(1006), promise: promise)
            promise.futureResult.whenComplete { _ in
                // Usually, closing a WebSocket is done by sending the close frame and waiting
                // for the peer to respond with their close frame. We are in a timeout situation,
                // so the other side likely will never send the close frame. We just close the
                // channel ourselves.
                self.channel.close(mode: .all, promise: nil)
            }
        } else {
            sendPing()
            waitingForPong = true
            scheduledTimeoutTask = eventLoop.scheduleTask(
                    deadline: .now() + pingInterval,
                    pingAndScheduleNextTimeoutTask
            )
        }
    }
}

extension NIOWebSocket: WebSocketErrorHandlerDelegate {

    func onError(error: NIOWebSocketError) {
        onErrorCallback(error)
    }

}

private struct WebSocketFrameSequence {
    var binaryBuffer: ByteBuffer
    var textBuffer: String
    var type: WebSocketOpcode

    init(type: WebSocketOpcode) {
        binaryBuffer = ByteBufferAllocator().buffer(capacity: 0)
        textBuffer = .init()
        self.type = type
    }

    mutating func append(_ frame: WebSocketFrame) {
        var data = frame.unmaskedData
        switch type {
        case .binary:
            binaryBuffer.writeBuffer(&data)
        case .text:
            if let string = data.readString(length: data.readableBytes) {
                textBuffer += string
            }
        default: break
        }
    }
}

extension NIOWebSocket {

    static func connect(
            to url: String,
            headers: HTTPHeaders = [:],
            configuration: WebSocketClient.Configuration = .init(),
            on eventLoopGroup: EventLoopGroup,
            onUpgrade: @escaping (NIOWebSocket) -> ()
    ) -> EventLoopFuture<Void> {
        guard let url = URL(string: url) else {
            return eventLoopGroup.next().makeFailedFuture(WebSocketClient.Error.invalidURL)
        }
        return self.connect(
                to: url,
                headers: headers,
                configuration: configuration,
                on: eventLoopGroup,
                onUpgrade: onUpgrade
        )
    }

    static func connect(
            to url: URL,
            headers: HTTPHeaders = [:],
            configuration: WebSocketClient.Configuration = .init(),
            on eventLoopGroup: EventLoopGroup,
            onUpgrade: @escaping (NIOWebSocket) -> ()
    ) -> EventLoopFuture<Void> {
        let scheme: String
        switch url.scheme {
        case "wss", "https": scheme = "wss"
        default: scheme = "ws"
        }
        return self.connect(
                scheme: scheme,
                host: url.host ?? "localhost",
                port: url.port ?? (scheme == "wss" ? 443 : 80),
                path: url.path + (url.hasDirectoryPath ? "/" : ""),
                headers: headers,
                configuration: configuration,
                on: eventLoopGroup,
                onUpgrade: onUpgrade
        )
    }

    static func connect(
            scheme: String = "ws",
            host: String,
            port: Int = 80,
            path: String = "/",
            headers: HTTPHeaders = [:],
            configuration: WebSocketClient.Configuration = .init(),
            on eventLoopGroup: EventLoopGroup,
            onUpgrade: @escaping (NIOWebSocket) -> ()
    ) -> EventLoopFuture<Void> {
        WebSocketClient(
                eventLoopGroupProvider: .shared(eventLoopGroup),
                configuration: configuration
        ).connect(
                scheme: scheme,
                host: host,
                port: port,
                path: path,
                headers: headers,
                onUpgrade: onUpgrade
        )
    }
}
