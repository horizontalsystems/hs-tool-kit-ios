import RxSwift
import Foundation

public class BackgroundModeObserver {
    public static let shared = BackgroundModeObserver()

    private let foregroundFromExpiredBackgroundSubject = PublishSubject<Void>()
    private var backgroundTask: UIBackgroundTaskIdentifier = UIBackgroundTaskIdentifier.invalid

    init() {
        NotificationCenter.default.addObserver(self, selector: #selector(appCameToBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appCameToForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    @objc private func appCameToBackground() {
        backgroundTask = UIApplication.shared.beginBackgroundTask {
            UIApplication.shared.endBackgroundTask(self.backgroundTask)
            self.backgroundTask = UIBackgroundTaskIdentifier.invalid
        }
    }

    @objc private func appCameToForeground() {
        if backgroundTask != UIBackgroundTaskIdentifier.invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = UIBackgroundTaskIdentifier.invalid
        } else {
            foregroundFromExpiredBackgroundSubject.onNext(())
        }
    }

    public var foregroundFromExpiredBackgroundObservable: Observable<Void> {
        foregroundFromExpiredBackgroundSubject.asObservable()
    }

}
