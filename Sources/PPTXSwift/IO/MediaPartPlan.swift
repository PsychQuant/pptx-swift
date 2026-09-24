import Foundation
import ImageIO
import UniformTypeIdentifiers

/// How `PptxWriter` lays out `Presentation.images` as `ppt/media/` parts
/// (PsychQuant/pptx-swift#1).
///
/// A `MediaFile.fileName` is model data — it may come from a caller, an MCP
/// argument or a read package — so it is never used as a path directly. Each
/// media file is written under a part name that is:
///
/// - **safe**: ASCII letters, digits, `.`, `_` and `-` only, not starting or
///   ending with `.`, so it needs no percent-encoding in a relationship
///   target and cannot leave `ppt/media/`;
/// - **unique case-insensitively**, as OPC part-name equivalence requires;
/// - **not typed by a structural `Default`**: an `xml` or `rels` extension
///   would inherit the package's `xml` / `rels` content types.
///
/// A name that already satisfies all three is kept unchanged, so a package
/// read from PowerPoint (`image1.png`, …) round-trips with its names intact.
/// Any other name is replaced by `imageN.<ext>`.
///
/// Only the first `MediaFile` for a given `fileName` is written, matching
/// `Presentation.mediaFile(for:)`, which resolves a picture to the first
/// entry with that name.
struct MediaPartPlan {
    struct Part {
        /// File name under `ppt/media/`.
        let name: String
        let data: Data
        let contentType: String
        /// Whether `contentType` is the one registered for the part's
        /// extension (a `Default` entry covers it); otherwise the part needs
        /// its own `Override`.
        let typedByExtension: Bool
    }

    /// Parts in `Presentation.images` order.
    let parts: [Part]
    private let partNameByFileName: [String: String]

    init(images: [MediaFile]) {
        // First entry per exact file name.
        var seen = Set<String>()
        let unique = images.filter { seen.insert($0.fileName).inserted }

        // Pass 1: keep every safe name that is not taken (case-insensitively).
        var taken = Set<String>()
        var kept: [String?] = unique.map { image in
            guard Self.isSafePartFileName(image.fileName),
                  taken.insert(image.fileName.lowercased()).inserted else { return nil }
            return image.fileName
        }

        // Pass 2: give every other file a generated name that is not taken.
        var counter = 1
        for index in unique.indices where kept[index] == nil {
            let ext = Self.generatedExtension(for: unique[index])
            var candidate: String
            repeat {
                candidate = "image\(counter).\(ext)"
                counter += 1
            } while !taken.insert(candidate.lowercased()).inserted
            kept[index] = candidate
        }

        var map: [String: String] = [:]
        parts = zip(unique, kept).map { image, name in
            let name = name!
            map[image.fileName] = name
            let ext = Self.extensionOf(name)
            if let known = MediaFile.contentTypesByExtension[ext] {
                return Part(name: name, data: image.data, contentType: known, typedByExtension: true)
            }
            return Part(name: name, data: image.data,
                        contentType: Self.sniffedContentType(of: image.data) ?? "application/octet-stream",
                        typedByExtension: false)
        }
        partNameByFileName = map
    }

    /// The part name written for the media file a picture names, or nil when
    /// `Presentation.images` has no entry with that `fileName`.
    func partName(forMediaFileName fileName: String) -> String? {
        partNameByFileName[fileName]
    }

    /// `Default` entries (lowercase extension → content type) needed by the
    /// parts typed by extension, sorted by extension.
    var defaultContentTypes: [(extension: String, contentType: String)] {
        var byExtension: [String: String] = [:]
        for part in parts where part.typedByExtension {
            byExtension[Self.extensionOf(part.name)] = part.contentType
        }
        return byExtension.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    /// Parts that need an `Override` entry.
    var overriddenParts: [Part] {
        parts.filter { !$0.typedByExtension }
    }

    // MARK: - Naming rules

    /// Extensions a media part must not carry: the package's structural
    /// `Default` entries would type it as XML or a relationship part.
    static let reservedExtensions: Set<String> = ["xml", "rels"]

    static func isSafePartFileName(_ name: String) -> Bool {
        guard !name.isEmpty, name.utf8.count <= 128,
              name.first != ".", name.last != "." else { return false }
        let allowed = name.unicodeScalars.allSatisfy { scalar in
            switch scalar {
            case "a"..."z", "A"..."Z", "0"..."9", ".", "_", "-": return true
            default: return false
            }
        }
        return allowed && !reservedExtensions.contains(extensionOf(name))
    }

    /// Lowercased text after the last `.`, or "" when there is none.
    static func extensionOf(_ name: String) -> String {
        guard let dot = name.lastIndex(of: ".") else { return "" }
        return String(name[name.index(after: dot)...]).lowercased()
    }

    /// Extension for a generated name: the original one when it is plain
    /// ASCII alphanumerics and not reserved, else one derived from the bytes,
    /// else `bin`.
    private static func generatedExtension(for image: MediaFile) -> String {
        let original = extensionOf(image.fileName)
        if !original.isEmpty, original.count <= 10, !reservedExtensions.contains(original),
           original.unicodeScalars.allSatisfy({ ("a"..."z").contains($0) || ("0"..."9").contains($0) }) {
            return original
        }
        if let type = sniffedType(of: image.data), let ext = type.preferredFilenameExtension?.lowercased(),
           !reservedExtensions.contains(ext) {
            return ext
        }
        return "bin"
    }

    private static func sniffedType(of data: Data) -> UTType? {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let identifier = CGImageSourceGetType(source) as String? else { return nil }
        return UTType(identifier)
    }

    /// MIME type ImageIO recognises the bytes as, if any.
    static func sniffedContentType(of data: Data) -> String? {
        sniffedType(of: data)?.preferredMIMEType
    }
}
