import Foundation

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

