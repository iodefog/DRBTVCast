import Foundation

/// 解析 GetPositionInfo 响应 XML
final class PositionInfoParser: NSObject, XMLParserDelegate {

    private let data: Data
    private var currentElement = ""
    private var currentText = ""
    private var relTime = ""
    private var duration = ""

    init(data: Data) {
        self.data = data
    }

    func parse() -> DLNACastPositionInfo? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()

        let currentSeconds = parseTimeString(relTime)
        let totalSeconds = parseTimeString(duration)

        guard totalSeconds > 0 else { return nil }

        return DLNACastPositionInfo(currentTime: currentSeconds, duration: totalSeconds)
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        currentElement = elementName
        currentText = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "RelTime":
            relTime = trimmed
        case "TrackDuration":
            duration = trimmed
        default:
            break
        }
    }

    private func parseTimeString(_ time: String) -> TimeInterval {
        // 格式: HH:MM:SS 或 HH:MM:SS.xxx
        let parts = time.components(separatedBy: ":")
        guard parts.count == 3 else { return 0 }
        let hours = Double(parts[0]) ?? 0
        let minutes = Double(parts[1]) ?? 0
        let seconds = Double(parts[2]) ?? 0
        return hours * 3600 + minutes * 60 + seconds
    }
}

/// 解析 GetTransportInfo 响应 XML，提取 CurrentTransportState
final class TransportInfoParser: NSObject, XMLParserDelegate {

    private let data: Data
    private var currentElement = ""
    private var currentText = ""
    private var transportState = "UNKNOWN"

    init(data: Data) {
        self.data = data
    }

    func parse() -> String {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return transportState
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        currentElement = elementName
        currentText = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        if elementName == "CurrentTransportState" {
            transportState = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
