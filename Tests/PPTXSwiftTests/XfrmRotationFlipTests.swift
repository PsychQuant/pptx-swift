import Testing
import Foundation
import OOXMLSwift
@testable import PPTXSwift

/// PsychQuant/pptx-swift#7: `a:xfrm`'s `rot` (rotation) and `flipH`／`flipV`
/// (flip) were not modeled at all — `Shape`／`Picture`／`GraphicFrame`／
/// `GroupShape` had no fields for them, the reader never read them, and the
/// writer's `<a:xfrm>`／`<p:xfrm>` templates never emitted them. Any rotated
/// or flipped element silently lost that transform on a round trip, with no
/// error (#5's "known limitations" section documented this as an existing,
/// cross-cutting gap once GroupShape round-tripping made it matter more).
struct XfrmRotationFlipTests {

    /// One full turn in `ST_Angle` units (60,000ths of a degree) —
    /// ECMA-376 Part 1 §20.1.10.3 defines `ST_Angle` as an unrestricted
    /// `xsd:int`, so this is a convention, not a schema limit.
    static let fullTurn = 21_600_000
    static func degrees(_ d: Int) -> Int { d * 60_000 }

    // MARK: - Scenario: a shape rotated 30° with a horizontal flip

    @Test func `A shape rotated 30 degrees with a horizontal flip round-trips both`() throws {
        var pres = PptxWriter.createNew()
        pres.slides[0].elements = [
            .shape(Shape(
                id: 2, name: "Rotated shape",
                position: Position(x: 914400, y: 914400), size: Size(width: 1828800, height: 914400),
                rotation: Self.degrees(30), flipHorizontal: true
            ))
        ]

        try TemporaryPPTX.written(pres) { url in
            let package = try PackageInspector(url)
            defer { package.cleanup() }
            #expect(try package.integrityViolations() == [])

            let slideXML = try package.xml("ppt/slides/slide1.xml")
            let xfrm = try #require(try slideXML.nodes(forXPath: "//*[local-name()='sp']/*[local-name()='spPr']/*[local-name()='xfrm']").first as? XMLElement)
            #expect(xfrm.attribute(forName: "rot")?.stringValue == "\(Self.degrees(30))")
            #expect(xfrm.attribute(forName: "flipH")?.stringValue == "1")
            #expect(xfrm.attribute(forName: "flipV") == nil, "flipV must stay omitted when false")

            let reread = try PptxReader.read(from: url)
            let shape = try #require(reread.slides[0].shapes.first)
            #expect(shape.rotation == Self.degrees(30))
            #expect(shape.flipHorizontal == true)
            #expect(shape.flipVertical == false)
        }
    }

    // MARK: - Scenario: a picture flipped vertically

    @Test func `A picture flipped vertically round-trips the flip with no rotation`() throws {
        let png = try GeneratedImage.png(width: 16, height: 12)
        var pres = PptxWriter.createNew()
        pres.images = [MediaFile(id: "photo.png", fileName: "photo.png", data: png)]
        pres.slides[0].elements = [
            .picture(Picture(
                id: 2, name: "Flipped picture",
                position: Position(x: 0, y: 0), size: Size(width: 200, height: 200),
                flipVertical: true,
                mediaFileName: "photo.png"
            ))
        ]

        try TemporaryPPTX.written(pres) { url in
            let package = try PackageInspector(url)
            defer { package.cleanup() }
            #expect(try package.integrityViolations() == [])

            let slideXML = try package.xml("ppt/slides/slide1.xml")
            let xfrm = try #require(try slideXML.nodes(forXPath: "//*[local-name()='pic']/*[local-name()='spPr']/*[local-name()='xfrm']").first as? XMLElement)
            #expect(xfrm.attribute(forName: "flipV")?.stringValue == "1")
            #expect(xfrm.attribute(forName: "flipH") == nil, "flipH must stay omitted when false")
            #expect(xfrm.attribute(forName: "rot") == nil, "rot must stay omitted when 0")

            let reread = try PptxReader.read(from: url)
            let picture = try #require(reread.slides[0].pictures.first)
            #expect(picture.rotation == 0)
            #expect(picture.flipVertical == true)
            #expect(picture.flipHorizontal == false)
        }
    }

    // MARK: - Scenario: a rotated nested group

    @Test func `A rotated nested group preserves rotation at every depth`() throws {
        var pres = PptxWriter.createNew()
        pres.slides[0].elements = [
            .group(GroupShape(
                id: 10, name: "Outer", rotation: Self.degrees(12),
                elements: [
                    .group(GroupShape(
                        id: 11, name: "Inner", rotation: Self.degrees(313), flipHorizontal: true,
                        elements: [
                            .shape(Shape(id: 12, name: "Deep shape", rotation: Self.degrees(90), flipVertical: true)),
                        ]
                    )),
                ]
            )),
        ]

        try TemporaryPPTX.written(pres) { url in
            let package = try PackageInspector(url)
            defer { package.cleanup() }
            #expect(try package.integrityViolations() == [])

            let reread = try PptxReader.read(from: url)
            let outer = try #require(reread.slides[0].elements.first.flatMap { element -> GroupShape? in
                if case .group(let g) = element { return g }
                return nil
            })
            #expect(outer.rotation == Self.degrees(12))
            #expect(outer.flipHorizontal == false)

            let inner = try #require(outer.elements.first.flatMap { element -> GroupShape? in
                if case .group(let g) = element { return g }
                return nil
            })
            #expect(inner.rotation == Self.degrees(313))
            #expect(inner.flipHorizontal == true)
            #expect(inner.flipVertical == false)

            let deep = try #require(inner.elements.first.flatMap { element -> Shape? in
                if case .shape(let s) = element { return s }
                return nil
            })
            #expect(deep.rotation == Self.degrees(90))
            #expect(deep.flipVertical == true)
            #expect(deep.flipHorizontal == false)
        }
    }

    // MARK: - Scenario: a rotated table (graphicFrame)

    @Test func `A rotated table round-trips its rotation via p colon xfrm`() throws {
        var pres = PptxWriter.createNew()
        pres.slides[0].elements = [
            .graphicFrame(GraphicFrame(
                id: 2, name: "Rotated table",
                position: Position(x: 0, y: 0), size: Size(width: 1000, height: 1000),
                rotation: Self.degrees(45), flipHorizontal: true, flipVertical: true,
                table: DrawingTable(columns: [TableColumn(width: 1000)], rows: [TableRow(height: 1000, cells: [TableCell(text: "x")])])
            ))
        ]

        try TemporaryPPTX.written(pres) { url in
            let package = try PackageInspector(url)
            defer { package.cleanup() }
            #expect(try package.integrityViolations() == [])

            let slideXML = try package.xml("ppt/slides/slide1.xml")
            // graphicFrame's transform element is `p:xfrm`, not `a:xfrm` (ECMA-376
            // Part 1 §19.3.1.28) — same `CT_Transform2D` type, different prefix.
            let xfrm = try #require(try slideXML.nodes(forXPath: "//*[local-name()='graphicFrame']/*[local-name()='xfrm']").first as? XMLElement)
            #expect(xfrm.attribute(forName: "rot")?.stringValue == "\(Self.degrees(45))")
            #expect(xfrm.attribute(forName: "flipH")?.stringValue == "1")
            #expect(xfrm.attribute(forName: "flipV")?.stringValue == "1")

            let reread = try PptxReader.read(from: url)
            let frame = try #require(reread.slides[0].elements.first.flatMap { element -> GraphicFrame? in
                if case .graphicFrame(let f) = element { return f }
                return nil
            })
            #expect(frame.rotation == Self.degrees(45))
            #expect(frame.flipHorizontal == true)
            #expect(frame.flipVertical == true)
        }
    }

    // MARK: - Scenario: negative and out-of-canonical-range rotation values normalize on write

    /// `ST_Angle` (ECMA-376 Part 1 §20.1.10.3) is an unrestricted `xsd:int` —
    /// nothing in the schema forbids a negative value or one at or beyond a
    /// full turn (`fullTurn` = 21,600,000). `PptxReader` accepts any such
    /// value as-is (never rejects a schema-valid `rot`), but `PptxWriter`
    /// normalizes into the canonical non-negative `[0, fullTurn)` range on
    /// write, because PowerPoint itself only ever emits values in that range
    /// and any value congruent modulo one full turn names the identical
    /// angle — see the "決定與理由" note in the issue report for the full
    /// reasoning; this test is the executable half of that decision.
    @Test(arguments: [
        (-Int(XfrmRotationFlipTests.degrees(30)), XfrmRotationFlipTests.degrees(330)),   // -30° ≡ 330°
        (XfrmRotationFlipTests.fullTurn + XfrmRotationFlipTests.degrees(10), XfrmRotationFlipTests.degrees(10)), // 370° ≡ 10°
        (-XfrmRotationFlipTests.fullTurn, 0),  // -360° ≡ 0° (and 0 stays omitted)
    ])
    func `Out of canonical range rotation values normalize to an equivalent angle on write`(raw: Int, expectedNormalized: Int) throws {
        var pres = PptxWriter.createNew()
        pres.slides[0].elements = [.shape(Shape(id: 2, name: "s", rotation: raw))]

        try TemporaryPPTX.written(pres) { url in
            let package = try PackageInspector(url)
            defer { package.cleanup() }
            let slideXML = try package.xml("ppt/slides/slide1.xml")
            let xfrm = try #require(try slideXML.nodes(forXPath: "//*[local-name()='sp']/*[local-name()='spPr']/*[local-name()='xfrm']").first as? XMLElement)
            let writtenRot = xfrm.attribute(forName: "rot")?.stringValue
            if expectedNormalized == 0 {
                #expect(writtenRot == nil, "normalized 0° must be omitted like any other unrotated element")
            } else {
                #expect(writtenRot == "\(expectedNormalized)")
            }

            let reread = try PptxReader.read(from: url)
            let shape = try #require(reread.slides[0].shapes.first)
            #expect(shape.rotation == expectedNormalized)
        }
    }

    // MARK: - Scenario: unrotated, unflipped elements produce byte-identical `xfrm` opening tags

    /// Before #7, `Shape`／`Picture`／`GraphicFrame`／`GroupShape` had no
    /// rotation or flip fields at all, so every `<a:xfrm>`／`<p:xfrm>`
    /// opening tag the writer emitted was exactly that literal string with
    /// no attributes. This test locks that in: an element left at its
    /// (still 0／false／false) defaults must keep producing the identical
    /// literal opening tag, byte for byte — not `<a:xfrm rot="0">` or any
    /// other spelling that happens to mean the same thing.
    @Test func `Elements without rotation or flip keep the exact pre existing xfrm opening tags`() throws {
        var pres = PptxWriter.createNew()
        pres.images = [MediaFile(id: "photo.png", fileName: "photo.png", data: try GeneratedImage.png(width: 4, height: 4))]
        pres.slides[0].elements = [
            .shape(Shape(id: 2, name: "s")),
            .picture(Picture(id: 3, name: "p", mediaFileName: "photo.png")),
            .graphicFrame(GraphicFrame(id: 4, name: "f", table: DrawingTable(
                columns: [TableColumn(width: 1000)], rows: [TableRow(height: 1000, cells: [TableCell(text: "x")])]
            ))),
            .group(GroupShape(id: 5, name: "g", elements: [.shape(Shape(id: 6, name: "child"))])),
        ]

        try TemporaryPPTX.written(pres) { url in
            let package = try PackageInspector(url)
            defer { package.cleanup() }
            #expect(try package.integrityViolations() == [])

            let slideXML = try Data(contentsOf: package.root.appendingPathComponent("ppt/slides/slide1.xml"))
            let slideText = try #require(String(data: slideXML, encoding: .utf8))
            let openingTags = slideText
                .components(separatedBy: "<a:xfrm>")
            #expect(openingTags.count - 1 == 4, "expected 4 literal '<a:xfrm>' opens (shape, picture, group, group's child shape), got \(openingTags.count - 1) in: \(slideText)")
            #expect(slideText.contains("<p:xfrm>\n"), "graphicFrame's p:xfrm must stay the exact pre-existing literal opening tag")
            #expect(!slideText.contains("rot=\""))
            #expect(!slideText.contains("flipH=\""))
            #expect(!slideText.contains("flipV=\""))
        }
    }

    // MARK: - Scenario: real fixture — cropped.pptx's nested groups carry real rotation

    /// `cropped.pptx` (Apache POI `CroppedBitmap.pptx`, already used by
    /// `GroupShapeWriteTests`) has three real, non-zero `rot` values baked
    /// in by PowerPoint itself: the outer group (`755916` ≈ 12.6°) and its
    /// two inner groups (`18792219` ≈ 313.2°, `1981530` ≈ 33.0°) — #5's
    /// "已知限制" section named these exact values as the rotation this
    /// fixture would silently lose before #7. This is the regression test
    /// for that specific, real-world loss.
    @Test func `cropped pptx's group rotations survive a round trip`() throws {
        let source = try #require(RealFileTests.fixturePath("cropped.pptx"))
        let original = try PptxReader.read(from: source)

        func groupRotations(_ elements: [SlideElement]) -> [Int] {
            elements.flatMap { element -> [Int] in
                switch element {
                case .group(let g): return [g.rotation] + groupRotations(g.elements)
                default: return []
                }
            }
        }

        let originalRotations = groupRotations(original.slides[0].elements).sorted()
        try #require(originalRotations == [755_916, 1_981_530, 18_792_219],
                      "fixture assumption: cropped.pptx's 3 groups carry exactly these rot values")

        try TemporaryPPTX.written(original, "cropped-rot-rt") { url in
            let package = try PackageInspector(url)
            defer { package.cleanup() }
            #expect(try package.integrityViolations() == [])

            let reread = try PptxReader.read(from: url)
            let rereadRotations = groupRotations(reread.slides[0].elements).sorted()
            #expect(rereadRotations == originalRotations)
        }
    }
}
