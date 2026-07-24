import Foundation

struct MemoEditorTextSnapshot: Equatable {
    var text: String
    var selectedRange: NSRange?
}

enum MemoEditorTextTransforms {
    private static let listItemPrefixes = ["- [ ] ", "- [x] ", "- [X] ", "* ", "- "]
    private static let uncheckedTodoPrefix = "- [ ] "

    static func caretAtEnd(of text: String) -> NSRange {
        NSRange(location: text.utf16.count, length: 0)
    }

    static func inserting(_ insertedText: String, into snapshot: MemoEditorTextSnapshot) -> MemoEditorTextSnapshot {
        guard
            let selectedRange = snapshot.selectedRange,
            let stringRange = Range(selectedRange, in: snapshot.text)
        else {
            let updatedText = snapshot.text + insertedText
            return MemoEditorTextSnapshot(
                text: updatedText,
                selectedRange: caretAtEnd(of: updatedText)
            )
        }

        let insertionLocation = NSRange(snapshot.text.startIndex..<stringRange.lowerBound, in: snapshot.text).length
        let updatedText = snapshot.text.replacingCharacters(in: stringRange, with: insertedText)
        let updatedSelection = NSRange(
            location: insertionLocation + insertedText.utf16.count,
            length: 0
        )
        return MemoEditorTextSnapshot(text: updatedText, selectedRange: updatedSelection)
    }

    static func togglingTodo(in snapshot: MemoEditorTextSnapshot) -> MemoEditorTextSnapshot {
        guard
            let selectedRange = snapshot.selectedRange,
            let stringRange = Range(selectedRange, in: snapshot.text)
        else {
            return snapshot
        }

        let currentText = snapshot.text
        let contentBefore = currentText[currentText.startIndex..<stringRange.lowerBound]
        let lineStart = contentBefore.lastIndex(of: "\n").map { currentText.index(after: $0) } ?? currentText.startIndex
        let lineEnd = currentText[stringRange.lowerBound...].firstIndex(of: "\n") ?? currentText.endIndex
        let currentLine = currentText[lineStart..<lineEnd]

        let existingPrefix = listItemPrefixes.first { currentLine.hasPrefix($0) }
        let replacementPrefix: String
        if existingPrefix == uncheckedTodoPrefix {
            replacementPrefix = "- [x] "
        } else {
            replacementPrefix = uncheckedTodoPrefix
        }

        let contentStart = existingPrefix.map {
            currentLine.index(currentLine.startIndex, offsetBy: $0.count)
        } ?? currentLine.startIndex
        let updatedLine = replacementPrefix + currentLine[contentStart...]
        let updatedText = currentText[..<lineStart] + updatedLine + currentText[lineEnd...]
        let prefixDelta = replacementPrefix.utf16.count - (existingPrefix?.utf16.count ?? 0)
        let updatedSelection = NSRange(
            location: max(0, selectedRange.location + prefixDelta),
            length: selectedRange.length
        )

        return MemoEditorTextSnapshot(
            text: String(updatedText),
            selectedRange: updatedSelection
        )
    }

    static func continuingList(from oldText: String, to newText: String) -> MemoEditorTextSnapshot? {
        guard
            let edit = detectSingleEdit(old: oldText, new: newText),
            edit.replacedRange.isEmpty,
            edit.insertedText == "\n"
        else {
            return nil
        }

        let insertionPoint = edit.replacedRange.lowerBound
        let contentBefore = oldText[oldText.startIndex..<insertionPoint]
        let lineStart = contentBefore.lastIndex(of: "\n").map { oldText.index(after: $0) } ?? oldText.startIndex
        let lineEnd = oldText[insertionPoint...].firstIndex(of: "\n") ?? oldText.endIndex
        let currentLine = oldText[lineStart..<lineEnd]

        guard let prefix = listItemPrefixes.first(where: { currentLine.hasPrefix($0) }) else {
            return nil
        }
        guard
            currentLine.count > prefix.count,
            oldText.index(currentLine.startIndex, offsetBy: prefix.count) < insertionPoint
        else {
            return nil
        }

        let insertionLocation = NSRange(oldText.startIndex..<insertionPoint, in: oldText).length
        let updatedText = oldText[..<insertionPoint] + "\n" + prefix + oldText[insertionPoint...]
        let updatedSelection = NSRange(
            location: insertionLocation + "\n".utf16.count + prefix.utf16.count,
            length: 0
        )
        return MemoEditorTextSnapshot(
            text: String(updatedText),
            selectedRange: updatedSelection
        )
    }

    private static func detectSingleEdit(
        old: String,
        new: String
    ) -> (replacedRange: Range<String.Index>, insertedText: Substring)? {
        var oldStart = old.startIndex
        var newStart = new.startIndex
        while oldStart < old.endIndex, newStart < new.endIndex, old[oldStart] == new[newStart] {
            old.formIndex(after: &oldStart)
            new.formIndex(after: &newStart)
        }

        if oldStart == old.endIndex, newStart == new.endIndex {
            return nil
        }

        var oldEnd = old.endIndex
        var newEnd = new.endIndex
        while oldEnd > oldStart, newEnd > newStart {
            let oldPrevious = old.index(before: oldEnd)
            let newPrevious = new.index(before: newEnd)
            guard old[oldPrevious] == new[newPrevious] else {
                break
            }
            oldEnd = oldPrevious
            newEnd = newPrevious
        }

        return (oldStart..<oldEnd, new[newStart..<newEnd])
    }
}
