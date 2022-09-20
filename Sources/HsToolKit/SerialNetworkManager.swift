import Foundation
import Alamofire
import RxSwift

public class SerialNetworkManager {
    private let networkManager: NetworkManager
    private let scheduler: DelayScheduler
    private let logger: Logger
    
    public var session: Session {
        networkManager.session
    }
    
    public init(requestInterval: TimeInterval, logger: Logger) {
        networkManager = NetworkManager(logger: logger)
        scheduler = DelayScheduler(delay: requestInterval, queue: .global(qos: .utility))
        self.logger = logger
    }
    
    public func single<Mapper: IApiMapper>(request: DataRequest, mapper: Mapper) -> Single<Mapper.T> {
        networkManager.single(request: request, mapper: mapper)
            .subscribeOn(scheduler)
    }
    
    public func single<Mapper: IApiMapper>(url: URLConvertible, method: HTTPMethod, parameters: Parameters, mapper: Mapper, encoding: ParameterEncoding = URLEncoding.default,
                                    headers: HTTPHeaders? = nil, interceptor: RequestInterceptor? = nil, responseCacherBehavior: ResponseCacher.Behavior? = nil) -> Single<Mapper.T> {
        networkManager.single(url: url, method: method, parameters: parameters, mapper: mapper, encoding: encoding, headers: headers, interceptor: interceptor, responseCacherBehavior: responseCacherBehavior)
            .subscribeOn(scheduler)
    }
    
}

class DelayScheduler: ImmediateSchedulerType {
    private var lastDispatch: DispatchTime = .now()
    private let queue: DispatchQueue
    private let dispatchDelay: TimeInterval
    
    init(delay: TimeInterval, queue: DispatchQueue = .main) {
        self.queue = queue
        dispatchDelay = delay
    }
    
    func schedule<StateType>(_ state: StateType, action: @escaping (StateType) -> Disposable) -> Disposable {
        let cancel = SingleAssignmentDisposable()
        lastDispatch = max(lastDispatch + dispatchDelay, .now())
        queue.asyncAfter(deadline: lastDispatch) {
            guard cancel.isDisposed == false else { return }
            cancel.setDisposable(action(state))
        }
        return cancel
    }
    
}

