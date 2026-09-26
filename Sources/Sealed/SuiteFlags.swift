//
//  SuiteFlags.swift
//  YayaShot
//
//  Hooks for the Yaya Suite installer. Local only: nothing here touches the
//  network.
//
//    --permissions-json    print permission state as one JSON line and exit,
//                          before any window, menu-bar item or Dock icon
//    --login-item on|off   register / unregister the login item, then continue
//    --onboarding          show the welcome tour again; when it finishes, a
//                          marker file tells the installer to move on
//

import AppKit
import ApplicationServices
import AVFoundation
import CoreGraphics
import IOKit.hid
import ServiceManagement

enum SuiteFlags {
    static var handoffDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/YayaSuite/handoff", isDirectory: true)
    }

    private(set) static var suiteOnboarding = false

    /// Runs first thing in the app's init, before launch preparation marks a
    /// first run, so the installer's probe never counts as opening the app.
    static func handleEarly() {
        let args = CommandLine.arguments
        if args.contains("--permissions-json") { answerPermissionProbe() }
        if let i = args.firstIndex(of: "--login-item"), i + 1 < args.count {
            let on = args[i + 1].lowercased() == "on"
            do {
                if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                print("YayaShot: login item: \(error.localizedDescription)")
            }
        }
        if args.contains("--onboarding") { suiteOnboarding = true }
    }

    static func markOnboardingDone() {
        guard suiteOnboarding else { return }
        try? FileManager.default.createDirectory(at: handoffDirectory, withIntermediateDirectories: true)
        try? Data("done \(Date())\n".utf8).write(to: handoffDirectory.appendingPathComponent("yayashot.done"))
    }

    private static func answerPermissionProbe() -> Never {
        NSApplication.shared.setActivationPolicy(.prohibited)
        func capture(_ type: AVMediaType) -> String {
            switch AVCaptureDevice.authorizationStatus(for: type) {
            case .authorized: "granted"
            case .denied, .restricted: "denied"
            default: "undetermined"
            }
        }
        let inputMonitoring: String = switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted: "granted"
        case kIOHIDAccessTypeDenied: "denied"
        default: "undetermined"
        }
        let json: [String: Any] = [
            "app": "YayaShot",
            // macOS only reports allowed / not yet allowed for these two.
            "screenRecording": CGPreflightScreenCaptureAccess() ? "granted" : "undetermined",
            "accessibility": AXIsProcessTrusted() ? "granted" : "undetermined",
            "microphone": capture(.audio),
            "camera": capture(.video),
            "inputMonitoring": inputMonitoring,
            "loginItem": SMAppService.mainApp.status == .enabled,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]),
           let line = String(data: data, encoding: .utf8) {
            print(line)
        }
        fflush(stdout)
        exit(0)
    }
}
