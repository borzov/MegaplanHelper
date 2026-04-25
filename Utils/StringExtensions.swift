import Foundation

// MARK: - Email Validation Extension
extension String {
    private static let emailDetector: NSDataDetector? = {
        try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    }()

    private static let emailPredicate: NSPredicate = {
        let emailRegex = "[A-Z0-9a-z._%+\\-!#$&'*/=?^`{|}~]+@[A-Za-z0-9][A-Za-z0-9.\\-]*[A-Za-z0-9]\\.[A-Za-z]{2,}"
        return NSPredicate(format: "SELF MATCHES %@", emailRegex)
    }()

    /// Validates email address format using NSDataDetector for RFC-compliant validation
    /// - Returns: true if the string is a valid email address
    func isValidEmail() -> Bool {
        guard !self.isEmpty else { return false }

        guard let detector = Self.emailDetector else {
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
        return Self.emailPredicate.evaluate(with: self)
    }
}

