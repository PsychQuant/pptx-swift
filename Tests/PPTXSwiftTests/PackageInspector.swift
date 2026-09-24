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

    /// `r:embed` values of the `a:blip` elements in a part, in document order.
    func blipEmbeds(in partName: String) throws -> [String?] {
        try xml(partName).nodes(forXPath: "//*[local-name()='blip']").map { node in
            (node as? XMLElement)?.attribute(forLocalName: "embed", uri: Self.nsR)?.stringValue
        }
    }

    /// The part an internal relationship of `sourcePart` points at.
    func resolve(_ relationship: Relationship, from sourcePart: String) -> String? {
        guard !relationship.isExternal else { return nil }
        return PptxReader.resolvePartPath(target: relationship.target, relativeTo: sourcePart)
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
    /// 7. an `a:srcRect` edge that is not an integer in the `xsd:int` range.
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
