import AppKit
import SwiftUI
let app = NSApplication.shared
app.setActivationPolicy(.regular)
final class PatternView: NSView {
    override func draw(_ dirty: NSRect) {
        for x in stride(from: 0, to: 720, by: 24) {
            for y in stride(from: 0, to: 360, by: 24) {
                let colors: [NSColor] = [.systemBlue, .systemOrange, .systemTeal, .systemPurple]
                colors[((x / 24) + (y / 24)) % colors.count].setFill()
                NSRect(x:x,y:y,width:24,height:24).fill()
            }
        }
    }
}
let background = NSWindow(contentRect:NSRect(x:280,y:240,width:720,height:360),styleMask:[.titled,.closable],backing:.buffered,defer:false)
background.title="DockCounts Material Comparison"
background.contentView=PatternView()
background.makeKeyAndOrderFront(nil)
final class SamplePanel: NSPanel { override var canBecomeKey: Bool { true } }
let overlay=SamplePanel(contentRect:background.contentRect(forFrameRect:background.frame),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
overlay.title="DockCounts Material Samples";overlay.setAccessibilityRole(.window);overlay.setAccessibilitySubrole(.standardWindow);overlay.isOpaque=false;overlay.backgroundColor = .clear;overlay.hasShadow=false;overlay.hidesOnDeactivate=false
let container=NSView(frame:NSRect(x:0,y:0,width:720,height:360))
let styles:[(String,NSVisualEffectView.Material)]=[("HUD",.hudWindow),("Popover",.popover),("Menu",.menu)]
for index in 0..<6 {
    let frame=NSRect(x:36+(index%3)*230,y:60+(index/3)*175,width:180,height:64)
    let effect:NSView
    let name:String
    if index < 3 {
        let view=NSVisualEffectView(frame:frame);view.material=styles[index].1;view.blendingMode = .behindWindow;view.state = .active;view.wantsLayer=true;view.layer?.cornerRadius=32;view.layer?.masksToBounds=true
        effect=view;name=styles[index].0
    } else if index == 5 {
        effect = NSHostingView(rootView: Text("3 · 1").font(.system(size:24,weight:.medium)).frame(width:180,height:64).background(.regularMaterial,in:Capsule()))
        effect.frame=frame;name="SwiftUI Regular"
    } else {
        let view=NSGlassEffectView(frame:frame);view.cornerRadius=32;view.style = .clear
        if index == 3 { view.tintColor = NSColor.white.withAlphaComponent(0.55) }
        effect=view;name=index == 3 ? "Clear + light tint" : "Glass Clear"
    }
    let label=NSTextField(labelWithString:"3 · 1")
    label.font = .monospacedDigitSystemFont(ofSize:24,weight:.medium);label.alignment = .center
    label.frame=NSRect(x:0,y:14,width:180,height:34)
    if index == 5 { } else if let glass=effect as? NSGlassEffectView { let content=NSView(frame:NSRect(x:0,y:0,width:180,height:64));content.addSubview(label);glass.contentView=content } else { effect.addSubview(label) }
    container.addSubview(effect)
    let title=NSTextField(labelWithString:name);title.font = .systemFont(ofSize:14,weight:.semibold);title.textColor = .white;title.drawsBackground=true;title.backgroundColor=NSColor.black.withAlphaComponent(0.75);title.alignment = .center;title.frame=NSRect(x:frame.minX,y:frame.maxY+10,width:180,height:24);container.addSubview(title)
}
background.addChildWindow(overlay,ordered:.above);overlay.contentView=container;app.activate(ignoringOtherApps:true);overlay.makeKeyAndOrderFront(nil);app.run()
