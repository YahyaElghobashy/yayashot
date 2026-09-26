import Foundation

/// yayashot:// automation routes. Every route that captures needs an on-screen
/// selection or click. YayaShot removed upstream's `capture/fullscreen`, which
/// let any local process take a silent full-screen screenshot through the
/// app's Screen Recording permission and read it from the clipboard.
nonisolated enum CaptureURLAction: String, CaseIterable {
    case region = "capture/region"
    case window = "capture/window"
    case scrollCapture = "capture/scroll"
    case recording = "record"
    case ocr
    case colorPicker = "color-picker"
    case settings

    init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "yayashot",
              components.user == nil, components.password == nil, components.port == nil,
              components.query == nil, components.fragment == nil,
              let host = components.host else { return nil }
        self.init(rawValue: host.lowercased() + components.path)
    }
}
