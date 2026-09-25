import Testing
import Foundation
import OOXMLSwift
@testable import PPTXSwift

/// PsychQuant/pptx-swift#11: `p:style` (`CT_ShapeStyle`) — a shape's or
/// connector's theme style reference (`lnRef`／`fillRef`／`effectRef`／
/// `fontRef`, each an `<a:schemeClr>` plus a style-matrix index) — was never
/// modeled: `parseShape`／`parseConnector` never looked for it, and
/// `serializeShape`／`serializeConnector` never wrote it. Many
/// PowerPoint-authored shapes rely on this *instead of* an explicit
/// `<a:ln>`／fill in `spPr` for their actual rendered color. Discovered
/// while re-verifying #10's fix with a full (non-isolated) LibreOffice
/// round trip of `shapes.pptx`: the fixture's three connectors and its
/// "Cloud" freeform shape all get their color *only* from `p:style` — none
/// has an explicit `<a:ln>`／`<a:solidFill>` — so after a round trip through
/// pptx-swift, none of them had any color information left anywhere in the
/// written XML, and LibreOffice rendered every one of them with no visible
/// stroke or fill at all (pixel-sampled: theme blue `(74,126,187)` before,
/// pure white `(255,255,255)` after, at the exact same coordinates).
struct ThemeStyleTests {
    private static let nsA = "http://schemas.openxmlformats.org/drawingml/2006/main"

    // MARK: - Scenario: a hand-built p:style round trips verbatim at the correct schema position

    /// Exercises the *writer's* splicing in isolation, independent of the
    /// reader — the caller supplies an already self-contained `styleXML`
    /// literal (as the reader would produce it) and this only checks it
    /// lands at the right place with the right structure.
    @Test func `A shapes explicit styleXML is written between spPr and txBody`() throws {
        let style = "<p:style xmlns:a=\"\(Self.nsA)\"><a:lnRef idx=\"2\"><a:schemeClr val=\"accent1\"/></a:lnRef><a:fillRef idx=\"1\"><a:schemeClr val=\"accent1\"/></a:fillRef><a:effectRef idx=\"0\"><a:schemeClr val=\"accent1\"/></a:effectRef><a:fontRef idx=\"minor\"><a:schemeClr val=\"lt1\"/></a:fontRef></p:style>"
        var pres = PptxWriter.createNew()
        pres.slides[0].elements = [
            .shape(Shape(id: 2, name: "Cloud", textBody: TextBody(paragraphs: [TextParagraph(text: "hi")]), styleXML: style)),
        ]

        try TemporaryPPTX.written(pres) { url in
            let package = try PackageInspector(url)
            defer { package.cleanup() }
            #expect(try package.integrityViolations() == [])

            let slideXML = try package.xml("ppt/slides/slide1.xml")
            let sp = try #require(try slideXML.nodes(forXPath: "//*[local-name()='sp']").first as? XMLElement)
            let children = try sp.nodes(forXPath: "*").compactMap { $0 as? XMLElement }
            let childNames = children.map { $0.localName ?? "" }
            #expect(childNames == ["nvSpPr", "spPr", "style", "txBody"],
                     "p:style must sit between spPr and txBody per CT_Shape's sequence, got \(childNames)")

            let styleEl = try #require(children.first { $0.localName == "style" })
            #expect(styleEl.uri == "http://schemas.openxmlformats.org/presentationml/2006/main")
            let lnRef = try #require(try styleEl.nodes(forXPath: "*[local-name()='lnRef']").first as? XMLElement)
            #expect(lnRef.attribute(forName: "idx")?.stringValue == "2")
            let schemeClr = try #require(try lnRef.nodes(forXPath: "*[local-name()='schemeClr']").first as? XMLElement)
            #expect(schemeClr.uri == Self.nsA, "the a: children inside p:style must resolve to the DrawingML namespace")
            #expect(schemeClr.attribute(forName: "val")?.stringValue == "accent1")
        }
    }

    /// `Connector` has no `txBody` — `p:style` is the element's last child.
    @Test func `A connectors explicit styleXML is written after spPr with no txBody to precede`() throws {
        let style = "<p:style xmlns:a=\"\(Self.nsA)\"><a:lnRef idx=\"1\"><a:schemeClr val=\"accent1\"/></a:lnRef><a:fillRef idx=\"0\"><a:schemeClr val=\"accent1\"/></a:fillRef><a:effectRef idx=\"0\"><a:schemeClr val=\"accent1\"/></a:effectRef><a:fontRef idx=\"minor\"><a:schemeClr val=\"tx1\"/></a:fontRef></p:style>"
        var pres = PptxWriter.createNew()
        pres.slides[0].elements = [.connector(Connector(id: 2, name: "conn", styleXML: style))]

        try TemporaryPPTX.written(pres) { url in
            let package = try PackageInspector(url)
            defer { package.cleanup() }
            let slideXML = try package.xml("ppt/slides/slide1.xml")
            let cxnSp = try #require(try slideXML.nodes(forXPath: "//*[local-name()='cxnSp']").first as? XMLElement)
            let children = try cxnSp.nodes(forXPath: "*").compactMap { $0 as? XMLElement }
            #expect(children.map { $0.localName ?? "" } == ["nvCxnSpPr", "spPr", "style"])
        }
    }

    /// No `styleXML` set (the common case — most shapes/connectors have none,
    /// and every shape/connector before #11) writes exactly as before: no
    /// `<p:style>` tag appears at all, not an empty one.
    @Test func `No styleXML means no p style tag is written at all`() throws {
        var pres = PptxWriter.createNew()
        pres.slides[0].elements = [
            .shape(Shape(id: 2, name: "s")),
            .connector(Connector(id: 3, name: "c")),
        ]
        try TemporaryPPTX.written(pres) { url in
            let package = try PackageInspector(url)
            defer { package.cleanup() }
            let slideXML = try package.xml("ppt/slides/slide1.xml")
            #expect(try slideXML.nodes(forXPath: "//*[local-name()='style']").isEmpty)
        }
    }

    // MARK: - Scenario: the real shapes.pptx fixture's theme-only shapes round-trip their color

    @Test func `shapes pptx's connectors and Cloud shape keep their p style theme reference across a round trip`() throws {
        let source = try #require(RealFileTests.fixturePath("shapes.pptx"))
        let original = try PptxReader.read(from: source)

        let originalConnectors = original.slides[0].elements.compactMap { element -> Connector? in
            if case .connector(let c) = element { return c }
            return nil
        }
        try #require(originalConnectors.count == 3, "fixture assumption: shapes.pptx has 3 connectors")
        for c in originalConnectors {
            let style = try #require(c.styleXML, "connector \"\(c.name)\" lost its p:style on read")
            #expect(style.contains("lnRef"))
            #expect(style.contains("accent1"))
        }

        let cloud = try #require(original.slides[0].elements.compactMap { element -> Shape? in
            if case .shape(let s) = element, s.name == "Freeform 6" { return s }
            return nil
        }.first, "fixture assumption: shapes.pptx has a shape named \"Freeform 6\"")
        let cloudStyle = try #require(cloud.styleXML, "the Cloud shape lost its p:style on read")
        #expect(cloudStyle.contains("fillRef"))
        #expect(cloudStyle.contains("accent1"))

        try TemporaryPPTX.written(original, "theme-style-rt") { url in
            let package = try PackageInspector(url)
            defer { package.cleanup() }
            #expect(try package.integrityViolations() == [])

            // Every p:sp / p:cxnSp that originally carried p:style still has
            // exactly one, in the DrawingML-namespaced-children shape.
            let styleNodes = try package.xml("ppt/slides/slide1.xml").nodes(forXPath: "//*[local-name()='style']")
            #expect(styleNodes.count == 4, "3 connectors + 1 shape (Freeform 6) should each still carry p:style")

            let reread = try PptxReader.read(from: url)
            let rereadConnectors = reread.slides[0].elements.compactMap { element -> Connector? in
                if case .connector(let c) = element { return c }
                return nil
            }
            #expect(rereadConnectors.count == 3)
            for c in rereadConnectors {
                #expect(c.styleXML?.contains("accent1") == true)
            }
        }
    }
}
