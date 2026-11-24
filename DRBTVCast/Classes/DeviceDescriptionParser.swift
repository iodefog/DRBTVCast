import Foundation

/// 解析设备描述 XML，提取 friendlyName、controlURL 等关键信息
final class DeviceDescriptionParser: NSObject, XMLParserDelegate {

    private let data: Data
    private let location: URL
    private let usn: String

    private var currentElement = ""
    private var currentText = ""
    private var friendlyName = ""
    private var manufacturer = ""
    private var modelName = ""
    private var controlURL = ""
    private var eventSubURL = ""
    private var renderingControlURL = ""
    private var baseURL: URL?

    private var tempServiceType = ""
    private var tempControlURL = ""
    private var tempEventSubURL = ""

    init(data: Data, location: URL, usn: String) {
        self.data = data
        self.location = location
        self.usn = usn
    }

    func parse() -> DLNADevice? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()

        guard !friendlyName.isEmpty else { return nil }
        
        #if DEBUG
        if controlURL.isEmpty {
            if let xmlString = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) {
                print("【DRBTVCast】WARNING: AVTransport controlURL not found! Raw XML for \(friendlyName):\n\(xmlString)")
            } else {
                print("【DRBTVCast】WARNING: AVTransport controlURL not found for \(friendlyName), and XML could not be decoded as string.")
            }
        }
        #endif

        let base = baseURL ?? URL(string: "/", relativeTo: location)?.absoluteURL ?? location

        let resolveURL: (String) -> URL? = { urlString in
            guard !urlString.isEmpty else { return nil }
            if urlString.hasPrefix("http") {
                return URL(string: urlString)
            }
            let fixedString = urlString.hasPrefix("/") ? urlString : "/\(urlString)"
            return URL(string: fixedString, relativeTo: base)
        }

        let resolvedControlURL = resolveURL(controlURL)
        let resolvedEventURL = resolveURL(eventSubURL)
        let resolvedRenderingURL = resolveURL(renderingControlURL)

        return DLNADevice(
            id: usn,
            friendlyName: friendlyName,
            manufacturer: manufacturer,
            modelName: modelName,
            location: location,
            controlURL: resolvedControlURL,
            eventSubURL: resolvedEventURL,
            renderingControlURL: resolvedRenderingURL
        )
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        currentElement = elementName
        currentText = ""
        if elementName == "service" {
            tempServiceType = ""
            tempControlURL = ""
            tempEventSubURL = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch elementName {
        case "friendlyName":
            if friendlyName.isEmpty { friendlyName = trimmed }
        case "manufacturer":
            if manufacturer.isEmpty { manufacturer = trimmed }
        case "modelName":
            if modelName.isEmpty { modelName = trimmed }
        case "URLBase":
            baseURL = URL(string: trimmed)
        case "serviceType":
            tempServiceType = trimmed
        case "controlURL":
            tempControlURL = trimmed
        case "eventSubURL":
            tempEventSubURL = trimmed
        case "service":
            if tempServiceType.localizedCaseInsensitiveContains("AVTransport") {
                if controlURL.isEmpty { controlURL = tempControlURL }
                if eventSubURL.isEmpty { eventSubURL = tempEventSubURL }
            } else if tempServiceType.localizedCaseInsensitiveContains("RenderingControl") {
                if renderingControlURL.isEmpty { renderingControlURL = tempControlURL }
            }
        default:
            break
        }

        currentText = ""
    }
}
