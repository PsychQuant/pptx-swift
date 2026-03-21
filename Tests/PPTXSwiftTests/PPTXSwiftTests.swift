import Testing
import Foundation
@testable import PPTXSwift

// MARK: - 8.1 PptxReader Tests

@Test func presentationCreation() {
    let presentation = PptxWriter.createNew()
    #expect(presentation.slideCount == 1)
    #expect(presentation.theme != nil)
}

@Test func slideSize() {
    var pres = Presentation()
    #expect(pres.slideSize.width == 9144000)
    #expect(pres.slideSize.height == 6858000)
    #expect(pres.slideSize.widthInches == 10.0)
    #expect(pres.slideSize.heightInches == 7.5)
}

@Test func presentationProperties() {
    var props = PresentationProperties()
    props.title = "Test"
    props.creator = "Author"
    #expect(props.title == "Test")
    #expect(props.creator == "Author")
}

// MARK: - 8.2 Shape/Text Model Tests

@Test func shapeGeometry() {
    let pos = Position(x: 914400, y: 1828800)
    #expect(pos.xInches == 1.0)
    #expect(pos.yInches == 2.0)

    let size = Size(width: 914400, height: 914400)
    #expect(size.widthInches == 1.0)
    #expect(size.widthPoints == 72.0)
}

@Test func textBodyExtraction() {
    let body = TextBody(paragraphs: [
        TextParagraph(text: "Hello"),
        TextParagraph(text: "World")
    ])
    #expect(body.getText() == "Hello\nWorld")
}

@Test func textRunProperties() {
    var props = TextRunProperties()
    props.fontSize = 4400
    #expect(props.fontSizePoints == 44.0)

    props.bold = true
    props.italic = false
    #expect(props.bold == true)
    #expect(props.italic == false)
}

@Test func slideTextExtraction() {
    let shape1 = Shape(
        id: 1, name: "Title",
        textBody: TextBody(paragraphs: [TextParagraph(text: "Slide Title")])
    )
    let shape2 = Shape(
        id: 2, name: "Body",
        textBody: TextBody(paragraphs: [TextParagraph(text: "Body text")])
    )
    let slide = Slide(elements: [.shape(shape1), .shape(shape2)])
    #expect(slide.getText() == "Slide Title\nBody text")
}

@Test func placeholderTypes() {
    let title = PlaceholderType(rawValue: "title")
    #expect(title == .title)

    let body = PlaceholderType(rawValue: "body")
    #expect(body == .body)

    let ctrTitle = PlaceholderType(rawValue: "ctrTitle")
    #expect(ctrTitle == .centerTitle)
}

@Test func tableTextExtraction() {
    let table = DrawingTable(
        columns: [TableColumn(width: 100), TableColumn(width: 100)],
        rows: [
            TableRow(height: 50, cells: [TableCell(text: "A1"), TableCell(text: "B1")]),
            TableRow(height: 50, cells: [TableCell(text: "A2"), TableCell(text: "B2")])
        ]
    )
    #expect(table.columnCount == 2)
    #expect(table.rowCount == 2)
    #expect(table.getCellText(row: 0, col: 1) == "B1")
    #expect(table.getText() == "A1\tB1\nA2\tB2")
}

@Test func tableCellUpdate() throws {
    var table = DrawingTable(
        columns: [TableColumn(width: 100)],
        rows: [TableRow(height: 50, cells: [TableCell(text: "old")])]
    )
    try table.updateCell(row: 0, col: 0, text: "new")
    #expect(table.getCellText(row: 0, col: 0) == "new")
}

// MARK: - Theme Tests

@Test func themeColorResolution() {
    var theme = Theme()
    theme.colorScheme.accent1 = "4472C4"
    theme.colorScheme.dk1 = "000000"

    #expect(theme.resolveColor("accent1") == "4472C4")
    #expect(theme.resolveColor("dk1") == "000000")
    #expect(theme.resolveColor("tx1") == "000000")  // tx1 = dk1
    #expect(theme.resolveColor("bg1") == theme.colorScheme.lt1)  // bg1 = lt1
    #expect(theme.resolveColor("unknown") == nil)
}

@Test func colorSchemeAllColors() {
    let scheme = ColorScheme()
    let colors = scheme.allColors
    #expect(colors.count == 12)
}

// MARK: - Slide Operations

@Test func slideManagement() throws {
    var pres = Presentation()
    pres.addSlide(Slide())
    pres.addSlide(Slide())
    #expect(pres.slideCount == 2)

    try pres.deleteSlide(at: 0)
    #expect(pres.slideCount == 1)

    pres.addSlide(Slide())
    pres.addSlide(Slide())
    try pres.reorderSlide(from: 0, to: 2)
    #expect(pres.slideCount == 3)

    let newIdx = try pres.duplicateSlide(at: 1)
    #expect(newIdx == 2)
    #expect(pres.slideCount == 4)
}

// MARK: - 8.3 Round-trip Tests

@Test func roundTripWriteRead() throws {
    // Create a presentation with content
    var pres = PptxWriter.createNew()
    pres.slides[0].elements.append(.shape(Shape(
        id: 2, name: "Title",
        placeholder: .title,
        position: Position(x: 457200, y: 274638),
        size: Size(width: 8229600, height: 1143000),
        textBody: TextBody(paragraphs: [TextParagraph(text: "Test Title")])
    )))
    pres.slides[0].elements.append(.shape(Shape(
        id: 3, name: "Content",
        position: Position(x: 457200, y: 1600200),
        size: Size(width: 8229600, height: 4525963),
        textBody: TextBody(paragraphs: [
            TextParagraph(text: "First paragraph"),
            TextParagraph(text: "Second paragraph")
        ])
    )))
    pres.properties.title = "Round Trip Test"
    pres.properties.creator = "PPTXSwift"

    // Write to temp file
    let tempURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("pptx-test-\(UUID().uuidString).pptx")
    defer { try? FileManager.default.removeItem(at: tempURL) }

    try PptxWriter.write(pres, to: tempURL)

    // Verify file exists and is non-empty
    let fileData = try Data(contentsOf: tempURL)
    #expect(fileData.count > 0)

    // Read back
    let readPres = try PptxReader.read(from: tempURL)
    #expect(readPres.slideCount == 1)
    #expect(readPres.slides[0].getText().contains("Test Title"))
    #expect(readPres.slides[0].getText().contains("First paragraph"))
    #expect(readPres.theme != nil)
}

@Test func roundTripMultiSlide() throws {
    var pres = PptxWriter.createNew()
    pres.addSlide(Slide(elements: [
        .shape(Shape(id: 2, name: "S2", textBody: TextBody(paragraphs: [TextParagraph(text: "Slide 2")])))
    ]))
    pres.addSlide(Slide(elements: [
        .shape(Shape(id: 2, name: "S3", textBody: TextBody(paragraphs: [TextParagraph(text: "Slide 3")])))
    ]))

    let tempURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("pptx-multi-\(UUID().uuidString).pptx")
    defer { try? FileManager.default.removeItem(at: tempURL) }

    try PptxWriter.write(pres, to: tempURL)
    let readPres = try PptxReader.read(from: tempURL)
    #expect(readPres.slideCount == 3)
}

// MARK: - Fill & Outline

@Test func shapeFillTypes() {
    let solidFill: ShapeFill = .solid(color: "FF0000")
    let schemeFill: ShapeFill = .schemeColor(name: "accent1")
    let noFill: ShapeFill = .noFill

    if case .solid(let color) = solidFill {
        #expect(color == "FF0000")
    }
    if case .schemeColor(let name) = schemeFill {
        #expect(name == "accent1")
    }
    if case .noFill = noFill {
        // pass
    }
}

@Test func shapeOutline() {
    let outline = ShapeOutline(color: "000000", width: 12700)
    #expect(outline.widthPoints == 1.0)
}

// MARK: - BulletStyle

@Test func bulletStyles() {
    let charBullet: BulletStyle = .character(char: "•", font: "Arial")
    let numBullet: BulletStyle = .autoNumbered(type: "arabicPeriod", startAt: 1)
    let noBullet: BulletStyle = BulletStyle.none

    if case .character(let char, let font) = charBullet {
        #expect(char == "•")
        #expect(font == "Arial")
    }
    if case .autoNumbered(let type, let startAt) = numBullet {
        #expect(type == "arabicPeriod")
        #expect(startAt == 1)
    }
    if case .none = noBullet {
        // pass
    }
}

// MARK: - MediaFile

@Test func mediaFileContentType() {
    let png = MediaFile(id: "img1", fileName: "image1.png", data: Data())
    #expect(png.contentType == "image/png")

    let jpg = MediaFile(id: "img2", fileName: "photo.jpg", data: Data())
    #expect(jpg.contentType == "image/jpeg")
}
