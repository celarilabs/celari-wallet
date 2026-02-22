import AuthenticationServices
import LocalAuthentication

actor PasskeyManager {

    // MARK: - Biometric Gate (FaceID / TouchID)

    func authenticateWithBiometrics(reason: String = "Authenticate to continue") async throws {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        context.localizedFallbackTitle = "Use Passcode"

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            // Fallback to device passcode
            guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
                throw PasskeyError.biometricUnavailable(error?.localizedDescription ?? "No authentication available")
            }
            try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            return
        }

        try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
    }

    // MARK: - Passkey Creation (P-256 / WebAuthn equivalent)

    @MainActor
    func createPasskey(accountLabel: String) async throws -> PasskeyResult {
        #if targetEnvironment(simulator)
        // Passkey API is not supported on Simulator — generate mock keys
        print("[PasskeyManager] Simulator detected — using mock passkey")
        let mockCredId = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        let mockX = (0..<32).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
        let mockY = (0..<32).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
        return PasskeyResult(
            credentialId: mockCredId.base64URLEncoded(),
            publicKeyX: "0x" + mockX,
            publicKeyY: "0x" + mockY
        )
        #else
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
            relyingPartyIdentifier: "celari.wallet"
        )

        let userId = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        let challenge = Data((0..<32).map { _ in UInt8.random(in: 0...255) })

        let request = provider.createCredentialRegistrationRequest(
            challenge: challenge,
            name: accountLabel,
            userID: userId
        )

        let result = try await performAuthorization(request: request)

        guard let registration = result.credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration else {
            throw PasskeyError.invalidResponse
        }

        let credentialId = registration.credentialID.base64URLEncoded()

        // Extract P-256 public key from DER/SPKI format
        guard let rawKey = registration.rawAttestationObject else {
            throw PasskeyError.noPublicKey
        }
        let (pubKeyX, pubKeyY) = try extractP256PublicKey(from: rawKey)

        return PasskeyResult(
            credentialId: credentialId,
            publicKeyX: "0x" + pubKeyX,
            publicKeyY: "0x" + pubKeyY
        )
        #endif
    }

    // MARK: - Passkey Verification (Sign challenge for tx approval)

    @MainActor
    func verifyPasskey(credentialId: String) async throws {
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
            relyingPartyIdentifier: "celari.wallet"
        )

        let challenge = Data((0..<32).map { _ in UInt8.random(in: 0...255) })

        guard let credData = Data(base64URLEncoded: credentialId) else {
            throw PasskeyError.invalidCredentialId
        }

        let request = provider.createCredentialAssertionRequest(challenge: challenge)
        request.allowedCredentials = [
            ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: credData)
        ]

        _ = try await performAuthorization(request: request)
    }

    // MARK: - ASAuthorization Helper

    @MainActor
    private func performAuthorization(request: ASAuthorizationRequest) async throws -> ASAuthorization {
        try await withCheckedThrowingContinuation { continuation in
            let controller = ASAuthorizationController(authorizationRequests: [request])
            let delegate = AuthDelegate(continuation: continuation)
            controller.delegate = delegate
            controller.presentationContextProvider = delegate
            // Prevent delegate deallocation
            objc_setAssociatedObject(controller, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN)
            controller.performRequests()
        }
    }

    // MARK: - P-256 Public Key Extraction

    nonisolated private func extractP256PublicKey(from data: Data) throws -> (String, String) {
        let bytes = [UInt8](data)
        // Find uncompressed point marker (0x04) followed by 64 bytes (X + Y)
        for i in 0..<(bytes.count - 64) {
            if bytes[i] == 0x04 && i + 65 <= bytes.count {
                let x = bytes[(i + 1)..<(i + 33)]
                let y = bytes[(i + 33)..<(i + 65)]
                return (
                    x.map { String(format: "%02x", $0) }.joined(),
                    y.map { String(format: "%02x", $0) }.joined()
                )
            }
        }
        throw PasskeyError.noPublicKey
    }
}

// MARK: - ASAuthorization Delegate

private class AuthDelegate: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<ASAuthorization, Error>?

    init(continuation: CheckedContinuation<ASAuthorization, Error>) {
        self.continuation = continuation
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        continuation?.resume(returning: authorization)
        continuation = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            return UIWindow()
        }
        return window
    }
}

// MARK: - Types

struct PasskeyResult {
    var credentialId: String
    var publicKeyX: String
    var publicKeyY: String
}

enum PasskeyError: LocalizedError {
    case biometricUnavailable(String)
    case invalidResponse
    case noPublicKey
    case invalidCredentialId
    case cancelled

    var errorDescription: String? {
        switch self {
        case .biometricUnavailable(let reason): return "Biometric auth unavailable: \(reason)"
        case .invalidResponse: return "Invalid passkey response"
        case .noPublicKey: return "Could not extract public key"
        case .invalidCredentialId: return "Invalid credential ID"
        case .cancelled: return "Authentication cancelled"
        }
    }
}

// MARK: - Base64URL Extensions

extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLEncoded string: String) {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        self.init(base64Encoded: base64)
    }
}
