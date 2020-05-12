import Alamofire
import RxSwift

public protocol IReachabilityManager {
    var isReachable: Bool { get }
    var reachabilityObservable: Observable<Bool> { get }
}

public class ReachabilityManager {
    private let manager: NetworkReachabilityManager?

    private(set) public var isReachable: Bool
    private let reachabilitySubject = PublishSubject<Bool>()

    public init() {
        manager = NetworkReachabilityManager()

        isReachable = manager?.isReachable ?? false

        manager?.startListening { [weak self] _ in
            self?.onUpdateStatus()
        }
    }

    private func onUpdateStatus() {
        let newReachable = manager?.isReachable ?? false

        if isReachable != newReachable {
            isReachable = newReachable
            reachabilitySubject.onNext(newReachable)
        }
    }

}

extension ReachabilityManager: IReachabilityManager {

    public var reachabilityObservable: Observable<Bool> {
        reachabilitySubject.asObservable()
    }

}

extension ReachabilityManager {

    public enum ReachabilityError: Error {
        case notReachable
    }

}
