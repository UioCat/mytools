import MacToolsCore

final class AppEnvironment {
    let logger = Logger()
    lazy var mainPanel = MainPanelController(
        rootView: MainPanelView(items: [], onSelect: { _ in })
    )
}
