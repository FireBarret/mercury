import Foundation
import Network

struct MailHeader {
    let uid: Int?
    let from: String
    let subject: String
    let messageID: String?
    let isUnread: Bool
    let isFlagged: Bool
    let accountEmail: String
}

enum IMAPError: Error, CustomStringConvertible {
    case timeout
    case connectionClosed
    case protocolError(String)
    case serverError(String)

    var description: String {
        switch self {
        case .timeout: return "Connection timed out"
        case .connectionClosed: return "Connection closed"
        case .protocolError(let m): return "Protocol error: \(m)"
        case .serverError(let m): return "Server error: \(m)"
        }
    }
}

/// A minimal IMAP client, built specifically for Gmail, that leans on IDLE
/// (RFC 2177) to get near-instant push notifications for new mail instead of
/// polling. Talks TLS-wrapped IMAP directly via Network.framework so the app
/// stays a single small binary with no third-party dependencies.
final class IMAPClient {
    private let email: String
    private let appPassword: String
    private let host = "imap.gmail.com"
    private let port: UInt16 = 993

    private let networkQueue = DispatchQueue(label: "IMAPClient.network")
    private let sessionQueue = DispatchQueue(label: "IMAPClient.session")

    private var connection: NWConnection?
    private let cond = NSCondition()
    private var buffer = Data()
    private var connectionError: Error?
    private var isClosed = false

    private var tagCounter = 0
    private var knownMessageCount: Int?
    private var isRunning = false
    private var reconnectAttempt = 0
    private var wakeRequested = false
    private var markAllAsReadRequested = false
    private var pendingActions: [PendingAction] = []

    private enum PendingAction {
        case setFlag(uid: Int, flag: String, on: Bool)
        case fetchBody(uid: Int, completion: (String?) -> Void)
    }

    var onNewMail: (([MailHeader]) -> Void)?
    var onUnreadCountChanged: ((Int) -> Void)?
    var onStatusChanged: ((String) -> Void)?
    var onLatestMessagesChanged: (([MailHeader]) -> Void)?

    init(email: String, appPassword: String) {
        self.email = email
        self.appPassword = appPassword.replacingOccurrences(of: " ", with: "")
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        sessionQueue.async { [weak self] in self?.runLoop() }
    }

    func stop() {
        isRunning = false
        cond.lock()
        isClosed = true
        cond.signal()
        cond.unlock()
        connection?.cancel()
        connection = nil
    }

    /// Ask the session to break out of IDLE and refresh right away.
    func checkNow() {
        cond.lock()
        wakeRequested = true
        cond.signal()
        cond.unlock()
    }

    /// Ask the session to mark every message in the mailbox as read.
    func markAllAsRead() {
        cond.lock()
        markAllAsReadRequested = true
        cond.signal()
        cond.unlock()
    }

    /// Sets or clears a single IMAP flag (e.g. "\\Flagged", "\\Seen") on one
    /// message, identified by its stable UID rather than a sequence number
    /// (which can shift as the mailbox changes).
    func setFlag(uid: Int, flag: String, on: Bool) {
        cond.lock()
        pendingActions.append(.setFlag(uid: uid, flag: flag, on: on))
        cond.signal()
        cond.unlock()
    }

    /// Fetches the full raw message (headers + body) for one UID, for
    /// on-demand actions like OTP/link extraction. Not prefetched for every
    /// recent message -- only called when the user actually asks for it.
    /// The completion is always called on the main thread.
    func fetchMessageBody(uid: Int, completion: @escaping (String?) -> Void) {
        cond.lock()
        pendingActions.append(.fetchBody(uid: uid, completion: completion))
        cond.signal()
        cond.unlock()
    }

    // MARK: - Session loop

    private func runLoop() {
        while isRunning {
            do {
                try runSession()
            } catch {
                if !isRunning { return }
                onStatusChanged?("Reconnecting… (\(error))")
            }
            guard isRunning else { return }
            reconnectAttempt += 1
            let delay = min(60.0, pow(2.0, Double(reconnectAttempt)))
            Thread.sleep(forTimeInterval: delay)
        }
    }

    private func runSession() throws {
        resetConnectionState()
        try connectSocket()
        _ = try readLogicalLine(deadline: Date().addingTimeInterval(15))
        try login()
        reconnectAttempt = 0
        onStatusChanged?("Connected")
        knownMessageCount = try selectInbox()
        let unseen = try fetchUnseenCount()
        onUnreadCountChanged?(unseen)
        onLatestMessagesChanged?(try fetchLatestMessages(count: recentListSize(forUnread: unseen)))

        while isRunning {
            try idleCycle()
        }
    }

    private func resetConnectionState() {
        cond.lock()
        buffer.removeAll()
        connectionError = nil
        isClosed = false
        cond.unlock()
        tagCounter = 0
    }

    // MARK: - Socket setup

    private func connectSocket() throws {
        let params = NWParameters.tls
        let conn = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(integerLiteral: port), using: params)
        connection = conn

        let sem = DispatchSemaphore(value: 0)
        var connectError: Error?
        var settled = false

        conn.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                if !settled { settled = true; sem.signal() }
            case .failed(let error):
                if !settled { settled = true; connectError = error; sem.signal() }
                self.fail(with: error)
            case .cancelled:
                if !settled { settled = true; connectError = IMAPError.connectionClosed; sem.signal() }
                self.fail(with: IMAPError.connectionClosed)
            default:
                break
            }
        }
        conn.start(queue: networkQueue)

        if sem.wait(timeout: .now() + 15) == .timedOut {
            conn.cancel()
            throw IMAPError.timeout
        }
        if let connectError = connectError {
            throw connectError
        }
        armReceive()
    }

    private func fail(with error: Error) {
        cond.lock()
        connectionError = error
        isClosed = true
        cond.signal()
        cond.unlock()
    }

    private func armReceive() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            self.cond.lock()
            if let data = data, !data.isEmpty {
                self.buffer.append(data)
            }
            if let error = error {
                self.connectionError = error
            }
            if isComplete {
                self.isClosed = true
            }
            self.cond.signal()
            self.cond.unlock()
            if error == nil && !isComplete {
                self.armReceive()
            }
        }
    }

    // MARK: - Raw I/O

    private func writeLine(_ s: String) throws {
        guard let connection = connection else { throw IMAPError.connectionClosed }
        let sem = DispatchSemaphore(value: 0)
        var sendError: Error?
        connection.send(content: Data((s + "\r\n").utf8), completion: .contentProcessed { error in
            sendError = error
            sem.signal()
        })
        sem.wait()
        if let sendError = sendError { throw sendError }
    }

    private func nextTag() -> String {
        tagCounter += 1
        return "A\(tagCounter)"
    }

    /// Reads one logical IMAP response line, transparently absorbing any
    /// `{n}` literal that appears on it (as Gmail sends for FETCH bodies).
    /// Returns nil if `deadline` passes with no complete line available.
    private func readLogicalLine(deadline: Date?) throws -> String? {
        cond.lock()
        defer { cond.unlock() }
        while true {
            if let line = tryExtractLineLocked() {
                return line
            }
            if let error = connectionError { throw error }
            if isClosed { throw IMAPError.connectionClosed }
            if let deadline = deadline {
                if !cond.wait(until: deadline) {
                    return nil
                }
            } else {
                cond.wait()
            }
        }
    }

    /// Must be called with `cond` already locked.
    private func tryExtractLineLocked() -> String? {
        guard let crlfRange = buffer.range(of: Data([0x0D, 0x0A])) else { return nil }
        let lineData = buffer.subdata(in: buffer.startIndex..<crlfRange.lowerBound)
        let lineString = String(data: lineData, encoding: .utf8) ?? ""

        if let literalLength = literalLength(in: lineString) {
            let literalStart = crlfRange.upperBound
            guard buffer.distance(from: literalStart, to: buffer.endIndex) >= literalLength else {
                return nil // need more bytes for the literal
            }
            let literalEnd = buffer.index(literalStart, offsetBy: literalLength)
            let literalData = buffer.subdata(in: literalStart..<literalEnd)
            let literalString = String(data: literalData, encoding: .utf8) ?? ""

            guard let restCrlfRange = buffer.range(of: Data([0x0D, 0x0A]), in: literalEnd..<buffer.endIndex) else {
                return nil // need the trailing CRLF after the literal
            }
            let restData = buffer.subdata(in: literalEnd..<restCrlfRange.lowerBound)
            let restString = String(data: restData, encoding: .utf8) ?? ""

            buffer.removeSubrange(buffer.startIndex..<restCrlfRange.upperBound)
            return lineString + "\n" + literalString + restString
        } else {
            buffer.removeSubrange(buffer.startIndex..<crlfRange.upperBound)
            return lineString
        }
    }

    private func literalLength(in line: String) -> Int? {
        guard line.hasSuffix("}"), let braceIdx = line.lastIndex(of: "{") else { return nil }
        let numberPart = line[line.index(after: braceIdx)..<line.index(before: line.endIndex)]
        return Int(numberPart)
    }

    /// Reads lines until the tagged completion for `tag` shows up, returning
    /// every line seen along the way (including the tagged one).
    private func readUntilTagged(_ tag: String, deadline: Date = Date().addingTimeInterval(30)) throws -> [String] {
        var lines: [String] = []
        while true {
            guard let line = try readLogicalLine(deadline: deadline) else {
                throw IMAPError.timeout
            }
            lines.append(line)
            if line.hasPrefix("\(tag) ") {
                if line.hasPrefix("\(tag) OK") {
                    return lines
                } else {
                    throw IMAPError.serverError(line)
                }
            }
        }
    }

    // MARK: - Commands

    private func login() throws {
        let tag = nextTag()
        try writeLine("\(tag) LOGIN \(quoted(email)) \(quoted(appPassword))")
        _ = try readUntilTagged(tag)
    }

    private func selectInbox() throws -> Int {
        let tag = nextTag()
        try writeLine("\(tag) SELECT INBOX")
        let lines = try readUntilTagged(tag)
        for line in lines {
            if let count = parseExists(line) {
                return count
            }
        }
        return 0
    }

    private func fetchUnseenCount() throws -> Int {
        let tag = nextTag()
        try writeLine("\(tag) STATUS INBOX (UNSEEN)")
        let lines = try readUntilTagged(tag)
        for line in lines {
            if let range = line.range(of: #"UNSEEN (\d+)"#, options: .regularExpression) {
                let match = line[range]
                if let numRange = match.range(of: #"\d+"#, options: .regularExpression) {
                    return Int(match[numRange]) ?? 0
                }
            }
        }
        return 0
    }

    private func currentMessageCount() throws -> Int {
        let tag = nextTag()
        try writeLine("\(tag) STATUS INBOX (MESSAGES)")
        let lines = try readUntilTagged(tag)
        for line in lines {
            if let range = line.range(of: #"MESSAGES (\d+)"#, options: .regularExpression) {
                let match = line[range]
                if let numRange = match.range(of: #"\d+"#, options: .regularExpression) {
                    return Int(match[numRange]) ?? 0
                }
            }
        }
        return knownMessageCount ?? 0
    }

    private func fetchHeaders(from: Int, to: Int) throws -> [MailHeader] {
        guard from <= to else { return [] }
        let tag = nextTag()
        try writeLine("\(tag) FETCH \(from):\(to) (UID FLAGS BODY.PEEK[HEADER.FIELDS (FROM SUBJECT MESSAGE-ID)])")
        let lines = try readUntilTagged(tag)
        var headers: [MailHeader] = []
        for line in lines where line.contains("FETCH") && line.contains("\n") {
            // Our readLogicalLine joins "<head>\n<literal + trailer>" for lines with literals.
            // UID and FLAGS are requested first, so both land in the part before the literal.
            let parts = line.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let metaPart = String(parts[0])
            let headerBlock = String(parts[1])
            let isUnread = !metaPart.contains("\\Seen")
            let isFlagged = metaPart.contains("\\Flagged")
            let uid = parseUID(metaPart)
            headers.append(parseHeaderBlock(headerBlock, uid: uid, isUnread: isUnread, isFlagged: isFlagged))
        }
        return headers
    }

    private func parseUID(_ metaPart: String) -> Int? {
        guard let range = metaPart.range(of: #"UID (\d+)"#, options: .regularExpression) else { return nil }
        let match = metaPart[range]
        guard let numRange = match.range(of: #"\d+"#, options: .regularExpression) else { return nil }
        return Int(match[numRange])
    }

    private func parseHeaderBlock(_ block: String, uid: Int?, isUnread: Bool, isFlagged: Bool) -> MailHeader {
        var from = ""
        var subject = ""
        var messageID: String?
        // Unfold header lines (continuation lines start with whitespace).
        let rawLines = block.components(separatedBy: "\r\n")
        var unfolded: [String] = []
        for line in rawLines {
            if line.first == " " || line.first == "\t", !unfolded.isEmpty {
                unfolded[unfolded.count - 1] += " " + line.trimmingCharacters(in: .whitespaces)
            } else if !line.isEmpty {
                unfolded.append(line)
            }
        }
        for line in unfolded {
            if line.lowercased().hasPrefix("from:") {
                from = decodeMIMEHeader(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
            } else if line.lowercased().hasPrefix("subject:") {
                subject = decodeMIMEHeader(String(line.dropFirst(8)).trimmingCharacters(in: .whitespaces))
            } else if line.lowercased().hasPrefix("message-id:") {
                messageID = String(line.dropFirst("message-id:".count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return MailHeader(
            uid: uid,
            from: prettifyFrom(from),
            subject: subject,
            messageID: messageID,
            isUnread: isUnread,
            isFlagged: isFlagged,
            accountEmail: email
        )
    }

    private func prettifyFrom(_ raw: String) -> String {
        // "Display Name" <address@example.com>  ->  Display Name
        if let ltIdx = raw.firstIndex(of: "<") {
            let namePart = raw[raw.startIndex..<ltIdx].trimmingCharacters(in: .whitespaces)
            let unquoted = namePart.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            if !unquoted.isEmpty {
                return unquoted
            }
            let addr = raw[ltIdx...].trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
            return addr
        }
        return raw
    }

    private func quoted(_ s: String) -> String {
        let escaped = s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private func parseExists(_ line: String) -> Int? {
        guard let range = line.range(of: #"^\* (\d+) EXISTS"#, options: .regularExpression) else { return nil }
        let match = line[range]
        guard let numRange = match.range(of: #"\d+"#, options: .regularExpression) else { return nil }
        return Int(match[numRange])
    }

    // MARK: - IDLE cycle

    private func idleCycle() throws {
        let tag = nextTag()
        try writeLine("\(tag) IDLE")
        guard let cont = try readLogicalLine(deadline: Date().addingTimeInterval(15)), cont.hasPrefix("+") else {
            throw IMAPError.protocolError("no IDLE continuation")
        }

        // Gmail drops IDLE connections after ~29 minutes of inactivity; refresh well before that.
        let idleDeadline = Date().addingTimeInterval(25 * 60)
        var sawNewCount: Int?
        var shouldMarkAllRead = false

        idleWait: while true {
            // Poll in short slices rather than blocking for the full deadline in
            // one shot, so a checkNow()/markAllAsRead() wake request is noticed
            // within ~1s instead of only incidentally when other server traffic
            // arrives.
            let pollDeadline = min(idleDeadline, Date().addingTimeInterval(1))
            if let line = try readLogicalLine(deadline: pollDeadline) {
                // Any untagged push during IDLE -- new mail (EXISTS), a message
                // being marked read elsewhere (FETCH FLAGS), a deletion
                // (EXPUNGE), etc. -- means our cached state may be stale, so
                // refresh rather than only reacting to EXISTS changes.
                // Otherwise the unread badge stays stuck after mail is read
                // outside this app (Gmail web, phone, or Mercury's own
                // "open in Mail.app" links).
                if let n = parseExists(line) {
                    sawNewCount = n
                }
                break idleWait
            }

            cond.lock()
            let woken = wakeRequested
            let markRequested = markAllAsReadRequested
            let hasActions = !pendingActions.isEmpty
            if woken { wakeRequested = false }
            if markRequested { markAllAsReadRequested = false }
            cond.unlock()
            if markRequested { shouldMarkAllRead = true }
            if woken || markRequested || hasActions || Date() >= idleDeadline {
                break idleWait
            }
        }

        try writeLine("DONE")
        _ = try readUntilTagged(tag)

        if shouldMarkAllRead {
            try markAllMessagesRead()
        }

        cond.lock()
        let actionsToProcess = pendingActions
        pendingActions.removeAll()
        cond.unlock()
        for action in actionsToProcess {
            processPendingAction(action)
        }

        let known = knownMessageCount ?? 0
        let latestCount = try sawNewCount ?? currentMessageCount()

        if latestCount > known {
            let headers = try fetchHeaders(from: known + 1, to: latestCount)
            knownMessageCount = latestCount
            if !headers.isEmpty {
                onNewMail?(headers)
            }
        } else {
            knownMessageCount = latestCount
        }

        if shouldMarkAllRead {
            // The UI already optimistically cleared; checking again this
            // instant risks racing Gmail's backend and reading back stale
            // (still-unseen) state right after. Give it a moment to settle
            // and confirm once, instead of refreshing immediately here.
            scheduleDelayedRecheck(after: 12)
        } else {
            let unseen = try fetchUnseenCount()
            onUnreadCountChanged?(unseen)
            onLatestMessagesChanged?(try fetchLatestMessages(count: recentListSize(forUnread: unseen)))
        }
    }

    private func scheduleDelayedRecheck(after seconds: TimeInterval) {
        // Deliberately not sessionQueue -- that thread is permanently busy
        // running the IDLE loop, so anything scheduled on it would never
        // get a turn. checkNow() itself is just a lock/signal, safe from
        // any thread.
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { [weak self] in
            self?.checkNow()
        }
    }

    /// Processes one queued per-message action. Deliberately swallows its
    /// own errors (logged, not thrown) -- a failed flag-set or body fetch
    /// shouldn't tear down the whole IDLE session the way a real protocol
    /// error should.
    private func processPendingAction(_ action: PendingAction) {
        switch action {
        case .setFlag(let uid, let flag, let on):
            do {
                let tag = nextTag()
                let sign = on ? "+FLAGS" : "-FLAGS"
                try writeLine("\(tag) UID STORE \(uid) \(sign) (\(flag))")
                _ = try readUntilTagged(tag)
            } catch {
                NSLog("IMAPClient: setFlag(uid: \(uid), flag: \(flag)) failed: \(error)")
            }
        case .fetchBody(let uid, let completion):
            var result: String?
            do {
                result = try fetchRawBody(uid: uid)
            } catch {
                NSLog("IMAPClient: fetchMessageBody(uid: \(uid)) failed: \(error)")
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Fetches the complete raw message (headers + body) for one UID. Not
    /// surgical about MIME parts -- for the on-demand OTP/link-scan use
    /// case this is simplest and correct for typical small notification/
    /// OTP emails, at the cost of being slow for anything with large
    /// attachments (BODY.PEEK[] pulls the whole thing, attachments
    /// included).
    private func fetchRawBody(uid: Int) throws -> String? {
        let tag = nextTag()
        try writeLine("\(tag) UID FETCH \(uid) (BODY.PEEK[])")
        let lines = try readUntilTagged(tag)
        for line in lines where line.contains("FETCH") && line.contains("\n") {
            let parts = line.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            return String(parts[1])
        }
        return nil
    }

    private func markAllMessagesRead() throws {
        guard (knownMessageCount ?? 0) > 0 else { return }
        let tag = nextTag()
        try writeLine("\(tag) STORE 1:* +FLAGS.SILENT (\\Seen)")
        _ = try readUntilTagged(tag)
    }

    /// Shows at least `Settings.recentListMinCount` recent messages, but
    /// grows up to `Settings.recentListMaxCount` when there's more unread
    /// mail than that, so most unread mail is visible at a glance without
    /// needing to open Gmail.
    private func recentListSize(forUnread unread: Int) -> Int {
        let minCount = max(0, Settings.recentListMinCount)
        let maxCount = max(minCount, Settings.recentListMaxCount)
        return min(maxCount, max(minCount, unread))
    }

    /// The `count` most recent messages in the mailbox, newest first,
    /// regardless of read/unread state.
    private func fetchLatestMessages(count: Int) throws -> [MailHeader] {
        let total = knownMessageCount ?? 0
        guard total > 0 else { return [] }
        let from = max(1, total - count + 1)
        return try Array(fetchHeaders(from: from, to: total).reversed())
    }
}
