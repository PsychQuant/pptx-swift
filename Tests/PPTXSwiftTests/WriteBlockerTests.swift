import Testing
import Foundation
import OOXMLSwift
@testable import PPTXSwift

/// `Presentation.writeBlockers`（#12 審查 C1）：寫出前能查到的拒絕存檔原因，依
/// 「目前」的模型狀態判斷；以及 writer 對整張投影片輸出的最後防線
/// （`PptxWriter.strayRelationshipReferences`）。
struct WriteBlockerTests {
    static let nsA = "http://schemas.openxmlformats.org/drawingml/2006/main"
    static let nsR = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"

    @Test func `The probe lists exactly the picture-filled shape as a blocker`() throws {
        let pres = try SpPrProbePackage.read(withPictures: true)
        #expect(pres.writeBlockers == [
            WriteBlocker(slideIndex: 0, element: .shape, elementId: 20, elementName: "BlipFillShape",
                         reason: .relationshipReference(part: .fill, attributes: ["r:embed"])),
        ])
    }

    /// 會帶圖片引用的原樣片段不只填色：`effectDag` 的 `a:blend`／`a:fillOverlay`、
    /// `extLst` 裡的 `a14:hiddenFill`、群組的 `grpSpPr` 填色都可能帶 `a:blip r:embed`。
    /// 前綴用 `rel:` 而不是 `r:`——判斷看命名空間，不看前綴字串。
    @Test func `Relationship references in every passthrough field are found by namespace not prefix`() throws {
        let blip = "<a:blip xmlns:rel=\"\(Self.nsR)\" rel:embed=\"rId7\"/>"
        var shape = Shape(id: 2, name: "s")
        shape.extLstXML = "<a:extLst xmlns:a=\"\(Self.nsA)\"><a:ext uri=\"{909E8E84-426E-40DD-AFC4-6F175D3DCCD1}\"><a14:hiddenFill xmlns:a14=\"http://schemas.microsoft.com/office/drawing/2010/main\"><a:blipFill>\(blip)</a:blipFill></a14:hiddenFill></a:ext></a:extLst>"
        var connector = Connector(id: 3, name: "c")
        connector.effectXML = "<a:effectDag xmlns:a=\"\(Self.nsA)\"><a:fillOverlay blend=\"over\"><a:blipFill>\(blip)</a:blipFill></a:fillOverlay></a:effectDag>"
        let group = GroupShape(id: 4, name: "g", elements: [.shape(Shape(id: 5, name: "child"))],
                               fill: .raw("<a:blipFill xmlns:a=\"\(Self.nsA)\">\(blip)</a:blipFill>"))
        var pres = PptxWriter.createNew()
        pres.slides[0].elements = [.shape(shape), .connector(connector), .group(group)]

        let found = pres.writeBlockers.map { ($0.elementId, $0.reason) }
        #expect(found.count == 3, "\(pres.writeBlockers)")
        #expect(found.contains { $0.0 == 2 && $0.1 == .relationshipReference(part: .extensionList, attributes: ["rel:embed"]) })
        #expect(found.contains { $0.0 == 3 && $0.1 == .relationshipReference(part: .effects, attributes: ["rel:embed"]) })
        #expect(found.contains { $0.0 == 4 && $0.1 == .relationshipReference(part: .fill, attributes: ["rel:embed"]) })

        let url = TemporaryPPTX.url("blockers-all")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: PPTXError.self) { try PptxWriter.write(pres, to: url) }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    /// 一個剛好叫 `r` 但綁到別的命名空間的前綴不是 relationship 引用。
    @Test func `An r prefix bound to another namespace is not a relationship reference`() throws {
        var shape = Shape(id: 2, name: "s")
        shape.extLstXML = "<a:extLst xmlns:a=\"\(Self.nsA)\"><a:ext uri=\"{X}\"><x:thing xmlns:x=\"urn:x\" xmlns:r=\"urn:not-relationships\" r:id=\"rId1\"/></a:ext></a:extLst>"
        var pres = PptxWriter.createNew()
        pres.slides[0].elements = [.shape(shape)]
        #expect(pres.writeBlockers == [])
        try TemporaryPPTX.written(pres, "blockers-foreign-r") { _ in }
    }

    @Test func `Blockers are judged on the current state, nested groups included`() throws {
        let blipFill = "<a:blipFill xmlns:a=\"\(Self.nsA)\" xmlns:r=\"\(Self.nsR)\"><a:blip r:embed=\"rId2\"/></a:blipFill>"
        var pres = PptxWriter.createNew()
        pres.slides[0].elements = [.group(GroupShape(id: 10, name: "outer", elements: [
            .group(GroupShape(id: 11, name: "inner", elements: [.shape(Shape(id: 12, name: "deep", fill: .raw(blipFill)))])),
        ]))]
        #expect(pres.writeBlockers.map(\.elementId) == [12])

        guard case .group(var outer) = pres.slides[0].elements[0], case .group(var inner) = outer.elements[0],
              case .shape(var deep) = inner.elements[0] else {
            Issue.record("unexpected structure")
            return
        }
        deep.fill = .noFill
        inner.elements[0] = .shape(deep)
        outer.elements[0] = .group(inner)
        pres.slides[0].elements[0] = .group(outer)
        #expect(pres.writeBlockers == [])
        try TemporaryPPTX.written(pres, "blockers-cleared") { url in
            let package = try PackageInspector(url)
            defer { package.cleanup() }
            #expect(try package.integrityViolations() == [])
        }
    }

    @Test func `A hand-built raw element that understates referencesRelationship is still refused`() throws {
        var pres = PptxWriter.createNew()
        pres.slides[0].elements = [.raw(RawSlideElement(
            localName: "contentPart",
            xml: "<p:contentPart xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\" xmlns:r=\"\(Self.nsR)\" r:id=\"rId5\"/>",
            elementIds: [], referencesRelationship: false))]
        #expect(pres.writeBlockers.count == 1)
        let url = TemporaryPPTX.url("blockers-understated")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: PPTXError.self) { try PptxWriter.write(pres, to: url) }
    }

    @Test func `A malformed passthrough fragment is refused instead of producing an invalid slide`() throws {
        var shape = Shape(id: 2, name: "s")
        shape.effectXML = "<a:effectLst><a:outerShdw>"
        var pres = PptxWriter.createNew()
        pres.slides[0].elements = [.shape(shape)]
        #expect(pres.writeBlockers.map(\.reason) == [.malformedPassthroughXML(part: .effects, detail: "無法解析")])
        #expect(pres.writeBlockers.first?.description.contains("spPr 的效果的原樣 XML 無法解析") == true,
                "\(pres.writeBlockers)")
    }

    @Test(arguments: [ShapeGeometry.unknown, .custom])
    func `A sentinel preset geometry is refused`(geometry: ShapeGeometry) throws {
        var shape = Shape(id: 2, name: "s")
        shape.geometry = geometry
        var pres = PptxWriter.createNew()
        pres.slides[0].elements = [.shape(shape)]
        #expect(pres.writeBlockers.map(\.reason) == [.invalidPresetGeometry(prst: geometry.rawValue)])
        let url = TemporaryPPTX.url("blockers-sentinel")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: PPTXError.self) { try PptxWriter.write(pres, to: url) }
    }

    // MARK: - The writer's last line of defense

    @Test func `strayRelationshipReferences accepts only a picture's own blip under spTree and groups`() throws {
        let root = "<p:sld xmlns:a=\"\(Self.nsA)\" xmlns:r=\"\(Self.nsR)\" xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\" xmlns:mc=\"http://schemas.openxmlformats.org/markup-compatibility/2006\"><p:cSld><p:spTree>"
        let pic = "<p:pic><p:blipFill><a:blip r:embed=\"rId2\" r:link=\"rId3\"/></p:blipFill></p:pic>"
        let ok = root + pic + "<p:grpSp><p:grpSp>" + pic + "</p:grpSp></p:grpSp></p:spTree></p:cSld></p:sld>"
        #expect(try PptxWriter.strayRelationshipReferences(inSlideXML: ok) == [])

        let shapeFill = root + "<p:sp><p:spPr><a:blipFill><a:blip r:embed=\"rId2\"/></a:blipFill></p:spPr></p:sp></p:spTree></p:cSld></p:sld>"
        #expect(try PptxWriter.strayRelationshipReferences(inSlideXML: shapeFill).count == 1)

        let alternate = root + "<mc:AlternateContent><mc:Choice Requires=\"a\">" + pic + "</mc:Choice></mc:AlternateContent></p:spTree></p:cSld></p:sld>"
        #expect(try PptxWriter.strayRelationshipReferences(inSlideXML: alternate).count == 2,
                "a picture inside passthrough content is not a picture the writer allocated for")
    }
}
