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
        /// that the target resolves to, when that part is a regular media file
        /// (see `resolvedMediaFileName`). Nil otherwise.
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
    private static let nsA = "http://schemas.openxmlformats.org/drawingml/2006/main"
    private static let nsP = "http://schemas.openxmlformats.org/presentationml/2006/main"

    /// An `xsd:boolean` attribute value. The lexical space is `{true, false,
    /// 1, 0}` (case-sensitive; both `"1"` and `"true"` are ordinary XSD
    /// compliance, not extra permissiveness) with the `whiteSpace` facet
    /// `collapse` — a producer may pad the value with leading/trailing XML
    /// whitespace (`" true "`) and it still means `true`; `PptxWriter` itself
    /// always emits the bare `"1"`. Anything else (including an absent
    /// attribute) is `false`, matching the schema default for `flipH`／
    /// `flipV`. Trims only the four XML whitespace characters (space, tab,
    /// CR, LF) — not `.whitespacesAndNewlines`, which also strips Unicode
    /// whitespace (e.g. non-breaking space) outside XSD's whiteSpace facet
    /// and would accept lexically-invalid input as if it were padded
    /// (Codex review round 1 LOW fixed the missing trim; round 2 LOW
    /// tightened the trim set to match the XSD facet exactly).
    static func parseXSDBoolean(_ value: String?) -> Bool {
        let xmlWhitespace = CharacterSet(charactersIn: " \t\r\n")
        guard let trimmed = value?.trimmingCharacters(in: xmlWhitespace) else { return false }
        return trimmed == "1" || trimmed == "true"
    }

    // MARK: - Public API

    /// 讀取 .pptx 檔案並解析為 Presentation
    public static func read(from url: URL) throws -> Presentation {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw PPTXError.fileNotFound(url.path)
        }

        let tempDir = try ZipHelper.unzip(url)
        defer { ZipHelper.cleanup(tempDir) }
        return try read(unpackedPackageAt: tempDir)
    }

    /// Parses a package that has already been extracted to `tempDir`.
    static func read(unpackedPackageAt tempDir: URL) throws -> Presentation {
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

        // 5. 提取圖片資源（連同來源套件為各 part 宣告的 content type）
        presentation.images = try extractImages(from: tempDir, contentTypes: try parseContentTypes(in: tempDir))

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
    /// and that part passes `isRegularMediaFile` (a regular file, not a link,
    /// really inside the package's `ppt/media`).
    static func resolvedMediaFileName(for rel: Rel, sourcePartPath: String, packageRoot: URL) -> String? {
        guard rel.isImage, !rel.isExternal,
              let partPath = resolvePartPath(target: rel.target, relativeTo: sourcePartPath) else { return nil }
        let segments = partPath.split(separator: "/")
        guard segments.count == 3, segments[0] == "ppt", segments[1] == "media" else { return nil }

        guard let realMedia = realMediaDirectory(packageRoot: packageRoot),
              isRegularMediaFile(atPath: packageRoot.appendingPathComponent(partPath).path,
                                 realMediaDirectory: realMedia) else { return nil }
        return String(segments[2])
    }

    // MARK: - Media file safety
    //
    // One check decides what counts as a media part, for both the picture →
    // media link (`resolvedMediaFileName`) and the media read
    // (`extractImages`): a regular file — by `lstat`, so a symbolic link,
    // FIFO, socket, device or directory never qualifies and is never opened —
    // whose real path is directly inside the package's real `ppt/media`.

    /// Real path of the package's `ppt/media`, or nil when `ppt` or
    /// `ppt/media` is missing, is not a directory, is a symbolic link, or
    /// resolves outside the package root.
    static func realMediaDirectory(packageRoot: URL) -> String? {
        for component in ["ppt", "ppt/media"] {
            guard fileType(atPath: packageRoot.appendingPathComponent(component).path) == S_IFDIR else {
                return nil
            }
        }
        guard let realRoot = realPath(packageRoot.path),
              let realMedia = realPath(packageRoot.appendingPathComponent("ppt/media").path),
              realMedia.hasPrefix(realRoot + "/") else { return nil }
        return realMedia
    }

    /// Whether `path` is a regular file (not followed if it is a link) whose
    /// real path lies directly inside `realMediaDirectory`.
    static func isRegularMediaFile(atPath path: String, realMediaDirectory: String) -> Bool {
        guard fileType(atPath: path) == S_IFREG, let real = realPath(path) else { return false }
        return (real as NSString).deletingLastPathComponent == realMediaDirectory
    }

    /// `lstat` file type bits (`S_IFREG`, `S_IFDIR`, `S_IFLNK`, …), or nil.
    private static func fileType(atPath path: String) -> mode_t? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return info.st_mode & S_IFMT
    }

    private static func realPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
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

        // 嵌入或連結的音訊／影片，涵蓋兩類 pptx-swift 都不建模、寫出時會遺失的來源：
        //
        // 1. CT_ApplicationNonVisualDrawingProps 的 EG_Media choice group
        //    （ECMA-376 Part 1 §19.3.1.1，DrawingML 命名空間）五種都要涵蓋，
        //    不是只有 audioFile／videoFile（Codex R1 HIGH 2）。
        // 2. 換場音效與動畫播放音效（`p:transition/p:sndAc/p:stSnd/p:snd`、
        //    animation 的 play-sound 效果），走 CT_EmbeddedWAVAudioFile 的
        //    `p:snd`（PresentationML 命名空間），跟 EG_Media 是不同機制
        //    （Codex R2 HIGH：只查 EG_Media 漏掉這類）。`SlideTransition`
        //    模型本來就沒有音效欄位，reader／writer 目前完全不解析
        //    `p:sndAc`，所以這類音效的丟失連偵測都沒有，遑論拒絕。
        //
        // 用 local-name() 撈節點後在 Swift 端核對 `.uri`，不靠 XPath 的
        // namespace-uri()：Foundation 的 XPath 引擎在 attribute node 上已知
        // 不可靠（PackageInspector.relationshipReferences 的註解），element
        // node 上沒把握，乾脆兩者都不依賴（Codex R2 MEDIUM——先前版本沒有
        // namespace 檢查，理論上會被同名但不相干命名空間的擴充元素誤觸發）。
        let unsupportedMediaElements: [(localName: String, namespace: String)] = [
            ("audioFile", nsA), ("videoFile", nsA), ("wavAudioFile", nsA),
            ("audioCd", nsA), ("quickTimeFile", nsA),
            ("snd", nsP),
        ]
        let unsupportedMediaXPath = Set(unsupportedMediaElements.map(\.localName))
            .map { "//*[local-name()='\($0)']" }
            .joined(separator: " | ")
        let expectedNamespace = Dictionary(unsupportedMediaElements.map { ($0.localName, $0.namespace) },
                                            uniquingKeysWith: { first, _ in first })
        let candidates = try xml.nodes(forXPath: unsupportedMediaXPath)
        slide.containsUnsupportedMedia = candidates.contains { node in
            guard let element = node as? XMLElement, let name = element.localName else { return false }
            return expectedNamespace[name] == element.uri
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
            case "cxnSp":
                let connector = try parseConnector(element)
                elements.append(.connector(connector))
            case "nvGrpSpPr", "grpSpPr":
                // spTree／grpSp 自己的結構性子元素（非視覺屬性、群組屬性），
                // 不是「內容」——PptxWriter 的樣板本來就無條件寫出它自己的
                // 版本，原樣保留這兩個會在輸出裡重複一份，不是遺失，是損毀。
                // 跟 #7 以前既有行為一致：一直是 default: break 的一部分。
                break
            default:
                // 其餘未建模的子元素（`mc:AlternateContent`、`p:contentPart`、
                // 或任何未來的未知元素）：原樣保留其 XML，不默默丟掉
                // （PsychQuant/pptx-swift#9）。
                elements.append(.raw(try parseRawSlideElement(element)))
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
                               rotation: &shape.rotation, flipHorizontal: &shape.flipHorizontal, flipVertical: &shape.flipVertical,
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

            // r:link：外部連結圖片。只在該 relationship 確實是 TargetMode="External"
            // 時採用其 Target，避免把內部 relationship 的相對路徑誤當成外部連結。
            if let linkId = blip.attribute(forLocalName: "link", uri: nsR)?.stringValue
                ?? blip.attribute(forName: "r:link")?.stringValue,
               !linkId.isEmpty,
               let linkRel = relationships.first(where: { $0.id == linkId }), linkRel.isExternal {
                picture.externalImageTarget = linkRel.target
            }
        }

        // Crop (#2)
        picture.sourceRect = try parseSourceRect(element)

        // Position and size
        if let spPr = try element.nodes(forXPath: "./*[local-name()='spPr']").first as? XMLElement {
            var fill: ShapeFill? = nil
            var outline: ShapeOutline? = nil
            var geometry: ShapeGeometry = .rect
            parseShapeProperties(spPr, position: &picture.position, size: &picture.size,
                               rotation: &picture.rotation, flipHorizontal: &picture.flipHorizontal, flipVertical: &picture.flipVertical,
                               fill: &fill, outline: &outline, geometry: &geometry)
        }

        return picture
    }

    /// `<a:srcRect>` of a picture's `blipFill`, or nil when there is none.
    /// An edge that is absent or unparsable takes the schema default, 0.
    private static func parseSourceRect(_ pic: XMLElement) throws -> PictureSourceRect? {
        guard let srcRect = try pic.nodes(
            forXPath: "./*[local-name()='blipFill']/*[local-name()='srcRect']"
        ).first as? XMLElement else { return nil }
        func edge(_ name: String) -> Int {
            srcRect.attribute(forName: name)?.stringValue.flatMap(parsePercentage) ?? 0
        }
        return PictureSourceRect(left: edge("l"), top: edge("t"), right: edge("r"), bottom: edge("b"))
    }

    /// An `ST_Percentage` value in thousandths of a percent. Accepts both
    /// forms the schemas allow: the transitional integer (`"52941"`) and the
    /// strict percent string, a plain decimal followed by `%` (`"52.941%"`,
    /// rounded to the nearest thousandth). Returns nil for anything else —
    /// exponent notation (`"1e2%"`) included — and for values outside the
    /// 32-bit range `xsd:int` allows.
    static func parsePercentage(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let value: Double
        if trimmed.hasSuffix("%") {
            let number = trimmed.dropLast()
            guard number.range(of: #"^[+-]?([0-9]+(\.[0-9]*)?|\.[0-9]+)$"#, options: .regularExpression) != nil,
                  let percent = Double(number), percent.isFinite else { return nil }
            value = (percent * 1000).rounded()
        } else {
            guard let integer = Int(trimmed) else { return nil }
            value = Double(integer)
        }
        guard value >= Double(Int32.min), value <= Double(Int32.max) else { return nil }
        return Int(value)
    }

    // MARK: - Graphic Frame (Table)

    private static func parseGraphicFrame(_ element: XMLElement) throws -> GraphicFrame {
        var frame = GraphicFrame()

        if let cNvPr = try element.nodes(forXPath: ".//*[local-name()='cNvPr']").first as? XMLElement {
            frame.id = Int(cNvPr.attribute(forName: "id")?.stringValue ?? "0") ?? 0
            frame.name = cNvPr.attribute(forName: "name")?.stringValue ?? ""
        }

        // Position and size from xfrm (`p:xfrm`, same `a:CT_Transform2D` type
        // as a shape's `a:xfrm` — see the doc comment on `GraphicFrame.rotation`)
        if let xfrm = try element.nodes(forXPath: ".//*[local-name()='xfrm']").first as? XMLElement {
            if let off = try xfrm.nodes(forXPath: "*[local-name()='off']").first as? XMLElement {
                frame.position.x = Int(off.attribute(forName: "x")?.stringValue ?? "0") ?? 0
                frame.position.y = Int(off.attribute(forName: "y")?.stringValue ?? "0") ?? 0
            }
            if let ext = try xfrm.nodes(forXPath: "*[local-name()='ext']").first as? XMLElement {
                frame.size.width = Int(ext.attribute(forName: "cx")?.stringValue ?? "0") ?? 0
                frame.size.height = Int(ext.attribute(forName: "cy")?.stringValue ?? "0") ?? 0
            }
            frame.rotation = Int(xfrm.attribute(forName: "rot")?.stringValue ?? "0") ?? 0
            frame.flipHorizontal = parseXSDBoolean(xfrm.attribute(forName: "flipH")?.stringValue)
            frame.flipVertical = parseXSDBoolean(xfrm.attribute(forName: "flipV")?.stringValue)
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
                // 子座標系（a:chOff / a:chExt）：不存在時視同無縮放，等於群組自己的 off/ext
                // （與 GroupShape.init 未指定時的預設一致）。
                if let chOff = try xfrm.nodes(forXPath: "*[local-name()='chOff']").first as? XMLElement {
                    group.childOffset.x = Int(chOff.attribute(forName: "x")?.stringValue ?? "0") ?? 0
                    group.childOffset.y = Int(chOff.attribute(forName: "y")?.stringValue ?? "0") ?? 0
                } else {
                    group.childOffset = group.position
                }
                if let chExt = try xfrm.nodes(forXPath: "*[local-name()='chExt']").first as? XMLElement {
                    group.childExtent.width = Int(chExt.attribute(forName: "cx")?.stringValue ?? "0") ?? 0
                    group.childExtent.height = Int(chExt.attribute(forName: "cy")?.stringValue ?? "0") ?? 0
                } else {
                    group.childExtent = group.size
                }
                group.rotation = Int(xfrm.attribute(forName: "rot")?.stringValue ?? "0") ?? 0
                group.flipHorizontal = parseXSDBoolean(xfrm.attribute(forName: "flipH")?.stringValue)
                group.flipVertical = parseXSDBoolean(xfrm.attribute(forName: "flipV")?.stringValue)
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
            case "cxnSp":
                group.elements.append(.connector(try parseConnector(childElement)))
            case "nvGrpSpPr", "grpSpPr":
                // 群組自己的結構性子元素，不是內容——理由同 parseShapeTree
                // 的同名 case（PsychQuant/pptx-swift#9）。
                break
            default:
                group.elements.append(.raw(try parseRawSlideElement(childElement)))
            }
        }

        return group
    }

    // MARK: - Shape Properties

    private static func parseShapeProperties(
        _ spPr: XMLElement,
        position: inout Position,
        size: inout Size,
        rotation: inout Int,
        flipHorizontal: inout Bool,
        flipVertical: inout Bool,
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
            // rot／flipH／flipV (ECMA-376 Part 1 §20.1.7.6, CT_Transform2D):
            // attributes of the xfrm element itself, not child elements.
            // `rot` is accepted as-is (ST_Angle is an unrestricted xsd:int);
            // out-of-canonical-range values are only normalized on write.
            rotation = Int(xfrm.attribute(forName: "rot")?.stringValue ?? "0") ?? 0
            flipHorizontal = parseXSDBoolean(xfrm.attribute(forName: "flipH")?.stringValue)
            flipVertical = parseXSDBoolean(xfrm.attribute(forName: "flipV")?.stringValue)
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
            // 線條端點（`a:headEnd`／`a:tailEnd`）：任何 `a:ln` 上 schema 都允許，
            // 最常見於連接線（`p:cxnSp`）表示箭頭方向（PsychQuant/pptx-swift#9）。
            func lineEnd(_ localName: String) -> LineEndStyle? {
                guard let el = try? ln.nodes(forXPath: "*[local-name()='\(localName)']").first as? XMLElement else { return nil }
                let type = el.attribute(forName: "type")?.stringValue
                let width = el.attribute(forName: "w")?.stringValue
                let length = el.attribute(forName: "len")?.stringValue
                guard type != nil || width != nil || length != nil else { return nil }
                return LineEndStyle(type: type, width: width, length: length)
            }
            shapeOutline.headEnd = lineEnd("headEnd")
            shapeOutline.tailEnd = lineEnd("tailEnd")
            outline = shapeOutline
        }
    }

    // MARK: - Connector

    /// `p:cxnSp`（PsychQuant/pptx-swift#9）：`spPr` 是與 `p:sp`／`p:pic` 完全
    /// 相同的 complex type，因此重用 `parseShapeProperties`；連接線特有的只有
    /// `p:cNvCxnSpPr` 底下可能的 `a:stCxn`／`a:endCxn`。
    private static func parseConnector(_ element: XMLElement) throws -> Connector {
        var connector = Connector()

        if let cNvPr = try element.nodes(forXPath: ".//*[local-name()='cNvPr']").first as? XMLElement {
            connector.id = Int(cNvPr.attribute(forName: "id")?.stringValue ?? "0") ?? 0
            connector.name = cNvPr.attribute(forName: "name")?.stringValue ?? ""
        }

        if let cNvCxnSpPr = try element.nodes(
            forXPath: "./*[local-name()='nvCxnSpPr']/*[local-name()='cNvCxnSpPr']"
        ).first as? XMLElement {
            func connection(_ localName: String) -> ConnectionSite? {
                guard let el = try? cNvCxnSpPr.nodes(forXPath: "*[local-name()='\(localName)']").first as? XMLElement,
                      let shapeId = Int(el.attribute(forName: "id")?.stringValue ?? ""),
                      let idx = Int(el.attribute(forName: "idx")?.stringValue ?? "") else { return nil }
                return ConnectionSite(shapeId: shapeId, index: idx)
            }
            connector.startConnection = connection("stCxn")
            connector.endConnection = connection("endCxn")
        }

        if let spPr = try element.nodes(forXPath: "./*[local-name()='spPr']").first as? XMLElement {
            var fill: ShapeFill? = nil
            parseShapeProperties(spPr, position: &connector.position, size: &connector.size,
                               rotation: &connector.rotation, flipHorizontal: &connector.flipHorizontal, flipVertical: &connector.flipVertical,
                               fill: &fill, outline: &connector.outline, geometry: &connector.geometry)
            // 預設幾何的調整值（a:prstGeom/a:avLst/a:gd），彎折／曲線連接線
            // 的實際轉折點常偏離預設路徑，靠這些調整值記錄（Codex round 1
            // review：先前完全不讀，寫出時永遠變回預設路徑）。
            if let avLst = try spPr.nodes(forXPath: "*[local-name()='prstGeom']/*[local-name()='avLst']").first as? XMLElement {
                for gd in try avLst.nodes(forXPath: "*[local-name()='gd']") {
                    guard let gdElement = gd as? XMLElement,
                          let name = gdElement.attribute(forName: "name")?.stringValue,
                          let formula = gdElement.attribute(forName: "fmla")?.stringValue else { continue }
                    connector.adjustments.append(GeometryAdjustment(name: name, formula: formula))
                }
            }
        }

        return connector
    }

    // MARK: - Raw (unmodeled) elements

    /// An element `parseShapeTree`／`parseGroupShape` does not recognize
    /// (`mc:AlternateContent`, `p:contentPart`, or anything future): captures
    /// its exact original XML self-contained (see `RawSlideElement.xml`), every
    /// `cNvPr/@id` in its subtree, and whether it references any relationship
    /// (PsychQuant/pptx-swift#9).
    private static func parseRawSlideElement(_ element: XMLElement) throws -> RawSlideElement {
        let localName = element.localName ?? element.name ?? "unknown"

        let ids = try element.nodes(forXPath: ".//*[local-name()='cNvPr']/@id")
            .compactMap { $0.stringValue }
            .compactMap { Int($0) }

        // Foundation 的 XPath 在 attribute node 上不可靠地支援
        // namespace-uri()（PackageInspector.relationshipReferences 的既有
        // 註解），所以撈全部屬性後在 Swift 端核對 .uri，不靠 XPath 判斷命名空間
        // （跟 #5／#7 既有的偵測手法一致）。
        let allAttrs = (try? element.nodes(forXPath: "(@* | .//@*)")) ?? []
        let referencesRelationship = allAttrs.contains { $0.uri == nsR }

        return RawSlideElement(
            localName: localName,
            xml: selfContainedXMLString(for: element),
            elementIds: ids,
            referencesRelationship: referencesRelationship
        )
    }

    /// `element.xmlString`, but with every namespace binding inherited from
    /// an ancestor (not locally re-declared on `element` itself) re-declared
    /// as an `xmlns:`／`xmlns` attribute on the fragment's own root —
    /// `XMLElement.xmlString` on a node detached from its parsed document
    /// does not re-declare a namespace the node only inherited (verified
    /// empirically against Foundation's actual behavior, not documented), so
    /// `<mc:AlternateContent>` copied out of a `<p:spTree xmlns:mc="...">`
    /// would otherwise silently lose the binding that makes its own `mc:`
    /// tag names resolvable once it is spliced into a different XML document
    /// (PsychQuant/pptx-swift#9).
    ///
    /// Declares **every** inherited binding unconditionally, rather than
    /// first scanning the serialized text for which prefixes look "used":
    /// a round 1 Codex review caught two real gaps in that scan-first
    /// design — it cannot see a prefix that appears only inside an
    /// `mc:Choice`／`mc:AlternateContent`'s `Requires` (or `mc:Ignorable`)
    /// attribute *value* (a space-separated list of prefixes, not an
    /// element／attribute name the scan would match), and it silently
    /// dropped the unprefixed default namespace entirely. Declaring
    /// everything inherited — an extra, unused `xmlns:` binding is
    /// harmless, valid XML — closes both without trying to enumerate every
    /// place OOXML can spell a namespace dependency.
    static func selfContainedXMLString(for element: XMLElement) -> String {
        var raw = element.xmlString

        // Every ancestor's locally-declared namespaces, outermost first so a
        // closer (later) re-declaration of the same prefix overrides it —
        // this is the effective in-scope binding at `element`'s position,
        // reconstructed by hand because `XMLElement.resolveNamespace(forName:)`
        // does not reliably walk the ancestor chain (verified empirically).
        // `""` is the dictionary key for the unprefixed default namespace.
        var chain: [XMLElement] = []
        var current: XMLNode? = element
        while let el = current as? XMLElement {
            chain.append(el)
            current = el.parent
        }
        var inScope: [String: String] = [:]
        for el in chain.reversed() {
            for ns in el.namespaces ?? [] {
                guard let uri = ns.stringValue else { continue }
                inScope[ns.name ?? ""] = uri
            }
        }
        guard !inScope.isEmpty else { return raw }

        // Only what `element` does not already declare locally on itself —
        // checked against `element.namespaces` (this node's own local
        // declarations), never against whether the *serialized text*
        // contains a matching substring anywhere: a round 1 Codex review
        // caught that a whole-fragment text search is fooled by a *different*
        // scope re-declaring the same prefix to a different URI deeper in
        // the subtree (valid, ordinary XML nesting) — that inner
        // re-declaration would wrongly suppress the outer one this root
        // actually needs.
        let rootLocallyDeclared = Set((element.namespaces ?? []).map { $0.name ?? "" })
        let declarations = inScope
            .filter { !rootLocallyDeclared.contains($0.key) }
            .sorted { $0.key < $1.key }
            .map { prefix, uri -> String in
                let escapedURI = escapeXMLAttributeValue(uri)
                return prefix.isEmpty ? "xmlns=\"\(escapedURI)\"" : "xmlns:\(prefix)=\"\(escapedURI)\""
            }
        guard !declarations.isEmpty,
              // OOXML element/attribute names are always simple ASCII
              // identifiers in practice (the schemas define them that way);
              // this does not accept the full XML Name production (Unicode
              // letters, combining marks, …) for an adversarial root tag —
              // an accepted, documented boundary, not a silent gap.
              let tagNameRange = raw.range(of: #"^<[A-Za-z_][\w:.\-]*"#, options: .regularExpression) else { return raw }
        raw.insert(contentsOf: " " + declarations.joined(separator: " "), at: tagNameRange.upperBound)
        return raw
    }

    /// Full XML attribute-value escaping (`&`, `<`, `"`) for a namespace URI
    /// being written into a synthesized `xmlns:*="..."` attribute — a round 1
    /// Codex review caught that escaping only `"` leaves a URI containing a
    /// literal `&` (uncommon but valid, e.g. a query-string-bearing extension
    /// namespace) producing malformed output once re-serialized.
    private static func escapeXMLAttributeValue(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
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

    /// `[Content_Types].xml`: `Override` entries keyed by lowercased,
    /// percent-decoded part name (`/ppt/media/image1.png`) and `Default`
    /// entries keyed by lowercased extension. Empty when the part is missing
    /// or unreadable — the declared types are only a hint for the writer.
    struct ContentTypes {
        var overrides: [String: String] = [:]
        var defaults: [String: String] = [:]

        func contentType(ofPart partName: String) -> String? {
            if let type = overrides[partName.lowercased()] { return type }
            let last = (partName as NSString).lastPathComponent
            guard let dot = last.lastIndex(of: ".") else { return nil }
            return defaults[String(last[last.index(after: dot)...]).lowercased()]
        }
    }

    static func parseContentTypes(in tempDir: URL) throws -> ContentTypes {
        var types = ContentTypes()
        let url = tempDir.appendingPathComponent("[Content_Types].xml")
        guard FileManager.default.fileExists(atPath: url.path),
              let xml = try? XMLDocument(data: Data(contentsOf: url)) else { return types }
        for node in (try? xml.nodes(forXPath: "//*[local-name()='Override']")) ?? [] {
            guard let element = node as? XMLElement,
                  let name = element.attribute(forName: "PartName")?.stringValue,
                  let type = element.attribute(forName: "ContentType")?.stringValue else { continue }
            types.overrides[(name.removingPercentEncoding ?? name).lowercased()] = type
        }
        for node in (try? xml.nodes(forXPath: "//*[local-name()='Default']")) ?? [] {
            guard let element = node as? XMLElement,
                  let ext = element.attribute(forName: "Extension")?.stringValue,
                  let type = element.attribute(forName: "ContentType")?.stringValue else { continue }
            types.defaults[ext.lowercased()] = type
        }
        return types
    }

    private static func extractImages(from tempDir: URL, contentTypes: ContentTypes) throws -> [MediaFile] {
        // 與 resolvedMediaFileName 共用同一個檢查：只收真正位於 ppt/media/ 的一般檔案
        // （lstat 判定，不跟隨 symlink；子目錄、FIFO 等一律略過且不開啟）
        guard let realMedia = realMediaDirectory(packageRoot: tempDir) else { return [] }
        let mediaDir = tempDir.appendingPathComponent("ppt/media")
        let files = try FileManager.default.contentsOfDirectory(at: mediaDir, includingPropertiesForKeys: nil)
            .filter { isRegularMediaFile(atPath: $0.path, realMediaDirectory: realMedia) }

        return try files.map { fileURL -> MediaFile in
            let data = try Data(contentsOf: fileURL)
            return MediaFile(
                id: fileURL.lastPathComponent,
                fileName: fileURL.lastPathComponent,
                data: data,
                packageContentType: contentTypes.contentType(ofPart: "/ppt/media/\(fileURL.lastPathComponent)")
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
