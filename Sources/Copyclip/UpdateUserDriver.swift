import AppKit
import Sparkle

/// Shows Sparkle's update steps in Copyclip's glass window instead of Sparkle's standard windows.
final class UpdateUserDriver: NSObject, SPUUserDriver {
    /// Called with the version found by a scheduled check, and with nil once that update is handled.
    var onScheduledUpdateChange: ((String?) -> Void)?
    private lazy var windowController = UpdateWindowController()
    /// An update found in the background, waiting for the user to open it from the menu.
    private var pendingUpdate: (item: SUAppcastItem, state: SPUUserUpdateState, reply: (SPUUserUpdateChoice) -> Void)?
    private var expectedLength: UInt64 = 0
    private var receivedLength: UInt64 = 0

    func showPendingUpdate() {
        guard let pendingUpdate else { return }
        presentUpdate(pendingUpdate.item, state: pendingUpdate.state, reply: pendingUpdate.reply)
    }

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        let answer = once { (automatic: Bool) in
            reply(SUUpdatePermissionResponse(automaticUpdateChecks: automatic, sendSystemProfile: false))
        }
        windowController.show(
            title: "Check for updates automatically?",
            message: "Copyclip can look for new versions on GitHub once a day. Nothing from your clipboard is sent.",
            actions: [
                .init(title: "Don't Check", isCancel: true) { [weak self] in
                    self?.windowController.dismiss()
                    answer(false)
                },
                .init(title: "Check Automatically", isPrimary: true) { [weak self] in
                    self?.windowController.dismiss()
                    answer(true)
                }
            ],
            onClose: { answer(false) })
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        windowController.show(title: "Checking for updates…", message: "Looking for a newer version of Copyclip.",
                              body: .progress(nil, ""),
                              actions: [.init(title: "Cancel", isCancel: true) { [weak self] in
                                  self?.windowController.dismiss()
                                  cancellation()
                              }],
                              onClose: cancellation)
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState,
                         reply: @escaping (SPUUserUpdateChoice) -> Void) {
        if state.userInitiated || windowController.isVisible {
            presentUpdate(appcastItem, state: state, reply: reply)
        } else {
            // Don't interrupt: offer it in the menu bar until the user is ready.
            pendingUpdate = (appcastItem, state, reply)
            onScheduledUpdateChange?(appcastItem.displayVersionString)
        }
    }

    private func presentUpdate(_ item: SUAppcastItem, state: SPUUserUpdateState,
                               reply: @escaping (SPUUserUpdateChoice) -> Void) {
        let answer = once { [weak self] (choice: SPUUserUpdateChoice) in
            self?.pendingUpdate = nil
            if choice != .install { self?.windowController.dismiss() }
            reply(choice)
        }
        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        var message = "You have version \(current)."
        if state.stage == .installing { message += " The update is ready to install." }
        let notes = item.itemDescription?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        var actions: [UpdateWindowController.Action] = [
            .init(title: "Skip This Version", alignsLeft: true) { answer(.skip) },
            .init(title: "Remind Me Later", isCancel: true) { answer(.dismiss) }
        ]
        if item.isInformationOnlyUpdate {
            actions.append(.init(title: "Learn More", isPrimary: true) {
                if let url = item.infoURL { NSWorkspace.shared.open(url) }
                answer(.dismiss)
            })
        } else {
            let title = state.stage == .installing ? "Install and Relaunch" : "Install Update"
            actions.append(.init(title: title, isPrimary: true) { answer(.install) })
        }
        windowController.show(title: "Copyclip \(item.displayVersionString) is available", message: message,
                              body: notes.isEmpty ? .none : .notes(notes), actions: actions,
                              onClose: { answer(.dismiss) })
    }

    // Release notes are embedded in the appcast, so there is nothing to download separately.
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}

    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        showNotice(title: error.localizedDescription,
                   message: (error as NSError).localizedRecoverySuggestion ?? "", acknowledgement: acknowledgement)
    }

    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        showNotice(title: "Copyclip couldn't be updated", message: error.localizedDescription,
                   acknowledgement: acknowledgement)
    }

    private func showNotice(title: String, message: String, acknowledgement: @escaping () -> Void) {
        let acknowledge = once(acknowledgement)
        windowController.show(title: title, message: message,
                              actions: [.init(title: "OK", isPrimary: true) { [weak self] in
                                  self?.windowController.dismiss()
                                  acknowledge()
                              }],
                              onClose: acknowledge)
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        expectedLength = 0
        receivedLength = 0
        windowController.show(title: "Downloading update…", message: "Copyclip keeps working while the update downloads.",
                              body: .progress(nil, "Starting download…"),
                              actions: [.init(title: "Cancel", isCancel: true) { [weak self] in
                                  self?.windowController.dismiss()
                                  cancellation()
                              }],
                              onClose: cancellation)
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        expectedLength = expectedContentLength
        receivedLength = 0
        updateDownloadProgress()
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        receivedLength += length
        updateDownloadProgress()
    }

    private func updateDownloadProgress() {
        let received = ByteCountFormatter.string(fromByteCount: Int64(receivedLength), countStyle: .file)
        guard expectedLength > 0 else {
            windowController.updateProgress(nil, label: "\(received) downloaded")
            return
        }
        let expected = ByteCountFormatter.string(fromByteCount: Int64(expectedLength), countStyle: .file)
        windowController.updateProgress(Double(receivedLength) / Double(expectedLength), label: "\(received) of \(expected)")
    }

    func showDownloadDidStartExtractingUpdate() {
        windowController.show(title: "Preparing update…", message: "Checking and unpacking the new version.",
                              body: .progress(nil, ""), actions: [])
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        windowController.updateProgress(progress, label: "")
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        let answer = once { [weak self] (choice: SPUUserUpdateChoice) in
            if choice != .install { self?.windowController.dismiss() }
            reply(choice)
        }
        windowController.show(title: "Ready to install",
                              message: "Copyclip will quit and reopen to finish updating. Your clips are kept.",
                              actions: [.init(title: "Later", isCancel: true) { answer(.dismiss) },
                                        .init(title: "Install and Relaunch", isPrimary: true) { answer(.install) }],
                              onClose: { answer(.dismiss) })
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool,
                              retryTerminatingApplication: @escaping () -> Void) {
        windowController.show(title: "Installing update…", message: "Copyclip will reopen in a moment.",
                              body: .progress(nil, ""), actions: [])
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        windowController.dismiss()
        acknowledgement()
    }

    func showUpdateInFocus() {
        if windowController.isVisible {
            windowController.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            showPendingUpdate()
        }
    }

    func dismissUpdateInstallation() {
        pendingUpdate = nil
        windowController.dismiss()
        onScheduledUpdateChange?(nil)
    }

    /// Wraps a reply so buttons and closing the window can't send it twice.
    private func once<T>(_ body: @escaping (T) -> Void) -> (T) -> Void {
        var done = false
        return { value in
            guard !done else { return }
            done = true
            body(value)
        }
    }

    private func once(_ body: @escaping () -> Void) -> () -> Void {
        var done = false
        return {
            guard !done else { return }
            done = true
            body()
        }
    }
}
