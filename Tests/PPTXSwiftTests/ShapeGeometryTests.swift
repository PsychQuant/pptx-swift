import Testing
import Foundation
@testable import PPTXSwift

/// §1.4 — shape geometry mutation in centimeters.
///
/// Covers spec `pptx-metric-geometry` Requirement "Shape geometry mutation in
/// centimeters": Scenario "Setting shape geometry", Scenario "Group-child
/// rejection", and `##### Example: Aspect-fit derivation`.
struct ShapeGeometryTests {

    // MARK: - Scenario: Setting shape geometry

    @Test func `Setting geometry in cm writes the EMU offset and extent`() throws {
        var shape = Shape(id: 2, name: "Title 1", placeholder: .title)
        try shape.setGeometry(xCm: 2.0, yCm: 3.0, widthCm: 10.0, heightCm: 7.5)
        #expect(shape.position.x == 720000)
        #expect(shape.position.y == 1080000)
        #expect(shape.size.width == 3600000)
        #expect(shape.size.height == 2700000)
    }

    @Test func `Slide-level geometry set mutates the stored top-level shape`() throws {
        var slide = Slide(elements: [
            .shape(Shape(id: 2, name: "Title 1")),
            .shape(Shape(id: 3, name: "Body 2")),
        ])
        try slide.setGeometry(ofElementId: 3, xCm: 2.0, yCm: 3.0, widthCm: 10.0, heightCm: 7.5)

        let stored = try #require(slide.shapes.first { $0.id == 3 })
        #expect(stored.position.x == 720000)
        #expect(stored.position.y == 1080000)
        #expect(stored.size.width == 3600000)
        #expect(stored.size.height == 2700000)
        let untouched = try #require(slide.shapes.first { $0.id == 2 })
        #expect(untouched.position.x == 0 && untouched.size.width == 0)
    }

    @Test func `Slide-level geometry set also applies to pictures and graphic frames`() throws {
        var slide = Slide(elements: [
            .picture(Picture(id: 4, name: "Picture 3")),
            .graphicFrame(GraphicFrame(id: 5, name: "Table 4")),
        ])
        try slide.setGeometry(ofElementId: 4, xCm: 1.0, yCm: 1.0, widthCm: 2.54, heightCm: 2.54)
        try slide.setGeometry(ofElementId: 5, xCm: 2.0, yCm: 3.0, widthCm: 10.0, heightCm: 7.5)

        let picture = try #require(slide.pictures.first)
        #expect(picture.position.x == 360000 && picture.position.y == 360000)
        #expect(picture.size.width == 914400 && picture.size.height == 914400)
        let frame = try #require(slide.elements.compactMap { el -> GraphicFrame? in
            if case .graphicFrame(let f) = el { return f } else { return nil }
        }.first)
        #expect(frame.position.x == 720000 && frame.position.y == 1080000)
        #expect(frame.size.width == 3600000 && frame.size.height == 2700000)
    }

    // MARK: - Scenario: Group-child rejection

    static let groupedSlide = Slide(elements: [
        .shape(Shape(id: 2, name: "Top-level")),
        .group(GroupShape(id: 10, name: "Group 9", elements: [
            .shape(Shape(id: 11, name: "Child shape")),
            .group(GroupShape(id: 12, name: "Inner group", elements: [
                .picture(Picture(id: 13, name: "Grandchild picture")),
            ])),
        ])),
    ])

    @Test(arguments: [11, 13])
    func `Setting geometry on a group child throws a typed error`(childId: Int) {
        var slide = Self.groupedSlide
        let error = #expect(throws: PPTXError.self) {
            try slide.setGeometry(ofElementId: childId, xCm: 2.0, yCm: 3.0, widthCm: 10.0, heightCm: 7.5)
        }
        guard case .groupGeometryUnsupported(let shapeId) = error else {
            Issue.record("expected .groupGeometryUnsupported, got \(String(describing: error))")
            return
        }
        #expect(shapeId == childId)
        #expect(error?.errorDescription?.contains("群組") == true)
    }

    @Test func `Setting geometry on a group container throws a typed error`() {
        var slide = Self.groupedSlide
        let error = #expect(throws: PPTXError.self) {
            try slide.setGeometry(ofElementId: 10, xCm: 2.0, yCm: 3.0, widthCm: 10.0, heightCm: 7.5)
        }
        guard case .groupGeometryUnsupported(let shapeId) = error else {
            Issue.record("expected .groupGeometryUnsupported, got \(String(describing: error))")
            return
        }
        #expect(shapeId == 10)
    }

    @Test func `Element location distinguishes top level, group members and absence`() {
        let slide = Self.groupedSlide
        #expect(slide.locateElement(id: 2) == .topLevel(index: 0))
        #expect(slide.locateElement(id: 10) == .topLevel(index: 1))
        #expect(slide.locateElement(id: 11) == .groupChild(groupId: 10))
        #expect(slide.locateElement(id: 13) == .groupChild(groupId: 10))
        #expect(slide.locateElement(id: 99) == .notFound)
    }

    @Test func `Unknown element id is an error`() {
        var slide = Self.groupedSlide
        #expect(throws: PPTXError.self) {
            try slide.setGeometry(ofElementId: 99, xCm: 2.0, yCm: 3.0, widthCm: 10.0, heightCm: 7.5)
        }
    }

    // MARK: - Invalid input leaves the element untouched

    static let invalidInputs: [(label: String, x: Double, y: Double, w: Double, h: Double)] = [
        ("zero width", 2.0, 3.0, 0.0, 7.5),
        ("negative height", 2.0, 3.0, 10.0, -1.0),
        ("NaN x", .nan, 3.0, 10.0, 7.5),
        ("infinite y", 2.0, .infinity, 10.0, 7.5),
        ("beyond OOXML coordinate range", 1e12, 3.0, 10.0, 7.5),
    ]

    @Test(arguments: invalidInputs)
    func `Invalid geometry throws without mutating`(
        input: (label: String, x: Double, y: Double, w: Double, h: Double)
    ) {
        let original = Shape(id: 2, position: Position(x: 1, y: 2), size: Size(width: 3, height: 4))
        var shape = original
        #expect(throws: PPTXError.self, "\(input.label)") {
            try shape.setGeometry(xCm: input.x, yCm: input.y, widthCm: input.w, heightCm: input.h)
        }
        #expect(shape.position.x == 1 && shape.position.y == 2)
        #expect(shape.size.width == 3 && shape.size.height == 4)
    }

    // MARK: - Example: Aspect-fit derivation

    @Test func `A 4 to 3 picture placed 10 cm wide derives a 7_5 cm height`() throws {
        let png = try GeneratedImage.png(width: 1600, height: 1200)
        let pixels = try NativeAspect.pixelDimensions(of: png)

        let fitted = try NativeAspect.fittedSize(
            keeping: .width, of: Size(widthCm: 10.0, heightCm: 0),
            pixelWidth: pixels.width, pixelHeight: pixels.height
        )
        #expect(fitted.width == 3600000)
        #expect(fitted.height == 2700000)
        #expect(abs(fitted.heightCm - 7.5) < 1e-9)

        var picture = Picture(id: 4, name: "Picture 3")
        try picture.setGeometry(xCm: 2.0, yCm: 3.0, widthCm: fitted.widthCm, heightCm: fitted.heightCm)
        #expect(picture.size.width == 3600000)
        #expect(picture.size.height == 2700000)
    }

    @Test func `Fitting a distorted extent re-derives the non-anchored dimension`() throws {
        let distorted = Size(width: 3600000, height: 1800000)

        let byWidth = try NativeAspect.fittedSize(keeping: .width, of: distorted, pixelWidth: 1600, pixelHeight: 1200)
        #expect(byWidth.width == 3600000)
        #expect(byWidth.height == 2700000)

        let byHeight = try NativeAspect.fittedSize(keeping: .height, of: distorted, pixelWidth: 1600, pixelHeight: 1200)
        #expect(byHeight.width == 2400000)
        #expect(byHeight.height == 1800000)
    }

    @Test func `Fitting with non-positive pixel dimensions is an error`() {
        #expect(throws: PPTXError.self) {
            _ = try NativeAspect.fittedSize(keeping: .width, of: Size(width: 100, height: 100), pixelWidth: 0, pixelHeight: 10)
        }
    }
}
