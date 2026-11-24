import Foundation

public enum CastDeviceType: String, Sendable {
    case dlna
    case airplay
    case googleCast
    
    public var priority: Int {
        switch self {
        case .googleCast: return 3
        case .dlna: return 2
        case .airplay: return 1
        }
    }
}

/// DLNA / AirPlay 设备描述模型
public struct DLNADevice: Identifiable, Equatable, Hashable, Sendable {
    public let id: String // USN (Unique Service Name) 或 AirPlay 服务名称
    public let friendlyName: String
    public let manufacturer: String
    public let modelName: String
    public let location: URL? // XML description URL
    public var controlURL: URL? // AVTransport control endpoint
    public var eventSubURL: URL? // Eventing subscription endpoint
    public var renderingControlURL: URL? // RenderingControl control endpoint
    public var deviceType: CastDeviceType

    public init(id: String, friendlyName: String, manufacturer: String, modelName: String, location: URL?, controlURL: URL? = nil, eventSubURL: URL? = nil, renderingControlURL: URL? = nil, deviceType: CastDeviceType = .dlna) {
        self.id = id
        self.friendlyName = friendlyName
        self.manufacturer = manufacturer
        self.modelName = modelName
        self.location = location
        self.controlURL = controlURL
        self.eventSubURL = eventSubURL
        self.renderingControlURL = renderingControlURL
        self.deviceType = deviceType
    }

    public static func == (lhs: DLNADevice, rhs: DLNADevice) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// 投屏播放状态
public enum DLNACastPlaybackState: Equatable, Sendable {
    case idle
    case loading
    case playing
    case paused
    case stopped
    case finished
    case error(DLNACastError)

    public static func == (lhs: DLNACastPlaybackState, rhs: DLNACastPlaybackState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading), (.playing, .playing),
             (.paused, .paused), (.stopped, .stopped), (.finished, .finished):
            return true
        case (.error(let a), .error(let b)):
            return a.localizedDescription == b.localizedDescription
        default:
            return false
        }
    }
}

/// 播放进度信息
public struct DLNACastPositionInfo: Sendable {
    public let currentTime: TimeInterval // 当前播放位置（秒）
    public let duration: TimeInterval    // 总时长（秒）
    public let progress: Double          // 0.0 ~ 1.0

    public init(currentTime: TimeInterval, duration: TimeInterval) {
        self.currentTime = currentTime
        self.duration = duration
        self.progress = duration > 0 ? min(currentTime / duration, 1.0) : 0
    }
}

/// 投屏媒体信息 — 包含视频 URL、标题、集数、字幕
public struct DLNACastMediaInfo: Sendable {
    public let mediaURL: String          // 视频直链 (MP4 / M3U8)
    public let title: String             // 剧名
    public let episode: Int?             // 集数（可选）
    public let subtitleURL: String?      // 外挂字幕 URL (SRT / VTT，可选)
    public let subtitleType: SubtitleType

    public enum SubtitleType: String, Sendable {
        case srt = "srt"
        case vtt = "vtt"
        case ass = "ass"
        case none = ""
    }

    public init(mediaURL: String, title: String, episode: Int? = nil,
                subtitleURL: String? = nil, subtitleType: SubtitleType = .none) {
        self.mediaURL = mediaURL
        self.title = title
        self.episode = episode
        self.subtitleURL = subtitleURL
        self.subtitleType = subtitleURL != nil ? subtitleType : .none
    }

    /// 组合显示标题（如 "Love Story Ep.3"）
    public var displayTitle: String {
        if let ep = episode {
            return "\(title) Ep.\(ep)"
        }
        return title
    }
}

/// 投屏错误类型
public enum DLNACastError: Error, LocalizedError, Sendable {
    case deviceNotFound
    case controlURLMissing
    case soapRequestFailed(statusCode: Int, body: String)
    case xmlParsingFailed(String)
    case networkError(Error)
    case playbackFailed(String)
    case disconnected

    public var errorDescription: String? {
        switch self {
        case .deviceNotFound: return "DLNA device not found"
        case .controlURLMissing: return "Device control URL not available"
        case .soapRequestFailed(let code, let body): return "SOAP failed (\(code)): \(body)"
        case .xmlParsingFailed(let msg): return "XML parse error: \(msg)"
        case .networkError(let err): return "Network error: \(err.localizedDescription)"
        case .playbackFailed(let msg): return "Playback failed: \(msg)"
        case .disconnected: return "Device disconnected"
        }
    }
}
