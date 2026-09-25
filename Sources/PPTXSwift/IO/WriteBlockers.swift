import Foundation

/// `PptxWriter.write` 會拒絕存檔的一個原因。依**呼叫當下**的模型狀態判斷，不是
/// 依「讀進來的檔案」：呼叫端把造成問題的內容換掉（例如用 typed 填色取代圖片
/// 填色、刪掉圖表）之後，同一份簡報就能存檔。
///
/// 只有這四類，封閉列舉——新增拒絕理由時要在這裡加 case，不要讓 writer 在別處
/// 另外丟出使用者事先查不到的錯誤。
public struct WriteBlocker: Equatable, CustomStringConvertible {
    public enum Reason: Equatable {
        /// 投影片含音訊、影片或換場音效：播放觸發、時間軸（`p:timing`）與換場
        /// 音效都沒有建模，寫出會遺失播放能力（PsychQuant/pptx-swift#5）。
        case unsupportedMedia
        /// 原樣保存的 XML 裡有 relationships 命名空間的屬性（`r:embed`／`r:link`／
        /// `r:id`……）。writer 每張投影片的 rels 都從頭配置（只替 `p:pic` 配
        /// image relationship），原樣片段裡的舊 rId 在新 rels 裡不是懸空、就是
        /// 指向別的 part（例如另一張圖）——PsychQuant/pptx-swift#9 對 `.raw`
        /// 元素、#12 審查 C1 對 `spPr` 原樣片段。`location` 是片段在元素上的
        /// 位置，`attributes` 是找到的屬性名稱。
        case relationshipReference(location: String, attributes: [String])
        /// 原樣保存的 XML 無法解析（只可能出自呼叫端手動指定的字串），寫出會產生
        /// 不合法的投影片。
        case malformedPassthroughXML(location: String)
        /// 預設幾何的 `prst` 是 `ShapeGeometry` 的哨兵值（`unknown`／`custom`）或
        /// 空字串，不是 `ST_ShapeType` 的值，寫出後 PowerPoint 會要求修復。
        case invalidPresetGeometry(prst: String)
    }

    /// 投影片索引（0 起算）。
    public let slideIndex: Int
    /// 元素種類的中文名稱（`形狀`、`連接線`、`群組`、`未建模元素 <mc:AlternateContent>`）；
    /// 投影片層級的原因（`unsupportedMedia`）為 `nil`。
    public let elementKind: String?
    public let elementId: Int?
    public let elementName: String?
    public let reason: Reason

    public var description: String {
        let slide = "投影片 \(slideIndex + 1)"
        var element = elementKind ?? ""
        if let elementId { element += " id=\(elementId)" }
        if let elementName, !elementName.isEmpty { element += "「\(elementName)」" }
        switch reason {
        case .unsupportedMedia:
            return "\(slide) 含音訊、影片或換場音效：pptx-swift 尚未建模播放觸發、時間軸（p:timing）與換場音效，寫出會遺失播放能力，拒絕存檔"
        case .relationshipReference(let location, let attributes):
            return "\(slide) 的\(element)：\(location)引用了 relationship（\(attributes.joined(separator: "、"))）。"
                + "pptx-swift 無法安全地確保該 rId 在重新配置後仍有效、且不與新配的 rId 衝突，拒絕存檔"
        case .malformedPassthroughXML(let location):
            return "\(slide) 的\(element)：\(location)的原樣 XML 無法解析，寫出會產生不合法的投影片，拒絕存檔"
        case .invalidPresetGeometry(let prst):
            return "\(slide) 的\(element)：預設幾何 prst=\"\(prst)\" 不是 ST_ShapeType 的值，寫出後檔案需要修復，拒絕存檔（請改設一個實際的幾何形狀）"
        }
    }
}

public extension Presentation {
    /// 目前狀態下會讓 `PptxWriter.write` 拒絕存檔的全部原因，依投影片、文件順序
    /// 排列（空陣列表示可以存檔）。`PptxWriter.write` 遇到第一個就丟出
    /// `PPTXError.writeError(blocker.description)`；呼叫端（例如 che-pptx-mcp 的
    /// `open_presentation`）可以在開檔時就列出來，不必等到存檔才發現。
    var writeBlockers: [WriteBlocker] {
        slides.enumerated().flatMap { index, slide in
            (slide.containsUnsupportedMedia
                ? [WriteBlocker(slideIndex: index, elementKind: nil, elementId: nil, elementName: nil, reason: .unsupportedMedia)]
                : [])
            + slide.elements.flatMap { WriteBlockerScan.blockers(in: $0, slideIndex: index) }
        }
    }
}

/// 一段會被原樣（或以原樣為底合併）寫進投影片的 XML，以及它在元素上的位置。
struct PassthroughFragment {
    let location: String
    let xml: String
}

extension Shape {
    /// 會被原樣寫出的全部片段。`PptxWriter` 寫出的原樣內容都要列在這裡——
    /// `writeBlockers` 只掃這份清單，漏列的片段不會被檢查（writer 另有對整張
    /// 投影片輸出的最後防線，見 `PptxWriter.strayRelationshipReferences`）。
    var passthroughFragments: [PassthroughFragment] {
        spPrPassthroughFragments(geometry: geometryDefinition, fill: fill, outline: outline,
                                 effectXML: effectXML, scene3dXML: scene3dXML, sp3dXML: sp3dXML,
                                 extLstXML: extLstXML, styleXML: styleXML)
    }
}

extension Connector {
    var passthroughFragments: [PassthroughFragment] {
        spPrPassthroughFragments(geometry: geometryDefinition, fill: fill, outline: outline,
                                 effectXML: effectXML, scene3dXML: scene3dXML, sp3dXML: sp3dXML,
                                 extLstXML: extLstXML, styleXML: styleXML)
    }
}

extension GroupShape {
    var passthroughFragments: [PassthroughFragment] {
        var fragments: [PassthroughFragment] = []
        if case .raw(let xml)? = fill { fragments.append(PassthroughFragment(location: "grpSpPr 的填色", xml: xml)) }
        if let effectXML { fragments.append(PassthroughFragment(location: "grpSpPr 的效果", xml: effectXML)) }
        if let scene3dXML { fragments.append(PassthroughFragment(location: "grpSpPr 的 scene3d", xml: scene3dXML)) }
        if let extLstXML { fragments.append(PassthroughFragment(location: "grpSpPr 的 extLst", xml: extLstXML)) }
        return fragments
    }
}

private func spPrPassthroughFragments(
    geometry: GeometryDefinition, fill: ShapeFill?, outline: ShapeOutline?,
    effectXML: String?, scene3dXML: String?, sp3dXML: String?, extLstXML: String?, styleXML: String?
) -> [PassthroughFragment] {
    var fragments: [PassthroughFragment] = []
    if case .custom(let xml) = geometry { fragments.append(PassthroughFragment(location: "spPr 的自訂幾何", xml: xml)) }
    if case .raw(let xml)? = fill { fragments.append(PassthroughFragment(location: "spPr 的填色", xml: xml)) }
    // 外框被 typed 欄位改動過時，寫出的是以原始 XML 為底的合併結果：只改寫
    // w／線條填色／headEnd／tailEnd（這幾樣本身不會帶 relationship），其餘原封
    // 不動——所以檢查原始 XML 就涵蓋了實際寫出的內容。
    if let xml = outline?.source?.xml { fragments.append(PassthroughFragment(location: "spPr 的外框", xml: xml)) }
    if let effectXML { fragments.append(PassthroughFragment(location: "spPr 的效果", xml: effectXML)) }
    if let scene3dXML { fragments.append(PassthroughFragment(location: "spPr 的 scene3d", xml: scene3dXML)) }
    if let sp3dXML { fragments.append(PassthroughFragment(location: "spPr 的 sp3d", xml: sp3dXML)) }
    if let extLstXML { fragments.append(PassthroughFragment(location: "spPr 的 extLst", xml: extLstXML)) }
    if let styleXML { fragments.append(PassthroughFragment(location: "p:style", xml: styleXML)) }
    return fragments
}

enum WriteBlockerScan {
    /// relationships 命名空間：Transitional 與 Strict 兩種寫法。判斷一律看屬性
    /// 的命名空間 URI，不看前綴字串（前綴可以是任意名字）。
    static let relationshipNamespaces: Set<String> = [
        "http://schemas.openxmlformats.org/officeDocument/2006/relationships",
        "http://purl.oclc.org/ooxml/officeDocument/relationships",
    ]

    static func blockers(in element: SlideElement, slideIndex: Int) -> [WriteBlocker] {
        func make(_ kind: String, _ id: Int?, _ name: String?, _ reason: WriteBlocker.Reason) -> WriteBlocker {
            WriteBlocker(slideIndex: slideIndex, elementKind: kind, elementId: id, elementName: name, reason: reason)
        }
        func scan(_ kind: String, _ id: Int, _ name: String, _ geometry: GeometryDefinition?, _ fragments: [PassthroughFragment]) -> [WriteBlocker] {
            var result: [WriteBlocker] = []
            if case .preset(let prst, _)? = geometry, !isWritablePreset(prst) {
                result.append(make(kind, id, name, .invalidPresetGeometry(prst: prst)))
            }
            for fragment in fragments {
                if let reason = reason(for: fragment) { result.append(make(kind, id, name, reason)) }
            }
            return result
        }

        switch element {
        case .shape(let shape):
            return scan("形狀", shape.id, shape.name, shape.geometryDefinition, shape.passthroughFragments)
        case .connector(let connector):
            return scan("連接線", connector.id, connector.name, connector.geometryDefinition, connector.passthroughFragments)
        case .group(let group):
            return scan("群組", group.id, group.name, nil, group.passthroughFragments)
                + group.elements.flatMap { blockers(in: $0, slideIndex: slideIndex) }
        case .raw(let raw):
            let fragment = PassthroughFragment(location: "其原樣 XML", xml: raw.xml)
            let kind = "未建模元素 <\(raw.localName)>"
            if raw.referencesRelationship {
                let attributes = (try? relationshipAttributes(in: raw.xml)).flatMap { $0.isEmpty ? nil : $0 } ?? ["r:*"]
                return [make(kind, raw.elementIds.first, nil, .relationshipReference(location: fragment.location, attributes: attributes))]
            }
            return reason(for: fragment).map { [make(kind, raw.elementIds.first, nil, $0)] } ?? []
        case .picture, .graphicFrame:
            // Picture 的 a:blip 由 writer 自己配置 relationship；表格沒有原樣片段。
            return []
        }
    }

    static func isWritablePreset(_ prst: String) -> Bool {
        !prst.isEmpty && prst != ShapeGeometry.unknown.rawValue && prst != ShapeGeometry.custom.rawValue
    }

    private static func reason(for fragment: PassthroughFragment) -> WriteBlocker.Reason? {
        guard let attributes = try? relationshipAttributes(in: fragment.xml) else {
            return .malformedPassthroughXML(location: fragment.location)
        }
        return attributes.isEmpty ? nil : .relationshipReference(location: fragment.location, attributes: attributes)
    }

    /// 片段裡每一個 relationships 命名空間屬性的名稱（依文件順序）；解析失敗
    /// 時丟出錯誤。片段放在與寫出的投影片根節點相同的命名空間環境裡解析
    /// （`a`／`r`／`p` 已綁定）——`PptxReader` 讀到的片段都是 self-contained，
    /// 但呼叫端手動指定的片段可以依賴投影片根節點的宣告，寫出後同樣合法；
    /// 未綁定的其他前綴則會在這裡被當成無法解析。
    static func relationshipAttributes(in xml: String) throws -> [String] {
        let wrapped = "<pptx-swift-fragment"
            + " xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\""
            + " xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\""
            + " xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\">"
            + xml + "</pptx-swift-fragment>"
        let document = try XMLDocument(xmlString: wrapped, options: [])
        return try withExtendedLifetime(document) {
            try document.nodes(forXPath: "//@*")
                .filter { relationshipNamespaces.contains($0.uri ?? "") }
                .map { $0.name ?? $0.localName ?? "?" }
        }
    }
}
