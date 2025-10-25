import Foundation

struct APILogger {
    private static var logEntries: [String] = []
    private static let logQueue = DispatchQueue(label: "com.ruvents.api-logger", qos: .utility)
    
    static func logRequest(method: String, url: String, headers: [String: String]?, body: Data?) {
        logQueue.async {
            let timestamp = DateFormatter.iso8601.string(from: Date())
            var logEntry = "===== REQUEST [\(timestamp)] =====\n"
            logEntry += "Method: \(method)\n"
            logEntry += "URL: \(url)\n"
            
            if let headers = headers {
                logEntry += "Headers: \(headers)\n"
            }
            
            if let body = body {
                logEntry += "Body: \(String(data: body, encoding: .utf8) ?? "Binary data")\n"
            } else {
                logEntry += "Body: nil\n"
            }
            
            logEntry += "\n"
            logEntries.append(logEntry)
        }
    }
    
    static func logResponse(statusCode: Int, error: Error?, data: Data?) {
        logQueue.async {
            let timestamp = DateFormatter.iso8601.string(from: Date())
            var logEntry = "===== RESPONSE [\(timestamp)] =====\n"
            logEntry += "Status Code: \(statusCode)\n"
            
            if let error = error {
                logEntry += "Error: \(error.localizedDescription)\n"
            } else {
                logEntry += "Error: nil\n"
            }
            
            if let data = data {
                // Попробуем декодировать base64
                if let decodedData = Data(base64Encoded: String(data: data, encoding: .utf8) ?? "") {
                    // Если это JSON, попробуем его отформатировать
                    if let jsonObject = try? JSONSerialization.jsonObject(with: decodedData),
                       let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted),
                       let prettyString = String(data: prettyData, encoding: .utf8) {
                        logEntry += "Data (JSON):\n\(prettyString)\n"
                    } else {
                        logEntry += "Data (decoded): \(String(data: decodedData, encoding: .utf8) ?? "Binary data")\n"
                    }
                } else {
                    // Если не base64, попробуем как JSON
                    if let jsonObject = try? JSONSerialization.jsonObject(with: data),
                       let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted),
                       let prettyString = String(data: prettyData, encoding: .utf8) {
                        logEntry += "Data (JSON):\n\(prettyString)\n"
                    } else {
                        logEntry += "Data: \(String(data: data, encoding: .utf8) ?? "Binary data")\n"
                    }
                }
            } else {
                logEntry += "Data: nil\n"
            }
            
            logEntry += "\n"
            logEntries.append(logEntry)
        }
    }
    
    static func clearLog() {
        logQueue.async {
            logEntries.removeAll()
        }
    }
    
    static func getLogContent() -> String {
        return logQueue.sync {
            if logEntries.isEmpty {
                return "Лог пуст"
            }
            return logEntries.joined(separator: "")
        }
    }
}

extension DateFormatter {
    static let iso8601: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}