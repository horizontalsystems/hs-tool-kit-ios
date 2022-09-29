import NIO
import NIOWebSocket

extension NIOWebSocket {
    static func client(
            on channel: Channel,
            onUpgrade: @escaping (NIOWebSocket) -> ()
    ) -> EventLoopFuture<Void> {
        handle(on: channel, as: .client, onUpgrade: onUpgrade)
    }

    static func server(
            on channel: Channel,
            onUpgrade: @escaping (NIOWebSocket) -> ()
    ) -> EventLoopFuture<Void> {
        handle(on: channel, as: .server, onUpgrade: onUpgrade)
    }

    private static func handle(
            on channel: Channel,
            as type: PeerType,
            onUpgrade: @escaping (NIOWebSocket) -> ()
    ) -> EventLoopFuture<Void> {
        let webSocket = NIOWebSocket(channel: channel, type: type)
        channel.pipeline.addHandler(WebSocketErrorHandler(delegate: webSocket))

        return channel.pipeline.addHandler(WebSocketHandler(webSocket: webSocket)).map { _ in
            onUpgrade(webSocket)
        }
    }
}

extension WebSocketErrorCode {
    init(_ error: NIOWebSocketError) {
        switch error {
        case .invalidFrameLength:
            self = .messageTooLarge
        case .fragmentedControlFrame,
             .multiByteControlFrameLength:
            self = .protocolError
        }
    }
}

private final class WebSocketHandler: ChannelInboundHandler {
    typealias InboundIn = WebSocketFrame
    typealias OutboundOut = WebSocketFrame
    private var webSocket: NIOWebSocket

    init(webSocket: NIOWebSocket) {
        self.webSocket = webSocket
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)
        webSocket.handle(incoming: frame)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        let errorCode: WebSocketErrorCode
        if let error = error as? NIOWebSocketError {
            errorCode = WebSocketErrorCode(error)
        } else {
            errorCode = .unexpectedServerError
        }
        _ = webSocket.close(code: errorCode)

        // We always forward the error on to let others see it.
        context.fireErrorCaught(error)
    }

    func channelInactive(context: ChannelHandlerContext) {
        let closedAbnormally = WebSocketErrorCode.unknown(1006)
        _ = webSocket.close(code: closedAbnormally)

        // We always forward the error on to let others see it.
        context.fireChannelInactive()
    }
}
