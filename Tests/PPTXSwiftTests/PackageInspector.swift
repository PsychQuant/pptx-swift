import Foundation
import ImageIO
import UniformTypeIdentifiers
import OOXMLSwift
@testable import PPTXSwift

/// A written `.pptx` unpacked for inspection, independent of `PptxReader`:
/// content types, relationships and `r:` references are read straight from
/// the package XML, so a writer bug cannot be masked by a matching reader bug.
struct PackageInspector {
    static let nsR = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    static let imageRelType = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/image"

    struct Relationship {
        let id: String
        let type: String
        let target: String
        let isExternal: Bool
    }

    let root: URL

    init(_ pptx: URL) throws {
        root = try ZipHelper.unzip(pptx)
    }

    func cleanup() {
        ZipHelper.cleanup(root)
    }

    /// Every file in the package, as part names without a leading `/`.
    func partNames() throws -> [String] {
        let base = root.standardizedFileURL.path
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey]
        ) else { return [] }
        var names: [String] = []
        for case let url as URL in enumerator {
            guard (try url.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true else { continue }
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(base + "/") else { continue }
            names.append(String(path.dropFirst(base.count + 1)))
        }
        return names.sorted()
    }

    func xml(_ partName: String) throws -> XMLDocument {
        try XMLDocument(data: Data(contentsOf: root.appendingPathComponent(partName)))
    }

    /// Content type of a part per OPC: an `Override` for the exact part name
    /// (case-insensitive) wins, else the `Default` for its extension.
    func contentType(of partName: String) throws -> String? {
        let types = try xml("[Content_Types].xml")
        for node in try types.nodes(forXPath: "//*[local-name()='Override']") {
            guard let element = node as? XMLElement,
                  let name = element.attribute(forName: "PartName")?.stringValue else { continue }
            if name.caseInsensitiveCompare("/" + partName) == .orderedSame {
                return element.attribute(forName: "ContentType")?.stringValue
            }
        }
        // OPC extension: everything after the last "." of the last segment
        // (so `_rels/.rels` has extension `rels`, unlike NSString.pathExtension).
        let last = (partName as NSString).lastPathComponent
        guard let dot = last.lastIndex(of: ".") else { return nil }
        let ext = String(last[last.index(after: dot)...])
        guard !ext.isEmpty else { return nil }
        for node in try types.nodes(forXPath: "//*[local-name()='Default']") {
            guard let element = node as? XMLElement,
                  let e = element.attribute(forName: "Extension")?.stringValue else { continue }
            if e.caseInsensitiveCompare(ext) == .orderedSame {
                return element.attribute(forName: "ContentType")?.stringValue
            }
        }
        return nil
    }

    func relsPartName(of partName: String) -> String {
        guard !partName.isEmpty else { return "_rels/.rels" }
        let dir = (partName as NSString).deletingLastPathComponent
        let file = (partName as NSString).lastPathComponent
        return dir.isEmpty ? "_rels/\(file).rels" : "\(dir)/_rels/\(file).rels"
    }

    func relationships(of partName: String) throws -> [Relationship] {
        let relsPart = relsPartName(of: partName)
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent(relsPart).path) else { return [] }
        return try xml(relsPart).nodes(forXPath: "//*[local-name()='Relationship']").compactMap { node in
            guard let element = node as? XMLElement else { return nil }
            return Relationship(
                id: element.attribute(forName: "Id")?.stringValue ?? "",
                type: element.attribute(forName: "Type")?.stringValue ?? "",
                target: element.attribute(forName: "Target")?.stringValue ?? "",
                isExternal: element.attribute(forName: "TargetMode")?.stringValue == "External"
            )
        }
    }

    /// Non-empty values of every `r:`-namespaced attribute (`r:embed`,
    /// `r:link`, `r:id`, …) in a part, in document order.
    func relationshipReferences(in partName: String) throws -> [String] {
        // Foundation's XPath does not evaluate namespace-uri() on attribute
        // nodes, so filter on the parsed attribute's `uri` instead.
        try xml(partName)
            .nodes(forXPath: "//@*")
            .filter { $0.uri == Self.nsR }
            .compactMap { $0.stringValue }
            .filter { !$0.isEmpty }
    }

    /// `r:` attributes of a part that are not on a picture's own blip (rule 8
    /// of `integrityViolations`), each described with the path of local
    /// names from the nearest shape-tree child down to the attribute's
    /// element, e.g. `sp/spPr/blipFill/blip r:embed="rId2"`. Checked here
    /// independently of `PptxWriter.strayRelationshipReferences`, so the
    /// writer's own guard cannot vouch for itself.
    func strayRelationshipReferences(in partName: String) throws -> [String] {
        // The document must outlive the walk: an attribute node returned by
        // XPath loses its `parent` once the owning XMLDocument is released,
        // and a temporary document is released right after `nodes(forXPath:)`.
        let document = try xml(partName)
        return try withExtendedLifetime(document) { try document.nodes(forXPath: "//@*").compactMap { attribute -> String? in
            guard attribute.uri == Self.nsR, let owner = attribute.parent as? XMLElement else { return nil }
            var path: [String] = []
            var current: XMLElement? = owner
            while let element = current, let name = element.localName, name != "spTree" {
                path.insert(name, at: 0)
                current = element.parent as? XMLElement
            }
            let onPictureBlip = path.count >= 3
                && path.suffix(3) == ["pic", "blipFill", "blip"]
                && path.dropLast(3).allSatisfy { $0 == "grpSp" }
            guard !onPictureBlip else { return nil }
            return "\(path.joined(separator: "/")) \(attribute.name ?? "")=\"\(attribute.stringValue ?? "")\""
        } }
    }

    /// `r:embed` values of the `a:blip` elements in a part, in document order.
    func blipEmbeds(in partName: String) throws -> [String?] {
        try xml(partName).nodes(forXPath: "//*[local-name()='blip']").map { node in
            (node as? XMLElement)?.attribute(forLocalName: "embed", uri: Self.nsR)?.stringValue
        }
    }

    /// `r:link` values of the `a:blip` elements in a part, in document order
    /// (PsychQuant/pptx-swift#5: external-link pictures).
    func blipLinks(in partName: String) throws -> [String?] {
        try xml(partName).nodes(forXPath: "//*[local-name()='blip']").map { node in
            (node as? XMLElement)?.attribute(forLocalName: "link", uri: Self.nsR)?.stringValue
        }
    }

    /// Depth (nesting level) of every `<p:grpSp>` element in a part, in
    /// document order: 0 for a group that is a direct child of `p:spTree`, 1
    /// for one nested one level deeper, and so on.
    func groupShapeDepths(in partName: String) throws -> [Int] {
        try xml(partName).nodes(forXPath: "//*[local-name()='grpSp']").map { node -> Int in
            var depth = 0
            var current = (node as? XMLElement)?.parent
            while let element = current as? XMLElement {
                if element.localName == "grpSp" { depth += 1 }
                current = element.parent
            }
            return depth
        }
    }

    /// The part an internal relationship of `sourcePart` points at, resolved
    /// here rather than with `PptxReader.resolvePartPath`, so the reader's
    /// resolution cannot vouch for itself: percent-decoded, relative to the
    /// source part's directory (the package root for a leading `/` or for the
    /// package's own relationships), `.` and `..` segments normalised; nil
    /// when the target climbs above the root.
    func resolve(_ relationship: Relationship, from sourcePart: String) -> String? {
        guard !relationship.isExternal else { return nil }
        let target = relationship.target.removingPercentEncoding ?? relationship.target
        var stack: [String] = target.hasPrefix("/")
            ? []
            : sourcePart.split(separator: "/").dropLast().map(String.init)
        for segment in target.split(separator: "/", omittingEmptySubsequences: true) {
            if segment == "." { continue }
            if segment == ".." {
                guard !stack.isEmpty else { return nil }
                stack.removeLast()
            } else {
                stack.append(String(segment))
            }
        }
        return stack.isEmpty ? nil : stack.joined(separator: "/")
    }

    /// Package-level consistency findings, human-readable (empty = none
    /// found). This is a structural check of the properties below, not a
    /// full schema validation or a PowerPoint render:
    ///
    /// 1. a part without a content type;
    /// 2. a relationship file (including the package's `_rels/.rels`) with
    ///    duplicate Ids;
    /// 3. an internal relationship whose target part does not exist;
    /// 4. an `r:` reference in a slide with no relationship of that Id;
    /// 5. a picture `r:embed` whose relationship is not an image relationship;
    /// 6. a media part ImageIO identifies whose content type is not that
    ///    format's MIME type;
    /// 7. an `a:srcRect` edge that is not an integer in the `xsd:int` range;
    /// 8. an `r:` reference in a slide anywhere other than a picture's own
    ///    `p:pic/p:blipFill/a:blip` (under `p:spTree` and `p:grpSp` only).
    ///    `PptxWriter` allocates relationships for nothing else, so any other
    ///    `r:` attribute in its output was carried over from a source rels
    ///    part that no longer exists — rule 4 cannot see it when the old Id
    ///    happens to name a relationship the writer allocated for something
    ///    else (#12 review C1: a picture-filled shape showed a different
    ///    picture after a round trip).
    func integrityViolations() throws -> [String] {
        var findings: [String] = []
        let parts = try partNames()
        let partSet = Set(parts)
        for part in parts where part != "[Content_Types].xml" {
            if try contentType(of: part) == nil { findings.append("no content type: \(part)") }
        }
        // "" stands for the package itself, whose relationships are _rels/.rels.
        for part in [""] + parts where !part.hasSuffix(".rels") && part != "[Content_Types].xml" {
            let rels = try relationships(of: part)
            let ids = rels.map(\.id)
            if Set(ids).count != ids.count { findings.append("duplicate relationship Ids in \(relsPartName(of: part))") }
            for rel in rels where !rel.isExternal {
                guard let target = resolve(rel, from: part), partSet.contains(target) else {
                    findings.append("\(part) \(rel.id) → missing part \(rel.target)")
                    continue
                }
            }
        }
        for part in parts where part.hasPrefix("ppt/media/") {
            let data = try Data(contentsOf: root.appendingPathComponent(part))
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let identifier = CGImageSourceGetType(source) as String?,
                  let mime = UTType(identifier)?.preferredMIMEType else { continue }
            let declared = try contentType(of: part)
            if declared != mime { findings.append("\(part) holds \(mime) but is typed \(declared ?? "nothing")") }
        }
        for part in parts where part.hasPrefix("ppt/slides/") && part.hasSuffix(".xml") && !part.contains("/_rels/") {
            for node in try xml(part).nodes(forXPath: "//*[local-name()='srcRect']") {
                for attribute in (node as? XMLElement)?.attributes ?? [] {
                    let value = attribute.stringValue ?? ""
                    if Int32(value) == nil { findings.append("\(part) srcRect \(attribute.name ?? "")=\"\(value)\" is not an xsd:int") }
                }
            }
            let rels = try relationships(of: part)
            let byId = Dictionary(rels.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for reference in try relationshipReferences(in: part) where byId[reference] == nil {
                findings.append("\(part) references undefined relationship \(reference)")
            }
            for stray in try strayRelationshipReferences(in: part) {
                findings.append("\(part) \(stray) is not on a picture's own blip")
            }
            for embed in try blipEmbeds(in: part).compactMap({ $0 }) {
                if let rel = byId[embed], rel.type != Self.imageRelType {
                    findings.append("\(part) r:embed \(embed) is a \(rel.type) relationship, not an image")
                }
            }
        }
        return findings
    }
}

enum TemporaryPPTX {
    static func url(_ label: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("pptx-\(label)-\(UUID().uuidString).pptx")
    }

    /// Writes `presentation`, hands the output to `body`, and removes it after.
    static func written<T>(_ presentation: Presentation, _ label: String = "w",
                           _ body: (URL) throws -> T) throws -> T {
        let url = url(label)
        defer { try? FileManager.default.removeItem(at: url) }
        try PptxWriter.write(presentation, to: url)
        return try body(url)
    }
}
