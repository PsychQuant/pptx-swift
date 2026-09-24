import Testing
import Foundation
@testable import PPTXSwift

/// 用 Apache POI 公開測試檔案驗證 pptx-swift（本地 Fixtures）
/// 來源: https://github.com/apache/poi/tree/trunk/test-data/slideshow (Apache License 2.0)
struct RealFileTests {

    static let testFiles: [(name: String, file: String, description: String)] = [
        ("SampleShow",     "sample1.pptx",   "基本簡報：文字、形狀"),
        ("table_test",     "table.pptx",     "表格測試"),
        ("shapes",         "shapes.pptx",    "多種形狀"),
        ("Header",         "header.pptx",    "含頁首頁尾"),
        ("Comment",        "comment.pptx",   "含備註"),
        ("CroppedBitmap",  "cropped.pptx",   "含裁切圖片"),
        ("EmbeddedAudio",  "audio.pptx",     "含嵌入音訊"),
        ("Performance",    "perf.pptx",      "大簡報（效能測試）"),
    ]

    /// 從 Tests/Fixtures/ 取得 fixture 路徑
    static func fixturePath(_ file: String) -> URL? {
        // #file = Tests/PPTXSwiftTests/RealFileTests.swift → 往上一層到 Tests/，再進 Fixtures/
        let testsDir = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()  // PPTXSwiftTests/
        // Fixtures 可能在 PPTXSwiftTests/ 旁邊（resource copy）或在 Tests/ 下
        let candidates = [
            testsDir.appendingPathComponent("Fixtures/\(file)"),
            testsDir.deletingLastPathComponent().appendingPathComponent("Fixtures/\(file)"),
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    @Test("讀取公開 PPTX — 基本結構", arguments: testFiles)
    func readBasicStructure(file: (name: String, file: String, description: String)) throws {
        guard let url = Self.fixturePath(file.file) else {
            print("⏭ 跳過 \(file.name)：fixture 不存在")
            return
        }

        let pres = try PptxReader.read(from: url)

        print("📊 \(file.name) (\(file.description)):")
        print("   投影片: \(pres.slideCount), 圖片: \(pres.images.count), 母片: \(pres.slideMasters.count)")
        print("   尺寸: \(pres.slideSize.widthInches)×\(pres.slideSize.heightInches) inches")
        if let theme = pres.theme {
            print("   主題: \(theme.name), 字型: \(theme.fontScheme.majorFont)/\(theme.fontScheme.minorFont)")
        }

        #expect(pres.slideCount > 0, "\(file.name) 應該有投影片")
    }

    @Test("讀取公開 PPTX — 文字提取", arguments: testFiles)
    func readTextContent(file: (name: String, file: String, description: String)) throws {
        guard let url = Self.fixturePath(file.file) else { return }
        let pres = try PptxReader.read(from: url)
        let fullText = pres.getText()
        print("   \(file.name): \(fullText.count) chars, \(pres.slides.flatMap(\.shapes).count) shapes total")
    }

    @Test("讀取公開 PPTX — 主題色彩", arguments: testFiles)
    func readTheme(file: (name: String, file: String, description: String)) throws {
        guard let url = Self.fixturePath(file.file) else { return }
        let pres = try PptxReader.read(from: url)
        if let theme = pres.theme {
            let colors = theme.colorScheme.allColors
            #expect(colors.count == 12, "\(file.name) 色彩配置應有 12 色")
            for (name, hex) in colors {
                #expect(!hex.isEmpty, "\(file.name) 的 \(name) 顏色不應為空")
            }
        }
    }

    @Test("讀取公開 PPTX — Round-trip", arguments: testFiles)
    func roundTrip(file: (name: String, file: String, description: String)) throws {
        guard let url = Self.fixturePath(file.file) else { return }
        let pres = try PptxReader.read(from: url)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pptx-rt-\(UUID().uuidString).pptx")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // audio.pptx 含嵌入音訊（a:audioFile + p:timing 播放觸發）：pptx-swift 不建模這層，
        // PptxWriter 拒絕寫出而不是默默遺失（PsychQuant/pptx-swift#5），round trip 因此預期失敗。
        guard !pres.slides.contains(where: { $0.containsUnsupportedMedia }) else {
            #expect(throws: PPTXError.self, "\(file.name) 含不支援的音訊／影片，寫出應拒絕") {
                try PptxWriter.write(pres, to: tempURL)
            }
            #expect(!FileManager.default.fileExists(atPath: tempURL.path), "\(file.name) 寫出失敗不應留下檔案")
            print("   \(file.name): 含音訊／影片，寫出如預期被拒絕")
            return
        }

        try PptxWriter.write(pres, to: tempURL)

        let fileSize = try FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? Int ?? 0
        #expect(fileSize > 0, "\(file.name) round-trip 輸出不應為空")

        let reread = try PptxReader.read(from: tempURL)
        #expect(reread.slideCount == pres.slideCount,
                "\(file.name) round-trip slides: \(reread.slideCount) vs \(pres.slideCount)")

        print("   \(file.name): \(pres.slideCount) slides → \(fileSize) bytes → \(reread.slideCount) slides ✓")
    }

    @Test("表格解析 — table.pptx")
    func tableSpecific() throws {
        guard let url = Self.fixturePath("table.pptx") else {
            print("⏭ 跳過 table 測試")
            return
        }
        let pres = try PptxReader.read(from: url)
        var tableCount = 0
        for (si, slide) in pres.slides.enumerated() {
            for frame in slide.tables {
                if let table = frame.table {
                    tableCount += 1
                    print("   Slide \(si+1) Table: \(table.columnCount)×\(table.rowCount)")
                }
            }
        }
        print("   共 \(tableCount) 個表格")
    }

    @Test("形狀多樣性 — shapes.pptx")
    func shapesSpecific() throws {
        guard let url = Self.fixturePath("shapes.pptx") else {
            print("⏭ 跳過 shapes 測試")
            return
        }
        let pres = try PptxReader.read(from: url)
        var geometries: Set<String> = []
        for slide in pres.slides {
            for element in slide.elements {
                if case .shape(let shape) = element {
                    geometries.insert(shape.geometry.rawValue)
                }
            }
        }
        print("   幾何形狀: \(geometries.sorted().joined(separator: ", "))")
        #expect(!geometries.isEmpty, "shapes.pptx 應該有形狀")
    }

    @Test("大檔案效能 — perf.pptx")
    func performanceTest() throws {
        guard let url = Self.fixturePath("perf.pptx") else {
            print("⏭ 跳過效能測試")
            return
        }
        let start = Date()
        let pres = try PptxReader.read(from: url)
        let readTime = Date().timeIntervalSince(start)
        print("   讀取 \(pres.slideCount) slides + \(pres.images.count) images in \(String(format: "%.2f", readTime))s")
        #expect(readTime < 10.0, "大簡報讀取應在 10 秒內完成")
    }
}
