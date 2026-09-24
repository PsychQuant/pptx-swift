import Testing
import Foundation
import OOXMLSwift
@testable import PPTXSwift

/// PsychQuant/pptx-swift#5: `PptxWriter` must serialize `GroupShape` — nested
/// groups, the group transform (`a:off`／`a:ext`／`a:chOff`／`a:chExt`), and
/// pictures inside a group (sharing the same slide-level image relationships
/// as top-level pictures) — so a presentation with groups round-trips without
/// losing the grouped content.
struct GroupShapeWriteTests {

    // MARK: - Flattening helper

    /// One element from a slide's shape tree, depth-first, with nested groups
    /// expanded in place — lets a test assert the whole tree (including
    /// content nested inside groups) without hand-walking it every time.
    /// `Slide.pictures` / `.shapes` only look at the top level, which is
    /// exactly the blind spot that let #5 go undetected: a picture nested
    /// inside a group was invisible to those properties both before and
    /// after a round trip, so a count-based assertion on them could not
    /// catch it disappearing.
    struct FlatElement: Equatable {
        enum Kind: Equatable { case shape, picture, graphicFrame, group }
        let kind: Kind
        let id: Int
        let name: String
        let depth: Int
    }

    static func flatten(_ elements: [SlideElement], depth: Int = 0) -> [FlatElement] {
        elements.flatMap { element -> [FlatElement] in
            switch element {
            case .shape(let s):
                return [FlatElement(kind: .shape, id: s.id, name: s.name, depth: depth)]
            case .picture(let p):
                return [FlatElement(kind: .picture, id: p.id, name: p.name, depth: depth)]
            case .graphicFrame(let f):
                return [FlatElement(kind: .graphicFrame, id: f.id, name: f.name, depth: depth)]
            case .group(let g):
                return [FlatElement(kind: .group, id: g.id, name: g.name, depth: depth)]
                    + flatten(g.elements, depth: depth + 1)
            }
        }
    }

    /// Every picture anywhere in the tree (top level or nested inside any
    /// number of groups), depth-first.
    static func allPictures(_ elements: [SlideElement]) -> [Picture] {
        elements.flatMap { element -> [Picture] in
            switch element {
            case .picture(let p): return [p]
            case .group(let g): return allPictures(g.elements)
            default: return []
            }
        }
    }

    // MARK: - Scenario: a flat group with a shape and a picture

    @Test func `A group with a shape and a picture round-trips its transform and children`() throws {
        let png = try GeneratedImage.png(width: 16, height: 12)
        var pres = PptxWriter.createNew()
        pres.images = [MediaFile(id: "photo.png", fileName: "photo.png", data: png)]
        pres.slides[0].elements = [
            .group(GroupShape(
                id: 10, name: "Group 1",
                position: Position(x: 914400, y: 914400),
                size: Size(width: 1828800, height: 914400),
                childOffset: Position(x: 0, y: 0),
                childExtent: Size(width: 3657600, height: 1828800),
                elements: [
                    .shape(Shape(id: 11, name: "Child shape", position: Position(x: 0, y: 0), size: Size(width: 100, height: 100))),
                    .picture(Picture(id: 12, name: "Child picture",
                                      position: Position(x: 1000, y: 1000), size: Size(width: 200, height: 200),
                                      mediaFileName: "photo.png")),
                ]
            ))
        ]

        try TemporaryPPTX.written(pres) { url in
            let package = try PackageInspector(url)
            defer { package.cleanup() }
            #expect(try package.integrityViolations() == [])

            // The group's own transform, written verbatim.
            let groupXML = try package.xml("ppt/slides/slide1.xml")
            let xfrm = try #require(try groupXML.nodes(forXPath: "//*[local-name()='grpSp']/*[local-name()='grpSpPr']/*[local-name()='xfrm']").first as? XMLElement)
            let off = try #require(try xfrm.nodes(forXPath: "*[local-name()='off']").first as? XMLElement)
            #expect(off.attribute(forName: "x")?.stringValue == "914400")
            #expect(off.attribute(forName: "y")?.stringValue == "914400")
            let ext = try #require(try xfrm.nodes(forXPath: "*[local-name()='ext']").first as? XMLElement)
            #expect(ext.attribute(forName: "cx")?.stringValue == "1828800")
            #expect(ext.attribute(forName: "cy")?.stringValue == "914400")
            let chOff = try #require(try xfrm.nodes(forXPath: "*[local-name()='chOff']").first as? XMLElement)
            #expect(chOff.attribute(forName: "x")?.stringValue == "0")
            let chExt = try #require(try xfrm.nodes(forXPath: "*[local-name()='chExt']").first as? XMLElement)
            #expect(chExt.attribute(forName: "cx")?.stringValue == "3657600")
            #expect(chExt.attribute(forName: "cy")?.stringValue == "1828800")

            // The picture inside the group still resolves its media, exactly
            // as a top-level picture would (#1's guarantee now extends into groups).
            let embed = try #require(try package.blipEmbeds(in: "ppt/slides/slide1.xml").first ?? nil)
            let rel = try #require(try package.relationships(of: "ppt/slides/slide1.xml").first { $0.id == embed })
            #expect(rel.type == PackageInspector.imageRelType)
            #expect(package.resolve(rel, from: "ppt/slides/slide1.xml") == "ppt/media/photo.png")

            let reread = try PptxReader.read(from: url)
            let group = try #require(reread.slides[0].elements.first.flatMap { element -> GroupShape? in
                if case .group(let g) = element { return g }
                return nil
            })
            #expect(group.id == 10)
            #expect(group.name == "Group 1")
            #expect(group.position.x == 914400 && group.position.y == 914400)
            #expect(group.size.width == 1828800 && group.size.height == 914400)
            #expect(group.childOffset.x == 0 && group.childOffset.y == 0)
            #expect(group.childExtent.width == 3657600 && group.childExtent.height == 1828800)
            #expect(group.elements.count == 2)
            #expect(reread.mediaFile(for: try #require(Self.allPictures(reread.slides[0].elements).first))?.data == png)
        }
    }

    // MARK: - Scenario: nested groups

    @Test func `A two-level nested group preserves structure at every depth`() throws {
        var pres = PptxWriter.createNew()
        pres.slides[0].elements = [
            .shape(Shape(id: 2, name: "Top-level")),
            .group(GroupShape(id: 10, name: "Outer", elements: [
                .shape(Shape(id: 11, name: "Middle shape")),
                .group(GroupShape(id: 12, name: "Inner", elements: [
                    .shape(Shape(id: 13, name: "Deep shape")),
                    .shape(Shape(id: 14, name: "Deep shape 2")),
                ])),
            ])),
        ]

        try TemporaryPPTX.written(pres) { url in
            let package = try PackageInspector(url)
            defer { package.cleanup() }
            #expect(try package.integrityViolations() == [])

            // Two <p:grpSp> elements, nested one inside the other.
            let depths = try package.groupShapeDepths(in: "ppt/slides/slide1.xml").sorted()
            #expect(depths == [0, 1])

            let reread = try PptxReader.read(from: url)
            let before = Self.flatten(pres.slides[0].elements)
            let after = Self.flatten(reread.slides[0].elements)
            #expect(before == after)
            #expect(after.map(\.id) == [2, 10, 11, 12, 13, 14])
            #expect(after.map(\.depth) == [0, 0, 1, 1, 2, 2])
        }
    }

    // MARK: - Scenario: id allocation inside groups

    @Test func `Auto-assigned ids do not collide between a group and its children`() throws {
        var pres = PptxWriter.createNew()
        // Every id left at its type's default (0) — the writer must still
        // hand out distinct ids to the group, its children, and any sibling
        // that follows the group at the top level.
        pres.slides[0].elements = [
            .group(GroupShape(elements: [
                .shape(Shape()),
                .shape(Shape()),
            ])),
            .shape(Shape(name: "After the group")),
        ]

        try TemporaryPPTX.written(pres) { url in
            let package = try PackageInspector(url)
            defer { package.cleanup() }
            #expect(try package.integrityViolations() == [])

            let reread = try PptxReader.read(from: url)
            let flat = Self.flatten(reread.slides[0].elements)
            #expect(flat.count == 4, "expected group + 2 children + 1 sibling, got \(flat)")
            let ids = flat.map(\.id)
            #expect(Set(ids).count == ids.count, "ids collided: \(ids)")
            #expect(ids.allSatisfy { $0 > 0 })
        }
    }

    // MARK: - Scenario: a picture inside a group that cannot be linked

    @Test func `A picture inside a group naming missing media fails to save and writes nothing`() throws {
        var pres = PptxWriter.createNew()
        pres.slides[0].elements = [
            .group(GroupShape(id: 10, elements: [
                .picture(Picture(id: 11, name: "Orphan", mediaFileName: "missing.png")),
            ])),
        ]
        let url = TemporaryPPTX.url("group-dangling")
        defer { try? FileManager.default.removeItem(at: url) }

        let error = #expect(throws: PPTXError.self) {
            try PptxWriter.write(pres, to: url)
        }
        guard case .writeError(let message)? = error else {
            Issue.record("expected .writeError, got \(String(describing: error))")
            return
        }
        #expect(message.contains("missing.png"))
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: - Scenario: a real fixture with nested groups (cropped.pptx)

    @Test func `cropped pptx's nested groups and their pictures survive a round trip`() throws {
        // cropped.pptx (Apache POI CroppedBitmap.pptx) slide 1 has 4 ordinary
        // (shape, cropped picture) pairs at the top level, followed by one
        // outer group wrapping two inner groups, each holding one more
        // (shape, cropped picture) pair two levels deep — 6 pictures total,
        // 2 of them reachable only through nested groups. Before #5, the
        // writer silently dropped every group (`case .group: return ""`),
        // so those 2 nested pictures vanished on a round trip; `Slide.pictures`
        // (top level only) could not see that, which is exactly why the bug
        // shipped undetected in #1.
        let source = try #require(RealFileTests.fixturePath("cropped.pptx"))
        let original = try PptxReader.read(from: source)
        let originalPictures = Self.allPictures(original.slides[0].elements)
        try #require(originalPictures.count == 6, "fixture assumption: 6 pictures (4 top-level + 2 nested) in cropped.pptx")

        try TemporaryPPTX.written(original, "cropped-rt") { url in
            let package = try PackageInspector(url)
            defer { package.cleanup() }
            #expect(try package.integrityViolations() == [])

            let reread = try PptxReader.read(from: url)
            let before = Self.flatten(original.slides[0].elements)
            let after = Self.flatten(reread.slides[0].elements)
            #expect(before.map(\.kind) == after.map(\.kind))
            #expect(before.map(\.depth) == after.map(\.depth))
            #expect(before.map(\.id) == after.map(\.id))

            let rereadPictures = Self.allPictures(reread.slides[0].elements)
            try #require(rereadPictures.count == originalPictures.count)
            for (before, after) in zip(originalPictures, rereadPictures) {
                let beforeMedia = original.mediaFile(for: before)
                let afterMedia = reread.mediaFile(for: after)
                #expect(afterMedia?.data == beforeMedia?.data, "nested picture id=\(before.id) lost its media")
                #expect(after.sourceRect == before.sourceRect, "nested picture id=\(before.id) lost its crop")
            }
        }
    }
}
