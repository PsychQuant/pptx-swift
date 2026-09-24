import Foundation
import ZIPFoundation
// ZipHelper reused from OOXMLSwift for ZIP extraction
import OOXMLSwift

/// PPTX 檔案讀取器
public struct PptxReader {

    // MARK: - Internal Types

    /// 簡化的關係結構（PPTX 用）
    struct Rel {
        let id: String
        let typeURI: String
        let target: String
        var targetMode: String? = nil
        /// For image relationships: the file name directly under `ppt/media/`
        /// that the target resolves to, when that part exists (see
        /// `resolvedMediaFileName`). Nil otherwise.
        var mediaFileName: String? = nil

        var isExternal: Bool { targetMode?.caseInsensitiveCompare("External") == .orderedSame }

        var isSlide: Bool { typeURI.hasSuffix("/slide") }
        var isSlideMaster: Bool { typeURI.hasSuffix("/slideMaster") }
        var isSlideLayout: Bool { typeURI.hasSuffix("/slideLayout") }
        var isTheme: Bool { typeURI.hasSuffix("/theme") }
        var isImage: Bool { typeURI.hasSuffix("/image") }
        var isNotesSlide: Bool { typeURI.hasSuffix("/notesSlide") }
    }

    private static let nsR = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"

    // MARK: - Public API

    /// 讀取 .pptx 檔案並解析為 Presentation
    public static func read(from url: URL) throws -> Presentation {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw PPTXError.fileNotFound(url.path)
        }

        let tempDir = try ZipHelper.unzip(url)
        defer { ZipHelper.cleanup(tempDir) }

        var presentation = Presentation()

        // 1. 解析 presentation.xml
        let presURL = tempDir.appendingPathComponent("ppt/presentation.xml")
        guard FileManager.default.fileExists(atPath: presURL.path) else {
            throw PPTXError.parseError("找不到 ppt/presentation.xml")
        }
        let presData = try Data(contentsOf: presURL)
        let presXML = try XMLDocument(data: presData)
        try parsePresentationXML(presXML, into: &presentation)

        // 2. 解析 presentation relationships
        let presRels = try parseRelationships(
            from: tempDir.appendingPathComponent("ppt/_rels/presentation.xml.rels")
        )

        // 3. 解析 theme
        if let themeRel = presRels.first(where: { $0.isTheme }) {
            let themeURL = tempDir.appendingPathComponent("ppt/\(themeRel.target)")
            if FileManager.default.fileExists(atPath: themeURL.path) {
                let themeData = try Data(contentsOf: themeURL)
                let themeXML = try XMLDocument(data: themeData)
                presentation.theme = try parseTheme(from: themeXML)
            }
        }

        // 4. 解析每張投影片
        let slideRels = presRels.filter { $0.isSlide }
            .sorted { $0.target.localizedStandardCompare($1.target) == .orderedAscending }

        for slideRel in slideRels {
            let slideURL = tempDir.appendingPathComponent("ppt/\(slideRel.target)")
            guard FileManager.default.fileExists(atPath: slideURL.path) else { continue }

            let slideData = try Data(contentsOf: slideURL)
            let slideXML = try XMLDocument(data: slideData)

            // 投影片的 relationships
            let slideFileName = (slideRel.target as NSString).lastPathComponent
            let slideRelsURL = tempDir.appendingPathComponent("ppt/slides/_rels/\(slideFileName).rels")
            let slidePartPath = resolvePartPath(target: slideRel.target, relativeTo: "ppt/presentation.xml")
                ?? "ppt/slides/\(slideFileName)"
            let slideRelationships = ((try? parseRelationships(from: slideRelsURL)) ?? []).map { rel in
                var rel = rel
                rel.mediaFileName = resolvedMediaFileName(for: rel, sourcePartPath: slidePartPath, packageRoot: tempDir)
                return rel
            }

            var slide = try parseSlide(from: slideXML, relationships: slideRelationships)

            // 解析 notes
            if let notesRel = slideRelationships.first(where: { $0.isNotesSlide }) {
                let notesURL = tempDir.appendingPathComponent("ppt/slides/\(notesRel.target)")
                if FileManager.default.fileExists(atPath: notesURL.path) {
                    let notesData = try Data(contentsOf: notesURL)
                    let notesXML = try XMLDocument(data: notesData)
                    slide.notes = try parseNotes(from: notesXML)
                }
            }

            presentation.slides.append(slide)
        }

        // 5. 提取圖片資源
        presentation.images = try extractImages(from: tempDir)

        // 6. 解析 slide masters
        let masterRels = presRels.filter { $0.isSlideMaster }
        for masterRel in masterRels {
            let masterURL = tempDir.appendingPathComponent("ppt/\(masterRel.target)")
            if FileManager.default.fileExists(atPath: masterURL.path) {
                let masterData = try Data(contentsOf: masterURL)
                let masterXML = try XMLDocument(data: masterData)
                let master = try parseSlideMaster(from: masterXML, id: masterRel.id)
                presentation.slideMasters.append(master)
            }
        }

        // 7. 解析 slide layouts
        let layoutRels = presRels.filter { $0.isSlideLayout }
        for layoutRel in layoutRels {
            let layoutURL = tempDir.appendingPathComponent("ppt/\(layoutRel.target)")
            if FileManager.default.fileExists(atPath: layoutURL.path) {
                let layoutData = try Data(contentsOf: layoutURL)
                let layoutXML = try XMLDocument(data: layoutData)
                let layout = try parseSlideLayout(from: layoutXML, id: layoutRel.id)
                presentation.slideLayouts.append(layout)
            }
        }

        // 8. 解析 document properties
        let coreURL = tempDir.appendingPathComponent("docProps/core.xml")
        if FileManager.default.fileExists(atPath: coreURL.path) {
            let coreData = try Data(contentsOf: coreURL)
            let coreXML = try XMLDocument(data: coreData)
            presentation.properties = try parseCoreProperties(from: coreXML)
        }

        return presentation
    }

    // MARK: - Presentation XML

    private static func parsePresentationXML(_ xml: XMLDocument, into presentation: inout Presentation) throws {
        let root = xml.rootElement()

        // 投影片尺寸
        if let sldSz = try root?.nodes(forXPath: "//*[local-name()='sldSz']").first as? XMLElement {
            let cx = Int(sldSz.attribute(forName: "cx")?.stringValue ?? "") ?? 9144000
            let cy = Int(sldSz.attribute(forName: "cy")?.stringValue ?? "") ?? 6858000
            presentation.slideSize = SlideSize(width: cx, height: cy)
        }
    }

    // MARK: - Relationships

    private static func parseRelationships(from url: URL) throws -> [Rel] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }

        let data = try Data(contentsOf: url)
        let xml = try XMLDocument(data: data)

        var relationships: [Rel] = []
        let relNodes = try xml.nodes(forXPath: "//*[local-name()='Relationship']")

        for node in relNodes {
            guard let element = node as? XMLElement else { continue }
            let id = element.attribute(forName: "Id")?.stringValue ?? ""
            let typeStr = element.attribute(forName: "Type")?.stringValue ?? ""
            let target = element.attribute(forName: "Target")?.stringValue ?? ""
            let targetMode = element.attribute(forName: "TargetMode")?.stringValue
            relationships.append(Rel(id: id, typeURI: typeStr, target: target, targetMode: targetMode))
        }

        return relationships
    }

    // MARK: - Part names

    /// The media file name an image relationship points at, or nil unless all
    /// hold: the relationship is an internal image relationship, its target
    /// resolves (relative to `sourcePartPath`) to exactly `ppt/media/<name>`,
    /// and that part exists as a regular file in the extracted package.
    static func resolvedMediaFileName(for rel: Rel, sourcePartPath: String, packageRoot: URL) -> String? {
        guard rel.isImage, !rel.isExternal,
              let partPath = resolvePartPath(target: rel.target, relativeTo: sourcePartPath) else { return nil }
        let segments = partPath.split(separator: "/")
        guard segments.count == 3, segments[0] == "ppt", segments[1] == "media" else { return nil }

        var isDirectory: ObjCBool = false
        let fileURL = packageRoot.appendingPathComponent(partPath)
        guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else { return nil }
        return String(segments[2])
    }

    /// Resolves a relationship `Target` to a package part name (OPC, ECMA-376
    /// Part 2 §9.3): relative targets resolve against the source part's
    /// directory, a leading `/` means the package root, targets are
    /// percent-decoded, and `.` / `..` segments are normalised. Returns nil
    /// for an empty target or one that climbs above the package root.
    static func resolvePartPath(target: String, relativeTo sourcePartPath: String) -> String? {
        let decoded = target.removingPercentEncoding ?? target
        guard !decoded.isEmpty else { return nil }
        var segments: [Substring] = decoded.hasPrefix("/")
            ? []
            : Array(sourcePartPath.split(separator: "/").dropLast())
        for segment in decoded.split(separator: "/") {
            switch segment {
            case ".":
                continue
            case "..":
                guard !segments.isEmpty else { return nil }
                segments.removeLast()
            default:
                segments.append(segment)
            }
        }
        return segments.isEmpty ? nil : segments.joined(separator: "/")
    }

    // MARK: - Theme

    private static func parseTheme(from xml: XMLDocument) throws -> Theme {
        var theme = Theme()

        // Theme name
        if let themeElement = try xml.nodes(forXPath: "//*[local-name()='theme']").first as? XMLElement {
            theme.name = themeElement.attribute(forName: "name")?.stringValue ?? ""
        }

        // Color scheme
        if let clrScheme = try xml.nodes(forXPath: "//*[local-name()='clrScheme']").first as? XMLElement {
            theme.colorScheme.name = clrScheme.attribute(forName: "name")?.stringValue ?? ""

            let colorNames = ["dk1", "lt1", "dk2", "lt2", "accent1", "accent2", "accent3",
                             "accent4", "accent5", "accent6", "hlink", "folHlink"]

            for name in colorNames {
                if let colorNode = try clrScheme.nodes(forXPath: "*[local-name()='\(name)']").first as? XMLElement {
                    if let hex = extractColorHex(from: colorNode) {
                        switch name {
                        case "dk1": theme.colorScheme.dk1 = hex
                        case "lt1": theme.colorScheme.lt1 = hex
                        case "dk2": theme.colorScheme.dk2 = hex
                        case "lt2": theme.colorScheme.lt2 = hex
                        case "accent1": theme.colorScheme.accent1 = hex
                        case "accent2": theme.colorScheme.accent2 = hex
                        case "accent3": theme.colorScheme.accent3 = hex
                        case "accent4": theme.colorScheme.accent4 = hex
                        case "accent5": theme.colorScheme.accent5 = hex
                        case "accent6": theme.colorScheme.accent6 = hex
                        case "hlink": theme.colorScheme.hlink = hex
                        case "folHlink": theme.colorScheme.folHlink = hex
                        default: break
                        }
                    }
                }
            }
        }

        // Font scheme
        if let fontScheme = try xml.nodes(forXPath: "//*[local-name()='fontScheme']").first as? XMLElement {
            theme.fontScheme.name = fontScheme.attribute(forName: "name")?.stringValue ?? ""

            if let majorFont = try fontScheme.nodes(forXPath: "*[local-name()='majorFont']/*[local-name()='latin']").first as? XMLElement {
                theme.fontScheme.majorFont = majorFont.attribute(forName: "typeface")?.stringValue ?? ""
            }
            if let minorFont = try fontScheme.nodes(forXPath: "*[local-name()='minorFont']/*[local-name()='latin']").first as? XMLElement {
                theme.fontScheme.minorFont = minorFont.attribute(forName: "typeface")?.stringValue ?? ""
            }
        }

        return theme
    }

    /// 從顏色節點提取 hex 值
    private static func extractColorHex(from element: XMLElement) -> String? {
        // <a:srgbClr val="FF0000"/>
        if let srgb = try? element.nodes(forXPath: "*[local-name()='srgbClr']").first as? XMLElement {
            return srgb.attribute(forName: "val")?.stringValue
        }
        // <a:sysClr val="windowText" lastClr="000000"/>
        if let sys = try? element.nodes(forXPath: "*[local-name()='sysClr']").first as? XMLElement {
            return sys.attribute(forName: "lastClr")?.stringValue
        }
        return nil
    }

    // MARK: - Slide

    private static func parseSlide(from xml: XMLDocument, relationships: [Rel]) throws -> Slide {
        var slide = Slide()

        // 解析 shape tree
        if let spTree = try xml.nodes(forXPath: "//*[local-name()='spTree']").first as? XMLElement {
            slide.elements = try parseShapeTree(spTree, relationships: relationships)
        }

        // 解析 transition
        if let transition = try xml.nodes(forXPath: "//*[local-name()='transition']").first as? XMLElement {
            slide.transition = parseTransition(transition)
        }

        return slide
    }

    // MARK: - Shape Tree

    private static func parseShapeTree(_ spTree: XMLElement, relationships: [Rel]) throws -> [SlideElement] {
        var elements: [SlideElement] = []

        for child in spTree.children ?? [] {
            guard let element = child as? XMLElement else { continue }
            let localName = element.localName ?? element.name ?? ""

            switch localName {
            case "sp":
                let shape = try parseShape(element)
                elements.append(.shape(shape))
            case "pic":
                let picture = try parsePicture(element, relationships: relationships)
                elements.append(.picture(picture))
            case "graphicFrame":
                let frame = try parseGraphicFrame(element)
                elements.append(.graphicFrame(frame))
            case "grpSp":
                let group = try parseGroupShape(element, relationships: relationships)
                elements.append(.group(group))
            default:
                break
            }
        }

        return elements
    }

    // MARK: - Shape

    private static func parseShape(_ element: XMLElement) throws -> Shape {
        var shape = Shape()

        // Non-visual properties
        if let cNvPr = try element.nodes(forXPath: ".//*[local-name()='cNvPr']").first as? XMLElement {
            shape.id = Int(cNvPr.attribute(forName: "id")?.stringValue ?? "0") ?? 0
            shape.name = cNvPr.attribute(forName: "name")?.stringValue ?? ""
        }

        // Placeholder
        if let ph = try element.nodes(forXPath: ".//*[local-name()='ph']").first as? XMLElement {
            let typeStr = ph.attribute(forName: "type")?.stringValue ?? "body"
            shape.placeholder = PlaceholderType(rawValue: typeStr) ?? .unknown
        }

        // Shape properties (position, size, geometry)
        if let spPr = try element.nodes(forXPath: "./*[local-name()='spPr']").first as? XMLElement {
            parseShapeProperties(spPr, position: &shape.position, size: &shape.size,
                               fill: &shape.fill, outline: &shape.outline, geometry: &shape.geometry)
        }

        // Text body
        if let txBody = try element.nodes(forXPath: "./*[local-name()='txBody']").first as? XMLElement {
            shape.textBody = try parseTextBody(txBody)
        }

        return shape
    }

    // MARK: - Picture

    private static func parsePicture(_ element: XMLElement, relationships: [Rel]) throws -> Picture {
        var picture = Picture()

        if let cNvPr = try element.nodes(forXPath: ".//*[local-name()='cNvPr']").first as? XMLElement {
            picture.id = Int(cNvPr.attribute(forName: "id")?.stringValue ?? "0") ?? 0
            picture.name = cNvPr.attribute(forName: "name")?.stringValue ?? ""
            picture.description = cNvPr.attribute(forName: "descr")?.stringValue
        }

        // Image reference
        if let blip = try element.nodes(forXPath: ".//*[local-name()='blip']").first as? XMLElement {
            // r:embed attribute — try with namespace first, then without
            picture.imageRelationshipId = blip.attribute(forLocalName: "embed", uri: nsR)?.stringValue
                ?? blip.attribute(forName: "r:embed")?.stringValue
                ?? ""
            // r:embed → ppt/media/ 檔名（已在讀取 slide relationships 時解析並驗證存在）
            picture.mediaFileName = relationships
                .first(where: { $0.id == picture.imageRelationshipId })?
                .mediaFileName
        }

        // Position and size
        if let spPr = try element.nodes(forXPath: "./*[local-name()='spPr']").first as? XMLElement {
            var fill: ShapeFill? = nil
            var outline: ShapeOutline? = nil
            var geometry: ShapeGeometry = .rect
            parseShapeProperties(spPr, position: &picture.position, size: &picture.size,
                               fill: &fill, outline: &outline, geometry: &geometry)
        }

        return picture
    }

    // MARK: - Graphic Frame (Table)

    private static func parseGraphicFrame(_ element: XMLElement) throws -> GraphicFrame {
        var frame = GraphicFrame()

        if let cNvPr = try element.nodes(forXPath: ".//*[local-name()='cNvPr']").first as? XMLElement {
            frame.id = Int(cNvPr.attribute(forName: "id")?.stringValue ?? "0") ?? 0
            frame.name = cNvPr.attribute(forName: "name")?.stringValue ?? ""
        }

        // Position and size from xfrm
        if let xfrm = try element.nodes(forXPath: ".//*[local-name()='xfrm']").first as? XMLElement {
            if let off = try xfrm.nodes(forXPath: "*[local-name()='off']").first as? XMLElement {
                frame.position.x = Int(off.attribute(forName: "x")?.stringValue ?? "0") ?? 0
                frame.position.y = Int(off.attribute(forName: "y")?.stringValue ?? "0") ?? 0
            }
            if let ext = try xfrm.nodes(forXPath: "*[local-name()='ext']").first as? XMLElement {
                frame.size.width = Int(ext.attribute(forName: "cx")?.stringValue ?? "0") ?? 0
                frame.size.height = Int(ext.attribute(forName: "cy")?.stringValue ?? "0") ?? 0
            }
        }

        // Table
        if let tbl = try element.nodes(forXPath: ".//*[local-name()='tbl']").first as? XMLElement {
            frame.table = try parseTable(tbl)
        }

        return frame
    }

    // MARK: - Table

    private static func parseTable(_ tbl: XMLElement) throws -> DrawingTable {
        var table = DrawingTable()

        // Grid columns
        let gridCols = try tbl.nodes(forXPath: "*[local-name()='tblGrid']/*[local-name()='gridCol']")
        for col in gridCols {
            guard let colElement = col as? XMLElement else { continue }
            let width = Int(colElement.attribute(forName: "w")?.stringValue ?? "0") ?? 0
            table.columns.append(TableColumn(width: width))
        }

        // Rows
        let rows = try tbl.nodes(forXPath: "*[local-name()='tr']")
        for row in rows {
            guard let rowElement = row as? XMLElement else { continue }
            let height = Int(rowElement.attribute(forName: "h")?.stringValue ?? "0") ?? 0
            var tableRow = TableRow(height: height)

            let cells = try rowElement.nodes(forXPath: "*[local-name()='tc']")
            for cell in cells {
                guard let cellElement = cell as? XMLElement else { continue }
                var tableCell = TableCell()

                if let txBody = try cellElement.nodes(forXPath: "*[local-name()='txBody']").first as? XMLElement {
                    tableCell.textBody = try parseTextBody(txBody)
                }

                tableRow.cells.append(tableCell)
            }

            table.rows.append(tableRow)
        }

        return table
    }

    // MARK: - Group Shape

    private static func parseGroupShape(_ element: XMLElement, relationships: [Rel]) throws -> GroupShape {
        var group = GroupShape()

        if let cNvPr = try element.nodes(forXPath: ".//*[local-name()='cNvPr']").first as? XMLElement {
            group.id = Int(cNvPr.attribute(forName: "id")?.stringValue ?? "0") ?? 0
            group.name = cNvPr.attribute(forName: "name")?.stringValue ?? ""
        }

        if let grpSpPr = try element.nodes(forXPath: "./*[local-name()='grpSpPr']").first as? XMLElement {
            if let xfrm = try grpSpPr.nodes(forXPath: "*[local-name()='xfrm']").first as? XMLElement {
                if let off = try xfrm.nodes(forXPath: "*[local-name()='off']").first as? XMLElement {
                    group.position.x = Int(off.attribute(forName: "x")?.stringValue ?? "0") ?? 0
                    group.position.y = Int(off.attribute(forName: "y")?.stringValue ?? "0") ?? 0
                }
                if let ext = try xfrm.nodes(forXPath: "*[local-name()='ext']").first as? XMLElement {
                    group.size.width = Int(ext.attribute(forName: "cx")?.stringValue ?? "0") ?? 0
                    group.size.height = Int(ext.attribute(forName: "cy")?.stringValue ?? "0") ?? 0
                }
            }
        }

        // Parse child elements
        for child in element.children ?? [] {
            guard let childElement = child as? XMLElement else { continue }
            let localName = childElement.localName ?? childElement.name ?? ""
            switch localName {
            case "sp":
                group.elements.append(.shape(try parseShape(childElement)))
            case "pic":
                group.elements.append(.picture(try parsePicture(childElement, relationships: relationships)))
            case "graphicFrame":
                group.elements.append(.graphicFrame(try parseGraphicFrame(childElement)))
            case "grpSp":
                group.elements.append(.group(try parseGroupShape(childElement, relationships: relationships)))
            default:
                break
            }
        }

        return group
    }

    // MARK: - Shape Properties

    private static func parseShapeProperties(
        _ spPr: XMLElement,
        position: inout Position,
        size: inout Size,
        fill: inout ShapeFill?,
        outline: inout ShapeOutline?,
        geometry: inout ShapeGeometry
    ) {
        // Position and size
        if let xfrm = try? spPr.nodes(forXPath: "*[local-name()='xfrm']").first as? XMLElement {
            if let off = try? xfrm.nodes(forXPath: "*[local-name()='off']").first as? XMLElement {
                position.x = Int(off.attribute(forName: "x")?.stringValue ?? "0") ?? 0
                position.y = Int(off.attribute(forName: "y")?.stringValue ?? "0") ?? 0
            }
            if let ext = try? xfrm.nodes(forXPath: "*[local-name()='ext']").first as? XMLElement {
                size.width = Int(ext.attribute(forName: "cx")?.stringValue ?? "0") ?? 0
                size.height = Int(ext.attribute(forName: "cy")?.stringValue ?? "0") ?? 0
            }
        }

        // Geometry
        if let prstGeom = try? spPr.nodes(forXPath: "*[local-name()='prstGeom']").first as? XMLElement {
            let prst = prstGeom.attribute(forName: "prst")?.stringValue ?? "rect"
            geometry = ShapeGeometry(rawValue: prst) ?? .unknown
        }

        // Fill
        if let solidFill = try? spPr.nodes(forXPath: "*[local-name()='solidFill']").first as? XMLElement {
            if let srgb = try? solidFill.nodes(forXPath: "*[local-name()='srgbClr']").first as? XMLElement {
                fill = .solid(color: srgb.attribute(forName: "val")?.stringValue ?? "000000")
            } else if let scheme = try? solidFill.nodes(forXPath: "*[local-name()='schemeClr']").first as? XMLElement {
                fill = .schemeColor(name: scheme.attribute(forName: "val")?.stringValue ?? "")
            }
        } else if (try? spPr.nodes(forXPath: "*[local-name()='noFill']").first) != nil {
            fill = .noFill
        }

        // Outline
        if let ln = try? spPr.nodes(forXPath: "*[local-name()='ln']").first as? XMLElement {
            var shapeOutline = ShapeOutline()
            shapeOutline.width = Int(ln.attribute(forName: "w")?.stringValue ?? "")
            if let srgb = try? ln.nodes(forXPath: ".//*[local-name()='srgbClr']").first as? XMLElement {
                shapeOutline.color = srgb.attribute(forName: "val")?.stringValue
            }
            outline = shapeOutline
        }
    }

    // MARK: - Text Body

    private static func parseTextBody(_ txBody: XMLElement) throws -> TextBody {
        var textBody = TextBody()

        // Body properties
        if let bodyPr = try txBody.nodes(forXPath: "*[local-name()='bodyPr']").first as? XMLElement {
            textBody.bodyProperties.wrap = bodyPr.attribute(forName: "wrap")?.stringValue
            textBody.bodyProperties.anchor = bodyPr.attribute(forName: "anchor")?.stringValue
        }

        // Paragraphs
        let paragraphs = try txBody.nodes(forXPath: "*[local-name()='p']")
        for paraNode in paragraphs {
            guard let paraElement = paraNode as? XMLElement else { continue }
            let paragraph = try parseParagraph(paraElement)
            textBody.paragraphs.append(paragraph)
        }

        return textBody
    }

    private static func parseParagraph(_ element: XMLElement) throws -> TextParagraph {
        var paragraph = TextParagraph()

        // Paragraph properties
        if let pPr = try element.nodes(forXPath: "*[local-name()='pPr']").first as? XMLElement {
            paragraph.properties.alignment = TextAlignment(rawValue: pPr.attribute(forName: "algn")?.stringValue ?? "")
            paragraph.properties.level = Int(pPr.attribute(forName: "lvl")?.stringValue ?? "")

            // Bullet
            if let buChar = try pPr.nodes(forXPath: "*[local-name()='buChar']").first as? XMLElement {
                let char = buChar.attribute(forName: "char")?.stringValue ?? "•"
                let font = (try? pPr.nodes(forXPath: "*[local-name()='buFont']").first as? XMLElement)?
                    .attribute(forName: "typeface")?.stringValue
                paragraph.bullet = .character(char: char, font: font)
            } else if let buAutoNum = try pPr.nodes(forXPath: "*[local-name()='buAutoNum']").first as? XMLElement {
                let type = buAutoNum.attribute(forName: "type")?.stringValue ?? "arabicPeriod"
                let startAt = Int(buAutoNum.attribute(forName: "startAt")?.stringValue ?? "")
                paragraph.bullet = .autoNumbered(type: type, startAt: startAt)
            } else if (try? pPr.nodes(forXPath: "*[local-name()='buNone']").first) != nil {
                paragraph.bullet = BulletStyle.none
            }
        }

        // Runs
        let runs = try element.nodes(forXPath: "*[local-name()='r']")
        for runNode in runs {
            guard let runElement = runNode as? XMLElement else { continue }
            let run = try parseRun(runElement)
            paragraph.runs.append(run)
        }

        return paragraph
    }

    private static func parseRun(_ element: XMLElement) throws -> TextRun {
        var run = TextRun(text: "")

        // Text
        if let t = try element.nodes(forXPath: "*[local-name()='t']").first {
            run.text = t.stringValue ?? ""
        }

        // Run properties
        if let rPr = try element.nodes(forXPath: "*[local-name()='rPr']").first as? XMLElement {
            run.properties.fontSize = Int(rPr.attribute(forName: "sz")?.stringValue ?? "")
            run.properties.bold = rPr.attribute(forName: "b")?.stringValue == "1"
            run.properties.italic = rPr.attribute(forName: "i")?.stringValue == "1"
            run.properties.underline = rPr.attribute(forName: "u")?.stringValue
            run.properties.strikethrough = rPr.attribute(forName: "strike")?.stringValue
            run.properties.language = rPr.attribute(forName: "lang")?.stringValue

            // Color
            if let srgb = try rPr.nodes(forXPath: "*[local-name()='solidFill']/*[local-name()='srgbClr']").first as? XMLElement {
                run.properties.color = srgb.attribute(forName: "val")?.stringValue
            } else if let scheme = try rPr.nodes(forXPath: "*[local-name()='solidFill']/*[local-name()='schemeClr']").first as? XMLElement {
                run.properties.schemeColor = scheme.attribute(forName: "val")?.stringValue
            }

            // Font
            if let latin = try rPr.nodes(forXPath: "*[local-name()='latin']").first as? XMLElement {
                run.properties.fontName = latin.attribute(forName: "typeface")?.stringValue
            }
        }

        return run
    }

    // MARK: - Notes

    private static func parseNotes(from xml: XMLDocument) throws -> String {
        let runs = try xml.nodes(forXPath: "//*[local-name()='txBody']//*[local-name()='t']")
        return runs.compactMap { $0.stringValue }.joined()
    }

    // MARK: - Transition

    private static func parseTransition(_ element: XMLElement) -> SlideTransition {
        let speedStr = element.attribute(forName: "spd")?.stringValue ?? "med"
        let speed = TransitionSpeed(rawValue: speedStr) ?? .medium

        var type: TransitionType = .none
        for child in element.children ?? [] {
            guard let childElement = child as? XMLElement else { continue }
            let name = childElement.localName ?? childElement.name ?? ""
            type = TransitionType(rawValue: name) ?? .unknown
            break
        }

        return SlideTransition(type: type, speed: speed)
    }

    // MARK: - Slide Master

    private static func parseSlideMaster(from xml: XMLDocument, id: String) throws -> SlideMaster {
        var master = SlideMaster(id: id)

        // Parse placeholders from shape tree
        let phNodes = try xml.nodes(forXPath: "//*[local-name()='ph']")
        for phNode in phNodes {
            guard let phElement = phNode as? XMLElement else { continue }
            let typeStr = phElement.attribute(forName: "type")?.stringValue ?? "body"
            let placeholder = PlaceholderDef(
                type: PlaceholderType(rawValue: typeStr) ?? .unknown,
                index: Int(phElement.attribute(forName: "idx")?.stringValue ?? "")
            )
            master.placeholders.append(placeholder)
        }

        return master
    }

    // MARK: - Slide Layout

    private static func parseSlideLayout(from xml: XMLDocument, id: String) throws -> SlideLayout {
        var layout = SlideLayout(id: id)

        if let root = xml.rootElement() {
            layout.type = root.attribute(forName: "type")?.stringValue
        }

        if let cSld = try xml.nodes(forXPath: "//*[local-name()='cSld']").first as? XMLElement {
            layout.name = cSld.attribute(forName: "name")?.stringValue ?? ""
        }

        // Parse placeholders
        let phNodes = try xml.nodes(forXPath: "//*[local-name()='ph']")
        for phNode in phNodes {
            guard let phElement = phNode as? XMLElement else { continue }
            let typeStr = phElement.attribute(forName: "type")?.stringValue ?? "body"
            let placeholder = PlaceholderDef(
                type: PlaceholderType(rawValue: typeStr) ?? .unknown,
                index: Int(phElement.attribute(forName: "idx")?.stringValue ?? "")
            )
            layout.placeholders.append(placeholder)
        }

        return layout
    }

    // MARK: - Images

    private static func extractImages(from tempDir: URL) throws -> [MediaFile] {
        let mediaDir = tempDir.appendingPathComponent("ppt/media")
        guard FileManager.default.fileExists(atPath: mediaDir.path) else { return [] }

        let fileManager = FileManager.default
        let files = try fileManager.contentsOfDirectory(at: mediaDir, includingPropertiesForKeys: [.isRegularFileKey])
            // 只收 ppt/media/ 下的一般檔案；子目錄不是 media part，讀它會讓整份簡報開啟失敗
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }

        return try files.map { fileURL -> MediaFile in
            let data = try Data(contentsOf: fileURL)
            return MediaFile(
                id: fileURL.lastPathComponent,
                fileName: fileURL.lastPathComponent,
                data: data
            )
        }
    }

    // MARK: - Document Properties

    private static func parseCoreProperties(from xml: XMLDocument) throws -> PresentationProperties {
        var props = PresentationProperties()

        let titleNodes = try xml.nodes(forXPath: "//*[local-name()='title']")
        props.title = titleNodes.first?.stringValue

        let creatorNodes = try xml.nodes(forXPath: "//*[local-name()='creator']")
        props.creator = creatorNodes.first?.stringValue

        let subjectNodes = try xml.nodes(forXPath: "//*[local-name()='subject']")
        props.subject = subjectNodes.first?.stringValue

        let descNodes = try xml.nodes(forXPath: "//*[local-name()='description']")
        props.description = descNodes.first?.stringValue

        let keywordNodes = try xml.nodes(forXPath: "//*[local-name()='keywords']")
        props.keywords = keywordNodes.first?.stringValue

        let lastModNodes = try xml.nodes(forXPath: "//*[local-name()='lastModifiedBy']")
        props.lastModifiedBy = lastModNodes.first?.stringValue

        return props
    }
}
