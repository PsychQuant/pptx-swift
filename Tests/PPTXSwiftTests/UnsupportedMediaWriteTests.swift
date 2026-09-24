import Testing
import Foundation
@testable import PPTXSwift

/// PsychQuant/pptx-swift#5 (secondary): audio／video (`a:audioFile`／
/// `a:videoFile`, usually paired with a `p:timing` click-to-play trigger) is
/// not modeled — `PptxWriter` refuses to write a slide that has it rather
/// than silently dropping the playback relationship, per the issue's "不要
/// 默默丟掉" requirement. See `RealFileTests.roundTrip` and
/// `PictureRelationshipWriteTests`'s fixture round trip for the same
/// behavior against the real `audio.pptx` fixture.
struct UnsupportedMediaWriteTests {

    @Test func `A slide with an audioFile reference fails to save and writes nothing`() throws {
        var pres = PptxWriter.createNew()
        pres.slides[0].containsUnsupportedMedia = true
        let url = TemporaryPPTX.url("unsupported-audio")
        defer { try? FileManager.default.removeItem(at: url) }

        let error = #expect(throws: PPTXError.self) {
            try PptxWriter.write(pres, to: url)
        }
        guard case .writeError(let message)? = error else {
            Issue.record("expected .writeError, got \(String(describing: error))")
            return
        }
        #expect(message.contains("投影片 1"))
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func `A failed save due to unsupported media leaves an existing destination file untouched`() throws {
        let url = TemporaryPPTX.url("unsupported-sentinel")
        defer { try? FileManager.default.removeItem(at: url) }
        let sentinel = Data("existing deck".utf8)
        try sentinel.write(to: url)

        var pres = PptxWriter.createNew()
        pres.slides[0].containsUnsupportedMedia = true
        #expect(throws: PPTXError.self) {
            try PptxWriter.write(pres, to: url)
        }
        #expect(try Data(contentsOf: url) == sentinel)
    }

    @Test func `A slide with no audioFile or videoFile reference is unaffected`() throws {
        var pres = PptxWriter.createNew()
        pres.slides[0].elements = [.shape(Shape(id: 2, name: "Plain"))]
        #expect(pres.slides[0].containsUnsupportedMedia == false)

        try TemporaryPPTX.written(pres) { url in
            #expect(FileManager.default.fileExists(atPath: url.path))
        }
    }

    @Test func `PptxReader flags a slide whose audioFile relationship is embedded audio`() throws {
        let source = try #require(RealFileTests.fixturePath("audio.pptx"))
        let pres = try PptxReader.read(from: source)
        try #require(pres.slides.count == 1)
        #expect(pres.slides[0].containsUnsupportedMedia == true)
    }
}
