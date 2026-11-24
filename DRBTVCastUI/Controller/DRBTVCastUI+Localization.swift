import Foundation

// MARK: - Light-weight Standalone Localization & Stubs for TV Cast UI
// We define self-contained Loc and Localizable classes to completely decouple DRBTVCastUI
// from DRBCommonKit and R.swift, using hardcoded Chinese/English strings.

public class Loc {
    public static func shared() -> Localizable {
        return Localizable.shared
    }
}

public class Localizable {
    nonisolated(unsafe) public static let shared = Localizable()

    private var isChinese: Bool {
        let lang = Locale.preferredLanguages.first ?? "en"
        return lang.contains("zh")
    }

    public func str_cast_title() -> String {
        return isChinese ? "投屏到电视" : "Cast to TV"
    }

    public func str_cast_availabledevice() -> String {
        return isChinese ? "附近的设备" : "Available Devices"
    }

    public func str_cast_notfound() -> String {
        return isChinese ? "没找到设备" : "No Devices Found"
    }

    public func str_cast_finddevice() -> String {
        return isChinese ? "查找设备" : "Search for Devices"
    }

    public func str_cast_casting() -> String {
        return isChinese ? "正在投屏中" : "Casting..."
    }

    public func str_ok() -> String {
        return isChinese ? "确定" : "OK"
    }

    public func str_video_auto_quality(_ quality: Int = 0) -> String {
        if quality > 0 {
            return isChinese ? "自动(\(quality)P)" : "Auto(\(quality)P)"
        }
        return isChinese ? "自动" : "Auto"
    }

    public func str_episode_alone_progress(_ episode: Int) -> String {
        return isChinese ? "第\(episode)集" : "Episode \(episode)"
    }

    public func str_videoquality_current() -> String {
        return isChinese ? "当前清晰度" : "Current Quality"
    }

    public func str_play_speed() -> String {
        return isChinese ? "播放速度" : "Playback Speed"
    }

    public func str_playdownloadvideo_fail() -> String {
        return isChinese ? "解锁失败，请重试" : "Unlock failed. Please try again."
    }

    public func str_unavailable_try_again() -> String {
        return isChinese ? "暂时不可用，请重试" : "Unavailable. Please try again."
    }

    public func str_download_memberads_toast() -> String {
        return isChinese ? "开通会员即可投屏观看" : "Subscribe to cast and watch"
    }

    public func str_series() -> String {
        return isChinese ? "选集" : "Episodes"
    }

    public func srt_cast_info() -> String {
        return isChinese ? "没找到设备？你的电视可能暂不支持，我们正在扩展兼容范围" : "No devices found? Your TV may not be supported yet — we're expanding compatibility."
    }

    public func str_cast_toast_notmember() -> String {
        return isChinese ? "仅会员用户支持投屏功能功能，请先订阅会员再使用投屏功能" : "Casting is available to members only. Please subscribe to use this feature."
    }

    public func str_cast_toast_fail() -> String {
        return isChinese ? "投屏失败，请重试" : "Casting failed. Please try again."
    }

    public func str_cast_fail_tryagain() -> String {
        return isChinese ? "链接错误，请重试" : "Connection failed. Please try again."
    }

    public func str_cast_nodevice_info() -> String {
        return isChinese ? "没找到设备？你的电视可能暂不支持，我们正在扩展兼容范围" : "No devices found? Your TV may not be supported yet — we're expanding compatibility."
    }
}
