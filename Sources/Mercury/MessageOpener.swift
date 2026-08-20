import AppKit

/// Routes "open this message" clicks (from the recent-messages menu or a
/// notification tap) to whichever app Settings.openMailAction points at.
enum MessageOpener {
    /// Routes to whichever app Settings.openMailAction points at -- used
    /// for notification taps, where there's no explicit per-app choice.
    static func open(messageID: String?) {
        switch Settings.openMailAction {
        case .mailApp:
            openInMailApp(messageID: messageID)
        case .gmailBrowser:
            openInGmailBrowser(messageID: messageID)
        }
    }

    static func openInMailApp(messageID: String?) {
        if let messageID = messageID {
            MailAppOpener.openMessage(withMessageID: messageID)
        } else {
            openGmailInbox()
        }
    }

    static func openInGmailBrowser(messageID: String?) {
        guard let messageID = messageID else {
            openGmailInbox()
            return
        }
        let trimmed = messageID.trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://mail.google.com/mail/u/0/#search/rfc822msgid:\(encoded)") else {
            openGmailInbox()
            return
        }
        NSWorkspace.shared.open(url)
    }

    private static func openGmailInbox() {
        if let url = URL(string: "https://mail.google.com") {
            NSWorkspace.shared.open(url)
        }
    }
}
