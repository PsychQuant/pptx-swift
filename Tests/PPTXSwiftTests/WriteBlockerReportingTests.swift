import Testing
import Foundation
import OOXMLSwift
@testable import PPTXSwift

/// #12 審查 R2 的 M-1、L-2、L-3、L-6、L-7：拒絕存檔的原因要讓呼叫端找得到、
/// 看得懂，而且原樣片段不能再有靜默寫錯、typed 值不能再有靜默消失的路徑。
@Suite(.serialized)
struct WriteBlockerReportingTests {
    static let nsA = "http://schemas.openxmlformats.org/drawingml/2006/main"

    /// 審查者的 `probe_grouped.pptx`：圖片填色形狀 id=20 包在群組 id=90 裡。
    static let groupedPictureFill = "<p:grpSp><p:nvGrpSpPr><p:cNvPr id=\"90\" name=\"Group 90\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>"
        + "<p:grpSpPr><a:xfrm><a:off x=\"4572000\" y=\"274320\"/><a:ext cx=\"2011680\" cy=\"914400\"/><a:chOff x=\"4572000\" y=\"274320\"/><a:chExt cx=\"2011680\" cy=\"914400\"/></a:xfrm></p:grpSpPr>"
        + SpPrProbePackage.shapeXML(
            id: 20, name: "BlipFillShape",
            spPrInner: SpPrProbePackage.rectGeometry + "<a:blipFill><a:blip r:embed=\"rId2\"/><a:stretch><a:fillRect/></a:stretch></a:blipFill>",
            style: false)
        + "</p:grpSp>"

    static func graphicFrame(id: Int, name: String, uri: String, body: String) -> String {
        "<p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id=\"\(id)\" name=\"\(name)\"/><p:cNvGraphicFramePr/><p:nvPr/></p:nvGraphicFramePr>"
            + "<p:xfrm><a:off x=\"914400\" y=\"914400\"/><a:ext cx=\"4572000\" cy=\"2743200\"/></p:xfrm>"
            + "<a:graphic><a:graphicData uri=\"\(uri)\">\(body)</a:graphicData></a:graphic></p:graphicFrame>"
    }

    static let chart = graphicFrame(
        id: 30, name: "Chart 1", uri: "http://schemas.openxmlformats.org/drawingml/2006/chart",
        body: "<c:chart xmlns:c=\"http://schemas.openxmlformats.org/drawingml/2006/chart\" r:id=\"rId9\"/>")
    static let smartArt = graphicFrame(
        id: 31, name: "Diagram 1", uri: "http://schemas.openxmlformats.org/drawingml/2006/diagram",
        body: "<dgm:relIds xmlns:dgm=\"http://schemas.openxmlformats.org/drawingml/2006/diagram\" r:dm=\"rId10\" r:lo=\"rId11\" r:qs=\"rId12\" r:cs=\"rId13\"/>")
    static let ole = graphicFrame(
        id: 32, name: "Object 1", uri: "http://schemas.openxmlformats.org/presentationml/2006/ole",
        body: "<p:oleObj spid=\"_x0000_s1\" name=\"Worksheet\" r:id=\"rId14\" imgW=\"100\" imgH=\"100\" progId=\"Excel.Sheet.12\"><p:embed/></p:oleObj>")
    static let unknownObject = graphicFrame(
        id: 33, name: "Thing 1", uri: "urn:example:unknown-graphic",
        body: "<x:thing xmlns:x=\"urn:example:unknown-graphic\" r:id=\"rId15\"/>")

    // MARK: - M-1：群組內元素的 blocker 要帶所屬群組

    @Test func `A blocker inside a group names the enclosing group`() throws {
        let pres = try SpPrProbePackage.read(withPictures: false, extraShapeTreeXML: Self.groupedPictureFill)
        let message = try #require(pres.writeBlockers.first).description
        #expect(message.contains("群組 id=90 內的形狀 id=20"), "the group the shape lives in must be named: \(message)")
    }

    @Test func `Nested groups give the full path and the outermost group as the top-level id`() throws {
        let blipFill = "<a:blipFill xmlns:a=\"\(Self.nsA)\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><a:blip r:embed=\"rId2\"/></a:blipFill>"
        var pres = PptxWriter.createNew()
        pres.slides[0].elements = [
            .shape(Shape(id: 2, name: "Title")),
            .group(GroupShape(id: 90, name: "Outer", elements: [
                .group(GroupShape(id: 91, name: "Inner", elements: [.shape(Shape(id: 20, name: "Deep", fill: .raw(blipFill)))])),
            ])),
        ]
        let blocker = try #require(pres.writeBlockers.first)
        #expect(pres.writeBlockers.count == 1)
        #expect(blocker.element == .shape)
        #expect(blocker.elementId == 20)
        #expect(blocker.enclosingGroupIds == [90, 91])
        #expect(blocker.topLevelElementId == 90)
        #expect(blocker.description.contains("群組 id=90 > 群組 id=91 內的形狀 id=20「Deep」"), "\(blocker.description)")
    }

    @Test func `A top-level blocker is its own top-level element`() throws {
        let pres = try SpPrProbePackage.read(withPictures: false)
        let blocker = try #require(pres.writeBlockers.first)
        #expect(blocker.enclosingGroupIds.isEmpty)
        #expect(blocker.topLevelElementId == 20)
    }

    // MARK: - L-2：原樣片段要恰好一個根元素，且根元素要合乎它的位置

    @Test(arguments: [
        "<a:noFill/><a:solidFill><a:srgbClr val=\"FF0000\"/></a:solidFill>",
        "<a:ln w=\"12700\"/>",
        "stray text <a:noFill/>",
    ])
    func `A raw fill that is not exactly one fill element is refused`(xml: String) throws {
        var pres = PptxWriter.createNew()
        pres.slides[0].elements = [.shape(Shape(id: 2, name: "s", fill: .raw(xml)))]
        let url = TemporaryPPTX.url("l2-raw")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: PPTXError.self, "a raw fill of \(xml) would write an invalid EG_FillProperties choice") {
            try PptxWriter.write(pres, to: url)
        }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func `A raw element with two root elements is refused`() throws {
        var pres = PptxWriter.createNew()
        pres.slides[0].elements = [.raw(RawSlideElement(
            localName: "AlternateContent",
            xml: "<mc:AlternateContent xmlns:mc=\"http://schemas.openxmlformats.org/markup-compatibility/2006\"/><mc:AlternateContent xmlns:mc=\"http://schemas.openxmlformats.org/markup-compatibility/2006\"/>"))]
        let url = TemporaryPPTX.url("l2-raw-element")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: PPTXError.self) { try PptxWriter.write(pres, to: url) }
    }

    // MARK: - L-3：沒有表格的 typed graphicFrame 不能靜默消失

    @Test func `A typed graphicFrame without a table is refused instead of vanishing`() throws {
        var pres = PptxWriter.createNew()
        pres.slides[0].elements = [.graphicFrame(GraphicFrame(id: 5, name: "Empty frame"))]
        let url = TemporaryPPTX.url("l3-empty-frame")
        defer { try? FileManager.default.removeItem(at: url) }
        let error = #expect(throws: PPTXError.self) { try PptxWriter.write(pres, to: url) }
        guard case .writeError(let message)? = error else {
            Issue.record("expected .writeError, got \(String(describing: error))")
            return
        }
        #expect(message.contains("id=5"), "\(message)")
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: - L-6：內嵌物件的種類要說人話

    @Test(arguments: [
        (chart, "圖表 id=30"),
        (smartArt, "SmartArt 圖形 id=31"),
        (ole, "OLE 內嵌物件 id=32"),
        (unknownObject, "圖表、SmartArt 或 OLE 等內嵌物件 id=33"),
    ])
    func `An embedded object blocker says what kind of object it is`(frame: String, expected: String) throws {
        let pres = try SpPrProbePackage.read(withPictures: false, extraShapeTreeXML: frame)
        let message = try #require(pres.writeBlockers.first).description
        #expect(message.contains(expected), "\(message)")
        #expect(!message.contains("<graphicFrame>"), "the raw tag name is not something a user can act on: \(message)")
    }

    /// 新版 PowerPoint 常把 OLE 物件包在 `mc:AlternateContent` 裡（Choice 是
    /// graphicFrame、Fallback 是圖片）；包起來的也要認得出來。
    @Test func `An OLE object wrapped in mc colon AlternateContent is still recognized`() throws {
        let wrapped = "<mc:AlternateContent xmlns:mc=\"http://schemas.openxmlformats.org/markup-compatibility/2006\">"
            + "<mc:Choice xmlns:v=\"urn:schemas-microsoft-com:vml\" Requires=\"v\">" + Self.ole + "</mc:Choice>"
            + "<mc:Fallback>" + Self.ole.replacingOccurrences(of: "id=\"32\"", with: "id=\"34\"") + "</mc:Fallback></mc:AlternateContent>"
        let pres = try SpPrProbePackage.read(withPictures: false, extraShapeTreeXML: wrapped)
        let raw = try #require(pres.slides[0].elements.compactMap { element -> RawSlideElement? in
            if case .raw(let r) = element { return r }
            return nil
        }.first)
        #expect(raw.localName == "AlternateContent")
        #expect(raw.embeddedObjectKind == .oleObject)
        let blocker = try #require(pres.writeBlockers.first)
        #expect(blocker.element == .embeddedObject(.oleObject))
        #expect(blocker.description.contains("OLE 內嵌物件 id=32"), "\(blocker.description)")
    }

    @Test func `An unmodeled element that is not an embedded object keeps its tag name`() throws {
        var pres = PptxWriter.createNew()
        pres.slides[0].elements = [.raw(RawSlideElement(
            localName: "contentPart",
            xml: "<p:contentPart xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" r:id=\"rId5\"/>",
            elementIds: [40], referencesRelationship: true))]
        let blocker = try #require(pres.writeBlockers.first)
        #expect(blocker.element == .unmodeled(localName: "contentPart"))
        #expect(blocker.description.contains("未建模元素 <contentPart> id=40：原樣 XML 引用了 relationship（r:id）"), "\(blocker.description)")
    }

    // MARK: - L-7：unsupportedMedia 依讀檔旗標，刪掉媒體元素不會解除

    @Test func `The unsupported media blocker follows the read-time flag, not the elements`() throws {
        var pres = PptxWriter.createNew()
        pres.slides[0] = Slide(elements: [], containsUnsupportedMedia: true)
        #expect(pres.writeBlockers.map(\.reason) == [.unsupportedMedia],
                "documented exception: removing media elements does not clear the flag")
        pres.slides[0].containsUnsupportedMedia = false
        #expect(pres.writeBlockers.isEmpty)
    }

    @Test func `setGeometry on a chart explains that charts cannot be moved yet`() throws {
        var pres = try SpPrProbePackage.read(withPictures: false, extraShapeTreeXML: Self.chart)
        let error = #expect(throws: PPTXError.self) {
            try pres.slides[0].setGeometry(ofElementId: 30, xCm: 1, yCm: 1, widthCm: 2, heightCm: 2)
        }
        let message = error?.errorDescription ?? ""
        #expect(message.contains("圖表"), "the error must cover charts, not only mc:AlternateContent／p:contentPart: \(message)")
    }
}
