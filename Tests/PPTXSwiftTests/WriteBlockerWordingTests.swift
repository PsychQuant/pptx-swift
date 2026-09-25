import Testing
import Foundation
import OOXMLSwift
@testable import PPTXSwift

/// #12 審查 R3：M-1'（包在 `mc:AlternateContent` 裡的表格被說成圖表類物件、原因
/// 寫錯、屬性重複列出）、L-1'（id 重複）、L-3'（根元素的命名空間）。
struct WriteBlockerWordingTests {
    static let nsA = "http://schemas.openxmlformats.org/drawingml/2006/main"
    static let tableURI = "http://schemas.openxmlformats.org/drawingml/2006/table"

    /// 審查者在真實檔案看到的形狀：`mc:AlternateContent` 的 Choice 與 Fallback 都是
    /// 表格 graphicFrame（同一個 `cNvPr id=4`），儲存格用圖片填色而帶 `r:embed`。
    static func tableFrame(cellImages: Int) -> String {
        let cells = (0..<cellImages).map { _ in
            "<a:tc><a:txBody><a:bodyPr/><a:lstStyle/><a:p/></a:txBody><a:tcPr><a:blipFill><a:blip r:embed=\"rId2\"/><a:stretch><a:fillRect/></a:stretch></a:blipFill></a:tcPr></a:tc>"
        }.joined()
        return "<p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id=\"4\" name=\"表格 3\"/><p:cNvGraphicFramePr/><p:nvPr/></p:nvGraphicFramePr>"
            + "<p:xfrm><a:off x=\"914400\" y=\"914400\"/><a:ext cx=\"4572000\" cy=\"914400\"/></p:xfrm>"
            + "<a:graphic><a:graphicData uri=\"\(tableURI)\"><a:tbl><a:tblGrid><a:gridCol w=\"914400\"/></a:tblGrid>"
            + "<a:tr h=\"370840\">\(cells)</a:tr></a:tbl></a:graphicData></a:graphic></p:graphicFrame>"
    }

    static var alternateContentTable: String {
        "<mc:AlternateContent xmlns:mc=\"http://schemas.openxmlformats.org/markup-compatibility/2006\">"
            + "<mc:Choice xmlns:a14=\"http://schemas.microsoft.com/office/drawing/2010/main\" Requires=\"a14\">" + tableFrame(cellImages: 8) + "</mc:Choice>"
            + "<mc:Fallback>" + tableFrame(cellImages: 8) + "</mc:Fallback></mc:AlternateContent>"
    }

    // MARK: - M-1'

    @Test func `A table wrapped in mc colon AlternateContent is called a table with a neutral reason`() throws {
        let pres = try SpPrProbePackage.read(withPictures: false, extraShapeTreeXML: Self.alternateContentTable)
        let message = try #require(pres.writeBlockers.first).description
        #expect(message.contains("表格 id=4「表格 3」"), "\(message)")
        #expect(!message.contains("圖表、SmartArt"), "a table is not a chart-like object: \(message)")
        #expect(!message.contains("另一個 part"), "a table's content lives in the slide, not in another part: \(message)")
        #expect(message.components(separatedBy: "r:embed").count - 1 == 1, "each attribute name once, not 16 times: \(message)")
    }

    @Test func `A raw element lists each of its ids once`() throws {
        let pres = try SpPrProbePackage.read(withPictures: false, extraShapeTreeXML: Self.alternateContentTable)
        let raw = try #require(pres.slides[0].elements.compactMap { element -> RawSlideElement? in
            if case .raw(let r) = element { return r }
            return nil
        }.first)
        #expect(raw.elementIds == [4], "Choice and Fallback both declare cNvPr id=4")
    }

    // MARK: - L-3'

    @Test(arguments: [
        "<a:noFill xmlns:a=\"urn:example:not-drawingml\"/>",
        "<p:noFill/>",
    ])
    func `A raw fill root in the wrong namespace is refused even when the name matches`(xml: String) throws {
        var pres = PptxWriter.createNew()
        pres.slides[0].elements = [.shape(Shape(id: 2, name: "s", fill: .raw(xml)))]
        #expect(pres.writeBlockers.count == 1, "\(pres.writeBlockers)")
        let url = TemporaryPPTX.url("r3-ns")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: PPTXError.self) { try PptxWriter.write(pres, to: url) }
    }

    @Test func `A hand-built p colon style in the PresentationML namespace still passes`() throws {
        var shape = Shape(id: 2, name: "s")
        shape.styleXML = "<p:style><a:lnRef idx=\"1\"><a:schemeClr val=\"accent1\"/></a:lnRef><a:fillRef idx=\"0\"><a:schemeClr val=\"accent1\"/></a:fillRef><a:effectRef idx=\"0\"><a:schemeClr val=\"accent1\"/></a:effectRef><a:fontRef idx=\"minor\"><a:schemeClr val=\"tx1\"/></a:fontRef></p:style>"
        var pres = PptxWriter.createNew()
        pres.slides[0].elements = [.shape(shape)]
        #expect(pres.writeBlockers.isEmpty, "\(pres.writeBlockers)")
    }
}
