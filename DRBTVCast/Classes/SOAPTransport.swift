import Foundation

/// DLNA SOAP 请求封装 — 负责构建和发送 AVTransport 控制指令
final class SOAPTransport: @unchecked Sendable {

    private let session: URLSession

    init() {
        // 使用 ephemeral 配置：不复用连接，避免 DLNA 设备对 keep-alive 的兼容问题
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldUsePipelining = false
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        self.session = URLSession(configuration: config)
    }

    // MARK: - AVTransport Actions

    /// SetAVTransportURI — 设置播放 URL（带标题、集数、字幕元数据）
    func setAVTransportURI(controlURL: URL, media: DLNACastMediaInfo,
                           completion: @escaping (Result<Void, DLNACastError>) -> Void) {
        let escapedURL = media.mediaURL.xmlEscaped
        let escapedTitle = media.displayTitle.xmlEscaped

        // 视频 MIME 推断
        let mimeType = media.mediaURL.lowercased().contains("m3u8")
            ? "video/x-mpegurl" : "video/mp4"

        // 字幕资源 (DIDL-Lite 内嵌方式 — 多方案并存，最大化设备兼容)
        var subtitleRes = ""
        if let subURL = media.subtitleURL {
            let escapedSubURL = subURL.xmlEscaped
            let subMime: String
            switch media.subtitleType {
            case .srt: subMime = "application/x-subrip"
            case .vtt: subMime = "text/vtt"
            case .ass: subMime = "text/x-ssa"
            case .none: subMime = "text/plain"
            }
            // 方式1: DIDL-Lite <res> 字幕 (LG / Sony / Android 渲染器)
            subtitleRes += "&lt;res protocolInfo=&quot;http-get:*:\(subMime):*&quot;&gt;\(escapedSubURL)&lt;/res&gt;"
            // 方式2: sec:CaptionInfoEx (Samsung 新固件)
            subtitleRes += "&lt;sec:CaptionInfoEx sec:type=&quot;\(media.subtitleType.rawValue)&quot;&gt;\(escapedSubURL)&lt;/sec:CaptionInfoEx&gt;"
            // 方式3: sec:CaptionInfo (Samsung 旧固件 / 部分国产电视)
            subtitleRes += "&lt;sec:CaptionInfo&gt;\(escapedSubURL)&lt;/sec:CaptionInfo&gt;"
        }

        let body = """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:SetAVTransportURI xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              <InstanceID>0</InstanceID>
              <CurrentURI>\(escapedURL)</CurrentURI>
              <CurrentURIMetaData>
                &lt;DIDL-Lite xmlns=&quot;urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/&quot; xmlns:dc=&quot;http://purl.org/dc/elements/1.1/&quot; xmlns:upnp=&quot;urn:schemas-upnp-org:metadata-1-0/upnp/&quot; xmlns:sec=&quot;http://www.sec.co.kr/&quot;&gt;
                  &lt;item id=&quot;0&quot; parentID=&quot;-1&quot; restricted=&quot;1&quot;&gt;
                    &lt;dc:title&gt;\(escapedTitle)&lt;/dc:title&gt;
                    &lt;upnp:class&gt;object.item.videoItem&lt;/upnp:class&gt;
                    &lt;res protocolInfo=&quot;http-get:*:\(mimeType):*&quot;&gt;\(escapedURL)&lt;/res&gt;
                    \(subtitleRes)
                  &lt;/item&gt;
                &lt;/DIDL-Lite&gt;
              </CurrentURIMetaData>
            </u:SetAVTransportURI>
          </s:Body>
        </s:Envelope>
        """

        sendSOAPRequest(
            controlURL: controlURL,
            action: "SetAVTransportURI",
            body: body,
            completion: completion
        )
    }

    /// Play — 开始播放
    func play(controlURL: URL, speed: String = "1",
              completion: @escaping (Result<Void, DLNACastError>) -> Void) {
        let body = """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:Play xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              <InstanceID>0</InstanceID>
              <Speed>\(speed)</Speed>
            </u:Play>
          </s:Body>
        </s:Envelope>
        """

        sendSOAPRequest(controlURL: controlURL, action: "Play", body: body, completion: completion)
    }

    /// Pause — 暂停播放
    func pause(controlURL: URL, completion: @escaping (Result<Void, DLNACastError>) -> Void) {
        let body = """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:Pause xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              <InstanceID>0</InstanceID>
            </u:Pause>
          </s:Body>
        </s:Envelope>
        """

        sendSOAPRequest(controlURL: controlURL, action: "Pause", body: body, completion: completion)
    }

    /// Stop — 停止播放
    func stop(controlURL: URL, completion: @escaping (Result<Void, DLNACastError>) -> Void) {
        let body = """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:Stop xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              <InstanceID>0</InstanceID>
            </u:Stop>
          </s:Body>
        </s:Envelope>
        """

        sendSOAPRequest(controlURL: controlURL, action: "Stop", body: body, completion: completion)
    }

    /// Seek — 跳转到指定位置
    func seek(controlURL: URL, target: TimeInterval,
              completion: @escaping (Result<Void, DLNACastError>) -> Void) {
        let timeString = formatTime(target)
        let body = """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:Seek xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              <InstanceID>0</InstanceID>
              <Unit>REL_TIME</Unit>
              <Target>\(timeString)</Target>
            </u:Seek>
          </s:Body>
        </s:Envelope>
        """

        sendSOAPRequest(controlURL: controlURL, action: "Seek", body: body, completion: completion)
    }

    /// GetPositionInfo — 获取当前播放进度
    func getPositionInfo(controlURL: URL,
                         completion: @escaping (Result<DLNACastPositionInfo, DLNACastError>) -> Void) {
        let body = """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:GetPositionInfo xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              <InstanceID>0</InstanceID>
            </u:GetPositionInfo>
          </s:Body>
        </s:Envelope>
        """

        let request = buildRequest(controlURL: controlURL, action: "GetPositionInfo", body: body)
        session.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(.networkError(error)))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(.soapRequestFailed(statusCode: 0, body: "No HTTP response")))
                return
            }
            guard (200...299).contains(httpResponse.statusCode), let data else {
                let bodyStr = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                completion(.failure(.soapRequestFailed(statusCode: httpResponse.statusCode, body: bodyStr)))
                return
            }

            let parser = PositionInfoParser(data: data)
            if let info = parser.parse() {
                completion(.success(info))
            } else {
                completion(.failure(.xmlParsingFailed("Failed to parse GetPositionInfo response")))
            }
        }.resume()
    }

    /// 尝试通过非标准 SOAP action 注入字幕（播放开始后调用）
    /// 覆盖国产电视/安卓盒子不解析 DIDL 字幕的场景，静默失败不影响播放
    func pushSubtitleFallback(controlURL: URL, subtitleURL: String, subtitleType: DLNACastMediaInfo.SubtitleType,
                              completion: @escaping (Result<Void, DLNACastError>) -> Void) {
        let escapedSubURL = subtitleURL.xmlEscaped

        // 非标准 action: X_SetSubtitle (乐播投屏/海信/小米等设备实现)
        let body = """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:X_SetSubtitle xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              <InstanceID>0</InstanceID>
              <SubtitleURI>\(escapedSubURL)</SubtitleURI>
              <SubtitleType>\(subtitleType.rawValue)</SubtitleType>
            </u:X_SetSubtitle>
          </s:Body>
        </s:Envelope>
        """

        sendSOAPRequest(controlURL: controlURL, action: "X_SetSubtitle", body: body, completion: completion)
    }

    /// GetTransportInfo — 获取当前传输状态 (PLAYING / PAUSED_PLAYBACK / STOPPED / etc.)
    func getTransportInfo(controlURL: URL,
                          completion: @escaping (Result<String, DLNACastError>) -> Void) {
        let body = """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:GetTransportInfo xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              <InstanceID>0</InstanceID>
            </u:GetTransportInfo>
          </s:Body>
        </s:Envelope>
        """

        let request = buildRequest(controlURL: controlURL, action: "GetTransportInfo", body: body)
        session.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(.networkError(error)))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  let data else {
                let bodyStr = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                completion(.failure(.soapRequestFailed(statusCode: code, body: bodyStr)))
                return
            }

            let parser = TransportInfoParser(data: data)
            completion(.success(parser.parse()))
        }.resume()
    }

    /// SetVolume — 设置音量 (0-100)
    func setVolume(renderingControlURL: URL, volume: Int,
                   completion: @escaping (Result<Void, DLNACastError>) -> Void) {
        let body = """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:SetVolume xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1">
              <InstanceID>0</InstanceID>
              <Channel>Master</Channel>
              <DesiredVolume>\(volume)</DesiredVolume>
            </u:SetVolume>
          </s:Body>
        </s:Envelope>
        """

        sendSOAPRequest(
            controlURL: renderingControlURL,
            serviceType: "urn:schemas-upnp-org:service:RenderingControl:1",
            action: "SetVolume",
            body: body,
            completion: completion
        )
    }

    // MARK: - Private

    private func sendSOAPRequest(controlURL: URL, serviceType: String = "urn:schemas-upnp-org:service:AVTransport:1", action: String, body: String,
                                 completion: @escaping (Result<Void, DLNACastError>) -> Void) {
        let request = buildRequest(controlURL: controlURL, serviceType: serviceType, action: action, body: body)
        session.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(.networkError(error)))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(.soapRequestFailed(statusCode: 0, body: "No response")))
                return
            }
            if (200...299).contains(httpResponse.statusCode) {
                completion(.success(()))
            } else {
                let bodyStr = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                completion(.failure(.soapRequestFailed(statusCode: httpResponse.statusCode, body: bodyStr)))
            }
        }.resume()
    }

    private func buildRequest(controlURL: URL, serviceType: String = "urn:schemas-upnp-org:service:AVTransport:1", action: String, body: String) -> URLRequest {
        // 去掉 body 每行前导空格（部分设备对 XML 缩进敏感）
        let trimmedBody = body.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
        let bodyData = trimmedBody.data(using: .utf8)!

        var request = URLRequest(url: controlURL)
        request.httpMethod = "POST"
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue("\"\(serviceType)#\(action)\"", forHTTPHeaderField: "SOAPAction")
        request.setValue("close", forHTTPHeaderField: "Connection")
        request.setValue("\(bodyData.count)", forHTTPHeaderField: "Content-Length")
        request.setValue("DRBCast/1.0 UPnP/1.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = bodyData
        request.timeoutInterval = 10
        return request
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}

// MARK: - XML Helpers

private extension String {
    var xmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
