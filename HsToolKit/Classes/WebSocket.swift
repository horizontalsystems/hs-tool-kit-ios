import Foundation
import RxSwift
import HsToolKit

public class WebSocket: NSObject {
    public weak var delegate: IWebSocketDelegate?

    private var disposeBag = DisposeBag()
    private var logger: Logger?
    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var request: URLRequest
    private var isStarted = false

    private let queue = DispatchQueue(label: "websocket-delegate-queue", qos: .background)
    private let url: URL
    private let reachabilityManager: IReachabilityManager

    public var state: WebSocketState = .disconnected(error: WebSocketState.DisconnectError.notStarted) {
        didSet {
            queue.async { [weak self] in
                self.flatMap { $0.delegate?.didUpdate(state: $0.state) }
            }
        }
    }

    public init(url: URL, reachabilityManager: IReachabilityManager, auth: String?, sessionRequestTimeout: TimeInterval = 20, logger: Logger? = nil) {
        self.url = url
        self.reachabilityManager = reachabilityManager
        self.logger = logger

        request = URLRequest(url: url)
        request.timeoutInterval = sessionRequestTimeout
        request.setValue(nil, forHTTPHeaderField: "Origin")

        if let auth = auth {
            let basicAuth = Data(":\(auth)".utf8).base64EncodedString()
            request.setValue("Basic \(basicAuth)", forHTTPHeaderField: "Authorization")
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.shouldUseExtendedBackgroundIdleMode = false
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 5

        super.init()

        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)

        reachabilityManager.reachabilityObservable
                .observeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
                .subscribe(onNext: { [weak self] _ in
                    if reachabilityManager.isReachable {
                        self?.reconnect()
                    } else {
                        self?.state = .disconnected(error: WebSocketState.DisconnectError.socketDisconnected(reason: "Network not reachable"))
                    }
                })
                .disposed(by: disposeBag)

        reachabilityManager.connectionTypeUpdatedObservable
                .observeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
                .subscribe(onNext: { [weak self] _ in
                    guard case .connected = self?.state else {
                        return
                    }

                    self?.state = .disconnected(error: WebSocketState.DisconnectError.socketDisconnected(reason: "Network not reachable"))
                    self?.reconnect()
                })
                .disposed(by: disposeBag)
    }

    private func connect() {
        guard case .disconnected = state else {
            return
        }
        state = .connecting

        task = session?.webSocketTask(with: request)
        doRead()
        logger?.debug("Connecting to \(url)")
        task?.resume()
    }

    private func reconnect() {
        guard isStarted else {
            return
        }

        logger?.debug("Reconnecting to \(url)")

        if let task = task {
            task.cancel(with: .normalClosure, reason: nil)
        }

        connect()
    }

    private func handleMessage(result: Result<URLSessionWebSocketTask.Message, Error>) {
        switch result {
        case .success(let message):
            switch message {
            case .string(let text):
                logger?.debug("WebSocket Received text: \(text)")
                delegate?.didReceive(text: text)
            case .data(let data):
                logger?.debug("WebSocket Received data: \(data.count)")
            @unknown default:
                break
            }
            break
        case .failure(let error):
            logger?.debug("WebSocket Received error: \(error)")
            let previousState = state
            state = .disconnected(error: error)

            if case .connected = previousState {
                reconnect()
            }

            return
        }

        doRead()
    }

    private func doRead() {
        task?.receive { [weak self] result in
            self?.handleMessage(result: result)
        }
    }

}

extension WebSocket: URLSessionWebSocketDelegate {

    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        let p = `protocol` ?? ""
        logger?.debug("WebSocket is connected: \(p)")

        state = .connected
    }

    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        var errorString = "Unknown error"
        if let d = reason {
            errorString = String(data: d, encoding: .utf8) ?? "Unknown error"
        }

        logger?.debug("WebSocket is closed by server: \(errorString)")
        state = .disconnected(error: WebSocketState.DisconnectError.socketDisconnected(reason: errorString))
    }

}

extension WebSocket: URLSessionTaskDelegate {
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        logger?.debug("didCompleteWithError \(error)")
    }

    public func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        logger?.debug("didBecomeInvalidWithError \(error)")
    }
}

extension WebSocket: IWebSocket {

    public var source: String {
        url.host ?? ""
    }

    public func start() {
        isStarted = true
        connect()
    }

    public func stop() {
        isStarted = false
        task?.cancel(with: .goingAway, reason: nil)
        state = .disconnected(error: WebSocketState.DisconnectError.notStarted)
    }

    public func send(data: Data, completionHandler: ((Error?) -> ())?) throws {
        guard case .connected = state else {
            throw WebSocketState.StateError.notConnected
        }

        task?.send(.data(data), completionHandler: completionHandler ?? { [weak self] error in
            if let error = error {
                self?.logger?.error("Error sending data: \(error.localizedDescription)")
            }
        })
    }

    public func send(ping: Data) throws {
        guard case .connected = state else {
            throw WebSocketState.StateError.notConnected
        }

        task?.sendPing(pongReceiveHandler: { [weak self] error in
            if let error = error {
                self?.logger?.error("Error sending ping: \(error.localizedDescription)")
            }
        })
    }

    public func send(pong: Data) throws {
        // URLSessionWebSocketTask has no method to send "pong" message
    }

}


public enum WebSocketState {
    case connecting
    case connected
    case disconnected(error: Error)

    public enum DisconnectError: Error {
        case notStarted
        case socketDisconnected(reason: String)
    }

    public enum StateError: Error {
        case notConnected
    }

}

public protocol IWebSocket: AnyObject {
    var delegate: IWebSocketDelegate? { get set }
    var source: String { get }

    func start()
    func stop()

    func send(data: Data, completionHandler: ((Error?) -> ())?) throws
    func send(ping: Data) throws
    func send(pong: Data) throws
}

public protocol IWebSocketDelegate: AnyObject {
    func didUpdate(state: WebSocketState)
    func didReceive(text: String)
    func didReceive(data: Data)
}
