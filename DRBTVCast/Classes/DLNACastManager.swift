import AVFoundation
import AVKit
import Foundation
import Network
import GoogleCast

// MARK: - Delegate Protocol

/// DLNACastManager 状态回调协议
@MainActor
public protocol DLNACastManagerDelegate: AnyObject {
    /// 设备发现
    func castManager(_ manager: DLNACastManager, didDiscoverDevice device: DLNADevice)
    /// 设备丢失
    func castManager(_ manager: DLNACastManager, didLoseDevice device: DLNADevice)
    /// 播放状态变化
    func castManager(_ manager: DLNACastManager, playbackStateDidChange state: DLNACastPlaybackState)
    /// 播放进度更新
    func castManager(_ manager: DLNACastManager, positionDidUpdate position: DLNACastPositionInfo)
    /// 播放完成（用于触发自动连播下一集）
    func castManagerDidFinishPlayback(_ manager: DLNACastManager)
    /// 播放错误
    func castManager(_ manager: DLNACastManager, didEncounterError error: DLNACastError)
}

// MARK: - Optional defaults

extension DLNACastManagerDelegate {
    public func castManager(_ manager: DLNACastManager, didLoseDevice device: DLNADevice) {}
}

// MARK: - DLNACastManager

/// DLNA / AirPlay 投屏管理器 — 负责设备发现、媒体投送、状态轮询
public final class DLNACastManager: NSObject, @unchecked Sendable {
    
    @MainActor public static let shared = DLNACastManager()
    
    /// 多播 delegate 集合（弱引用）
    @MainActor private let delegates = NSHashTable<AnyObject>.weakObjects()
    
    /// 兼容旧接口：设置 delegate 等同于 addDelegate
    @MainActor public weak var delegate: DLNACastManagerDelegate? {
        didSet {
            if let d = delegate {
                addDelegate(d)
            }
        }
    }
    
    /// 添加一个监听者（弱引用，不会重复添加）
    @MainActor public func addDelegate(_ d: DLNACastManagerDelegate) {
        delegates.add(d as AnyObject)
    }
    
    /// 移除一个监听者
    @MainActor public func removeDelegate(_ d: DLNACastManagerDelegate) {
        delegates.remove(d as AnyObject)
    }
    
    /// 遍历所有活跃的 delegate
    @MainActor private func enumerateDelegates(_ body: (DLNACastManagerDelegate) -> Void) {
        for obj in delegates.allObjects {
            if let d = obj as? DLNACastManagerDelegate {
                body(d)
            }
        }
    }
    
    /// 当前连接的设备
    public var connectedDevice: DLNADevice? {
        didSet {
            guard connectedDevice != oldValue else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                NotificationCenter.default.post(
                    name: NSNotification.Name("DLNACastConnectedDeviceDidChangeNotification"), object: self)
            }
        }
    }
    
    /// 当前要投屏的媒体
    public var currentMedia: DLNACastMediaInfo?
    
    /// 已发现的设备列表
    public private(set) var discoveredDevices: [DLNADevice] = []
    
    private var rawDLNADevices: [DLNADevice] = []
    private var rawAirPlayDevices: [DLNADevice] = []
    private var rawGoogleCastDevices: [DLNADevice] = []
    private var pendingMediaToCast: DLNACastMediaInfo?
    
    /// 当前播放状态
    public private(set) var playbackState: DLNACastPlaybackState = .idle {
        didSet {
            guard playbackState != oldValue else { return }
            DispatchQueue.main.async { @MainActor [weak self] in
                guard let self else { return }
                self.enumerateDelegates { $0.castManager(self, playbackStateDidChange: self.playbackState) }
                NotificationCenter.default.post(
                    name: NSNotification.Name("DLNACastPlaybackStateDidChangeNotification"), object: self)
            }
        }
    }
    
    /// 最近一次进度信息
    public private(set) var lastPosition: DLNACastPositionInfo?
    
    // MARK: - Private
    
    private let discovery = SSDPDiscovery()
    private let transport = SOAPTransport()
    private var pollingTimer: Timer?
    private var failedPollCount = 0
    private let maxFailedPolls = 5
    private let pollingInterval: TimeInterval = 2.0
    
    // Bonjour discovery for AirPlay
    private var bonjourBrowser: NWBrowser?
    @MainActor private var pickerHelper: DLNAAirPlayPickerHelper?
    
    // AirPlay Player & Observers
    @MainActor private var avPlayer: AVPlayer?
    @MainActor private var avPlayerLayer: AVPlayerLayer?
    @MainActor private var timeObserverToken: Any?
    @MainActor private var rateObservation: NSKeyValueObservation?
    @MainActor private var statusObservation: NSKeyValueObservation?
    @MainActor private var externalActiveObservation: NSKeyValueObservation?
    
    // 播放完成检测（纯靠进度，不依赖 transport state）
    private let finishThresholdSeconds: TimeInterval = 5.0  // 距离结尾 5 秒内视为完成
    private var positionStallCount = 0  // 进度停滞计数
    private var lastPolledTime: TimeInterval = -1
    private var hasNotifiedFinish = false
    @MainActor private var dlnaVolume: Int = 50
    @MainActor public private(set) var currentPlayRate: Float = 1.0
    @MainActor private var pendingSeekAfterCast: TimeInterval?
    private var pendingPauseRequest: Bool = false
    private var wasPlaying: Bool = false
    private var castStartTime: Date?
    private var isPreparingForNewCast: Bool = false
    
    @MainActor private var googleCastClient: GCKRemoteMediaClient? {
        if GCKCastContext.isSharedInstanceInitialized(),
           let client = GCKCastContext.sharedInstance().sessionManager.currentCastSession?.remoteMediaClient {
            client.add(self)
            return client
        }
        return nil
    }
    
    private var isAudioInterrupted = false
    
    private override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(handleAudioInterruption(_:)), name: AVAudioSession.interruptionNotification, object: nil)
        setupDiscoveryCallbacks()
    }
    
    @MainActor @objc private func handleAudioInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        
        if type == .began {
            isAudioInterrupted = true
        } else if type == .ended {
            isAudioInterrupted = false
            
            // 如果系统提示打断结束可以恢复播放，则尝试恢复
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    if self.connectedDevice?.deviceType == .airplay, self.playbackState != .stopped {
                        self.avPlayer?.play()
                        self.playbackState = .playing
                    }
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self = self else { return }
                if self.connectedDevice?.deviceType == .airplay, self.avPlayer?.isExternalPlaybackActive == false {
                    let hasAirPlay = AVAudioSession.sharedInstance().currentRoute.outputs.contains(where: { $0.portType == .airPlay })
                    if !hasAirPlay {
                        self.disconnect()
                    }
                }
            }
        }
    }
    
    // MARK: - Public API: Discovery
    
    /// 开始搜索局域网 DLNA、AirPlay 和 Google Cast 设备
    public func startDiscovery(timeout: TimeInterval = 10) {
        discoveredDevices.removeAll()
        rawDLNADevices.removeAll()
        rawAirPlayDevices.removeAll()
        rawGoogleCastDevices.removeAll()
        discovery.startSearch(timeout: timeout)
        startBonjourDiscovery(timeout: timeout)
        if GCKCastContext.isSharedInstanceInitialized() {
            GCKCastContext.sharedInstance().discoveryManager.startDiscovery()
            self.didUpdateDeviceList()
        }
    }
    
    @MainActor
    private func updateDiscoveredDevices() {
        let allRaw = rawAirPlayDevices + rawGoogleCastDevices + rawDLNADevices
        let newDiscovered = allRaw.sorted(by: { $0.friendlyName < $1.friendlyName })
        let oldDiscovered = self.discoveredDevices
        
        self.discoveredDevices = newDiscovered
        
        // Find removed
        for old in oldDiscovered {
            if !newDiscovered.contains(where: { $0.id == old.id }) {
                self.enumerateDelegates { $0.castManager(self, didLoseDevice: old) }
            }
        }
        
        // Find added
        for new in newDiscovered {
            if !oldDiscovered.contains(where: { $0.id == new.id }) {
                self.enumerateDelegates { $0.castManager(self, didDiscoverDevice: new) }
            }
        }
    }
    
    /// 停止搜索
    public func stopDiscovery() {
        discovery.stopSearch()
        stopBonjourDiscovery()
        if GCKCastContext.isSharedInstanceInitialized() {
            GCKCastContext.sharedInstance().discoveryManager.stopDiscovery()
        }
    }
    
    // MARK: - Public API: Connection
    
    /// 连接到指定设备
    public func connect(to device: DLNADevice) {
        connectedDevice = device
        playbackState = .idle
        
        if device.deviceType == .airplay {
            DispatchQueue.main.async {
                self.showSystemAirPlayPicker()
            }
        } else if device.deviceType == .googleCast {
            if GCKCastContext.isSharedInstanceInitialized() {
                let discoveryManager = GCKCastContext.sharedInstance().discoveryManager
                if let nativeDevice = discoveryManager.device(withUniqueID: device.id) {
                    print("【DRBTVCast】Connecting to Google Cast device: \(device.friendlyName)")
                    GCKCastContext.sharedInstance().sessionManager.startSession(with: nativeDevice)
                } else {
                    print("【DRBTVCast】Google Cast device not found in discovery manager: \(device.id)")
                    reportError(.deviceNotFound)
                }
            }
        }
    }
    
    /// 断开连接
    @MainActor
    public func disconnect() {
        if connectedDevice?.deviceType == .airplay {
            cleanupAVPlayer()
            
            // 会话分类/激活互相视为耗时操作，统一挪到后台队列执行，避免主线程卡顿
            //（主线程调用 setActive 会打印 "AVAudioSession_iOS.mm:978 ... UI unresponsiveness" 告警）
            let sessionQueue = DispatchQueue.global(qos: .userInitiated)
            sessionQueue.async {
                do {
                    // 1. 强行改变分类，迫使系统把音频路由抓回本地扬声器
                    try AVAudioSession.sharedInstance().setCategory(.playAndRecord, options: [.defaultToSpeaker])
                    try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
                    print("【DRBTVCast】Successfully forced route back to speaker.")

                    // 2. 关键修复：必须延迟 0.1 秒，给系统硬件留出路由切换的缓冲时间
                    sessionQueue.asyncAfter(deadline: .now() + 0.1) {
                        do {
                            // 3. 此时路由已在本地，再稳妥地切回常规的 playback 模式
                            try AVAudioSession.sharedInstance().setCategory(.playback, options: [])
                            try AVAudioSession.sharedInstance().setActive(true)
                            print("【DRBTVCast】Audio session restored to playback mode.")
                        } catch {
                            print("【DRBTVCast】Failed to restore playback category: \(error.localizedDescription)")
                        }
                    }
                } catch {
                    print("【DRBTVCast】Failed to reset audio session: \(error.localizedDescription)")
                }
            }
        } else if connectedDevice?.deviceType == .googleCast {
            if GCKCastContext.isSharedInstanceInitialized() {
                let sessionManager = GCKCastContext.sharedInstance().sessionManager
                if sessionManager.hasConnectedCastSession() {
                    sessionManager.endSession()
                }
            }
        } else {
            stopPolling()
            if let controlURL = connectedDevice?.controlURL {
                transport.stop(controlURL: controlURL) { _ in }
            }
        }
        connectedDevice = nil
        pendingMediaToCast = nil
        playbackState = .idle
        lastPosition = nil
    }
    
    // MARK: - Public API: Playback Control
    
    /// 准备投屏新剧集，清除旧的回调和进度
    @MainActor
    public func prepareForNewCast() {
        isPreparingForNewCast = true
        stopPolling()
        lastPosition = DLNACastPositionInfo(currentTime: 0, duration: 0)
        self.enumerateDelegates { $0.castManager(self, positionDidUpdate: self.lastPosition!) }
    }
    
    /// 投送媒体到电视播放（完整信息：标题+集数+字幕）
    /// - Parameters:
    ///   - media: 媒体信息
    ///   - resumePosition: 可选，投屏成功后自动 seek 到该时间（秒），用于切清晰度等场景
    @MainActor
    public func cast(media: DLNACastMediaInfo, resumePosition: TimeInterval? = nil) {
        guard let device = connectedDevice else {
            reportError(.deviceNotFound)
            return
        }
        
        pendingSeekAfterCast = resumePosition
        pendingPauseRequest = false
        wasPlaying = false
        isPreparingForNewCast = false
        castStartTime = Date()
        lastPosition = DLNACastPositionInfo(currentTime: 0, duration: 0)
        self.enumerateDelegates { $0.castManager(self, positionDidUpdate: self.lastPosition!) }
        
        if device.deviceType == .dlna {
            guard let controlURL = device.controlURL else {
                reportError(.controlURLMissing)
                return
            }
            
            playbackState = .loading
            failedPollCount = 0
            positionStallCount = 0
            lastPolledTime = -1
            hasNotifiedFinish = false
            
            // Stop any playing video on the TV before casting new media
            transport.stop(controlURL: controlURL) { [weak self] _ in
                guard let self = self else { return }
                self.transport.setAVTransportURI(controlURL: controlURL, media: media) {
                    [weak self] result in
                    guard let self = self else { return }
                    switch result {
                    case .success:
                        self.transport.play(controlURL: controlURL) { [weak self] playResult in
                            guard let self = self else { return }
                            switch playResult {
                            case .success:
                                self.playbackState = .playing
                                self.startPolling()
                                self.attemptSubtitleFallback(controlURL: controlURL, media: media)
                                // pendingSeekAfterCast will be handled in pollStatus when duration > 0
                            case .failure(let error):
                                self.reportError(error)
                            }
                        }
                    case .failure(let error):
                        self.reportError(error)
                    }
                }
            }
        } else if device.deviceType == .googleCast {
            playbackState = .loading
            let metadata = GCKMediaMetadata(metadataType: .movie)
            metadata.setString(media.title, forKey: kGCKMetadataKeyTitle)
            if let ep = media.episode {
                metadata.setString("EP.\(ep)", forKey: kGCKMetadataKeySubtitle)
            }
            
            guard let contentURL = URL(string: media.mediaURL) else {
                reportError(.controlURLMissing)
                return
            }
            
            let mediaInfoBuilder = GCKMediaInformationBuilder(contentURL: contentURL)
            mediaInfoBuilder.streamType = .buffered
            mediaInfoBuilder.contentType = media.mediaURL.contains(".m3u8") ? "application/x-mpegurl" : "video/mp4"
            mediaInfoBuilder.metadata = metadata
            
            if let remoteClient = googleCastClient {
                let loadOptions = GCKMediaLoadOptions()
                loadOptions.autoplay = true
                if let seekTime = pendingSeekAfterCast, seekTime > 0 {
                    loadOptions.playPosition = seekTime
                    pendingSeekAfterCast = nil
                }
                remoteClient.loadMedia(mediaInfoBuilder.build(), with: loadOptions)
                pendingMediaToCast = nil
            } else {
                print("【DRBTVCast】Google Cast session not ready, buffering media cast request.")
                pendingMediaToCast = media
            }
        } else {
            castToAirPlay(media: media)
        }
    }
    
    /// 投送媒体 URL 到电视播放（简化版）
    @MainActor
    public func cast(urlString: String, title: String = "DramaBox", episode: Int? = nil) {
        let media = DLNACastMediaInfo(mediaURL: urlString, title: title, episode: episode)
        cast(media: media)
    }
    
    /// 暂停
    @MainActor
    public func pause() {
        pendingPauseRequest = true
        if connectedDevice?.deviceType == .airplay {
            avPlayer?.pause()
            playbackState = .paused
        } else if connectedDevice?.deviceType == .googleCast {
            if playbackState == .playing {
                googleCastClient?.pause()
            }
            playbackState = .paused
        } else {
            guard let controlURL = connectedDevice?.controlURL else { return }
            transport.pause(controlURL: controlURL) { [weak self] result in
                if case .success = result {
                    self?.playbackState = .paused
                }
            }
        }
    }
    
    /// 恢复播放
    @MainActor
    public func resume() {
        pendingPauseRequest = false
        if connectedDevice?.deviceType == .airplay {
            avPlayer?.rate = currentPlayRate
            playbackState = .playing
        } else if connectedDevice?.deviceType == .googleCast {
            googleCastClient?.play()
            playbackState = .playing
        } else {
            guard let controlURL = connectedDevice?.controlURL else { return }
            transport.play(controlURL: controlURL) { [weak self] result in
                if case .success = result {
                    self?.playbackState = .playing
                }
            }
        }
    }
    
    /// 停止
    @MainActor
    public func stop() {
        pendingPauseRequest = false
        if connectedDevice?.deviceType == .airplay {
            cleanupAVPlayer()
            playbackState = .stopped
        } else if connectedDevice?.deviceType == .googleCast {
            googleCastClient?.stop()
            playbackState = .stopped
        } else {
            guard let controlURL = connectedDevice?.controlURL else { return }
            stopPolling()
            transport.stop(controlURL: controlURL) { [weak self] _ in
                self?.playbackState = .stopped
            }
        }
    }
    
    /// 跳转到指定时间
    @MainActor
    public func seek(to seconds: TimeInterval) {
        if connectedDevice?.deviceType == .airplay {
            let targetTime = CMTime(seconds: seconds, preferredTimescale: 1000)
            avPlayer?.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
        } else if connectedDevice?.deviceType == .googleCast {
            let options = GCKMediaSeekOptions()
            options.interval = seconds
            options.resumeState = .play
            googleCastClient?.seek(with: options)
        } else {
            guard let controlURL = connectedDevice?.controlURL else { return }
            transport.seek(controlURL: controlURL, target: seconds) { _ in }
        }
    }
    
    /// 设置播放倍速（针对 AirPlay / Google Cast）
    @MainActor
    public func setPlayRate(_ rate: Float) {
        currentPlayRate = rate
        if connectedDevice?.deviceType == .airplay {
            if playbackState == .playing {
                avPlayer?.rate = rate
            }
        } else if connectedDevice?.deviceType == .googleCast {
            googleCastClient?.setPlaybackRate(rate)
        }
    }
    
    /// 改变音量（针对 AirPlay / DLNA / Google Cast）
    @MainActor
    public func changeVolume(delta: Float) {
        if connectedDevice?.deviceType == .airplay {
            if let player = avPlayer {
                player.volume = max(0.0, min(1.0, player.volume + delta))
            }
        } else if connectedDevice?.deviceType == .googleCast {
            if let session = GCKCastContext.sharedInstance().sessionManager.currentCastSession {
                let current = session.currentDeviceVolume
                session.setDeviceVolume(max(Float(0.0), min(Float(1.0), current + delta)))
            }
        } else if connectedDevice?.deviceType == .dlna {
            guard let renderingURL = connectedDevice?.renderingControlURL else { return }
            let change = Int(delta * 100)
            dlnaVolume = max(0, min(100, dlnaVolume + change))
            transport.setVolume(renderingControlURL: renderingURL, volume: dlnaVolume) { _ in }
        }
    }
    
    /// 设置音量（针对 AirPlay / DLNA / Google Cast，范围 0.0 - 1.0）
    @MainActor
    public func setVolume(_ volume: Float) {
        let normalizedVolume = max(0.0, min(1.0, volume))
        if connectedDevice?.deviceType == .airplay {
            avPlayer?.volume = normalizedVolume
        } else if connectedDevice?.deviceType == .googleCast {
            GCKCastContext.sharedInstance().sessionManager.currentCastSession?.setDeviceVolume(normalizedVolume)
        } else if connectedDevice?.deviceType == .dlna {
            guard let renderingURL = connectedDevice?.renderingControlURL else { return }
            dlnaVolume = Int(normalizedVolume * 100)
            transport.setVolume(renderingControlURL: renderingURL, volume: dlnaVolume) { _ in }
        }
    }
    
    /// 获取当前音量（范围 0.0 - 1.0）
    @MainActor
    public func currentVolume() -> Float {
        if connectedDevice?.deviceType == .airplay {
            return avPlayer?.volume ?? 1.0
        } else if connectedDevice?.deviceType == .googleCast {
            return GCKCastContext.sharedInstance().sessionManager.currentCastSession?.currentDeviceVolume ?? 1.0
        } else if connectedDevice?.deviceType == .dlna {
            return Float(dlnaVolume) / 100.0
        }
        return 1.0
    }
    
    // MARK: - Subtitle Fallback
    
    /// 播放成功后尝试通过非标准 action 推送字幕，静默失败
    private func attemptSubtitleFallback(controlURL: URL, media: DLNACastMediaInfo) {
        guard let subURL = media.subtitleURL, media.subtitleType != .none else { return }
        transport.pushSubtitleFallback(
            controlURL: controlURL,
            subtitleURL: subURL,
            subtitleType: media.subtitleType
        ) { _ in }
    }
    
    // MARK: - Polling
    
    private func startPolling() {
        stopPolling()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pollingTimer = Timer.scheduledTimer(
                withTimeInterval: self.pollingInterval, repeats: true
            ) { [weak self] _ in
                self?.pollStatus()
            }
        }
    }
    
    private func stopPolling() {
        DispatchQueue.main.async { [weak self] in
            self?.pollingTimer?.invalidate()
            self?.pollingTimer = nil
        }
    }
    
    private func pollStatus() {
        guard let controlURL = connectedDevice?.controlURL else { return }
        
        transport.getPositionInfo(controlURL: controlURL) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch result {
                case .success(let position):
                    // 如果正在准备投屏新剧集（例如正在请求视频地址），忽略任何旧的进度回调
                    if self.isPreparingForNewCast {
                        print("【DRBTVCast】正在准备新投屏，忽略旧进度回调")
                        return
                    }
                    
                    // 过滤刚投屏时电视返回的旧进度
                    if let startTime = self.castStartTime, Date().timeIntervalSince(startTime) < 8.0 {
                        let expectedTime = self.pendingSeekAfterCast ?? 0
                        if abs(position.currentTime - expectedTime) > 10.0 {
                            print("【DRBTVCast】忽略电视返回的旧进度: \(position.currentTime)")
                            return
                        }
                    }
                    
                    self.failedPollCount = 0
                    self.lastPosition = position
                    
                    // Handle pending seek after cast (quality switch etc.)
                    if let seekTime = self.pendingSeekAfterCast, seekTime > 0, position.duration > 0 {
                        print("【DRBTVCast】Executing pending seek after cast to \(seekTime)s")
                        self.seek(to: seekTime)
                        self.pendingSeekAfterCast = nil
                    }
                    self.enumerateDelegates { $0.castManager(self, positionDidUpdate: position) }
                    
                    self.evaluatePlaybackProgress(position: position)
                    
                case .failure:
                    self.failedPollCount += 1
                    if self.failedPollCount >= self.maxFailedPolls {
                        self.stopPolling()
                        self.reportError(.disconnected)
                    }
                }
            }
        }
    }
    
    /// 纯靠进度判断播放完成（不依赖 GetTransportInfo）
    private func evaluatePlaybackProgress(position: DLNACastPositionInfo) {
        guard !hasNotifiedFinish else { return }
        guard position.duration > 0 else { return }
        
        // 策略1: 当前时间距离总时长 <= 5 秒 → 视为即将/已经播完
        let remaining = position.duration - position.currentTime
        if remaining <= finishThresholdSeconds && position.currentTime > 0 {
            triggerFinish()
            return
        }
        
        // 策略2: 进度停滞检测 — 连续 3 次轮询 position 不变（且已过半）
        // 覆盖电视播到最后一帧卡住、不更新进度的情况
        if position.currentTime > 0 && abs(position.currentTime - lastPolledTime) < 0.5 {
            positionStallCount += 1
            if positionStallCount >= 3 && position.progress > 0.9 {
                triggerFinish()
                return
            }
        } else {
            positionStallCount = 0
        }
        lastPolledTime = position.currentTime
        
        if pendingPauseRequest {
            if playbackState != .paused {
                playbackState = .paused
                if connectedDevice?.deviceType == .dlna {
                    if let controlURL = connectedDevice?.controlURL {
                        transport.pause(controlURL: controlURL) { _ in }
                    }
                }
            }
        } else {
            // 正常播放中，确保状态正确
            wasPlaying = true
            if playbackState != .playing {
                playbackState = .playing
            }
        }
    }
    
    private func triggerFinish() {
        guard !hasNotifiedFinish else { return }
        hasNotifiedFinish = true
        stopPolling()
        playbackState = .finished
        DispatchQueue.main.async { @MainActor [weak self] in
            guard let self else { return }
            self.enumerateDelegates { $0.castManagerDidFinishPlayback(self) }
        }
    }
    
    // MARK: - Private Helpers: Bonjour & AirPlay
    
    private func startBonjourDiscovery(timeout: TimeInterval) {
        stopBonjourDiscovery()
        
        let descriptor = NWBrowser.Descriptor.bonjour(type: "_airplay._tcp", domain: "local.")
        let parameters = NWParameters()
        let browser = NWBrowser(for: descriptor, using: parameters)
        
        browser.browseResultsChangedHandler = { [weak self] results, changes in
            guard let self = self else { return }
            
            var airplayDevices: [DLNADevice] = []
            for result in results {
                if case .service(name: let name, type: _, domain: _, interface: _) = result.endpoint {
                    let serviceId = "airplay-\(name)"
                    let device = DLNADevice(
                        id: serviceId,
                        friendlyName: name,
                        manufacturer: "Apple",
                        modelName: "AirPlay Device",
                        location: nil,
                        controlURL: nil,
                        eventSubURL: nil,
                        deviceType: .airplay
                    )
                    airplayDevices.append(device)
                }
            }
            
            DispatchQueue.main.async { @MainActor [weak self] in
                guard let self = self else { return }
                self.rawAirPlayDevices = airplayDevices
                self.updateDiscoveredDevices()
            }
        }
        
        self.bonjourBrowser = browser
        browser.start(queue: .global(qos: .userInitiated))
    }
    
    private func stopBonjourDiscovery() {
        bonjourBrowser?.cancel()
        bonjourBrowser = nil
    }
    
    @MainActor
    private func getTopViewController(from viewController: UIViewController?) -> UIViewController? {
        if let nav = viewController as? UINavigationController {
            return getTopViewController(from: nav.visibleViewController)
        }
        if let tab = viewController as? UITabBarController {
            return getTopViewController(from: tab.selectedViewController)
        }
        if let presented = viewController?.presentedViewController {
            return getTopViewController(from: presented)
        }
        return viewController
    }
    
    @MainActor
    public func showSystemAirPlayPicker() {
        guard
            let windowScene = UIApplication.shared.connectedScenes.first(where: {
                $0.activationState == .foregroundActive
            }) as? UIWindowScene,
            let keyWindow = windowScene.windows.first(where: { $0.isKeyWindow })
        else {
            return
        }
        
        let picker = AVRoutePickerView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        picker.isHidden = false
        picker.alpha = 0.01
        
        let helper = DLNAAirPlayPickerHelper()
        helper.onDidEndPresenting = { [weak self, weak picker] in
            NotificationCenter.default.post(
                name: Notification.Name("DLNACastAirPlayPickerDidDismiss"), object: nil)
            picker?.removeFromSuperview()
            self?.pickerHelper = nil
        }
        picker.delegate = helper
        self.pickerHelper = helper
        
        keyWindow.addSubview(picker)
        picker.layoutIfNeeded()
        
        func findButton(in view: UIView) -> UIButton? {
            if let button = view as? UIButton {
                return button
            }
            for subview in view.subviews {
                if let found = findButton(in: subview) {
                    return found
                }
            }
            return nil
        }
        
        let triggerPicker: () -> Bool = {
            if let button = findButton(in: picker) {
                button.sendActions(for: .touchUpInside)
                return true
            }
            return false
        }
        
        var attempts = 0
        func tryTrigger() {
            if triggerPicker() {
                return
            }
            attempts += 1
            if attempts < 20 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    tryTrigger()
                }
            } else {
                print("【DRBTVCast】Failed to find AirPlay button in AVRoutePickerView after 20 attempts")
            }
        }
        tryTrigger()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) { [weak self, weak picker] in
            picker?.removeFromSuperview()
            if self?.pickerHelper === helper {
                self?.pickerHelper = nil
                NotificationCenter.default.post(
                    name: Notification.Name("DLNACastAirPlayPickerDidDismiss"), object: nil)
            }
        }
    }
    
    @MainActor
    private func castToAirPlay(media: DLNACastMediaInfo) {
        guard let url = URL(string: media.mediaURL) else {
            reportError(.controlURLMissing)
            return
        }
        
        playbackState = .loading
        cleanupAVPlayer()
        
        let playerItem = AVPlayerItem(url: url)
        
        let titleItem = AVMutableMetadataItem()
        titleItem.identifier = .commonIdentifierTitle
        titleItem.value = media.displayTitle as NSString
        titleItem.extendedLanguageTag = "und"
        playerItem.externalMetadata = [titleItem]
        
        let player = AVPlayer(playerItem: playerItem)
        player.allowsExternalPlayback = true
        player.usesExternalPlaybackWhileExternalScreenIsActive = true
        
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspectFill
        self.avPlayerLayer = playerLayer
        
        setupAVPlayerObservers(player: player)
        
        self.avPlayer = player
        
        // For AirPlay: if there's a pending seek, seek first then play at rate
        if let seekTime = self.pendingSeekAfterCast, seekTime > 0 {
            let targetTime = CMTime(seconds: seekTime, preferredTimescale: 1000)
            player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    if !self.pendingPauseRequest {
                        self.avPlayer?.rate = self.currentPlayRate
                    }
                    self.pendingSeekAfterCast = nil
                }
            }
        } else {
            if !pendingPauseRequest {
                player.rate = currentPlayRate
            }
        }
    }
    
    @MainActor
    private func setupAVPlayerObservers(player: AVPlayer) {
        rateObservation = player.observe(\.rate, options: [.new]) { [weak self] player, change in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let rate = player.rate
                if rate == 0 {
                    if self.playbackState != .finished && self.playbackState != .stopped {
                        self.playbackState = .paused
                    }
                } else {
                    self.playbackState = .playing
                }
            }
        }
        
        if let currentItem = player.currentItem {
            statusObservation = currentItem.observe(\.status, options: [.new]) {
                [weak self] item, change in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    switch item.status {
                    case .readyToPlay:
                        self.playbackState = .playing
                    case .failed:
                        let errorMsg = item.error?.localizedDescription ?? "AVPlayer playback failed"
                        self.reportError(.playbackFailed(errorMsg))
                    case .unknown:
                        break
                    @unknown default:
                        break
                    }
                }
            }
        }
        
        externalActiveObservation = player.observe(\.isExternalPlaybackActive, options: [.new]) {
            [weak self] player, change in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let isActive = player.isExternalPlaybackActive
                print("【DRBTVCast】AirPlay isExternalPlaybackActive changed: \(isActive)")
                if !isActive {
                    if !self.isAudioInterrupted {
                        let hasAirPlay = AVAudioSession.sharedInstance().currentRoute.outputs.contains(where: { $0.portType == .airPlay })
                        if !hasAirPlay {
                            self.disconnect()
                        }
                    }
                }
            }
        }
        
        let interval = CMTime(seconds: 1.0, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) {
            [weak self] time in
            Task { @MainActor [weak self] in
                guard let self = self, let player = self.avPlayer, let currentItem = player.currentItem
                else { return }
                let currentTime = CMTimeGetSeconds(time)
                let duration = CMTimeGetSeconds(currentItem.duration)
                
                guard !currentTime.isNaN, !duration.isNaN, duration > 0 else { return }
                
                let position = DLNACastPositionInfo(currentTime: currentTime, duration: duration)
                self.lastPosition = position
                self.enumerateDelegates { $0.castManager(self, positionDidUpdate: position) }
            }
        }
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(avPlayerItemDidPlayToEndTime(_:)),
            name: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem
        )
    }
    
    @MainActor
    private func cleanupAVPlayer() {
        if let token = timeObserverToken {
            avPlayer?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        
        rateObservation?.invalidate()
        rateObservation = nil
        
        statusObservation?.invalidate()
        statusObservation = nil
        
        externalActiveObservation?.invalidate()
        externalActiveObservation = nil
        
        NotificationCenter.default.removeObserver(
            self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        
        avPlayer?.allowsExternalPlayback = false
        avPlayer?.pause()
        avPlayer = nil
    }
    
    @objc @MainActor private func avPlayerItemDidPlayToEndTime(_ notification: Notification) {
        playbackState = .finished
        enumerateDelegates { $0.castManagerDidFinishPlayback(self) }
    }
    
    // MARK: - Private Helpers: Discovery Callbacks
    
    private func setupDiscoveryCallbacks() {
        discovery.onDeviceFound = { [weak self] device in
            guard let self else { return }
            DispatchQueue.main.async { @MainActor in
                if !self.rawDLNADevices.contains(where: { $0.id == device.id }) {
                    self.rawDLNADevices.append(device)
                    self.updateDiscoveredDevices()
                }
            }
        }
        
        discovery.onDeviceLost = { [weak self] device in
            guard let self else { return }
            DispatchQueue.main.async { @MainActor in
                self.rawDLNADevices.removeAll { $0.id == device.id }
                self.updateDiscoveredDevices()
            }
        }
        
        discovery.onError = { [weak self] error in
            guard let self else { return }
            self.reportError(.networkError(error))
        }
    }
    
    private func reportError(_ error: DLNACastError) {
        playbackState = .error(error)
        DispatchQueue.main.async { @MainActor [weak self] in
            guard let self = self else { return }
            self.enumerateDelegates { $0.castManager(self, didEncounterError: error) }
        }
    }
    
    /// 初始化 Google Cast SDK
    @MainActor
    public func initializeGoogleCast(applicationId: String = kGCKDefaultMediaReceiverApplicationID) {
        guard !GCKCastContext.isSharedInstanceInitialized() else { return }
        
        let criteria = GCKDiscoveryCriteria(applicationID: applicationId)
        let options = GCKCastOptions(discoveryCriteria: criteria)
        GCKCastContext.setSharedInstanceWith(options)
        
        let sessionManager = GCKCastContext.sharedInstance().sessionManager
        sessionManager.add(self)
        
        let discoveryManager = GCKCastContext.sharedInstance().discoveryManager
        discoveryManager.add(self)
        discoveryManager.passiveScan = false
        
        GCKLogger.sharedInstance().delegate = self
        let logFilter = GCKLoggerFilter()
        #if DEBUG
        logFilter.minimumLevel = .verbose
        #else
        logFilter.minimumLevel = .warning
        #endif
        GCKLogger.sharedInstance().filter = logFilter
    }
}

// MARK: - DLNAAirPlayPickerHelper

class DLNAAirPlayPickerHelper: NSObject, AVRoutePickerViewDelegate {
    var onDidEndPresenting: (() -> Void)?
    func routePickerViewDidEndPresentingRoutes(_ routePickerView: AVRoutePickerView) {
        onDidEndPresenting?()
    }
}

// MARK: - GCKDiscoveryManagerListener, GCKSessionManagerListener, GCKRemoteMediaClientListener

extension DLNACastManager: GCKDiscoveryManagerListener {
    public func didInsert(_ device: GCKDevice, at index: UInt) {
        didUpdateDeviceList()
    }
    
    public func didUpdate(_ device: GCKDevice, at index: UInt) {
        didUpdateDeviceList()
    }
    
    public func didRemove(_ device: GCKDevice, at index: UInt) {
        didUpdateDeviceList()
    }

    public func didUpdateDeviceList() {
        let discoveryManager = GCKCastContext.sharedInstance().discoveryManager
        let count = discoveryManager.deviceCount
        print("【DRBTVCast】Google Cast didUpdateDeviceList called! deviceCount = \(count)")
        
        var currentDevices: [DLNADevice] = []
        for i in 0..<count {
            let device = discoveryManager.device(at: i)
            let name = device.friendlyName ?? "Chromecast"
            let dlnaDevice = DLNADevice(
                id: device.uniqueID,
                friendlyName: name,
                manufacturer: "Google",
                modelName: device.modelName ?? "Chromecast",
                location: nil,
                controlURL: nil,
                eventSubURL: nil,
                deviceType: .googleCast
            )
            currentDevices.append(dlnaDevice)
            print("【DRBTVCast】Google Cast active device: \(name)")
        }
        
        DispatchQueue.main.async { @MainActor [weak self] in
            guard let self = self else { return }
            self.rawGoogleCastDevices = currentDevices
            self.updateDiscoveredDevices()
        }
    }
}

extension DLNACastManager: GCKSessionManagerListener {
    public func sessionManager(_ sessionManager: GCKSessionManager, didStart session: GCKSession) {
        print("【DRBTVCast】Google Cast session started")
        (session as? GCKCastSession)?.remoteMediaClient?.add(self)
        DispatchQueue.main.async { @MainActor [weak self] in
            guard let self = self else { return }
            self.playbackState = .idle
            if let pending = self.pendingMediaToCast {
                print("【DRBTVCast】Session started, loading buffered media.")
                self.cast(media: pending)
            }
        }
    }
    
    public func sessionManager(_ sessionManager: GCKSessionManager, didResumeSession session: GCKSession) {
        print("【DRBTVCast】Google Cast session resumed")
        (session as? GCKCastSession)?.remoteMediaClient?.add(self)
    }
    
    public func sessionManager(_ sessionManager: GCKSessionManager, didEnd session: GCKSession, withError error: Error?) {
        print("【DRBTVCast】Google Cast session ended, error: \(String(describing: error))")
        (session as? GCKCastSession)?.remoteMediaClient?.remove(self)
        DispatchQueue.main.async { @MainActor [weak self] in
            guard let self = self else { return }
            self.pendingMediaToCast = nil
            self.disconnect()
        }
    }
    
    public func sessionManager(_ sessionManager: GCKSessionManager, didFailToStart session: GCKSession, withError error: Error) {
        print("【DRBTVCast】Google Cast session failed to start: \(error.localizedDescription)")
        DispatchQueue.main.async { @MainActor [weak self] in
            guard let self = self else { return }
            self.pendingMediaToCast = nil
            self.reportError(.playbackFailed("Failed to start session: \(error.localizedDescription)"))
        }
    }
}

extension DLNACastManager: GCKRemoteMediaClientListener {
    public func remoteMediaClient(_ client: GCKRemoteMediaClient, didUpdate mediaStatus: GCKMediaStatus?) {
        guard let status = mediaStatus else { return }
        
        let playerState = status.playerState
        let idleReason = status.idleReason
        let currentTime = client.approximateStreamPosition()
        let duration = status.mediaInformation?.streamDuration ?? 0
        
        DispatchQueue.main.async { @MainActor [weak self] in
            guard let self = self else { return }
            
            switch playerState {
            case .idle:
                if idleReason == .finished {
                    self.playbackState = .finished
                    self.enumerateDelegates { $0.castManagerDidFinishPlayback(self) }
                } else if idleReason == .error {
                    self.reportError(.playbackFailed("Chromecast playback idle with error"))
                } else {
                    self.playbackState = .idle
                }
            case .playing:
                self.wasPlaying = true
                if self.pendingPauseRequest {
                    self.googleCastClient?.pause()
                    self.playbackState = .paused
                } else {
                    self.playbackState = .playing
                }
            case .paused:
                if self.wasPlaying {
                    self.pendingPauseRequest = false
                }
                self.playbackState = .paused
            case .buffering:
                self.playbackState = .loading
            case .loading:
                self.playbackState = .loading
            case .unknown:
                self.playbackState = .idle
            @unknown default:
                break
            }
            
            if duration > 0 {
                let position = DLNACastPositionInfo(currentTime: currentTime, duration: duration)
                self.lastPosition = position
                self.enumerateDelegates { $0.castManager(self, positionDidUpdate: position) }
            }
        }
    }
}

// MARK: - GCKLoggerDelegate

extension DLNACastManager: GCKLoggerDelegate {
    public func logMessage(_ message: String, at level: GCKLoggerLevel, fromFunction function: String, location: String) {
//        DLog.info("【GoogleCastSDK】[\(level.rawValue)] \(function) - \(message)")
    }
}
