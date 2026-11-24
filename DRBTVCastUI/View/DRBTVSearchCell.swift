//
//  DRBTVSearchCell.swift
//  DramaBox
//
//  Created by LHL on 2026/6/29.
//

// MARK: - DRBTVSearchCell

class DRBTVSearchCell: UITableViewCell, Reusable {
    private lazy var iconImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        return iv
    }()
    
    private lazy var nameLabel: UILabel = {
        let label = UILabel()
        label.font = .regularFont(14)
        label.lineBreakMode = .byTruncatingTail
        label.numberOfLines = 1
        return label
    }()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        
        contentView.addSubview(iconImageView)
        contentView.addSubview(nameLabel)
        
        iconImageView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(fitScale(16))
            make.top.bottom.equalToSuperview().inset(fitScale(16))
            make.width.height.equalTo(fitScale(20))
        }
        
        nameLabel.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.leading.equalTo(iconImageView.snp.trailing).offset(fitScale(12))
            make.trailing.equalToSuperview().offset(-fitScale(16))
        }
        
        changeTheme()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func configure(with deviceName: String) {
        nameLabel.text = deviceName
    }
    
    func changeTheme() {
        nameLabel.textColor = DRBResource.colors.text_primary_color
        iconImageView.image = DRBResource.images.tv_cast_icon
    }
}
