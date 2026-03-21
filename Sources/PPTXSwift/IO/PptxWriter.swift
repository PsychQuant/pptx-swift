import Foundation
import ZIPFoundation
import OOXMLSwift

/// PPTX 檔案寫入器
public struct PptxWriter {

    /// 將 Presentation 寫入 .pptx 檔案
    public static func write(_ presentation: Presentation, to url: URL) throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("che-pptx-mcp-write")
            .appendingPathComponent(UUID().uuidString)

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // 1. 寫入 [Content_Types].xml
        try writeContentTypes(presentation, to: tempDir)

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
            try writeSlide(slide, index: index, to: tempDir)
        }

        // 8. 寫入 media
        try writeMedia(presentation.images, to: tempDir)

        // 9. 寫入 docProps
        try writeDocProps(presentation.properties, to: tempDir)

        // 10. 壓縮為 .pptx
        try ZipHelper.zip(tempDir, to: url)
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

    private static func writeContentTypes(_ presentation: Presentation, to dir: URL) throws {
        var xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Default Extension="png" ContentType="image/png"/>
          <Default Extension="jpeg" ContentType="image/jpeg"/>
          <Default Extension="jpg" ContentType="image/jpeg"/>
          <Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>
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

    private static func writeSlide(_ slide: Slide, index: Int, to dir: URL) throws {
        let slidesDir = dir.appendingPathComponent("ppt/slides")
        try FileManager.default.createDirectory(at: slidesDir, withIntermediateDirectories: true)

        let slideRelsDir = dir.appendingPathComponent("ppt/slides/_rels")
        try FileManager.default.createDirectory(at: slideRelsDir, withIntermediateDirectories: true)

        // Shape tree XML
        var shapeXML = ""
        var nextId = 2
        for element in slide.elements {
            shapeXML += serializeElement(element, nextId: &nextId)
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

        // Slide relationships
        let slideRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>
        </Relationships>
        """
        try slideRels.write(to: slideRelsDir.appendingPathComponent("slide\(index + 1).xml.rels"), atomically: true, encoding: .utf8)
    }

    // MARK: - Element Serialization

    private static func serializeElement(_ element: SlideElement, nextId: inout Int) -> String {
        switch element {
        case .shape(let shape):
            return serializeShape(shape, nextId: &nextId)
        case .picture(let picture):
            return serializePicture(picture, nextId: &nextId)
        case .graphicFrame(let frame):
            return serializeGraphicFrame(frame, nextId: &nextId)
        case .group:
            return ""  // 群組序列化暫不實作
        }
    }

    private static func serializeShape(_ shape: Shape, nextId: inout Int) -> String {
        let id = shape.id > 0 ? shape.id : nextId
        nextId = max(nextId, id + 1)

        var phXML = ""
        if let ph = shape.placeholder {
            phXML = "<p:ph type=\"\(ph.rawValue)\"/>"
        }

        var fillXML = ""
        if let fill = shape.fill {
            switch fill {
            case .solid(let color):
                fillXML = "<a:solidFill><a:srgbClr val=\"\(color)\"/></a:solidFill>"
            case .schemeColor(let name):
                fillXML = "<a:solidFill><a:schemeClr val=\"\(name)\"/></a:solidFill>"
            case .noFill:
                fillXML = "<a:noFill/>"
            case .gradient:
                break
            }
        }

        var textBodyXML = ""
        if let textBody = shape.textBody {
            textBodyXML = serializeTextBody(textBody)
        }

        return """
              <p:sp>
                <p:nvSpPr>
                  <p:cNvPr id="\(id)" name="\(escapeXML(shape.name))"/>
                  <p:cNvSpPr/>
                  <p:nvPr>\(phXML)</p:nvPr>
                </p:nvSpPr>
                <p:spPr>
                  <a:xfrm>
                    <a:off x="\(shape.position.x)" y="\(shape.position.y)"/>
                    <a:ext cx="\(shape.size.width)" cy="\(shape.size.height)"/>
                  </a:xfrm>
                  <a:prstGeom prst="\(shape.geometry.rawValue)"><a:avLst/></a:prstGeom>
                  \(fillXML)
                </p:spPr>
                \(textBodyXML)
              </p:sp>

        """
    }

    private static func serializePicture(_ picture: Picture, nextId: inout Int) -> String {
        let id = picture.id > 0 ? picture.id : nextId
        nextId = max(nextId, id + 1)

        return """
              <p:pic>
                <p:nvPicPr>
                  <p:cNvPr id="\(id)" name="\(escapeXML(picture.name))"/>
                  <p:cNvPicPr/>
                  <p:nvPr/>
                </p:nvPicPr>
                <p:blipFill>
                  <a:blip r:embed="\(picture.imageRelationshipId)"/>
                  <a:stretch><a:fillRect/></a:stretch>
                </p:blipFill>
                <p:spPr>
                  <a:xfrm>
                    <a:off x="\(picture.position.x)" y="\(picture.position.y)"/>
                    <a:ext cx="\(picture.size.width)" cy="\(picture.size.height)"/>
                  </a:xfrm>
                  <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
                </p:spPr>
              </p:pic>

        """
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
                rowsXML += "              \(serializeTextBody(cell.textBody))\n"
                rowsXML += "              <a:tcPr/>\n"
                rowsXML += "            </a:tc>\n"
            }
            rowsXML += "          </a:tr>\n"
        }

        return """
              <p:graphicFrame>
                <p:nvGraphicFramePr>
                  <p:cNvPr id="\(id)" name="\(escapeXML(frame.name))"/>
                  <p:cNvGraphicFramePr><a:graphicFrameLocks noGrp="1"/></p:cNvGraphicFramePr>
                  <p:nvPr/>
                </p:nvGraphicFramePr>
                <p:xfrm>
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

    private static func serializeTextBody(_ textBody: TextBody) -> String {
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

        return "<p:txBody><a:bodyPr/><a:lstStyle/>\(paragraphsXML)</p:txBody>"
    }

    // MARK: - Media

    private static func writeMedia(_ images: [MediaFile], to dir: URL) throws {
        guard !images.isEmpty else { return }
        let mediaDir = dir.appendingPathComponent("ppt/media")
        try FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true)

        for image in images {
            try image.data.write(to: mediaDir.appendingPathComponent(image.fileName))
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
