import Observation
import SwiftUI
import UIKit

@MainActor
@Observable
final class MemoEditorTextState {
    var text = ""
    private(set) var selectedRange: NSRange?
    private(set) var selectionRevision = 0

    func updateSelectionFromEditor(_ selectedRange: NSRange?) {
        self.selectedRange = selectedRange
    }

    func apply(_ snapshot: MemoEditorTextSnapshot) {
        text = snapshot.text
        selectedRange = snapshot.selectedRange
        selectionRevision &+= 1
    }
}

struct AdaptiveMemoTextEditor: View {
    let state: MemoEditorTextState
    let focused: FocusState<Bool>.Binding

    @ViewBuilder
    var body: some View {
        if #available(iOS 18.0, macCatalyst 18.0, visionOS 2.0, *) {
            NativeSelectionMemoTextEditor(state: state, focused: focused)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            LegacySelectionMemoTextEditor(state: state, focused: focused)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

@available(iOS 18.0, macCatalyst 18.0, visionOS 2.0, *)
private struct NativeSelectionMemoTextEditor: View {
    @Bindable var state: MemoEditorTextState
    let focused: FocusState<Bool>.Binding

    @State private var nativeSelection: TextSelection?

    var body: some View {
        TextEditor(text: $state.text, selection: $nativeSelection)
            .focused(focused)
            .onChange(of: nativeSelection) { _, newSelection in
                state.updateSelectionFromEditor(nsRange(for: newSelection))
            }
            .onChange(of: state.selectionRevision, initial: true) { _, _ in
                nativeSelection = textSelection(for: state.selectedRange)
            }
    }

    private func nsRange(for selection: TextSelection?) -> NSRange? {
        guard let selection else {
            return nil
        }
        switch selection.indices {
        case .selection(let range):
            return NSRange(range, in: state.text)
        case .multiSelection(let rangeSet):
            guard let range = rangeSet.ranges.first else {
                return nil
            }
            return NSRange(range, in: state.text)
        @unknown default:
            return nil
        }
    }

    private func textSelection(for range: NSRange?) -> TextSelection? {
        guard
            let range,
            let stringRange = Range(range, in: state.text)
        else {
            return nil
        }
        return TextSelection(range: stringRange)
    }
}

private struct LegacySelectionMemoTextEditor: UIViewRepresentable {
    let state: MemoEditorTextState
    let focused: FocusState<Bool>.Binding

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state, focused: focused)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        textView.textContainer.lineFragmentPadding = 5
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        if textView.text != state.text {
            textView.text = state.text
        }

        if context.coordinator.appliedSelectionRevision != state.selectionRevision {
            let textLength = textView.text.utf16.count
            let range = state.selectedRange ?? NSRange(location: textLength, length: 0)
            let location = min(max(0, range.location), textLength)
            let length = min(max(0, range.length), textLength - location)
            textView.selectedRange = NSRange(location: location, length: length)
            context.coordinator.appliedSelectionRevision = state.selectionRevision
        }

        if focused.wrappedValue, !textView.isFirstResponder {
            textView.becomeFirstResponder()
        } else if !focused.wrappedValue, textView.isFirstResponder {
            textView.resignFirstResponder()
        }
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        let state: MemoEditorTextState
        let focused: FocusState<Bool>.Binding
        var appliedSelectionRevision = -1

        init(state: MemoEditorTextState, focused: FocusState<Bool>.Binding) {
            self.state = state
            self.focused = focused
        }

        func textViewDidChange(_ textView: UITextView) {
            state.text = textView.text
            state.updateSelectionFromEditor(textView.selectedRange)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            state.updateSelectionFromEditor(textView.selectedRange)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            focused.wrappedValue = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            focused.wrappedValue = false
        }
    }
}
