//
//  DRBTVMananger.swift
//  DramaBox
//
//  Created by LHL on 2026/6/25.
//

import Foundation
import DRBTVCast

@MainActor
class DRBTVPlayManager: NSObject, DLNACastManagerDelegate {
    static let shared = DRBTVPlayManager()
    
    var bookId: String? {
        didSet {
            if oldValue != bookId {
                videoPathsCache.removeAll()
                lastPreloadedIndex = -1
            }
        }
    }
    var bookName: String?
    var albumModel: DRBAlbumModel?
    var chapterId: String?
    var currentChapterIndex: Int = 0
    var chapterList: [DRBTVChapterModel] = []
    
    var currencyPlaySource: String?
    var currencyPlaySourceName: String?
    
    var videoPathsCache: [String: [DRBTVCDNModel]] = [:]
    private var lastPreloadedIndex: Int = -1
    
    private var playDurationAccumulator: TimeInterval = 0
    private var lastPlaybackStateChangeTime: Date?
    
    private var isShowingErrorAlert = false
    
    private func showConnectionErrorAlert() {
        guard !isShowingErrorAlert else { return }
        isShowingErrorAlert = true
        #if DRB_CAST_DEMO
        DRBToast.toast(text: Loc.shared().str_cast_fail_tryagain())
        #else
        let okAction = DRBAlertViewAction(title: Loc.shared().str_ok(), style: .reColorButton()) { [weak self] _ in
            DRBAlertManager.shared.hide()
            guard let self = self else { return }
            self.isShowingErrorAlert = false
        }
        let alert = DRBNormalAlert(title: nil, message: Loc.shared().str_cast_fail_tryagain(), actions: [okAction])
        DRBAlertManager.shared.showNormalAlert(alertType: .deleteConfirm, view: alert)
        #endif
    }
    
    private func reportPlayDurationAndReset() {
        if let startTime = lastPlaybackStateChangeTime {
            let elapsed = Date().timeIntervalSince(startTime)
            playDurationAccumulator += elapsed
            lastPlaybackStateChangeTime = nil
        }
        
        if playDurationAccumulator > 0, let bookId = bookId, let oldChapterId = chapterId {
            var map = [String: Any]()
            map["book_id"] = bookId
            map["chapter_id"] = oldChapterId
            map["from"] = "投屏"
            map["duration"] = Int(playDurationAccumulator)
            #if !DRB_CAST_DEMO
            DRBSensorsHelper.track("playDuration", withProperties: map)
            #endif
            DLog.info("playDuration事件投屏上报: map: \(map)")
        }
        
        playDurationAccumulator = 0
        lastPlaybackStateChangeTime = nil
    }
    
    func reset() {
        reportPlayDurationAndReset()
        
        isShowingErrorAlert = false
        bookId = nil
        bookName = nil
        albumModel = nil
        chapterId = nil
        currentChapterIndex = 0
        chapterList = []
        currencyPlaySource = nil
        currencyPlaySourceName = nil
        videoPathsCache.removeAll()
        lastPreloadedIndex = -1
    }
    
    weak var activeController: DRBTVPlayController?
    
    override init() {
        super.init()
    }
    
    func startManager() {
        DLNACastManager.shared.addDelegate(self)
    }
    
    func playChapter(chapterId: String?, chapterIndex: Int, resumePosition: TimeInterval? = nil) {
        guard let bookId = bookId, let chapterId = chapterId else { return }
        
        activeController?.reportReadProgress()
        reportPlayDurationAndReset()
        
        DLNACastManager.shared.prepareForNewCast()
        
        self.chapterId = chapterId
        self.currentChapterIndex = chapterIndex
        
        // Report videoPlay for the new chapter
        var map = [String: Any]()
        map["book_id"] = bookId
        map["chapter_id"] = chapterId
        map["from"] = "投屏"
        #if !DRB_CAST_DEMO
        DRBSensorsHelper.track("videoPlay", withProperties: map)
        #endif
        DLog.info("videoPlay事件投屏上报: map: \(map)")
        
        activeController?.updateUIForMediaInfo(chapterId: chapterId, chapterIndex: chapterIndex)
        
        if let cachedCDNs = videoPathsCache[chapterId] {
            castWithCDNList(cachedCDNs, chapterId: chapterId, chapterIndex: chapterIndex, resumePosition: resumePosition)
            preloadNextChapters(from: chapterIndex)
        } else {
            if let activeVC = activeController {
                DRBLoadingView.show(inView: activeVC.view, isUserInterActive: true)
            }
            
            var targetChapterIds: [String: String] = [:]
            targetChapterIds["\(chapterIndex)"] = chapterId
            if chapterIndex < chapterList.count {
                for i in 1...2 {
                    let nextIndex = chapterIndex + i
                    if nextIndex < chapterList.count {
                        if let nextId = chapterList[nextIndex].chapterId {
                            targetChapterIds["\(nextIndex)"] = nextId
                        }
                    }
                }
            }
            
            requestVideoPaths(chapterIds: targetChapterIds) { [weak self] in
                guard let self = self else { return }
                if let activeVC = self.activeController {
                    DRBLoadingView.dismiss(inView: activeVC.view)
                }
                if let cachedCDNs = self.videoPathsCache[chapterId] {
                    self.castWithCDNList(cachedCDNs, chapterId: chapterId, chapterIndex: chapterIndex, resumePosition: resumePosition)
                } else {
                    DRBToast.toast(text: Loc.shared().str_cast_fail_tryagain())
                    DispatchQueue.main.async {
                        DLNACastManager.shared.stop()
                    }
                }
            }
        }
    }
    
    private func preloadNextChapters(from index: Int) {
        var targetChapters: [String: String] = [:]
        for i in 1...2 {
            let nextIndex = index + i
            if nextIndex < chapterList.count {
                let nextChapter = chapterList[nextIndex]
                if let nextChapterId = nextChapter.chapterId, videoPathsCache[nextChapterId] == nil {
                    targetChapters["\(nextIndex)"] = nextChapterId
                }
            }
        }
        if !targetChapters.isEmpty {
            requestVideoPaths(chapterIds: targetChapters, completion: nil)
        }
    }
    
    private func castWithCDNList(_ cdnList: [DRBTVCDNModel], chapterId: String, chapterIndex: Int, resumePosition: TimeInterval? = nil) {
        let quality = DRBQualityCDNHelper.shared.currentSelectedQuality
        guard let videoPath = DRBQualityCDNHelper.shared.getVideoPath(cdnList: cdnList, quality: quality) else {
            DRBToast.toast(text: Loc.shared().str_cast_fail_tryagain())
            return
        }
        
        var actualQuality: Int = 720
        if let matchedQuality = cdnList.flatMap({ $0.videoPathList ?? [] }).first(where: { $0.videoPath == videoPath })?.quality {
            actualQuality = matchedQuality
        }
        
        DRBQualityCDNHelper.shared.currentPlayingQuality = actualQuality
        activeController?.updateQualityTitleUI(actualQuality: actualQuality)
        
        var chapterTitle = Loc.shared().str_episode_alone_progress(chapterIndex + 1)
        if chapterIndex < chapterList.count {
            chapterTitle = chapterList[chapterIndex].chapterName ?? Loc.shared().str_episode_alone_progress(chapterList[chapterIndex].chapterIndex ?? (chapterIndex + 1))
        }
        
        let bookName = self.bookName ?? ""
        let title: String
        let episode: Int?
        if !bookName.isEmpty {
            title = bookName
            episode = chapterIndex + 1
        } else {
            title = chapterTitle
            episode = nil
        }
        
        let media = DLNACastMediaInfo(
            mediaURL: videoPath,
            title: title,
            episode: episode
        )
        DLNACastManager.shared.currentMedia = media
        DLNACastManager.shared.cast(media: media, resumePosition: resumePosition)
        if let activeVC = activeController {
            DLNACastManager.shared.setPlayRate(activeVC.currentSpeedRate)
        } else {
            DLNACastManager.shared.setPlayRate(DRBPlayerManager.recordRate)
        }
        activeController?.updateMediaInfoUI()
    }
    
    func requestVideoPaths(chapterIds: [String: String], completion: (() -> Void)?) {
        #if DRB_CAST_DEMO
        for (_, chapterId) in chapterIds {
            if let chapter = chapterList.first(where: { $0.chapterId == chapterId }),
               let cdnList = chapter.cdnList, !cdnList.isEmpty {
                videoPathsCache[chapterId] = cdnList
            }
        }
        completion?()
        #else
        let request = DRBTVPlayRequestModel.batchVideoPath(
            bookId: bookId,
            chapterIds: chapterIds,
            currencyPlaySource: currencyPlaySource,
            currencyPlaySourceName: currencyPlaySourceName
        )
        
        DRBNetwork.shared.requestMappable(target: request, type: DRBTVBatchVideoPathResponseModel.self) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let response):
                if let data = response?.data, let videoList = data.chapterVideoList {
                    for videoModel in videoList {
                        if let cId = videoModel.chapterId, let cdnList = videoModel.cdnList {
                            self.videoPathsCache[cId] = cdnList
                            
                            if let index = self.chapterList.firstIndex(where: { $0.chapterId == cId }) {
                                self.chapterList[index].cdnList = cdnList
                                if let name = videoModel.chapterName {
                                    self.chapterList[index].chapterName = name
                                }
                            }
                        }
                    }
                }
                completion?()
            case .failure(let error):
                DLog.error("Request video paths failed: \(error)")
                completion?()
            }
        }
        #endif
    }
    
    private func checkAndPreloadNextChapters(currentTime: TimeInterval, duration: TimeInterval) {
        guard duration > 0, duration - currentTime <= 30 else { return }
        guard currentChapterIndex != lastPreloadedIndex else { return }
        
        var targetChapters: [String: String] = [:]
        for i in 1...3 {
            let nextIndex = currentChapterIndex + i
            if nextIndex < chapterList.count {
                let nextChapter = chapterList[nextIndex]
                if let nextChapterId = nextChapter.chapterId, videoPathsCache[nextChapterId] == nil {
                    targetChapters["\(nextIndex)"] = nextChapterId
                }
            }
        }
        
        lastPreloadedIndex = currentChapterIndex
        
        if !targetChapters.isEmpty {
            requestVideoPaths(chapterIds: targetChapters, completion: nil)
        }
    }
    
    // MARK: - DLNACastManagerDelegate
    func castManager(_ manager: DLNACastManager, didDiscoverDevice device: DLNADevice) {
        DLog.info("DRBTVPlayManager didDiscoverDevice: \(device.friendlyName)")
        activeController?.castManager(manager, didDiscoverDevice: device)
    }
    
    func castManager(_ manager: DLNACastManager, didLoseDevice device: DLNADevice) {
        DLog.info("DRBTVPlayManager didLoseDevice: \(device.friendlyName)")
        activeController?.castManager(manager, didLoseDevice: device)
    }
    
    func castManager(_ manager: DLNACastManager, playbackStateDidChange state: DLNACastPlaybackState) {
        DLog.info("DRBTVPlayManager playbackStateDidChange: \(state)")
        activeController?.updatePlaybackStateUI(state: state)
        
        switch state {
        case .playing:
            lastPlaybackStateChangeTime = Date()
            if let activeVC = activeController {
                DLNACastManager.shared.setPlayRate(activeVC.currentSpeedRate)
            } else {
                DLNACastManager.shared.setPlayRate(DRBPlayerManager.recordRate)
            }
        case .idle, .finished, .paused, .stopped, .error:
            if let startTime = lastPlaybackStateChangeTime {
                let elapsed = Date().timeIntervalSince(startTime)
                playDurationAccumulator += elapsed
                lastPlaybackStateChangeTime = nil
            }
            if case .error(let err) = state {
                DLog.error("DRBTVPlayManager playback error: \(err)")
                showConnectionErrorAlert()
            }
        case .loading:
            break
        @unknown default:
            break
        }
    }
    
    func castManager(_ manager: DLNACastManager, positionDidUpdate position: DLNACastPositionInfo) {
        DLog.debug("DRBTVPlayManager positionDidUpdate: \(position.currentTime) / \(position.duration)")
        activeController?.updateProgressUI(position: position)
        checkAndPreloadNextChapters(currentTime: position.currentTime, duration: position.duration)
    }
    
    func castManagerDidFinishPlayback(_ manager: DLNACastManager) {
        DLog.info("DRBTVPlayManager castManagerDidFinishPlayback")
        playNextEpisode()
    }
    
    func castManager(_ manager: DLNACastManager, didEncounterError error: DLNACastError) {
        DLog.error("DRBTVPlayManager didEncounterError: \(error)")
        showConnectionErrorAlert()
        activeController?.handleError(error)
    }
    
    private func playNextEpisode() {
        #if DRB_CAST_DEMO
        proceedToPlayNext()
        #else
        if DRBConfig.downloadType == .goPay {
            if DRBAppInfo.memberStatus == .paidMemberShip {
                proceedToPlayNext()
            } else {
                handleExpiredSubscription()
            }
        } else {
            proceedToPlayNext()
        }
        #endif
    }
    
    private func proceedToPlayNext() {
        if self.currentChapterIndex + 1 < self.chapterList.count {
            let nextIndex = self.currentChapterIndex + 1
            let nextChapter = self.chapterList[nextIndex]
            self.playChapter(chapterId: nextChapter.chapterId, chapterIndex: nextIndex)
        } else {
            activeController?.exitTVCastFlow()
        }
    }
    
    private func handleExpiredSubscription() {
        if let activeVC = self.activeController, activeVC.isViewLoaded && activeVC.view.window != nil {
            activeVC.pushToMembershipForTVCast()
        } else {
            DLNACastManager.shared.disconnect()
            self.reset()
            
            if let activeVC = self.activeController {
                DispatchQueue.main.async {
                    if let nav = activeVC.navigationController {
                        let vcs = nav.viewControllers
                        for vc in vcs.reversed() {
                            if !(vc is DRBTVPlayController) && !(vc is DRBTVSearchController) {
                                nav.popToViewController(vc, animated: true)
                                return
                            }
                        }
                        nav.popViewController(animated: true)
                    }
                }
            }
        }
    }
}
