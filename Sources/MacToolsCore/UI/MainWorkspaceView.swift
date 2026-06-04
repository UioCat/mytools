import SwiftUI

public struct MainWorkspaceView<SettingsContent: View, ClipboardContent: View, TranslationContent: View>: View {
    @Binding private var selectedModule: MainToolModule
    private let settingsContent: SettingsContent
    private let clipboardContent: ClipboardContent
    private let translationContent: TranslationContent

    public init(
        selectedModule: Binding<MainToolModule>,
        @ViewBuilder settings: () -> SettingsContent,
        @ViewBuilder clipboard: () -> ClipboardContent,
        @ViewBuilder translation: () -> TranslationContent
    ) {
        self._selectedModule = selectedModule
        self.settingsContent = settings()
        self.clipboardContent = clipboard()
        self.translationContent = translation()
    }

    public var body: some View {
        HStack(spacing: 0) {
            sidebar

            Divider()
                .overlay(Color.black.opacity(0.10))
                .padding(.vertical, 12)

            moduleContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(18)
        .liquidGlassPanel(cornerRadius: 30)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .frame(
            minWidth: 900,
            idealWidth: 1080,
            maxWidth: .infinity,
            minHeight: 620,
            idealHeight: 720,
            maxHeight: .infinity
        )
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(MainToolModule.allCases) { module in
                Button {
                    selectedModule = module
                } label: {
                    Label(module.title, systemImage: module.iconName)
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 42)
                        .padding(.horizontal, 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(selectedModule == module ? Color.black : Color.black.opacity(0.58))
                .liquidGlassModule(cornerRadius: 16, isSelected: selectedModule == module)
            }

            Spacer(minLength: 0)
        }
        .frame(width: 150)
        .padding(.trailing, 16)
    }

    @ViewBuilder
    private var moduleContent: some View {
        switch selectedModule {
        case .settings:
            settingsContent
        case .clipboard:
            clipboardContent
        case .translation:
            translationContent
        }
    }
}
