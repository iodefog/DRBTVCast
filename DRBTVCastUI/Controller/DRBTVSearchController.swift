//
//  DRBTVSearchController.swift
//  DramaBox
//
//  Created by LHL on 2026/6/25.
//

import UIKit
import SnapKit
import DRBTVCast
import AVFoundation

// MARK: - DRBTVSearchController

public class DRBTVSearchController: UIViewController {

    private lazy var naviBar: DRBTVNaviBar = DRBTVNaviBar()
    private lazy var baseContentView: UIView = UIView()

    var chapterList: [DRBTVChapterModel] = []
    var currentChapterIndex: Int = 0
    
    var bookId: String?
    var bookName: String?
    var albumModel: DRBAlbumModel?
    var chapterId: String?
    var currencyPlaySource: String?
    var currencyPlaySourceName: String?
    
    private var isSearching = false
    private var searchTimer: Timer?
    private var isWaitingForAirPlay = false
    private var isAirPlayPickerDismissed = true
    private var pendingDeviceAfterSubscription: DLNADevice?
    
    // MARK: - UI Elements
    private lazy var noticeLabel: UILabel = {
        let label = UILabel()
        label.text = Loc.shared().srt_cast_info()
        label.font = .mediumFont(12)
        label.numberOfLines = 0
        label.textAlignment = .natural
        return label
    }()
    
    private lazy var availableDevicesLabel: UILabel = {
        let label = UILabel()
        label.text = Loc.shared().str_cast_availabledevice()
        label.font = .mediumFont(12)
        return label
    }()
    
    private lazy var refreshIconView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.isUserInteractionEnabled = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(refreshIconTapped))
        iv.addGestureRecognizer(tap)
        return iv
    }()
    
    private lazy var tableView: DRBTVTableView = {
        let tv = DRBTVTableView(frame: .zero, style: .plain)
        tv.delegate = self
        tv.dataSource = self
        tv.separatorStyle = .none
        tv.showsVerticalScrollIndicator = false
        tv.layer.cornerRadius = fitScale(8)
        tv.clipsToBounds = true
        tv.register(cellClass: DRBTVSearchCell.self)
        tv.register(cellClass: DRBTVEmptyCell.self)
        tv.contentInset = UIEdgeInsets(top: fitScale(8), left: 0, bottom: fitScale(8), right: 0)
        tv.alwaysBounceVertical = false
        return tv
    }()
    
    private lazy var searchAgainButton: UIButton = {
        let btn = UIButton(type: .custom)
        btn.setTitle(Loc.shared().str_cast_finddevice(), for: .normal)
        btn.titleLabel?.font = .mediumFont(16)
        btn.layer.cornerRadius = fitScale(4)
        btn.clipsToBounds = true
        btn.addTarget(self, action: #selector(searchAgainClicked), for: .touchUpInside)
        return btn
    }()
    
    private lazy var warningContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = DRBResource.colors.bgTertiaryD3
        view.layer.cornerRadius = fitScale(4)
        view.clipsToBounds = true
        
        view.addSubview(warningIconView)
        view.addSubview(warningLabel)
        
        warningIconView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(fitScale(12))
            make.centerY.equalToSuperview()
            make.width.height.equalTo(fitScale(20))
        }
        
        warningLabel.snp.makeConstraints { make in
            make.leading.equalTo(warningIconView.snp.trailing).offset(fitScale(8))
            make.trailing.equalToSuperview().offset(-fitScale(12))
            make.top.bottom.equalToSuperview().inset(fitScale(12))
        }
        return view
    }()
    
    private lazy var warningIconView: UIImageView = {
        let iv = UIImageView()
        iv.image = DRBResource.images.tv_cast_warning
        iv.contentMode = .scaleAspectFit
        return iv
    }()
    
    private lazy var warningLabel: UILabel = {
        let label = UILabel()
        label.text = Loc.shared().str_cast_nodevice_info()
        label.textColor = DRBResource.colors.newTextPrimary
        label.font = .regularFont(12)
        label.numberOfLines = 0
        label.textAlignment = .natural
        return label
    }()
    
    // MARK: - Lifecycle
    
    public override func viewDidLoad() {
        super.viewDidLoad()

        self.view.backgroundColor = .black
        setupCommonLayout()
        setupViews()
        setupConstraints()
        
        DLNACastManager.shared.initializeGoogleCast()
        
        DLNACastManager.shared.addDelegate(self)
        changeTheme()
        startSearching()
        
        DRBNotify.subscribeSuccess.addObserver(observer: self, selector: #selector(subscribeSuccess))
        NotificationCenter.default.addObserver(self, selector: #selector(handleAudioRouteChange(_:)), name: AVAudioSession.routeChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        
        let edgePan = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handleEdgePan(_:)))
        edgePan.edges = .left
        self.view.addGestureRecognizer(edgePan)
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        DLNACastManager.shared.addDelegate(self)
        reloadTableView()
        
        if pendingDeviceAfterSubscription != nil {
            self.subscribeSuccess()
        }
    }
    
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopSearchingUI()
        isWaitingForAirPlay = false
        NotificationCenter.default.removeObserver(self, name: Notification.Name("DLNACastAirPlayPickerDidDismiss"), object: nil)
        
        if self.isMovingFromParent || self.isBeingDismissed {
            DLNACastManager.shared.stopDiscovery()
            DLNACastManager.shared.disconnect()
            DLNACastManager.shared.removeDelegate(self)
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func backButtonAction() {
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

    // MARK: - UI Setup

    private func setupViews() {
        naviBar.titleLabel.text = Loc.shared().str_cast_title()
        title = naviBar.titleLabel.text
        
        baseContentView.addSubview(noticeLabel)
        baseContentView.addSubview(availableDevicesLabel)
        baseContentView.addSubview(refreshIconView)
        baseContentView.addSubview(tableView)
        baseContentView.addSubview(searchAgainButton)
        baseContentView.addSubview(warningContainerView)
    }
    
    private func setupConstraints() {
        noticeLabel.snp.makeConstraints { make in
            make.top.equalTo(naviBar.snp.bottom).offset(fitScale(16))
            make.leading.trailing.equalToSuperview().inset(fitScale(16))
        }
        
        availableDevicesLabel.snp.makeConstraints { make in
            make.top.equalTo(noticeLabel.snp.bottom).offset(fitScale(30))
            make.leading.equalToSuperview().offset(fitScale(16))
        }
        
        refreshIconView.snp.makeConstraints { make in
            make.centerY.equalTo(availableDevicesLabel)
            make.leading.equalTo(availableDevicesLabel.snp.trailing).offset(fitScale(12))
            make.width.height.equalTo(fitScale(16))
        }
        
        searchAgainButton.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.width.equalTo(fitScale(343))
            make.height.equalTo(fitScale(44))
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom).offset(-fitScale(16))
        }
        
        warningContainerView.snp.makeConstraints { make in
            make.bottom.equalTo(searchAgainButton.snp.top).offset(-fitScale(20))
            make.leading.trailing.equalToSuperview().inset(fitScale(16))
        }
        
        tableView.snp.makeConstraints { make in
            make.top.equalTo(availableDevicesLabel.snp.bottom).offset(fitScale(12))
            make.centerX.equalToSuperview()
            make.width.equalTo(fitScale(343))
            make.bottom.lessThanOrEqualTo(warningContainerView.snp.top).offset(-fitScale(26))
        }
    }
    
    // MARK: - Theme Update
    
    private func changeTheme() {
        view.backgroundColor = DRBResource.colors.background_primary_color
        
        noticeLabel.textColor = DRBResource.colors.text_secondary_color
        availableDevicesLabel.textColor = DRBResource.colors.text_secondary_color
        warningLabel.textColor = DRBResource.colors.newTextPrimary
        warningIconView.image = DRBResource.images.tv_cast_warning
        
        tableView.backgroundColor = DRBResource.colors.background_secondary_color
        
        searchAgainButton.setTitleColor(DRBResource.colors.text_primary_color, for: .normal)
        searchAgainButton.backgroundColor = DRBResource.colors.tvSearchAgainBtnBgColor
 
        warningContainerView.backgroundColor = DRBResource.colors.bgTertiaryD3
        
        updateSearchingState()
        reloadTableView()
    }
    
    // MARK: - Search Logic
    
    private func startSearching() {
        guard !isSearching else { return }
        isSearching = true
        updateSearchingState()
        
        DLNACastManager.shared.startDiscovery(timeout: 10)
        
        searchTimer?.invalidate()
        searchTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] _ in
            // Timer 只停止 UI 上的搜索动画，不再强杀底层 discovery
            Task { @MainActor [weak self] in
                self?.stopSearchingUI()
            }
        }
    }
    
    /// 只停止 UI 上的搜索状态（动画/按钮），不触碰底层 discovery
    private func stopSearchingUI() {
        guard isSearching else { return }
        isSearching = false
        updateSearchingState()
        searchTimer?.invalidate()
        searchTimer = nil
    }
    
    @objc private func handleAirPlayPickerDismiss(_ notification: Notification) {
        guard isWaitingForAirPlay else { return }
        isAirPlayPickerDismissed = true
        
        NotificationCenter.default.removeObserver(self, name: Notification.Name("DLNACastAirPlayPickerDidDismiss"), object: nil)
        
        pushToPlayVCForAirPlayIfNeeded()
    }
    
    @objc private func handleAudioRouteChange(_ notification: Notification) {
        guard isWaitingForAirPlay else { return }
        DispatchQueue.main.async { [weak self] in
            if self?.isAirPlayPickerDismissed == true {
                self?.pushToPlayVCForAirPlayIfNeeded()
            }
        }
    }
    
    private func pushToPlayVCForAirPlayIfNeeded() {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        let hasAirPlay = outputs.contains(where: { $0.portType == .airPlay })
        
        if hasAirPlay {
            isWaitingForAirPlay = false
            if let downloadType = DRBConfig.downloadType {
                switch downloadType {
                case .download:
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        let playVC = DRBTVPlayController()
                        playVC.setup(params: self.getCastParams())
                        self.navigationController?.pushViewController(playVC, animated: true)
                    }
                case .goPay:
                    let airplayDevice = DLNADevice(
                        id: "airplay-generic",
                        friendlyName: "AirPlay",
                        manufacturer: "Apple",
                        modelName: "AirPlay",
                        location: nil,
                        controlURL: nil,
                        eventSubURL: nil,
                        deviceType: .airplay
                    )
                    self.pendingDeviceAfterSubscription = airplayDevice
                    self.pushToMembershipForTVCast()
                case .showToast:
                    DRBToast.toast(text: Loc.shared().str_download_memberads_toast())
                    DLNACastManager.shared.disconnect()
                }
            } else {
                // Fallback
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    let playVC = DRBTVPlayController()
                    playVC.setup(params: self.getCastParams())
                    self.navigationController?.pushViewController(playVC, animated: true)
                }
            }
        }
    }
    
    private func updateSearchingState() {
        // "图片先留空，我会补充". We set DRBResource.images.tv_cast_scaning when searching, and UIImage(named: "ic_tv_search_refresh") otherwise.
        if isSearching {
            refreshIconView.image = DRBResource.images.tv_cast_scaning
            startLoadingAnimation()
            searchAgainButton.alpha = 0.5
        } else {
            refreshIconView.image = nil
            stopLoadingAnimation()
            searchAgainButton.alpha = 1.0
        }
    }
    
    private func startLoadingAnimation() {
        refreshIconView.layer.removeAnimation(forKey: "rotationAnimation")
        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation.toValue = NSNumber(value: Double.pi * 2)
        rotation.duration = 1.0
        rotation.isCumulative = true
        rotation.repeatCount = Float.infinity
        refreshIconView.layer.add(rotation, forKey: "rotationAnimation")
    }
    
    private func stopLoadingAnimation() {
        refreshIconView.layer.removeAnimation(forKey: "rotationAnimation")
    }
    
    // MARK: - Actions
    
    @objc private func refreshIconTapped() {
        if !isSearching {
            startSearching()
        }
    }
    
    @objc private func searchAgainClicked() {
        if !isSearching {
            startSearching()
        }
    }
    
    @objc private func appDidBecomeActive() {
        // 用户如果刚关闭了本地网络权限申请弹窗（无论同意还是拒绝），App会回到Active状态
        // 此时为了确保能拿到最新的网络权限并扫描到设备，我们需要重新触发一次搜索
        if isSearching {
            stopSearchingUI() // 先停止当前可能的阻塞状态
        }
        startSearching()
    }
    
    private func reloadTableView() {
        let devices = DLNACastManager.shared.discoveredDevices.filter { $0.deviceType == .dlna || $0.deviceType == .googleCast }
        if devices.count > 0 {
            tableView.contentInset = UIEdgeInsets(top: fitScale(8), left: 0, bottom: fitScale(8), right: 0)
        } else {
            tableView.contentInset = .zero
        }
        tableView.reloadData()
    }
}

// MARK: - UITableViewDataSource, UITableViewDelegate

extension DRBTVSearchController: UITableViewDataSource, UITableViewDelegate {
    
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let devices = DLNACastManager.shared.discoveredDevices.filter { $0.deviceType == .dlna || $0.deviceType == .googleCast }
        return devices.count + 1
    }
    
    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusable(cellClass: DRBTVSearchCell.self)
        if indexPath.row == 0 {
            cell.configure(with: "AirPlay")
        } else {
            let devices = DLNACastManager.shared.discoveredDevices.filter { $0.deviceType == .dlna || $0.deviceType == .googleCast }
            guard indexPath.row - 1 >= 0 && indexPath.row - 1 < devices.count else {
                cell.configure(with: "")
                cell.changeTheme()
                return cell
            }
            let device = devices[indexPath.row - 1]
            let prefix = device.deviceType == .googleCast ? "[Chromecast] " : ""
            cell.configure(with: prefix + device.friendlyName)
        }
        cell.changeTheme()
        return cell
    }
    
    private func getCastParams() -> DRBTVCastParams {
        return DRBTVCastParams(
            bookId: bookId,
            bookName: bookName,
            albumModel: albumModel,
            chapterId: chapterId,
            currencyPlaySource: currencyPlaySource,
            currencyPlaySourceName: currencyPlaySourceName,
            chapterList: chapterList,
            currentChapterIndex: currentChapterIndex
        )
    }

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.row == 0 {
            let airplayDevice = DLNADevice(
                id: "airplay-generic",
                friendlyName: "AirPlay",
                manufacturer: "Apple",
                modelName: "AirPlay",
                location: nil,
                controlURL: nil,
                eventSubURL: nil,
                deviceType: .airplay
            )
            isWaitingForAirPlay = true
            isAirPlayPickerDismissed = false
            DLNACastManager.shared.connect(to: airplayDevice)
            DRBSensorsTracking.buttonClickCommonLog(buttonName: "cast", deviceName: "AirPlay", isSuccess: true)
            
            NotificationCenter.default.removeObserver(self, name: Notification.Name("DLNACastAirPlayPickerDidDismiss"), object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(handleAirPlayPickerDismiss(_:)), name: Notification.Name("DLNACastAirPlayPickerDidDismiss"), object: nil)
        } else {
            let devices = DLNACastManager.shared.discoveredDevices.filter { $0.deviceType == .dlna || $0.deviceType == .googleCast }
            guard indexPath.row - 1 < devices.count else { return }
            let device = devices[indexPath.row - 1]
            
            if let downloadType = DRBConfig.downloadType {
                switch downloadType {
                case .download:
                    DLNACastManager.shared.connect(to: device)
                    DRBSensorsTracking.buttonClickCommonLog(buttonName: "cast", deviceName: device.friendlyName, isSuccess: true)
                    
                    let playVC = DRBTVPlayController()
                    playVC.setup(params: self.getCastParams())
                    navigationController?.pushViewController(playVC, animated: true)
                case .goPay:
                    self.pendingDeviceAfterSubscription = device
                    DRBSensorsTracking.buttonClickCommonLog(buttonName: "cast", deviceName: device.friendlyName, isSuccess: false)
                    self.pushToMembershipForTVCast()
                case .showToast:
                    DRBSensorsTracking.buttonClickCommonLog(buttonName: "cast", deviceName: device.friendlyName, isSuccess: false)
                    DRBToast.toast(text: Loc.shared().str_download_memberads_toast())
                }
            } else {
                // Fallback
                DLNACastManager.shared.connect(to: device)
                DRBSensorsTracking.buttonClickCommonLog(buttonName: "cast", deviceName: device.friendlyName, isSuccess: true)
                
                let playVC = DRBTVPlayController()
                playVC.setup(params: self.getCastParams())
                navigationController?.pushViewController(playVC, animated: true)
            }
        }
    }
}

// MARK: - DRBTVEmptyCell

class DRBTVEmptyCell: UITableViewCell, Reusable {
    
    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.text = Loc.shared().str_cast_notfound()
        label.font = .regularFont(14)
        label.textAlignment = .natural
        return label
    }()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(fitScale(16))
            make.centerY.equalToSuperview()
            make.trailing.equalToSuperview().offset(-fitScale(16))
            make.top.bottom.equalToSuperview().inset(fitScale(16))
        }
        changeTheme()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func changeTheme() {
        titleLabel.textColor = DRBResource.colors.text_primary_color
    }
}

// MARK: - DLNACastManagerDelegate

extension DRBTVSearchController: DLNACastManagerDelegate {
    
    public func castManager(_ manager: DLNACastManager, didDiscoverDevice device: DLNADevice) {
        DLog.info("DRBTVSearchController didDiscoverDevice: \(device.friendlyName)")
        reloadTableView()
    }
    
    public func castManager(_ manager: DLNACastManager, didLoseDevice device: DLNADevice) {
        DLog.info("DRBTVSearchController didLoseDevice: \(device.friendlyName)")
        reloadTableView()
    }
    
    public func castManager(_ manager: DLNACastManager, playbackStateDidChange state: DLNACastPlaybackState) {
        DLog.info("DRBTVSearchController playbackStateDidChange: \(state)")
    }
    
    public func castManager(_ manager: DLNACastManager, positionDidUpdate position: DLNACastPositionInfo) {
        DLog.debug("DRBTVSearchController positionDidUpdate: \(position.currentTime) / \(position.duration)")
    }
    
    public func castManagerDidFinishPlayback(_ manager: DLNACastManager) {
        DLog.info("DRBTVSearchController castManagerDidFinishPlayback")
    }
    
    public func castManager(_ manager: DLNACastManager, didEncounterError error: DLNACastError) {
        DLog.error("DRBTVSearchController didEncounterError: \(error)")
    }
}

// MARK: - DRBTVTableView

class DRBTVTableView: UITableView {
    override var contentSize: CGSize {
        didSet {
            invalidateIntrinsicContentSize()
        }
    }
    
    override var intrinsicContentSize: CGSize {
        layoutIfNeeded()
        let height = contentSize.height + contentInset.top + contentInset.bottom
        return CGSize(width: UIView.noIntrinsicMetric, height: height)
    }
}

// MARK: - TV Cast Parameters Config extension
extension DRBTVSearchController {
    public func setup(params: DRBTVCastParams) {
        self.bookId = params.bookId
        self.bookName = params.bookName
        self.albumModel = params.albumModel
        self.chapterId = params.chapterId
        self.currencyPlaySource = params.currencyPlaySource
        self.currencyPlaySourceName = params.currencyPlaySourceName
        self.chapterList = params.chapterList
        self.currentChapterIndex = params.currentChapterIndex
    }
}

// MARK: - Subscription flow
extension DRBTVSearchController {
    @objc private func subscribeSuccess() {
        if let device = pendingDeviceAfterSubscription {
            pendingDeviceAfterSubscription = nil
            
            if let downloadType = DRBConfig.downloadType {
                switch downloadType {
                case .download:
                    self.proceedAfterUnlockCheck(device: device)
                case .goPay, .showToast:
                    self.unlockAndProceed(device: device)
                }
            } else {
                self.proceedAfterUnlockCheck(device: device)
            }
        }
    }
    
    private func proceedAfterUnlockCheck(device: DLNADevice) {
        if device.deviceType == .airplay {
            let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
            let hasAirPlay = outputs.contains(where: { $0.portType == .airPlay })
            if hasAirPlay {
                let playVC = DRBTVPlayController()
                playVC.setup(params: self.getCastParams())
                navigationController?.pushViewController(playVC, animated: true)
            } else {
                isWaitingForAirPlay = true
                isAirPlayPickerDismissed = false
                DLNACastManager.shared.connect(to: device)
                NotificationCenter.default.removeObserver(self, name: Notification.Name("DLNACastAirPlayPickerDidDismiss"), object: nil)
                NotificationCenter.default.addObserver(self, selector: #selector(handleAirPlayPickerDismiss(_:)), name: Notification.Name("DLNACastAirPlayPickerDidDismiss"), object: nil)
            }
        } else {
            DLNACastManager.shared.connect(to: device)
            DRBToast.toast(text: "Connected to \(device.friendlyName)")
            
            let playVC = DRBTVPlayController()
            playVC.setup(params: self.getCastParams())
            navigationController?.pushViewController(playVC, animated: true)
        }
    }
    
    private func unlockAndProceed(device: DLNADevice) {
        #if DRB_CAST_DEMO
        proceedAfterUnlockCheck(device: device)
        #else
        guard let bookId = self.bookId else { return }
        
        let targetChapterId = self.chapterId ?? self.chapterList.first(where: { $0.chapterIndex == self.currentChapterIndex })?.chapterId ?? self.chapterList.first?.chapterId
        
        let target = DRBAlbumRequestModel.unlock(
            autoPay: DRBConfig.autoPay,
            bookId: bookId,
            chapterId: targetChapterId,
            confirmPay: false,
            currencyPlaySource: self.currencyPlaySource ?? "",
            currencyPlaySourceName: self.currencyPlaySourceName ?? "",
            hintName: "",
            hintType: "",
            index: self.currentChapterIndex,
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
                        self.proceedAfterUnlockCheck(device: device)
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

    private func pushToMembershipForTVCast() {
        #if DRB_CAST_DEMO
        DRBToast.toast(text: Loc.shared().str_cast_toast_notmember())
        #else
        var dic = [String: Any]()
        dic["channel"] = MemberShipRootChannelType.tvCase.rawValue
        dic["chapterId"] = chapterId
        dic["chapterIndex"] = currentChapterIndex
        dic["bookId"] = bookId
        dic["bookName"] = bookName
        dic["currencyPlaySource"] = currencyPlaySource
        dic["currencyPlaySourceName"] = currencyPlaySourceName
        
        let path = memberShipVCPath.appendParamsWithDict(dict: dic)
        navigator.open(path, context: self)
        #endif
    }
}
