import Testing
import Foundation
import OOXMLSwift
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

    // MARK: - Scenario: detection is namespace-scoped, not just local-name (Codex R2)

    /// `sample1.pptx`'s `ppt/slides/slide1.xml`, with `fragment` spliced in
    /// right before `</p:sld>` (a valid position for any of `p:clrMapOvr`,
    /// `p:transition`, `p:timing`, `p:extLst` — all optional trailing
    /// siblings of `p:cSld` in `CT_Slide`), rezipped to a temp `.pptx`.
    static func slide1(withTrailingFragment fragment: String) throws -> URL {
        let fixture = try #require(RealFileTests.fixturePath("sample1.pptx"))
        let dir = try ZipHelper.unzip(fixture)
        defer { ZipHelper.cleanup(dir) }

        let slideURL = dir.appendingPathComponent("ppt/slides/slide1.xml")
        var slideXML = try String(contentsOf: slideURL, encoding: .utf8)
        try #require(slideXML.contains("</p:sld>"))
        slideXML = slideXML.replacingOccurrences(of: "</p:sld>", with: fragment + "</p:sld>")
        try slideXML.write(to: slideURL, atomically: true, encoding: .utf8)

        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("pptx-unsupported-media-\(UUID().uuidString).pptx")
        try ZipHelper.zip(dir, to: out)
        return out
    }

    @Test func `An element with a matching local name in an unrelated namespace does not trigger the gate`() throws {
        // Same local name as one of the EG_Media choices, but a made-up
        // namespace — must NOT be treated as OOXML audio (Codex R2 MEDIUM:
        // the original local-name()-only XPath would have false-positived here).
        let url = try Self.slide1(withTrailingFragment: #"<custom:audioFile xmlns:custom="https://example.com/not-ooxml" val="1"/>"#)
        defer { try? FileManager.default.removeItem(at: url) }

        let pres = try PptxReader.read(from: url)
        let slide1 = try #require(pres.slides.first)
        #expect(slide1.containsUnsupportedMedia == false)
    }

    @Test func `A transition sound (p:snd) triggers the gate even with no EG_Media element present`() throws {
        // Transition sound (CT_TransitionSoundAction) is a separate mechanism
        // from EG_Media — a slide can have `p:snd` with no `a:audioFile`/etc.
        // anywhere (Codex R2 HIGH: EG_Media alone is not exhaustive).
        let fragment = """
        <p:transition><p:sndAc><p:stSnd><p:snd r:embed="rId99"/></p:stSnd></p:sndAc></p:transition>
        """
        let url = try Self.slide1(withTrailingFragment: fragment)
        defer { try? FileManager.default.removeItem(at: url) }

        let pres = try PptxReader.read(from: url)
        let slide1 = try #require(pres.slides.first)
        #expect(slide1.containsUnsupportedMedia == true)
    }
}
