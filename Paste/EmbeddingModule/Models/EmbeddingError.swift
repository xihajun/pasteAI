
import Foundation
import Network

enum EmbeddingError: LocalizedError {
    case invalidAPIKey
    case invalidURL
    case invalidInput(String)
    case networkError(String)
    case decodingError(String)
    case timeout
    case serverError(Int)
    case connectionRefused
    case serviceUnavailable(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return "Invalid API key. Please check your settings and try again."
        case .invalidURL:
            return "Invalid URL. Please check the server address in settings."
        case .invalidInput(let message):
            return "Invalid input: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .decodingError(let message):
            return "Failed to decode response: \(message)"
        case .timeout:
            return "Request timed out. Please check your connection and try again."
        case .serverError(let code):
            return "Server error (code: \(code)). Please try again later."
        case .connectionRefused:
            return "Could not connect to the embedding service. Please check if the service is running and properly configured."
        case .serviceUnavailable(let provider):
            return "The \(provider) embedding service is currently unavailable. Please check your settings and try again."
        }
    }
}
