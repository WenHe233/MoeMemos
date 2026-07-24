import Foundation
import XCTest
@testable import MemoKit

final class MemoEditorTextTransformsTests: XCTestCase {
    func testInsertAtCaretUsesUTF16Offsets() {
        let result = MemoEditorTextTransforms.inserting(
            "#swift ",
            into: MemoEditorTextSnapshot(
                text: "🙂memo",
                selectedRange: NSRange(location: 2, length: 0)
            )
        )

        XCTAssertEqual(result.text, "🙂#swift memo")
        XCTAssertEqual(result.selectedRange, NSRange(location: 9, length: 0))
    }

    func testInsertReplacesSelection() {
        let result = MemoEditorTextTransforms.inserting(
            "#tag ",
            into: MemoEditorTextSnapshot(
                text: "hello world",
                selectedRange: NSRange(location: 6, length: 5)
            )
        )

        XCTAssertEqual(result.text, "hello #tag ")
        XCTAssertEqual(result.selectedRange, NSRange(location: 11, length: 0))
    }

    func testInsertWithoutSelectionAppendsToEmptyText() {
        let result = MemoEditorTextTransforms.inserting(
            "#tag ",
            into: MemoEditorTextSnapshot(text: "", selectedRange: nil)
        )

        XCTAssertEqual(result.text, "#tag ")
        XCTAssertEqual(result.selectedRange, NSRange(location: 5, length: 0))
    }

    func testInsertSafelyReplacesCombiningCharacterSelection() {
        let text = "e\u{301}x"
        let result = MemoEditorTextTransforms.inserting(
            "A",
            into: MemoEditorTextSnapshot(
                text: text,
                selectedRange: NSRange(location: 0, length: 2)
            )
        )

        XCTAssertEqual(result.text, "Ax")
        XCTAssertEqual(result.selectedRange, NSRange(location: 1, length: 0))
    }

    func testToggleTodoChecksUncheckedItem() {
        let result = MemoEditorTextTransforms.togglingTodo(
            in: MemoEditorTextSnapshot(
                text: "- [ ] task",
                selectedRange: NSRange(location: 6, length: 0)
            )
        )

        XCTAssertEqual(result.text, "- [x] task")
        XCTAssertEqual(result.selectedRange, NSRange(location: 6, length: 0))
    }

    func testToggleTodoConvertsCheckedItemToUncheckedItem() {
        let result = MemoEditorTextTransforms.togglingTodo(
            in: MemoEditorTextSnapshot(
                text: "- [X] task",
                selectedRange: NSRange(location: 6, length: 0)
            )
        )

        XCTAssertEqual(result.text, "- [ ] task")
        XCTAssertEqual(result.selectedRange, NSRange(location: 6, length: 0))
    }

    func testToggleTodoConvertsOtherListPrefixToUncheckedItem() {
        let result = MemoEditorTextTransforms.togglingTodo(
            in: MemoEditorTextSnapshot(
                text: "* task",
                selectedRange: NSRange(location: 2, length: 0)
            )
        )

        XCTAssertEqual(result.text, "- [ ] task")
        XCTAssertEqual(result.selectedRange, NSRange(location: 6, length: 0))
    }

    func testToggleTodoPreservesCrossLineSelectionLength() {
        let result = MemoEditorTextTransforms.togglingTodo(
            in: MemoEditorTextSnapshot(
                text: "first\nsecond\nthird",
                selectedRange: NSRange(location: 8, length: 8)
            )
        )

        XCTAssertEqual(result.text, "first\n- [ ] second\nthird")
        XCTAssertEqual(result.selectedRange, NSRange(location: 14, length: 8))
    }

    func testListContinuationInsertsMatchingPrefix() {
        let result = MemoEditorTextTransforms.continuingList(
            from: "- item",
            to: "- item\n"
        )

        XCTAssertEqual(result?.text, "- item\n- ")
        XCTAssertEqual(result?.selectedRange, NSRange(location: 9, length: 0))
    }

    func testListContinuationUsesUTF16CaretForEmoji() {
        let result = MemoEditorTextTransforms.continuingList(
            from: "- 🙂",
            to: "- 🙂\n"
        )

        XCTAssertEqual(result?.text, "- 🙂\n- ")
        XCTAssertEqual(result?.selectedRange, NSRange(location: 7, length: 0))
    }

    func testListContinuationDoesNotContinueEmptyItem() {
        let result = MemoEditorTextTransforms.continuingList(
            from: "- ",
            to: "- \n"
        )

        XCTAssertNil(result)
    }
}
