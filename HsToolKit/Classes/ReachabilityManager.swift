import Alamofire
import RxSwift

public protocol IReachabilityManager {
    var isReachable: Bool { get }
    var reachabilityObservable: Observable<Bool> { get }
    var connectionTypeUpdatedObservable: Observable<Void> { get }
}

public class ReachabilityManager {
    private let manager: NetworkReachabilityManager?

    private(set) public var isReachable: Bool
    private(set) public var connectionType: NetworkReachabilityManager.NetworkReachabilityStatus.ConnectionType?
    private let reachabilitySubject = PublishSubject<Bool>()
    private let connectionTypeUpdatedSubject = PublishSubject<Void>()

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

        if let status = manager?.status, case .reachable(let connectionType) = status, self.connectionType != connectionType {
            self.connectionType = connectionType
            connectionTypeUpdatedSubject.onNext(())
        }
    }

}

extension ReachabilityManager: IReachabilityManager {

    public var reachabilityObservable: Observable<Bool> {
        reachabilitySubject.asObservable()
    }

    public var connectionTypeUpdatedObservable: Observable<Void> {
        connectionTypeUpdatedSubject.asObservable()
    }

}

extension ReachabilityManager {

    public enum ReachabilityError: Error {
        case notReachable
    }

}
