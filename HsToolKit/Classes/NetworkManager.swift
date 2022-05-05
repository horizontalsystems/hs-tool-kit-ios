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

    public func single<Mapper: IApiMapper>(url: URLConvertible, method: HTTPMethod, parameters: Parameters, mapper: Mapper, encoding: ParameterEncoding = URLEncoding.default,
                                           headers: HTTPHeaders? = nil, interceptor: RequestInterceptor? = nil, responseCacherBehavior: ResponseCacher.Behavior? = nil) -> Single<Mapper.T> {
        let serializer = JsonMapperResponseSerializer<Mapper>(mapper: mapper, logger: logger)

        return Single<Mapper.T>.create { [weak self] observer in
            guard let manager = self else {
                observer(.error(NetworkManager.RequestError.disposed))
                return Disposables.create()
            }

            var request = manager
                    .session
                    .request(url, method: method, parameters: parameters, encoding: encoding, headers: headers, interceptor: interceptor)
                    .validate(statusCode: 200..<400)
                    .validate(contentType: ["application/json"])

            if let behavior = responseCacherBehavior {
                request = request.cacheResponse(using: ResponseCacher(behavior: behavior))
            }

            let requestReference = request.response(queue: DispatchQueue.global(qos: .background), responseSerializer: serializer) { response in
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
            var parametersLog = ""

            if let httpBody = request.request?.httpBody, let json = try? JSONSerialization.jsonObject(with: httpBody), let data = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys, .prettyPrinted]), let string = String(data: data, encoding: .utf8) {
                parametersLog = "\n\(string)"
            }

            logger?.debug("API OUT [\(request.id)]\n\(request)\(parametersLog)\n")
        }

        func requestIsRetrying(_ request: Request) {
            logger?.warning("API RETRY: \(request.id)")
        }

        func request<Value>(_ request: DataRequest, didParseResponse response: DataResponse<Value, AFError>) {
            switch response.result {
            case .success(let result):
                logger?.debug("API IN [\(request.id)]\n\(result)\n")
            case .failure(let error):
                logger?.error("API IN [\(request.id)]\n\(NetworkManager.unwrap(error: error))\n")
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
            if let error = error as? AFError {
                // Handle failure Http status codes
                // By default handle only wrong status code, otherwise fallback to 400 'Bad request' code
                if case let .responseValidationFailed(reason) = error,
                   case let .unacceptableStatusCode(code) = reason {
                    throw RequestError.invalidResponse(statusCode: code, data: data)
                } else {
                    throw error
                }
            }
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
        case disposed
    }

}

public protocol IApiMapper {
    associatedtype T
    func map(statusCode: Int, data: Any?) throws -> T
}
