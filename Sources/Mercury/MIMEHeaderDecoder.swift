import Foundation

/// Decodes RFC 2047 encoded-words (e.g. "=?UTF-8?B?....?=") that Gmail uses
/// in From/Subject headers whenever they contain non-ASCII characters.
///
/// Adjacent encoded-words (whitespace-only between them) are merged at the
/// *byte* level before decoding: senders split long non-ASCII text across
/// several words, often in the middle of a multi-byte character, so each
/// word alone is invalid UTF-8 and only decodes once re-joined.
func decodeMIMEHeader(_ raw: String) -> String {
    guard raw.contains("=?") else { return raw }

    var result = ""
    var run: (charset: String, bytes: [UInt8])?
    var pendingSpace = ""

    func flushRun() {
        if let r = run {
            result += decodeBytes(r.bytes, charset: r.charset)
            run = nil
        }
    }

    var remainder = Substring(raw)
    while let start = remainder.range(of: "=?") {
        let before = remainder[remainder.startIndex..<start.lowerBound]
        let afterStart = remainder[start.upperBound...]

        guard let q1 = afterStart.firstIndex(of: "?"),
              let q2 = afterStart[afterStart.index(after: q1)...].firstIndex(of: "?"),
              let end = afterStart[afterStart.index(after: q2)...].range(of: "?=") else {
            break
        }

        let charset = String(afterStart[afterStart.startIndex..<q1])
        let encoding = String(afterStart[afterStart.index(after: q1)..<q2])
        let payload = String(afterStart[afterStart.index(after: q2)..<end.lowerBound])

        guard let bytes = encodedWordBytes(encoding: encoding, payload: payload) else {
            // Not decodable: emit it verbatim as plain text.
            flushRun()
            result += pendingSpace + before + "=?\(charset)?\(encoding)?\(payload)?="
            pendingSpace = ""
            remainder = afterStart[end.upperBound...]
            continue
        }

        if run != nil, before.allSatisfy({ $0.isWhitespace }), run?.charset.uppercased() == charset.uppercased() {
            run?.bytes += bytes
        } else {
            flushRun()
            result += pendingSpace + before
            run = (charset, bytes)
        }
        pendingSpace = ""
        remainder = afterStart[end.upperBound...]
    }

    // Whitespace directly after a word that's followed by plain text is real.
    flushRun()
    result += pendingSpace + remainder
    return result
}

private func encodedWordBytes(encoding: String, payload: String) -> [UInt8]? {
    switch encoding.uppercased() {
    case "B":
        guard let data = Data(base64Encoded: payload) else { return nil }
        return [UInt8](data)
    case "Q":
        var bytes: [UInt8] = []
        let chars = Array(payload)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "_" {
                bytes.append(0x20)
                i += 1
            } else if c == "=", i + 2 < chars.count,
                      let hi = chars[i + 1].hexDigitValue, let lo = chars[i + 2].hexDigitValue {
                bytes.append(UInt8(hi * 16 + lo))
                i += 3
            } else {
                bytes.append(contentsOf: Array(String(c).utf8))
                i += 1
            }
        }
        return bytes
    default:
        return nil
    }
}

private func decodeBytes(_ bytes: [UInt8], charset: String) -> String {
    let encoding = foundationEncoding(forCharset: charset)
    return String(bytes: bytes, encoding: encoding)
        ?? String(bytes: bytes, encoding: .utf8)
        ?? String(decoding: bytes, as: UTF8.self)
}

/// Maps a MIME charset name (as seen in RFC 2047 encoded-words) to the
/// matching Foundation encoding. Beyond UTF-8/Latin-1, this specifically
/// covers the charsets Japanese mail actually uses -- ISO-2022-JP is the
/// charset mandated for Japanese email by RFC 1468 and what most Japanese
/// senders' Subject/From headers are encoded with, not UTF-8.
private func foundationEncoding(forCharset charset: String) -> String.Encoding {
    switch charset.uppercased() {
    case "UTF-8", "UTF8":
        return .utf8
    case "ISO-2022-JP":
        return .iso2022JP
    case "SHIFT_JIS", "SHIFT-JIS", "SJIS", "CP932", "WINDOWS-31J", "MS932":
        return .shiftJIS
    case "EUC-JP", "EUCJP":
        return .japaneseEUC
    case "ISO-8859-1", "LATIN1", "LATIN-1":
        return .isoLatin1
    case "WINDOWS-1252", "CP1252":
        return .windowsCP1252
    case "US-ASCII", "ASCII":
        return .ascii
    default:
        return .utf8
    }
}
