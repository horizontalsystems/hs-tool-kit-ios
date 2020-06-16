import RxSwift
import Alamofire

public class NetworkManager {
    public let session: Session
    private var logger: Logger?

    public init(logger: Logger? = nil) {
        let networkLogger = NetworkLogger(logger: logger)
        session = Session(eventMonitors: [networkLogger])
        self.logger = logger
    }

    public func single<Mapper: IApiMapper>(request: DataRequest, mapper: Mapper) -> Single<Mapper.T> {
        let serializer = JsonMapperResponseSerializer<Mapper>(mapper: mapper, logger: logger)

        return Single<Mapper.T>.create { observer in
            let requestReference = request.response(queue: DispatchQueue.global(qos: .background), responseSerializer: serializer)
            { response in
                switch response.result {
                case .success(let result):
                    observer(.success(result))
                case .failure(let error):
                    observer(.error(NetworkManager.unwrap(error: error)))
                }
            }

            return Disposables.create {
                requestReference.cancel()
            }
        }
    }

}

extension NetworkManager {

    class NetworkLogger: EventMonitor {
        private var logger: Logger?

        let queue = DispatchQueue(label: "Network Logger", qos: .background)

        init(logger: Logger?) {
            self.logger = logger
        }

        func requestDidResume(_ request: Request) {
            logger?.debug("API OUT: \(request)")
        }

        func requestIsRetrying(_ request: Request) {
            logger?.warning("API RETRY: \(request)")
        }

        func request<Value>(_ request: DataRequest, didParseResponse response: DataResponse<Value, AFError>) {
            switch response.result {
            case .success(let result):
                logger?.debug("API IN: \(request)\n\(result)")
            case .failure(let error):
                logger?.error("API IN: \(request)\n\(NetworkManager.unwrap(error: error))")
            }
        }

    }

}

extension NetworkManager {

    class JsonMapperResponseSerializer<Mapper: IApiMapper>: ResponseSerializer {
        private let mapper: Mapper
        private var logger: Logger?

        private let jsonSerializer = JSONResponseSerializer()

        init(mapper: Mapper, logger: Logger?) {
            self.mapper = mapper
            self.logger = logger
        }

        func serialize(request: URLRequest?, response: HTTPURLResponse?, data: Data?, error: Error?) throws -> Mapper.T {
            guard let response = response else {
                throw RequestError.noResponse(reason: error?.localizedDescription)
            }

            let json = try? jsonSerializer.serialize(request: request, response: response, data: data, error: nil)

            if let json = json {
                logger?.verbose("JSON Response:\n\(json)")
            }

            return try mapper.map(statusCode: response.statusCode, data: json)
        }

    }

}

extension NetworkManager {

    public static func unwrap(error: Error) -> Error {
        if case let AFError.responseSerializationFailed(reason) = error, case let .customSerializationFailed(error) = reason {
            return error
        }

        return error
    }

}

extension NetworkManager {

    public enum RequestError: Error {
        case invalidResponse(statusCode: Int, data: Any?)
        case noResponse(reason: String?)
    }

}

public protocol IApiMapper {
    associatedtype T
    func map(statusCode: Int, data: Any?) throws -> T
}
