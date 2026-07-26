// `ScreenshotEditorView` 的屏幕捕获系统集成实现。
// 负责选区、截图、标注和录屏生命周期，不承载可复用的纯业务模型。

import CoreGraphics
import MacToolsCore
import SwiftUI

/// 扩展 `ScreenshotAnnotationTool`，补充本文件所需的屏幕捕获系统集成能力。
private extension ScreenshotAnnotationTool {
    var title: String {
        switch self {
        case .line:
            return "划线"
        case .freehand:
            return "画笔"
        case .arrow:
            return "箭头"
        case .rectangle:
            return "长方形"
        case .mosaic:
            return "马赛克"
        }
    }

    var imageName: String {
        switch self {
        case .line:
            return "line.diagonal"
        case .freehand:
            return "pencil.tip"
        case .arrow:
            return "arrow.up.right"
        case .rectangle:
            return "rectangle"
        case .mosaic:
            return "checkerboard.rectangle"
        }
    }
}

/// 封装 `ScreenshotEditorView` 在屏幕捕获系统集成中的值语义和相关操作。
struct ScreenshotEditorView: View {
    let image: CGImage
    let imageFrame: CGRect
    let toolbarFrame: CGRect
    let onSettingsChange: (ScreenCaptureSettings) -> Bool
    let onCopy: (Data) -> Void
    let onCancel: () -> Void

    @State private var tool: ScreenshotAnnotationTool
    @State private var annotationColor: ScreenshotAnnotationColor
    @State private var annotationLineWidth: ScreenshotAnnotationLineWidth
    @State private var annotationStore = ScreenshotAnnotationStore()
    @State private var dragStart: CGPoint?
    @State private var freehandStroke = ScreenshotFreehandStroke()
    @State private var previewAnnotation: ScreenshotAnnotation?
    @State private var errorMessage: String?
    @State private var isExporting = false
    @State private var mosaicPreviewImage: CGImage?
    @State private var pendingSettings: ScreenCaptureSettings?
    @State private var settingsSaveTask: Task<Void, Never>?

    /// 创建 `ScreenshotEditorView`，保存传入依赖并建立初始状态。
    init(
        image: CGImage,
        imageFrame: CGRect,
        toolbarFrame: CGRect,
        settings: ScreenCaptureSettings,
        onSettingsChange: @escaping (ScreenCaptureSettings) -> Bool,
        onCopy: @escaping (Data) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.image = image
        self.imageFrame = imageFrame
        self.toolbarFrame = toolbarFrame
        self.onSettingsChange = onSettingsChange
        self.onCopy = onCopy
        self.onCancel = onCancel
        _tool = State(initialValue: settings.annotationTool)
        _annotationColor = State(initialValue: settings.annotationColor.nearestPreset)
        _annotationLineWidth = State(initialValue: settings.annotationLineWidth)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.42)
                .ignoresSafeArea()

            editorCanvas
                .frame(width: imageFrame.width, height: imageFrame.height)
                .position(x: imageFrame.midX, y: imageFrame.midY)

            editorToolbar
                .frame(width: toolbarFrame.width, height: toolbarFrame.height)
                .position(x: toolbarFrame.midX, y: toolbarFrame.midY)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.red)
                    .padding(10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .position(x: toolbarFrame.midX, y: max(24, toolbarFrame.minY - 24))
            }
        }
        .task(id: tool) {
            guard tool == .mosaic, mosaicPreviewImage == nil else {
                return
            }
            let sourceImage = image
            mosaicPreviewImage = try? await Task.detached(priority: .userInitiated) {
                try ScreenshotRenderer.mosaicImage(image: sourceImage)
            }.value
        }
        .onDisappear {
            flushPendingSettings()
        }
    }

    private var editorToolbar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(ScreenshotAnnotationTool.allCases, id: \.self) { candidate in
                    Button {
                        selectTool(candidate)
                    } label: {
                        toolbarLabel(candidate.title, systemImage: candidate.imageName)
                    }
                    .buttonStyle(.bordered)
                    .tint(tool == candidate ? .accentColor : .secondary)
                    .accessibilityValue(tool == candidate ? "已选择" : "未选择")
                }

                Button {
                    _ = annotationStore.undo()
                } label: {
                    toolbarLabel("撤销", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)
                .disabled(annotationStore.annotations.isEmpty)
                .keyboardShortcut("z", modifiers: .command)

                Spacer(minLength: 2)

                Button("取消", action: onCancel)
                    .buttonStyle(.bordered)
                    .disabled(isExporting)
                    .keyboardShortcut(.cancelAction)

                Button {
                    copyScreenshot()
                } label: {
                    toolbarLabel(isExporting ? "处理中" : "完成", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isExporting)
                .keyboardShortcut(.return, modifiers: .command)
            }

            HStack(spacing: 8) {
                Text("颜色")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                ForEach(ScreenshotAnnotationColor.presets, id: \.self) { color in
                    colorButton(color)
                }

                Divider()
                    .frame(height: 20)

                Text("粗细")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                ForEach(ScreenshotAnnotationLineWidth.allCases, id: \.rawValue) { lineWidth in
                    lineWidthButton(lineWidth)
                }

                Spacer(minLength: 4)

                if toolbarFrame.width >= 680 {
                    Text(tool == .mosaic ? "拖拽区域进行像素化" : "拖拽截图区域进行标注")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(tool == .mosaic)
            .opacity(tool == .mosaic ? 0.45 : 1)
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .foregroundStyle(MacToolsGlassTheme.textPrimary)
    }

    /// 构建并返回 `toolbarLabel` 对应的 SwiftUI 界面内容或展示状态。
    @ViewBuilder
    private func toolbarLabel(_ title: String, systemImage: String) -> some View {
        if toolbarFrame.width < 680 {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .help(title)
                .accessibilityLabel(title)
        } else {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: .semibold))
        }
    }

    /// 构建并返回 `colorButton` 对应的 SwiftUI 界面内容或展示状态。
    private func colorButton(_ color: ScreenshotAnnotationColor) -> some View {
        Button {
            selectColor(color)
        } label: {
            Circle()
                .fill(swiftUIColor(color))
                .frame(width: 16, height: 16)
                .overlay {
                    Circle()
                        .stroke(.primary.opacity(0.35), lineWidth: 1)
                }
                .padding(3)
                .overlay {
                    if annotationColor == color {
                        Circle()
                            .stroke(Color.accentColor, lineWidth: 2)
                    }
                }
        }
        .buttonStyle(.plain)
        .help("选择\(colorName(color))")
        .accessibilityLabel(colorName(color))
        .accessibilityValue(annotationColor == color ? "已选择" : "未选择")
    }

    /// 构建并返回 `lineWidthButton` 对应的 SwiftUI 界面内容或展示状态。
    private func lineWidthButton(_ lineWidth: ScreenshotAnnotationLineWidth) -> some View {
        Button {
            annotationLineWidth = lineWidth
            persistSettings(tool: tool, color: annotationColor, lineWidth: lineWidth)
        } label: {
            ScreenshotLineWidthPreview()
                .stroke(
                    Color.primary.opacity(0.88),
                    style: StrokeStyle(lineWidth: lineWidth.points, lineCap: .round)
                )
                .frame(width: 22, height: 12)
                .frame(width: 30, height: 22)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(
                            annotationLineWidth == lineWidth
                                ? Color.accentColor.opacity(0.16)
                                : Color.primary.opacity(0.04)
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(
                            annotationLineWidth == lineWidth
                                ? Color.accentColor.opacity(0.8)
                                : Color.primary.opacity(0.12),
                            lineWidth: annotationLineWidth == lineWidth ? 1.5 : 0.5
                        )
                }
        }
        .buttonStyle(.plain)
        .help(lineWidthName(lineWidth))
        .accessibilityLabel(lineWidthName(lineWidth))
        .accessibilityValue(annotationLineWidth == lineWidth ? "已选择" : "未选择")
    }

    /// 解析并返回 `selectColor` 对应的屏幕捕获系统集成结果。
    private func selectColor(_ color: ScreenshotAnnotationColor) {
        annotationColor = color
        persistSettings(tool: tool, color: color, lineWidth: annotationLineWidth)
    }

    /// 解析并返回 `selectTool` 对应的屏幕捕获系统集成结果。
    private func selectTool(_ tool: ScreenshotAnnotationTool) {
        self.tool = tool
        persistSettings(tool: tool, color: annotationColor, lineWidth: annotationLineWidth)
    }

    /// 保存 `persistSettings` 接收的屏幕捕获系统集成数据，并保持既有持久化约束。
    private func persistSettings(
        tool: ScreenshotAnnotationTool,
        color: ScreenshotAnnotationColor,
        lineWidth: ScreenshotAnnotationLineWidth
    ) {
        let settings = ScreenCaptureSettings(
            annotationTool: tool,
            annotationColor: color,
            annotationLineWidth: lineWidth
        )
        pendingSettings = settings
        settingsSaveTask?.cancel()
        settingsSaveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else {
                return
            }
            commitPendingSettings()
        }
    }

    /// 构建并返回 `flushPendingSettings` 对应的 SwiftUI 界面内容或展示状态。
    private func flushPendingSettings() {
        settingsSaveTask?.cancel()
        commitPendingSettings()
    }

    /// 构建并返回 `commitPendingSettings` 对应的 SwiftUI 界面内容或展示状态。
    private func commitPendingSettings() {
        guard let pendingSettings else {
            return
        }
        settingsSaveTask = nil
        if onSettingsChange(pendingSettings) {
            self.pendingSettings = nil
            if errorMessage == "截图偏好保存失败，下次打开可能无法保留" {
                errorMessage = nil
            }
        } else {
            errorMessage = "截图偏好保存失败，下次打开可能无法保留"
        }
    }

    /// 构建并返回 `colorName` 对应的 SwiftUI 界面内容或展示状态。
    private func colorName(_ color: ScreenshotAnnotationColor) -> String {
        switch color {
        case .red:
            return "红色"
        case .orange:
            return "橙色"
        case .yellow:
            return "黄色"
        case .green:
            return "绿色"
        case .blue:
            return "蓝色"
        case .purple:
            return "紫色"
        case .black:
            return "黑色"
        case .white:
            return "白色"
        default:
            return "颜色"
        }
    }

    /// 构建并返回 `lineWidthName` 对应的 SwiftUI 界面内容或展示状态。
    private func lineWidthName(_ lineWidth: ScreenshotAnnotationLineWidth) -> String {
        switch lineWidth {
        case .thin:
            return "细线"
        case .medium:
            return "标准线"
        case .thick:
            return "粗线"
        }
    }

    private var editorCanvas: some View {
        GeometryReader { proxy in
            let imageRect = CGRect(origin: .zero, size: proxy.size)

            ZStack {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: proxy.size.width, height: proxy.size.height)

                Canvas { context, _ in
                    for annotation in annotationStore.annotations {
                        draw(annotation, in: &context, imageRect: imageRect)
                    }
                    if let previewAnnotation {
                        draw(previewAnnotation, in: &context, imageRect: imageRect, isPreview: true)
                    }
                    if tool == .freehand,
                       let freehandPreview = freehandAnnotation(imageRect: imageRect) {
                        draw(freehandPreview, in: &context, imageRect: imageRect, isPreview: true)
                    }
                }
                .contentShape(Rectangle())
                .gesture(annotationGesture(imageRect: imageRect))
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.accentColor, lineWidth: 2)
            }
        }
    }

    /// 构建并返回 `annotationGesture` 对应的 SwiftUI 界面内容或展示状态。
    private func annotationGesture(imageRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard let point = imagePoint(from: value.location, imageRect: imageRect) else {
                    return
                }
                if dragStart == nil {
                    dragStart = point
                }
                guard let dragStart else {
                    return
                }
                if tool == .freehand {
                    freehandStroke.append(point)
                    return
                }
                previewAnnotation = annotation(from: dragStart, to: point, imageRect: imageRect)
            }
            .onEnded { value in
                defer {
                    dragStart = nil
                    freehandStroke = ScreenshotFreehandStroke()
                    previewAnnotation = nil
                }
                guard let dragStart else {
                    return
                }

                if tool == .freehand {
                    if let point = imagePoint(from: value.location, imageRect: imageRect) {
                        freehandStroke.append(point)
                    }
                    guard let annotation = freehandAnnotation(imageRect: imageRect) else {
                        return
                    }
                    annotationStore.append(annotation)
                    return
                }

                guard let point = imagePoint(from: value.location, imageRect: imageRect),
                      distance(from: dragStart, to: point) >= 2 else {
                    return
                }
                annotationStore.append(annotation(from: dragStart, to: point, imageRect: imageRect))
            }
    }

    /// 构建并返回 `freehandAnnotation` 对应的 SwiftUI 界面内容或展示状态。
    private func freehandAnnotation(imageRect: CGRect) -> ScreenshotAnnotation? {
        freehandStroke.annotation(
            color: annotationColor,
            lineWidth: imageLineWidth(in: imageRect)
        )
    }

    /// 构建并返回 `annotation` 对应的 SwiftUI 界面内容或展示状态。
    private func annotation(
        from start: CGPoint,
        to end: CGPoint,
        imageRect: CGRect
    ) -> ScreenshotAnnotation {
        let lineWidth = imageLineWidth(in: imageRect)
        switch tool {
        case .line:
            return .line(start: start, end: end, color: annotationColor, lineWidth: lineWidth)
        case .freehand:
            return .freehand(points: [start, end], color: annotationColor, lineWidth: lineWidth)
        case .arrow:
            return .arrow(start: start, end: end, color: annotationColor, lineWidth: lineWidth)
        case .rectangle:
            return .rectangle(
                CGRect(x: start.x, y: start.y, width: end.x - start.x, height: end.y - start.y),
                color: annotationColor,
                lineWidth: lineWidth
            )
        case .mosaic:
            return .mosaic(CGRect(x: start.x, y: start.y, width: end.x - start.x, height: end.y - start.y))
        }
    }

    /// 构建并返回 `draw` 对应的 SwiftUI 界面内容或展示状态。
    private func draw(
        _ annotation: ScreenshotAnnotation,
        in context: inout GraphicsContext,
        imageRect: CGRect,
        isPreview: Bool = false
    ) {
        switch annotation {
        case let .line(start, end, color, lineWidth):
            let lineWidth = canvasLineWidth(lineWidth, in: imageRect)
            var path = Path()
            path.move(to: canvasPoint(from: start, imageRect: imageRect))
            path.addLine(to: canvasPoint(from: end, imageRect: imageRect))
            context.stroke(
                path,
                with: .color(displayColor(color, isPreview: isPreview)),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            )
        case let .freehand(points, color, lineWidth):
            guard let firstPoint = points.first else {
                return
            }
            let lineWidth = canvasLineWidth(lineWidth, in: imageRect)
            var path = Path()
            path.move(to: canvasPoint(from: firstPoint, imageRect: imageRect))
            for point in points.dropFirst() {
                path.addLine(to: canvasPoint(from: point, imageRect: imageRect))
            }
            context.stroke(
                path,
                with: .color(displayColor(color, isPreview: isPreview)),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            )
        case let .arrow(start, end, color, lineWidth):
            let lineWidth = canvasLineWidth(lineWidth, in: imageRect)
            let start = canvasPoint(from: start, imageRect: imageRect)
            let end = canvasPoint(from: end, imageRect: imageRect)
            let angle = atan2(end.y - start.y, end.x - start.x)
            let headLength = ScreenshotAnnotationArrowStyle.headLength(forLineWidth: lineWidth)
            let headLeft = CGPoint(
                x: end.x - headLength * cos(angle - .pi / 6),
                y: end.y - headLength * sin(angle - .pi / 6)
            )
            let headRight = CGPoint(
                x: end.x - headLength * cos(angle + .pi / 6),
                y: end.y - headLength * sin(angle + .pi / 6)
            )
            var path = Path()
            path.move(to: start)
            path.addLine(to: end)
            path.addLine(to: headLeft)
            path.move(to: end)
            path.addLine(to: headRight)
            context.stroke(
                path,
                with: .color(displayColor(color, isPreview: isPreview)),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            )
        case let .rectangle(rect, color, lineWidth):
            context.stroke(
                Path(canvasRect(from: rect, imageRect: imageRect)),
                with: .color(displayColor(color, isPreview: isPreview)),
                lineWidth: canvasLineWidth(lineWidth, in: imageRect)
            )
        case let .mosaic(rect):
            let rect = canvasRect(from: rect, imageRect: imageRect)
            if let mosaicPreviewImage {
                context.drawLayer { layer in
                    layer.clip(to: Path(rect))
                    layer.draw(Image(decorative: mosaicPreviewImage, scale: 1), in: imageRect)
                }
            } else {
                context.fill(Path(rect), with: .color(.secondary.opacity(0.35)))
            }
            if ScreenshotMosaicOutlinePolicy.shouldShowOutline(isPreview: isPreview) {
                context.stroke(
                    Path(rect),
                    with: .color(.accentColor.opacity(0.72)),
                    lineWidth: 2
                )
            }
        }
    }

    /// 构建并返回 `imageLineWidth` 对应的 SwiftUI 界面内容或展示状态。
    private func imageLineWidth(in imageRect: CGRect) -> CGFloat {
        guard imageRect.width > 0 else {
            return annotationLineWidth.points
        }
        return annotationLineWidth.points * CGFloat(image.width) / imageRect.width
    }

    /// 判断 `canvasLineWidth` 所描述的屏幕捕获系统集成条件是否成立。
    private func canvasLineWidth(_ imageLineWidth: CGFloat, in imageRect: CGRect) -> CGFloat {
        imageLineWidth * imageRect.width / CGFloat(image.width)
    }

    /// 构建并返回 `displayColor` 对应的 SwiftUI 界面内容或展示状态。
    private func displayColor(_ color: ScreenshotAnnotationColor, isPreview: Bool) -> Color {
        swiftUIColor(color).opacity(isPreview ? 0.72 : 1)
    }

    /// 构建并返回 `swiftUIColor` 对应的 SwiftUI 界面内容或展示状态。
    private func swiftUIColor(_ color: ScreenshotAnnotationColor) -> Color {
        Color(
            red: Double(color.red),
            green: Double(color.green),
            blue: Double(color.blue),
            opacity: Double(color.alpha)
        )
    }

    /// 构建并返回 `imagePoint` 对应的 SwiftUI 界面内容或展示状态。
    private func imagePoint(from canvasPoint: CGPoint, imageRect: CGRect) -> CGPoint? {
        guard imageRect.contains(canvasPoint) else {
            return nil
        }
        return CGPoint(
            x: (canvasPoint.x - imageRect.minX) * CGFloat(image.width) / imageRect.width,
            y: (imageRect.maxY - canvasPoint.y) * CGFloat(image.height) / imageRect.height
        )
    }

    /// 判断 `canvasPoint` 所描述的屏幕捕获系统集成条件是否成立。
    private func canvasPoint(from imagePoint: CGPoint, imageRect: CGRect) -> CGPoint {
        CGPoint(
            x: imageRect.minX + imagePoint.x * imageRect.width / CGFloat(image.width),
            y: imageRect.maxY - imagePoint.y * imageRect.height / CGFloat(image.height)
        )
    }

    /// 判断 `canvasRect` 所描述的屏幕捕获系统集成条件是否成立。
    private func canvasRect(from imageRect: CGRect, imageRect canvasImageRect: CGRect) -> CGRect {
        let rect = imageRect.standardized
        let minPoint = canvasPoint(from: CGPoint(x: rect.minX, y: rect.minY), imageRect: canvasImageRect)
        let maxPoint = canvasPoint(from: CGPoint(x: rect.maxX, y: rect.maxY), imageRect: canvasImageRect)
        return CGRect(
            x: min(minPoint.x, maxPoint.x),
            y: min(minPoint.y, maxPoint.y),
            width: abs(maxPoint.x - minPoint.x),
            height: abs(maxPoint.y - minPoint.y)
        )
    }

    /// 计算并返回 `distance` 所描述的屏幕捕获系统集成结果。
    private func distance(from first: CGPoint, to second: CGPoint) -> CGFloat {
        hypot(first.x - second.x, first.y - second.y)
    }

    /// 执行 `copyScreenshot` 对应的屏幕捕获系统集成输入输出操作。
    private func copyScreenshot() {
        let annotations = annotationStore.annotations
        let image = image
        isExporting = true
        errorMessage = nil
        Task {
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    try ScreenshotRenderer.pngData(image: image, annotations: annotations)
                }.value
                onCopy(data)
            } catch {
                errorMessage = "截图合成失败，请重试"
                isExporting = false
            }
        }
    }
}

/// 封装 `ScreenshotLineWidthPreview` 在屏幕捕获系统集成中的值语义和相关操作。
private struct ScreenshotLineWidthPreview: Shape {
    /// 构建并返回 `path` 对应的 SwiftUI 界面内容或展示状态。
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 4, y: rect.maxY - 3))
        path.addCurve(
            to: CGPoint(x: rect.maxX - 4, y: rect.minY + 3),
            control1: CGPoint(x: rect.midX - 3, y: rect.maxY - 3),
            control2: CGPoint(x: rect.midX + 3, y: rect.minY + 3)
        )
        return path
    }
}
