import Foundation
import Darwin

/// SSDP 设备发现器 — 使用 POSIX UDP socket 发送组播搜索，接收任意来源的单播响应
public final class SSDPDiscovery: @unchecked Sendable {

    private let multicastGroup = "239.255.255.250"
    private let multicastPort: UInt16 = 1900
    private let searchTargets = [
        "urn:schemas-upnp-org:device:MediaRenderer:1",
        "urn:schemas-upnp-org:service:AVTransport:1",
        "urn:schemas-upnp-org:service:RenderingControl:1"
    ]

    private let queue = DispatchQueue(label: "com.drb.cast.ssdp", qos: .userInitiated)
    private let lock = NSLock()
    private var discoveredDevices: [String: DLNADevice] = [:]
    private var isSearching = false
    private var socketFD: Int32 = -1

    public var onDeviceFound: ((DLNADevice) -> Void)?
    public var onDeviceLost: ((DLNADevice) -> Void)?
    public var onError: ((Error) -> Void)?

    public init() {}

    deinit {
        stopSearch()
    }

    // MARK: - Public

    /// 开始搜索设备
    public func startSearch(timeout: TimeInterval = 10) {
        guard !isSearching else { return }
        isSearching = true
        lock.lock()
        discoveredDevices.removeAll()
        lock.unlock()

        queue.async { [weak self] in
            self?.performSearch(timeout: timeout)
        }
    }

    /// 停止搜索
    public func stopSearch() {
        isSearching = false
        if socketFD >= 0 {
            Darwin.close(socketFD)
            socketFD = -1
        }
    }

    // MARK: - Private

    private func performSearch(timeout: TimeInterval) {
        // 创建 UDP socket
        socketFD = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard socketFD >= 0 else {
            reportError("Failed to create socket: \(errno)")
            return
        }

        // SO_REUSEADDR
        var reuse: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        // 设置0.5秒接收超时，确保不丢失接收又可以定期重发
        var tv = timeval(tv_sec: 0, tv_usec: 500_000)
        setsockopt(socketFD, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        // 构造组播目标地址
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = multicastPort.bigEndian
        inet_pton(AF_INET, multicastGroup, &addr.sin_addr)

        // 构造多组 M-SEARCH 报文
        var messageDatas: [[UInt8]] = []
        for target in searchTargets {
            let message = buildMSearchMessage(target: target)
            messageDatas.append(Array(message.utf8))
        }

        var buffer = [UInt8](repeating: 0, count: 4096)
        let startTime = CFAbsoluteTimeGetCurrent()
        var lastSendTime: TimeInterval = 0

        while isSearching && (CFAbsoluteTimeGetCurrent() - startTime) < timeout {
            let currentTime = CFAbsoluteTimeGetCurrent()
            // 每 1.5 秒重新发送一次所有报文，确保不丢包
            if currentTime - lastSendTime >= 1.5 {
                withUnsafePointer(to: &addr) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                        for data in messageDatas {
                            _ = sendto(socketFD, data, data.count, 0, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                        }
                    }
                }
                lastSendTime = currentTime
            }

            let bytesRead = recv(socketFD, &buffer, buffer.count, 0)
            if bytesRead > 0, let response = String(bytes: buffer[0..<bytesRead], encoding: .utf8) {
                parseSSDPResponse(response)
            }
        }

        // 清理
        if socketFD >= 0 {
            Darwin.close(socketFD)
            socketFD = -1
        }
        isSearching = false
    }

    private func buildMSearchMessage(target: String) -> String {
        "M-SEARCH * HTTP/1.1\r\nHOST: \(multicastGroup):\(multicastPort)\r\nMAN: \"ssdp:discover\"\r\nMX: 1\r\nST: \(target)\r\n\r\n"
    }

    private func parseSSDPResponse(_ response: String) {
        let lines = response.components(separatedBy: "\r\n")
        var headers: [String: String] = [:]

        for line in lines {
            if let colonIndex = line.firstIndex(of: ":") {
                let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces).lowercased()
                let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }

        // SSDP LOCATION header 可能带 "http" scheme, 需要拼回来
        guard let locationString = extractLocation(from: response),
              let locationURL = URL(string: locationString) else { return }

        let rawUSN = headers["usn"] ?? locationString
        // 提取设备 UUID 基础部分，去掉 "::urn:schemas-upnp-org:..." 后缀，防止多目标搜索产生同一个设备的多个分身
        let deviceId = rawUSN.components(separatedBy: "::").first ?? rawUSN

        // 去重
        lock.lock()
        let isKnown = (discoveredDevices[deviceId] != nil)
        lock.unlock()
        guard !isKnown else { return }

        fetchDeviceDescription(location: locationURL, usn: deviceId)
    }

    /// 单独提取 LOCATION，避免 ":" 分割把 http:// 截断
    private func extractLocation(from response: String) -> String? {
        let lines = response.components(separatedBy: "\r\n")
        for line in lines {
            let lower = line.lowercased()
            if lower.hasPrefix("location:") {
                let value = String(line.dropFirst("location:".count)).trimmingCharacters(in: .whitespaces)
                return value
            }
        }
        return nil
    }

    private func fetchDeviceDescription(location: URL, usn: String) {
        let task = URLSession.shared.dataTask(with: location) { [weak self] data, _, _ in
            guard let self, let data else { return }
            let parser = DeviceDescriptionParser(data: data, location: location, usn: usn)
            guard let device = parser.parse() else { return }
            self.lock.lock()
            let isNew = self.discoveredDevices[usn] == nil
            if isNew {
                self.discoveredDevices[usn] = device
            }
            self.lock.unlock()
            
            if isNew {
                DispatchQueue.main.async {
                    self.onDeviceFound?(device)
                }
            }
        }
        task.resume()
    }

    private func reportError(_ message: String) {
        let error = NSError(domain: "com.drb.cast.ssdp", code: -1,
                            userInfo: [NSLocalizedDescriptionKey: message])
        DispatchQueue.main.async { [weak self] in
            self?.onError?(error)
        }
    }
}
