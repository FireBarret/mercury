import AppKit

/// Opens a specific message in Mail.app via its Message-ID, using the same
/// `message://` URL scheme Mail.app's own "Copy Link" feature produces.
/// Requires Mail.app to have already synced the message locally — if it's
/// not running, this launches it, but the message may not resolve until
/// Mail.app finishes syncing.
enum MailAppOpener {
    static func openMessage(withMessageID messageID: String) {
        let trimmed = messageID.trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
        guard !trimmed.isEmpty,
              let encoded = "<\(trimmed)>".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "message://\(encoded)") else {
            NSWorkspace.shared.open(URL(string: "https://mail.google.com")!)
            return
        }
        NSWorkspace.shared.open(url)
    }
}
