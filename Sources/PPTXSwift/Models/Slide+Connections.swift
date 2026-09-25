import Foundation

/// 連接線（`p:cxnSp`）的 `a:stCxn`／`a:endCxn` 綁定的是形狀的 `cNvPr/@id`，不是
/// 形狀本身：形狀被刪掉之後，綁定仍然指著那個 id。如果之後又有新元素拿到同一個
/// id，連接線就會靜默改黏到不相干的新元素上（#12 審查 L4：連接線從 #9 起能存活
/// 往返之後才出現的後果）。這兩個 API 讓配號與刪除都能顧及這件事。
///
/// 只涵蓋 typed 的 `.connector`（含群組內）；`.raw` 元素（例如包在
/// `mc:AlternateContent` 裡的連接線）的內容不透明，不讀也不改。
public extension Slide {
    /// 投影片上（含群組內）所有連接線的 `stCxn`／`endCxn` 目前指向的形狀 id。
    /// 配置新元素 id 時要一併避開：這些 id 就算已經沒有元素使用，也仍被連接線
    /// 引用著。
    var connectionTargetIds: Set<Int> {
        Set(elements.flatMap(Self.connectionTargetIds(in:)))
    }

    /// 把所有指向 `ids` 的連接線綁定（`stCxn`／`endCxn`）解除，連接線本身與它的
    /// 幾何不變——與 PowerPoint 刪除被連接的形狀時的行為相同。回傳解除的綁定數。
    @discardableResult
    mutating func detachConnections(from ids: Set<Int>) -> Int {
        var detached = 0
        elements = elements.map { Self.detaching(ids, in: $0, count: &detached) }
        return detached
    }

    private static func connectionTargetIds(in element: SlideElement) -> [Int] {
        switch element {
        case .connector(let connector):
            return [connector.startConnection?.shapeId, connector.endConnection?.shapeId].compactMap { $0 }
        case .group(let group):
            return group.elements.flatMap(connectionTargetIds(in:))
        case .shape, .picture, .graphicFrame, .raw:
            return []
        }
    }

    private static func detaching(_ ids: Set<Int>, in element: SlideElement, count: inout Int) -> SlideElement {
        switch element {
        case .connector(var connector):
            if let start = connector.startConnection, ids.contains(start.shapeId) {
                connector.startConnection = nil
                count += 1
            }
            if let end = connector.endConnection, ids.contains(end.shapeId) {
                connector.endConnection = nil
                count += 1
            }
            return .connector(connector)
        case .group(var group):
            group.elements = group.elements.map { detaching(ids, in: $0, count: &count) }
            return .group(group)
        case .shape, .picture, .graphicFrame, .raw:
            return element
        }
    }
}
