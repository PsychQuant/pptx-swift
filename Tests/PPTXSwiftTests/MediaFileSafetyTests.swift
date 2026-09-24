import Testing
import Foundation
import OOXMLSwift
@testable import PPTXSwift

/// Only regular files that really live in the package's `ppt/media/` are
/// media (PsychQuant/macdoc#90 review round 2, MEDIUM 1). Symbolic links,
/// FIFOs and a `ppt/media` that is itself a link must be neither resolved as a
/// picture's media nor read into `Presentation.images`.
///
/// `ZipHelper.unzip` already refuses symlink entries, so these states are
/// built directly in an unpacked directory and parsed with
/// `PptxReader.read(unpackedPackageAt:)`.
@Suite(.serialized)
struct MediaFileSafetyTests {

    /// cropped.pptx unpacked, with the image relationship pointed at `target`.
    private static func unpackedCropped(target: String) throws -> URL {
        let fixture = try #require(RealFileTests.fixturePath("cropped.pptx"))
        let dir = try ZipHelper.unzip(fixture)
        let relsURL = dir.appendingPathComponent("ppt/slides/_rels/slide1.xml.rels")
        let rels = try String(contentsOf: relsURL, encoding: .utf8)
        #expect(rels.contains(#"Target="../media/image1.png""#))
        try rels.replacingOccurrences(of: #"Target="../media/image1.png""#, with: #"Target="\#(target)""#)
            .write(to: relsURL, atomically: true, encoding: .utf8)
        return dir
    }

    private static func outsideDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pptx-outside-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func read(_ dir: URL) throws -> (names: [String?], images: [String]) {
        let pres = try PptxReader.read(unpackedPackageAt: dir)
        let pictures = pres.slides.flatMap(\.pictures)
        #expect(!pictures.isEmpty)
        return (pictures.map(\.mediaFileName), pres.images.map(\.fileName).sorted())
    }

    @Test func `A symlink in ppt/media pointing outside the package is not media`() throws {
        let dir = try Self.unpackedCropped(target: "../media/a.png")
        defer { ZipHelper.cleanup(dir) }
        let outside = try Self.outsideDirectory()
        defer { try? FileManager.default.removeItem(at: outside) }
        let secret = outside.appendingPathComponent("secret.png")
        try Data(contentsOf: dir.appendingPathComponent("ppt/media/image1.png")).write(to: secret)
        try FileManager.default.createSymbolicLink(
            at: dir.appendingPathComponent("ppt/media/a.png"), withDestinationURL: secret)

        let result = try Self.read(dir)
        #expect(result.names.allSatisfy { $0 == nil })
        #expect(result.images == ["image1.png"])
    }

    @Test func `A symlink in ppt/media pointing at another media file is rejected too`() throws {
        let dir = try Self.unpackedCropped(target: "../media/alias.png")
        defer { ZipHelper.cleanup(dir) }
        try FileManager.default.createSymbolicLink(
            atPath: dir.appendingPathComponent("ppt/media/alias.png").path, withDestinationPath: "image1.png")

        let result = try Self.read(dir)
        #expect(result.names.allSatisfy { $0 == nil })
        #expect(result.images == ["image1.png"])
    }

    @Test func `A FIFO in ppt/media is not media and is never opened`() throws {
        let dir = try Self.unpackedCropped(target: "../media/pipe.png")
        defer { ZipHelper.cleanup(dir) }
        let fifo = dir.appendingPathComponent("ppt/media/pipe.png").path
        #expect(mkfifo(fifo, 0o600) == 0)

        let result = try Self.read(dir)
        #expect(result.names.allSatisfy { $0 == nil })
        #expect(result.images == ["image1.png"])
    }

    @Test func `A ppt/media directory that is a symlink out of the package yields no media`() throws {
        let dir = try Self.unpackedCropped(target: "../media/image1.png")
        defer { ZipHelper.cleanup(dir) }
        let outside = try Self.outsideDirectory()
        defer { try? FileManager.default.removeItem(at: outside) }
        let media = dir.appendingPathComponent("ppt/media")
        try FileManager.default.moveItem(at: media.appendingPathComponent("image1.png"),
                                         to: outside.appendingPathComponent("image1.png"))
        try FileManager.default.removeItem(at: media)
        try FileManager.default.createSymbolicLink(at: media, withDestinationURL: outside)

        let result = try Self.read(dir)
        #expect(result.names.allSatisfy { $0 == nil })
        #expect(result.images.isEmpty)
    }

    @Test func `The ordinary regular media file is still resolved and read`() throws {
        let dir = try Self.unpackedCropped(target: "../media/image1.png")
        defer { ZipHelper.cleanup(dir) }
        let result = try Self.read(dir)
        #expect(result.names.allSatisfy { $0 == "image1.png" })
        #expect(result.images == ["image1.png"])
    }
}
