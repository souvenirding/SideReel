import AppKit

public struct DisplayInfo: Identifiable, Equatable {
    public let id: CGDirectDisplayID
    public let name: String
    public let isBuiltin: Bool
    public let width: Int
    public let height: Int

    public var label: String {
        let size = "\(width)×\(height)"
        return isBuiltin ? "\(name)（内置，\(size)）" : "\(name)（\(size)）"
    }
}

public enum ScreenUtils {
    public static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    public static func isBuiltin(_ screen: NSScreen) -> Bool {
        guard let id = displayID(of: screen) else { return false }
        return CGDisplayIsBuiltin(id) != 0
    }

    public static func displays() -> [DisplayInfo] {
        NSScreen.screens.compactMap { screen in
            guard let id = displayID(of: screen) else { return nil }
            return DisplayInfo(
                id: id,
                name: screen.localizedName,
                isBuiltin: isBuiltin(screen),
                width: Int(screen.frame.width),
                height: Int(screen.frame.height)
            )
        }
    }

    public static func defaultTarget() -> NSScreen? {
        NSScreen.screens.first { !isBuiltin($0) } ?? NSScreen.main ?? NSScreen.screens.first
    }

    public static func screen(named name: String) -> NSScreen? {
        guard !name.isEmpty else { return defaultTarget() }
        return NSScreen.screens.first { $0.localizedName == name } ?? defaultTarget()
    }

    public static func screens(matching names: [String]) -> [NSScreen] {
        names.compactMap { name in NSScreen.screens.first { $0.localizedName == name } }
    }

    public static func selectedScreens(names: [String]) -> [NSScreen] {
        if names.isEmpty {
            return defaultTarget().map { [$0] } ?? []
        }
        return screens(matching: names)
    }

    public static func coversAllScreens(_ screens: [NSScreen]) -> Bool {
        let all = Set(NSScreen.screens.compactMap { displayID(of: $0) })
        let selected = Set(screens.compactMap { displayID(of: $0) })
        return !all.isEmpty && selected == all
    }
}