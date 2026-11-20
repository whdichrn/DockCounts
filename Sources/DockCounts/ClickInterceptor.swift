import AppKit
import ApplicationServices

final class ClickInterceptor {
    var entries: [DockEntry] = []
    var hitTest: (CGPoint, [DockEntry]) -> DockEntry? = { AX.clickedEntry(at: $0, entries: $1) }
    var replay: (CGEvent, CGEventTapProxy?) -> Void = { event, proxy in if let proxy { event.tapPostEvent(proxy) } }
    var onClick: ((DockEntry, CGPoint) -> Void)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var pending: (entry: DockEntry, down: CGEvent)?
    func start() -> Bool {
        if let tap { return CGEvent.tapIsEnabled(tap: tap) }
        let mask = [CGEventType.leftMouseDown, .leftMouseUp, .leftMouseDragged].reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: { proxy, type, event, pointer in
            guard let pointer else { return Unmanaged.passUnretained(event) }
            return Unmanaged<ClickInterceptor>.fromOpaque(pointer).takeUnretainedValue().handle(proxy, type, event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { return false }
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }
    func stop() {
        // Release any held mouse-down before removing the tap.
        if let pending { pending.down.post(tap: .cgSessionEventTap) }
        pending = nil
        if let tap { CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil; entries = []
    }
    func handle(_ proxy: CGEventTapProxy?, _ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            pending = nil
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if type == .leftMouseDown {
            let modifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
            guard event.flags.intersection(modifiers).isEmpty,
                  entries.contains(where: { $0.frame.insetBy(dx: -100, dy: -100).contains(event.location) }),
                  let entry = hitTest(event.location, entries), let copy = event.copy() else { return Unmanaged.passUnretained(event) }
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
                DispatchQueue.main.async { [weak self] in self?.onClick?(held.entry, event.location) }
            } else {
                replay(held.down, proxy)
                return Unmanaged.passUnretained(event)
            }
            return nil
        }
        return Unmanaged.passUnretained(event)
    }
}
