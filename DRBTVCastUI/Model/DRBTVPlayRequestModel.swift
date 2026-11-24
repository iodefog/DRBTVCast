//
//  DRBTVPlayRequestModel.swift
//  DramaBox
//
//  Created by LHL on 2026/7/2.
//
import Foundation

#if !DRB_CAST_DEMO
enum DRBTVPlayRequestModel {
    /**
     * 获取投屏视频播放地址
     * bookId: 短剧ID
     * chapterIds: 章节ID列表，多个以逗号分割
     * currencyPlaySource: 本次播放来源ID
     * currencyPlaySourceName: 本次播放来源名称
     */
    case batchVideoPath(bookId: String?, chapterIds: [String: String]?, currencyPlaySource: String?, currencyPlaySourceName: String?)
}

extension DRBTVPlayRequestModel: DRBRequestable {
    var params: [String: Any]? {
        switch self {
        case .batchVideoPath(let bookId, let chapterIds, let currencyPlaySource, let currencyPlaySourceName):
            var params = [String: Any]()
            params["bookId"] = bookId
            params["chapterMap"] = chapterIds
            params["currencyPlaySource"] = currencyPlaySource
            params["currencyPlaySourceName"] = currencyPlaySourceName
            return params
        }
    }
    
    var requiredParams: [String]? {
        switch self {
        case .batchVideoPath:
            return ["bookId", "chapterIds"]
        }
    }
    
    var requestPath: String! {
        switch self {
        case .batchVideoPath:
            return "/drama-box/chapterv2/batch/videoPath"
        }
    }
}

class DRBTVBatchVideoPathResponseModel {
    var bookId: String?
    var chapterVideoList: [DRBTVChapterVideoModel]?

    init(dict: [String: Any]) {
        bookId = dict["bookId"] as? String
        if let list = dict["chapterVideoList"] as? [[String: Any]] {
            chapterVideoList = list.map { DRBTVChapterVideoModel(dict: $0) }
        }
    }
}

class DRBTVChapterVideoModel {
    var chapterId: String?
    var chapterIndex: Int?
    var chapterName: String?
    var cdnList: [DRBTVCDNModel]?

    init(dict: [String: Any]) {
        chapterId = dict["chapterId"] as? String
        chapterIndex = dict["chapterIndex"] as? Int
        chapterName = dict["chapterName"] as? String
        if let list = dict["cdnList"] as? [[String: Any]] {
            cdnList = list.map { item in
                let qualities = (item["videoPathList"] as? [[String: Any]])?.map {
                    DRBTVQualityModel(videoPath: $0["videoPath"] as? String,
                                      quality: $0["quality"] as? Int)
                }
                return DRBTVCDNModel(cdnDomain: item["cdnDomain"] as? String,
                                     isDefault: item["isDefault"] as? Int,
                                     videoPath: item["videoPath"] as? String,
                                     videoPathList: qualities)
            }
        }
    }
}
#endif
