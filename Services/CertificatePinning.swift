import CommonCrypto
import Foundation

// MARK: - Certificate Pinning State

extension Notification.Name {
    /// Posted when certificate pinning fails but connection is allowed (graceful degradation)
    static let certificatePinningFailed = Notification.Name("MegaplanCertificatePinningFailed")
}

/// Thread-safe wrapper for certificate pinning failure state
final class PinningState {
    private var _pinningFailureNotified = false
    private let lock = NSLock()

    var pinningFailureNotified: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _pinningFailureNotified
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _pinningFailureNotified = newValue
        }
    }

    func setNotifiedIfNeeded() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if _pinningFailureNotified {
            return false
        }
        _pinningFailureNotified = true
        return true
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        _pinningFailureNotified = false
    }
}

// MARK: - URLSessionDelegate (Certificate Pinning)

extension MegaplanAPI: URLSessionDelegate {
    /// Thread-safe state for tracking pinning failures
    static let pinningState = PinningState()

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // Пропускаем pinning в debug сборках для отладки с proxy
        guard Constants.CertificatePinning.isEnabled else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Стандартная валидация TLS
        let policies = [SecPolicyCreateSSL(true, challenge.protectionSpace.host as CFString)]
        SecTrustSetPolicies(serverTrust, policies as CFArray)

        var error: CFError?
        guard SecTrustEvaluateWithError(serverTrust, &error) else {
            AppLogger.error("Certificate validation failed: \(error?.localizedDescription ?? "unknown")")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Проверяем совпадение хешей в цепочке сертификатов
        let certificateCount = SecTrustGetCertificateCount(serverTrust)

        // DoS защита: отклоняем слишком глубокие цепочки
        guard certificateCount <= Constants.SecurityConfig.maxCertificateChainDepth else {
            AppLogger.warning("Rejected certificate chain with \(certificateCount) certificates (max: \(Constants.SecurityConfig.maxCertificateChainDepth))")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        var isPinned = false

        AppLogger.debug("Certificate pinning: checking \(certificateCount) certificates for \(challenge.protectionSpace.host)")

        for index in 0..<certificateCount {
            guard let certificate = SecTrustGetCertificateAtIndex(serverTrust, index) else { continue }

            if let publicKeyHash = getPublicKeyHash(for: certificate) {
                AppLogger.debug("Certificate[\(index)] hash: \(publicKeyHash)")
                if Constants.CertificatePinning.pinnedPublicKeyHashes.contains(publicKeyHash) {
                    isPinned = true
                    break
                }
            } else {
                AppLogger.debug("Certificate[\(index)] hash: failed to compute")
            }
        }

        if isPinned {
            AppLogger.debug("Certificate pinning succeeded for \(challenge.protectionSpace.host)")
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            // Graceful degradation: разрешаем соединение с предупреждением
            AppLogger.warning("Certificate pinning failed for \(challenge.protectionSpace.host) — allowing with warning")

            // Уведомляем UI только один раз за сессию
            if Self.pinningState.setNotifiedIfNeeded() {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .certificatePinningFailed,
                        object: nil,
                        userInfo: ["host": challenge.protectionSpace.host]
                    )
                }
            }

            // Разрешаем соединение (TLS валиден, только не pinned)
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        }
    }

    private func getPublicKeyHash(for certificate: SecCertificate) -> String? {
        guard let publicKey = SecCertificateCopyKey(certificate) else { return nil }

        var error: Unmanaged<CFError>?
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            return nil
        }

        // Определяем тип ключа для выбора правильного ASN.1 заголовка
        guard let keyAttributes = SecKeyCopyAttributes(publicKey) as? [String: Any],
              let keyType = keyAttributes[kSecAttrKeyType as String] as? String else {
            return nil
        }

        // Строим SPKI (Subject Public Key Info) с ASN.1 заголовком
        var spkiData = Data()

        if keyType == (kSecAttrKeyTypeRSA as String) {
            let keySize = publicKeyData.count
            if keySize > 256 {
                spkiData.append(contentsOf: Self.rsa4096SPKIHeader)
            } else {
                spkiData.append(contentsOf: Self.rsa2048SPKIHeader)
            }
        } else if keyType == (kSecAttrKeyTypeECSECPrimeRandom as String) {
            spkiData.append(contentsOf: Self.ecdsaSecp256r1SPKIHeader)
        } else {
            AppLogger.warning("Unknown key type for certificate pinning: \(keyType)")
        }

        spkiData.append(publicKeyData)

        // SHA256 хеш SPKI
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        spkiData.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &hash)
        }

        return Data(hash).base64EncodedString()
    }

    // MARK: - ASN.1 SPKI Headers

    // RSA 2048 SPKI header (for keys ~256 bytes)
    private static let rsa2048SPKIHeader: [UInt8] = [
        0x30, 0x82, 0x01, 0x22,  // SEQUENCE, length 290
        0x30, 0x0D,              // SEQUENCE, length 13
        0x06, 0x09,              // OID, length 9
        0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01,  // rsaEncryption OID
        0x05, 0x00,              // NULL
        0x03, 0x82, 0x01, 0x0F,  // BIT STRING, length 271
        0x00                     // padding
    ]

    // RSA 4096 SPKI header (for keys ~512 bytes)
    private static let rsa4096SPKIHeader: [UInt8] = [
        0x30, 0x82, 0x02, 0x22,  // SEQUENCE, length 546
        0x30, 0x0D,              // SEQUENCE, length 13
        0x06, 0x09,              // OID, length 9
        0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01,  // rsaEncryption OID
        0x05, 0x00,              // NULL
        0x03, 0x82, 0x02, 0x0F,  // BIT STRING, length 527
        0x00                     // padding
    ]

    // ECDSA P-256 (secp256r1) SPKI header
    private static let ecdsaSecp256r1SPKIHeader: [UInt8] = [
        0x30, 0x59,              // SEQUENCE, length 89
        0x30, 0x13,              // SEQUENCE, length 19
        0x06, 0x07,              // OID, length 7
        0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01,  // ecPublicKey OID
        0x06, 0x08,              // OID, length 8
        0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07,  // secp256r1 OID
        0x03, 0x42,              // BIT STRING, length 66
        0x00                     // padding
    ]

    /// Resets pinning failure state (call on logout or app restart)
    static func resetPinningState() {
        pinningState.reset()
    }
}
