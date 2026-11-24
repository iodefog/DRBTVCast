#if DRB_CAST_DEMO
import UIKit

// MARK: - 基础工具

public func fitScale(_ value: CGFloat) -> CGFloat { value }

public struct DLog {
    public static func debug(_ message: String) { print("[DEBUG] \(message)") }
    public static func info(_ message: String) { print("[INFO] \(message)") }
    public static func error(_ message: String) { print("[ERROR] \(message)") }
}

public protocol Reusable {
    static var reuseIdentifier: String { get }
}
extension Reusable {
    public static var reuseIdentifier: String { String(describing: self) }
}
extension UITableView {
    public func dequeueReusable<T: UITableViewCell>(cellClass: T.Type) -> T where T: Reusable {
        return dequeueReusableCell(withIdentifier: cellClass.reuseIdentifier) as? T ?? T()
    }
    public func register<T: UITableViewCell>(cellClass: T.Type) where T: Reusable {
        register(cellClass, forCellReuseIdentifier: cellClass.reuseIdentifier)
    }
}

// MARK: - 投屏数据模型

public struct DRBTVQualityModel {
    public var videoPath: String?
    public var quality: Int?
    public init(videoPath: String? = nil, quality: Int? = nil) {
        self.videoPath = videoPath
        self.quality = quality
    }
}

public struct DRBTVCDNModel {
    public var videoPath: String?
    public var videoPathList: [DRBTVQualityModel]?
    public init(videoPath: String? = nil, videoPathList: [DRBTVQualityModel]? = nil) {
        self.videoPath = videoPath
        self.videoPathList = videoPathList
    }
}

public struct DRBTVChapterModel {
    public var chapterId: String?
    public var chapterIndex: Int?
    public var chapterName: String?
    public var videoPath: String?
    public var cdnList: [DRBTVCDNModel]?
    public init(chapterId: String? = nil, chapterIndex: Int? = nil, chapterName: String? = nil,
                videoPath: String? = nil, cdnList: [DRBTVCDNModel]? = nil) {
        self.chapterId = chapterId
        self.chapterIndex = chapterIndex
        self.chapterName = chapterName
        self.videoPath = videoPath
        self.cdnList = cdnList
    }
}

public struct DRBTVChapterItemModel {
    public var chapterId: String?
    public var chapterIndex: Int?
    public var chapterName: String?
    public init(chapterId: String? = nil, chapterIndex: Int? = nil, chapterName: String? = nil) {
        self.chapterId = chapterId
        self.chapterIndex = chapterIndex
        self.chapterName = chapterName
    }
    public init(chapter: DRBTVChapterModel) {
        self.chapterId = chapter.chapterId
        self.chapterIndex = chapter.chapterIndex
        self.chapterName = chapter.chapterName
    }
}

public enum DRBAlbumBookCategory: Int {
    case normal = 0
    case free = 1
}

public struct DRBAlbumModel {
    public var bookId: String = ""
    public var bookName: String?
    public var bookCategory: DRBAlbumBookCategory?
    public var chapterList: [DRBTVChapterModel]?
    public init() {}
}

public struct DRBTVAlbumDetailModel {
    public var list: [DRBTVChapterItemModel]?
    public init() {}
    public init(albumModel: DRBAlbumModel) {
        self.list = albumModel.chapterList?.map { DRBTVChapterItemModel(chapter: $0) }
    }
}

public struct DRBTVAlbumDataModel {
    public var bookId: String?
    public var albumData: DRBAlbumModel?
    public init(bookId: String?, albumData: DRBAlbumModel?) {
        self.bookId = bookId
        self.albumData = albumData
    }
}

// MARK: - 清晰度与倍速

public class DRBQualityCDNHelper {
    nonisolated(unsafe) public static let shared = DRBQualityCDNHelper()
    public var currentSelectedQuality: Int = 0
    public var currentPlayingQuality: Int = 0

    public func getVideoPath(model chapter: DRBTVChapterModel?) -> String? {
        return chapter?.cdnList?.first?.videoPathList?.first?.videoPath ?? chapter?.videoPath
    }
    public func getVideoPath(cdnList: [DRBTVCDNModel], quality: Int) -> String? {
        return cdnList.first?.videoPathList?.first(where: { $0.quality == quality })?.videoPath
            ?? cdnList.first?.videoPathList?.first?.videoPath
            ?? cdnList.first?.videoPath
    }
    public func getVideoQualitySelectList(cdnList: [DRBTVCDNModel]?) -> [DRBTVQualityModel]? {
        return cdnList?.flatMap { $0.videoPathList ?? [] }
    }
}

public let speedRateList: [Float] = [3.0, 2.0, 1.5, 1.25, 1.0, 0.75]

// MARK: - 半屏选择弹层

@MainActor
public protocol DRBHalfFloatingViewDelegate: AnyObject {
    func didSelectItem(at index: Int, in view: DRBHalfFloatingView)
    func willShowHalfFloatingView(_ view: DRBHalfFloatingView)
    func didShowHalfFloatingView(_ view: DRBHalfFloatingView)
    func willHideHalfFloatingView(_ view: DRBHalfFloatingView)
    func didHideHalfFloatingView(_ view: DRBHalfFloatingView)
    func didSelectItemSwitchButton(at index: Int, in view: DRBHalfFloatingView, isOn: Bool)
    func didSelectItemReportButton(at index: Int, in view: DRBHalfFloatingView)
}

public enum DRBHalfFloatingLayoutStyle {
    case textSelection
}

public struct DRBHalfFloatingViewModel {
    public var id: String
    public var title: String
    public var isSelected: Bool
    public init(id: String, title: String, isSelected: Bool = false) {
        self.id = id
        self.title = title
        self.isSelected = isSelected
    }
}

open class DRBHalfFloatingView: UIView {
    public weak var delegate: DRBHalfFloatingViewDelegate?
    open var layoutStyle: DRBHalfFloatingLayoutStyle = .textSelection
    open var selectedImage: UIImage?
    open var maskViewColor: UIColor?
    private var items: [DRBHalfFloatingViewModel] = []

    open func show(in view: UIView, showMask: Bool, with data: [DRBHalfFloatingViewModel], title: String,
                   selectedIndex: Int = 0, layoutStyle: DRBHalfFloatingLayoutStyle = .textSelection) {
        items = data
    }
    open func getItem(index: Int) -> DRBHalfFloatingViewModel? {
        guard items.indices.contains(index) else { return nil }
        return items[index]
    }
}

// MARK: - 选集弹窗

@MainActor
public protocol DRBAlbumDetailEpisodesControllerDelegate: AnyObject {
    func didSelectedChapter(_ controller: DRBAlbumDetailEpisodesController, chapterModel: DRBTVChapterItemModel)
}

open class DRBAlbumDetailEpisodesController: UIViewController {
    public weak var delegate: DRBAlbumDetailEpisodesControllerDelegate?
    public var isFromTV: Bool = false
    public var showHeader: Bool = false
    public var playingChapterIndex: Int = 0
    public var albumDataModel: DRBTVAlbumDataModel?
    public var dataModel: DRBTVAlbumDetailModel?
}

// MARK: - 导航与基础视图

open class DRBTVNaviBar: UIView {
    public let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 17, weight: .medium)
        label.textColor = .white
        label.textAlignment = .center
        return label
    }()
    open private(set) lazy var backButton: UIButton = {
        let button = UIButton(type: .custom)
        button.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        button.tintColor = .white
        return button
    }()
    open private(set) lazy var rightButton: UIButton = {
        let button = UIButton(type: .custom)
        button.setImage(UIImage(systemName: "xmark"), for: .normal)
        button.tintColor = .white
        return button
    }()

    public override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(titleLabel)
        addSubview(backButton)
        addSubview(rightButton)
        [titleLabel, backButton, rightButton].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            backButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            backButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 44),
            backButton.heightAnchor.constraint(equalToConstant: 44),
            rightButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            rightButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            rightButton.widthAnchor.constraint(equalToConstant: 44),
            rightButton.heightAnchor.constraint(equalToConstant: 44),
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: backButton.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: rightButton.leadingAnchor, constant: -8)
        ])
    }
    required public init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    open func setRightButtonImage(_ image: UIImage?) {
        rightButton.setImage(image ?? UIImage(systemName: "xmark"), for: .normal)
    }
}

open class DRBBaseView: UIView {
    @objc open func changeTheme() {}
}
extension UIView {
    @objc open func addThemeChangeObserver() {}
}

public protocol DRBPlayerSliderDelegate: AnyObject {}
open class DRBPlayerSlider: UIView {
    open var value: CGFloat = 0
    open var alwaysShowWhiteThumb: Bool = false
    open var isFixedStyle: Bool = false
    open var fixedThumbSize: CGSize = .zero
    open weak var delegate: DRBPlayerSliderDelegate?
    open func updateTheme() {}
}

// MARK: - Demo 所需的最小宿主桩

public enum DRBDownloadType {
    case download, goPay, showToast
}
public class DRBConfig {
    nonisolated(unsafe) public static var downloadType: DRBDownloadType? = .download
}

public class DRBNotify {
    nonisolated(unsafe) public static let userVipStatusChanged = DRBNotify()
    nonisolated(unsafe) public static let loginSuccess = DRBNotify()
    nonisolated(unsafe) public static let subscribeSuccess = DRBNotify()
    public func addObserver(observer: Any, selector: Selector) {}
}
public class DRBPlayerManager {
    nonisolated(unsafe) public static let shared = DRBPlayerManager()
    nonisolated(unsafe) public static var recordRate: Float = 1.0
}
public class DRBAlbumPlayerHandler {
    public static var isLocalPlayerPlaying: Bool { false }
}

public class DRBSensorsTracking {
    public static func buttonClickCommonLog(buttonName: String, deviceName: String?, isSuccess: Bool?) {}
}
public class DRBToast {
    public static func toast(text: String) {}
}
public class DRBLoadingView {
    public static func show(inView view: UIView, isUserInterActive: Bool) {}
    public static func dismiss(inView view: UIView) {}
}

// MARK: - 主题与资源

public struct DRBResource {
    public struct colors {
        nonisolated(unsafe) public static var text_primary_color: UIColor = .white
        nonisolated(unsafe) public static var text_secondary_color: UIColor = .lightGray
        nonisolated(unsafe) public static var background_primary_color: UIColor = .black
        nonisolated(unsafe) public static var background_secondary_color: UIColor = .darkGray
        nonisolated(unsafe) public static var tvSearchAgainBtnBgColor: UIColor = .darkGray
        nonisolated(unsafe) public static var bgTertiaryD3: UIColor = .darkGray
        nonisolated(unsafe) public static var newTextPrimary: UIColor = .white
        nonisolated(unsafe) public static var opacity_02_color: UIColor = .gray
        nonisolated(unsafe) public static var opacity_divider_color: UIColor = .gray
        nonisolated(unsafe) public static var opacity_border_color: UIColor = .gray
        nonisolated(unsafe) public static var tvFloatBtnBgColor: UIColor = .darkGray
    }
    public struct images {
        nonisolated(unsafe) public static var tv_cast_icon: UIImage?
        nonisolated(unsafe) public static var tv_cast_warning: UIImage?
        nonisolated(unsafe) public static var tv_cast_close: UIImage?
        nonisolated(unsafe) public static var tv_cast_scaning: UIImage?
        nonisolated(unsafe) public static var tv_volume_up: UIImage?
        nonisolated(unsafe) public static var tv_volume_down: UIImage?
        nonisolated(unsafe) public static var tv_album_pre: UIImage?
        nonisolated(unsafe) public static var tv_album_next: UIImage?
        nonisolated(unsafe) public static var tv_cast_bg: UIImage?
        nonisolated(unsafe) public static var tv_album_pause: UIImage?
        nonisolated(unsafe) public static var tv_album_play: UIImage?
    }
}

public struct R {
    public struct image {
        public static func album_floating_red_arrow() -> UIImage? { nil }
        public static func tv_cast_entry_icon() -> UIImage? { nil }
    }
}

extension UIFont {
    public static func mediumFont(_ size: CGFloat) -> UIFont { .systemFont(ofSize: size, weight: .medium) }
    public static func regularFont(_ size: CGFloat) -> UIFont { .systemFont(ofSize: size, weight: .regular) }
    public static func semiFont(_ size: CGFloat) -> UIFont { .systemFont(ofSize: size, weight: .semibold) }
}

// MARK: - Demo 测试数据

public struct DRBTVDemoVideo: Sendable {
    public let name: String
    public let url: String
    public init(name: String, url: String) {
        self.name = name
        self.url = url
    }
}

public struct DRBTVDemoVideoSection: Sendable {
    public let title: String
    public let items: [DRBTVDemoVideo]
    public init(title: String, items: [DRBTVDemoVideo]) {
        self.title = title
        self.items = items
    }
}

public enum DRBTVDemoData {
    public static let sections: [DRBTVDemoVideoSection] = [
        DRBTVDemoVideoSection(title: "M3U8 / HLS", items: [
            DRBTVDemoVideo(name: "电视无信号", url: "https://playertest.longtailvideo.com/adaptive/bipbop/gear4/prog_index.m3u8"),
            DRBTVDemoVideo(name: "大白兔动画片", url: "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8"),
            DRBTVDemoVideo(name: "Skate Phantom 4K", url: "http://sample.vodobox.net/skate_phantom_flex_4k/skate_phantom_flex_4k.m3u8"),
            DRBTVDemoVideo(name: "Wowza ID3", url: "http://playertest.longtailvideo.com/adaptive/wowzaid3/playlist.m3u8"),
            DRBTVDemoVideo(name: "JW Player Manifest", url: "http://content.jwplatform.com/manifests/vM7nH0Kl.m3u8"),
            DRBTVDemoVideo(name: "Apple IPTV", url: "http://qthttp.apple.com.edgesuite.net/1010qwoeiuryfg/sl.m3u8"),
            DRBTVDemoVideo(name: "Apple BipBop 16x9", url: "https://devimages.apple.com.edgekey.net/streaming/examples/bipbop_16x9/bipbop_16x9_variant.m3u8"),
            DRBTVDemoVideo(name: "Canal Mediaserver", url: "https://canal.mediaserver.com.co/live/buenisimatv.m3u8"),
            DRBTVDemoVideo(name: "143b Live Cam", url: "https://live.143b.ch/cam/flux/ts:abr.m3u8"),
            DRBTVDemoVideo(name: "切橘子", url: "https://assets.afcdn.com/video49/20210722/v_645516.m3u8"),
            DRBTVDemoVideo(name: "Fitfest Sample", url: "https://diceyk6a7voy4.cloudfront.net/e78752a1-2e83-43fa-85ae-3d508be29366/hls/fitfest-sample-1_Ott_Hls_Ts_Avc_Aac_16x9_1280x720p_30Hz_6.0Mbps_qvbr.m3u8"),
            DRBTVDemoVideo(name: "西瓜播放器", url: "https://sf1-cdn-tos.huoshanstatic.com/obj/media-fe/xgplayer_doc_video/hls/xgplayer-demo.m3u8"),
            DRBTVDemoVideo(name: "耳机广告", url: "https://flipfit-cdn.akamaized.net/flip_hls/6656423247ffe600199e8363-15125d/video_h1.m3u8"),
            DRBTVDemoVideo(name: "打印机广告", url: "https://flipfit-cdn.akamaized.net/flip_hls/664d87dfe8e47500199e49e-dbd56b/video_h1.m3u8"),
            DRBTVDemoVideo(name: "吃东西", url: "https://flipfit-cdn.akamaized.net/flip_hls/661f570aab9d840019942b80-473e0b/video_h1.m3u8"),
            DRBTVDemoVideo(name: "失败的（对照用）", url: "https://flipfit-cdn.akamaized.net/flip_hls/663d1244f22a010019f3ec12-f3c958/video_h1.m3u8")
        ]),
        DRBTVDemoVideoSection(title: "MP4", items: [
            DRBTVDemoVideo(name: "海洋", url: "http://vjs.zencdn.net/v/oceans.mp4"),
            DRBTVDemoVideo(name: "西瓜视频 Demo", url: "https://sf1-cdn-tos.huoshanstatic.com/obj/media-fe/xgplayer_doc_video/mp4/xgplayer-demo-360p.mp4"),
            DRBTVDemoVideo(name: "大兔子", url: "http://www.w3school.com.cn/example/html5/mov_bbb.mp4"),
            DRBTVDemoVideo(name: "大灰熊", url: "https://www.w3schools.com/html/movie.mp4"),
            DRBTVDemoVideo(name: "冰川", url: "https://media.w3.org/2010/05/sintel/trailer.mp4"),
            DRBTVDemoVideo(name: "新闻视频 1", url: "https://stream7.iqilu.com/10339/upload_transcode/202002/09/20200209105011F0zPoYzHry.mp4"),
            DRBTVDemoVideo(name: "新闻视频 2", url: "https://stream7.iqilu.com/10339/upload_transcode/202002/09/20200209104902N3v5Vpxuvb.mp4")
        ]),
        DRBTVDemoVideoSection(title: "电视直播", items: [
            DRBTVDemoVideo(name: "TV 播放", url: "http://ali-m-l.cztv.com/channels/lantian/channel21/720p.m3u8")
        ])
    ]
}
#endif
