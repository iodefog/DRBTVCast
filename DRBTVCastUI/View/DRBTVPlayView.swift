import UIKit
import SnapKit
import DRBTVCast

private class DRBDialButton: UIButton {
    override var isHighlighted: Bool {
        didSet {
            alpha = isHighlighted ? 0.5 : (isEnabled ? 1.0 : 0.3)
        }
    }
    
    override var isEnabled: Bool {
        didSet {
            alpha = isHighlighted ? 0.5 : (isEnabled ? 1.0 : 0.3)
        }
    }
}

@MainActor protocol DRBTVPlayViewDelegate: AnyObject {
    func tvPlayViewDidClickQuality()
    func tvPlayViewDidClickSpeed()
    func tvPlayViewDidClickEpisodes()
    func tvPlayViewDidClickPlayPause()
    func tvPlayViewDidClickLeft()
    func tvPlayViewDidClickRight()
    func tvPlayViewDidClickUp()
    func tvPlayViewDidClickDown()
    func tvPlayViewSliderDidBeginEditing()
    func tvPlayViewSliderDidEndEditing(value: Float)
}

class DRBTVPlayView: DRBBaseView {
    weak var delegate: DRBTVPlayViewDelegate?
    
    // MARK: - UI Components
    private lazy var bgImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        return imageView
    }()
    
    private lazy var bgOverlayView: UIView = {
        let view = UIView()
        return view
    }()
    
    // 3. Title
    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .center
        label.numberOfLines = 2
        label.font = .semiFont(16)
        return label
    }()
    
    // 4. Episode
    private lazy var episodeLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .center
        label.font = .regularFont(14)
        label.numberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        return label
    }()
    
    // 5. Options (Quality, Speed, Episodes)
    private lazy var optionsStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.distribution = .fill
        stackView.spacing = 0
        stackView.layer.cornerRadius = fitScale(8)
        stackView.layer.masksToBounds = true
        return stackView
    }()
    
    private lazy var optionsBgView: UIView = {
        let view = UIView()
        view.layer.cornerRadius = fitScale(8)
        return view
    }()
    
    private lazy var qualityButton: UIButton = {
        let button = UIButton(type: .custom)
        button.addTarget(self, action: #selector(qualityAction), for: .touchUpInside)
        return button
    }()
    
    private lazy var divider1: UIView = {
        let view = UIView()
        return view
    }()
    
    private lazy var speedButton: UIButton = {
        let button = UIButton(type: .custom)
        button.addTarget(self, action: #selector(speedAction), for: .touchUpInside)
        return button
    }()
    
    private lazy var divider2: UIView = {
        let view = UIView()
        return view
    }()
    
    private lazy var episodesButton: UIButton = {
        let button = UIButton(type: .custom)
        button.addTarget(self, action: #selector(episodesAction), for: .touchUpInside)
        return button
    }()
    
    // 6. Control Dial
    private lazy var dialContainerView: UIView = {
        let view = UIView()
        view.layer.cornerRadius = fitScale(106) // 212 / 2
        view.layer.borderWidth = 1
        return view
    }()
    
    private lazy var upButton: UIButton = {
        let button = DRBDialButton(type: .custom)
        button.addTarget(self, action: #selector(upAction), for: .touchUpInside)
        return button
    }()
    
    private lazy var downButton: UIButton = {
        let button = DRBDialButton(type: .custom)
        button.addTarget(self, action: #selector(downAction), for: .touchUpInside)
        return button
    }()
    
    private lazy var leftButton: UIButton = {
        let button = DRBDialButton(type: .custom)
        button.addTarget(self, action: #selector(leftAction), for: .touchUpInside)
        return button
    }()
    
    private lazy var rightButton: UIButton = {
        let button = DRBDialButton(type: .custom)
        button.addTarget(self, action: #selector(rightAction), for: .touchUpInside)
        return button
    }()
    
    private lazy var playPauseBgView: UIView = {
        let view = UIView()
        view.layer.cornerRadius = fitScale(43)
        view.layer.borderWidth = 1
        view.isUserInteractionEnabled = false
        return view
    }()
    
    private lazy var playPauseButton: UIButton = {
        let button = UIButton(type: .custom)
        button.addTarget(self, action: #selector(playPauseAction), for: .touchUpInside)
        return button
    }()
    
    // 7. Progress Bar
    private lazy var slider: DRBPlayerSlider = {
        let slider = DRBPlayerSlider()
        slider.alwaysShowWhiteThumb = true
        slider.isFixedStyle = true
        slider.fixedThumbSize = CGSize(width: fitScale(14), height: fitScale(14))
        slider.delegate = self
        return slider
    }()
    
    private lazy var currentTimeLabel: UILabel = {
        let label = UILabel()
        label.text = "00:00"
        label.font = .mediumFont(12)
        return label
    }()
    
    private lazy var totalTimeLabel: UILabel = {
        let label = UILabel()
        label.text = "00:00"
        label.font = .mediumFont(12)
        label.textAlignment = .right
        return label
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        changeTheme()
        addThemeChangeObserver()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        tintAdjustmentMode = .normal
        
        addSubview(bgImageView)
        addSubview(bgOverlayView)
        
        addSubview(titleLabel)
        addSubview(episodeLabel)
        
        addSubview(optionsBgView)
        addSubview(optionsStackView)
        optionsStackView.addArrangedSubview(qualityButton)
        optionsStackView.addArrangedSubview(divider1)
        optionsStackView.addArrangedSubview(speedButton)
        optionsStackView.addArrangedSubview(divider2)
        optionsStackView.addArrangedSubview(episodesButton)
        
        addSubview(dialContainerView)
        dialContainerView.addSubview(playPauseBgView)
        dialContainerView.addSubview(upButton)
        dialContainerView.addSubview(downButton)
        dialContainerView.addSubview(leftButton)
        dialContainerView.addSubview(rightButton)
        dialContainerView.addSubview(playPauseButton)
        
        addSubview(slider)
        addSubview(currentTimeLabel)
        addSubview(totalTimeLabel)
        
        bgImageView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        bgOverlayView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        titleLabel.snp.makeConstraints { make in
            make.top.equalTo(safeAreaLayoutGuide.snp.top).offset(fitScale(60))
            make.left.equalToSuperview().offset(fitScale(16))
            make.right.equalToSuperview().offset(-fitScale(16))
        }
        
        episodeLabel.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(8)
            make.left.right.equalTo(titleLabel)
        }
        
        optionsBgView.snp.makeConstraints { make in
            make.edges.equalTo(optionsStackView)
        }
        
        optionsStackView.snp.makeConstraints { make in
            make.top.equalTo(episodeLabel.snp.bottom).offset(fitScale(32))
            make.centerX.equalToSuperview()
            make.leading.greaterThanOrEqualToSuperview().offset(fitScale(16))
            make.trailing.lessThanOrEqualToSuperview().offset(fitScale(-16))
            make.height.equalTo(fitScale(40))
        }
        
        qualityButton.snp.makeConstraints { make in
            make.height.equalTo(fitScale(40))
            make.width.equalTo(fitScale(100))
        }
        setupOptionButton(qualityButton, title: Loc.shared().str_video_auto_quality(720), insets: UIEdgeInsets(top: fitScale(12), left: fitScale(16), bottom: fitScale(12), right: fitScale(16)))
        
        divider1.snp.makeConstraints { make in
            make.width.equalTo(fitScale(1))
            make.height.equalTo(fitScale(12))
        }
        
        speedButton.snp.makeConstraints { make in
            make.height.equalTo(fitScale(40))
            make.width.equalTo(fitScale(100))
        }
        setupOptionButton(speedButton, title: "1.0x", insets: UIEdgeInsets(top: fitScale(12), left: fitScale(16), bottom: fitScale(12), right: fitScale(16)))
        
        divider2.snp.makeConstraints { make in
            make.width.equalTo(fitScale(1))
            make.height.equalTo(fitScale(12))
        }
        
        episodesButton.snp.makeConstraints { make in
            make.height.equalTo(fitScale(40))
            make.width.equalTo(fitScale(100))
        }
        setupOptionButton(episodesButton, title: Loc.shared().str_series(), insets: UIEdgeInsets(top: fitScale(12), left: fitScale(16), bottom: fitScale(12), right: fitScale(16)))
        
        dialContainerView.snp.makeConstraints { make in
            make.top.equalTo(optionsStackView.snp.bottom).offset(fitScale(80))
            make.centerX.equalToSuperview()
            make.height.equalTo(fitScale(212))
            make.width.equalTo(dialContainerView.snp.height)
        }
        
        playPauseBgView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.height.equalTo(fitScale(86))
        }
        
        playPauseButton.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.height.equalTo(fitScale(32))
        }
        
        upButton.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(fitScale(9.5))
            make.centerX.equalToSuperview()
            make.width.height.equalTo(fitScale(44))
        }
        
        downButton.snp.makeConstraints { make in
            make.bottom.equalToSuperview().offset(-fitScale(9.5))
            make.centerX.equalToSuperview()
            make.width.height.equalTo(fitScale(44))
        }
        
        leftButton.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(fitScale(9.5))
            make.centerY.equalToSuperview()
            make.width.height.equalTo(fitScale(44))
        }
        
        rightButton.snp.makeConstraints { make in
            make.right.equalToSuperview().offset(-fitScale(9.5))
            make.centerY.equalToSuperview()
            make.width.height.equalTo(fitScale(44))
        }
        
        slider.snp.makeConstraints { make in
            make.top.equalTo(dialContainerView.snp.bottom).offset(fitScale(80))
            make.centerX.equalToSuperview()
            make.width.equalTo(fitScale(343))
            make.height.equalTo(fitScale(34))
        }
        
        currentTimeLabel.snp.makeConstraints { make in
            make.bottom.equalTo(slider.snp.top).offset(fitScale(3))
            make.left.equalTo(slider)
        }
        
        totalTimeLabel.snp.makeConstraints { make in
            make.bottom.equalTo(currentTimeLabel.snp.bottom)
            make.right.equalTo(slider)
        }
    }
    
    override func changeTheme() {
        titleLabel.textColor = DRBResource.colors.text_primary_color
        episodeLabel.textColor = DRBResource.colors.text_secondary_color
        
        let optionTextColor = DRBResource.colors.text_primary_color
        if var config = qualityButton.configuration {
            config.baseForegroundColor = optionTextColor
            qualityButton.configuration = config
        }
        if var config = speedButton.configuration {
            config.baseForegroundColor = optionTextColor
            speedButton.configuration = config
        }
        if var config = episodesButton.configuration {
            config.baseForegroundColor = optionTextColor
            episodesButton.configuration = config
        }
        
        optionsBgView.backgroundColor = DRBResource.colors.opacity_02_color
        let dividerColor = DRBResource.colors.opacity_divider_color
        divider1.backgroundColor = dividerColor
        divider2.backgroundColor = dividerColor
        
        dialContainerView.layer.borderColor = DRBResource.colors.opacity_border_color.cgColor
        
        // Linear gradient for dial
        if let sublayers = dialContainerView.layer.sublayers {
            for layer in sublayers where layer is CAGradientLayer {
                layer.removeFromSuperlayer()
            }
        }
        let gradientLayer = CAGradientLayer()
        gradientLayer.frame = CGRect(x: 0, y: 0, width: fitScale(212), height: fitScale(212))
        gradientLayer.cornerRadius = fitScale(106)
        #if DRB_CAST_DEMO
        let isLight = false
        #else
        let isLight = DRBThemeManager.shared.current is DRBLightTheme
        #endif
        if isLight {
            gradientLayer.colors = [UIColor(white: 0, alpha: 0.06).cgColor, UIColor(white: 0, alpha: 0.02).cgColor]
        } else {
            gradientLayer.colors = [UIColor(white: 1, alpha: 0.12).cgColor, UIColor(white: 1, alpha: 0.06).cgColor]
        }
        dialContainerView.layer.insertSublayer(gradientLayer, at: 0)
        
        // Linear gradient for playPauseBgView
        if let sublayers = playPauseBgView.layer.sublayers {
            for layer in sublayers where layer is CAGradientLayer {
                layer.removeFromSuperlayer()
            }
        }
        let playBgGradientLayer = CAGradientLayer()
        playBgGradientLayer.frame = CGRect(x: 0, y: 0, width: fitScale(86), height: fitScale(86))
        playBgGradientLayer.cornerRadius = fitScale(43)
        if isLight {
            let playColor1 = UIColor(white: 0, alpha: 0.08)
            let playColor2 = UIColor(white: 0, alpha: 0.01)
            playBgGradientLayer.colors = [playColor1.cgColor, playColor2.cgColor]
            playPauseBgView.layer.borderColor = UIColor(white: 1, alpha: 0.06).cgColor
        } else {
            let playColor1 = UIColor(red: 23/255.0, green: 14/255.0, blue: 17/255.0, alpha: 1.0)
            let playColor2 = UIColor(red: 23/255.0, green: 14/255.0, blue: 17/255.0, alpha: 0.2)
            playBgGradientLayer.colors = [playColor1.cgColor, playColor2.cgColor]
            playPauseBgView.layer.borderColor = UIColor(white: 1, alpha: 0.06).cgColor
        }
        playPauseBgView.layer.insertSublayer(playBgGradientLayer, at: 0)
        
        let timeColor = DRBResource.colors.text_secondary_color
        currentTimeLabel.textColor = timeColor
        totalTimeLabel.textColor = timeColor
        
        // Update images based on DRBResource.images
        upButton.setImage(DRBResource.images.tv_volume_up, for: .normal)
        upButton.setImage(DRBResource.images.tv_volume_up, for: .highlighted)
        downButton.setImage(DRBResource.images.tv_volume_down, for: .normal)
        downButton.setImage(DRBResource.images.tv_volume_down, for: .highlighted)
        leftButton.setImage(DRBResource.images.tv_album_pre, for: .normal)
        leftButton.setImage(DRBResource.images.tv_album_pre, for: .highlighted)
        rightButton.setImage(DRBResource.images.tv_album_next, for: .normal)
        rightButton.setImage(DRBResource.images.tv_album_next, for: .highlighted)
        
        bgImageView.image = DRBResource.images.tv_cast_bg
        
        let isPlaying = (DLNACastManager.shared.playbackState == .playing)
        updatePlayState(isPlaying: isPlaying)
        
        slider.updateTheme()
    }
    
    @objc private func qualityAction() {
        delegate?.tvPlayViewDidClickQuality()
    }
    
    @objc private func speedAction() {
        delegate?.tvPlayViewDidClickSpeed()
    }
    
    @objc private func episodesAction() {
        delegate?.tvPlayViewDidClickEpisodes()
    }
    
    @objc private func playPauseAction() {
        delegate?.tvPlayViewDidClickPlayPause()
    }
    
    @objc private func upAction() {
        delegate?.tvPlayViewDidClickUp()
    }
    
    @objc private func downAction() {
        delegate?.tvPlayViewDidClickDown()
    }
    
    @objc private func leftAction() {
        delegate?.tvPlayViewDidClickLeft()
    }
    
    @objc private func rightAction() {
        delegate?.tvPlayViewDidClickRight()
    }
    
    // MARK: - Private Helper Methods
    
    private func setupOptionButton(_ button: UIButton, title: String, insets: UIEdgeInsets) {
        var config = UIButton.Configuration.plain()
        config.contentInsets = NSDirectionalEdgeInsets(top: insets.top, leading: insets.left, bottom: insets.bottom, trailing: insets.right)
        config.title = title
        config.titleLineBreakMode = .byTruncatingTail
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .semiFont(13)
            return outgoing
        }
        config.baseForegroundColor = DRBResource.colors.text_primary_color
        config.background.backgroundColor = .clear
        button.configuration = config
        
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.7
    }
    
    // MARK: - Public Helper Methods
    
    func setVolumeControlsEnabled(_ enabled: Bool) {
        upButton.isEnabled = enabled
        downButton.isEnabled = enabled
    }
    
    func updatePlayState(isPlaying: Bool, isLoading: Bool = false) {
        let image = isPlaying ? DRBResource.images.tv_album_pause : DRBResource.images.tv_album_play
        playPauseButton.setImage(image, for: .normal)
    }

    func updateProgress(currentTime: TimeInterval, duration: TimeInterval) {
        if duration <= 0 {
            slider.value = 0
            currentTimeLabel.text = "00:00"
            totalTimeLabel.text = "00:00"
            return
        }
        let safeCurrentTime = min(max(currentTime, 0), duration)
        let progress = safeCurrentTime / duration
        slider.value = CGFloat(progress)
        
        currentTimeLabel.text = formatTime(seconds: safeCurrentTime)
        totalTimeLabel.text = formatTime(seconds: duration)
    }

    private func formatTime(seconds: TimeInterval) -> String {
        guard !seconds.isNaN, !seconds.isInfinite, seconds >= 0 else { return "00:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    func updateMediaInfo(title: String?, episode: String?) {
        if let title = title {
            titleLabel.text = title
        }
        
        if let ep = episode {
            episodeLabel.text = ep
            episodeLabel.isHidden = false
        } else {
            episodeLabel.isHidden = true
        }
    }

    func updateQualityTitle(_ title: String) {
        if var config = qualityButton.configuration {
            config.title = title
            qualityButton.configuration = config
        }
    }

    func updateSpeedTitle(_ title: String) {
        if var config = speedButton.configuration {
            config.title = title
            speedButton.configuration = config
        }
    }
}

// MARK: - DRBPlayerSliderDelegate

extension DRBTVPlayView: DRBPlayerSliderDelegate {
    func sliderDidStartDragging(_ slider: DRBPlayerSlider) {
        delegate?.tvPlayViewSliderDidBeginEditing()
    }
    
    func slider(_ slider: DRBPlayerSlider, valueDidChanged value: CGFloat) {
        delegate?.tvPlayViewSliderDidEndEditing(value: Float(value))
    }
    
    func sliding(_ slider: DRBPlayerSlider, sliderValue: CGFloat) {
        // Can update current time label during drag if desired
    }
    
    func tapTopView(_ slider: DRBPlayerSlider, guesture: UIPanGestureRecognizer) {
        // Handle tap if needed
    }
}
