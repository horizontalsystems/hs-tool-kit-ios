import Alamofire
import ObjectMapper
import RxSwift

extension NetworkManager {

    public func single<T: ImmutableMappable>(request: DataRequest) -> Single<T> {
        single(request: request, mapper: ObjectMapper<T>())
    }

    public func single<T: ImmutableMappable>(request: DataRequest) -> Single<[T]> {
        single(request: request, mapper: ObjectArrayMapper<T>())
    }

}

extension NetworkManager {

    class ObjectMapper<T: ImmutableMappable>: IApiMapper {

        func map(statusCode: Int, data: Any?) throws -> T {
            guard let jsonObject = data as? [String: Any] else {
                throw RequestError.invalidResponse(statusCode: statusCode, data: data)
            }

            return try T(JSONObject: jsonObject)
        }

    }

    class ObjectArrayMapper<T: ImmutableMappable>: IApiMapper {

        func map(statusCode: Int, data: Any?) throws -> [T] {
            guard let jsonArray = data as? [[String: Any]] else {
                throw RequestError.invalidResponse(statusCode: statusCode, data: data)
            }

            return try jsonArray.map { try T(JSONObject: $0) }
        }

    }

    public enum ObjectMapperError: Error {
        case mappingError
    }

}
