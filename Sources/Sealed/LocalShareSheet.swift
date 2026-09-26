//
//  LocalShareSheet.swift
//  YayaShot (sealed build)
//
//  Replaces upstream's cloud upload. "Share" now opens the macOS share sheet
//  (AirDrop, Messages, Mail, Notes, and any installed share extensions), so a
//  file only leaves the Mac through a service the user picks, and never
//  through a YayaShot server or bucket.
//

import AppKit

enum LocalShareSheet {
    /// Shows the macOS share sheet for `url`. It anchors to `view` when one is
    /// given, otherwise to the window under the pointer.
    static func present(_ url: URL, from view: NSView? = nil) {
        let picker = NSSharingServicePicker(items: [url])
        if let view {
            picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
            return
        }
        let mouse = NSEvent.mouseLocation
        let window = NSApp.windows.first { $0.isVisible && $0.frame.contains(mouse) }
            ?? NSApp.keyWindow
            ?? NSApp.windows.first { $0.isVisible }
        guard let window, let content = window.contentView else {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return
        }
        let point = content.convert(window.convertPoint(fromScreen: mouse), from: nil)
        picker.show(relativeTo: NSRect(x: point.x, y: point.y, width: 1, height: 1), of: content, preferredEdge: .minY)
    }
}
