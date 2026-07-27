import Foundation

/// Decodes RFC 2047 encoded-words (e.g. "=?UTF-8?B?....?=") that Gmail uses
/// in From/Subject headers whenever they contain non-ASCII characters.
func decodeMIMEHeader(_ raw: String) -> String {
    guard raw.contains("=?") else { return raw }

    var result = ""
    var remainder = Substring(raw)

    while let start = remainder.range(of: "=?") {
        result += remainder[remainder.startIndex..<start.lowerBound]
        let afterStart = remainder[start.upperBound...]

        guard let q1 = afterStart.firstIndex(of: "?"),
              let q2 = afterStart[afterStart.index(after: q1)...].firstIndex(of: "?"),
              let end = afterStart[afterStart.index(after: q2)...].range(of: "?=") else {
            result += remainder[start.lowerBound...]
            remainder = Substring("")
            break
        }

        let charset = String(afterStart[afterStart.startIndex..<q1])
        let encoding = String(afterStart[afterStart.index(after: q1)..<q2])
        let payload = String(afterStart[afterStart.index(after: q2)..<end.lowerBound])

        if let decoded = decodeEncodedWord(charset: charset, encoding: encoding, payload: payload) {
            result += decoded
        } else {
            result += "=?\(charset)?\(encoding)?\(payload)?="
        }

        remainder = afterStart[end.upperBound...]
        // RFC 2047 says adjacent encoded-words separated only by whitespace should
        // have that whitespace collapsed; skip a single separating space/newline.
        if remainder.first == " " {
            let lookahead = remainder.dropFirst()
            if lookahead.hasPrefix("=?") {
                remainder = lookahead
            }
        }
    }
    result += remainder
    return result
}

private func decodeEncodedWord(charset: String, encoding: String, payload: String) -> String? {
    let stringEncoding: String.Encoding = charset.uppercased().contains("UTF-8") ? .utf8 : .isoLatin1

    switch encoding.uppercased() {
    case "B":
        guard let data = Data(base64Encoded: payload) else { return nil }
        return String(data: data, encoding: stringEncoding)
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
        return String(bytes: bytes, encoding: stringEncoding)
    default:
        return nil
    }
}
