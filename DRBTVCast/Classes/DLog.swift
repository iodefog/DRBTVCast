import Foundation

// MARK: - Light-weight Standalone Logger Stub for DRBTVCast
// This removes DRBTVCast dependency on NFCommonKit for logging.

public struct DLog {
    public static func info(_ msg: String) {
        print("DLog: \(msg)")
    }
    public static func error(_ msg: String) {
        print("DLog ERROR: \(msg)")
    }
}
