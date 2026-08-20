import Foundation

/// Best-effort parsing of a raw fetched message (headers + body) for the
/// on-demand "Copy Code" / "Check for Links" quick actions. Deliberately
/// NOT a full RFC 2045-2049 MIME parser -- just enough boundary/part
/// splitting and Content-Transfer-Encoding decoding to handle typical
/// simple notification/OTP/marketing emails. Unusual structures (deeply
/// nested multipart, uncommon encodings) may not be handled.
enum MessageBodyParser {
    private struct MIMEPart {
        let contentType: String
        let encoding: String
        let body: String
    }

    /// The best available human-readable text for this message -- prefers
    /// a text/plain part, falls back to text/html with tags stripped, and
    /// falls back to the raw message itself if no MIME structure is found.
    static func extractPlainText(fromRawMessage raw: String) -> String {
        let parts = mimeParts(fromRawMessage: raw)
        guard !parts.isEmpty else { return raw }

        if let plain = parts.first(where: { $0.contentType.hasPrefix("text/plain") }) {
            return decode(part: plain)
        }
        if let html = parts.first(where: { $0.contentType.hasPrefix("text/html") }) {
            return stripHTMLTags(decode(part: html))
        }
        return decode(part: parts[0])
    }

    /// All http(s) links found in the message, from both `href="..."`
    /// attributes (HTML part) and bare URLs in plain text, deduplicated and
    /// capped so the resulting picker menu stays usable.
    static func extractLinks(fromRawMessage raw: String) -> [String] {
        let parts = mimeParts(fromRawMessage: raw)
        let decodedParts = parts.isEmpty ? [raw] : parts.map { decode(part: $0) }

        var seen = Set<String>()
        var links: [String] = []

        func add(_ url: String) {
            let trimmed = url.trimmingCharacters(in: CharacterSet(charactersIn: "\"'>) "))
            guard trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") else { return }
            guard !seen.contains(trimmed) else { return }
            seen.insert(trimmed)
            links.append(trimmed)
        }

        for text in decodedParts {
            for match in matches(of: #"href\s*=\s*["']([^"']+)["']"#, in: text, group: 1) {
                add(match)
            }
            for match in matches(of: #"https?://[^\s"'<>\)]+"#, in: text, group: 0) {
                add(match)
            }
            if links.count >= 15 { break }
        }
        return Array(links.prefix(15))
    }

    /// Heuristic one-time-passcode detection: prefers a short digit (or
    /// digit/letter) run near a contextual keyword like "code" or "OTP";
    /// falls back to the first standalone 4-8 digit run otherwise.
    static func findOTPCode(inText text: String) -> String? {
        let keywordPattern = #"(?i)(?:code|otp|passcode|verification)\D{0,20}\b([A-Z0-9]{4,8})\b"#
        if let match = matches(of: keywordPattern, in: text, group: 1).first {
            return match
        }
        let boundedPattern = #"(?<![\d/.-])\b(\d{4,8})\b(?![\d/.-])"#
        if let match = matches(of: boundedPattern, in: text, group: 1).first {
            return match
        }
        return nil
    }

    // MARK: - MIME part splitting

    private static func mimeParts(fromRawMessage raw: String) -> [MIMEPart] {
        guard let headerEnd = raw.range(of: "\r\n\r\n") ?? raw.range(of: "\n\n") else { return [] }
        let topHeaders = String(raw[raw.startIndex..<headerEnd.lowerBound])
        let rest = String(raw[headerEnd.upperBound...])

        guard let boundary = boundaryValue(fromHeaders: topHeaders) else {
            // Not multipart -- treat the whole body as a single part, using
            // whatever top-level Content-Type/Transfer-Encoding it declared.
            let contentType = headerValue("content-type", in: topHeaders)?.lowercased() ?? "text/plain"
            let encoding = headerValue("content-transfer-encoding", in: topHeaders)?.lowercased() ?? "7bit"
            return [MIMEPart(contentType: contentType, encoding: encoding, body: rest)]
        }

        let delimiter = "--" + boundary
        let rawParts = rest.components(separatedBy: delimiter)
        var parts: [MIMEPart] = []
        for rawPart in rawParts {
            let trimmed = rawPart.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed != "--" else { continue }
            guard let partHeaderEnd = trimmed.range(of: "\r\n\r\n") ?? trimmed.range(of: "\n\n") else { continue }
            let partHeaders = String(trimmed[trimmed.startIndex..<partHeaderEnd.lowerBound])
            let partBody = String(trimmed[partHeaderEnd.upperBound...])
            let contentType = headerValue("content-type", in: partHeaders)?.lowercased() ?? "text/plain"
            let encoding = headerValue("content-transfer-encoding", in: partHeaders)?.lowercased() ?? "7bit"
            // Only recurse one level deep (nested multipart/related etc. is
            // rare for the kinds of emails this feature targets); otherwise
            // keep the part as-is.
            if contentType.hasPrefix("multipart/"), let nestedBoundary = boundaryValue(fromHeaders: partHeaders) {
                let nestedDelimiter = "--" + nestedBoundary
                for nestedRaw in partBody.components(separatedBy: nestedDelimiter) {
                    let nestedTrimmed = nestedRaw.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !nestedTrimmed.isEmpty, nestedTrimmed != "--" else { continue }
                    guard let nestedHeaderEnd = nestedTrimmed.range(of: "\r\n\r\n") ?? nestedTrimmed.range(of: "\n\n") else { continue }
                    let nestedHeaders = String(nestedTrimmed[nestedTrimmed.startIndex..<nestedHeaderEnd.lowerBound])
                    let nestedBody = String(nestedTrimmed[nestedHeaderEnd.upperBound...])
                    parts.append(MIMEPart(
                        contentType: headerValue("content-type", in: nestedHeaders)?.lowercased() ?? "text/plain",
                        encoding: headerValue("content-transfer-encoding", in: nestedHeaders)?.lowercased() ?? "7bit",
                        body: nestedBody
                    ))
                }
            } else {
                parts.append(MIMEPart(contentType: contentType, encoding: encoding, body: partBody))
            }
        }
        return parts
    }

    private static func boundaryValue(fromHeaders headers: String) -> String? {
        guard let contentType = headerValue("content-type", in: headers) else { return nil }
        // Quoted form first (the common case) -- captures everything between
        // the quotes as-is, including any "=" the boundary itself contains
        // (real-world boundaries frequently do, e.g. "===============123==").
        if let quoted = matches(of: #"boundary\s*=\s*"([^"]*)""#, in: contentType, group: 1).first {
            return quoted
        }
        // Unquoted fallback.
        if let bare = matches(of: #"boundary\s*=\s*([^;\s]+)"#, in: contentType, group: 1).first {
            return bare
        }
        return nil
    }

    /// Finds a header's value (unfolding continuation lines), case-insensitive.
    private static func headerValue(_ name: String, in headerBlock: String) -> String? {
        let lines = headerBlock.components(separatedBy: "\r\n").flatMap { $0.components(separatedBy: "\n") }
        var unfolded: [String] = []
        for line in lines {
            if line.first == " " || line.first == "\t", !unfolded.isEmpty {
                unfolded[unfolded.count - 1] += " " + line.trimmingCharacters(in: .whitespaces)
            } else if !line.isEmpty {
                unfolded.append(line)
            }
        }
        let prefix = name.lowercased() + ":"
        for line in unfolded where line.lowercased().hasPrefix(prefix) {
            return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    // MARK: - Decoding

    private static func decode(part: MIMEPart) -> String {
        switch part.encoding {
        case "base64":
            let cleaned = part.body.filter { !$0.isWhitespace }
            if let data = Data(base64Encoded: cleaned), let text = String(data: data, encoding: .utf8) {
                return text
            }
            return part.body
        case "quoted-printable":
            return decodeQuotedPrintable(part.body)
        default:
            return part.body
        }
    }

    private static func decodeQuotedPrintable(_ text: String) -> String {
        // Soft line breaks: a line ending in "=" means the newline itself
        // isn't part of the content -- join with the next line first.
        let joined = text
            .replacingOccurrences(of: "=\r\n", with: "")
            .replacingOccurrences(of: "=\n", with: "")

        var bytes: [UInt8] = []
        let chars = Array(joined.utf8)
        var i = 0
        while i < chars.count {
            if chars[i] == UInt8(ascii: "="), i + 2 < chars.count,
               let hi = Character(UnicodeScalar(chars[i + 1])).hexDigitValue,
               let lo = Character(UnicodeScalar(chars[i + 2])).hexDigitValue {
                bytes.append(UInt8(hi * 16 + lo))
                i += 3
            } else {
                bytes.append(chars[i])
                i += 1
            }
        }
        return String(bytes: bytes, encoding: .utf8) ?? joined
    }

    private static func stripHTMLTags(_ html: String) -> String {
        html.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func matches(of pattern: String, in text: String, group: Int) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = text as NSString
        let results = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        return results.compactMap { result in
            guard group < result.numberOfRanges else { return nil }
            let range = result.range(at: group)
            guard range.location != NSNotFound else { return nil }
            return nsText.substring(with: range)
        }
    }
}
