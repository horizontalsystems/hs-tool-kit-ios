import NIO
import NIOHTTP1

final class HTTPInitialRequestHandler: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = HTTPClientResponsePart
    typealias OutboundOut = HTTPClientRequestPart

    let host: String
    let path: String
    let headers: HTTPHeaders
    let upgradePromise: EventLoopPromise<Void>

    init(host: String, path: String, headers: HTTPHeaders, upgradePromise: EventLoopPromise<Void>) {
        self.host = host
        self.path = path
        self.headers = headers
        self.upgradePromise = upgradePromise
    }

    func channelActive(context: ChannelHandlerContext) {
        var headers = self.headers
        headers.add(name: "Content-Type", value: "text/plain; charset=utf-8")
        headers.add(name: "Content-Length", value: "\(0)")
        headers.add(name: "Host", value: host)

        let requestHead = HTTPRequestHead(
                version: HTTPVersion(major: 1, minor: 1),
                method: .GET,
                uri: path.hasPrefix("/") ? path : "/" + path,
                headers: headers
        )
        context.write(wrapOutboundOut(.head(requestHead)), promise: nil)

        let emptyBuffer = context.channel.allocator.buffer(capacity: 0)
        let body = HTTPClientRequestPart.body(.byteBuffer(emptyBuffer))
        context.write(wrapOutboundOut(body), promise: nil)

        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let clientResponse = unwrapInboundIn(data)
        switch clientResponse {
        case .head(let responseHead):
            upgradePromise.fail(WebSocketClient.Error.invalidResponseStatus(responseHead))
        case .body: break
        case .end:
            context.close(promise: nil)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        upgradePromise.fail(error)
        context.close(promise: nil)
    }
}
