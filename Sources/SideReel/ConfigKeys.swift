import Foundation

enum ConfigKeys {
    static let folderPath = "folderPath"
    static let screenName = "screenName"
    static let interval = "interval"
    static let shuffle = "shuffle"
    static let idleEnabled = "idleEnabled"
    static let idleMinutes = "idleMinutes"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            folderPath: "",
            screenName: "",
            interval: 10.0,
            shuffle: true,
            idleEnabled: false,
            idleMinutes: 5,
        ])
    }
}