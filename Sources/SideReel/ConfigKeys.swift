import Foundation

enum ConfigKeys {
    static let folderPath = "folderPath"
    static let screenNames = "screenNames"
    static let interval = "interval"
    static let playbackMode = "playbackMode"
    static let driftSpeed = "driftSpeed"
    static let tileCount = "tileCount"
    static let shuffle = "shuffle"
    static let idleEnabled = "idleEnabled"
    static let idleMinutes = "idleMinutes"
    static let keepAwake = "keepAwake"
    static let lockOnExit = "lockOnExit"
    static let scheduleStart = "scheduleStart"
    static let scheduleEnd = "scheduleEnd"

    static func registerDefaults() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: screenNames) == nil,
           let old = defaults.string(forKey: "screenName"), !old.isEmpty {
            defaults.set(old, forKey: screenNames)
        }
        defaults.register(defaults: [
            folderPath: "",
            screenNames: "",
            interval: 10.0,
            playbackMode: "slideshow",
            driftSpeed: 20.0,
            tileCount: 13,
            shuffle: true,
            idleEnabled: false,
            idleMinutes: 5,
            keepAwake: true,
            lockOnExit: false,
            scheduleStart: 0,
            scheduleEnd: 1439,
        ])
    }
}