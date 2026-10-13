import AppKit
import SwiftUI

/// App-local mouse events release the field editor without intercepting the next control's click.
struct EditorFocusDismissal: NSViewRepresentable {
    final class Anchor: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
    final class Coordinator {
        var monitor: Any?
        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> Anchor {
        let view = Anchor()
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak view] event in
            guard let window = view?.window, event.window === window,
                  let editor = window.firstResponder as? NSTextView, editor.isFieldEditor,
                  let field = editor.delegate as? NSTextField else { return event }
            let point = field.convert(event.locationInWindow, from: nil)
            if !field.bounds.contains(point) { window.makeFirstResponder(nil) }
            return event
        }
        return view
    }
    func updateNSView(_ view: Anchor, context: Context) {}
    static func dismantleNSView(_ view: Anchor, coordinator: Coordinator) { coordinator.stop() }
}
