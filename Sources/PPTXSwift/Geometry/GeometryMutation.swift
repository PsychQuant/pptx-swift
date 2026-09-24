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
extension Connector: MetricGeometryMutable {}

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
        // Not `allElementIds` here: that recurses into a `.group`'s
        // descendants, which would make an id nested inside a group match at
        // `.topLevel` (the group's own array index) instead of
        // `.groupChild` — the two cases exist precisely to keep that
        // distinction. A top-level `.raw` element is the one real exception:
        // it can carry more than one id of its own (no nesting involved), so
        // it needs all of them checked, not just `elementId`'s first
        // (PsychQuant/pptx-swift#9 — Codex round 1 review caught that using
        // `elementId` here would report a top-level raw element's *second*
        // id as simply not found).
        if let index = elements.firstIndex(where: { element in
            if case .raw(let raw) = element { return raw.elementIds.contains(id) }
            return element.elementId == id
        }) {
            return .topLevel(index: index)
        }
        for element in elements {
            if case .group(let group) = element, group.containsElement(id: id) {
                return .groupChild(groupId: group.id)
            }
        }
        return .notFound
    }

    /// Sets the geometry of the top-level shape, picture, connector or graphic
    /// frame with the given id, in centimeters.
    ///
    /// - Throws: `PPTXError.groupGeometryUnsupported` when the id is a group or
    ///   lives inside one (parent transforms compound; out of scope);
    ///   `PPTXError.rawElementGeometryUnsupported` when the id names (or lives
    ///   inside) a `.raw` element — an unmodeled kind such as
    ///   `mc:AlternateContent` has no typed geometry to set
    ///   (PsychQuant/pptx-swift#9); `PPTXError.invalidParameter` when the id is
    ///   absent or the geometry is invalid. The slide is left unchanged on throw.
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
            case .connector(var connector):
                try connector.setGeometry(xCm: xCm, yCm: yCm, widthCm: widthCm, heightCm: heightCm)
                elements[index] = .connector(connector)
            case .group:
                throw PPTXError.groupGeometryUnsupported(shapeId: id)
            case .raw:
                throw PPTXError.rawElementGeometryUnsupported(shapeId: id)
            }
        }
    }
}

extension SlideElement {
    /// The `cNvPr/@id` of the element — for `.raw`, its *first* id if it
    /// carries more than one (an `mc:AlternateContent` may bundle several).
    /// Use `allElementIds` instead when the goal is avoiding an id collision;
    /// this single-id form only serves the existing top-level id lookup
    /// (`Slide.locateElement`), which addresses one element by one id.
    var elementId: Int {
        switch self {
        case .shape(let s): return s.id
        case .picture(let p): return p.id
        case .graphicFrame(let f): return f.id
        case .group(let g): return g.id
        case .connector(let c): return c.id
        case .raw(let r): return r.elementIds.first ?? 0
        }
    }

    /// Every `cNvPr/@id` this element declares, at any nesting depth for a
    /// `.group` — the id-collision-safe set a new element's id must avoid
    /// (PsychQuant/pptx-swift#9, #6's lesson: an id allocator that only sees
    /// typed elements can hand out an id already used inside content it does
    /// not model, such as an `mc:AlternateContent` branch). Usually one
    /// element, one id; `.group` includes its own id plus every descendant's;
    /// `.raw` includes every id found anywhere in its original subtree.
    public var allElementIds: [Int] {
        switch self {
        case .shape(let s): return [s.id]
        case .picture(let p): return [p.id]
        case .graphicFrame(let f): return [f.id]
        case .connector(let c): return [c.id]
        case .group(let g): return [g.id] + g.elements.flatMap(\.allElementIds)
        case .raw(let r): return r.elementIds
        }
    }
}

public extension Slide {
    /// Every `cNvPr/@id` anywhere on the slide, at any nesting depth,
    /// including inside `.raw` (unmodeled) elements — see
    /// `SlideElement.allElementIds`. A consumer allocating a new element's id
    /// (such as `che-pptx-mcp`'s insert tools) should avoid every id in this
    /// set, not just the ids of the element kinds it itself models.
    var allElementIds: [Int] {
        elements.flatMap(\.allElementIds)
    }
}

extension GroupShape {
    /// Whether `id` names a member of this group at any nesting depth.
    func containsElement(id: Int) -> Bool {
        elements.contains { $0.allElementIds.contains(id) }
    }
}
