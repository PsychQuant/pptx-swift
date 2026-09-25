import Testing
import Foundation
import OOXMLSwift
@testable import PPTXSwift

/// #12 審查 R3：M-1'（包在 `mc:AlternateContent` 裡的表格被說成圖表類物件、原因
/// 寫錯、屬性重複列出）、L-1'（id 重複）。
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
}
