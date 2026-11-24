//
//  DRBTVFloatingCastView.swift
//  DramaBox
//
//  Created by Antigravity on 2026/7/3.
//

import UIKit
import SnapKit

class DRBTVFloatingCastView: DRBBaseView {
    var enbaleAlpha: Bool = false
    static var safeAreaInsets: UIEdgeInsets {
        // 现代获取 keyWindow 的标准方式
        let keyWindow = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows } .first { $0.isKeyWindow }
        
        return keyWindow?.safeAreaInsets ?? .zero
    }

    static var statusBarHeight: CGFloat {
        // 现代获取 windowScene 的方式
        let windowScene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        
        return windowScene?.statusBarManager?.statusBarFrame.height ?? 0.0
    }

    static var tabBarHeight: CGFloat {
        // 复用上方重构好的 safeAreaInsets 获取 keyWindow
        let keyWindow = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }.first { $0.isKeyWindow }

        if let root = keyWindow?.rootViewController as? UITabBarController {
            let barFrame = root.tabBar.frame
            // 必须确认 tabbar 真是一条横在底部的条：iPhone Duo 内屏横置时系统会把它挪到
            // **屏幕右侧变成竖向 side bar**，那时 `frame.height` 是整个窗口的高度，
            // 直接当「底部占位高度」用会把悬浮投屏入口顶到屏幕外面去。
            // 侧边栏形态下底部确实没有占位，返回 0。
            guard barFrame.width > barFrame.height else { return 0 }
            return barFrame.height
        }

        // 默认高度 + 安全区域底部高度
        return 49.0 + safeAreaInsets.bottom
    }
    
    private lazy var imageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.image = R.image.tv_cast_entry_icon()
        return iv
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        // Container background color rgba(56, 56, 56, 0.5) for both dark and light modes
        self.backgroundColor = DRBResource.colors.tvFloatBtnBgColor
        
        self.addSubview(imageView)
        imageView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(CGSize(width: fitScale(22), height: fitScale(22)))
        }
        
        // Drag gesture
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        self.addGestureRecognizer(panGesture)
        
        // Tap gesture
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        self.addGestureRecognizer(tapGesture)
    }
    
    override func changeTheme() {
        self.backgroundColor = DRBResource.colors.tvFloatBtnBgColor.withAlphaComponent(enbaleAlpha ? 0.5 : 1)
    }
    
    @objc private func handleTap() {
        DRBTVFloatingCastManager.shared.navigateToCastingPage()
    }
    
    func updateCornerRadius(isLeft: Bool) {
        self.layer.cornerRadius = 19
        self.clipsToBounds = true
        if isLeft {
            self.layer.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        } else {
            self.layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        }
    }
    
    func updateEnableAlpha(enbale: Bool = false) {
        enbaleAlpha = enbale
        self.backgroundColor = DRBResource.colors.tvFloatBtnBgColor.withAlphaComponent(enbale ? 5 : 1)
    }
    
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let superview = self.superview else { return }
        let translation = gesture.translation(in: superview)
        
        switch gesture.state {
        case .changed:
            let center = self.center
            var newCenter = CGPoint(x: center.x + translation.x, y: center.y + translation.y)
            
            // Limit vertical bounds: status bar height to bottom tab bar height
            let topLimit = Self.statusBarHeight + self.bounds.height / 2.0
            let bottomLimit = superview.bounds.height - Self.tabBarHeight - self.bounds.height / 2.0
            newCenter.y = max(topLimit, min(bottomLimit, newCenter.y))
            
            // Limit horizontal bounds to stay inside the screen
            let leftLimit = self.bounds.width / 2.0
            let rightLimit = superview.bounds.width - self.bounds.width / 2.0
            newCenter.x = max(leftLimit, min(rightLimit, newCenter.x))
            
            self.center = newCenter
            gesture.setTranslation(.zero, in: superview)
            
        case .ended, .cancelled:
            let midX = superview.bounds.width / 2.0
            let targetX: CGFloat
            let isLeft: Bool
            if self.center.x < midX {
                targetX = self.bounds.width / 2.0
                isLeft = true
            } else {
                targetX = superview.bounds.width - self.bounds.width / 2.0
                isLeft = false
            }
            
            let topLimit = Self.statusBarHeight + self.bounds.height / 2.0
            let bottomLimit = superview.bounds.height - Self.tabBarHeight - self.bounds.height / 2.0
            let targetY = max(topLimit, min(bottomLimit, self.center.y))
            
            UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseOut, animations: {
                self.center = CGPoint(x: targetX, y: targetY)
                self.updateCornerRadius(isLeft: isLeft)
            }, completion: { _ in
                DRBTVFloatingCastManager.shared.lastPosition = self.center
            })
            
        default:
            break
        }
    }
}
