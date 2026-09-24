import Testing
import Foundation
import OOXMLSwift
@testable import PPTXSwift

/// PsychQuant/pptx-swift#10: `PptxWriter.serializeGraphicFrame` wrote a
/// table cell's text body as `<p:txBody>` (`serializeTextBody`'s literal,
/// correct for `p:sp`/`p:pic`) instead of the ECMA-376-required
/// `<a:txBody>` for `CT_TableCell` (`a:tc`) — a namespace error, not a
/// missing-content one: the text is present, just wrapped in the wrong
/// element. Discovered during #9's LibreOffice verification: LibreOffice's
/// stricter OOXML importer silently stops rendering everything in the shape
/// tree from that table onward (the table's own content, and any element
/// that follows it in document order) once it hits the mistagged element.
struct TableCellNamespaceTests {
    private static let nsA = "http://schemas.openxmlformats.org/drawingml/2006/main"
    private static let nsP = "http://schemas.openxmlformats.org/presentationml/2006/main"

    // MARK: - Scenario: a table cell's text body is in the DrawingML namespace

    @Test func `A table cells text body is written in the DrawingML namespace`() throws {
        var pres = PptxWriter.createNew()
        pres.slides[0].elements = [
            .graphicFrame(GraphicFrame(
                id: 2, name: "Table 1",
                position: Position(x: 914400, y: 914400), size: Size(width: 1828800, height: 914400),
                table: DrawingTable(
                    columns: [TableColumn(width: 914400), TableColumn(width: 914400)],
                    rows: [TableRow(height: 914400, cells: [TableCell(text: "A1"), TableCell(text: "B1")])]
                )
            )),
        ]

        try TemporaryPPTX.written(pres) { url in
            let package = try PackageInspector(url)
            defer { package.cleanup() }
            #expect(try package.integrityViolations() == [])

            let slideXML = try package.xml("ppt/slides/slide1.xml")
            let tc = try #require(try slideXML.nodes(forXPath: "//*[local-name()='tc']").first as? XMLElement)
            let txBody = try #require(try tc.nodes(forXPath: "*[local-name()='txBody']").first as? XMLElement)
            #expect(txBody.uri == Self.nsA, "a:tc's text body must be a:txBody (DrawingML), not p:txBody")
            #expect(txBody.prefix == "a", "the written element must actually carry the a: prefix, not merely resolve to the DrawingML URI incidentally")

            // The DrawingML CT_TextBody structure itself (bodyPr, lstStyle,
            // paragraphs) must be unchanged — only the wrapping element's
            // namespace differs from before this fix.
            #expect(try txBody.nodes(forXPath: "*[local-name()='bodyPr']").count == 1)
            #expect(try txBody.nodes(forXPath: "*[local-name()='lstStyle']").count == 1)
            let text = try txBody.nodes(forXPath: ".//*[local-name()='t']").first?.stringValue
            #expect(text == "A1")

            // Reader still parses it back correctly (parseTable already used
            // local-name()-only XPath, so this was never broken on the read
            // side — this asserts the fix did not change reader behavior).
            let reread = try PptxReader.read(from: url)
            let frame = try #require(reread.slides[0].elements.compactMap { element -> GraphicFrame? in
                if case .graphicFrame(let f) = element { return f }
                return nil
            }.first)
            #expect(frame.table?.getCellText(row: 0, col: 0) == "A1")
            #expect(frame.table?.getCellText(row: 0, col: 1) == "B1")
        }
    }

    // MARK: - Scenario: a shape's text body keeps the unchanged p:txBody (regression guard)

    /// `serializeTextBody` is shared between `serializeShape` (correctly
    /// `p:txBody`, `CT_Shape`'s own type) and the table-cell call site (now
    /// `a:txBody`). This locks in that the *other* call site did not change.
    @Test func `A shapes text body still writes the exact literal p txBody unchanged`() throws {
        var pres = PptxWriter.createNew()
        pres.slides[0].elements = [
            .shape(Shape(id: 2, name: "s", textBody: TextBody(paragraphs: [TextParagraph(text: "hi")]))),
        ]

        try TemporaryPPTX.written(pres) { url in
            let package = try PackageInspector(url)
            defer { package.cleanup() }
            let slideXML = try package.xml("ppt/slides/slide1.xml")
            let sp = try #require(try slideXML.nodes(forXPath: "//*[local-name()='sp']").first as? XMLElement)
            let txBody = try #require(try sp.nodes(forXPath: "*[local-name()='txBody']").first as? XMLElement)
            #expect(txBody.uri == Self.nsP)
            #expect(txBody.prefix == "p")
        }
    }

    // MARK: - Scenario: real fixture — table.pptx round-trips with the correct namespace

    @Test func `table pptx round trips its cell text in the DrawingML namespace`() throws {
        let source = try #require(RealFileTests.fixturePath("table.pptx"))
        let original = try PptxReader.read(from: source)

        try TemporaryPPTX.written(original, "table-ns-rt") { url in
            let package = try PackageInspector(url)
            defer { package.cleanup() }
            #expect(try package.integrityViolations() == [])

            let slideXML = try package.xml("ppt/slides/slide1.xml")
            let tcs = try slideXML.nodes(forXPath: "//*[local-name()='tc']")
            try #require(!tcs.isEmpty, "fixture assumption: table.pptx has at least one table cell")
            for node in tcs {
                guard let tc = node as? XMLElement,
                      let txBody = try tc.nodes(forXPath: "*[local-name()='txBody']").first as? XMLElement else { continue }
                #expect(txBody.uri == Self.nsA)
            }

            let reread = try PptxReader.read(from: url)
            #expect(reread.slides[0].tables.first?.table?.getText() == original.slides[0].tables.first?.table?.getText())
        }
    }
}
