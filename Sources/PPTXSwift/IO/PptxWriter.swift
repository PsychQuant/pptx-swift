import Foundation
import ZIPFoundation
import OOXMLSwift

/// PPTX 檔案寫入器
public struct PptxWriter {

    /// 將 Presentation 寫入 .pptx 檔案
    public static func write(_ presentation: Presentation, to url: URL) throws {
        // 在建立任何暫存檔之前先擋下寫出去會遺失內容的投影片（#5）：不要默默丟掉。
        try validateSupportedContent(presentation)

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("che-pptx-mcp-write")
            .appendingPathComponent(UUID().uuidString)

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // media 的 part 名稱與 content type（#1）：先決定，投影片的 image
        // relationship、[Content_Types].xml 與 ppt/media/ 都依同一份配置
        let media = MediaPartPlan(images: presentation.images)

        // 1. 寫入 [Content_Types].xml
        try writeContentTypes(presentation, media: media, to: tempDir)

        // 2. 寫入 _rels/.rels
        try writePackageRelationships(to: tempDir)

        // 3. 寫入 ppt/presentation.xml
        try writePresentationXML(presentation, to: tempDir)

        // 4. 寫入 ppt/_rels/presentation.xml.rels
        try writePresentationRelationships(presentation, to: tempDir)

        // 5. 寫入 theme
        try writeTheme(presentation.theme, to: tempDir)

        // 6. 寫入 slide master 和 layout
        try writeSlideMasterAndLayout(to: tempDir)

        // 7. 寫入每張投影片
        for (index, slide) in presentation.slides.enumerated() {
            try writeSlide(slide, index: index, media: media, to: tempDir)
        }

        // 8. 寫入 media
        try writeMedia(media, to: tempDir)

        // 9. 寫入 docProps
        try writeDocProps(presentation.properties, to: tempDir)

        // 10. 壓縮為 .pptx
        try ZipHelper.zip(tempDir, to: url)
    }

    /// 拒絕寫出無法保留其內容的投影片，而不是默默遺失。
    ///
    /// - Throws: `PPTXError.writeError` when a slide has embedded or linked
    ///   media (any DrawingML `EG_Media` element, usually paired with a
    ///   `p:timing` play trigger) or a transition sound (`p:snd`): the model
    ///   does not carry that structure, so writing would silently drop
    ///   playback (PsychQuant/pptx-swift#5). Also throws when a slide has a
    ///   `.raw` (unmodeled) element that references a relationship (`r:id`,
    ///   `r:embed`, `r:link`, …): see the decision note below
    ///   (PsychQuant/pptx-swift#9).
    private static func validateSupportedContent(_ presentation: Presentation) throws {
        for (index, slide) in presentation.slides.enumerated() {
            if slide.containsUnsupportedMedia {
                throw PPTXError.writeError(
                    "投影片 \(index + 1) 含音訊、影片或換場音效：pptx-swift 尚未建模播放觸發、時間軸（p:timing）與換場音效，寫出會遺失播放能力，拒絕存檔"
                )
            }
            // 未建模子元素（mc:AlternateContent／p:contentPart／其他）本身用
            // raw XML 原樣寫回（見 serializeElement 的 .raw case），但若它
            // 引用了 relationship，pptx-swift 的 relationship 配置是「整份
            // 投影片重新配置」（SlideImageRelationships 從 rId2 起算，#1 既有
            // 設計），無法安全地知道原始 rId 在新配置下是否仍指向同一個
            // relationship、或撞上新配的 rId。與其冒險寫出一個 rId 失效或
            // 指錯 part 的檔案，選擇明確拒絕——跟 #5 對音訊／影片的選擇一致
            // （見 issue #9「決定與理由」的完整討論：曾考慮重新配置引用的
            // relationship 並改寫 raw XML 裡的 rId，但那需要在 raw 文字裡精準
            // 定位並替換屬性值，複雜度與風險都遠超過這張 issue 的範圍）。
            if let offending = firstUnwritableRawSlideElement(in: slide.elements) {
                throw PPTXError.writeError(
                    "投影片 \(index + 1) 含未建模的子元素 <\(offending.localName)> 引用了 relationship："
                        + "pptx-swift 無法安全地確保該 rId 在重新配置後仍有效、且不與新配的 rId 衝突，拒絕存檔"
                )
            }
        }
    }

    /// The first `.raw` element (at any nesting depth) whose subtree
    /// references a relationship, or nil.
    private static func firstUnwritableRawSlideElement(in elements: [SlideElement]) -> RawSlideElement? {
        for element in elements {
            switch element {
            case .raw(let raw) where raw.referencesRelationship:
                return raw
            case .group(let group):
                if let found = firstUnwritableRawSlideElement(in: group.elements) { return found }
            default:
                continue
            }
        }
        return nil
    }

    /// Normalizes an `ST_Angle` value (60,000ths of a degree) into the
    /// canonical non-negative range `[0, fullTurn)`. `ST_Angle` itself is an
    /// unrestricted `xsd:int` (ECMA-376 Part 1 §20.1.10.3) — every 32-bit
    /// value is schema-valid, so there is nothing to reject — but a rotation
    /// is periodic modulo one full turn, so a value outside this range names
    /// the exact same angle as its residue inside it. PowerPoint itself only
    /// ever emits values in `[0, fullTurn)`; normalizing on write keeps our
    /// output conventional without losing anything a renderer acts on.
    static func normalizedAngle(_ rawUnits: Int) -> Int {
        let fullTurn = 21_600_000
        let remainder = rawUnits % fullTurn
        return remainder < 0 ? remainder + fullTurn : remainder
    }

    /// The `rot`／`flipH`／`flipV` attributes to splice into an `<a:xfrm>`／
    /// `<p:xfrm>` opening tag, or the empty string when all three are at
    /// their schema default (0／false／false) — omitting the attributes
    /// entirely rather than writing them out at their default value keeps
    /// an unrotated, unflipped element's output byte-identical to before
    /// this support existed (PsychQuant/pptx-swift#7).
    static func xfrmTransformAttributes(rotation: Int, flipHorizontal: Bool, flipVertical: Bool) -> String {
        var attrs = ""
        let normalized = normalizedAngle(rotation)
        // Compare the *normalized* value to 0, not the raw one: a raw value
        // like -21_600_000 (a full turn backwards) normalizes to 0 and must
        // be omitted exactly like an ordinary unrotated element, not written
        // out as a literal `rot="0"`.
        if normalized != 0 { attrs += " rot=\"\(normalized)\"" }
        if flipHorizontal { attrs += " flipH=\"1\"" }
        if flipVertical { attrs += " flipV=\"1\"" }
        return attrs
    }

    /// 建立新的空白簡報
    public static func createNew() -> Presentation {
        var presentation = Presentation()
        presentation.theme = Theme(
            name: "Office Theme",
            colorScheme: ColorScheme(),
            fontScheme: FontScheme()
        )
        presentation.slides = [Slide()]
        return presentation
    }

    // MARK: - Content Types

    private static func writeContentTypes(_ presentation: Presentation, media: MediaPartPlan, to dir: URL) throws {
        // 每個 media part 都要有 content type，否則整個套件無效（PowerPoint 會要求修復）
        let builtInDefaults: Set<String> = ["rels", "xml", "png", "jpeg", "jpg"]
        let mediaDefaults = media.defaultContentTypes
            .filter { !builtInDefaults.contains($0.extension) }
            .map { "  <Default Extension=\"\($0.extension)\" ContentType=\"\(escapeXML($0.contentType))\"/>\n" }
            .joined()

        var xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Default Extension="png" ContentType="image/png"/>
          <Default Extension="jpeg" ContentType="image/jpeg"/>
          <Default Extension="jpg" ContentType="image/jpeg"/>
        \(mediaDefaults)  <Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>
          <Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>
          <Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/>
          <Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>
          <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
          <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
        """

        for (index, _) in presentation.slides.enumerated() {
            xml += """
              <Override PartName="/ppt/slides/slide\(index + 1).xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>
            """
        }

        for part in media.overriddenParts {
            xml += "\n  <Override PartName=\"/ppt/media/\(escapeXML(part.name))\" ContentType=\"\(escapeXML(part.contentType))\"/>"
        }

        xml += "\n</Types>"

        let contentTypesURL = dir.appendingPathComponent("[Content_Types].xml")
        try xml.write(to: contentTypesURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Package Relationships

    private static func writePackageRelationships(to dir: URL) throws {
        let relsDir = dir.appendingPathComponent("_rels")
        try FileManager.default.createDirectory(at: relsDir, withIntermediateDirectories: true)

        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/>
          <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
          <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
        </Relationships>
        """

        try xml.write(to: relsDir.appendingPathComponent(".rels"), atomically: true, encoding: .utf8)
    }

    // MARK: - Presentation XML

    private static func writePresentationXML(_ presentation: Presentation, to dir: URL) throws {
        let pptDir = dir.appendingPathComponent("ppt")
        try FileManager.default.createDirectory(at: pptDir, withIntermediateDirectories: true)

        var slideIdList = ""
        for (index, _) in presentation.slides.enumerated() {
            let slideId = 256 + index
            let rId = "rId\(index + 3)"  // rId1=master, rId2=theme, slides start at rId3
            slideIdList += "    <p:sldId id=\"\(slideId)\" r:id=\"\(rId)\"/>\n"
        }

        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
                        xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
                        xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
          <p:sldMasterIdLst>
            <p:sldMasterId id="2147483648" r:id="rId1"/>
          </p:sldMasterIdLst>
          <p:sldIdLst>
        \(slideIdList)  </p:sldIdLst>
          <p:sldSz cx="\(presentation.slideSize.width)" cy="\(presentation.slideSize.height)"/>
          <p:notesSz cx="\(presentation.slideSize.height)" cy="\(presentation.slideSize.width)"/>
        </p:presentation>
        """

        try xml.write(to: pptDir.appendingPathComponent("presentation.xml"), atomically: true, encoding: .utf8)
    }

    // MARK: - Presentation Relationships

    private static func writePresentationRelationships(_ presentation: Presentation, to dir: URL) throws {
        let relsDir = dir.appendingPathComponent("ppt/_rels")
        try FileManager.default.createDirectory(at: relsDir, withIntermediateDirectories: true)

        var rels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="slideMasters/slideMaster1.xml"/>
          <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="theme/theme1.xml"/>
        """

        for (index, _) in presentation.slides.enumerated() {
            let rId = "rId\(index + 3)"
            rels += "  <Relationship Id=\"\(rId)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide\" Target=\"slides/slide\(index + 1).xml\"/>\n"
        }

        rels += "</Relationships>"

        try rels.write(to: relsDir.appendingPathComponent("presentation.xml.rels"), atomically: true, encoding: .utf8)
    }

    // MARK: - Theme

    private static func writeTheme(_ theme: Theme?, to dir: URL) throws {
        let themeDir = dir.appendingPathComponent("ppt/theme")
        try FileManager.default.createDirectory(at: themeDir, withIntermediateDirectories: true)

        let cs = theme?.colorScheme ?? ColorScheme()
        let fs = theme?.fontScheme ?? FontScheme()
        let majorFont = fs.majorFont.isEmpty ? "Calibri Light" : fs.majorFont
        let minorFont = fs.minorFont.isEmpty ? "Calibri" : fs.minorFont

        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="\(theme?.name ?? "Office Theme")">
          <a:themeElements>
            <a:clrScheme name="\(cs.name.isEmpty ? "Office" : cs.name)">
              <a:dk1><a:srgbClr val="\(cs.dk1)"/></a:dk1>
              <a:lt1><a:srgbClr val="\(cs.lt1)"/></a:lt1>
              <a:dk2><a:srgbClr val="\(cs.dk2)"/></a:dk2>
              <a:lt2><a:srgbClr val="\(cs.lt2)"/></a:lt2>
              <a:accent1><a:srgbClr val="\(cs.accent1)"/></a:accent1>
              <a:accent2><a:srgbClr val="\(cs.accent2)"/></a:accent2>
              <a:accent3><a:srgbClr val="\(cs.accent3)"/></a:accent3>
              <a:accent4><a:srgbClr val="\(cs.accent4)"/></a:accent4>
              <a:accent5><a:srgbClr val="\(cs.accent5)"/></a:accent5>
              <a:accent6><a:srgbClr val="\(cs.accent6)"/></a:accent6>
              <a:hlink><a:srgbClr val="\(cs.hlink)"/></a:hlink>
              <a:folHlink><a:srgbClr val="\(cs.folHlink)"/></a:folHlink>
            </a:clrScheme>
            <a:fontScheme name="\(fs.name.isEmpty ? "Office" : fs.name)">
              <a:majorFont><a:latin typeface="\(majorFont)"/><a:ea typeface=""/><a:cs typeface=""/></a:majorFont>
              <a:minorFont><a:latin typeface="\(minorFont)"/><a:ea typeface=""/><a:cs typeface=""/></a:minorFont>
            </a:fontScheme>
            <a:fmtScheme name="Office">
              <a:fillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:fillStyleLst>
              <a:lnStyleLst><a:ln w="6350"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln><a:ln w="12700"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln><a:ln w="19050"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln></a:lnStyleLst>
              <a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst>
              <a:bgFillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:bgFillStyleLst>
            </a:fmtScheme>
          </a:themeElements>
        </a:theme>
        """

        try xml.write(to: themeDir.appendingPathComponent("theme1.xml"), atomically: true, encoding: .utf8)
    }

    // MARK: - Slide Master & Layout

    private static func writeSlideMasterAndLayout(to dir: URL) throws {
        // Slide Master
        let masterDir = dir.appendingPathComponent("ppt/slideMasters")
        try FileManager.default.createDirectory(at: masterDir, withIntermediateDirectories: true)

        let masterRelsDir = dir.appendingPathComponent("ppt/slideMasters/_rels")
        try FileManager.default.createDirectory(at: masterRelsDir, withIntermediateDirectories: true)

        let masterXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <p:sldMaster xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
                     xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
                     xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
          <p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/></p:spTree></p:cSld>
          <p:sldLayoutIdLst>
            <p:sldLayoutId id="2147483649" r:id="rId1"/>
          </p:sldLayoutIdLst>
        </p:sldMaster>
        """
        try masterXML.write(to: masterDir.appendingPathComponent("slideMaster1.xml"), atomically: true, encoding: .utf8)

        let masterRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>
          <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="../theme/theme1.xml"/>
        </Relationships>
        """
        try masterRels.write(to: masterRelsDir.appendingPathComponent("slideMaster1.xml.rels"), atomically: true, encoding: .utf8)

        // Slide Layout
        let layoutDir = dir.appendingPathComponent("ppt/slideLayouts")
        try FileManager.default.createDirectory(at: layoutDir, withIntermediateDirectories: true)

        let layoutRelsDir = dir.appendingPathComponent("ppt/slideLayouts/_rels")
        try FileManager.default.createDirectory(at: layoutRelsDir, withIntermediateDirectories: true)

        let layoutXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <p:sldLayout xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
                     xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
                     xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"
                     type="blank">
          <p:cSld name="Blank"><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/></p:spTree></p:cSld>
        </p:sldLayout>
        """
        try layoutXML.write(to: layoutDir.appendingPathComponent("slideLayout1.xml"), atomically: true, encoding: .utf8)

        let layoutRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="../slideMasters/slideMaster1.xml"/>
        </Relationships>
        """
        try layoutRels.write(to: layoutRelsDir.appendingPathComponent("slideLayout1.xml.rels"), atomically: true, encoding: .utf8)
    }

    // MARK: - Slide

    private static func writeSlide(_ slide: Slide, index: Int, media: MediaPartPlan, to dir: URL) throws {
        let slidesDir = dir.appendingPathComponent("ppt/slides")
        try FileManager.default.createDirectory(at: slidesDir, withIntermediateDirectories: true)

        let slideRelsDir = dir.appendingPathComponent("ppt/slides/_rels")
        try FileManager.default.createDirectory(at: slideRelsDir, withIntermediateDirectories: true)

        // Shape tree XML（圖片的 r:embed 由 imageRels 配置，rId1 保留給 slideLayout）
        var shapeXML = ""
        var nextId = 2
        var imageRels = SlideImageRelationships(media: media)
        for element in slide.elements {
            shapeXML += try serializeElement(element, nextId: &nextId, imageRels: &imageRels)
        }

        // Transition XML
        var transitionXML = ""
        if let transition = slide.transition, transition.type != .none {
            transitionXML = "  <p:transition spd=\"\(transition.speed.rawValue)\"><p:\(transition.type.rawValue)/></p:transition>\n"
        }

        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
               xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
               xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
          <p:cSld>
            <p:spTree>
              <p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>
              <p:grpSpPr/>
        \(shapeXML)    </p:spTree>
          </p:cSld>
        \(transitionXML)</p:sld>
        """

        try xml.write(to: slidesDir.appendingPathComponent("slide\(index + 1).xml"), atomically: true, encoding: .utf8)

        // Slide relationships：slideLayout + 此投影片上每個被引用的 media part 各一個 image
        // relationship，加上每個外部連結圖片（r:link）各一個 TargetMode="External" 的
        // image relationship（無對應 ppt/media/ part，Target 就是原始連結字串）
        var imageRelsXML = ""
        for entry in imageRels.entries {
            imageRelsXML += "  <Relationship Id=\"\(entry.id)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"../media/\(escapeXML(entry.partName))\"/>\n"
        }
        for entry in imageRels.linkEntries {
            imageRelsXML += "  <Relationship Id=\"\(entry.id)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"\(escapeXML(entry.target))\" TargetMode=\"External\"/>\n"
        }
        let slideRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>
        \(imageRelsXML)</Relationships>
        """
        try slideRels.write(to: slideRelsDir.appendingPathComponent("slide\(index + 1).xml.rels"), atomically: true, encoding: .utf8)
    }

    // MARK: - Element Serialization

    private static func serializeElement(
        _ element: SlideElement, nextId: inout Int, imageRels: inout SlideImageRelationships
    ) throws -> String {
        switch element {
        case .shape(let shape):
            return serializeShape(shape, nextId: &nextId)
        case .picture(let picture):
            // CT_Blip's r:embed and r:link are independent optional attributes
            // (ECMA-376 Part 1 §20.1.8.13), not alternatives: a picture linked
            // with a local cached copy ("Insert and Link" in PowerPoint) has
            // both, and both must survive a round trip (Codex review round 1,
            // HIGH 1 — the writer previously always preferred embed and
            // silently dropped a coexisting link).
            let embedId = try imageRels.embedId(for: picture)
            let linkId: String? = (picture.externalImageTarget.map { !$0.isEmpty } ?? false)
                ? imageRels.linkId(for: picture.externalImageTarget!)
                : nil
            return try serializePicture(picture, embedId: embedId, linkId: linkId, nextId: &nextId)
        case .graphicFrame(let frame):
            return serializeGraphicFrame(frame, nextId: &nextId)
        case .group(let group):
            return try serializeGroupShape(group, nextId: &nextId, imageRels: &imageRels)
        case .connector(let connector):
            return serializeConnector(connector, nextId: &nextId)
        case .raw(let raw):
            // 原樣寫回已經是 self-contained 的原始 XML（`RawSlideElement.xml`，見
            // `PptxReader.selfContainedXMLString`），不重新組裝、不動 nextId
            // （沒有型別化的 id 欄位可以配置）。relationship 引用的安全性已在
            // `validateSupportedContent` 把關，這裡不會走到不安全的情況
            // （PsychQuant/pptx-swift#9）。
            return "      \(raw.xml)\n"
        }
    }

    /// 群組（`p:grpSp`）：schema 上與 `p:spTree` 同一個 complex type
    /// （`CT_GroupShape`），子元素可以是 `p:sp`／`p:pic`／`p:graphicFrame`／`p:grpSp`
    /// 的任意排列與巢狀深度，因此直接重用 `serializeElement` 遞迴序列化每個子元素；
    /// `nextId` 與 `imageRels` 用 `inout` 貫穿整棵樹，群組內圖片與投影片其餘部分共用
    /// 同一份 `slideN.xml.rels`（relationship 是以 part 為範圍，不是以群組為範圍）。
    private static func serializeGroupShape(
        _ group: GroupShape, nextId: inout Int, imageRels: inout SlideImageRelationships
    ) throws -> String {
        let id = group.id > 0 ? group.id : nextId
        nextId = max(nextId, id + 1)

        var childXML = ""
        for element in group.elements {
            childXML += try serializeElement(element, nextId: &nextId, imageRels: &imageRels)
        }

        let xfrmAttrs = xfrmTransformAttributes(
            rotation: group.rotation, flipHorizontal: group.flipHorizontal, flipVertical: group.flipVertical)
        // CT_GroupShapeProperties (#12): xfrm?, EG_FillProperties?,
        // EG_EffectProperties?, scene3d?, extLst? — a smaller sequence than
        // CT_ShapeProperties (no geometry choice, no ln, no sp3d), so this
        // does not share `spPrTailExtrasXML` with Shape/Connector. `rawFillXML`
        // has no typed counterpart to be mutually exclusive with — `GroupShape`
        // has never modeled a typed fill.
        let extrasXML = [group.rawFillXML, group.effectXML, group.scene3dXML, group.extLstXML]
            .compactMap { $0 }.joined(separator: "\n                  ")

        return """
              <p:grpSp>
                <p:nvGrpSpPr>
                  <p:cNvPr id="\(id)" name="\(escapeXML(group.name))"/>
                  <p:cNvGrpSpPr/>
                  <p:nvPr/>
                </p:nvGrpSpPr>
                <p:grpSpPr>
                  <a:xfrm\(xfrmAttrs)>
                    <a:off x="\(group.position.x)" y="\(group.position.y)"/>
                    <a:ext cx="\(group.size.width)" cy="\(group.size.height)"/>
                    <a:chOff x="\(group.childOffset.x)" y="\(group.childOffset.y)"/>
                    <a:chExt cx="\(group.childExtent.width)" cy="\(group.childExtent.height)"/>
                  </a:xfrm>
                  \(extrasXML)
                </p:grpSpPr>
        \(childXML)      </p:grpSp>

        """
    }

    private static func serializeShape(_ shape: Shape, nextId: inout Int) -> String {
        let id = shape.id > 0 ? shape.id : nextId
        nextId = max(nextId, id + 1)

        var phXML = ""
        if let ph = shape.placeholder {
            phXML = "<p:ph type=\"\(ph.rawValue)\"/>"
        }

        // Geometry — EG_Geometry choice (PsychQuant/pptx-swift#12):
        // `customGeometryXML` (raw `<a:custGeom>`) takes priority and
        // *replaces* `<a:prstGeom>` entirely — writing both is invalid XML
        // (the schema only allows one).
        let geometryXML = shape.customGeometryXML
            ?? "<a:prstGeom prst=\"\(shape.geometry.rawValue)\"><a:avLst/></a:prstGeom>"

        // Fill — EG_FillProperties choice: `rawFillXML` (raw `<a:gradFill>`／
        // `<a:blipFill>`／`<a:pattFill>`／`<a:grpFill>`) takes priority over
        // the typed `fill`, same mutual-exclusivity reasoning as geometry.
        var typedFillXML = ""
        if let fill = shape.fill {
            switch fill {
            case .solid(let color):
                typedFillXML = "<a:solidFill><a:srgbClr val=\"\(color)\"/></a:solidFill>"
            case .schemeColor(let name):
                typedFillXML = "<a:solidFill><a:schemeClr val=\"\(name)\"/></a:solidFill>"
            case .noFill:
                typedFillXML = "<a:noFill/>"
            case .gradient:
                break
            }
        }
        let fillXML = shape.rawFillXML ?? typedFillXML

        var textBodyXML = ""
        if let textBody = shape.textBody {
            textBodyXML = serializeTextBody(textBody)
        }

        let xfrmAttrs = xfrmTransformAttributes(
            rotation: shape.rotation, flipHorizontal: shape.flipHorizontal, flipVertical: shape.flipVertical)
        // p:style（PsychQuant/pptx-swift#11）: CT_Shape's sequence places it
        // after spPr, before txBody — self-contained raw XML, spliced
        // verbatim (same pattern as RawSlideElement.xml). `styleXML == nil`
        // (the vast majority of shapes, and every shape before #11) writes
        // no tag at all, not an empty one.
        let styleXML = shape.styleXML ?? ""
        // effectLst／effectDag, scene3d, sp3d, extLst (#12): each raw, each
        // optional, each omitted (not an empty tag) when nil — same splice
        // pattern as the rest of this function's spPr children.
        let tailXML = spPrTailExtrasXML(
            effectXML: shape.effectXML, scene3dXML: shape.scene3dXML,
            sp3dXML: shape.sp3dXML, extLstXML: shape.extLstXML)

        return """
              <p:sp>
                <p:nvSpPr>
                  <p:cNvPr id="\(id)" name="\(escapeXML(shape.name))"/>
                  <p:cNvSpPr/>
                  <p:nvPr>\(phXML)</p:nvPr>
                </p:nvSpPr>
                <p:spPr>
                  <a:xfrm\(xfrmAttrs)>
                    <a:off x="\(shape.position.x)" y="\(shape.position.y)"/>
                    <a:ext cx="\(shape.size.width)" cy="\(shape.size.height)"/>
                  </a:xfrm>
                  \(geometryXML)
                  \(fillXML)
                  \(tailXML)
                </p:spPr>
                \(styleXML)
                \(textBodyXML)
              </p:sp>

        """
    }

    /// `<a:effectLst>`／`<a:effectDag>`, `<a:scene3d>`, `<a:sp3d>`,
    /// `<a:extLst>` — the tail of `CT_ShapeProperties`'s sequence, after
    /// `<a:ln>` (PsychQuant/pptx-swift#12). Each is raw, self-contained XML
    /// (`PptxReader.selfContainedXMLString`) or omitted entirely when nil —
    /// shared between `serializeShape` and `serializeConnector` since both
    /// use the exact same `CT_ShapeProperties` tail. `GroupShape`'s
    /// `grpSpPr` does NOT use this — `CT_GroupShapeProperties` has no `ln`
    /// or `sp3d` slot, so its assembly is separate (`serializeGroupShape`).
    private static func spPrTailExtrasXML(
        effectXML: String?, scene3dXML: String?, sp3dXML: String?, extLstXML: String?
    ) -> String {
        [effectXML, scene3dXML, sp3dXML, extLstXML].compactMap { $0 }.joined(separator: "\n                  ")
    }

    /// `p:cxnSp`（PsychQuant/pptx-swift#9）：`spPr` 用與 `p:sp`／`p:pic` 相同的
    /// `xfrmTransformAttributes` 共用 helper；連接線特有的只有 `p:cNvCxnSpPr`
    /// 底下的 `a:stCxn`／`a:endCxn` 與線條端點（`a:ln` 的 `headEnd`／`tailEnd`）。
    private static func serializeConnector(_ connector: Connector, nextId: inout Int) -> String {
        let id = connector.id > 0 ? connector.id : nextId
        nextId = max(nextId, id + 1)

        var cNvCxnSpPrXML = ""
        if let start = connector.startConnection {
            cNvCxnSpPrXML += "<a:stCxn id=\"\(start.shapeId)\" idx=\"\(start.index)\"/>"
        }
        if let end = connector.endConnection {
            cNvCxnSpPrXML += "<a:endCxn id=\"\(end.shapeId)\" idx=\"\(end.index)\"/>"
        }

        let xfrmAttrs = xfrmTransformAttributes(
            rotation: connector.rotation, flipHorizontal: connector.flipHorizontal, flipVertical: connector.flipVertical)
        let lnXML = connector.outline.map(serializeConnectorLine) ?? ""
        // 沒有調整值時寫空 <a:avLst/>，跟 #9 之前逐位元組相同；有的話原樣
        // 寫回每一個 <a:gd>（Codex round 1 review：先前永遠寫空，會靜默丟棄
        // 讀進來的調整值）。
        let avLstXML = connector.adjustments.isEmpty
            ? "<a:avLst/>"
            : "<a:avLst>" + connector.adjustments.map { "<a:gd name=\"\(escapeXML($0.name))\" fmla=\"\(escapeXML($0.formula))\"/>" }.joined() + "</a:avLst>"
        // Geometry — EG_Geometry choice (#12): `customGeometryXML` replaces
        // `<a:prstGeom>` (and its adjustments, meaningless for a custGeom
        // path) entirely.
        let geometryXML = connector.customGeometryXML
            ?? "<a:prstGeom prst=\"\(connector.geometry.rawValue)\">\(avLstXML)</a:prstGeom>"
        // rawFillXML (#12): Connector has no typed fill to be "mutually
        // exclusive" with — see the doc comment on `Connector.rawFillXML`.
        let fillXML = connector.rawFillXML ?? ""
        // p:style（PsychQuant/pptx-swift#11）: CT_Connector's sequence places
        // it right after spPr, as the element's last child (no txBody to
        // precede, unlike CT_Shape) — same self-contained-XML splice as
        // Shape.styleXML.
        let styleXML = connector.styleXML ?? ""
        let tailXML = spPrTailExtrasXML(
            effectXML: connector.effectXML, scene3dXML: connector.scene3dXML,
            sp3dXML: connector.sp3dXML, extLstXML: connector.extLstXML)

        return """
              <p:cxnSp>
                <p:nvCxnSpPr>
                  <p:cNvPr id="\(id)" name="\(escapeXML(connector.name))"/>
                  <p:cNvCxnSpPr>\(cNvCxnSpPrXML)</p:cNvCxnSpPr>
                  <p:nvPr/>
                </p:nvCxnSpPr>
                <p:spPr>
                  <a:xfrm\(xfrmAttrs)>
                    <a:off x="\(connector.position.x)" y="\(connector.position.y)"/>
                    <a:ext cx="\(connector.size.width)" cy="\(connector.size.height)"/>
                  </a:xfrm>
                  \(geometryXML)
                  \(fillXML)
                  \(lnXML)
                  \(tailXML)
                </p:spPr>
                \(styleXML)
              </p:cxnSp>

        """
    }

    /// `<a:ln>`（ECMA-376 `CT_LineProperties`，child order: fill, then
    /// `headEnd`／`tailEnd`）：width／color／兩個端點皆為可選，全部缺席時
    /// 省略整個 `<a:ln>` 標籤——跟 `xfrmTransformAttributes` 同一個「沒有值
    /// 就不寫屬性／標籤」慣例。
    private static func serializeConnectorLine(_ outline: ShapeOutline) -> String {
        var attrs = ""
        if let width = outline.width { attrs += " w=\"\(width)\"" }

        var children = ""
        if let color = outline.color {
            children += "<a:solidFill><a:srgbClr val=\"\(color)\"/></a:solidFill>"
        }
        func lineEndXML(_ tag: String, _ style: LineEndStyle?) -> String {
            guard let style else { return "" }
            var lineAttrs = ""
            if let type = style.type { lineAttrs += " type=\"\(type)\"" }
            if let width = style.width { lineAttrs += " w=\"\(width)\"" }
            if let length = style.length { lineAttrs += " len=\"\(length)\"" }
            return "<a:\(tag)\(lineAttrs)/>"
        }
        children += lineEndXML("headEnd", outline.headEnd)
        children += lineEndXML("tailEnd", outline.tailEnd)

        guard !attrs.isEmpty || !children.isEmpty else { return "" }
        return "<a:ln\(attrs)>\(children)</a:ln>"
    }

    /// `embedId`／`linkId` are the relationship Ids this slide's rels give
    /// the picture's media part (`r:embed`) and external link (`r:link`)
    /// respectively — independent OOXML attributes (`CT_Blip`, ECMA-376
    /// Part 1 §20.1.8.13), not alternatives: a picture inserted as "linked
    /// with a local cache" carries both, and a nil one is simply omitted.
    /// `<a:blip/>` with neither is a picture with no media at all, never a
    /// reference to a relationship that does not exist.
    private static func serializePicture(_ picture: Picture, embedId: String?, linkId: String?, nextId: inout Int) throws -> String {
        let id = picture.id > 0 ? picture.id : nextId
        nextId = max(nextId, id + 1)
        var blipAttrs = ""
        if let embedId { blipAttrs += " r:embed=\"\(embedId)\"" }
        if let linkId { blipAttrs += " r:link=\"\(linkId)\"" }
        let blipXML = blipAttrs.isEmpty ? "<a:blip/>" : "<a:blip\(blipAttrs)/>"
        // CT_BlipFillProperties order: blip, srcRect, then the fill mode (#2)
        let srcRectXML = try picture.sourceRect.map { try serializeSourceRect($0, pictureId: id) } ?? ""
        let xfrmAttrs = xfrmTransformAttributes(
            rotation: picture.rotation, flipHorizontal: picture.flipHorizontal, flipVertical: picture.flipVertical)

        return """
              <p:pic>
                <p:nvPicPr>
                  <p:cNvPr id="\(id)" name="\(escapeXML(picture.name))"/>
                  <p:cNvPicPr/>
                  <p:nvPr/>
                </p:nvPicPr>
                <p:blipFill>
                  \(blipXML)\(srcRectXML)
                  <a:stretch><a:fillRect/></a:stretch>
                </p:blipFill>
                <p:spPr>
                  <a:xfrm\(xfrmAttrs)>
                    <a:off x="\(picture.position.x)" y="\(picture.position.y)"/>
                    <a:ext cx="\(picture.size.width)" cy="\(picture.size.height)"/>
                  </a:xfrm>
                  <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
                </p:spPr>
              </p:pic>

        """
    }

    /// `<a:srcRect>` with only the non-zero edges (0 is the schema default).
    ///
    /// - Throws: `PPTXError.writeError` when an edge does not fit `xsd:int`:
    ///   written as is it would be invalid, and read back as 0.
    private static func serializeSourceRect(_ rect: PictureSourceRect, pictureId: Int) throws -> String {
        guard rect.isRepresentable else {
            throw PPTXError.writeError(
                "圖片 id=\(pictureId) 的 srcRect 超出 32 位元整數範圍（l=\(rect.left) t=\(rect.top) r=\(rect.right) b=\(rect.bottom)），無法寫出"
            )
        }
        let edges = [("l", rect.left), ("t", rect.top), ("r", rect.right), ("b", rect.bottom)]
        let attributes = edges.filter { $0.1 != 0 }.map { " \($0.0)=\"\($0.1)\"" }.joined()
        return "<a:srcRect\(attributes)/>"
    }

    private static func serializeGraphicFrame(_ frame: GraphicFrame, nextId: inout Int) -> String {
        guard let table = frame.table else { return "" }
        let id = frame.id > 0 ? frame.id : nextId
        nextId = max(nextId, id + 1)

        var gridXML = ""
        for col in table.columns {
            gridXML += "          <a:gridCol w=\"\(col.width)\"/>\n"
        }

        var rowsXML = ""
        for row in table.rows {
            rowsXML += "          <a:tr h=\"\(row.height)\">\n"
            for cell in row.cells {
                rowsXML += "            <a:tc>\n"
                rowsXML += "              \(serializeTextBody(cell.textBody, wrappingElement: "a:txBody"))\n"
                rowsXML += "              <a:tcPr/>\n"
                rowsXML += "            </a:tc>\n"
            }
            rowsXML += "          </a:tr>\n"
        }

        let xfrmAttrs = xfrmTransformAttributes(
            rotation: frame.rotation, flipHorizontal: frame.flipHorizontal, flipVertical: frame.flipVertical)

        return """
              <p:graphicFrame>
                <p:nvGraphicFramePr>
                  <p:cNvPr id="\(id)" name="\(escapeXML(frame.name))"/>
                  <p:cNvGraphicFramePr><a:graphicFrameLocks noGrp="1"/></p:cNvGraphicFramePr>
                  <p:nvPr/>
                </p:nvGraphicFramePr>
                <p:xfrm\(xfrmAttrs)>
                  <a:off x="\(frame.position.x)" y="\(frame.position.y)"/>
                  <a:ext cx="\(frame.size.width)" cy="\(frame.size.height)"/>
                </p:xfrm>
                <a:graphic>
                  <a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/table">
                    <a:tbl>
                      <a:tblPr/>
                      <a:tblGrid>
        \(gridXML)              </a:tblGrid>
        \(rowsXML)            </a:tbl>
                  </a:graphicData>
                </a:graphic>
              </p:graphicFrame>

        """
    }

    /// `wrappingElement` defaults to `p:txBody` (`CT_Shape`'s own type, used
    /// by `p:sp`/`p:pic`). A table cell (`a:tc`, `CT_TableCell`) needs
    /// `a:txBody` instead — the *same* DrawingML `CT_TextBody` structure
    /// (`a:bodyPr`/`a:lstStyle`/`a:p`…) either way, only the wrapping
    /// element's own namespace differs (PsychQuant/pptx-swift#10: writing
    /// `p:txBody` here was a namespace error ECMA-376 does not permit for
    /// `CT_TableCell`, discovered because LibreOffice's stricter importer
    /// silently stopped rendering everything in the shape tree from that
    /// table onward once it hit the mistagged element).
    private static func serializeTextBody(_ textBody: TextBody, wrappingElement: String = "p:txBody") -> String {
        var paragraphsXML = ""
        for para in textBody.paragraphs {
            var pPrXML = ""
            if let alignment = para.properties.alignment {
                pPrXML = "<a:pPr algn=\"\(alignment.rawValue)\"/>"
            }

            var runsXML = ""
            for run in para.runs {
                var rPrAttrs = ""
                if let sz = run.properties.fontSize { rPrAttrs += " sz=\"\(sz)\"" }
                if run.properties.bold == true { rPrAttrs += " b=\"1\"" }
                if run.properties.italic == true { rPrAttrs += " i=\"1\"" }
                if let lang = run.properties.language { rPrAttrs += " lang=\"\(lang)\"" }

                var rPrChildren = ""
                if let color = run.properties.color {
                    rPrChildren = "<a:solidFill><a:srgbClr val=\"\(color)\"/></a:solidFill>"
                }
                if let font = run.properties.fontName {
                    rPrChildren += "<a:latin typeface=\"\(escapeXML(font))\"/>"
                }

                let rPrXML = rPrAttrs.isEmpty && rPrChildren.isEmpty
                    ? "<a:rPr lang=\"en-US\" dirty=\"0\"/>"
                    : "<a:rPr\(rPrAttrs)>\(rPrChildren)</a:rPr>"

                runsXML += "<a:r>\(rPrXML)<a:t>\(escapeXML(run.text))</a:t></a:r>"
            }

            if runsXML.isEmpty {
                runsXML = "<a:endParaRPr lang=\"en-US\"/>"
            }

            paragraphsXML += "<a:p>\(pPrXML)\(runsXML)</a:p>"
        }

        if paragraphsXML.isEmpty {
            paragraphsXML = "<a:p><a:endParaRPr lang=\"en-US\"/></a:p>"
        }

        return "<\(wrappingElement)><a:bodyPr/><a:lstStyle/>\(paragraphsXML)</\(wrappingElement)>"
    }

    // MARK: - Media

    /// Writes each planned part under its safe part name (never the raw
    /// `MediaFile.fileName`, which could name a path outside `ppt/media/`).
    private static func writeMedia(_ media: MediaPartPlan, to dir: URL) throws {
        guard !media.parts.isEmpty else { return }
        let mediaDir = dir.appendingPathComponent("ppt/media")
        try FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true)

        for part in media.parts {
            try part.data.write(to: mediaDir.appendingPathComponent(part.name))
        }
    }

    // MARK: - Document Properties

    private static func writeDocProps(_ props: PresentationProperties, to dir: URL) throws {
        let docPropsDir = dir.appendingPathComponent("docProps")
        try FileManager.default.createDirectory(at: docPropsDir, withIntermediateDirectories: true)

        let coreXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties"
                           xmlns:dc="http://purl.org/dc/elements/1.1/"
                           xmlns:dcterms="http://purl.org/dc/terms/"
                           xmlns:dcmitype="http://purl.org/dc/dcmitype/"
                           xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
          <dc:title>\(escapeXML(props.title ?? ""))</dc:title>
          <dc:creator>\(escapeXML(props.creator ?? ""))</dc:creator>
          <dc:subject>\(escapeXML(props.subject ?? ""))</dc:subject>
          <dc:description>\(escapeXML(props.description ?? ""))</dc:description>
        </cp:coreProperties>
        """
        try coreXML.write(to: docPropsDir.appendingPathComponent("core.xml"), atomically: true, encoding: .utf8)

        let appXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">
          <Application>PPTXSwift</Application>
        </Properties>
        """
        try appXML.write(to: docPropsDir.appendingPathComponent("app.xml"), atomically: true, encoding: .utf8)
    }

    // MARK: - Helpers

    private static func escapeXML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

// MARK: - Slide image relationships

/// The image relationships of one slide part, allocated as pictures are
/// serialized: one relationship per distinct media part, `rId2` upward
/// (`rId1` is the slide layout). The Id a picture carried in its source
/// package (`Picture.imageRelationshipId`) is not reused — it belonged to a
/// relationship part this writer does not reproduce.
struct SlideImageRelationships {
    let media: MediaPartPlan
    private(set) var entries: [(id: String, partName: String)] = []
    /// External-link image relationships (`r:link`, `TargetMode="External"`):
    /// one per distinct link target, sharing the same Id namespace as
    /// `entries` so an `r:embed` and an `r:link` on the same slide never
    /// collide.
    private(set) var linkEntries: [(id: String, target: String)] = []
    private var idByPartName: [String: String] = [:]
    private var idByExternalTarget: [String: String] = [:]
    /// Next Id to allocate, `rId2` upward (`rId1` is the slide layout).
    private var nextRelId = 2

    init(media: MediaPartPlan) {
        self.media = media
    }

    /// The relationship Id for the picture's media part, or nil when the
    /// picture names no media.
    ///
    /// - Throws: `PPTXError.writeError` when the picture names a media file
    ///   that `Presentation.images` does not contain — writing it would leave
    ///   an `r:embed` pointing at nothing.
    mutating func embedId(for picture: Picture) throws -> String? {
        guard let fileName = picture.mediaFileName else { return nil }
        guard let partName = media.partName(forMediaFileName: fileName) else {
            throw PPTXError.writeError(
                "圖片 id=\(picture.id)（\(picture.name)）的 media '\(fileName)' 不在 Presentation.images 中，無法寫出 image relationship"
            )
        }
        if let id = idByPartName[partName] { return id }
        let id = "rId\(nextRelId)"
        nextRelId += 1
        idByPartName[partName] = id
        entries.append((id, partName))
        return id
    }

    /// The relationship Id for an external image link target (`r:link`), one
    /// per distinct target — pictures linking the same URL share a
    /// relationship, matching how `embedId(for:)` shares one per media part.
    mutating func linkId(for target: String) -> String {
        if let id = idByExternalTarget[target] { return id }
        let id = "rId\(nextRelId)"
        nextRelId += 1
        idByExternalTarget[target] = id
        linkEntries.append((id, target))
        return id
    }
}
