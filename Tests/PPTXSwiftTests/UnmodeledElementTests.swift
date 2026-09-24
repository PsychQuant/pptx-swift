import Testing
import Foundation
import OOXMLSwift
@testable import PPTXSwift

/// PsychQuant/pptx-swift#9: `p:spTree`／`p:grpSp` only recognized `p:sp`／
/// `p:pic`／`p:graphicFrame`／`p:grpSp`. Everything else — `p:cxnSp`
/// (connectors), `mc:AlternateContent`, `p:contentPart` — fell to
/// `default: break` in the reader and vanished with no error the moment
/// `PptxWriter` rewrote the slide. `p:cxnSp` gets full typed modeling
/// (`Connector`); everything else round-trips as self-contained raw XML
/// (`RawSlideElement`) unless it references a relationship, which `PptxWriter`
/// refuses to write rather than risk a dangling or colliding `rId`.
struct UnmodeledElementTests {

    // MARK: - Scenario: a connector with full styling round-trips

    @Test func `A connector with geometry rotation flip line and connection sites round trips`() throws {
        var pres = PptxWriter.createNew()
        pres.slides[0].elements = [
            .shape(Shape(id: 2, name: "Target shape", position: Position(x: 0, y: 0), size: Size(width: 914400, height: 914400))),
            .connector(Connector(
                id: 3, name: "Arrow", geometry: .bentConnector3,
                position: Position(x: 914400, y: 914400), size: Size(width: 1828800, height: 914400),
                rotation: 1_800_000, flipHorizontal: true, flipVertical: true,
                outline: ShapeOutline(
                    color: "FF0000", width: 12700,
                    headEnd: LineEndStyle(type: "triangle", width: "med", length: "lg"),
                    tailEnd: LineEndStyle(type: "arrow")
                ),
                startConnection: ConnectionSite(shapeId: 2, index: 0),
                endConnection: ConnectionSite(shapeId: 2, index: 2)
            )),
        ]

        try TemporaryPPTX.written(pres) { url in
            let package = try PackageInspector(url)
            defer { package.cleanup() }
            #expect(try package.integrityViolations() == [])

            let slideXML = try package.xml("ppt/slides/slide1.xml")
            let cxnSp = try #require(try slideXML.nodes(forXPath: "//*[local-name()='cxnSp']").first as? XMLElement)
            let stCxn = try #require(try cxnSp.nodes(forXPath: ".//*[local-name()='stCxn']").first as? XMLElement)
            #expect(stCxn.attribute(forName: "id")?.stringValue == "2")
            #expect(stCxn.attribute(forName: "idx")?.stringValue == "0")
            let endCxn = try #require(try cxnSp.nodes(forXPath: ".//*[local-name()='endCxn']").first as? XMLElement)
            #expect(endCxn.attribute(forName: "id")?.stringValue == "2")
            #expect(endCxn.attribute(forName: "idx")?.stringValue == "2")

            let reread = try PptxReader.read(from: url)
            let connector = try #require(reread.slides[0].elements.compactMap { element -> Connector? in
                if case .connector(let c) = element { return c }
                return nil
            }.first)
            #expect(connector.id == 3)
            #expect(connector.name == "Arrow")
            #expect(connector.geometry == .bentConnector3)
            #expect(connector.position.x == 914400 && connector.position.y == 914400)
            #expect(connector.size.width == 1828800 && connector.size.height == 914400)
            #expect(connector.rotation == 1_800_000)
            #expect(connector.flipHorizontal == true)
            #expect(connector.flipVertical == true)
            #expect(connector.outline?.color == "FF0000")
            #expect(connector.outline?.width == 12700)
            #expect(connector.outline?.headEnd == LineEndStyle(type: "triangle", width: "med", length: "lg"))
            #expect(connector.outline?.tailEnd == LineEndStyle(type: "arrow"))
            #expect(connector.startConnection == ConnectionSite(shapeId: 2, index: 0))
            #expect(connector.endConnection == ConnectionSite(shapeId: 2, index: 2))
        }
    }

    // MARK: - Scenario: a connector's geometry adjustment values round-trip

    /// Codex review round 1, MEDIUM: the writer always emitted an empty
    /// `<a:avLst/>`, silently discarding any adjustment values a bent or
    /// curved connector actually had — the bounding box, rotation and
    /// connection sites would all round-trip correctly while the connector's
    /// visible routing quietly reset to the preset default.
    @Test func `A connector with non default geometry adjustments round trips them`() throws {
        var pres = PptxWriter.createNew()
        pres.slides[0].elements = [
            .connector(Connector(
                id: 2, name: "Adjusted elbow", geometry: .bentConnector3,
                size: Size(width: 914400, height: 914400),
                adjustments: [GeometryAdjustment(name: "adj1", formula: "val 25000"), GeometryAdjustment(name: "adj2", formula: "val 75000")]
            )),
        ]

        try TemporaryPPTX.written(pres) { url in
            let package = try PackageInspector(url)
            defer { package.cleanup() }
            #expect(try package.integrityViolations() == [])

            let slideXML = try package.xml("ppt/slides/slide1.xml")
            let avLst = try #require(try slideXML.nodes(forXPath: "//*[local-name()='cxnSp']//*[local-name()='avLst']").first as? XMLElement)
            let gds = try avLst.nodes(forXPath: "*[local-name()='gd']").compactMap { $0 as? XMLElement }
            // Asserted directly on the written XML, independent of
            // `PptxReader` — Codex round 2 noted the original version only
            // checked `gds.count`, then verified `name`/`fmla` solely via a
            // round trip through the reader, which could not tell a writer
            // bug from a matching reader bug (the same blind spot the model
            // this project follows for other fields, e.g.
            // `PackageInspector`-based assertions elsewhere in this file).
            #expect(gds.map { $0.attribute(forName: "name")?.stringValue } == ["adj1", "adj2"])
            #expect(gds.map { $0.attribute(forName: "fmla")?.stringValue } == ["val 25000", "val 75000"])

            let reread = try PptxReader.read(from: url)
            let connector = try #require(reread.slides[0].elements.compactMap { element -> Connector? in
                if case .connector(let c) = element { return c }
                return nil
            }.first)
            #expect(connector.adjustments == [
                GeometryAdjustment(name: "adj1", formula: "val 25000"),
                GeometryAdjustment(name: "adj2", formula: "val 75000"),
            ])
        }
    }

    // MARK: - Scenario: a connector with no adjustments keeps the exact pre-#9 empty avLst

    /// Codex round 2: the claim that an empty `adjustments` array reproduces
    /// the pre-fix literal `<a:avLst/>` byte-for-byte was evident from the
    /// interpolation change but never asserted directly. Locks it in, the
    /// same way `XfrmRotationFlipTests`' "byte identical" test locks in
    /// omitted default attributes elsewhere in this codebase.
    @Test func `A connector with no adjustments writes the exact literal empty avLst tag`() throws {
        var pres = PptxWriter.createNew()
        pres.slides[0].elements = [.connector(Connector(id: 2, name: "c"))]

        try TemporaryPPTX.written(pres) { url in
            let package = try PackageInspector(url)
            defer { package.cleanup() }
            let slideText = try #require(String(data: try Data(contentsOf: package.root.appendingPathComponent("ppt/slides/slide1.xml")), encoding: .utf8))
            #expect(slideText.contains("<a:avLst/>"))
            // No leading-space assumption (Codex round 3 LOW: "<a:gd " alone
            // would miss a hypothetical self-closing "<a:gd/>" with no
            // attributes) — any spelling of the tag name is excluded.
            #expect(!slideText.contains("<a:gd"))
        }
    }

    // MARK: - Scenario: real fixture — shapes.pptx's three connectors

    /// `shapes.pptx` (Apache POI, already used by `RealFileTests`) has three
    /// `p:cxnSp` elements: a plain unconnected line (`prst="line"`, no
    /// `a:ln`), an unconnected double-headed arrow (`straightConnector1`,
    /// `flipV`, head+tail arrows), and an elbow connector whose end is wired
    /// to shape id=2 (`bentConnector3`, `flipV`, tail arrow only,
    /// `endCxn id="2" idx="1"`). Before #9 all three silently vanished on a
    /// round trip.
    @Test func `shapes pptx's three connectors survive a round trip`() throws {
        let source = try #require(RealFileTests.fixturePath("shapes.pptx"))
        let original = try PptxReader.read(from: source)

        func connectors(_ elements: [SlideElement]) -> [Connector] {
            elements.flatMap { element -> [Connector] in
                switch element {
                case .connector(let c): return [c]
                case .group(let g): return connectors(g.elements)
                default: return []
                }
            }
        }
        let originalConnectors = connectors(original.slides[0].elements)
        try #require(originalConnectors.count == 3, "fixture assumption: shapes.pptx slide 1 has 3 connectors")

        let line = try #require(originalConnectors.first { $0.name == "Straight Connector 5" })
        #expect(line.geometry == .line)
        #expect(line.flipVertical == false)
        #expect(line.outline?.headEnd == nil && line.outline?.tailEnd == nil)

        let arrow = try #require(originalConnectors.first { $0.name == "Straight Arrow Connector 7" })
        #expect(arrow.geometry == .straightConnector1)
        #expect(arrow.flipVertical == true)
        #expect(arrow.outline?.headEnd?.type == "arrow")
        #expect(arrow.outline?.tailEnd?.type == "arrow")
        #expect(arrow.startConnection == nil && arrow.endConnection == nil)

        let elbow = try #require(originalConnectors.first { $0.name == "Elbow Connector 9" })
        #expect(elbow.geometry == .bentConnector3)
        #expect(elbow.flipVertical == true)
        #expect(elbow.outline?.headEnd == nil)
        #expect(elbow.outline?.tailEnd?.type == "arrow")
        #expect(elbow.endConnection == ConnectionSite(shapeId: 2, index: 1))
        #expect(elbow.startConnection == nil)

        try TemporaryPPTX.written(original, "shapes-connectors-rt") { url in
            let package = try PackageInspector(url)
            defer { package.cleanup() }
            #expect(try package.integrityViolations() == [])

            let reread = try PptxReader.read(from: url)
            let rereadConnectors = connectors(reread.slides[0].elements)
            #expect(rereadConnectors.count == 3)
            for name in ["Straight Connector 5", "Straight Arrow Connector 7", "Elbow Connector 9"] {
                let before = try #require(originalConnectors.first { $0.name == name })
                let after = try #require(rereadConnectors.first { $0.name == name })
                #expect(before.geometry == after.geometry, "\(name) lost its geometry")
                #expect(before.flipVertical == after.flipVertical, "\(name) lost its flip")
                #expect(before.outline?.headEnd == after.outline?.headEnd, "\(name) lost its head arrow")
                #expect(before.outline?.tailEnd == after.outline?.tailEnd, "\(name) lost its tail arrow")
                #expect(before.endConnection == after.endConnection, "\(name) lost its end connection")
            }
        }
    }

    // MARK: - Helpers for building a synthetic package with an unmodeled element

    /// Writes `pres`, unzips the result, splices `rawXML` directly into
    /// slide 1's `<p:spTree>` (before the closing tag, so it lands after
    /// whatever `pres.slides[0].elements` already produced), and rezips —
    /// the same "write a valid skeleton, patch the raw text, rezip" pattern
    /// `XfrmRotationFlipTests` uses to test the reader in isolation from the
    /// writer. Used here to get an `mc:AlternateContent`／`p:contentPart`
    /// into a real package without `PptxWriter` needing to know how to
    /// *originate* one (only how to read one back and pass it through).
    static func writtenWithRawContentSpliced(_ pres: Presentation, rawXML: String, extraNamespaceDecl: String = "", label: String) throws -> URL {
        let url = TemporaryPPTX.url(label)
        try PptxWriter.write(pres, to: url)

        let unpacked = try ZipHelper.unzip(url)
        defer { ZipHelper.cleanup(unpacked) }
        let slidePath = unpacked.appendingPathComponent("ppt/slides/slide1.xml")
        var text = try String(contentsOf: slidePath, encoding: .utf8)
        guard let range = text.range(of: "</p:spTree>") else {
            throw PPTXError.parseError("fixture assumption: slide1.xml has a literal </p:spTree>")
        }
        text.replaceSubrange(range, with: rawXML + "</p:spTree>")
        if !extraNamespaceDecl.isEmpty, let sldTagEnd = text.range(of: ">", range: text.range(of: "<p:sld ")!.upperBound..<text.endIndex) {
            text.insert(contentsOf: " " + extraNamespaceDecl, at: sldTagEnd.lowerBound)
        }
        try text.write(to: slidePath, atomically: true, encoding: .utf8)

        try FileManager.default.removeItem(at: url)
        try ZipHelper.zip(unpacked, to: url)
        return url
    }

    // MARK: - Scenario: synthetic mc:AlternateContent round-trips as raw XML

    /// `mc:` is declared **only** on the outer `<p:sld>` (`extraNamespaceDecl`),
    /// never locally inside the raw content itself — the raw fragment has no
    /// `xmlns:mc="..."` of its own anywhere. This is deliberate: a version of
    /// `selfContainedXMLString` that did nothing (`element.xmlString`
    /// verbatim) would fail this test, because the fragment would be
    /// genuinely unbound once spliced elsewhere. Before Codex review round 1,
    /// the fixture declared `mc:` locally on the captured root, which meant
    /// the test could not tell a working repair from a no-op.
    @Test func `A synthetic mc colon AlternateContent element round trips as self contained raw XML`() throws {
        var pres = PptxWriter.createNew()
        pres.slides[0].elements = [.shape(Shape(id: 2, name: "Ordinary shape"))]

        let raw = """
        <mc:AlternateContent>\
        <mc:Choice Requires="p14">\
        <p:sp><p:nvSpPr><p:cNvPr id="50" name="Choice shape"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>\
        <p:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="100" cy="100"/></a:xfrm>\
        <a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr></p:sp>\
        </mc:Choice>\
        <mc:Fallback>\
        <p:sp><p:nvSpPr><p:cNvPr id="51" name="Fallback shape"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>\
        <p:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="100" cy="100"/></a:xfrm>\
        <a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr></p:sp>\
        </mc:Fallback>\
        </mc:AlternateContent>
        """
        let outerNamespaces = "xmlns:mc=\"http://schemas.openxmlformats.org/markup-compatibility/2006\" "
            + "xmlns:p14=\"http://schemas.microsoft.com/office/powerpoint/2010/main\""

        let url = try Self.writtenWithRawContentSpliced(pres, rawXML: raw, extraNamespaceDecl: outerNamespaces, label: "mc-alt-content")
        defer { try? FileManager.default.removeItem(at: url) }

        let package = try PackageInspector(url)
        defer { package.cleanup() }
        #expect(try package.integrityViolations() == [])

        let reread = try PptxReader.read(from: url)
        #expect(reread.slides[0].elements.count == 2, "expected the ordinary shape plus the raw AlternateContent element")
        let rawElement = try #require(reread.slides[0].elements.compactMap { element -> RawSlideElement? in
            if case .raw(let r) = element { return r }
            return nil
        }.first)
        #expect(rawElement.localName == "AlternateContent")
        #expect(rawElement.elementIds.sorted() == [50, 51], "must see ids from both the Choice and Fallback branches")
        #expect(rawElement.referencesRelationship == false)
        // `mc:` itself must be repaired (it is used as an element prefix, so
        // even the old scan-based design would have caught it) — asserted on
        // the parsed fragment's actual namespace URI, not a literal
        // substring, so a repair that injects the wrong URI would still fail.
        let fragmentRoot = try #require(try XMLDocument(xmlString: rawElement.xml).rootElement())
        #expect(fragmentRoot.namespaces?.first { $0.name == "mc" }?.stringValue
                == "http://schemas.openxmlformats.org/markup-compatibility/2006")

        // Round-trip again (read → write → read) to prove the self-contained
        // fragment really is well-formed once spliced into a *second*
        // generation of output, not just readable from the first patch.
        try TemporaryPPTX.written(reread, "mc-alt-content-rt2") { url2 in
            let package2 = try PackageInspector(url2)
            defer { package2.cleanup() }
            #expect(try package2.integrityViolations() == [])
            let reread2 = try PptxReader.read(from: url2)
            let rawElement2 = try #require(reread2.slides[0].elements.compactMap { element -> RawSlideElement? in
                if case .raw(let r) = element { return r }
                return nil
            }.first)
            #expect(rawElement2.elementIds.sorted() == [50, 51])
        }
    }

    // MARK: - Scenario: a namespace dependency named only inside an mc:Choice Requires value

    /// Codex review round 1, HIGH: `mc:Choice`'s `Requires` attribute holds a
    /// space-separated list of namespace *prefixes* the consumer must
    /// understand — a genuine namespace dependency that never appears as an
    /// element／attribute *name* prefix anywhere in the content. A design
    /// that only re-declares prefixes it finds by scanning for `prefix:name`
    /// usages (the pre-review-round-1 version of
    /// `selfContainedXMLString`) cannot see this dependency at all: nothing
    /// in this fixture's content is `p14:`-prefixed. `p14` is declared only
    /// on the outer `<p:sld>`, never locally in the raw content.
    @Test func `A namespace named only in a Requires attribute value is still repaired`() throws {
        var pres = PptxWriter.createNew()
        pres.slides[0].elements = [.shape(Shape(id: 2, name: "s"))]

        let raw = """
        <mc:AlternateContent>\
        <mc:Choice Requires="p14"><p:sp><p:nvSpPr><p:cNvPr id="50" name="x"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>\
        <p:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="1" cy="1"/></a:xfrm>\
        <a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr></p:sp></mc:Choice>\
        <mc:Fallback/>\
        </mc:AlternateContent>
        """
        let outerNamespaces = "xmlns:mc=\"http://schemas.openxmlformats.org/markup-compatibility/2006\" "
            + "xmlns:p14=\"http://schemas.microsoft.com/office/powerpoint/2010/main\""

        let url = try Self.writtenWithRawContentSpliced(pres, rawXML: raw, extraNamespaceDecl: outerNamespaces, label: "mc-requires-only")
        defer { try? FileManager.default.removeItem(at: url) }

        let reread = try PptxReader.read(from: url)
        let rawElement = try #require(reread.slides[0].elements.compactMap { element -> RawSlideElement? in
            if case .raw(let r) = element { return r }
            return nil
        }.first)
        try #require(!rawElement.xml.contains("p14:"), "fixture assumption: p14 never appears as an element/attribute prefix, only inside Requires=\"p14\"")
        let fragmentRoot = try #require(try XMLDocument(xmlString: rawElement.xml).rootElement())
        #expect(fragmentRoot.namespaces?.first { $0.name == "p14" }?.stringValue
                == "http://schemas.microsoft.com/office/powerpoint/2010/main",
                "p14 must be re-declared even though it never appears as a tag/attribute prefix")
    }

    // MARK: - Scenario: a prefix re-declared to a different URI deeper in the subtree

    /// Codex review round 1, HIGH: a whole-fragment text search for
    /// `xmlns:x="` (the pre-review-round-1 design's "already declared, skip
    /// it" guard) is fooled by a *descendant* re-declaring the same prefix to
    /// a *different* URI — ordinary, valid XML nesting. The captured root
    /// itself does not locally declare `x`; only its child does, to a
    /// different URI than the ancestor's. The root still needs the
    /// ancestor's binding injected.
    @Test func `A prefix redeclared deeper in the subtree does not suppress the roots own binding`() throws {
        var pres = PptxWriter.createNew()
        pres.slides[0].elements = [.shape(Shape(id: 2, name: "s"))]

        let raw = "<x:widget><x:inner xmlns:x=\"urn:inner\"/></x:widget>"
        let url = try Self.writtenWithRawContentSpliced(pres, rawXML: raw, extraNamespaceDecl: "xmlns:x=\"urn:outer\"", label: "nested-redecl")
        defer { try? FileManager.default.removeItem(at: url) }

        let reread = try PptxReader.read(from: url)
        let rawElement = try #require(reread.slides[0].elements.compactMap { element -> RawSlideElement? in
            if case .raw(let r) = element { return r }
            return nil
        }.first)
        let fragmentRoot = try #require(try XMLDocument(xmlString: rawElement.xml).rootElement())
        #expect(fragmentRoot.namespaces?.first { $0.name == "x" }?.stringValue == "urn:outer",
                "the captured root must get the ancestor's binding, not be suppressed by the descendant's different one")
        let inner = try #require(fragmentRoot.children?.first as? XMLElement)
        #expect(inner.namespaces?.first { $0.name == "x" }?.stringValue == "urn:inner",
                "the descendant's own closer re-declaration must survive untouched")
    }

    // MARK: - Scenario: an inherited, unprefixed default namespace is also repaired

    /// Codex round 1 HIGH also named the unprefixed default namespace as a
    /// class of dependency the old scan-based design dropped entirely; round
    /// 2 noted no test exercised it directly. The captured root and its
    /// child are both unprefixed (no local `xmlns=` of their own anywhere in
    /// the raw content) and rely entirely on the ambient default namespace
    /// declared only on the outer `<p:sld>`.
    @Test func `An inherited unprefixed default namespace is also repaired`() throws {
        var pres = PptxWriter.createNew()
        pres.slides[0].elements = [.shape(Shape(id: 2, name: "s"))]

        let raw = "<widget><item/></widget>"
        let url = try Self.writtenWithRawContentSpliced(pres, rawXML: raw, extraNamespaceDecl: "xmlns=\"urn:defaultns\"", label: "default-ns")
        defer { try? FileManager.default.removeItem(at: url) }

        let reread = try PptxReader.read(from: url)
        let rawElement = try #require(reread.slides[0].elements.compactMap { element -> RawSlideElement? in
            if case .raw(let r) = element { return r }
            return nil
        }.first)
        #expect(rawElement.localName == "widget")
        let fragmentRoot = try #require(try XMLDocument(xmlString: rawElement.xml).rootElement())
        #expect(fragmentRoot.namespaces?.first { $0.name == "" }?.stringValue == "urn:defaultns",
                "the unprefixed default namespace inherited from the outer slide must also be repaired onto the fragment root")
    }

    // MARK: - Scenario: id collision avoidance sees ids inside raw content

    @Test func `Slide allElementIds and GroupShape containsElement see ids inside raw content`() throws {
        let raw = RawSlideElement(localName: "AlternateContent", xml: "<mc:AlternateContent/>", elementIds: [50, 51])
        var slide = Slide()
        slide.elements = [
            .shape(Shape(id: 2, name: "s")),
            .raw(raw),
            .group(GroupShape(id: 10, name: "g", elements: [
                .shape(Shape(id: 11, name: "nested")),
                .raw(RawSlideElement(localName: "contentPart", xml: "<p:contentPart/>", elementIds: [60])),
            ])),
        ]

        #expect(slide.allElementIds.sorted() == [2, 10, 11, 50, 51, 60])
        #expect(slide.locateElement(id: 50) == .topLevel(index: 1))
        // The raw element's *second* id, not just its first — Codex round 2
        // noted the original assertion here only ever exercised id 50, which
        // would not have caught the `elementId`-only bug round 1 introduced
        // (fixed before round 1's own review completed, but the test itself
        // was never strengthened to cover it explicitly until now).
        #expect(slide.locateElement(id: 51) == .topLevel(index: 1))
        #expect(slide.locateElement(id: 60) == .groupChild(groupId: 10))
        #expect(slide.locateElement(id: 999) == .notFound)

        guard case .group(let group) = slide.elements[2] else {
            Issue.record("expected the group at index 2")
            return
        }
        #expect(group.containsElement(id: 60))
        #expect(group.containsElement(id: 11))
        #expect(!group.containsElement(id: 50), "id 50 belongs to a sibling raw element, not this group's subtree")
    }

    // MARK: - Scenario: setGeometry on a raw element throws a typed error

    @Test func `setGeometry on a raw element throws rawElementGeometryUnsupported`() throws {
        var slide = Slide()
        slide.elements = [.raw(RawSlideElement(localName: "AlternateContent", xml: "<mc:AlternateContent/>", elementIds: [50]))]

        let error = #expect(throws: PPTXError.self) {
            try slide.setGeometry(ofElementId: 50, xCm: 1, yCm: 1, widthCm: 1, heightCm: 1)
        }
        guard case .rawElementGeometryUnsupported(let shapeId)? = error else {
            Issue.record("expected .rawElementGeometryUnsupported, got \(String(describing: error))")
            return
        }
        #expect(shapeId == 50)
    }

    // MARK: - Scenario: a relationship-referencing raw element refuses to write

    /// `p:contentPart` (digital ink) is, structurally, just an `r:id`
    /// reference to an ink part — it never appears without one. This is the
    /// case #9's "或明確報錯" branch exists for: pptx-swift cannot safely
    /// renumber a relationship reference buried in opaque raw XML text
    /// without risking a dangling or colliding `rId`, so it refuses to write
    /// rather than guess.
    @Test func `A slide with a relationship referencing raw element fails to save and writes nothing`() throws {
        var pres = PptxWriter.createNew()
        pres.slides[0].elements = [.shape(Shape(id: 2, name: "s"))]

        let contentPart = """
        <p:contentPart xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" r:id="rId5"/>
        """
        let url = try Self.writtenWithRawContentSpliced(pres, rawXML: contentPart, label: "content-part-src")
        let reread = try PptxReader.read(from: url)
        try FileManager.default.removeItem(at: url)

        let rawElement = try #require(reread.slides[0].elements.compactMap { element -> RawSlideElement? in
            if case .raw(let r) = element { return r }
            return nil
        }.first)
        #expect(rawElement.localName == "contentPart")
        #expect(rawElement.referencesRelationship == true)

        let outURL = TemporaryPPTX.url("content-part-write-refused")
        defer { try? FileManager.default.removeItem(at: outURL) }
        let error = #expect(throws: PPTXError.self) {
            try PptxWriter.write(reread, to: outURL)
        }
        guard case .writeError(let message)? = error else {
            Issue.record("expected .writeError, got \(String(describing: error))")
            return
        }
        #expect(message.contains("contentPart"))
        #expect(!FileManager.default.fileExists(atPath: outURL.path))
    }

    // MARK: - Scenario: the same refusal reaches a raw element nested inside a group

    @Test func `A relationship referencing raw element nested in a group also fails to save`() throws {
        var pres = PptxWriter.createNew()
        pres.slides[0].elements = [
            .group(GroupShape(id: 10, name: "g", elements: [
                .raw(RawSlideElement(
                    localName: "contentPart",
                    xml: "<p:contentPart xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" r:id=\"rId5\"/>",
                    referencesRelationship: true
                )),
            ])),
        ]

        let url = TemporaryPPTX.url("nested-content-part")
        defer { try? FileManager.default.removeItem(at: url) }
        let error = #expect(throws: PPTXError.self) {
            try PptxWriter.write(pres, to: url)
        }
        guard case .writeError(let message)? = error else {
            Issue.record("expected .writeError, got \(String(describing: error))")
            return
        }
        #expect(message.contains("contentPart"))
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}
