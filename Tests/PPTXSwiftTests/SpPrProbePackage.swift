import Foundation
import OOXMLSwift
@testable import PPTXSwift

/// 獨立審查（#11／#12 的對抗式審查）用來重現 spPr 保真問題的探測簡報，改寫成
/// 正式的測試素材：以 `cropped.pptx` 為底，在投影片 1 的 `p:spTree` 尾端加入
/// 八個元素，每一個對應審查報告的一個失敗情境——
///
/// | id | 名稱 | 情境 |
/// |---|---|---|
/// | 20 | `BlipFillShape` | 形狀以圖片填色（`a:blipFill r:embed="rId2"`，指向另加的 image2） |
/// | 21 | `NoOutline` | `<a:ln w="76200"><a:noFill/></a:ln>`＋`p:style`（`lnRef idx=2`） |
/// | 22 | `RedOutline` | 紅色 6pt 外框＋`p:style` |
/// | 23 | `SysClrFill` | `<a:solidFill><a:sysClr val="window"/>`＋`p:style`（`fillRef idx=1`） |
/// | 24 | `Gradient` | `a:gradFill` |
/// | 25 | `Chevron` | `prst="chevron"`（不在 `ShapeGeometry` 列舉內） |
/// | 26 | `RoundRectAdj` | `roundRect`＋`<a:gd name="adj" fmla="val 50000"/>` |
/// | 27 | `Conn` | 連接線：`<a:ln w="38100">` 的 `schemeClr tx1`＋`p:style`（`lnRef accent1`） |
///
/// `withPictures == true` 時保留投影片原有的兩張 `p:pic`（改指向 `rId3`），
/// 讓圖片填色形狀的 `rId2` 與 writer 重新配給圖片的 `rId2` 撞號——這正是審查
/// 實測到「形狀顯示成另一張圖」的情境。`false` 時移除所有 `p:pic`，形狀的
/// `rId2` 在寫出後會變成懸空參照。
enum SpPrProbePackage {
    static let styleXML =
        "<p:style><a:lnRef idx=\"2\"><a:schemeClr val=\"accent1\"><a:shade val=\"50000\"/></a:schemeClr></a:lnRef>"
        + "<a:fillRef idx=\"1\"><a:schemeClr val=\"accent1\"/></a:fillRef><a:effectRef idx=\"0\"><a:schemeClr val=\"accent1\"/></a:effectRef>"
        + "<a:fontRef idx=\"minor\"><a:schemeClr val=\"lt1\"/></a:fontRef></p:style>"

    static let rectGeometry = "<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom>"

    static func shapeXML(id: Int, name: String, spPrInner: String, style: Bool = true, line: String = "", spPrAttributes: String = "") -> String {
        "<p:sp><p:nvSpPr><p:cNvPr id=\"\(id)\" name=\"\(name)\"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>"
            + "<p:spPr\(spPrAttributes)><a:xfrm><a:off x=\"\(4_572_000 + (id % 2) * 2_286_000)\" y=\"\(274_320 + ((id - 20) / 2) * 1_188_720)\"/><a:ext cx=\"2011680\" cy=\"914400\"/></a:xfrm>"
            + spPrInner + line + "</p:spPr>"
            + (style ? styleXML : "")
            + "<p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:endParaRPr lang=\"en-US\"/></a:p></p:txBody></p:sp>"
    }

    static func connectorXML(id: Int, name: String, line: String, spPrExtra: String = "") -> String {
        "<p:cxnSp><p:nvCxnSpPr><p:cNvPr id=\"\(id)\" name=\"\(name)\"/><p:cNvCxnSpPr/><p:nvPr/></p:nvCxnSpPr>"
            + "<p:spPr><a:xfrm><a:off x=\"6858000\" y=\"5212080\"/><a:ext cx=\"2011680\" cy=\"0\"/></a:xfrm>"
            + "<a:prstGeom prst=\"line\"><a:avLst/></a:prstGeom>" + spPrExtra + line + "</p:spPr>"
            + "<p:style><a:lnRef idx=\"1\"><a:schemeClr val=\"accent1\"/></a:lnRef><a:fillRef idx=\"0\"><a:schemeClr val=\"accent1\"/></a:fillRef>"
            + "<a:effectRef idx=\"0\"><a:schemeClr val=\"accent1\"/></a:effectRef><a:fontRef idx=\"minor\"><a:schemeClr val=\"tx1\"/></a:fontRef></p:style></p:cxnSp>"
    }

    /// 審查報告的八個探測元素。
    static let reviewProbeElements: String = [
        shapeXML(id: 20, name: "BlipFillShape",
                 spPrInner: rectGeometry + "<a:blipFill><a:blip r:embed=\"rId2\"/><a:stretch><a:fillRect/></a:stretch></a:blipFill>",
                 style: false),
        shapeXML(id: 21, name: "NoOutline",
                 spPrInner: rectGeometry + "<a:solidFill><a:srgbClr val=\"FFFF00\"/></a:solidFill>",
                 line: "<a:ln w=\"76200\"><a:noFill/></a:ln>"),
        shapeXML(id: 22, name: "RedOutline",
                 spPrInner: rectGeometry + "<a:solidFill><a:srgbClr val=\"FFFF00\"/></a:solidFill>",
                 line: "<a:ln w=\"76200\"><a:solidFill><a:srgbClr val=\"FF0000\"/></a:solidFill></a:ln>"),
        shapeXML(id: 23, name: "SysClrFill",
                 spPrInner: rectGeometry + "<a:solidFill><a:sysClr val=\"window\" lastClr=\"FFFFFF\"/></a:solidFill>"),
        shapeXML(id: 24, name: "Gradient",
                 spPrInner: rectGeometry + "<a:gradFill><a:gsLst><a:gs pos=\"0\"><a:srgbClr val=\"FF0000\"/></a:gs><a:gs pos=\"100000\"><a:srgbClr val=\"0000FF\"/></a:gs></a:gsLst><a:lin ang=\"0\" scaled=\"0\"/></a:gradFill>",
                 style: false),
        shapeXML(id: 25, name: "Chevron",
                 spPrInner: "<a:prstGeom prst=\"chevron\"><a:avLst/></a:prstGeom><a:solidFill><a:srgbClr val=\"00FF00\"/></a:solidFill>",
                 style: false),
        shapeXML(id: 26, name: "RoundRectAdj",
                 spPrInner: "<a:prstGeom prst=\"roundRect\"><a:avLst><a:gd name=\"adj\" fmla=\"val 50000\"/></a:avLst></a:prstGeom><a:solidFill><a:srgbClr val=\"00FF00\"/></a:solidFill>",
                 style: false),
        connectorXML(id: 27, name: "Conn",
                     line: "<a:ln w=\"38100\"><a:solidFill><a:schemeClr val=\"tx1\"/></a:solidFill></a:ln>"),
    ].joined()

    /// 同上，但圖片填色形狀不帶 `r:embed`——給不測 relationship 防護、只測
    /// 其他元素保真度的案例用（否則整份會因 C1 防護而無法存檔）。
    static let reviewProbeElementsWithoutRelationships: String =
        reviewProbeElements.replacingOccurrences(of: " r:embed=\"rId2\"", with: "")

    /// 以 `cropped.pptx` 為底建出探測簡報，回傳暫存檔 URL（呼叫端負責刪除）。
    /// `extraShapeTreeXML` 附加在 `p:spTree` 結尾；`extraNamespaces` 加在
    /// `<p:sld>` 根節點上（給需要 `c:`、`mc:` 等前綴的片段用）。
    static func build(
        withPictures: Bool,
        extraShapeTreeXML: String = reviewProbeElements,
        extraNamespaces: String = "",
        label: String = "sppr-probe"
    ) throws -> URL {
        guard let source = RealFileTests.fixturePath("cropped.pptx") else {
            throw PPTXError.fileNotFound("Tests/Fixtures/cropped.pptx")
        }
        let unpacked = try ZipHelper.unzip(source)
        defer { ZipHelper.cleanup(unpacked) }

        let slidePath = unpacked.appendingPathComponent("ppt/slides/slide1.xml")
        var slide = try String(contentsOf: slidePath, encoding: .utf8)
        if withPictures {
            slide = slide.replacingOccurrences(of: "r:embed=\"rId2\"", with: "r:embed=\"rId3\"")
        } else {
            slide = slide.replacingOccurrences(of: #"(?s)<p:pic>.*?</p:pic>"#, with: "", options: .regularExpression)
        }
        guard let treeEnd = slide.range(of: "</p:spTree>") else {
            throw PPTXError.parseError("fixture assumption: slide1.xml has a literal </p:spTree>")
        }
        slide.replaceSubrange(treeEnd, with: extraShapeTreeXML + "</p:spTree>")
        if !extraNamespaces.isEmpty, let root = slide.range(of: "<p:sld ") {
            slide.replaceSubrange(root, with: "<p:sld " + extraNamespaces + " ")
        }
        try slide.write(to: slidePath, atomically: true, encoding: .utf8)

        let relsPath = unpacked.appendingPathComponent("ppt/slides/_rels/slide1.xml.rels")
        let imageType = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/image"
        let rels = try String(contentsOf: relsPath, encoding: .utf8).replacingOccurrences(
            of: "<Relationship Id=\"rId2\" Type=\"\(imageType)\" Target=\"../media/image1.png\"/>",
            with: "<Relationship Id=\"rId2\" Type=\"\(imageType)\" Target=\"../media/image2.png\"/>"
                + "<Relationship Id=\"rId3\" Type=\"\(imageType)\" Target=\"../media/image1.png\"/>")
        try rels.write(to: relsPath, atomically: true, encoding: .utf8)
        try GeneratedImage.png(width: 8, height: 8)
            .write(to: unpacked.appendingPathComponent("ppt/media/image2.png"))

        let url = TemporaryPPTX.url(label)
        try ZipHelper.zip(unpacked, to: url)
        return url
    }

    /// 讀取探測簡報（讀完即刪除暫存檔）。
    static func read(withPictures: Bool, extraShapeTreeXML: String = reviewProbeElements, extraNamespaces: String = "") throws -> Presentation {
        let url = try build(withPictures: withPictures, extraShapeTreeXML: extraShapeTreeXML, extraNamespaces: extraNamespaces)
        defer { try? FileManager.default.removeItem(at: url) }
        return try PptxReader.read(from: url)
    }

    /// 投影片 1 上名稱為 `name` 的 `p:sp`／`p:cxnSp` 在寫出後的 `spPr`。
    static func writtenSpPr(named name: String, in package: PackageInspector) throws -> XMLElement? {
        let slide = try package.xml("ppt/slides/slide1.xml")
        return try slide.nodes(forXPath: "//*[local-name()='cNvPr'][@name='\(name)']/../../*[local-name()='spPr']").first as? XMLElement
    }
}

extension Slide {
    /// 測試用：頂層元素中名稱為 `name` 的形狀索引與值。
    func shapeIndex(named name: String) -> (Int, Shape)? {
        for (i, element) in elements.enumerated() {
            if case .shape(let shape) = element, shape.name == name { return (i, shape) }
        }
        return nil
    }

    /// 測試用：頂層元素中名稱為 `name` 的連接線索引與值。
    func connectorIndex(named name: String) -> (Int, Connector)? {
        for (i, element) in elements.enumerated() {
            if case .connector(let connector) = element, connector.name == name { return (i, connector) }
        }
        return nil
    }
}
