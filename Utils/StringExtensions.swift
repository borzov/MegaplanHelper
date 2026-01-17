import Foundation

// MARK: - Email Validation Extension
extension String {
    /// Validates email address format using NSDataDetector for RFC-compliant validation
    /// - Returns: true if the string is a valid email address
    func isValidEmail() -> Bool {
        guard !self.isEmpty else { return false }

        // Use NSDataDetector for more accurate email validation
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            // Fallback to basic regex if detector fails
            return isValidEmailFallback()
        }

        let range = NSRange(self.startIndex..., in: self)
        let matches = detector.matches(in: self, options: [], range: range)

        // Check if the entire string is a valid mailto: link
        guard matches.count == 1,
              let match = matches.first,
              match.range == range,
              let url = match.url,
              url.scheme == "mailto" else {
            // NSDataDetector may not catch all valid emails, use fallback
            return isValidEmailFallback()
        }

        return true
    }

    /// Fallback regex validation supporting + in local part
    private func isValidEmailFallback() -> Bool {
        // RFC 5321 compliant pattern allowing + and other valid characters
        let emailRegex = "[A-Z0-9a-z._%+\\-!#$&'*/=?^`{|}~]+@[A-Za-z0-9][A-Za-z0-9.\\-]*[A-Za-z0-9]\\.[A-Za-z]{2,}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: self)
    }
}

// MARK: - Pluralization Extension
extension Int {
    /// Склонение числительных для русского языка
    /// - Parameter forms: Кортеж с формами (одна, две, пять)
    /// - Returns: Правильная форма слова
    func pluralized(_ forms: (one: String, few: String, many: String)) -> String {
        let remainder10 = self % 10
        let remainder100 = self % 100
        
        // Для чисел 11-19 всегда используется форма "много"
        if remainder100 >= 11 && remainder100 <= 19 {
            return forms.many
        }
        
        switch remainder10 {
        case 1:
            return forms.one
        case 2, 3, 4:
            return forms.few
        default:
            return forms.many
        }
    }
}

