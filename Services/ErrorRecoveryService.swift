import Foundation

/// Service for error recovery with retry mechanism
final class ErrorRecoveryService: Sendable {
    static let shared = ErrorRecoveryService()
    
    private let maxRetries = 3
    private let baseDelay: TimeInterval = 1.0
    private let maxDelay: TimeInterval = 30.0
    
    private init() {}
    
    /// Выполняет операцию с retry механизмом и экспоненциальной задержкой
    func executeWithRetry<T>(
        operation: @escaping () async throws -> T,
        onRetry: ((Int, TimeInterval) -> Void)? = nil,
        onFailure: ((Error) -> Void)? = nil
    ) async throws -> T {
        var lastError: Error?
        
        for attempt in 1...maxRetries {
            do {
                return try await operation()
            } catch {
                lastError = error
                
                // Не повторяем для определенных типов ошибок
                if shouldNotRetry(error) {
                    throw error
                }
                
                // Если это последняя попытка, выбрасываем ошибку
                if attempt >= maxRetries {
                    break
                }
                
                // Вычисляем задержку с экспоненциальным backoff
                let delay = min(baseDelay * pow(2.0, Double(attempt - 1)), maxDelay)
                
                onRetry?(attempt, delay)
                AppLogger.info("Retry attempt \(attempt)/\(maxRetries) after \(delay)s delay")
                
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        
        // Если все попытки исчерпаны, вызываем обработчик ошибки
        if let error = lastError {
            onFailure?(error)
            throw error
        }
        
        throw NSError(domain: "ErrorRecoveryService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown error"])
    }
    
    /// Определяет, следует ли повторять операцию для данной ошибки
    private func shouldNotRetry(_ error: Error) -> Bool {
        // Не повторяем для ошибок авторизации
        if let networkError = error as? NetworkError {
            switch networkError {
            case .unauthorized, .validationFailed, .tooManyAttempts:
                return true
            default:
                break
            }
        }
        
        // Не повторяем для ошибок, которые не связаны с сетью
        if let urlError = error as? URLError {
            switch urlError.code {
            case .badURL, .unsupportedURL, .cannotFindHost, .cannotConnectToHost:
                return false // Можно повторить
            case .userCancelledAuthentication, .userAuthenticationRequired:
                return true // Не повторяем
            default:
                return false
            }
        }
        
        return false
    }
    
    /// Автоматически восстанавливается после сетевых ошибок
    func recoverFromNetworkError(_ error: Error) async -> Bool {
        // Проверяем, является ли это сетевой ошибкой
        guard isNetworkError(error) else {
            return false
        }
        
        // Ждем немного перед повторной попыткой
        do {
            try await Task.sleep(nanoseconds: UInt64(baseDelay * 1_000_000_000))
            return true
        } catch {
            return false
        }
    }
    
    /// Проверяет, является ли ошибка сетевой
    private func isNetworkError(_ error: Error) -> Bool {
        if let networkError = error as? NetworkError {
            switch networkError {
            case .transport, .offline:
                return true
            default:
                return false
            }
        }
        
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost:
                return true
            default:
                return false
            }
        }
        
        return false
    }
}

