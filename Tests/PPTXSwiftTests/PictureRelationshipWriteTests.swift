import Testing
import Foundation
import OOXMLSwift
@testable import PPTXSwift

/// PsychQuant/pptx-swift#1: the writer must link every picture it writes to
/// its media part — `slideN.xml.rels` image relationship, the `ppt/media/`
/// part itself, and a content type for it — so the saved package opens in
/// PowerPoint without repair and without missing pictures.
struct PictureRelationshipWriteTests {

    // MARK: - Fixtures

    static func pngData(_ width: Int = 16, _ height: Int = 12) throws -> Data {
        try GeneratedImage.png(width: width, height: height)
    }

    static func presentation(pictures: [[Picture]], images: [MediaFile]) -> Presentation {
        var pres = PptxWriter.createNew()
        pres.slides = pictures.map { Slide(elements: $0.map { .picture($0) }) }
        pres.images = images
        return pres
    }

    static func picture(_ id: Int, media: String?, rId: String = "rId99") -> Picture {
        Picture(id: id, name: "Picture \(id)", position: Position(x: 914400, y: 914400),
                size: Size(width: 1828800, height: 1371600),
                imageRelationshipId: rId, mediaFileName: media)
    }

    // MARK: - Scenario: an in-memory picture is linked after save

    @Test func `A picture inserted in memory resolves r:embed to its media part after save`() throws {
        let png = try Self.pngData()
        let pres = Self.presentation(
            pictures: [[Self.picture(2, media: "photo.png")]],
            images: [MediaFile(id: "photo.png", fileName: "photo.png", data: png)]
        )

        try TemporaryPPTX.written(pres) { url in
            let package = try PackageInspector(url)
            defer { package.cleanup() }
            let violations = try package.integrityViolations()
            #expect(violations == [])

            let embed = try #require(try package.blipEmbeds(in: "ppt/slides/slide1.xml").first ?? nil)
            let rel = try #require(try package.relationships(of: "ppt/slides/slide1.xml").first { $0.id == embed })
            #expect(rel.type == PackageInspector.imageRelType)
            let target = try #require(package.resolve(rel, from: "ppt/slides/slide1.xml"))
            #expect(target == "ppt/media/photo.png")
            #expect(try Data(contentsOf: package.root.appendingPathComponent(target)) == png)
            #expect(try package.contentType(of: target) == "image/png")

            let reread = try PptxReader.read(from: url)
            let picture = try #require(reread.slides.first?.pictures.first)
            #expect(picture.mediaFileName == "photo.png")
            #expect(reread.mediaFile(for: picture)?.data == png)
        }
    }

    // MARK: - Scenario: existing (read) pictures survive a round trip

    @Test(arguments: RealFileTests.testFiles.map(\.file))
    func `Every picture read from a fixture is still linked to the same media after a round trip`(file: String) throws {
        let source = try #require(RealFileTests.fixturePath(file))
        let original = try PptxReader.read(from: source)

        try TemporaryPPTX.written(original, "rt") { url in
            let package = try PackageInspector(url)
            defer { package.cleanup() }
            let violations = try package.integrityViolations()
            #expect(violations == [], "\(file)")

            let reread = try PptxReader.read(from: url)
            try #require(reread.slides.count == original.slides.count)
            for (index, (before, after)) in zip(original.slides, reread.slides).enumerated() {
                try #require(after.pictures.count == before.pictures.count, "\(file) slide \(index + 1)")
                for (p0, p1) in zip(before.pictures, after.pictures) {
                    #expect(p1.id == p0.id)
                    guard let media = original.mediaFile(for: p0) else { continue }
                    let linked = reread.mediaFile(for: p1)
                    #expect(linked?.data == media.data,
                            "\(file) slide \(index + 1) picture id=\(p0.id) lost its media \(media.fileName)")
                }
            }
        }
    }

    // MARK: - Scenario: every media type gets a content type

    @Test func `Media parts of any type are registered in the content types`() throws {
        let png = try Self.pngData()
        let svg = Data(#"<svg xmlns="http://www.w3.org/2000/svg" width="4" height="3"/>"#.utf8)
        let files: [(name: String, data: Data)] = [
            ("a.gif", try GeneratedImage.encoded(.gif)),
            ("b.BMP", try GeneratedImage.encoded(.bmp)),
            ("c.tiff", try GeneratedImage.encoded(.tiff)),
            ("d.svg", svg),
            ("noextension", png),
            ("e.xyz", png),
        ]
        let pres = Self.presentation(
            pictures: [files.enumerated().map { Self.picture($0.offset + 2, media: $0.element.name) }],
            images: files.map { MediaFile(id: $0.name, fileName: $0.name, data: $0.data) }
        )
        try TemporaryPPTX.written(pres) { url in
            let package = try PackageInspector(url)
            defer { package.cleanup() }
            let violations = try package.integrityViolations()
            #expect(violations == [])
            #expect(try package.contentType(of: "ppt/media/a.gif") == "image/gif")
            #expect(try package.contentType(of: "ppt/media/b.BMP") == "image/bmp")
            #expect(try package.contentType(of: "ppt/media/c.tiff") == "image/tiff")
            #expect(try package.contentType(of: "ppt/media/d.svg") == "image/svg+xml")
            #expect(try package.contentType(of: "ppt/media/noextension") == "image/png",
                    "an extension-less part is typed by sniffing its bytes")
            #expect(try package.contentType(of: "ppt/media/e.xyz") == "image/png")
        }
    }

    @Test func `A part's content type follows its bytes when they disagree with its extension`() throws {
        // Review round 1, HIGH 1: OPC types a part by [Content_Types].xml, not
        // by its extension, so a PNG may legitimately be named photo.svg.
        let png = try Self.pngData()
        let jpeg = try GeneratedImage.jpeg(width: 8, height: 6, orientation: 1)
        let files: [(name: String, data: Data, type: String)] = [
            ("photo.svg", png, "image/png"),
            ("shot.png", jpeg, "image/jpeg"),
            ("plain.png", png, "image/png"),
        ]
        let pres = Self.presentation(
            pictures: [files.enumerated().map { Self.picture($0.offset + 2, media: $0.element.name) }],
            images: files.map { MediaFile(id: $0.name, fileName: $0.name, data: $0.data) }
        )
        try TemporaryPPTX.written(pres) { url in
            let package = try PackageInspector(url)
            defer { package.cleanup() }
            let violations = try package.integrityViolations()
            #expect(violations == [])
            for file in files {
                #expect(try package.contentType(of: "ppt/media/\(file.name)") == file.type, "\(file.name)")
                #expect(try Data(contentsOf: package.root.appendingPathComponent("ppt/media/\(file.name)")) == file.data)
            }
        }
    }

    @Test func `A declared content type survives a round trip when the bytes cannot be identified`() throws {
        // An EMF-like part stored under a .png name, typed by an Override the
        // source package declared: ImageIO cannot identify it, and the
        // extension would say image/png, so only the declared type is right.
        var emf: [UInt8] = [0x01, 0x00, 0x00, 0x00, 0x6C, 0x00, 0x00, 0x00]
        emf += [UInt8](repeating: 0, count: 32) + Array(" EMF".utf8) + [UInt8](repeating: 0, count: 64)
        let url = try PictureMediaTests.tamperedCropped(
            relationship: PictureMediaTests.imageRel(target: "../media/image1.png"),
            extraFiles: ["ppt/media/image1.png": Data(emf)],
            contentTypeOverrides: ["/ppt/media/image1.png": "image/x-emf"]
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let pres = try PptxReader.read(from: url)
        let media = try #require(pres.images.first { $0.fileName == "image1.png" })
        #expect(media.packageContentType == "image/x-emf")

        try TemporaryPPTX.written(pres) { written in
            let package = try PackageInspector(written)
            defer { package.cleanup() }
            #expect(try package.contentType(of: "ppt/media/image1.png") == "image/x-emf")
        }
    }

    // MARK: - Scenario: sharing and per-slide relationship parts

    @Test func `Pictures sharing a media part share one relationship and every slide gets its own`() throws {
        let png = try Self.pngData()
        let pres = Self.presentation(
            pictures: [
                [Self.picture(2, media: "shared.png"), Self.picture(3, media: "shared.png")],
                [Self.picture(2, media: "shared.png")],
            ],
            images: [MediaFile(id: "shared.png", fileName: "shared.png", data: png)]
        )
        try TemporaryPPTX.written(pres) { url in
            let package = try PackageInspector(url)
            defer { package.cleanup() }
            let violations = try package.integrityViolations()
            #expect(violations == [])

            let slide1Images = try package.relationships(of: "ppt/slides/slide1.xml")
                .filter { $0.type == PackageInspector.imageRelType }
            #expect(slide1Images.count == 1)
            let embeds = try package.blipEmbeds(in: "ppt/slides/slide1.xml")
            #expect(embeds.count == 2)
            #expect(Set(embeds) == [slide1Images.first?.id])

            let slide2Images = try package.relationships(of: "ppt/slides/slide2.xml")
                .filter { $0.type == PackageInspector.imageRelType }
            #expect(slide2Images.count == 1)
            #expect(try package.partNames().filter { $0.hasPrefix("ppt/media/") } == ["ppt/media/shared.png"])
        }
    }

    @Test func `The relationship Id never collides with the layout relationship`() throws {
        // A read picture may carry rId1 from its source package, where rId1
        // was the image; in the written package rId1 is the slide layout.
        let png = try Self.pngData()
        let pres = Self.presentation(
            pictures: [[Self.picture(2, media: "p.png", rId: "rId1")]],
            images: [MediaFile(id: "p.png", fileName: "p.png", data: png)]
        )
        try TemporaryPPTX.written(pres) { url in
            let package = try PackageInspector(url)
            defer { package.cleanup() }
            let violations = try package.integrityViolations()
            #expect(violations == [])
            let reread = try PptxReader.read(from: url)
            #expect(reread.slides[0].pictures.first?.mediaFileName == "p.png")
        }
    }

    // MARK: - Scenario: pictures that cannot be linked

    @Test func `A picture naming media that does not exist fails to save and writes nothing`() throws {
        let pres = Self.presentation(pictures: [[Self.picture(2, media: "missing.png")]], images: [])
        let url = TemporaryPPTX.url("dangling")
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

    @Test func `A failed save leaves an existing destination file untouched`() throws {
        let url = TemporaryPPTX.url("sentinel")
        defer { try? FileManager.default.removeItem(at: url) }
        let sentinel = Data("existing deck".utf8)
        try sentinel.write(to: url)

        let failing: [(label: String, presentation: Presentation)] = [
            ("missing media", Self.presentation(pictures: [[Self.picture(2, media: "missing.png")]], images: [])),
            ("unrepresentable crop", {
                var pres = PptxWriter.createNew()
                pres.slides[0].elements = [.picture(Picture(
                    id: 2, sourceRect: PictureSourceRect(left: Int(Int32.max) + 1)
                ))]
                return pres
            }()),
        ]
        for c in failing {
            #expect(throws: PPTXError.self, "\(c.label)") {
                try PptxWriter.write(c.presentation, to: url)
            }
            #expect(try Data(contentsOf: url) == sentinel, "\(c.label) overwrote the destination")
        }
    }

    @Test func `A picture without media is written with no r:embed rather than a dangling one`() throws {
        let pres = Self.presentation(pictures: [[Self.picture(2, media: nil, rId: "rId7")]], images: [])
        try TemporaryPPTX.written(pres) { url in
            let package = try PackageInspector(url)
            defer { package.cleanup() }
            let violations = try package.integrityViolations()
            #expect(violations == [])
            #expect(try package.blipEmbeds(in: "ppt/slides/slide1.xml") == [nil])

            let reread = try PptxReader.read(from: url)
            let picture = try #require(reread.slides[0].pictures.first)
            #expect(picture.id == 2)
            #expect(picture.mediaFileName == nil)
        }
    }

    // MARK: - Scenario: media names are made safe part names

    @Test func `Unsafe or colliding media names are written inside ppt/media and stay linked`() throws {
        let escapeName = "pptx-escape-\(UUID().uuidString).png"
        let escapeURL = FileManager.default.temporaryDirectory.appendingPathComponent(escapeName)
        defer { try? FileManager.default.removeItem(at: escapeURL) }

        let names = [
            "../../../../\(escapeName)",   // would climb out of the writer's staging directory
            "sub/dir.png",                  // a nested path
            "a b.png",                      // needs percent-encoding in a relationship target
            "Photo.png", "photo.png",       // the same OPC part name (case-insensitive)
            "evil.xml",                     // would take the `xml` Default content type
            "訊息.png",                     // non-ASCII
        ]
        var images: [MediaFile] = []
        var pictures: [Picture] = []
        for (offset, name) in names.enumerated() {
            let data = try Self.pngData(10 + offset, 10)
            images.append(MediaFile(id: name, fileName: name, data: data))
            pictures.append(Self.picture(offset + 2, media: name))
        }
        let pres = Self.presentation(pictures: [pictures], images: images)

        try TemporaryPPTX.written(pres) { url in
            #expect(!FileManager.default.fileExists(atPath: escapeURL.path), "media escaped the package staging directory")

            let package = try PackageInspector(url)
            defer { package.cleanup() }
            let violations = try package.integrityViolations()
            #expect(violations == [])
            let parts = try package.partNames()
            let media = parts.filter { $0.hasPrefix("ppt/media/") }
            #expect(media.count == names.count)
            #expect(Set(media.map { $0.lowercased() }).count == names.count, "part names must differ case-insensitively")
            for part in media {
                let name = String(part.dropFirst("ppt/media/".count))
                #expect(name.range(of: #"^[A-Za-z0-9_-][A-Za-z0-9._-]*$"#, options: .regularExpression) != nil,
                        "unsafe part name \(part)")
                #expect((name as NSString).pathExtension.lowercased() != "xml")
            }
            #expect(parts.allSatisfy { $0 == "[Content_Types].xml" || $0.hasPrefix("_rels/")
                || $0.hasPrefix("ppt/") || $0.hasPrefix("docProps/") }, "unexpected part outside the layout: \(parts)")

            let reread = try PptxReader.read(from: url)
            for (offset, picture) in reread.slides[0].pictures.enumerated() {
                #expect(reread.mediaFile(for: picture)?.data == images[offset].data,
                        "picture for \(names[offset]) is not linked to its bytes")
            }
        }
    }

    @Test func `Duplicate media entries resolve to the first, as Presentation.mediaFile(for:) does`() throws {
        let first = try Self.pngData(20, 10)
        let second = try Self.pngData(10, 20)
        let pres = Self.presentation(
            pictures: [[Self.picture(2, media: "dup.png")]],
            images: [MediaFile(id: "dup.png", fileName: "dup.png", data: first),
                     MediaFile(id: "dup.png", fileName: "dup.png", data: second)]
        )
        #expect(pres.mediaFile(for: pres.slides[0].pictures[0])?.data == first)
        try TemporaryPPTX.written(pres) { url in
            let reread = try PptxReader.read(from: url)
            #expect(reread.mediaFile(for: reread.slides[0].pictures[0])?.data == first)
        }
    }
}
