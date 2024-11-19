// EmbeddingTypes.swift

import Foundation

enum EmbeddingProvider: String, CaseIterable, Codable {
    case local = "Local"
    case google = "Google"
    case openAI = "OpenAI"
}

struct EmbeddingSettings: Codable {
    var provider: EmbeddingProvider
    var localBaseURL: String
    var googleAPIKey: String
    var googleModel: String
    var openAIAPIKey: String
    var openAIModel: String
    
    static let defaultSettings = EmbeddingSettings(
        provider: .local,
        localBaseURL: "http://localhost:8080/embedding",
        googleAPIKey: "",
        googleModel: "models/text-embedding-004",
        openAIAPIKey: "",
        openAIModel: "text-embedding-3-small"
    )
}

class EmbeddingSettingsManager {
    static let shared = EmbeddingSettingsManager()
    private let defaults = UserDefaults.standard
    private let settingsKey = "embeddingSettings"
    
    // Add publisher for settings changes
    private var observers: [(EmbeddingSettings) -> Void] = []
    
    var currentSettings: EmbeddingSettings {
        get {
            if let data = defaults.data(forKey: settingsKey),
               let settings = try? JSONDecoder().decode(EmbeddingSettings.self, from: data) {
                return settings
            }
            return EmbeddingSettings.defaultSettings
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: settingsKey)
                // Notify all observers
                observers.forEach { $0(newValue) }
                NotificationCenter.default.post(name: NSNotification.Name("EmbeddingSettingsChanged"), object: nil)
            }
        }
    }
    
    // Add method to subscribe to settings changes
    func addObserver(_ observer: @escaping (EmbeddingSettings) -> Void) {
        observers.append(observer)
        // Call the observer immediately with current settings
        observer(currentSettings)
    }
    
    // Add method to remove observer
    func removeObserver(_ observer: @escaping (EmbeddingSettings) -> Void) {
        observers.removeAll(where: { $0 as AnyObject === observer as AnyObject })
    }
}
