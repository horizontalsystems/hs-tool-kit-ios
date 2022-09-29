import Foundation

public protocol ILogStorage {
    func log(date: Date, level: Logger.Level, message: String, file: String?, function: String?, line: Int?, context: [String]?)
}

public class Logger {

    public enum Level: Int {
        case verbose = 0
        case debug = 1
        case info = 2
        case warning = 3
        case error = 4
    }

    private let colors: [Level: String] = [
        Level.verbose: "💜 VERBOSE ",     // silver
        Level.debug:   "💚 DEBUG ",       // green
        Level.info:    "💙 INFO ",        // blue
        Level.warning: "💛 WARNING ",     // yellow
        Level.error:   "❤️ ERROR "        // red
    ]

    private lazy var dateFormatter: DateFormatter = {
        var formatter = DateFormatter()
        formatter.timeZone = TimeZone.autoupdatingCurrent
        formatter.locale = Locale.current
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    private let minLogLevel: Level
    private let storage: ILogStorage?
    private let scope: String?
    private let delegate: Logger?

    public init(minLogLevel: Level, storage: ILogStorage? = nil) {
        self.minLogLevel = minLogLevel
        self.storage = storage
        self.scope = nil
        self.delegate = nil
    }

    fileprivate init(minLogLevel: Level, scope: String, delegate: Logger) {
        self.minLogLevel = minLogLevel
        self.storage = nil
        self.scope = scope
        self.delegate = delegate
    }

    public func scoped(with scope: String) -> Logger {
        Logger(minLogLevel: self.minLogLevel, scope: scope, delegate: self)
    }

    /// log something generally unimportant (lowest priority)
    public func verbose(_ message: @autoclosure () -> Any,
                        _ file: String? = nil, _ function: String? = nil, line: Int? = nil, context: [String]? = nil, save: Bool = false) {
        log(level: .verbose, message: message(), file: file, function: function, line: line, context: context, save: save)
    }

    /// log something which help during debugging (low priority)
    public func debug(_ message: @autoclosure () -> Any,
                      _ file: String? = nil, _ function: String? = nil, line: Int? = nil, context: [String]? = nil, save: Bool = false) {
        log(level: .debug, message: message(), file: file, function: function, line: line, context: context, save: save)
    }

    /// log something which you are really interested but which is not an issue or error (normal priority)
    public func info(_ message: @autoclosure () -> Any,
                     _ file: String? = nil, _ function: String? = nil, line: Int? = nil, context: [String]? = nil, save: Bool = false) {
        log(level: .info, message: message(), file: file, function: function, line: line, context: context, save: save)
    }

    /// log something which may cause big trouble soon (high priority)
    public func warning(_ message: @autoclosure () -> Any,
                        _ file: String? = nil, _ function: String? = nil, line: Int? = nil, context: [String]? = nil, save: Bool = false) {
        log(level: .warning, message: message(), file: file, function: function, line: line, context: context, save: save)
    }

    /// log something which will keep you awake at night (highest priority)
    public func error(_ message: @autoclosure () -> Any,
                      _ file: String? = nil, _ function: String? = nil, line: Int? = nil, context: [String]? = nil, save: Bool = false) {
        log(level: .error, message: message(), file: file, function: function, line: line, context: context, save: save)
    }

    /// custom logging to manually adjust values, should just be used by other frameworks
    public func log(level: Logger.Level, message: @autoclosure () -> Any,
                    file: String? = nil, function: String? = nil, line: Int? = nil, context: [String]? = nil, save: Bool = false) {

        if let delegate = delegate {
            var scopedContext = context ?? [String]()
            if let scope = scope {
                scopedContext.insert(scope, at: 0)
            }

            let resolvedMessage = message()
            delegate.log(level: level, message: resolvedMessage, file: file, function: function, line: line, context: scopedContext, save: save)
            return
        }

        if let storage = storage, save {
            storage.log(date: Date(), level: level, message: "\(message())", file: file, function: function, line: line, context: context)
        }

        guard level.rawValue >= minLogLevel.rawValue else {
            return
        }

        var str = "\(dateFormatter.string(from: Date())) \(colors[level]!)"

        if let file = file {
            str = str + " \(fileNameWithoutSuffix(file)) "

            if let function = function {
                str = str + " \(function) "
            }

            if let line = line {
                str = str + " \(line) "
            }
        }

        if let context = context {
            str = str + " \(context.joined(separator: " "))"
        }

        str = str + ": \(message())"

        print(str)
    }

    private func functionName(_ function: String) -> String {
        if let index = function.firstIndex(of: "(") {
            return String(function.prefix(index.utf16Offset(in: function)))
        } else {
            return function
        }
    }

    // returns the current thread name
    private func threadName() -> String {
        if Thread.isMainThread {
            return ""
        } else {
            let threadName = Thread.current.name
            if let threadName = threadName, !threadName.isEmpty {
                return threadName
            } else {
                return String(format: "%p", Thread.current)
            }
        }
    }

    // returns the filename without suffix (= file ending) of a path
    private func fileNameWithoutSuffix(_ file: String) -> String {
        let fileName = fileNameOfFile(file)

        if !fileName.isEmpty {
            let fileNameParts = fileName.components(separatedBy: ".")
            if let firstPart = fileNameParts.first {
                return firstPart
            }
        }
        return ""
    }

    // returns the filename of a path
    private func fileNameOfFile(_ file: String) -> String {
        let fileParts = file.components(separatedBy: "/")
        if let lastPart = fileParts.last {
            return lastPart
        }
        return ""
    }

}
