import AppKit
import SwiftUI

/// A read-only, selectable, searchable (⌘F) log view. Appends new lines
/// incrementally and follows the output while scrolled to the bottom.
struct LogTextView: NSViewRepresentable {
    let logs: LogBuffer
    // Passed explicitly so SwiftUI re-runs updateNSView when they change.
    let sequence: Int
    let generation: Int

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        let textView = scrollView.documentView as! NSTextView
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isAutomaticLinkDetectionEnabled = false
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.render(logs, into: scrollView)
    }

    @MainActor
    final class Coordinator {
        private weak var renderedBuffer: LogBuffer?
        private var renderedGeneration = -1
        private var renderedUpTo = 0
        private var renderedLineCount = 0

        func render(_ logs: LogBuffer, into scrollView: NSScrollView) {
            guard let textView = scrollView.documentView as? NSTextView, let storage = textView.textStorage else { return }
            let atBottom = scrollView.contentView.bounds.maxY >= textView.frame.height - 24

            let mustRebuild = renderedBuffer !== logs
                || renderedGeneration != logs.generation
                || renderedUpTo < logs.firstSequence // Lines we never showed were trimmed.
                || renderedLineCount > LogBuffer.capacity + 1_000
            let newLines: ArraySlice<LogLine>
            if mustRebuild {
                storage.setAttributedString(NSAttributedString())
                renderedLineCount = 0
                newLines = logs.lines[...]
            } else {
                newLines = logs.lines.dropFirst(renderedUpTo - logs.firstSequence)
            }
            renderedBuffer = logs
            renderedGeneration = logs.generation
            renderedUpTo = logs.nextSequence
            guard mustRebuild || !newLines.isEmpty else { return }

            let chunk = NSMutableAttributedString()
            for line in newLines {
                if renderedLineCount > 0 || chunk.length > 0 { chunk.append(Self.newline) }
                chunk.append(ANSI.attributed(line.text, base: Self.attributes(for: line.stream)))
            }
            renderedLineCount += newLines.count
            storage.append(chunk)

            if mustRebuild || atBottom {
                textView.scrollToEndOfDocument(nil)
            }
        }

        private static let newline = NSAttributedString(string: "\n", attributes: attributes(for: .stdout))
        private static let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

        private static func attributes(for stream: LogStream) -> [NSAttributedString.Key: Any] {
            switch stream {
            case .stdout:
                [.font: font, .foregroundColor: NSColor.labelColor]
            case .stderr:
                [.font: font, .foregroundColor: NSColor.systemRed]
            case .system:
                [.font: NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask), .foregroundColor: NSColor.secondaryLabelColor]
            }
        }
    }
}
