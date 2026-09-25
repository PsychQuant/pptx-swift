import Testing
import Foundation
import OOXMLSwift
@testable import PPTXSwift

/// PsychQuant/pptx-swift#12: `CT_ShapeProperties` (`p:spPr`) has several
/// optional children pptx-swift never modeled at all — `<a:custGeom>` (the
/// `EG_Geometry` alternative to `<a:prstGeom>`), `<a:gradFill>`/`<a:blipFill>`/
/// `<a:pattFill>`/`<a:grpFill>` (the `EG_FillProperties` alternatives to
/// `<a:noFill>`/`<a:solidFill>`), `<a:effectLst>`/`<a:effectDag>`
/// (`EG_EffectProperties`), `<a:scene3d>`, `<a:sp3d>`, and `<a:extLst>` — plus
/// `p:grpSpPr`'s own (smaller) subset of the same. Before this, any shape or
/// connector using one of these silently lost it on a round trip; discovered
/// via #11's investigation into `shapes.pptx`'s "Cloud" shape, which uses
/// `<a:custGeom>` and rendered as a plain rectangle after a round trip.
struct ShapePropertiesExtrasTests {
    private static let nsA = "http://schemas.openxmlformats.org/drawingml/2006/main"

    // MARK: - Scenario: a custom geometry is written instead of prstGeom (EG_Geometry is a choice)

    @Test func `A shapes custom geometry is written instead of prstGeom`() throws {
        let custGeom = "<a:custGeom xmlns:a=\"\(Self.nsA)\"><a:avLst/><a:gdLst/><a:ahLst/><a:cxnLst/><a:rect l=\"l\" t=\"t\" r=\"r\" b=\"b\"/><a:pathLst><a:path w=\"100\" h=\"100\"><a:moveTo><a:pt x=\"0\" y=\"0\"/></a:moveTo></a:path></a:pathLst></a:custGeom>"
        var shape = Shape(id: 2, name: "Cloud")
        shape.geometryDefinition = .custom(custGeom)
        #expect(shape.geometry == .custom)
        var pres = PptxWriter.createNew()
        pres.slides[0].elements = [.shape(shape)]

        try TemporaryPPTX.written(pres) { url in
            let package = try PackageInspector(url)
            defer { package.cleanup() }
            #expect(try package.integrityViolations() == [])

            let slideXML = try package.xml("ppt/slides/slide1.xml")
            let spPr = try #require(try slideXML.nodes(forXPath: "//*[local-name()='spPr']").first as? XMLElement)
            #expect(try spPr.nodes(forXPath: "*[local-name()='prstGeom']").isEmpty,
                     "a custom geometry must suppress prstGeom entirely — writing both is invalid (EG_Geometry is a choice)")
            let custGeomEl = try #require(try spPr.nodes(forXPath: "*[local-name()='custGeom']").first as? XMLElement)
            #expect(custGeomEl.uri == Self.nsA)
            #expect(try custGeomEl.nodes(forXPath: ".//*[local-name()='pathLst']").count == 1)
        }
    }

    @Test func `A preset geometry still writes prstGeom as before`() throws {
        var pres = PptxWriter.createNew()
        pres.slides[0].elements = [.shape(Shape(id: 2, name: "s", geometry: .ellipse))]
        try TemporaryPPTX.written(pres) { url in
            let package = try PackageInspector(url)
            defer { package.cleanup() }
            let slideXML = try package.xml("ppt/slides/slide1.xml")
            let spPr = try #require(try slideXML.nodes(forXPath: "//*[local-name()='spPr']").first as? XMLElement)
            #expect(try spPr.nodes(forXPath: "*[local-name()='custGeom']").isEmpty)
            let prstGeom = try #require(try spPr.nodes(forXPath: "*[local-name()='prstGeom']").first as? XMLElement)
            #expect(prstGeom.attribute(forName: "prst")?.stringValue == "ellipse")
        }
    }

    // MARK: - Scenario: typed and raw fill are one value — a typed setter replaces a raw fill

    /// Review finding H2: this test used to pin "raw wins over typed" as the
    /// expected behavior, which is exactly what made che-pptx-mcp's
    /// `set_shape_fill` a silent no-op on a gradient or picture-filled shape.
    /// Typed and raw are now the same field (`ShapeFill.raw`), so the state
    /// "both set" cannot exist: assigning a typed fill replaces the raw one.
    @Test func `A typed fill assigned after a raw fill wins`() throws {
        let gradFill = "<a:gradFill xmlns:a=\"\(Self.nsA)\"><a:gsLst><a:gs pos=\"0\"><a:srgbClr val=\"FF0000\"/></a:gs><a:gs pos=\"100000\"><a:srgbClr val=\"0000FF\"/></a:gs></a:gsLst></a:gradFill>"
        var shape = Shape(id: 2, name: "s", fill: .raw(gradFill))
        shape.fill = .solid(color: "00FF00")
        var pres = PptxWriter.createNew()
        pres.slides[0].elements = [.shape(shape)]
        try TemporaryPPTX.written(pres) { url in
            let package = try PackageInspector(url)
            defer { package.cleanup() }
            let slideXML = try package.xml("ppt/slides/slide1.xml")
            let spPr = try #require(try slideXML.nodes(forXPath: "//*[local-name()='spPr']").first as? XMLElement)
            #expect(try spPr.nodes(forXPath: "*[local-name()='gradFill']").isEmpty,
                     "the typed fill must replace the raw gradient, not be ignored")
            let srgb = try spPr.nodes(forXPath: "*[local-name()='solidFill']/*[local-name()='srgbClr']").first as? XMLElement
            #expect(srgb?.attribute(forName: "val")?.stringValue == "00FF00")
        }
    }

    @Test func `A raw fill is written verbatim`() throws {
        let gradFill = "<a:gradFill xmlns:a=\"\(Self.nsA)\"><a:gsLst><a:gs pos=\"0\"><a:srgbClr val=\"FF0000\"/></a:gs><a:gs pos=\"100000\"><a:srgbClr val=\"0000FF\"/></a:gs></a:gsLst></a:gradFill>"
        var pres = PptxWriter.createNew()
        pres.slides[0].elements = [.shape(Shape(id: 2, name: "s", fill: .raw(gradFill)))]
        try TemporaryPPTX.written(pres) { url in
            let package = try PackageInspector(url)
            defer { package.cleanup() }
            let slideXML = try package.xml("ppt/slides/slide1.xml")
            let spPr = try #require(try slideXML.nodes(forXPath: "//*[local-name()='spPr']").first as? XMLElement)
            let grad = try #require(try spPr.nodes(forXPath: "*[local-name()='gradFill']").first as? XMLElement)
            #expect(try grad.nodes(forXPath: ".//*[local-name()='gs']").count == 2)
        }
    }

    // MARK: - Scenario: effectXML / scene3dXML / sp3dXML / extLstXML all land inside spPr, in schema order, after ln

    @Test func `A connectors effect scene3d sp3d and extLst all land inside spPr after ln in schema order`() throws {
        var connector = Connector(id: 2, name: "c", outline: ShapeOutline(color: "FF0000", width: 12700))
        connector.effectXML = "<a:effectLst xmlns:a=\"\(Self.nsA)\"><a:outerShdw blurRad=\"40000\" dist=\"20000\" dir=\"5400000\"><a:srgbClr val=\"000000\"/></a:outerShdw></a:effectLst>"
        connector.scene3dXML = "<a:scene3d xmlns:a=\"\(Self.nsA)\"><a:camera prst=\"orthographicFront\"/><a:lightRig rig=\"threePt\" dir=\"t\"/></a:scene3d>"
        connector.sp3dXML = "<a:sp3d xmlns:a=\"\(Self.nsA)\"><a:bevelT/></a:sp3d>"
        connector.extLstXML = "<a:extLst xmlns:a=\"\(Self.nsA)\"><a:ext uri=\"{00000000-0000-0000-0000-000000000000}\"/></a:extLst>"

        var pres = PptxWriter.createNew()
        pres.slides[0].elements = [.connector(connector)]
        try TemporaryPPTX.written(pres) { url in
            let package = try PackageInspector(url)
            defer { package.cleanup() }
            #expect(try package.integrityViolations() == [])

            let slideXML = try package.xml("ppt/slides/slide1.xml")
            let spPr = try #require(try slideXML.nodes(forXPath: "//*[local-name()='spPr']").first as? XMLElement)
            let children = try spPr.nodes(forXPath: "*").compactMap { $0 as? XMLElement }
            let names = children.map { $0.localName ?? "" }
            #expect(names == ["xfrm", "prstGeom", "ln", "effectLst", "scene3d", "sp3d", "extLst"],
                     "CT_ShapeProperties sequence: xfrm, geometry, fill, ln, effect, scene3d, sp3d, extLst — got \(names)")
            for name in ["effectLst", "scene3d", "sp3d", "extLst"] {
                let el = try #require(children.first { $0.localName == name })
                #expect(el.uri == Self.nsA)
            }
        }
    }

    @Test func `None of the extras set means none of the extra tags appear`() throws {
        var pres = PptxWriter.createNew()
        pres.slides[0].elements = [.shape(Shape(id: 2, name: "s"))]
        try TemporaryPPTX.written(pres) { url in
            let package = try PackageInspector(url)
            defer { package.cleanup() }
            let slideXML = try package.xml("ppt/slides/slide1.xml")
            for name in ["custGeom", "gradFill", "blipFill", "pattFill", "grpFill", "effectLst", "effectDag", "scene3d", "sp3d", "extLst"] {
                #expect(try slideXML.nodes(forXPath: "//*[local-name()='\(name)']").isEmpty, "\(name) must not appear when unset")
            }
        }
    }

    // MARK: - Scenario: GroupShape's grpSpPr carries its own (smaller) subset

    @Test func `A group shapes fill effectXML scene3dXML and extLstXML land inside grpSpPr in schema order`() throws {
        var group = GroupShape(id: 2, name: "g", elements: [.shape(Shape(id: 3, name: "child"))])
        group.fill = .raw("<a:grpFill xmlns:a=\"\(Self.nsA)\"/>")
        group.effectXML = "<a:effectLst xmlns:a=\"\(Self.nsA)\"/>"
        group.scene3dXML = "<a:scene3d xmlns:a=\"\(Self.nsA)\"><a:camera prst=\"orthographicFront\"/></a:scene3d>"
        group.extLstXML = "<a:extLst xmlns:a=\"\(Self.nsA)\"/>"

        var pres = PptxWriter.createNew()
        pres.slides[0].elements = [.group(group)]
        try TemporaryPPTX.written(pres) { url in
            let package = try PackageInspector(url)
            defer { package.cleanup() }
            #expect(try package.integrityViolations() == [])

            let slideXML = try package.xml("ppt/slides/slide1.xml")
            // The slide root's own p:spTree also has an (always-empty)
            // p:grpSpPr — must target the p:grpSp's own, not match that one.
            let grpSpPr = try #require(
                try slideXML.nodes(forXPath: "//*[local-name()='grpSp']/*[local-name()='grpSpPr']").first as? XMLElement)
            let names = try grpSpPr.nodes(forXPath: "*").compactMap { ($0 as? XMLElement)?.localName }
            #expect(names == ["xfrm", "grpFill", "effectLst", "scene3d", "extLst"])
        }
    }

    // MARK: - Scenario: Slide.setGeometry (che-pptx-mcp's set_placeholder_geometry) does not clobber custGeom into a rect

    /// che-pptx-mcp's geometry-editing tools go through `Slide.setGeometry`.
    /// This goes all the way through `PptxReader` → `Slide.setGeometry` →
    /// `PptxWriter` → the written XML (not just the in-memory struct), so it
    /// fails if the writer stops emitting the custom path — the original
    /// version only checked value semantics on the struct and kept passing
    /// with #12's writer change reverted (review finding L5).
    @Test func `Slide setGeometry moves a custGeom shape without turning it into a rect`() throws {
        let source = try #require(RealFileTests.fixturePath("shapes.pptx"))
        var pres = try PptxReader.read(from: source)
        let cloudId = try #require(pres.slides[0].shapeIndex(named: "Freeform 6")?.1.id)

        try pres.slides[0].setGeometry(ofElementId: cloudId, xCm: 5, yCm: 6, widthCm: 7, heightCm: 8)

        try TemporaryPPTX.written(pres, "setgeom-custgeom") { url in
            let package = try PackageInspector(url)
            defer { package.cleanup() }
            #expect(try package.integrityViolations() == [])
            let spPr = try #require(try SpPrProbePackage.writtenSpPr(named: "Freeform 6", in: package))
            #expect(try spPr.nodes(forXPath: "*[local-name()='prstGeom']").isEmpty, "must not turn into a preset rect")
            let custGeom = try #require(try spPr.nodes(forXPath: "*[local-name()='custGeom']").first as? XMLElement,
                                        "the custom path must survive a geometry-only edit")
            #expect(try !custGeom.nodes(forXPath: ".//*[local-name()='cubicBezTo']").isEmpty)
            let off = try spPr.nodes(forXPath: "*[local-name()='xfrm']/*[local-name()='off']").first as? XMLElement
            let expectedX = try PPTXMetric.emu(fromCm: 5)
            let expectedY = try PPTXMetric.emu(fromCm: 6)
            #expect(off?.attribute(forName: "x")?.stringValue == "\(expectedX)")
            #expect(off?.attribute(forName: "y")?.stringValue == "\(expectedY)")
        }
    }

    // MARK: - Scenario: the real shapes.pptx fixture's Cloud shape (custGeom) round-trips its path

    @Test func `shapes pptx's Cloud shape keeps its custGeom path across a round trip`() throws {
        let source = try #require(RealFileTests.fixturePath("shapes.pptx"))
        let original = try PptxReader.read(from: source)

        let cloud = try #require(original.slides[0].elements.compactMap { element -> Shape? in
            if case .shape(let s) = element, s.name == "Freeform 6" { return s }
            return nil
        }.first, "fixture assumption: shapes.pptx has a shape named \"Freeform 6\"")
        guard case .custom(let custGeom) = cloud.geometryDefinition else {
            Issue.record("the Cloud shape lost its custGeom on read: \(cloud.geometryDefinition)")
            return
        }
        #expect(custGeom.contains("pathLst"))
        #expect(custGeom.contains("cubicBezTo"), "the Cloud shape's outline is drawn with cubic Bezier segments")

        try TemporaryPPTX.written(original, "custgeom-rt") { url in
            let package = try PackageInspector(url)
            defer { package.cleanup() }
            #expect(try package.integrityViolations() == [])

            let reread = try PptxReader.read(from: url)
            let rereadCloud = try #require(reread.slides[0].elements.compactMap { element -> Shape? in
                if case .shape(let s) = element, s.name == "Freeform 6" { return s }
                return nil
            }.first)
            guard case .custom(let rereadPath) = rereadCloud.geometryDefinition else {
                Issue.record("the Cloud shape lost its custGeom after a round trip")
                return
            }
            #expect(rereadPath.contains("pathLst"))
            #expect(rereadPath.contains("cubicBezTo"))

            // Never both — mutual exclusivity holds through a real fixture too,
            // not just the hand-built tests above.
            let slideXML = try package.xml("ppt/slides/slide1.xml")
            let spPrs = try slideXML.nodes(forXPath: "//*[local-name()='sp']/*[local-name()='spPr']")
            for node in spPrs {
                guard let spPr = node as? XMLElement else { continue }
                let hasCustGeom = try !spPr.nodes(forXPath: "*[local-name()='custGeom']").isEmpty
                let hasPrstGeom = try !spPr.nodes(forXPath: "*[local-name()='prstGeom']").isEmpty
                #expect(!(hasCustGeom && hasPrstGeom), "a single spPr must never carry both custGeom and prstGeom")
            }
        }
    }
}
