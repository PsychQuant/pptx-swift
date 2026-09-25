import Testing
import Foundation
import OOXMLSwift
@testable import PPTXSwift

/// PsychQuant/pptx-swift#15：非表格的 `p:graphicFrame`（圖表、SmartArt、OLE 物件）
/// 以前被讀成 `table == nil` 的 typed `.graphicFrame`，寫出時 `serializeGraphicFrame`
/// 遇到 `table == nil` 直接回傳空字串——圖表在存檔後靜默消失。這些 graphicFrame
/// 都靠 relationship（`c:chart r:id`、`dgm:relIds r:dm…`、`p:oleObj r:id`）指向
/// 另一個 part，因此改讀成 `.raw` 後會自然撞上 #9 的拒絕存檔防護：寧可明確拒絕，
/// 也不默默刪掉使用者的圖表。
struct NonTableGraphicFrameTests {
    static let chartFrame = """
    <p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id="30" name="Chart 1"/><p:cNvGraphicFramePr/><p:nvPr/></p:nvGraphicFramePr>\
    <p:xfrm><a:off x="914400" y="914400"/><a:ext cx="4572000" cy="2743200"/></p:xfrm>\
    <a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/chart">\
    <c:chart xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" r:id="rId9"/>\
    </a:graphicData></a:graphic></p:graphicFrame>
    """

    @Test func `A chart graphicFrame is read as a raw element that references a relationship`() throws {
        let pres = try SpPrProbePackage.read(withPictures: false, extraShapeTreeXML: Self.chartFrame)
        let raw = pres.slides[0].elements.compactMap { element -> RawSlideElement? in
            if case .raw(let r) = element { return r }
            return nil
        }
        let chart = try #require(raw.first { $0.localName == "graphicFrame" },
                                 "a chart graphicFrame must not become a typed graphicFrame with no table")
        #expect(chart.referencesRelationship)
        #expect(chart.elementIds == [30])
        #expect(pres.slides[0].tables.isEmpty)
    }

    @Test func `Saving a slide with a chart is refused instead of silently deleting the chart`() throws {
        let pres = try SpPrProbePackage.read(withPictures: false, extraShapeTreeXML: Self.chartFrame)
        let url = TemporaryPPTX.url("chart-refused")
        defer { try? FileManager.default.removeItem(at: url) }
        let error = #expect(throws: PPTXError.self) { try PptxWriter.write(pres, to: url) }
        guard case .writeError(let message)? = error else {
            Issue.record("expected .writeError, got \(String(describing: error))")
            return
        }
        #expect(message.contains("圖表 id=30"), "the message must say it is a chart, by id: \(message)")
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    /// 迴歸防護：表格的 graphicFrame 維持 typed（che-pptx-mcp 的表格工具靠它）。
    @Test func `A table graphicFrame stays typed`() throws {
        let source = try #require(RealFileTests.fixturePath("table.pptx"))
        let pres = try PptxReader.read(from: source)
        #expect(!pres.slides[0].tables.isEmpty)
        #expect(!pres.slides[0].elements.contains { if case .raw(let r) = $0 { return r.localName == "graphicFrame" } else { return false } })
    }

    /// 刪掉圖表之後就能存檔（拒絕是針對「目前狀態」，不是針對「讀進來的檔案」）。
    @Test func `Deleting the chart makes the slide savable`() throws {
        var pres = try SpPrProbePackage.read(withPictures: false, extraShapeTreeXML: Self.chartFrame)
        pres.slides[0].elements.removeAll { element in
            if case .raw(let r) = element { return r.elementIds.contains(30) }
            if case .graphicFrame(let f) = element { return f.id == 30 }
            return false
        }
        try TemporaryPPTX.written(pres, "chart-deleted") { url in
            let package = try PackageInspector(url)
            defer { package.cleanup() }
            #expect(try package.integrityViolations() == [])
        }
    }
}
