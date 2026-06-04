import Foundation

public struct BaiduTranslationConfiguration: Equatable {
    public var appID: String
    public var secret: String

    public init(appID: String, secret: String) {
        self.appID = appID
        self.secret = secret
    }
}

public final class BaiduTranslationProvider: TranslationProvider {
    public let providerID = "baidu"

    private let configuration: BaiduTranslationConfiguration?

    public init(configuration: BaiduTranslationConfiguration?) {
        self.configuration = configuration
    }

    public func translate(_ request: TranslationRequest) async -> Result<TranslationResponse, TranslationError> {
        guard configuration != nil else {
            return .failure(.providerNotConfigured)
        }

        return .failure(.providerFailure("Baidu API wiring is waiting for supplied credentials and endpoint details."))
    }
}
