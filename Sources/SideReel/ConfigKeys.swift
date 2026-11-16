import Foundation

enum ConfigKeys {
    static let folderPath = "folderPath"
    static let screenNames = "screenNames"
    static let interval = "interval"
    static let playbackMode = "playbackMode"
    static let driftSpeed = "driftSpeed"
    static let shuffle = "shuffle"
    static let idleEnabled = "idleEnabled"
    static let idleMinutes = "idleMinutes"
    static let keepAwake = "keepAwake"

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
            shuffle: true,
            idleEnabled: false,
            idleMinutes: 5,
            keepAwake: true,
        ])
    }
}