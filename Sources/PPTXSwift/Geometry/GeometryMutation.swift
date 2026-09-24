import Foundation

// MARK: - Validated cm → EMU geometry

public extension PPTXMetric {
    /// Validates a centimeter rectangle and converts it to an EMU offset / extent.
    ///
    /// - Throws: `PPTXError.invalidParameter` when any value is non-finite or
    ///   outside `coordinateRangeEmu`, or when width / height is not strictly
    ///   positive (also after rounding to whole EMU). Never traps.
    static func geometry(
        xCm: Double, yCm: Double, widthCm: Double, heightCm: Double
    ) throws -> (position: Position, size: Size) {
        let position = try Position(xCm: xCm, yCm: yCm)
        let size = try Size(widthCm: widthCm, heightCm: heightCm)
        guard widthCm > 0 else {
            throw PPTXError.invalidParameter("widthCm", "必須大於 0（收到 \(widthCm)）")
        }
        guard heightCm > 0 else {
            throw PPTXError.invalidParameter("heightCm", "必須大於 0（收到 \(heightCm)）")
        }
        guard size.width > 0, size.height > 0 else {
            throw PPTXError.invalidParameter("widthCm/heightCm", "換算後小於 1 EMU（收到 \(widthCm) × \(heightCm) cm）")
        }
        return (position, size)
    }
}

// MARK: - Element geometry mutation

/// A slide element whose DrawingML transform (`a:off` / `a:ext`) is stored as
/// `Position` / `Size` in EMU.
public protocol MetricGeometryMutable {
    var position: Position { get set }
    var size: Size { get set }
}

public extension MetricGeometryMutable {
    /// Sets the element's offset and extent from centimeters.
    ///
    /// - Throws: `PPTXError.invalidParameter` for non-finite, out-of-range or
    ///   non-positive values; the element is left unchanged on throw.
    mutating func setGeometry(xCm: Double, yCm: Double, widthCm: Double, heightCm: Double) throws {
        let (position, size) = try PPTXMetric.geometry(
            xCm: xCm, yCm: yCm, widthCm: widthCm, heightCm: heightCm
        )
        self.position = position
        self.size = size
    }
}

extension Shape: MetricGeometryMutable {}
extension Picture: MetricGeometryMutable {}
extension GraphicFrame: MetricGeometryMutable {}

// MARK: - Slide-level addressing with group rejection

/// Where an element id lives in a slide's shape tree.
public enum SlideElementLocation: Equatable {
    /// A direct child of the slide's shape tree, at `index` in `Slide.elements`.
    case topLevel(index: Int)
    /// Nested (at any depth) inside the top-level group `groupId`.
    case groupChild(groupId: Int)
    case notFound
}

public extension Slide {
    /// Locates an element by id. Top-level elements take precedence over
    /// group members that happen to share the id.
    func locateElement(id: Int) -> SlideElementLocation {
        if let index = elements.firstIndex(where: { $0.elementId == id }) {
            return .topLevel(index: index)
        }
        for element in elements {
            if case .group(let group) = element, group.containsElement(id: id) {
                return .groupChild(groupId: group.id)
            }
        }
        return .notFound
    }

    /// Sets the geometry of the top-level shape, picture or graphic frame with
    /// the given id, in centimeters.
    ///
    /// - Throws: `PPTXError.groupGeometryUnsupported` when the id is a group or
    ///   lives inside one (parent transforms compound; out of scope);
    ///   `PPTXError.invalidParameter` when the id is absent or the geometry is
    ///   invalid. The slide is left unchanged on throw.
    mutating func setGeometry(
        ofElementId id: Int, xCm: Double, yCm: Double, widthCm: Double, heightCm: Double
    ) throws {
        switch locateElement(id: id) {
        case .notFound:
            throw PPTXError.invalidParameter("shape_id", "找不到形狀 id=\(id)")
        case .groupChild:
            throw PPTXError.groupGeometryUnsupported(shapeId: id)
        case .topLevel(let index):
            switch elements[index] {
            case .shape(var shape):
                try shape.setGeometry(xCm: xCm, yCm: yCm, widthCm: widthCm, heightCm: heightCm)
                elements[index] = .shape(shape)
            case .picture(var picture):
                try picture.setGeometry(xCm: xCm, yCm: yCm, widthCm: widthCm, heightCm: heightCm)
                elements[index] = .picture(picture)
            case .graphicFrame(var frame):
                try frame.setGeometry(xCm: xCm, yCm: yCm, widthCm: widthCm, heightCm: heightCm)
                elements[index] = .graphicFrame(frame)
            case .group:
                throw PPTXError.groupGeometryUnsupported(shapeId: id)
            }
        }
    }
}

extension SlideElement {
    /// The `cNvPr/@id` of the element.
    var elementId: Int {
        switch self {
        case .shape(let s): return s.id
        case .picture(let p): return p.id
        case .graphicFrame(let f): return f.id
        case .group(let g): return g.id
        }
    }
}

extension GroupShape {
    /// Whether `id` names a member of this group at any nesting depth.
    func containsElement(id: Int) -> Bool {
        elements.contains { element in
            if element.elementId == id { return true }
            if case .group(let inner) = element { return inner.containsElement(id: id) }
            return false
        }
    }
}
