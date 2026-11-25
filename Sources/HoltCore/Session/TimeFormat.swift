import Foundation

public enum TimeFormat {
    /// `mm:ss`, or `h:mm:ss` at an hour or more. Rounds up so 0.2 s left shows 00:01.
    public static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded(.up))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }
}
