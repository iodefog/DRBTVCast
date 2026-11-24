//
//  DRBTVFloatingCastManager.swift
//  DramaBox
//
//  Created by Antigravity on 2026/7/3.
//

import UIKit
import DRBTVCast

@MainActor
class DRBTVFloatingCastManager {
    static let shared = DRBTVFloatingCastManager()
    
    private(set) lazy var floatingView: DRBTVFloatingCastView = {
        let view = DRBTVFloatingCastView(frame: CGRect(x: 0, y: 431, width: 46, height: 38))
        return view
    }()
    
    var lastPosition: CGPoint?
    private weak var currentVisibleVC: UIViewController?
    
    private init() {
        // Observe DLNA cast state changes
        NotificationCenter.default.addObserver(self, selector: #selector(handleCastStateChange), name: NSNotification.Name("DLNACastPlaybackStateDidChangeNotification"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleCastStateChange), name: NSNotification.Name("DLNACastConnectedDeviceDidChangeNotification"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleCastStateChange), name: NSNotification.Name("DRBLocalPlayerStateDidChangeNotification"), object: nil)
        
        // Observe user membership and login changes
        DRBNotify.userVipStatusChanged.addObserver(observer: self, selector: #selector(handleCastStateChange))
        DRBNotify.loginSuccess.addObserver(observer: self, selector: #selector(handleCastStateChange))
    }
    
    @objc private func handleCastStateChange() {
        updateVisibility()
    }
    
    func viewControllerDidAppear(_ vc: UIViewController) {
        self.currentVisibleVC = vc
        updateVisibility()
    }
    
    func updateVisibility() {
        guard let window = getActiveWindow() else { return }
        
        #if DRB_CAST_DEMO
        let isMember = true
        #else
        let isMember = DRBAppInfo.memberStatus == .paidMemberShip
        #endif
        let isCasting = DLNACastManager.shared.connectedDevice != nil && (
            DLNACastManager.shared.playbackState == .playing ||
            DLNACastManager.shared.playbackState == .paused ||
            DLNACastManager.shared.playbackState == .loading
        )
        let isLocalPlaying = DRBAlbumPlayerHandler.isLocalPlayerPlaying
        var shouldShow = isMember && isCasting
        
        if shouldShow {
            if let topVC = getTopViewController() {
                if topVC is DRBTVPlayController || topVC is DRBTVSearchController {
                    shouldShow = false
                }
            } else {
                shouldShow = false
            }
        }
        
        if shouldShow {
            if floatingView.superview == nil {
                window.addSubview(floatingView)
            }
            window.bringSubviewToFront(floatingView)
            floatingView.isHidden = false
            
            if let lastPos = lastPosition {
                floatingView.center = lastPos
                let isLeft = lastPos.x < window.bounds.width / 2.0
                floatingView.updateCornerRadius(isLeft: isLeft)
            } else {
                floatingView.frame = CGRect(x: 0, y: 431, width: 46, height: 38)
                floatingView.updateCornerRadius(isLeft: true)
            }
        } else {
            floatingView.isHidden = true
        }
    }
    
    func navigateToCastingPage() {
        guard let topVC = getTopViewController() else { return }
        if topVC is DRBTVPlayController || topVC is DRBTVSearchController {
            return
        }
        
        let params = DRBTVCastParams(
            bookId: DRBTVPlayManager.shared.bookId,
            bookName: DRBTVPlayManager.shared.bookName,
            albumModel: DRBTVPlayManager.shared.albumModel,
            chapterId: DRBTVPlayManager.shared.chapterId,
            currencyPlaySource: DRBTVPlayManager.shared.currencyPlaySource,
            currencyPlaySourceName: DRBTVPlayManager.shared.currencyPlaySourceName,
            chapterList: DRBTVPlayManager.shared.chapterList,
            currentChapterIndex: DRBTVPlayManager.shared.currentChapterIndex
        )
        
        let vc: UIViewController
        if DRBConfig.downloadType != .download {
            let searchVC = DRBTVSearchController()
            searchVC.setup(params: params)
            vc = searchVC
        } else {
            let playVC = DRBTVPlayController()
            playVC.isRestoring = true
            playVC.setup(params: params)
            vc = playVC
        }
        
        vc.hidesBottomBarWhenPushed = true

        if let nav = topVC.navigationController {
            nav.pushViewController(vc, animated: true)
        } else {
            let nav = UINavigationController(rootViewController: vc)
            nav.modalPresentationStyle = .fullScreen
            topVC.present(nav, animated: true, completion: nil)
        }
    }
    
    func updateEnableAlpha(enbale: Bool = false) {
        floatingView.updateEnableAlpha(enbale: enbale)
    }
    
    private func getActiveWindow() -> UIWindow? {
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }
    
    func getTopViewController(base: UIViewController? = nil) -> UIViewController? {
        let baseVC = base ?? getActiveWindow()?.rootViewController
        if let nav = baseVC as? UINavigationController {
            return getTopViewController(base: nav.visibleViewController)
        }
        if let tab = baseVC as? UITabBarController {
            if let selected = tab.selectedViewController {
                return getTopViewController(base: selected)
            }
        }
        if let presented = baseVC?.presentedViewController {
            return getTopViewController(base: presented)
        }
        return baseVC
    }
}
