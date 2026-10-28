import Foundation

enum RequestPolicy {
    static func userMessage(for error: Error) -> String {
        let value = error as NSError
        guard value.domain == NSURLErrorDomain else { return error.localizedDescription }
        switch value.code {
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
            return "当前没有网络连接，请检查 Wi-Fi 或蜂窝网络后重试。"
        case NSURLErrorTimedOut:
            return "连接汽水服务超时，请检查网络后重试。"
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
            return "无法连接汽水服务，请检查网络或稍后重试。"
        case NSURLErrorCannotConnectToHost:
            return "暂时无法连接汽水服务，请稍后重试。"
        default:
            return error.localizedDescription
        }
    }

    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let value = error as NSError
        if value.domain == NSURLErrorDomain && value.code == NSURLErrorCancelled { return true }
        if let underlying = value.userInfo[NSUnderlyingErrorKey] as? Error {
            let nested = underlying as NSError
            return nested.domain == NSURLErrorDomain && nested.code == NSURLErrorCancelled
        }
        return false
    }

    static func isProtectedAudio(_ item: [String: Any]) -> Bool {
        let info = item["encrypt_info"] as? [String: Any] ?? [:]
        return flag(info["encrypt"]) || nonEmpty(info["spade_a"])
            || nonEmpty(item["PlayAuth"]) || flag(item["Encrypt"])
    }

    private static func flag(_ value: Any?) -> Bool {
        if let number = value as? NSNumber { return number.doubleValue != 0 }
        if let text = value as? String {
            if let number = Double(text) { return number != 0 }
            return text.lowercased() == "true"
        }
        return false
    }

    private static func nonEmpty(_ value: Any?) -> Bool {
        guard let text = value as? String else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
