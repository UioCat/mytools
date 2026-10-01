import MacToolsCore

/// 将设置请求的结果交付到视图；凭据状态由运行时凭据模型提供。
@MainActor
enum RuntimeTranslationSettingsSaveRequest {
    static func perform(
        save: () async throws -> AppSettings,
        onSaved: (AppSettings) -> Void,
        credentialIsUnavailable: () -> Bool,
        onCredentialUnavailableChanged: (Bool) -> Void
    ) async throws {
        do {
            onSaved(try await save())
            onCredentialUnavailableChanged(credentialIsUnavailable())
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            onCredentialUnavailableChanged(credentialIsUnavailable())
            throw error
        }
    }
}
