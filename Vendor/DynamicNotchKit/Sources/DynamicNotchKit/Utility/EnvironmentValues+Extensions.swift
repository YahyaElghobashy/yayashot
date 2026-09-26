//
//  EnvironmentValues+Extensions.swift
//  DynamicNotchKit
//
//  Created by Kai Azim on 2025-03-26.
//

import SwiftUI

// YayaShot build note: `@Entry` is a SwiftUI macro whose compiler plugin ships only
// with Xcode. These are the equivalent hand-written environment keys so the package
// builds with the Command Line Tools alone.
private struct NotchStyleKey: EnvironmentKey {
    static let defaultValue: DynamicNotchStyle = .auto
}

private struct NotchSectionKey: EnvironmentKey {
    static let defaultValue: DynamicNotchSection = .expanded
}

extension EnvironmentValues {
    var notchStyle: DynamicNotchStyle {
        get { self[NotchStyleKey.self] }
        set { self[NotchStyleKey.self] = newValue }
    }

    var notchSection: DynamicNotchSection {
        get { self[NotchSectionKey.self] }
        set { self[NotchSectionKey.self] = newValue }
    }
}

enum DynamicNotchSection {
    case expanded
    case compactLeading
    case compactTrailing
}
