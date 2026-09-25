import Testing
import Foundation
import OOXMLSwift
@testable import PPTXSwift

/// #11／#12 對抗式審查（VERDICT: FAIL）指出的 spPr 保真問題的回歸測試，素材是
/// 審查者的探測簡報（`SpPrProbePackage`）：
///
/// - H1：`spPr` 裡覆寫 `p:style` 的明確值（`<a:ln>`、非 srgb／scheme 的顏色、
///   色彩變換）必須保留。
/// - H2：typed setter 必須勝過讀進來的原樣內容，不能靜默變成 no-op。
/// - M1：不在 `ShapeGeometry` 列舉內的 `prst` 與 `Shape` 的 `avLst` 調整值保留。
/// - L1／L2：連接線的填色、`bwMode` 保留。
@Suite(.serialized)
struct ShapePropertiesFidelityTests {
    static let nsA = "http://schemas.openxmlformats.org/drawingml/2006/main"
    static let nsR = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"

    // MARK: - H2：typed setter 必須勝出

    @Test func `Setting a typed fill on a gradient shape read from a file replaces the gradient`() throws {
        var pres = try SpPrProbePackage.read(withPictures: false,
                                             extraShapeTreeXML: SpPrProbePackage.reviewProbeElementsWithoutRelationships)
        let (index, found) = try #require(pres.slides[0].shapeIndex(named: "Gradient"))
        var shape = found
        shape.fill = .solid(color: "00FF00")
        pres.slides[0].elements[index] = .shape(shape)

        try TemporaryPPTX.written(pres, "h2-grad") { url in
            let reread = try PptxReader.read(from: url)
            let (_, back) = try #require(reread.slides[0].shapeIndex(named: "Gradient"))
            guard case .solid(let color)? = back.fill else {
                Issue.record("expected the typed solid fill to win, got \(String(describing: back.fill))")
                return
            }
            #expect(color == "00FF00")
            let package = try PackageInspector(url)
            defer { package.cleanup() }
            let spPr = try #require(try SpPrProbePackage.writtenSpPr(named: "Gradient", in: package))
            #expect(try spPr.nodes(forXPath: "*[local-name()='gradFill']").isEmpty)
        }
    }

    @Test func `Setting a typed geometry on a custGeom shape replaces the custom path`() throws {
        let source = try #require(RealFileTests.fixturePath("shapes.pptx"))
        var pres = try PptxReader.read(from: source)
        let (index, found) = try #require(pres.slides[0].shapeIndex(named: "Freeform 6"))
        var shape = found
        shape.geometry = .ellipse
        pres.slides[0].elements[index] = .shape(shape)

        try TemporaryPPTX.written(pres, "h2-geom") { url in
            let package = try PackageInspector(url)
            defer { package.cleanup() }
            let spPr = try #require(try SpPrProbePackage.writtenSpPr(named: "Freeform 6", in: package))
            #expect(try spPr.nodes(forXPath: "*[local-name()='custGeom']").isEmpty, "the typed geometry must win")
            let prst = try spPr.nodes(forXPath: "*[local-name()='prstGeom']").first as? XMLElement
            #expect(prst?.attribute(forName: "prst")?.stringValue == "ellipse")
        }
    }

    // MARK: - H1：覆寫 p:style 的明確值必須保留

    @Test func `An explicit no-outline line survives next to a p colon style lnRef`() throws {
        let spPr = try writtenProbeSpPr("NoOutline")
        let ln = try #require(try spPr.nodes(forXPath: "*[local-name()='ln']").first as? XMLElement,
                              "Shape must write its <a:ln>")
        #expect(ln.attribute(forName: "w")?.stringValue == "76200")
        #expect(try !ln.nodes(forXPath: "*[local-name()='noFill']").isEmpty, "the explicit noFill must survive")
    }

    @Test func `An explicit red outline survives on a shape`() throws {
        let spPr = try writtenProbeSpPr("RedOutline")
        let ln = try #require(try spPr.nodes(forXPath: "*[local-name()='ln']").first as? XMLElement)
        #expect(ln.attribute(forName: "w")?.stringValue == "76200")
        let srgb = try ln.nodes(forXPath: "*[local-name()='solidFill']/*[local-name()='srgbClr']").first as? XMLElement
        #expect(srgb?.attribute(forName: "val")?.stringValue == "FF0000")
    }

    @Test func `A sysClr solid fill survives instead of vanishing`() throws {
        let spPr = try writtenProbeSpPr("SysClrFill")
        let sys = try #require(try spPr.nodes(forXPath: "*[local-name()='solidFill']/*[local-name()='sysClr']").first as? XMLElement)
        #expect(sys.attribute(forName: "val")?.stringValue == "window")
        #expect(sys.attribute(forName: "lastClr")?.stringValue == "FFFFFF")
    }

    @Test func `A connectors schemeClr line color survives`() throws {
        let spPr = try writtenProbeSpPr("Conn")
        let ln = try #require(try spPr.nodes(forXPath: "*[local-name()='ln']").first as? XMLElement)
        #expect(ln.attribute(forName: "w")?.stringValue == "38100")
        let scheme = try ln.nodes(forXPath: "*[local-name()='solidFill']/*[local-name()='schemeClr']").first as? XMLElement
        #expect(scheme?.attribute(forName: "val")?.stringValue == "tx1")
    }

    /// 只有 typed 欄位能完整重現原始 XML 的顏色才走 typed；其餘（系統色、預設色、
    /// HSL、scRGB，以及帶色彩變換的 scheme／srgb）一律原樣保留。
    @Test(arguments: [
        "<a:schemeClr val=\"accent1\"><a:lumMod val=\"60000\"/><a:lumOff val=\"40000\"/></a:schemeClr>",
        "<a:srgbClr val=\"FF0000\"><a:alpha val=\"50000\"/></a:srgbClr>",
        "<a:prstClr val=\"black\"/>",
        "<a:hslClr hue=\"14400000\" sat=\"100000\" lum=\"50000\"/>",
        "<a:scrgbClr r=\"0\" g=\"50000\" b=\"100000\"/>",
        "<a:schemeClr val=\"accent2\"><a:shade val=\"50000\"/></a:schemeClr>",
    ])
    func `A solid fill color the typed model cannot fully express round trips verbatim`(color: String) throws {
        let extra = SpPrProbePackage.shapeXML(
            id: 40, name: "Colored",
            spPrInner: SpPrProbePackage.rectGeometry + "<a:solidFill>\(color)</a:solidFill>", style: false)
        let pres = try SpPrProbePackage.read(withPictures: false, extraShapeTreeXML: extra)
        try TemporaryPPTX.written(pres, "h1-color") { url in
            let package = try PackageInspector(url)
            defer { package.cleanup() }
            let spPr = try #require(try SpPrProbePackage.writtenSpPr(named: "Colored", in: package))
            let solid = try #require(try spPr.nodes(forXPath: "*[local-name()='solidFill']").first as? XMLElement,
                                     "the solid fill vanished")
            let expected = try XMLElement(xmlString: color.addingNamespace(Self.nsA))
            let written = try #require(solid.children?.first as? XMLElement)
            #expect(Self.canonical(written) == Self.canonical(expected), "got \(written.xmlString)")
        }
    }

    /// `<a:ln>` 裡 typed 模型沒建模的部分（虛線、接合、端點樣式、`cap`、主題色）
    /// 在沒有被 typed setter 改動時必須原樣保留（PsychQuant/pptx-swift#13 列的遺失）。
    @Test func `An untouched line keeps dash join cap and theme color`() throws {
        let line = "<a:ln w=\"12700\" cap=\"rnd\" cmpd=\"dbl\" algn=\"ctr\"><a:solidFill><a:schemeClr val=\"tx1\"><a:lumMod val=\"75000\"/></a:schemeClr></a:solidFill>"
            + "<a:prstDash val=\"dash\"/><a:round/><a:headEnd type=\"oval\"/><a:tailEnd type=\"triangle\" w=\"lg\" len=\"lg\"/></a:ln>"
        let extra = SpPrProbePackage.shapeXML(id: 41, name: "Dashed", spPrInner: SpPrProbePackage.rectGeometry, style: false, line: line)
            + SpPrProbePackage.connectorXML(id: 42, name: "DashedConn", line: line)
        let pres = try SpPrProbePackage.read(withPictures: false, extraShapeTreeXML: extra)
        try TemporaryPPTX.written(pres, "h1-dash") { url in
            let package = try PackageInspector(url)
            defer { package.cleanup() }
            for name in ["Dashed", "DashedConn"] {
                let spPr = try #require(try SpPrProbePackage.writtenSpPr(named: name, in: package))
                let ln = try #require(try spPr.nodes(forXPath: "*[local-name()='ln']").first as? XMLElement, "\(name) lost its ln")
                #expect(Self.canonical(ln) == Self.canonical(try XMLElement(xmlString: line.addingNamespace(Self.nsA))),
                        "\(name): \(ln.xmlString)")
            }
        }
    }

    /// typed setter 只改線寬時，其餘沒被改動的部分（主題色、虛線、接合、`cap`）
    /// 仍要保留——只有被改的那個欄位改寫。
    @Test func `Changing only the line width keeps every other part of the line`() throws {
        let line = "<a:ln w=\"12700\" cap=\"rnd\"><a:solidFill><a:schemeClr val=\"tx1\"/></a:solidFill><a:prstDash val=\"dash\"/><a:round/><a:tailEnd type=\"triangle\"/></a:ln>"
        let extra = SpPrProbePackage.connectorXML(id: 43, name: "WidthOnly", line: line)
        var pres = try SpPrProbePackage.read(withPictures: false, extraShapeTreeXML: extra)
        let (index, found) = try #require(pres.slides[0].connectorIndex(named: "WidthOnly"))
        var connector = found
        connector.outline?.width = 50800
        pres.slides[0].elements[index] = .connector(connector)

        try TemporaryPPTX.written(pres, "h1-width") { url in
            let package = try PackageInspector(url)
            defer { package.cleanup() }
            let spPr = try #require(try SpPrProbePackage.writtenSpPr(named: "WidthOnly", in: package))
            let ln = try #require(try spPr.nodes(forXPath: "*[local-name()='ln']").first as? XMLElement)
            #expect(ln.attribute(forName: "w")?.stringValue == "50800")
            #expect(ln.attribute(forName: "cap")?.stringValue == "rnd")
            let names = try ln.nodes(forXPath: "*").compactMap { ($0 as? XMLElement)?.localName }
            #expect(names == ["solidFill", "prstDash", "round", "tailEnd"], "got \(names)")
            let scheme = try ln.nodes(forXPath: "*[local-name()='solidFill']/*[local-name()='schemeClr']").first as? XMLElement
            #expect(scheme?.attribute(forName: "val")?.stringValue == "tx1")
        }
    }

    // MARK: - M1：prstGeom 保真

    @Test func `A preset outside the ShapeGeometry enum keeps its prst instead of writing unknown`() throws {
        let spPr = try writtenProbeSpPr("Chevron")
        let prst = try #require(try spPr.nodes(forXPath: "*[local-name()='prstGeom']").first as? XMLElement)
        #expect(prst.attribute(forName: "prst")?.stringValue == "chevron")
    }

    @Test func `A shapes preset adjustments survive a round trip`() throws {
        let spPr = try writtenProbeSpPr("RoundRectAdj")
        let prst = try #require(try spPr.nodes(forXPath: "*[local-name()='prstGeom']").first as? XMLElement)
        #expect(prst.attribute(forName: "prst")?.stringValue == "roundRect")
        let gd = try prst.nodes(forXPath: "*[local-name()='avLst']/*[local-name()='gd']").first as? XMLElement
        #expect(gd?.attribute(forName: "name")?.stringValue == "adj")
        #expect(gd?.attribute(forName: "fmla")?.stringValue == "val 50000")
    }

    // MARK: - L1／L2

    @Test func `A connectors own spPr fill survives`() throws {
        let extra = SpPrProbePackage.connectorXML(
            id: 44, name: "FilledConn", line: "<a:ln w=\"12700\"/>",
            spPrExtra: "<a:solidFill><a:srgbClr val=\"123456\"/></a:solidFill>")
            + SpPrProbePackage.connectorXML(id: 45, name: "NoFillConn", line: "", spPrExtra: "<a:noFill/>")
        let pres = try SpPrProbePackage.read(withPictures: false, extraShapeTreeXML: extra)
        try TemporaryPPTX.written(pres, "l1") { url in
            let package = try PackageInspector(url)
            defer { package.cleanup() }
            let filled = try #require(try SpPrProbePackage.writtenSpPr(named: "FilledConn", in: package))
            let srgb = try filled.nodes(forXPath: "*[local-name()='solidFill']/*[local-name()='srgbClr']").first as? XMLElement
            #expect(srgb?.attribute(forName: "val")?.stringValue == "123456")
            let noFill = try #require(try SpPrProbePackage.writtenSpPr(named: "NoFillConn", in: package))
            #expect(try !noFill.nodes(forXPath: "*[local-name()='noFill']").isEmpty)
        }
    }

    @Test func `bwMode on spPr and grpSpPr survives`() throws {
        let group = "<p:grpSp><p:nvGrpSpPr><p:cNvPr id=\"50\" name=\"BwGroup\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>"
            + "<p:grpSpPr bwMode=\"gray\"><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"914400\" cy=\"914400\"/><a:chOff x=\"0\" y=\"0\"/><a:chExt cx=\"914400\" cy=\"914400\"/></a:xfrm></p:grpSpPr>"
            + SpPrProbePackage.shapeXML(id: 51, name: "BwShape", spPrInner: SpPrProbePackage.rectGeometry, style: false, spPrAttributes: " bwMode=\"auto\"")
            + "</p:grpSp>"
        let pres = try SpPrProbePackage.read(withPictures: false, extraShapeTreeXML: group)
        try TemporaryPPTX.written(pres, "l2") { url in
            let package = try PackageInspector(url)
            defer { package.cleanup() }
            let slide = try package.xml("ppt/slides/slide1.xml")
            let grpSpPr = try slide.nodes(
                forXPath: "//*[local-name()='cNvPr'][@name='BwGroup']/../../*[local-name()='grpSpPr']").first as? XMLElement
            #expect(grpSpPr?.attribute(forName: "bwMode")?.stringValue == "gray")
            let spPr = try SpPrProbePackage.writtenSpPr(named: "BwShape", in: package)
            #expect(spPr?.attribute(forName: "bwMode")?.stringValue == "auto")
        }
    }

    // MARK: - Helpers

    private func writtenProbeSpPr(_ name: String) throws -> XMLElement {
        let pres = try SpPrProbePackage.read(withPictures: false,
                                             extraShapeTreeXML: SpPrProbePackage.reviewProbeElementsWithoutRelationships)
        let url = TemporaryPPTX.url("h1-\(name)")
        defer { try? FileManager.default.removeItem(at: url) }
        try PptxWriter.write(pres, to: url)
        let package = try PackageInspector(url)
        defer { package.cleanup() }
        #expect(try package.integrityViolations() == [])
        return try #require(try SpPrProbePackage.writtenSpPr(named: name, in: package), "\(name) missing from output")
    }

    /// 元素的正規化表示：local name、命名空間、排序後的屬性、子元素遞迴——
    /// 忽略前綴與命名空間宣告的位置，只比語意。
    static func canonical(_ element: XMLElement) -> String {
        let attrs = (element.attributes ?? [])
            .map { "\($0.localName ?? $0.name ?? "")=\($0.stringValue ?? "")" }
            .sorted()
            .joined(separator: ",")
        let children = (element.children ?? []).compactMap { $0 as? XMLElement }.map(canonical).joined()
        return "<\(element.uri ?? ""):\(element.localName ?? "")[\(attrs)]>\(children)</>"
    }
}

private extension String {
    /// 在片段根節點補上 `xmlns:a`，讓單獨解析時前綴有綁定。
    func addingNamespace(_ uri: String) -> String {
        guard let end = range(of: #"^<[A-Za-z:]+"#, options: .regularExpression) else { return self }
        var copy = self
        copy.insert(contentsOf: " xmlns:a=\"\(uri)\"", at: end.upperBound)
        return copy
    }
}

/// typed／原樣單一值的其餘語意（#12 審查 H1／H2／M1）。
struct ShapePropertiesSingleValueTests {
    static let nsA = "http://schemas.openxmlformats.org/drawingml/2006/main"

    @Test func `Plain srgb and scheme solid fills and noFill are still read as typed values`() throws {
        let extra = SpPrProbePackage.shapeXML(id: 60, name: "Srgb", spPrInner: SpPrProbePackage.rectGeometry + "<a:solidFill><a:srgbClr val=\"ABCDEF\"/></a:solidFill>", style: false)
            + SpPrProbePackage.shapeXML(id: 61, name: "Scheme", spPrInner: SpPrProbePackage.rectGeometry + "<a:solidFill><a:schemeClr val=\"accent2\"/></a:solidFill>", style: false)
            + SpPrProbePackage.shapeXML(id: 62, name: "None", spPrInner: SpPrProbePackage.rectGeometry + "<a:noFill/>", style: false)
        let slide = try SpPrProbePackage.read(withPictures: false, extraShapeTreeXML: extra).slides[0]
        guard case .solid(let color)? = slide.shapeIndex(named: "Srgb")?.1.fill else { Issue.record("Srgb not typed"); return }
        #expect(color == "ABCDEF")
        guard case .schemeColor(let name)? = slide.shapeIndex(named: "Scheme")?.1.fill else { Issue.record("Scheme not typed"); return }
        #expect(name == "accent2")
        guard case .noFill? = slide.shapeIndex(named: "None")?.1.fill else { Issue.record("None not typed"); return }
    }

    @Test func `Reassigning the same geometry keeps adjustments and a custom path`() throws {
        var preset = Shape(id: 2, geometry: .roundRect, adjustments: [GeometryAdjustment(name: "adj", formula: "val 50000")])
        preset.geometry = .roundRect
        #expect(preset.adjustments == [GeometryAdjustment(name: "adj", formula: "val 50000")])
        preset.geometry = .ellipse
        #expect(preset.geometryDefinition == .preset("ellipse", adjustments: []), "a different preset clears adjustments")

        var custom = Shape(id: 3)
        custom.geometryDefinition = .custom("<a:custGeom xmlns:a=\"\(Self.nsA)\"/>")
        custom.geometry = custom.geometry
        #expect(custom.geometryDefinition == .custom("<a:custGeom xmlns:a=\"\(Self.nsA)\"/>"))

        var unrecognized = Shape(id: 4)
        unrecognized.geometryDefinition = .preset("chevron", adjustments: [])
        #expect(unrecognized.geometry == .unknown)
        unrecognized.geometry = .unknown
        #expect(unrecognized.geometryDefinition == .preset("chevron", adjustments: []))
    }

    @Test func `A typed gradient is written and one with fewer than two stops is refused`() throws {
        var pres = PptxWriter.createNew()
        pres.slides[0].elements = [.shape(Shape(id: 2, name: "g", fill: .gradient(stops: [("FF0000", 0), ("0000FF", 100000)])))]
        try TemporaryPPTX.written(pres, "typed-grad") { url in
            let package = try PackageInspector(url)
            defer { package.cleanup() }
            let spPr = try #require(try SpPrProbePackage.writtenSpPr(named: "g", in: package))
            let stops = try spPr.nodes(forXPath: "*[local-name()='gradFill']/*[local-name()='gsLst']/*[local-name()='gs']")
            #expect(stops.count == 2)
        }
        pres.slides[0].elements = [.shape(Shape(id: 2, name: "g", fill: .gradient(stops: [("FF0000", 0)])))]
        let url = TemporaryPPTX.url("typed-grad-bad")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: PPTXError.self) { try PptxWriter.write(pres, to: url) }
    }

    @Test func `A shape outline built in code is written`() throws {
        var pres = PptxWriter.createNew()
        pres.slides[0].elements = [.shape(Shape(id: 2, name: "o", outline: ShapeOutline(color: "FF0000", width: 12700)))]
        try TemporaryPPTX.written(pres, "typed-ln") { url in
            let package = try PackageInspector(url)
            defer { package.cleanup() }
            let ln = try #require(try SpPrProbePackage.writtenSpPr(named: "o", in: package)?.nodes(forXPath: "*[local-name()='ln']").first as? XMLElement)
            #expect(ln.attribute(forName: "w")?.stringValue == "12700")
        }
    }

    /// 改線色：線條填色換成實心色（原本的 noFill 被取代），其餘不動；把線色改成
    /// nil（原本有值）：線條填色移除；改端點：只換那一端，未被改的 `<a:headEnd/>`
    /// 空元素原樣保留。
    @Test func `Line merge rewrites only the changed parts`() throws {
        let noFillLine = "<a:ln w=\"9525\"><a:noFill/><a:miter lim=\"800000\"/><a:headEnd/><a:tailEnd/></a:ln>"
        let redLine = "<a:ln w=\"9525\"><a:solidFill><a:srgbClr val=\"FF0000\"/></a:solidFill><a:prstDash val=\"dash\"/></a:ln>"
        let extra = SpPrProbePackage.shapeXML(id: 70, name: "ToColor", spPrInner: SpPrProbePackage.rectGeometry, style: false, line: noFillLine)
            + SpPrProbePackage.shapeXML(id: 71, name: "ToNil", spPrInner: SpPrProbePackage.rectGeometry, style: false, line: redLine)
            + SpPrProbePackage.shapeXML(id: 72, name: "ToArrow", spPrInner: SpPrProbePackage.rectGeometry, style: false, line: noFillLine)
        var pres = try SpPrProbePackage.read(withPictures: false, extraShapeTreeXML: extra)
        func edit(_ name: String, _ change: (inout ShapeOutline) -> Void) throws {
            let (index, found) = try #require(pres.slides[0].shapeIndex(named: name))
            var shape = found
            var outline = try #require(shape.outline)
            change(&outline)
            shape.outline = outline
            pres.slides[0].elements[index] = .shape(shape)
        }
        try edit("ToColor") { $0.color = "00FF00" }
        try edit("ToNil") { $0.color = nil }
        try edit("ToArrow") { $0.tailEnd = LineEndStyle(type: "triangle") }

        try TemporaryPPTX.written(pres, "ln-merge") { url in
            let package = try PackageInspector(url)
            defer { package.cleanup() }
            func children(_ name: String) throws -> [String] {
                let ln = try #require(try SpPrProbePackage.writtenSpPr(named: name, in: package)?.nodes(forXPath: "*[local-name()='ln']").first as? XMLElement)
                return (ln.children ?? []).compactMap { el -> String? in
                    guard let el = el as? XMLElement else { return nil }
                    let attrs = (el.attributes ?? []).map { "\($0.name ?? "")=\($0.stringValue ?? "")" }.sorted().joined(separator: ",")
                    let kids = (el.children ?? []).compactMap { ($0 as? XMLElement)?.localName }.joined(separator: ",")
                    return "\(el.localName ?? "")[\(attrs)](\(kids))"
                }
            }
            #expect(try children("ToColor") == ["solidFill[](srgbClr)", "miter[lim=800000]()", "headEnd[]()", "tailEnd[]()"])
            #expect(try children("ToNil") == ["prstDash[val=dash]()"])
            #expect(try children("ToArrow") == ["noFill[]()", "miter[lim=800000]()", "headEnd[]()", "tailEnd[type=triangle]()"])
        }
    }
}
