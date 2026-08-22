import AppKit

enum ClipKind: String, Codable, CaseIterable {
    case text, rtf, html, image, fileURL, color

    var badge: String {
        switch self {
        case .text: return "TXT"
        case .rtf: return "RTF"
        case .html: return "HTML"
        case .image: return "IMG"
        case .fileURL: return "FILE"
        case .color: return "COLOR"
        }
    }

    var symbolName: String {
        switch self {
        case .text: return "text.alignleft"
        case .rtf: return "doc.richtext"
        case .html: return "chevron.left.forwardslash.chevron.right"
        case .image: return "photo"
        case .fileURL: return "folder"
        case .color: return "paintpalette"
        }
    }
}

struct Clip: Identifiable, Codable, Hashable {
    let id: UUID
    let kind: ClipKind
    var text: String
    var data: Data?
    var fileURLs: [String]?
    var capturedAt: Date
    var pinned: Bool
    var name: String?

    init(
        id: UUID = UUID(),
        kind: ClipKind,
        text: String,
        data: Data? = nil,
        fileURLs: [String]? = nil,
        capturedAt: Date = Date(),
        pinned: Bool = false,
        name: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.data = data
        self.fileURLs = fileURLs
        self.capturedAt = capturedAt
        self.pinned = pinned
        self.name = name
    }

    static func == (lhs: Clip, rhs: Clip) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// Stable signature of the underlying content (independent of id/timestamp) used to dedupe captures.
    var contentSignature: String {
        switch kind {
        case .text, .rtf, .html:
            return "\(kind.rawValue):\(text.hashValue)"
        case .image:
            return "image:\((data ?? Data()).hashValue)"
        case .fileURL:
            return "files:" + (fileURLs ?? []).joined(separator: "|")
        case .color:
            return "color:\((data ?? Data()).hashValue)"
        }
    }

    var displayTitle: String {
        if let name, !name.isEmpty { return name }
        return kind.badge
    }
}
