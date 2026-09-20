import CoreGraphics
import Foundation
import MacToolsCore

/// start/stop 由主 Actor 串行调用；tap、手势和一次性计时器只在专用线程访问。
/// lock 仅保护跨线程的运行循环句柄，回调不等待主线程，不执行文件或选区 I/O。
final class RightClickEventTap: @unchecked Sendable {
    typealias TapFactory = @Sendable (CGEventMask, CGEventTapCallBack, UnsafeMutableRawPointer) -> CFMachPort?
    private let lock = NSLock()
    private var runLoop: CFRunLoop?
    private var stopping = false
    private var installed = false
    private let ready = DispatchSemaphore(value: 0)
    private let finished = DispatchSemaphore(value: 0)
    private let logger: Logger
    private let processor: RightClickEventProcessor
    private let createTap: TapFactory
    private var tap: CFMachPort?
    private var timer: Timer?
    private var scheduledDeadline: Int?

    init(thresholdMilliseconds: Int, logger: Logger,
         createTap: @escaping TapFactory = { mask, callback, info in
             CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                 options: .defaultTap, eventsOfInterest: mask, callback: callback, userInfo: info)
         },
         output: @escaping @Sendable (RightClickEventProcessor.Output) -> Void) {
        self.logger = logger
        self.createTap = createTap
        processor = RightClickEventProcessor(thresholdMilliseconds: thresholdMilliseconds, output: output)
    }

    func start() -> Bool {
        let thread = Thread { [self] in run() }
        thread.name = "MacTools right-click events"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        return lock.withLock { installed }
    }

    func stop() {
        let loop = lock.withLock { () -> CFRunLoop? in
            guard !stopping else { return nil }
            stopping = true
            return runLoop
        }
        guard let loop else { return }
        CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue) { [self] in
            timer?.invalidate()
            timer = nil
            processor.cancel()
            if let tap { CFMachPortInvalidate(tap) }
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
        CFRunLoopWakeUp(loop)
        // 旧 tap 必须完全退出，才能安装新 tap，避免短按回放再次被旧监听器消费。
        finished.wait()
    }

    private func run() {
        defer { finished.signal() }
        let mask = CGEventMask(1 << CGEventType.rightMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.rightMouseUp.rawValue)
            | CGEventMask(1 << CGEventType.rightMouseDragged.rawValue)
        guard let tap = createTap(mask, { proxy, type, event, info in
                guard let info else { return Unmanaged.passUnretained(event) }
                let owner = Unmanaged<RightClickEventTap>.fromOpaque(info).takeUnretainedValue()
                return autoreleasepool { owner.handle(type: type, event: event, proxy: proxy) }
            }, Unmanaged.passUnretained(self).toOpaque()
        ) else {
            ready.signal()
            return
        }
        self.tap = tap
        let loop = CFRunLoopGetCurrent()!
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(loop, source, .commonModes)
        lock.withLock { runLoop = loop; installed = true }
        CGEvent.tapEnable(tap: tap, enable: true)
        ready.signal()
        CFRunLoopRun()
        timer?.invalidate()
        CFMachPortInvalidate(tap)
        CFRunLoopRemoveSource(loop, source, .commonModes)
        self.tap = nil
        lock.withLock { runLoop = nil; installed = false }
    }

    private func handle(type: CGEventType, event: CGEvent, proxy: CGEventTapProxy) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            timer?.invalidate()
            timer = nil
            scheduledDeadline = nil
            processor.cancel()
            logger.error("super right click event tap interrupted; cancelled active gesture")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let suppress = processor.process(type: type, event: event) { $0.tapPostEvent(proxy) }
        scheduleTimer()
        return suppress ? nil : Unmanaged.passUnretained(event)
    }

    private func scheduleTimer() {
        let deadline = processor.deadlineMilliseconds
        guard scheduledDeadline != deadline else { return }
        timer?.invalidate()
        timer = nil
        scheduledDeadline = deadline
        guard let deadline else { return }
        let now = Int(DispatchTime.now().uptimeNanoseconds / 1_000_000)
        let timer = Timer(timeInterval: max(0.001, Double(deadline - now) / 1_000), repeats: false) { [weak self] _ in
            guard let self else { return }
            autoreleasepool {
                self.scheduledDeadline = nil
                self.processor.timerFired()
                self.scheduleTimer()
            }
        }
        self.timer = timer
        RunLoop.current.add(timer, forMode: .common)
    }
}
