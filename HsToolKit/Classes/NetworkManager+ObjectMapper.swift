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

    public func single<T: ImmutableMappable>(url: URLConvertible, method: HTTPMethod, parameters: Parameters = [:], encoding: ParameterEncoding = URLEncoding.default, headers: HTTPHeaders? = nil, interceptor: RequestInterceptor? = nil, responseCacherBehavior: ResponseCacher.Behavior? = nil) -> Single<T> {
        single(url: url, method: method, parameters: parameters, mapper: ObjectMapper<T>(), encoding: encoding, headers: headers, interceptor: interceptor, responseCacherBehavior: responseCacherBehavior)
    }

    public func single<T: ImmutableMappable>(url: URLConvertible, method: HTTPMethod, parameters: Parameters = [:], encoding: ParameterEncoding = URLEncoding.default, headers: HTTPHeaders? = nil, interceptor: RequestInterceptor? = nil, responseCacherBehavior: ResponseCacher.Behavior? = nil) -> Single<[T]> {
        single(url: url, method: method, parameters: parameters, mapper: ObjectArrayMapper<T>(), encoding: encoding, headers: headers, interceptor: interceptor, responseCacherBehavior: responseCacherBehavior)
    }

    public func single<T: ImmutableMappable>(url: URLConvertible, method: HTTPMethod, parameters: Parameters = [:], encoding: ParameterEncoding = URLEncoding.default, headers: HTTPHeaders? = nil, interceptor: RequestInterceptor? = nil, responseCacherBehavior: ResponseCacher.Behavior? = nil) -> Single<[String: T]> {
        single(url: url, method: method, parameters: parameters, mapper: ObjectDictionaryMapper<T>(), encoding: encoding, headers: headers, interceptor: interceptor, responseCacherBehavior: responseCacherBehavior)
    }

}

extension NetworkManager {

    class ObjectMapper<T: ImmutableMappable>: IApiMapper {

        func map(statusCode: Int, data: Any?) throws -> T {
            guard let data = data else {
                throw RequestError.invalidResponse(statusCode: statusCode, data: data)
            }

            return try T(JSONObject: data)
        }

    }

    class ObjectArrayMapper<T: ImmutableMappable>: IApiMapper {

        func map(statusCode: Int, data: Any?) throws -> [T] {
            guard let data = data else {
                throw RequestError.invalidResponse(statusCode: statusCode, data: data)
            }

            return try Mapper<T>().mapArray(JSONObject: data)
        }

    }

    class ObjectDictionaryMapper<T: ImmutableMappable>: IApiMapper {

        func map(statusCode: Int, data: Any?) throws -> [String: T] {
            guard let data = data else {
                throw RequestError.invalidResponse(statusCode: statusCode, data: data)
            }

            return try Mapper<T>().mapDictionary(JSONObject: data)
        }

    }

    public enum ObjectMapperError: Error {
        case mappingError
    }

}
