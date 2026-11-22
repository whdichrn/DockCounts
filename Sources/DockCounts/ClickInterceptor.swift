import AppKit
import ApplicationServices

final class ClickInterceptor {
    var entries: [DockEntry] = []
    var dockPID: pid_t?
    var shouldIntercept: (DockEntry) -> Bool = { ($0.counts?.total ?? 0) > 0 }
    var hitTest: (CGPoint, [DockEntry]) -> DockEntry?
    var replay: (CGEvent, CGEventTapProxy?) -> Void = { event, proxy in
        if let proxy { event.tapPostEvent(proxy) }
    }
    var onClick: ((DockEntry, CGPoint) -> Void)?
    var onPointerDown: ((CGPoint) -> Void)?
    var dismissOnlyRect: CGRect?
    var onDismissOnlyClick: (() -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var pending: (entry: DockEntry, down: CGEvent)?
    private var consumingDismissClick = false

    init() {
        hitTest = { _, _ in nil }
        hitTest = { [weak self] point, entries in
            AX.fastClickedEntry(at: point, entries: entries, dockPID: self?.dockPID)
        }
    }

    func start() -> Bool {
        if let tap { return CGEvent.tapIsEnabled(tap: tap) }
        let mask = [CGEventType.leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .otherMouseDown]
            .reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        tap = CGEvent.tapCreate(
            tap: .cgAnnotatedSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, pointer in
                guard let pointer else { return Unmanaged.passUnretained(event) }
                return Unmanaged<ClickInterceptor>.fromOpaque(pointer).takeUnretainedValue().handle(proxy, type, event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        guard let tap else { return false }
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let pending { pending.down.post(tap: .cgSessionEventTap) }
        pending = nil
        consumingDismissClick = false
        dismissOnlyRect = nil
        if let tap { CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        entries = []
    }

    func handle(_ proxy: CGEventTapProxy?, _ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            pending = nil
            consumingDismissClick = false
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        if consumingDismissClick {
            if type == .leftMouseDragged {
                return nil
            }
            if type == .leftMouseUp {
                consumingDismissClick = false
                return nil
            }
        }

        let modifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
        if type == .leftMouseDown,
           let dismissOnlyRect,
           event.flags.intersection(modifiers).isEmpty,
           dismissOnlyRect.contains(event.location) {
            consumingDismissClick = true
            DispatchQueue.main.async { [weak self] in self?.onDismissOnlyClick?() }
            return nil
        }

        if [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(type), onPointerDown != nil {
            let point = event.location
            DispatchQueue.main.async { [weak self] in self?.onPointerDown?(point) }
        }

        if type == .leftMouseDown {
            guard event.flags.intersection(modifiers).isEmpty,
                  entries.contains(where: { $0.frame.insetBy(dx: -100, dy: -100).contains(event.location) }),
                  let entry = hitTest(event.location, entries),
                  shouldIntercept(entry),
                  let copy = event.copy() else {
                return Unmanaged.passUnretained(event)
            }
            pending = (entry, copy)
            return nil
        }

        guard let held = pending else { return Unmanaged.passUnretained(event) }

        if type == .leftMouseDragged {
            if hypot(event.location.x - held.down.location.x, event.location.y - held.down.location.y) > 5 {
                pending = nil
                replay(held.down, proxy)
                return Unmanaged.passUnretained(event)
            }
            return nil
        }

        if type == .leftMouseUp {
            pending = nil
            if held.entry.frame.contains(event.location) {
                let point = event.location
                DispatchQueue.main.async { [weak self] in self?.onClick?(held.entry, point) }
            } else {
                replay(held.down, proxy)
                return Unmanaged.passUnretained(event)
            }
            return nil
        }

        return Unmanaged.passUnretained(event)
    }
}
