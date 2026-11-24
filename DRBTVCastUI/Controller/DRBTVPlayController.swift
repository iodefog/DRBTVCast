//
//  DRBTVPlayController.swift
//  DramaBox
//
//  Created by LHL on 2026/6/25.
//

import AVFoundation
import DRBTVCast
import SnapKit
import UIKit

class DRBTVPlayController: UIViewController {

    private lazy var naviBar: DRBTVNaviBar = DRBTVNaviBar()
    private lazy var baseContentView: UIView = UIView()

    var bookId: String? {
        set { DRBTVPlayManager.shared.bookId = newValue }
        get { DRBTVPlayManager.shared.bookId }
    }
    var bookName: String? {
        set { DRBTVPlayManager.shared.bookName = newValue }
        get { DRBTVPlayManager.shared.bookName }
    }
    var albumModel: DRBAlbumModel? {
        set { DRBTVPlayManager.shared.albumModel = newValue }
        get { DRBTVPlayManager.shared.albumModel }
    }
    var chapterId: String? {
        set { DRBTVPlayManager.shared.chapterId = newValue }
        get { DRBTVPlayManager.shared.chapterId }
    }
    var currencyPlaySource: String? {
        set { DRBTVPlayManager.shared.currencyPlaySource = newValue }
        get { DRBTVPlayManager.shared.currencyPlaySource }
    }
    var currencyPlaySourceName: String? {
        set { DRBTVPlayManager.shared.currencyPlaySourceName = newValue }
        get { DRBTVPlayManager.shared.currencyPlaySourceName }
    }
    var isRestoring = false
    private var previousBookId: String?
    
    var chapterList: [DRBTVChapterModel] {
        set {
            DRBTVPlayManager.shared.chapterList = newValue
        }
        get {
            return DRBTVPlayManager.shared.chapterList
        }
    }
    
    var currentChapterIndex: Int {
        set {
            DRBTVPlayManager.shared.currentChapterIndex = newValue
        }
        get {
            return DRBTVPlayManager.shared.currentChapterIndex
        }
    }
    
    private let tvPopupTransitionDelegate = DRBTVPopupTransitioningDelegate()
    
    private weak var currentEpisodesVC: DRBAlbumDetailEpisodesController?

    var currentSpeedRate: Float = DRBPlayerManager.recordRate
    private var lastUserActionTime: TimeInterval = 0
    
    private var lastReportedChapterId: String?
    private var lastReportedProgress: Int64 = -1
    
    private lazy var tvPlayView: DRBTVPlayView = {
        let view = DRBTVPlayView()
        view.delegate = self
        return view
    }()
    
    // Half floating views
    private lazy var speedListView: DRBHalfFloatingView = {
        let view = DRBHalfFloatingView()
        view.layoutStyle = .textSelection
        view.selectedImage = R.image.album_floating_red_arrow()
        view.maskViewColor = UIColor.black.withAlphaComponent(0.6)
        view.delegate = self
        return view
    }()
    
    private lazy var qualityListView: DRBHalfFloatingView = {
        let view = DRBHalfFloatingView()
        view.layoutStyle = .textSelection
        view.selectedImage = R.image.album_floating_red_arrow()
        view.maskViewColor = UIColor.black.withAlphaComponent(0.6)
        view.delegate = self
        return view
    }()
    
    private lazy var customTitleContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        view.addSubview(customTitleLabel)
        view.addSubview(subtitleLabel)
        
        customTitleLabel.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.centerX.equalToSuperview()
            make.leading.greaterThanOrEqualToSuperview()
            make.trailing.lessThanOrEqualToSuperview()
        }
        
        subtitleLabel.snp.makeConstraints { make in
            make.top.equalTo(customTitleLabel.snp.bottom).offset(fitScale(2))
            make.centerX.equalToSuperview()
            make.leading.greaterThanOrEqualToSuperview()
            make.trailing.lessThanOrEqualToSuperview()
            make.bottom.equalToSuperview()
        }
        return view
    }()
    
    private lazy var customTitleLabel: UILabel = {
        let label = UILabel()
        label.font = .mediumFont(17)
        label.textColor = DRBResource.colors.text_primary_color
        label.textAlignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.8
        return label
    }()
    
    private lazy var subtitleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 10)
        label.textColor = DRBResource.colors.text_secondary_color
        label.textAlignment = .center
        label.text = Loc.shared().str_cast_casting()
        label.lineBreakMode = .byTruncatingTail
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.5
        return label
    }()
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    override func viewDidLoad() {
        self.view.backgroundColor = .black
        super.viewDidLoad()
        
        if DLNACastManager.shared.connectedDevice?.deviceType == .airplay {
            let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
            let hasAirPlay = outputs.contains(where: { $0.portType == .airPlay })
            if !hasAirPlay {
                DLNACastManager.shared.disconnect()
                DispatchQueue.main.async { [weak self] in
                    self?.navigationController?.popViewController(animated: false)
                }
                return
            }
        }
        
        setupCommonLayout()
        setupUI()

        title = ""  // Hide default title
        customTitleLabel.text = DLNACastManager.shared.connectedDevice?.friendlyName ?? "TV"
        naviBar.setRightButtonImage(DRBResource.images.tv_cast_close)
        naviBar.rightButton.addTarget(self, action: #selector(rightButtonTapped), for: .touchUpInside)
        naviBar.rightButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        
        naviBar.addSubview(customTitleContainerView)
        customTitleContainerView.snp.makeConstraints { make in
            make.centerY.equalTo(naviBar.backButton.snp.centerY)
            make.centerX.equalToSuperview()
            make.leading.greaterThanOrEqualTo(naviBar.backButton.snp.trailing).offset(fitScale(4))
            make.trailing.lessThanOrEqualTo(naviBar.rightButton.snp.leading).offset(fitScale(-4))
        }
        
        // Bind controller to manager and make manager delegate for DLNA
        DRBTVPlayManager.shared.activeController = self
        DRBTVPlayManager.shared.startManager()
        
        if isRestoring {
            
            updateMediaInfoUI()
            updateUIForState()
        } else if let bookId = self.bookId, let chapterId = self.chapterId {
            // If the same drama is already casting, just restore UI without re-casting
            let isSameDrama =
            (previousBookId == bookId)
            && DLNACastManager.shared.connectedDevice != nil
            && (DLNACastManager.shared.playbackState == .playing
                || DLNACastManager.shared.playbackState == .paused
                || DLNACastManager.shared.playbackState == .loading)
            
            if isSameDrama {
                DLog.info("[DRBTVPlayController] Same drama is already casting, restoring UI only")
                updateMediaInfoUI()
                updateUIForState()
            } else {
                DRBTVPlayManager.shared.playChapter(chapterId: chapterId, chapterIndex: currentChapterIndex)
            }
        } else if let media = DLNACastManager.shared.currentMedia,
                  DLNACastManager.shared.playbackState == .idle {
            DLog.info("[DRBTVPlayController] 设置投屏链接(已有): \(media.mediaURL)")
            DLNACastManager.shared.cast(media: media)
        }
        
        updateMediaInfoUI()
        updateVolumeControlsState()
        
        let edgePan = UIScreenEdgePanGestureRecognizer(
            target: self, action: #selector(handleEdgePan(_:)))
        edgePan.edges = .left
        self.view.addGestureRecognizer(edgePan)
        
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleDeviceDidChange),
            name: NSNotification.Name("DLNACastConnectedDeviceDidChangeNotification"), object: nil)
        
        var currentlyPlayingQuality = 720
        if let media = DLNACastManager.shared.currentMedia {
            let activeCdnList = DRBTVPlayManager.shared.chapterList.first(where: {
                $0.chapterId == DRBTVPlayManager.shared.chapterId
            })?.cdnList
            if let activeCdnList = activeCdnList,
               let matchedQuality = activeCdnList.flatMap({ $0.videoPathList ?? [] }).first(where: {
                   $0.videoPath == media.mediaURL
               })?.quality {
                currentlyPlayingQuality = matchedQuality
            }
        } else if DRBQualityCDNHelper.shared.currentPlayingQuality != 0 {
            currentlyPlayingQuality = DRBQualityCDNHelper.shared.currentPlayingQuality
        }
        let qualityTitle = "\(currentlyPlayingQuality)p"
        tvPlayView.updateQualityTitle(qualityTitle)
        
        let rate = speedRateList.first(where: { abs($0 - currentSpeedRate) < 0.01 }) ?? currentSpeedRate
        let rateStr: String
        if rate == Float(Int(rate)) {
            rateStr = String(format: "%.1f", rate)
        } else {
            rateStr = "\(rate)"
        }
        let speedTitle = "\(rateStr)x"
        tvPlayView.updateSpeedTitle(speedTitle)
        DLNACastManager.shared.setPlayRate(currentSpeedRate)
        
        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification, object: nil)
        DRBNotify.subscribeSuccess.addObserver(observer: self, selector: #selector(subscribeSuccess))
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        DRBTVPlayManager.shared.activeController = self
        DRBTVPlayManager.shared.startManager()
        updateUIForState()
        updateVolumeControlsState()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.reportReadProgress()
        if DRBTVPlayManager.shared.activeController == self {
            DRBTVPlayManager.shared.activeController = nil
        }
    }

    private var isWaitingForAirPlayDisconnect = false
    private var isAirPlayPickerVisible = false
    private var isAudioInterrupted = false
    
    @objc private func rightButtonTapped() {
        if DLNACastManager.shared.connectedDevice?.deviceType == .airplay {
            isWaitingForAirPlayDisconnect = true
            isAirPlayPickerVisible = true
            DLNACastManager.shared.showSystemAirPlayPicker()
            
            NotificationCenter.default.removeObserver(
                self, name: Notification.Name("DLNACastAirPlayPickerDidDismiss"), object: nil)
            NotificationCenter.default.addObserver(
                self, selector: #selector(handleAirPlayPickerDismiss(_:)),
                name: Notification.Name("DLNACastAirPlayPickerDidDismiss"), object: nil)
            
            NotificationCenter.default.removeObserver(
                self, name: AVAudioSession.routeChangeNotification, object: nil)
            
            NotificationCenter.default.addObserver(
                self, selector: #selector(handleAudioInterruption(_:)),
                name: AVAudioSession.interruptionNotification, object: nil)
            
            NotificationCenter.default.addObserver(
                self, selector: #selector(handleAudioRouteChange(_:)),
                name: AVAudioSession.routeChangeNotification, object: nil)
        } else {
            performDisconnectAndExit()
        }
    }
    
    @objc private func handleAirPlayPickerDismiss(_ notification: Notification) {
        guard isWaitingForAirPlayDisconnect else { return }
        isAirPlayPickerVisible = false
        NotificationCenter.default.removeObserver(
            self, name: Notification.Name("DLNACastAirPlayPickerDidDismiss"), object: nil)
        
        checkAirPlayStatusAndExitIfNeeded()
        
        // Wait a brief moment to let AVAudioSession route change complete if user disconnected and it was delayed
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self, self.isWaitingForAirPlayDisconnect, !self.isAirPlayPickerVisible else {
                return
            }
            self.checkAirPlayStatusAndExitIfNeeded()
        }
    }
    
    @objc private func handleAudioInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        if type == .began {
            isAudioInterrupted = true
        } else if type == .ended {
            isAudioInterrupted = false
            // Check again in case AirPlay was disconnected during the interruption
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.checkAirPlayStatusAndExitIfNeeded()
            }
        }
    }
    
    @objc private func handleAudioRouteChange(_ notification: Notification) {
        guard isWaitingForAirPlayDisconnect else { return }
        if isAudioInterrupted { return }
        
        // If the system picker is still visible, we don't want to abruptly exit the page yet.
        // We will handle the exit when the picker dismisses.
        if isAirPlayPickerVisible {
            return
        }
        checkAirPlayStatusAndExitIfNeeded()
    }
    
    private func checkAirPlayStatusAndExitIfNeeded() {
        if isAirPlayPickerVisible { return }
        
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        let hasAirPlay = outputs.contains(where: { $0.portType == .airPlay })
        
        if !hasAirPlay || DLNACastManager.shared.connectedDevice == nil {
            isWaitingForAirPlayDisconnect = false
            NotificationCenter.default.removeObserver(
                self, name: AVAudioSession.routeChangeNotification, object: nil)
            NotificationCenter.default.removeObserver(
                self, name: AVAudioSession.interruptionNotification, object: nil)
            performDisconnectAndExit()
        }
    }
    
    private func performDisconnectAndExit() {
        DLNACastManager.shared.disconnect()
        DRBTVPlayManager.shared.reset()
        
        if let nav = self.navigationController {
            let vcs = nav.viewControllers
            if let searchIndex = vcs.firstIndex(where: { $0 is DRBTVSearchController }), searchIndex > 0 {
                nav.popToViewController(vcs[searchIndex - 1], animated: true)
                return
            }
            for vc in vcs.reversed() {
                if !(vc is DRBTVPlayController) && !(vc is DRBTVSearchController) {
                    nav.popToViewController(vc, animated: true)
                    return
                }
            }
        }
        currentEpisodesVC?.dismiss(animated: false, completion: nil)
        self.navigationController?.popViewController(animated: true)
    }
    
    func exitTVCastFlow() {
        performDisconnectAndExit()
    }
    
    @objc private func backButtonAction() {
        if let nav = self.navigationController {
            let vcs = nav.viewControllers
            for (index, vc) in vcs.enumerated().reversed() {
                if String(describing: type(of: vc)).contains("Album") {
                    if index > 0 {
                        nav.popToViewController(vcs[index - 1], animated: true)
                        return
                    }
                }
            }
        }
        navigationController?.popViewController(animated: true)
    }

    @objc private func handleEdgePan(_ gesture: UIScreenEdgePanGestureRecognizer) {
        if gesture.state == .began {
            backButtonAction()
        }
    }

    private func setupCommonLayout() {
        view.addSubview(naviBar)
        naviBar.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top)
            make.leading.trailing.equalToSuperview()
            make.height.equalTo(44)
        }
        naviBar.backButton.addTarget(self, action: #selector(backButtonAction), for: .touchUpInside)

        view.addSubview(baseContentView)
        baseContentView.snp.makeConstraints { make in
            make.top.equalTo(naviBar.snp.bottom)
            make.leading.trailing.bottom.equalToSuperview()
        }
    }

    private func setupUI() {
        baseContentView.addSubview(tvPlayView)
        tvPlayView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    private func changeTheme() {
        naviBar.setRightButtonImage(DRBResource.images.tv_cast_close)
        tvPlayView.changeTheme()
        customTitleLabel.textColor = DRBResource.colors.text_primary_color
        subtitleLabel.textColor = DRBResource.colors.text_secondary_color
    }
    
    private func updateUIForState() {
        let state = DLNACastManager.shared.playbackState
        let isPlaying = (state == .playing || state == .loading || state == .idle)
        tvPlayView.updatePlayState(isPlaying: isPlaying, isLoading: state == .loading)
        
        if let pos = DLNACastManager.shared.lastPosition {
            tvPlayView.updateProgress(currentTime: pos.currentTime, duration: pos.duration)
        }
    }
    
    private func updateVolumeControlsState() {
        let isAirPlay = (DLNACastManager.shared.connectedDevice?.deviceType == .airplay)
        tvPlayView.setVolumeControlsEnabled(!isAirPlay)
    }
    
    // MARK: - UI Callback updates from DRBTVPlayManager
    func updateUIForMediaInfo(chapterId: String?, chapterIndex: Int) {
        self.tvPlayView.updateProgress(currentTime: 0, duration: 0)
        
        // 统一先计算当前客观的集数（索引 + 1）
        let currentEpisodeNumber = chapterIndex + 1
        
        if chapterIndex < chapterList.count {
            let chapter = chapterList[chapterIndex]
            let displayEpisode = currentEpisodeNumber
            
            self.tvPlayView.updateMediaInfo(
                title: chapter.chapterName,
                episode: Loc.shared().str_episode_alone_progress(displayEpisode)
            )
        } else {
            self.tvPlayView.updateMediaInfo(
                title: "DramaBox",
                episode: Loc.shared().str_episode_alone_progress(currentEpisodeNumber)
            )
        }
    }
    
    func updateEpisodesListView() {
        // Can trigger custom episodes selection popup reload if visible and necessary
    }
    
    private var stateSyncTimer: Timer?

    func updatePlaybackStateUI(state: DLNACastPlaybackState) {
        if Date().timeIntervalSince1970 - lastUserActionTime < 1.5 {
            // Ignore immediate changes from TV to avoid flicker, BUT ensure we sync later
            stateSyncTimer?.invalidate()
            stateSyncTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.forceSyncPlaybackState()
                }
            }
            return
        }
        
        forceSyncPlaybackState()
    }
    
    private func forceSyncPlaybackState() {
        let state = DLNACastManager.shared.playbackState
        let isPlaying = (state == .playing || state == .loading || state == .idle)
        self.tvPlayView.updatePlayState(isPlaying: isPlaying, isLoading: state == .loading)
        
        if let pos = DLNACastManager.shared.lastPosition {
            self.tvPlayView.updateProgress(currentTime: pos.currentTime, duration: pos.duration)
        }
        
        switch state {
        case .playing:
            self.reportReadProgress()
        case .idle, .stopped:
            break
        default:
            break
        }
    }
    
    func updateProgressUI(position: DLNACastPositionInfo) {
        self.tvPlayView.updateProgress(currentTime: position.currentTime, duration: position.duration)
    }
    
    func handleError(_ error: DLNACastError) {
        // Custom error UI handling if needed
    }
    
    func updateMediaInfoUI() {
        if let media = DLNACastManager.shared.currentMedia {
            let epText =
            media.episode != nil ? Loc.shared().str_episode_alone_progress(media.episode!) : nil
            self.tvPlayView.updateMediaInfo(title: media.title, episode: epText)
        }
    }
}

// MARK: - DRBTVPlayViewDelegate
extension DRBTVPlayController: DRBTVPlayViewDelegate {
    
    func tvPlayViewDidClickQuality() {
        var activeCdnList: [DRBTVCDNModel]?
        let currentIndex = DRBTVPlayManager.shared.currentChapterIndex
        if currentIndex < chapterList.count, let chapterId = chapterList[currentIndex].chapterId {
            activeCdnList =
            DRBTVPlayManager.shared.videoPathsCache[chapterId] ?? chapterList[currentIndex].cdnList
        } else if let chapterId = self.chapterId {
            activeCdnList = DRBTVPlayManager.shared.videoPathsCache[chapterId]
        }
        
        let qualityModels =
        DRBQualityCDNHelper.shared.getVideoQualitySelectList(cdnList: activeCdnList) ?? []
        
        var items: [DRBHalfFloatingViewModel] = []
        var selectedIndex = 0
        var currentlyPlayingQuality = DRBQualityCDNHelper.shared.currentSelectedQuality
        if let media = DLNACastManager.shared.currentMedia,
           let cdnList = activeCdnList,
           let matchedQuality = cdnList.flatMap({ $0.videoPathList ?? [] }).first(where: {
               $0.videoPath == media.mediaURL
           })?.quality {
            currentlyPlayingQuality = matchedQuality
        } else if DRBQualityCDNHelper.shared.currentPlayingQuality != 0 {
            currentlyPlayingQuality = DRBQualityCDNHelper.shared.currentPlayingQuality
        }
        
        let filteredModels = qualityModels.filter { ($0.quality ?? 0) > 0 }
        for (idx, model) in filteredModels.enumerated() {
            let q = model.quality ?? 0
            let isSel = (q == currentlyPlayingQuality)
            
            if isSel {
                selectedIndex = idx
            }
            items.append(
                DRBHalfFloatingViewModel(id: "\(q)", title: "\(q)p", isSelected: isSel))
        }
        
        if items.isEmpty {
            let qualities = [1080, 720, 540, 360, 144]
            for (idx, q) in qualities.enumerated() {
                let isSel = (q == currentlyPlayingQuality)
                
                if isSel {
                    selectedIndex = idx
                }
                items.append(DRBHalfFloatingViewModel(id: "\(q)", title: "\(q)p", isSelected: isSel))
            }
        }
        qualityListView.show(
            in: self.view, showMask: true, with: items, title: Loc.shared().str_videoquality_current(),
            selectedIndex: selectedIndex, layoutStyle: .textSelection)
    }
    
    func tvPlayViewDidClickSpeed() {
        var items: [DRBHalfFloatingViewModel] = []
        var selectedIndex = 4  // default to 1.0x in speedRateList: [Float] = [3.0, 2.0, 1.5, 1.25, 1.0, 0.75]
        
        for (idx, rate) in speedRateList.enumerated() {
            let isSel = (abs(rate - currentSpeedRate) < 0.01)
            if isSel {
                selectedIndex = idx
            }
            let rateStr: String
            if rate == Float(Int(rate)) {
                rateStr = String(format: "%.1f", rate)
            } else {
                rateStr = "\(rate)"
            }
            items.append(DRBHalfFloatingViewModel(id: "\(rate)", title: "\(rateStr)x", isSelected: isSel))
        }
        
        speedListView.show(
            in: self.view, showMask: true, with: items, title: Loc.shared().str_play_speed(),
            selectedIndex: selectedIndex, layoutStyle: .textSelection)
    }
    
    func tvPlayViewDidClickEpisodes() {
        let episodesVC = DRBAlbumDetailEpisodesController()
        episodesVC.delegate = self
        episodesVC.playingChapterIndex = self.currentChapterIndex
        episodesVC.showHeader = true
        episodesVC.isFromTV = true
        episodesVC.isModalInPresentation = false
        self.currentEpisodesVC = episodesVC

        let presentSheet: () -> Void = { [weak self] in
            guard let self = self else { return }
            episodesVC.modalPresentationStyle = .custom
            episodesVC.transitioningDelegate = self.tvPopupTransitionDelegate
            self.present(episodesVC, animated: true, completion: nil)
        }
        
        if let albumModel = self.albumModel {
            var detailModel = DRBTVAlbumDetailModel(albumModel: albumModel)
            if detailModel.list == nil {
                detailModel.list = albumModel.chapterList?.map { DRBTVChapterItemModel(chapter: $0) }
            }
            let albumData = DRBTVAlbumDataModel(bookId: bookId, albumData: albumModel)
            episodesVC.albumDataModel = albumData
            episodesVC.dataModel = detailModel
            presentSheet()
        } else if let bookId = self.bookId {
            #if DRB_CAST_DEMO
            var detail = DRBTVAlbumDetailModel()
            detail.list = chapterList.map { DRBTVChapterItemModel(chapter: $0) }
            episodesVC.albumDataModel = DRBTVAlbumDataModel(bookId: bookId, albumData: nil)
            episodesVC.dataModel = detail
            presentSheet()
            #else
            DRBLoadingView.show(inView: self.view, isUserInterActive: true)
            let request = DRBAlbumDetailRequestModel.albumDetailData(bookId: bookId, from: .bookAblum, needRecommend: false)
            DRBNetwork.shared.requestMappable(target: request, type: DRBTVAlbumDetailModel.self) { [weak self] result in
                guard let self = self else { return }
                DRBLoadingView.dismiss(inView: self.view)
                switch result {
                case .success(let response):
                    if var detail = response?.data {
                        if (detail.list == nil || detail.list?.isEmpty == true) && !self.chapterList.isEmpty {
                            detail.list = self.chapterList.map { DRBTVChapterItemModel(chapter: $0) }
                        }
                        let albumData = DRBTVAlbumDataModel(bookId: bookId, albumData: nil)
                        episodesVC.albumDataModel = albumData
                        episodesVC.dataModel = detail
                        presentSheet()
                    } else {
                        DRBToast.toast(text: Loc.shared().str_unavailable_try_again())
                    }
                case .failure:
                    DRBToast.toast(text: Loc.shared().str_unavailable_try_again())
                }
            }
            #endif
        } else if !self.chapterList.isEmpty {
            var detailModel = DRBTVAlbumDetailModel()
            detailModel.list = self.chapterList.map { DRBTVChapterItemModel(chapter: $0) }
            let albumData = DRBTVAlbumDataModel(bookId: nil, albumData: nil)
            episodesVC.albumDataModel = albumData
            episodesVC.dataModel = detailModel
            presentSheet()
        }
    }
    
    func tvPlayViewDidClickPlayPause() {
        lastUserActionTime = Date().timeIntervalSince1970
        let state = DLNACastManager.shared.playbackState
        let isPlaying = (state == .playing || state == .loading || state == .idle)
        if isPlaying {
            self.tvPlayView.updatePlayState(isPlaying: false)
            DLNACastManager.shared.pause()
        } else {
            self.tvPlayView.updatePlayState(isPlaying: true)
            DLNACastManager.shared.resume()
        }
        
        stateSyncTimer?.invalidate()
        stateSyncTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.forceSyncPlaybackState()
            }
        }
    }
    
    func tvPlayViewDidClickLeft() {
        if let pos = DLNACastManager.shared.lastPosition {
            let targetTime = max(0, pos.currentTime - 5)
            DLNACastManager.shared.seek(to: targetTime)
            resumeIfPaused()
        }
    }
    
    func tvPlayViewDidClickRight() {
        if let pos = DLNACastManager.shared.lastPosition {
            let targetTime = min(pos.duration, pos.currentTime + 5)
            DLNACastManager.shared.seek(to: targetTime)
            resumeIfPaused()
        }
    }
    
    func tvPlayViewDidClickUp() {
        DLNACastManager.shared.changeVolume(delta: 0.1)
    }
    
    func tvPlayViewDidClickDown() {
        DLNACastManager.shared.changeVolume(delta: -0.1)
    }
    
    func tvPlayViewSliderDidBeginEditing() {
        // Drag began
    }
    
    func tvPlayViewSliderDidEndEditing(value: Float) {
        if let pos = DLNACastManager.shared.lastPosition {
            let targetTime = TimeInterval(value) * pos.duration
            DLNACastManager.shared.seek(to: targetTime)
            resumeIfPaused()
        }
    }
    
    private func resumeIfPaused() {
        if DLNACastManager.shared.playbackState == .paused {
            self.tvPlayView.updatePlayState(isPlaying: true)
            DLNACastManager.shared.resume()
        }
    }
}

// MARK: - DRBHalfFloatingViewDelegate
extension DRBTVPlayController: DRBHalfFloatingViewDelegate {
    func didSelectItem(at index: Int, in view: DRBHalfFloatingView) {
        if view == speedListView {
            let item = speedListView.getItem(index: index)
            if let speedStr = item?.id, let speedVal = Float(speedStr) {
                currentSpeedRate = speedVal
                DRBPlayerManager.recordRate = speedVal
                DLNACastManager.shared.setPlayRate(speedVal)
                resumeIfPaused()
                if let title = item?.title {
                    tvPlayView.updateSpeedTitle(title)
                }
            }
        } else if view == qualityListView {
            let item = qualityListView.getItem(index: index)
            if let title = item?.title {
                tvPlayView.updateQualityTitle(title)
                
                // Save current playback position for resume after quality switch
                let resumeTime = DLNACastManager.shared.lastPosition?.currentTime
                
                var qualityVal: Int = 720
                if let idStr = item?.id, let parsed = Int(idStr) {
                    qualityVal = parsed
                } else {
                    let digits = title.filter { $0.isNumber }
                    if let parsed = Int(digits) {
                        qualityVal = parsed
                    }
                }
                DRBQualityCDNHelper.shared.currentSelectedQuality = qualityVal
                
                if bookId != nil {
                    let currentIndex = DRBTVPlayManager.shared.currentChapterIndex
                    if currentIndex < chapterList.count {
                        let chapter = chapterList[currentIndex]
                        if let chapterId = chapter.chapterId {
                            DRBTVPlayManager.shared.playChapter(
                                chapterId: chapterId, chapterIndex: currentIndex, resumePosition: resumeTime)
                            resumeIfPaused()
                        }
                    } else if let chapterId = self.chapterId {
                        DRBTVPlayManager.shared.playChapter(
                            chapterId: chapterId, chapterIndex: currentIndex, resumePosition: resumeTime)
                        resumeIfPaused()
                    }
                } else {
                    let currentIndex = currentChapterIndex
                    if currentIndex < chapterList.count {
                        let chapter = chapterList[currentIndex]
                        currentChapterIndex = currentIndex
                        if let videoPath = DRBQualityCDNHelper.shared.getVideoPath(model: chapter) {
                            DLog.info("[DRBTVPlayController] 设置投屏链接: \(videoPath)")
                            let media = DLNACastMediaInfo(
                                mediaURL: videoPath,
                                title: chapter.chapterName ?? "DramaBox",
                                episode: chapter.chapterIndex
                            )
                            DLNACastManager.shared.currentMedia = media
                            DLNACastManager.shared.cast(media: media, resumePosition: resumeTime)
                            updateMediaInfoUI()
                            resumeIfPaused()
                        }
                    }
                }
            }
        }
    }
    
    func willShowHalfFloatingView(_ view: DRBHalfFloatingView) {}
    func didShowHalfFloatingView(_ view: DRBHalfFloatingView) {}
    func willHideHalfFloatingView(_ view: DRBHalfFloatingView) {}
    func didHideHalfFloatingView(_ view: DRBHalfFloatingView) {}
    func didSelectItemSwitchButton(at index: Int, in view: DRBHalfFloatingView, isOn: Bool) {}
    func didSelectItemReportButton(at index: Int, in view: DRBHalfFloatingView) {}
}

// MARK: - DLNACastManagerDelegate
extension DRBTVPlayController: DLNACastManagerDelegate {
    func castManager(_ manager: DLNACastManager, didDiscoverDevice device: DLNADevice) {
        DLog.info("DRBTVPlayController didDiscoverDevice: \(device.friendlyName)")
    }
    func castManager(_ manager: DLNACastManager, didLoseDevice device: DLNADevice) {
        DLog.info("DRBTVPlayController didLoseDevice: \(device.friendlyName)")
    }
    func castManager(_ manager: DLNACastManager, playbackStateDidChange state: DLNACastPlaybackState){
        DLog.info("DRBTVPlayController playbackStateDidChange: \(state)")
    }
    func castManager(_ manager: DLNACastManager, positionDidUpdate position: DLNACastPositionInfo) {
        DLog.debug(
            "DRBTVPlayController positionDidUpdate: \(position.currentTime) / \(position.duration)")
    }
    func castManagerDidFinishPlayback(_ manager: DLNACastManager) {
        DLog.info("DRBTVPlayController castManagerDidFinishPlayback")
    }
    func castManager(_ manager: DLNACastManager, didEncounterError error: DLNACastError) {
        DLog.error("DRBTVPlayController didEncounterError: \(error)")
    }
}

// MARK: - DRBAlbumDetailEpisodesControllerDelegate
extension DRBTVPlayController: DRBAlbumDetailEpisodesControllerDelegate {
    func didSelectedChapter(_ controller: DRBAlbumDetailEpisodesController, chapterModel: DRBTVChapterItemModel) {
        guard let index = chapterModel.chapterIndex else { return }
        controller.dismiss(animated: true) { [weak self] in
            guard let self = self else { return }

            if let bookId = self.bookId {
                if let chapterId = chapterModel.chapterId {
                    DRBTVPlayManager.shared.playChapter(chapterId: chapterId, chapterIndex: index)
                    self.resumeIfPaused()
                } else {
                    DLog.info("[DRBTVPlayController] chapterId为nil, 通过chapterv2/list获取, index: \(index)")
                    self.fetchChapterIdAndPlay(bookId: bookId, chapterIndex: index)
                }
            } else {
                guard index < self.chapterList.count else { return }
                let chapter = self.chapterList[index]
                self.currentChapterIndex = index
                if let videoPath = DRBQualityCDNHelper.shared.getVideoPath(model: chapter) {
                    DLog.info("[DRBTVPlayController] 设置投屏链接: \(videoPath)")
                    let media = DLNACastMediaInfo(
                        mediaURL: videoPath,
                        title: chapter.chapterName ?? "DramaBox",
                        episode: chapter.chapterIndex
                    )
                    DLNACastManager.shared.currentMedia = media
                    DLNACastManager.shared.cast(media: media)
                    self.updateMediaInfoUI()
                    self.resumeIfPaused()
                }
            }
        }
    }

    private func fetchChapterIdAndPlay(bookId: String, chapterIndex: Int) {
        #if DRB_CAST_DEMO
        DRBToast.toast(text: Loc.shared().str_unavailable_try_again())
        #else
        DRBLoadingView.show(inView: self.view, isUserInterActive: true)
        let request = DRBAlbumRequestModel.albumChapterList(bookId: bookId)
        DRBNetwork.shared.requestMappable(target: request, type: DRBTVAlbumDetailModel.self) { [weak self] result in
            guard let self = self else { return }
            DRBLoadingView.dismiss(inView: self.view)
            switch result {
            case .success(let response):
                guard let list = response?.data?.list,
                      let targetItem = list.first(where: { $0.chapterIndex == chapterIndex }),
                      let chapterId = targetItem.chapterId else {
                    DLog.error("[DRBTVPlayController] chapterv2/list未找到index=\(chapterIndex)的chapterId")
                    DRBToast.toast(text: Loc.shared().str_unavailable_try_again())
                    return
                }
                // 更新manager中对应位置的chapterId，避免下次重复请求
                if chapterIndex < self.chapterList.count {
                    self.chapterList[chapterIndex].chapterId = chapterId
                }
                DRBTVPlayManager.shared.playChapter(chapterId: chapterId, chapterIndex: chapterIndex)
                self.resumeIfPaused()
            case .failure:
                DLog.error("[DRBTVPlayController] chapterv2/list请求失败")
                DRBToast.toast(text: Loc.shared().str_unavailable_try_again())
            }
        }
        #endif
    }
}

// MARK: - TV Cast Parameters Config
public struct DRBTVCastParams {
    public var bookId: String?
    public var bookName: String?
    public var albumModel: DRBAlbumModel?
    public var chapterId: String?
    public var currencyPlaySource: String?
    public var currencyPlaySourceName: String?
    public var chapterList: [DRBTVChapterModel] = []
    public var currentChapterIndex: Int = 0

    public init(bookId: String? = nil, bookName: String? = nil, albumModel: DRBAlbumModel? = nil,
                chapterId: String? = nil, currencyPlaySource: String? = nil,
                currencyPlaySourceName: String? = nil, chapterList: [DRBTVChapterModel] = [],
                currentChapterIndex: Int = 0) {
        self.bookId = bookId
        self.bookName = bookName
        self.albumModel = albumModel
        self.chapterId = chapterId
        self.currencyPlaySource = currencyPlaySource
        self.currencyPlaySourceName = currencyPlaySourceName
        self.chapterList = chapterList
        self.currentChapterIndex = currentChapterIndex
    }
}

extension DRBTVPlayController {
    public func setup(params: DRBTVCastParams) {
        self.previousBookId = DRBTVPlayManager.shared.bookId
        self.bookId = params.bookId
        self.bookName = params.bookName
        self.albumModel = params.albumModel
        self.chapterId = params.chapterId
        self.currencyPlaySource = params.currencyPlaySource
        self.currencyPlaySourceName = params.currencyPlaySourceName
        self.chapterList = params.chapterList
        self.currentChapterIndex = params.currentChapterIndex
    }
    
    func pushToMembershipForTVCast() {
        #if DRB_CAST_DEMO
        DRBToast.toast(text: Loc.shared().str_cast_toast_notmember())
        #else
        var dic = [String: Any]()
        dic["channel"] = MemberShipRootChannelType.dramaListSubscribeNow.rawValue
        dic["chapterId"] = DRBTVPlayManager.shared.chapterId ?? chapterId
        dic["chapterIndex"] = currentChapterIndex
        dic["bookId"] = bookId
        dic["bookName"] = bookName
        dic["currencyPlaySource"] = currencyPlaySource
        dic["currencyPlaySourceName"] = currencyPlaySourceName
        
        let path = memberShipVCPath.appendParamsWithDict(dict: dic)
        navigator.open(path, context: self)
        #endif
    }
    
    @objc private func handleDeviceDidChange() {
        if DLNACastManager.shared.connectedDevice == nil {
            if isAirPlayPickerVisible {
                return
            }
            autoExitCastingPage()
        }
    }
    
    func autoExitCastingPage() {
        self.reportReadProgress()
        // Disconnect and reset
        DLNACastManager.shared.disconnect()
        DRBTVPlayManager.shared.reset()
        
        if let nav = self.navigationController {
            let vcs = nav.viewControllers
            if let searchIndex = vcs.firstIndex(where: { $0 is DRBTVSearchController }), searchIndex > 0 {
                nav.popToViewController(vcs[searchIndex - 1], animated: true)
                return
            }
            for vc in vcs.reversed() {
                if !(vc is DRBTVPlayController) && !(vc is DRBTVSearchController) {
                    nav.popToViewController(vc, animated: true)
                    return
                }
            }
        }
        currentEpisodesVC?.dismiss(animated: false, completion: nil)
        self.navigationController?.popViewController(animated: true)
    }
    
    @objc private func appDidEnterBackground() {
        self.reportReadProgress()
    }
    
    func reportReadProgress() {
        #if DRB_CAST_DEMO
        #else
        guard let bookId = self.bookId, !bookId.isEmpty else { return }
        
        let manager = DRBTVPlayManager.shared
        let chId = manager.chapterId ?? self.chapterId
        let chIndex = manager.currentChapterIndex
        
        let position = DLNACastManager.shared.lastPosition?.currentTime ?? 0
        let progressSec = Int64(position)
        
        if lastReportedChapterId == chId && lastReportedProgress == progressSec {
            return
        }
        lastReportedChapterId = chId
        lastReportedProgress = progressSec
        
        let isBottom = (self.albumModel?.bookCategory == .free) ? 1 : 0
        
        let request = DRBChapterRequest.readUpdate(
            bookId: bookId,
            chapterId: chId,
            chapterIndex: chIndex,
            isBottomBook: isBottom,
            interactionTipFlag: nil,
            sectionId: nil,
            isLastSectionId: nil,
            viewingDuration: progressSec
        )
        
        DRBNetwork.shared.requestMappable(target: request, type: DRBReadUpdateModel.self) { result in
            switch result {
            case .success:
                DLog.info(
                    "[DRBTVPlayController] readUpdate success for bookId=\(bookId), chapter=\(chIndex), progress=\(progressSec)s"
                )
                DRBNotify.readUpdate(bookId, chIndex).notify()
            case .failure(let error):
                DLog.error("[DRBTVPlayController] readUpdate failed: \(error)")
            }
        }
        #endif
    }
    
    func updateQualityTitleUI(actualQuality: Int) {
        let title = "\(actualQuality)p"
        tvPlayView.updateQualityTitle(title)
    }
    
    @objc private func subscribeSuccess() {
        if let downloadType = DRBConfig.downloadType {
            switch downloadType {
            case .download:
                self.resumeCastingAfterSubscribe()
            case .goPay, .showToast:
                self.unlockAndProceed()
            }
        } else {
            self.resumeCastingAfterSubscribe()
        }
    }
    
    private func resumeCastingAfterSubscribe() {
        let manager = DRBTVPlayManager.shared
        let index = manager.currentChapterIndex
        let chId = manager.chapterId ?? self.chapterId
        manager.playChapter(chapterId: chId, chapterIndex: index)
    }
    
    private func unlockAndProceed() {
        #if DRB_CAST_DEMO
        resumeCastingAfterSubscribe()
        #else
        guard let bookId = self.bookId else { return }
        let manager = DRBTVPlayManager.shared
        let chId = manager.chapterId ?? self.chapterId
        let index = manager.currentChapterIndex
        
        let target = DRBAlbumRequestModel.unlock(
            autoPay: DRBConfig.autoPay,
            bookId: bookId,
            chapterId: chId,
            confirmPay: false,
            currencyPlaySource: self.currencyPlaySource ?? "",
            currencyPlaySourceName: self.currencyPlaySourceName ?? "",
            hintName: "",
            hintType: "",
            index: index,
            lastChapterUtime: nil,
            locationId: nil,
            queryKeyword: "",
            source: "",
            unLockType: nil,
            vip: nil,
            bookCategory: self.albumModel?.bookCategory,
            alreadyViewedAdNums: nil,
            coinsExchangeRate: nil,
            coinsExchangeDays: nil,
            fromShare: nil,
            interactionChapter: nil,
            bookPos: nil
        )

        DRBLoadingView.show(inView: self.view, isUserInterActive: true)
        DRBNetwork.shared.requestMappable(target: target, type: DRBAlbumUnlockModel.self) { [weak self] result in
            guard let self = self else { return }
            DRBLoadingView.dismiss(inView: self.view)
            
            switch result {
            case .success(let response):
                if let data = response?.data {
                    DRBConfig.setOfflineDownloadInfo(data.offlineDownloadInfo)
                    DRBConfig.vipQualityType = data.vipQualityType
                    if DRBConfig.downloadType == .download {
                        self.resumeCastingAfterSubscribe()
                    } else {
                        DRBToast.toast(text: Loc.shared().str_playdownloadvideo_fail())
                    }
                } else {
                    DRBToast.toast(text: Loc.shared().str_cast_fail_tryagain())
                }
            case .failure:
                DRBToast.toast(text: Loc.shared().str_cast_fail_tryagain())
            }
        }
        #endif
    }
}

class DRBTVPopupPresentationController: UIPresentationController {
    private lazy var dimmingView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissController))
        view.addGestureRecognizer(tap)
        return view
    }()
    
    @objc private func dismissController() {
        presentedViewController.dismiss(animated: true, completion: nil)
    }
    
    override func presentationTransitionWillBegin() {
        guard let containerView = containerView else { return }
        dimmingView.frame = containerView.bounds
        dimmingView.alpha = 0
        containerView.insertSubview(dimmingView, at: 0)
        
        presentedViewController.transitionCoordinator?.animate(alongsideTransition: { _ in
            self.dimmingView.alpha = 1
        }, completion: nil)
    }
    
    override func dismissalTransitionWillBegin() {
        presentedViewController.transitionCoordinator?.animate(alongsideTransition: { _ in
            self.dimmingView.alpha = 0
        }, completion: nil)
    }
    
    override func containerViewWillLayoutSubviews() {
        super.containerViewWillLayoutSubviews()
        guard let containerView = containerView else { return }
        dimmingView.frame = containerView.bounds
        
        // For TV cast we want top 322px
        let topOffset = fitScale(322)
        let height = containerView.bounds.height - topOffset
        presentedView?.frame = CGRect(x: 0, y: topOffset, width: containerView.bounds.width, height: height)
        
        presentedView?.layer.cornerRadius = 15
        presentedView?.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        presentedView?.layer.masksToBounds = true
    }
}

class DRBTVPopupTransitioningDelegate: NSObject, UIViewControllerTransitioningDelegate {
    func presentationController(forPresented presented: UIViewController, presenting: UIViewController?, source: UIViewController) -> UIPresentationController? {
        return DRBTVPopupPresentationController(presentedViewController: presented, presenting: presenting)
    }
}
