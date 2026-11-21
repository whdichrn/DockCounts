// Read-only installed-app transition recorder. No input events or screen pixels.
import AppKit
import ApplicationServices
func value(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
    var result: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, key as CFString, &result) == .success ? result : nil
}
func frame(_ element: AXUIElement) -> CGRect? {
    guard let p=value(element,kAXPositionAttribute),let s=value(element,kAXSizeAttribute),CFGetTypeID(p)==AXValueGetTypeID(),CFGetTypeID(s)==AXValueGetTypeID() else{return nil}
    var point=CGPoint.zero,size=CGSize.zero
    guard AXValueGetValue(p as! AXValue,.cgPoint,&point),AXValueGetValue(s as! AXValue,.cgSize,&size) else{return nil}
    return CGRect(origin:point,size:size)
}
func rect(_ r:CGRect)->[Double]{[r.minX,r.minY,r.width,r.height].map(Double.init)}
let duration = Double(CommandLine.arguments.dropFirst().first ?? "60") ?? 60
let path = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "/tmp/dockcounts-transitions.jsonl"
FileManager.default.createFile(atPath:path,contents:nil)
let file=try FileHandle(forWritingTo:URL(fileURLWithPath:path))
let start=ProcessInfo.processInfo.systemUptime
while ProcessInfo.processInfo.systemUptime-start < duration {
    autoreleasepool {
        guard let dock=NSRunningApplication.runningApplications(withBundleIdentifier:"com.apple.dock").first,
              let app=NSRunningApplication.runningApplications(withBundleIdentifier:"io.github.whdichrn.DockCounts").first else{return}
        let root=AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(root,0.03)
        let roots=value(root,kAXChildrenAttribute) as? [AXUIElement] ?? []
        let list=roots.first{value($0,kAXRoleAttribute) as? String == kAXListRole}
        let items=list.flatMap{value($0,kAXChildrenAttribute) as? [AXUIElement]} ?? []
        let tiles=items.compactMap { item->[String:Any]? in
            guard value(item,kAXSubroleAttribute) as? String == "AXApplicationDockItem",let r=frame(item) else{return nil}
            return ["frame":rect(r)]
        }
        let windows=CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]] ?? []
        let ax=AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(ax,0.03)
        let owned=value(ax,kAXWindowsAttribute) as? [AXUIElement] ?? []
        let badges=owned.compactMap { window->[String:Any]? in
            guard value(window,kAXIdentifierAttribute) as? String == "io.github.whdichrn.DockCounts.badge",let r=frame(window) else{return nil}
            let match=windows.first { info in
                guard info[kCGWindowOwnerPID as String] as? Int == Int(app.processIdentifier),let bounds=info[kCGWindowBounds as String] as? NSDictionary,let cg=CGRect(dictionaryRepresentation:bounds) else{return false}
                return abs(cg.minX-r.minX)<1 && abs(cg.minY-r.minY)<1 && abs(cg.width-r.width)<1
            }
            return ["frame":rect(r),"onscreen":match != nil,"number":match?[kCGWindowNumber as String] as? Int ?? -1]
        }
        let event:[String:Any]=["t":ProcessInfo.processInfo.systemUptime-start,"dock":list.flatMap(frame).map(rect) ?? [],"tiles":tiles,"badges":badges,"reduced":NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency]
        if let data=try? JSONSerialization.data(withJSONObject:event,options:[.sortedKeys]) {file.write(data);file.write(Data([10]))}
    }
    RunLoop.current.run(until:Date().addingTimeInterval(0.05))
}
try file.close()
print(path)
