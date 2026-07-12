import CoreGraphics
import MacToolsCore
import SwiftUI

private enum ScreenshotEditorTool: CaseIterable, Identifiable {
    case line
    case arrow
    case rectangle
    case mosaic

    var id: Self { self }

    var title: String {
        switch self {
        case .line:
            return "划线"
        case .arrow:
            return "箭头"
        case .rectangle:
            return "画框"
        case .mosaic:
            return "马赛克"
        }
    }

    var imageName: String {
        switch self {
        case .line:
            return "line.diagonal"
        case .arrow:
            return "arrow.up.right"
        case .rectangle:
            return "rectangle"
        case .mosaic:
            return "checkerboard.rectangle"
        }
    }
}

struct ScreenshotEditorView: View {
    let image: CGImage
    let onCopy: (Data) -> Void
    let onCancel: () -> Void

    @State private var tool: ScreenshotEditorTool = .line
    @State private var annotationStore = ScreenshotAnnotationStore()
    @State private var dragStart: CGPoint?
    @State private var previewAnnotation: ScreenshotAnnotation?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 14) {
            header
            editorCanvas
            footer
        }
        .padding(18)
        .frame(minWidth: 620, minHeight: 440)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Label("截图编辑", systemImage: "camera.viewfinder")
                .font(.system(size: 18, weight: .semibold))

            Spacer()

            ForEach(ScreenshotEditorTool.allCases) { candidate in
                Button {
                    tool = candidate
                } label: {
                    Label(candidate.title, systemImage: candidate.imageName)
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .tint(tool == candidate ? .accentColor : .secondary)
            }

            Button {
                _ = annotationStore.undo()
            } label: {
                Label("撤销", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(.bordered)
            .disabled(annotationStore.annotations.isEmpty)
            .keyboardShortcut("z", modifiers: .command)
        }
        .foregroundStyle(MacToolsGlassTheme.textPrimary)
    }

    private var editorCanvas: some View {
        GeometryReader { proxy in
            let imageRect = fittedImageRect(in: proxy.size)

            ZStack {
                Color.black.opacity(0.76)

                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: imageRect.width, height: imageRect.height)
                    .position(x: imageRect.midX, y: imageRect.midY)

                Canvas { context, _ in
                    for annotation in annotationStore.annotations {
                        draw(annotation, in: &context, imageRect: imageRect)
                    }
                    if let previewAnnotation {
                        draw(previewAnnotation, in: &context, imageRect: imageRect, isPreview: true)
                    }
                }
                .contentShape(Rectangle())
                .gesture(annotationGesture(imageRect: imageRect))
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottomLeading) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.red)
                    .padding(10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(12)
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("拖拽即可\(tool.title)；完成后仅复制到剪贴板")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(MacToolsGlassTheme.textSecondary)

            Spacer()

            Button("取消", action: onCancel)
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)

            Button {
                copyScreenshot()
            } label: {
                Label("完成并复制", systemImage: "doc.on.clipboard")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: .command)
        }
    }

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
                previewAnnotation = annotation(from: dragStart, to: point)
            }
            .onEnded { value in
                defer {
                    dragStart = nil
                    previewAnnotation = nil
                }
                guard let dragStart,
                      let point = imagePoint(from: value.location, imageRect: imageRect),
                      distance(from: dragStart, to: point) >= 2 else {
                    return
                }
                annotationStore.append(annotation(from: dragStart, to: point))
            }
    }

    private func annotation(from start: CGPoint, to end: CGPoint) -> ScreenshotAnnotation {
        switch tool {
        case .line:
            return .line(start: start, end: end)
        case .arrow:
            return .arrow(start: start, end: end)
        case .rectangle:
            return .rectangle(CGRect(x: start.x, y: start.y, width: end.x - start.x, height: end.y - start.y))
        case .mosaic:
            return .mosaic(CGRect(x: start.x, y: start.y, width: end.x - start.x, height: end.y - start.y))
        }
    }

    private func draw(
        _ annotation: ScreenshotAnnotation,
        in context: inout GraphicsContext,
        imageRect: CGRect,
        isPreview: Bool = false
    ) {
        let color = isPreview ? Color.accentColor.opacity(0.72) : Color.accentColor
        let lineWidth: CGFloat = isPreview ? 2 : 3

        switch annotation {
        case let .line(start, end):
            var path = Path()
            path.move(to: canvasPoint(from: start, imageRect: imageRect))
            path.addLine(to: canvasPoint(from: end, imageRect: imageRect))
            context.stroke(path, with: .color(color), lineWidth: lineWidth)
        case let .arrow(start, end):
            let start = canvasPoint(from: start, imageRect: imageRect)
            let end = canvasPoint(from: end, imageRect: imageRect)
            let angle = atan2(end.y - start.y, end.x - start.x)
            let headLength: CGFloat = 10
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
            context.stroke(path, with: .color(color), lineWidth: lineWidth)
        case let .rectangle(rect):
            context.stroke(
                Path(canvasRect(from: rect, imageRect: imageRect)),
                with: .color(color),
                lineWidth: lineWidth
            )
        case let .mosaic(rect):
            context.fill(
                Path(canvasRect(from: rect, imageRect: imageRect)),
                with: .color(.black.opacity(isPreview ? 0.25 : 0.38))
            )
            context.stroke(
                Path(canvasRect(from: rect, imageRect: imageRect)),
                with: .color(color),
                lineWidth: lineWidth
            )
        }
    }

    private func fittedImageRect(in size: CGSize) -> CGRect {
        let imageSize = CGSize(width: image.width, height: image.height)
        let scale = min(size.width / imageSize.width, size.height / imageSize.height)
        let fittedSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (size.width - fittedSize.width) / 2,
            y: (size.height - fittedSize.height) / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }

    private func imagePoint(from canvasPoint: CGPoint, imageRect: CGRect) -> CGPoint? {
        guard imageRect.contains(canvasPoint) else {
            return nil
        }
        return CGPoint(
            x: (canvasPoint.x - imageRect.minX) * CGFloat(image.width) / imageRect.width,
            y: (imageRect.maxY - canvasPoint.y) * CGFloat(image.height) / imageRect.height
        )
    }

    private func canvasPoint(from imagePoint: CGPoint, imageRect: CGRect) -> CGPoint {
        CGPoint(
            x: imageRect.minX + imagePoint.x * imageRect.width / CGFloat(image.width),
            y: imageRect.maxY - imagePoint.y * imageRect.height / CGFloat(image.height)
        )
    }

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

    private func distance(from first: CGPoint, to second: CGPoint) -> CGFloat {
        hypot(first.x - second.x, first.y - second.y)
    }

    private func copyScreenshot() {
        do {
            onCopy(try ScreenshotRenderer.pngData(image: image, annotations: annotationStore.annotations))
        } catch {
            errorMessage = "截图合成失败，请重试"
        }
    }
}
