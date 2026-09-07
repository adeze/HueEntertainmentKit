import Foundation

public struct HueHTTPRequest: Sendable {
    public enum Method: String, Sendable { case get = "GET", post = "POST", put = "PUT" }
    public let method: Method
    public let url: URL
    public let headers: [String: String]
    public let body: Data?

    public init(method: Method, url: URL, headers: [String: String] = [:], body: Data? = nil) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }
}

public struct HueHTTPResponse: Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let body: Data

    public init(statusCode: Int, headers: [String: String] = [:], body: Data) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }
}

public protocol HueHTTPTransport: Sendable {
    func send(_ request: HueHTTPRequest) async throws -> HueHTTPResponse
}

public enum HueBridgeTrustPolicy: Sendable {
    case system
    case hueBridge(bridgeID: String)
    case pinnedRootCertificates([Data], expectedCommonName: String)
}

public final class URLSessionHueHTTPTransport: NSObject, HueHTTPTransport, @unchecked Sendable {
    private let delegate: TrustDelegate
    private let session: URLSession

    public init(trustPolicy: HueBridgeTrustPolicy = .system) {
        let delegate = TrustDelegate(policy: trustPolicy)
        self.delegate = delegate
        self.session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        super.init()
    }

    public func send(_ request: HueHTTPRequest) async throws -> HueHTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        urlRequest.timeoutInterval = 10
        request.headers.forEach { urlRequest.setValue($1, forHTTPHeaderField: $0) }
        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw HueEntertainmentError.malformedResponse }
        let headers = http.allHeaderFields.reduce(into: [String: String]()) { result, pair in
            result[String(describing: pair.key).lowercased()] = String(describing: pair.value)
        }
        return HueHTTPResponse(statusCode: http.statusCode, headers: headers, body: data)
    }
}

private final class TrustDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    let policy: HueBridgeTrustPolicy
    init(policy: HueBridgeTrustPolicy) { self.policy = policy }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        switch policy {
        case .system:
            completionHandler(.performDefaultHandling, nil)
        case .hueBridge(let bridgeID):
            evaluate(trust: trust, roots: HueBridgeCertificateAuthority.rootCertificates, commonName: bridgeID,
                completionHandler: completionHandler)
        case .pinnedRootCertificates(let roots, let commonName):
            evaluate(trust: trust, roots: roots, commonName: commonName, completionHandler: completionHandler)
        }
    }

    private func evaluate(
        trust: SecTrust,
        roots: [Data],
        commonName: String,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
            let certificates = roots.compactMap { SecCertificateCreateWithData(nil, $0 as CFData) }
            let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate]
            var leafCommonName: CFString?
            if let leaf = chain?.first { SecCertificateCopyCommonName(leaf, &leafCommonName) }
            guard !certificates.isEmpty,
                  let leafCommonName,
                  (leafCommonName as String).caseInsensitiveCompare(commonName) == .orderedSame,
                  SecTrustSetAnchorCertificates(trust, certificates as CFArray) == errSecSuccess,
                  SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess,
                  SecTrustSetPolicies(trust, SecPolicyCreateBasicX509()) == errSecSuccess,
                  SecTrustEvaluateWithError(trust, nil)
            else {
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
            completionHandler(.useCredential, URLCredential(trust: trust))
    }
}

public enum HueBridgeCertificateAuthority {
    /// Current and secondary roots published by Signify in its Hue HTTPS guidance.
    public static let rootCertificates: [Data] = [
        "MIICMjCCAdigAwIBAgIUO7FSLbaxikuXAljzVaurLXWmFw4wCgYIKoZIzj0EAwIwOTELMAkGA1UEBhMCTkwxFDASBgNVBAoMC1BoaWxpcHMgSHVlMRQwEgYDVQQDDAtyb290LWJyaWRnZTAiGA8yMDE3MDEwMTAwMDAwMFoYDzIwMzgwMTE5MDMxNDA3WjA5MQswCQYDVQQGEwJOTDEUMBIGA1UECgwLUGhpbGlwcyBIdWUxFDASBgNVBAMMC3Jvb3QtYnJpZGdlMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEjNw2tx2AplOf9x86aTdvEcL1FU65QDxziKvBpW9XXSIcibAeQiKxegpq8Exbr9v6LBnYbna2VcaK0G22jOKkTqOBuTCBtjAPBgNVHRMBAf8EBTADAQH/MA4GA1UdDwEB/wQEAwIBhjAdBgNVHQ4EFgQUZ2ONTFrDT6o8ItRnKfqWKnHFGmQwdAYDVR0jBG0wa4AUZ2ONTFrDT6o8ItRnKfqWKnHFGmShPaQ7MDkxCzAJBgNVBAYTAk5MMRQwEgYDVQQKDAtQaGlsaXBzIEh1ZTEUMBIGA1UEAwwLcm9vdC1icmlkZ2WCFDuxUi22sYpLlwJY81Wrqy11phcOMAoGCCqGSM49BAMCA0gAMEUCIEBYYEOsa07TH7E5MJnGw557lVkORgit2Rm1h3B2sFgDAiEA1Fj/C3AN5psFMjo0//mrQebo0eKd3aWRx+pQY08mk48=",
        "MIIBzDCCAXOgAwIBAgICEAAwCgYIKoZIzj0EAwIwPDELMAkGA1UEBhMCTkwxFDASBgNVBAoMC1NpZ25pZnkgSHVlMRcwFQYDVQQDDA5IdWUgUm9vdCBDQSAwMTAgFw0yNTAyMjUwMDAwMDBaGA8yMDUwMTIzMTIzNTk1OVowPDELMAkGA1UEBhMCTkwxFDASBgNVBAoMC1NpZ25pZnkgSHVlMRcwFQYDVQQDDA5IdWUgUm9vdCBDQSAwMTBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABFfOO0jfSAUXGQ9kjEDzyBrcMQ3ItyA5krE+cyvb1Y3xFti7KlAad8UOnAx0FBLn7HZrlmIwm1QnX0fK3LPM13mjYzBhMB0GA1UdDgQWBBTF1pSpsCASX/z0VHLigxU2CAaqoTAfBgNVHSMEGDAWgBTF1pSpsCASX/z0VHLigxU2CAaqoTAPBgNVHRMBAf8EBTADAQH/MA4GA1UdDwEB/wQEAwIBBjAKBggqhkjOPQQDAgNHADBEAiAk7duT+IHbOGO4UUuGLAEpyYejGZK9Z7V9oSfnvuQ5BQIgIYSgwwxHXm73/JgcU9lAM6c8Bmu3UE3kBIUwBs1qXFw="
    ].compactMap { Data(base64Encoded: $0) }
}
