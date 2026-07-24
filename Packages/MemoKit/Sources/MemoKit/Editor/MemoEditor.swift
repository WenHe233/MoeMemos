import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import Models
import Account
import DesignSystem
import SwiftData
#if canImport(JournalingSuggestions) && os(iOS) && !targetEnvironment(macCatalyst)
@_weakLinked @preconcurrency import JournalingSuggestions
#endif

@MainActor
public struct MemoEditor: View {
    public let memo: StoredMemo?
    public let actions: MemoEditorActions

    @Environment(AccountViewModel.self) private var userState
    @Environment(AccountManager.self) private var accountManager
    @State private var viewModel = MemoEditorViewModel()

    @State private var editorTextState = MemoEditorTextState()
    @State private var isApplyingAutoContinuation = false

    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    @State private var showingPhotoPicker = false
    @State private var showingImagePicker = false
    @State private var showingDocumentScanner = false
    @State private var showingFilePicker = false
    @State private var showingJournalingSuggestionsPicker = false
    @State private var submitError: Error?
    @State private var showingErrorToast = false
    @State private var availableTags: [Tag] = []

    public init(memo: StoredMemo?, actions: MemoEditorActions) {
        self.memo = memo
        self.actions = actions
    }

    private var text: String {
        editorTextState.text
    }

    private var textSnapshot: MemoEditorTextSnapshot {
        MemoEditorTextSnapshot(
            text: editorTextState.text,
            selectedRange: editorTextState.selectedRange
        )
    }

    private var draftUserDefaults: UserDefaults {
        UserDefaults(suiteName: AppInfo.groupContainerIdentifier) ?? .standard
    }

    private var draftStorageKey: String {
        "draft.\(accountManager.currentAccount?.key ?? "default")"
    }

    private var draft: String {
        get {
            draftUserDefaults.string(forKey: draftStorageKey) ?? ""
        }
        nonmutating set {
            draftUserDefaults.set(newValue, forKey: draftStorageKey)
        }
    }

    @ViewBuilder
    private func toolbar() -> some View {
        MemoEditorToolbar(
            tags: availableTags,
            onInsertTag: { tag in
                insert(tag: tag)
            },
            onToggleTodo: {
                toggleTodoItem()
            },
            onPickJournalingSuggestion: {
                showingJournalingSuggestionsPicker = true
            },
            supportsJournalingSuggestions: supportsJournalingSuggestions,
            onPickPhotos: {
                showingPhotoPicker = true
            },
            onPickCamera: {
                showingImagePicker = true
            },
            supportsDocumentScanning: supportsDocumentScanning,
            onScanDocument: {
                showingDocumentScanner = true
            },
            onPickFiles: {
                showingFilePicker = true
            }
        )
    }

    @ViewBuilder
    private func editor() -> some View {
        ZStack(alignment: .bottom) {
            VStack(alignment: .leading) {
                privacyMenu
                    .padding(.horizontal)
                AdaptiveMemoTextEditor(state: editorTextState, focused: $focused)
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("input.placeholder")
                                .foregroundColor(.secondary)
                                .padding(EdgeInsets(top: 8, leading: 5, bottom: 8, trailing: 5))
                        }
                    }
                    .padding(.horizontal)
                MemoEditorResourceView(viewModel: viewModel)
            }
            .safeAreaInset(edge: .bottom) {
                toolbar()
            }
        }

        .onAppear {
            if let memo = memo {
                editorTextState.apply(
                    MemoEditorTextSnapshot(
                        text: memo.content,
                        selectedRange: MemoEditorTextTransforms.caretAtEnd(of: memo.content)
                    )
                )
                viewModel.visibility = memo.visibility
            } else {
                let draftText = draft
                editorTextState.apply(
                    MemoEditorTextSnapshot(
                        text: draftText,
                        selectedRange: MemoEditorTextTransforms.caretAtEnd(of: draftText)
                    )
                )
                viewModel.visibility = userState.currentUser?.defaultVisibility ?? .private
            }
            if let memo {
                viewModel.resourceList = memo.resources.filter { !$0.softDeleted }.sorted { $0.createdAt > $1.createdAt }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
                focused = true
            }
        }
        .onChange(of: text) { oldValue, newValue in
            applyAutoListContinuationIfNeeded(oldValue: oldValue, newValue: newValue)
        }
        .task {
            do {
                availableTags = try await actions.loadTags()
            } catch {
                print(error)
            }
        }
        .onDisappear {
            if memo == nil {
                draft = text
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            if memo == nil {
                draft = text
            }
        }
        .toast(isPresenting: $showingErrorToast, alertType: .systemImage("xmark.circle", submitError?.localizedDescription))
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(memo == nil ? NSLocalizedString("input.compose", comment: "Compose") : NSLocalizedString("input.edit", comment: "Edit"))
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Text("input.close")
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task {
                        try await saveMemo()
                    }
                } label: {
                    Label("input.save", systemImage: "paperplane")
                }
                .disabled((text.isEmpty && viewModel.resourceList.isEmpty))
            }
        }
        .fullScreenCover(isPresented: $showingImagePicker, content: {
            ImagePicker { image in
                Task {
                    try await upload(images: [image])
                }
            }
            .edgesIgnoringSafeArea(.all)
        })
#if canImport(VisionKit) && os(iOS) && !targetEnvironment(macCatalyst)
        .fullScreenCover(isPresented: $showingDocumentScanner) {
            DocumentScanner { result in
                Task {
                    await handleDocumentScan(result)
                }
            }
            .edgesIgnoringSafeArea(.all)
        }
#endif
        .interactiveDismissDisabled()
    }

    public var body: some View {
        NavigationStack {
            withJournalingSuggestionsPicker(
                editor()
                .photosPicker(isPresented: $showingPhotoPicker, selection: $viewModel.photos)
                .onChange(of: viewModel.photos) { _, newValue in
                    Task {
                        if !newValue.isEmpty {
                            try await upload(images: newValue)
                            viewModel.photos = []
                        }
                    }
                }
                .fileImporter(
                    isPresented: $showingFilePicker,
                    allowedContentTypes: [.data],
                    allowsMultipleSelection: false
                ) { result in
                    switch result {
                    case .success(let urls):
                        guard let url = urls.first else { return }
                        Task {
                            try await upload(fileURL: url)
                        }
                    case .failure(let error):
                        submitError = error
                        showingErrorToast = true
                    }
                }
            )
        }
    }

    private func upload(images: [PhotosPickerItem]) async throws {
        do {
            for item in images {
                let contentType = item.supportedContentTypes.first
                let imageData = try await item.loadTransferable(type: Data.self)
                guard let imageData = imageData else { continue }

                let fileExtension = contentType?.preferredFilenameExtension
                let filename = fileExtension.map { "\(UUID().uuidString).\($0)" } ?? "\(UUID().uuidString).dat"
                let mimeType = contentType?.preferredMIMEType ?? "application/octet-stream"
                try await viewModel.upload(data: imageData, filename: filename, mimeType: mimeType)
            }
            submitError = nil
        } catch {
            submitError = error
            showingErrorToast = true
        }
    }

    private func upload(images: [UIImage]) async throws {
        do {
            for image in images {
                guard let data = image.jpegData(compressionQuality: 1.0) else { continue }
                try await viewModel.upload(data: data, filename: "\(UUID().uuidString).jpg", mimeType: "image/jpeg")
            }
            submitError = nil
        } catch {
            submitError = error
            showingErrorToast = true
        }
    }

    private func upload(fileURL: URL) async throws {
        do {
            try await viewModel.upload(fileURL: fileURL)
            submitError = nil
        } catch {
            submitError = error
            showingErrorToast = true
        }
    }

#if canImport(VisionKit) && os(iOS) && !targetEnvironment(macCatalyst)
    private func handleDocumentScan(_ result: DocumentScanner.Result) async {
        showingDocumentScanner = false

        switch result {
        case .success(let images):
            do {
                let data = try ScannedDocumentPDFBuilder.makePDFData(from: images)
                try await viewModel.upload(data: data, filename: scannedDocumentFilename(), mimeType: "application/pdf")
                submitError = nil
            } catch {
                submitError = error
                showingErrorToast = true
            }
        case .cancelled:
            break
        case .failure(let error):
            submitError = error
            showingErrorToast = true
        }
    }
#endif

    private var supportsDocumentScanning: Bool {
#if canImport(VisionKit) && os(iOS) && !targetEnvironment(macCatalyst)
        DocumentScanner.isSupported
#else
        false
#endif
    }

    private func scannedDocumentFilename(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "scan-\(formatter.string(from: date)).pdf"
    }

    private func saveMemo() async throws {
        let tags = viewModel.extractCustomTags(from: text)

        do {
            let resourceIds = viewModel.resourceList.map(\.id)
            if let memo = memo {
                try await actions.editMemo(memo.id, text, viewModel.visibility, resourceIds, tags)
            } else {
                try await actions.createMemo(text, viewModel.visibility, resourceIds, tags)
                draft = ""
            }
            editorTextState.apply(MemoEditorTextSnapshot(text: "", selectedRange: nil))
            dismiss()
            submitError = nil
        } catch {
            submitError = error
            showingErrorToast = true
        }
    }

    private var privacyMenu: some View {
      Menu {
        Section("input.visibility") {
        ForEach(availableVisibilities, id: \.self) { visibility in
            Button {
              viewModel.visibility = visibility
            } label: {
              Label(visibility.title, systemImage: visibility.iconName)
            }
          }
        }
      } label: {
        HStack {
          Label(viewModel.visibility.title, systemImage: viewModel.visibility.iconName)
          Image(systemName: "chevron.down")
        }
        .font(.footnote)
        .padding(4)
        .overlay(
          RoundedRectangle(cornerRadius: 8)
            .stroke(.green, lineWidth: 1)
        )
      }
    }

    private var availableVisibilities: [MemoVisibility] {
        accountManager.currentService?.memoVisibilities() ?? [.private]
    }

    private var supportsJournalingSuggestions: Bool {
#if canImport(JournalingSuggestions) && os(iOS) && !targetEnvironment(macCatalyst)
        guard #available(iOS 17.2, *) else {
            return false
        }
        let deviceFamily: MemoEditorDeviceFamily
        switch UIDevice.current.userInterfaceIdiom {
        case .pad:
            deviceFamily = .pad
        case .mac:
            deviceFamily = .mac
        default:
            deviceFamily = .phone
        }
        return MemoEditorFeatureAvailability.supportsJournalingSuggestions(
            operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersion,
            deviceFamily: deviceFamily,
            isIOSAppOnMac: ProcessInfo.processInfo.isiOSAppOnMac
        )
#else
        return false
#endif
    }

    private func insert(tag: Tag?) {
        let tagText = "#\(tag?.name ?? "") "
        insertAtSelection(tagText)
    }

    private func toggleTodoItem() {
        editorTextState.apply(MemoEditorTextTransforms.togglingTodo(in: textSnapshot))
    }

    private func applyAutoListContinuationIfNeeded(oldValue: String, newValue: String) {
        guard !isApplyingAutoContinuation else {
            isApplyingAutoContinuation = false
            return
        }

        guard let snapshot = MemoEditorTextTransforms.continuingList(from: oldValue, to: newValue) else {
            return
        }

        isApplyingAutoContinuation = true
        editorTextState.apply(snapshot)
    }

    private func insertAtSelection(_ insertedText: String) {
        editorTextState.apply(MemoEditorTextTransforms.inserting(insertedText, into: textSnapshot))
    }

    @inline(never)
    private func withJournalingSuggestionsPicker<Content: View>(_ content: Content) -> AnyView {
#if canImport(JournalingSuggestions) && os(iOS) && !targetEnvironment(macCatalyst)
        if #available(iOS 17.2, *), supportsJournalingSuggestions {
            return withNativeJournalingSuggestionsPicker(AnyView(content))
        }
#endif
        return AnyView(content)
    }

#if canImport(JournalingSuggestions) && os(iOS) && !targetEnvironment(macCatalyst)
    @available(iOS 17.2, *)
    @inline(never)
    private func withNativeJournalingSuggestionsPicker(_ content: AnyView) -> AnyView {
        AnyView(
            content
                .journalingSuggestionsPicker(isPresented: $showingJournalingSuggestionsPicker) { suggestion in
                    await insertJournalingSuggestion(suggestion)
                }
        )
    }

    @available(iOS 17.2, *)
    private func insertJournalingSuggestion(_ suggestion: JournalingSuggestion) async {
        await attachJournalingSuggestionAssets(from: suggestion)
        let snippet = await journalingSuggestionSnippet(from: suggestion)
        guard !snippet.isEmpty else { return }
        let content = text.isEmpty ? snippet : "\n\n\(snippet)"
        insertAtSelection(content)
    }

    @available(iOS 17.2, *)
    private func attachJournalingSuggestionAssets(from suggestion: JournalingSuggestion) async {
        let urls = await journalingSuggestionAssetURLs(from: suggestion)
        guard !urls.isEmpty else { return }

        var firstError: Error?
        for url in urls {
            do {
                try await viewModel.upload(fileURL: url)
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        }

        if let firstError {
            submitError = firstError
            showingErrorToast = true
        }
    }

    @available(iOS 17.2, *)
    private func journalingSuggestionAssetURLs(from suggestion: JournalingSuggestion) async -> [URL] {
        var urls: [URL] = []

        let photos = await suggestion.content(forType: JournalingSuggestion.Photo.self)
        for photo in photos where !urls.contains(photo.photo) {
            urls.append(photo.photo)
        }

        let livePhotos = await suggestion.content(forType: JournalingSuggestion.LivePhoto.self)
        for livePhoto in livePhotos {
            if !urls.contains(livePhoto.image) {
                urls.append(livePhoto.image)
            }
        }

        return urls
    }

    @available(iOS 17.2, *)
    private func journalingSuggestionSnippet(from suggestion: JournalingSuggestion) async -> String {
        var lines: [String] = []
        let title = suggestion.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            lines.append(title)
        }

        if #available(iOS 18.0, *) {
            let reflections = await suggestion.content(forType: JournalingSuggestion.Reflection.self)
            let prompts = reflections.map(\.prompt).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            lines.append(contentsOf: prompts.map { "- \($0)" })
        }

        if let date = suggestion.date {
            lines.append("")
            lines.append("_\(formattedSuggestionDateInterval(date))_")
        }

        return lines.joined(separator: "\n")
    }

    private func formattedSuggestionDateInterval(_ interval: DateInterval) -> String {
        let formatter = Date.IntervalFormatStyle(date: .abbreviated, time: .shortened)
        return (interval.start..<interval.end).formatted(formatter)
    }
#endif
}
