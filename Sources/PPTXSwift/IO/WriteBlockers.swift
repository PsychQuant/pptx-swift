import Foundation

/// `PptxWriter.write` 會拒絕存檔的一個原因。除了 `unsupportedMedia`（見該 case
/// 的例外說明），都依**呼叫當下**的模型狀態判斷，不是依「讀進來的檔案」：呼叫端
/// 把造成問題的內容換掉（例如用 typed 填色取代圖片填色、刪掉圖表）之後，同一份
/// 簡報就能存檔。
///
/// `Reason` 只有下列五類，封閉列舉——新增拒絕理由時要在這裡加 case，不要讓
/// writer 在別處另外丟出使用者事先查不到的錯誤。
public struct WriteBlocker: Equatable, CustomStringConvertible {
    public enum Reason: Equatable {
        /// 投影片含音訊、影片或換場音效：播放觸發、時間軸（`p:timing`）與換場
        /// 音效都沒有建模，寫出會遺失播放能力（PsychQuant/pptx-swift#5）。
        ///
        /// **例外：不依目前狀態判斷。** 依據是 `PptxReader` 讀檔時設定的旗標
        /// `Slide.containsUnsupportedMedia`；刪掉投影片上的媒體元素**不會**清除它，
        /// 只有呼叫端自己把旗標設成 `false`（表示接受遺失播放能力）才會解除。
        case unsupportedMedia
        /// 原樣保存的 XML 裡有 relationships 命名空間的屬性（`r:embed`／`r:link`／
        /// `r:id`……）。writer 每張投影片的 rels 都從頭配置（只替 `p:pic` 配
        /// image relationship），原樣片段裡的舊 rId 在新 rels 裡不是懸空、就是
        /// 指向別的 part（例如另一張圖）——PsychQuant/pptx-swift#9 對 `.raw`
        /// 元素、#12 審查 C1 對 `spPr` 原樣片段。`attributes` 是找到的屬性名稱。
        case relationshipReference(part: PassthroughPart, attributes: [String])
        /// 原樣 XML 寫出後會是不合法的投影片：無法解析、不是恰好一個根元素、根元素
        /// 外有文字，或根元素不能放在這個位置（例如 `ShapeFill.raw` 的根不是
        /// `EG_FillProperties` 的選項）。只可能出自呼叫端手動指定的字串——
        /// `PptxReader` 產生的片段都合格。`detail` 是具體問題。
        case malformedPassthroughXML(part: PassthroughPart, detail: String)
        /// 預設幾何的 `prst` 是 `ShapeGeometry` 的哨兵值（`unknown`／`custom`）或
        /// 空字串，不是 `ST_ShapeType` 的值，寫出後 PowerPoint 會要求修復。
        case invalidPresetGeometry(prst: String)
        /// typed 的 `GraphicFrame` 沒有表格（`table == nil`）。writer 只會寫表格類
        /// 的 graphicFrame，這種值寫出時會整個消失（#12 審查 R2 L-3；
        /// `PptxReader` 不會產生它，非表格的 graphicFrame 讀成 `.raw`，見 #15）。
        case graphicFrameWithoutTable
    }

    /// 被擋下的元素是什麼。
    public enum Element: Equatable {
        case shape
        case connector
        case group
        /// typed 的 `GraphicFrame`（見 `Reason.graphicFrameWithoutTable`）。
        case graphicFrame
        /// 讀成 `.raw` 的內嵌物件（非表格的 graphicFrame，或包著它的
        /// `mc:AlternateContent`）。
        case embeddedObject(EmbeddedObjectKind)
        /// 其他讀成 `.raw` 的未建模元素；`localName` 是它的 XML local name。
        case unmodeled(localName: String)

        /// 給人看的名稱。
        public var displayName: String {
            switch self {
            case .shape: return "形狀"
            case .connector: return "連接線"
            case .group: return "群組"
            case .graphicFrame: return "graphicFrame"
            case .embeddedObject(let kind): return kind.displayName
            case .unmodeled(let localName): return "未建模元素 <\(localName)>"
            }
        }
    }

    /// 原樣片段在元素上的位置。
    public enum PassthroughPart: Equatable {
        /// 自訂幾何（`<a:custGeom>`）。
        case geometry
        /// 填色（`EG_FillProperties`）。
        case fill
        /// 外框（`<a:ln>`）的原始 XML。
        case outline
        /// 效果（`<a:effectLst>`／`<a:effectDag>`）。
        case effects
        case scene3d
        case shape3d
        case extensionList
        /// `p:style`。
        case style
        /// 整個未建模元素本身（`.raw`）。
        case wholeElement

        /// 這個位置的根元素必須屬於的命名空間（Transitional 與 Strict）；`nil` 表示
        /// 不限（#12 審查 R3 L-3'：只比對 local name 的話，`<p:noFill/>` 這種名字對、
        /// 命名空間錯的片段會放行）。
        var allowedRootNamespaces: Set<String>? {
            switch self {
            case .style:
                return ["http://schemas.openxmlformats.org/presentationml/2006/main",
                        "http://purl.oclc.org/ooxml/presentationml/main"]
            case .wholeElement:
                return nil
            case .geometry, .fill, .outline, .effects, .scene3d, .shape3d, .extensionList:
                return ["http://schemas.openxmlformats.org/drawingml/2006/main",
                        "http://purl.oclc.org/ooxml/drawingml/main"]
            }
        }

        /// 這個位置可以放的根元素 local name；`nil` 表示任何單一元素都可以。
        var allowedRootNames: Set<String>? {
            switch self {
            case .geometry: return ["custGeom"]
            case .fill: return PptxReader.fillLocalNames
            case .outline: return ["ln"]
            case .effects: return ["effectLst", "effectDag"]
            case .scene3d: return ["scene3d"]
            case .shape3d: return ["sp3d"]
            case .extensionList: return ["extLst"]
            case .style: return ["style"]
            case .wholeElement: return nil
            }
        }

        func label(in element: Element?) -> String {
            let container = element == .group ? "grpSpPr" : "spPr"
            switch self {
            case .geometry: return "\(container) 的自訂幾何"
            case .fill: return "\(container) 的填色"
            case .outline: return "\(container) 的外框"
            case .effects: return "\(container) 的效果"
            case .scene3d: return "\(container) 的 scene3d"
            case .shape3d: return "\(container) 的 sp3d"
            case .extensionList: return "\(container) 的 extLst"
            case .style: return "p:style"
            case .wholeElement: return "原樣 XML"
            }
        }
    }

    /// 投影片索引（0 起算）。
    public let slideIndex: Int
    /// 被擋下的元素；投影片層級的原因（`unsupportedMedia`）為 `nil`。
    public let element: Element?
    public let elementId: Int?
    public let elementName: String?
    /// 元素所在的群組 id，由外而內（頂層元素為空陣列）。呼叫端若只能操作頂層
    /// 元素（例如 che-pptx-mcp 的 `set_shape_fill`／`delete_shape`），要改的是
    /// `topLevelElementId`（#12 審查 R2 M-1）。
    public let enclosingGroupIds: [Int]
    public let reason: Reason

    public init(
        slideIndex: Int,
        element: Element?,
        elementId: Int?,
        elementName: String?,
        enclosingGroupIds: [Int] = [],
        reason: Reason
    ) {
        self.slideIndex = slideIndex
        self.element = element
        self.elementId = elementId
        self.elementName = elementName
        self.enclosingGroupIds = enclosingGroupIds
        self.reason = reason
    }

    /// 投影片頂層（`p:spTree` 的直接子元素）中包含這個元素的那一個的 id：元素在
    /// 群組內時是最外層群組的 id，否則是元素自己的 id。
    public var topLevelElementId: Int? { enclosingGroupIds.first ?? elementId }

    /// 元素的中文名稱（`形狀`、`圖表`、`未建模元素 <mc:AlternateContent>`……）；
    /// 投影片層級的原因為 `nil`。
    public var elementKind: String? { element?.displayName }

    /// 「群組 id=90 內的形狀 id=20「名稱」」這樣的描述；投影片層級的原因為空字串。
    public var elementDescription: String {
        guard let element else { return "" }
        var text = enclosingGroupIds.isEmpty
            ? ""
            : enclosingGroupIds.map { "群組 id=\($0)" }.joined(separator: " > ") + " 內的"
        text += element.displayName
        if let elementId { text += " id=\(elementId)" }
        if let elementName, !elementName.isEmpty { text += "「\(elementName)」" }
        return text
    }

    /// 為什麼被擋下（不含投影片與元素的描述）。
    public var reasonDescription: String {
        switch reason {
        case .unsupportedMedia:
            return "含音訊、影片或換場音效：pptx-swift 尚未建模播放觸發、時間軸（p:timing）與換場音效，寫出會遺失播放能力"
        case .relationshipReference(.wholeElement, let attributes) where storesContentInAnotherPart:
            return "內容存放在檔案的另一個 part，透過 relationship（\(attributes.joined(separator: "、"))）引用；"
                + "pptx-swift 會重新配置 relationship，無法保證寫出後仍指向它"
        case .relationshipReference(let part, let attributes):
            return "\(spaced(part.label(in: element)))引用了 relationship（\(attributes.joined(separator: "、"))）；"
                + "pptx-swift 無法安全地確保該 rId 在重新配置後仍有效、且不與新配的 rId 衝突"
        case .malformedPassthroughXML(.wholeElement, let detail):
            return "原樣 XML \(detail)，寫出會產生不合法的投影片"
        case .malformedPassthroughXML(let part, let detail):
            return "\(spaced(part.label(in: element)))的原樣 XML \(detail)，寫出會產生不合法的投影片"
        case .invalidPresetGeometry(let prst):
            return "預設幾何 prst=\"\(prst)\" 不是 ST_ShapeType 的值，寫出後檔案需要修復（請改設一個實際的幾何形狀）"
        case .graphicFrameWithoutTable:
            return "沒有表格內容；pptx-swift 只能寫出表格類的 graphicFrame，寫出時它會整個消失"
        }
    }

    public var description: String {
        let slide = "投影片 \(slideIndex + 1)"
        guard element != nil else { return "\(slide) \(reasonDescription)，拒絕存檔" }
        return "\(slide) 的\(elementDescription)：\(reasonDescription)，拒絕存檔"
    }

    /// 以 ASCII 結尾的標籤（`p:style`、`原樣 XML`）後面接中文前補一個空格。
    private func spaced(_ label: String) -> String {
        label.last?.isASCII == true ? label + " " : label
    }

    private var storesContentInAnotherPart: Bool {
        if case .embeddedObject(let kind)? = element { return kind.storesContentInAnotherPart }
        return false
    }
}

public extension Presentation {
    /// 目前狀態下會讓 `PptxWriter.write` 拒絕存檔的全部原因，依投影片、文件順序
    /// 排列（空陣列表示可以存檔）。`PptxWriter.write` 遇到第一個就丟出
    /// `PPTXError.writeError(blocker.description)`；呼叫端（例如 che-pptx-mcp 的
    /// `open_presentation`）可以在開檔時就列出來，不必等到存檔才發現。
    ///
    /// 例外：`unsupportedMedia` 依讀檔時設定的 `Slide.containsUnsupportedMedia`
    /// 旗標判斷，刪掉媒體元素不會解除它（見 `WriteBlocker.Reason.unsupportedMedia`）。
    var writeBlockers: [WriteBlocker] {
        slides.enumerated().flatMap { index, slide in
            (slide.containsUnsupportedMedia
                ? [WriteBlocker(slideIndex: index, element: nil, elementId: nil, elementName: nil, reason: .unsupportedMedia)]
                : [])
            + slide.elements.flatMap { WriteBlockerScan.blockers(in: $0, slideIndex: index, enclosingGroupIds: []) }
        }
    }
}

/// 一段會被原樣（或以原樣為底合併）寫進投影片的 XML，以及它在元素上的位置。
struct PassthroughFragment {
    let part: WriteBlocker.PassthroughPart
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
        if case .raw(let xml)? = fill { fragments.append(PassthroughFragment(part: .fill, xml: xml)) }
        if let effectXML { fragments.append(PassthroughFragment(part: .effects, xml: effectXML)) }
        if let scene3dXML { fragments.append(PassthroughFragment(part: .scene3d, xml: scene3dXML)) }
        if let extLstXML { fragments.append(PassthroughFragment(part: .extensionList, xml: extLstXML)) }
        return fragments
    }
}

private func spPrPassthroughFragments(
    geometry: GeometryDefinition, fill: ShapeFill?, outline: ShapeOutline?,
    effectXML: String?, scene3dXML: String?, sp3dXML: String?, extLstXML: String?, styleXML: String?
) -> [PassthroughFragment] {
    var fragments: [PassthroughFragment] = []
    if case .custom(let xml) = geometry { fragments.append(PassthroughFragment(part: .geometry, xml: xml)) }
    if case .raw(let xml)? = fill { fragments.append(PassthroughFragment(part: .fill, xml: xml)) }
    // 外框被 typed 欄位改動過時，寫出的是以原始 XML 為底的合併結果：只改寫
    // w／線條填色／headEnd／tailEnd（這幾樣本身不會帶 relationship），其餘原封
    // 不動——所以檢查原始 XML 就涵蓋了實際寫出的內容。
    if let xml = outline?.source?.xml { fragments.append(PassthroughFragment(part: .outline, xml: xml)) }
    if let effectXML { fragments.append(PassthroughFragment(part: .effects, xml: effectXML)) }
    if let scene3dXML { fragments.append(PassthroughFragment(part: .scene3d, xml: scene3dXML)) }
    if let sp3dXML { fragments.append(PassthroughFragment(part: .shape3d, xml: sp3dXML)) }
    if let extLstXML { fragments.append(PassthroughFragment(part: .extensionList, xml: extLstXML)) }
    if let styleXML { fragments.append(PassthroughFragment(part: .style, xml: styleXML)) }
    return fragments
}

enum WriteBlockerScan {
    /// relationships 命名空間：Transitional 與 Strict 兩種寫法。判斷一律看屬性
    /// 的命名空間 URI，不看前綴字串（前綴可以是任意名字）。
    static let relationshipNamespaces: Set<String> = [
        "http://schemas.openxmlformats.org/officeDocument/2006/relationships",
        "http://purl.oclc.org/ooxml/officeDocument/relationships",
    ]

    static func blockers(in element: SlideElement, slideIndex: Int, enclosingGroupIds: [Int]) -> [WriteBlocker] {
        func make(_ kind: WriteBlocker.Element, _ id: Int?, _ name: String?, _ reason: WriteBlocker.Reason) -> WriteBlocker {
            WriteBlocker(slideIndex: slideIndex, element: kind, elementId: id, elementName: name,
                         enclosingGroupIds: enclosingGroupIds, reason: reason)
        }
        func scan(_ kind: WriteBlocker.Element, _ id: Int, _ name: String, _ geometry: GeometryDefinition?,
                  _ fragments: [PassthroughFragment]) -> [WriteBlocker] {
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
            return scan(.shape, shape.id, shape.name, shape.geometryDefinition, shape.passthroughFragments)
        case .connector(let connector):
            return scan(.connector, connector.id, connector.name, connector.geometryDefinition, connector.passthroughFragments)
        case .group(let group):
            return scan(.group, group.id, group.name, nil, group.passthroughFragments)
                + group.elements.flatMap {
                    blockers(in: $0, slideIndex: slideIndex, enclosingGroupIds: enclosingGroupIds + [group.id])
                }
        case .raw(let raw):
            let kind: WriteBlocker.Element = raw.embeddedObjectKind.map { .embeddedObject($0) }
                ?? .unmodeled(localName: raw.localName)
            let fragment = PassthroughFragment(part: .wholeElement, xml: raw.xml)
            let name = firstElementName(in: raw.xml)
            if raw.referencesRelationship {
                let attributes = (try? inspect(fragment)).flatMap { $0.isEmpty ? nil : $0 } ?? ["r:*"]
                return [make(kind, raw.elementIds.first, name, .relationshipReference(part: .wholeElement, attributes: attributes))]
            }
            return reason(for: fragment).map { [make(kind, raw.elementIds.first, name, $0)] } ?? []
        case .graphicFrame(let frame):
            return frame.table == nil ? [make(.graphicFrame, frame.id, frame.name, .graphicFrameWithoutTable)] : []
        case .picture:
            // Picture 的 a:blip 由 writer 自己配置 relationship；spPr 沒有原樣片段（#14）。
            return []
        }
    }

    static func isWritablePreset(_ prst: String) -> Bool {
        !prst.isEmpty && prst != ShapeGeometry.unknown.rawValue && prst != ShapeGeometry.custom.rawValue
    }

    private static func reason(for fragment: PassthroughFragment) -> WriteBlocker.Reason? {
        do {
            let attributes = try inspect(fragment)
            return attributes.isEmpty ? nil : .relationshipReference(part: fragment.part, attributes: attributes)
        } catch let problem as FragmentProblem {
            return .malformedPassthroughXML(part: fragment.part, detail: problem.detail)
        } catch {
            return .malformedPassthroughXML(part: fragment.part, detail: FragmentProblem.unparsable.detail)
        }
    }

    enum FragmentProblem: Error, Equatable {
        case unparsable
        case rootCount(Int)
        case textOutsideRoot
        case unexpectedRoot(found: String, allowed: [String])
        case unexpectedNamespace(found: String, uri: String?)

        var detail: String {
            switch self {
            case .unparsable: return "無法解析"
            case .rootCount(let count): return "不是恰好一個根元素（有 \(count) 個）"
            case .textOutsideRoot: return "在根元素之外還有文字"
            case .unexpectedRoot(let found, let allowed):
                return "的根元素 <\(found)> 不能放在這個位置（應為 \(allowed.map { "<\($0)>" }.joined(separator: "／"))）"
            case .unexpectedNamespace(let found, let uri):
                return "的根元素 <\(found)> 的命名空間不對（是 \(uri ?? "無命名空間")）"
            }
        }
    }

    /// 核對一段原樣片段寫出後是否合法，回傳其中每一個 relationships 命名空間屬性
    /// 的名稱（依文件順序）。片段放在與寫出的投影片根節點相同的命名空間環境裡解析
    /// （`a`／`r`／`p` 已綁定）——`PptxReader` 讀到的片段都是 self-contained，
    /// 但呼叫端手動指定的片段可以依賴投影片根節點的宣告，寫出後同樣合法；未綁定
    /// 的其他前綴則視為無法解析。
    ///
    /// 片段必須恰好是一個元素（前後只能有空白），而且根元素要合乎它所在的位置
    /// （`PassthroughPart.allowedRootNames`）：`ShapeFill.raw` 是 `EG_FillProperties`
    /// 的一個選項，兩個根元素或 `<a:ln>` 放進填色位置都會寫出不合 schema 的投影片
    /// （#12 審查 R2 L-2）。在存檔時檢查而不是在建構時拒絕：`ShapeFill.raw` 等是
    /// enum 的 associated value，建構時沒有地方丟錯，而 `writeBlockers` 本來就是
    /// 「事先列出、存檔時拒絕」的單一機制。
    static func inspect(_ fragment: PassthroughFragment) throws -> [String] {
        let wrapped = "<pptx-swift-fragment"
            + " xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\""
            + " xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\""
            + " xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\">"
            + fragment.xml + "</pptx-swift-fragment>"
        let document: XMLDocument
        do {
            document = try XMLDocument(xmlString: wrapped, options: [])
        } catch {
            throw FragmentProblem.unparsable
        }
        return try withExtendedLifetime(document) {
            guard let wrapper = document.rootElement() else { throw FragmentProblem.unparsable }
            let children = wrapper.children ?? []
            let roots = children.compactMap { $0 as? XMLElement }
            guard roots.count == 1, let root = roots.first else { throw FragmentProblem.rootCount(roots.count) }
            let strayText = children.contains { node in
                node.kind == .text && !(node.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            guard !strayText else { throw FragmentProblem.textOutsideRoot }
            if let allowed = fragment.part.allowedRootNames, !allowed.contains(root.localName ?? "") {
                throw FragmentProblem.unexpectedRoot(found: root.name ?? root.localName ?? "?", allowed: allowed.sorted())
            }
            if let namespaces = fragment.part.allowedRootNamespaces, !namespaces.contains(root.uri ?? "") {
                throw FragmentProblem.unexpectedNamespace(found: root.name ?? root.localName ?? "?", uri: root.uri)
            }
            // 同一個屬性名稱只列一次（R3 M-1'：一個表格的 16 個 r:embed 不必逐一列出）。
            var seen = Set<String>()
            return try document.nodes(forXPath: "//@*")
                .filter { relationshipNamespaces.contains($0.uri ?? "") }
                .map { $0.name ?? $0.localName ?? "?" }
                .filter { seen.insert($0).inserted }
        }
    }

    /// 未建模元素子樹裡第一個 `cNvPr/@name`（給人看的名稱；找不到或無法解析時為 nil）。
    private static func firstElementName(in xml: String) -> String? {
        guard let document = try? XMLDocument(xmlString: xml, options: []) else { return nil }
        return withExtendedLifetime(document) {
            (try? document.nodes(forXPath: "//*[local-name()='cNvPr']/@name"))?.first?.stringValue
        }
    }
}
