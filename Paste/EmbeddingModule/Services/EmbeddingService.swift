// EmbeddingService.swift
import Foundation
import Network

class EmbeddingService {
    static let shared = EmbeddingService()
    private let monitor = NWPathMonitor()
    private var isNetworkAvailable = true
    private var currentSettings: EmbeddingSettings
    
    private init() {
        self.currentSettings = EmbeddingSettingsManager.shared.currentSettings
        setupNetworkMonitoring()
        setupSettingsListener()
    }
    
    private func setupSettingsListener() {
        EmbeddingSettingsManager.shared.addObserver { [weak self] newSettings in
            print("📡 EmbeddingService received settings update: \(newSettings.provider.rawValue)")
            self?.currentSettings = newSettings
        }
    }

    private func setupNetworkMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.isNetworkAvailable = path.status == .satisfied
        }
        monitor.start(queue: DispatchQueue.global(qos: .background))
    }
    
    deinit {
        monitor.cancel()
    }
    
    private func checkNetworkAndThrow() throws {
        guard isNetworkAvailable else {
            throw EmbeddingError.networkError("No network connection available")
        }
    }
    
    func generateEmbedding(for text: String) async throws -> [Float] {
        try checkNetworkAndThrow()
        
        guard !text.isEmpty else {
            throw EmbeddingError.invalidInput("Empty text provided")
        }
        
        do {
            switch currentSettings.provider {
            case .local:
                print("local embedding")
                return try await generateLocalEmbedding(text, baseURL: currentSettings.localBaseURL)
            case .google:
                print("google embedding")
                return try await generateGoogleEmbedding(text, apiKey: currentSettings.googleAPIKey, model: currentSettings.googleModel)
            case .openAI:
                print("openai embedding")
                return try await generateOpenAIEmbedding(text, apiKey: currentSettings.openAIAPIKey, model: currentSettings.openAIModel)
            }
        } catch {
            throw handleNetworkError(error)
        }
    }
    
    private func handleNetworkError(_ error: Error) -> EmbeddingError {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return .timeout
            case .cannotConnectToHost, .networkConnectionLost:
                if currentSettings.provider == .local {
                    return .connectionRefused
                } else {
                    return .serviceUnavailable(currentSettings.provider.rawValue)
                }
            default:
                return .networkError(urlError.localizedDescription)
            }
        }
        return error as? EmbeddingError ?? .networkError(error.localizedDescription)
    }
    
    private func generateLocalEmbedding(_ text: String, baseURL: String) async throws -> [Float] {
        var urlString = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
            urlString = "http://" + urlString
        }
        
        guard let url = URL(string: urlString) else {
            throw EmbeddingError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        
        let requestBody = ["content": text]
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw EmbeddingError.networkError("Invalid response type")
        }
        
        if httpResponse.statusCode == 503 {
            throw EmbeddingError.serviceUnavailable("Local")
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw EmbeddingError.serverError(httpResponse.statusCode)
        }
        
        struct LocalResponse: Decodable {
            let embedding: [Float]
        }
        
        do {
            let result = try JSONDecoder().decode(LocalResponse.self, from: data)
            return result.embedding
        } catch {
            throw EmbeddingError.decodingError("Failed to decode local response: \(error.localizedDescription)")
        }
    }
    
    private func generateGoogleEmbedding(_ text: String, apiKey: String, model: String) async throws -> [Float] {
        guard !apiKey.isEmpty else {
            throw EmbeddingError.invalidAPIKey
        }
        
        let cleanModel = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model
        let cleanKey = apiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? apiKey
        
        let urlString = "https://generativelanguage.googleapis.com/v1beta/\(cleanModel):embedContent?key=\(cleanKey)"
        guard let url = URL(string: urlString) else {
            throw EmbeddingError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody: [String: Any] = [
            "model": model,
            "content": [
                "parts": [
                    ["text": text]
                ]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw EmbeddingError.networkError("Invalid response type")
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorJson["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw EmbeddingError.networkError("Google API Error: \(message)")
            }
            throw EmbeddingError.serverError(httpResponse.statusCode)
        }
        
        struct GoogleResponse: Decodable {
            struct Embedding: Decodable {
                let values: [Float]
            }
            let embedding: Embedding
        }
        
        do {
            let result = try JSONDecoder().decode(GoogleResponse.self, from: data)
            return result.embedding.values
        } catch {
            throw EmbeddingError.decodingError("Failed to decode Google response: \(error.localizedDescription)")
        }
    }
    
    private func generateOpenAIEmbedding(_ text: String, apiKey: String, model: String) async throws -> [Float] {
        guard !apiKey.isEmpty else {
            throw EmbeddingError.invalidAPIKey
        }
        
        let url = URL(string: "https://api.openai.com/v1/embeddings")!
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let requestBody: [String: Any] = [
            "input": text,
            "model": model
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw EmbeddingError.networkError("Invalid response type")
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorJson["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw EmbeddingError.networkError("OpenAI API Error: \(message)")
            }
            throw EmbeddingError.serverError(httpResponse.statusCode)
        }
        
        struct OpenAIResponse: Decodable {
            struct EmbeddingData: Decodable {
                let embedding: [Float]
            }
            let data: [EmbeddingData]
        }
        
        do {
            let result = try JSONDecoder().decode(OpenAIResponse.self, from: data)
            guard let embedding = result.data.first?.embedding else {
                throw EmbeddingError.decodingError("No embedding data found in response")
            }
            return embedding
        } catch {
            throw EmbeddingError.decodingError("Failed to decode OpenAI response: \(error.localizedDescription)")
        }
    }
}
