import Testing
import Foundation
@testable import PPTXSwift

/// `Slide.connectionTargetIds`／`Slide.detachConnections(from:)`（#12 審查 L4）。
struct ConnectionBindingTests {
    static func slide() -> Slide {
        Slide(elements: [
            .shape(Shape(id: 2, name: "a")),
            .shape(Shape(id: 3, name: "b")),
            .connector(Connector(id: 4, name: "c1",
                                 startConnection: ConnectionSite(shapeId: 2, index: 1),
                                 endConnection: ConnectionSite(shapeId: 3, index: 3))),
            .group(GroupShape(id: 10, name: "g", elements: [
                .connector(Connector(id: 11, name: "c2", endConnection: ConnectionSite(shapeId: 3, index: 0))),
            ])),
        ])
    }

    @Test func `connectionTargetIds sees top level and grouped connectors`() {
        #expect(Self.slide().connectionTargetIds == [2, 3])
    }

    @Test func `detachConnections unbinds every end pointing at the ids and nothing else`() throws {
        var slide = Self.slide()
        #expect(slide.detachConnections(from: [3]) == 2)
        guard case .connector(let c1) = slide.elements[2],
              case .group(let group) = slide.elements[3], case .connector(let c2) = group.elements[0] else {
            Issue.record("unexpected structure")
            return
        }
        #expect(c1.startConnection == ConnectionSite(shapeId: 2, index: 1), "the other end stays glued")
        #expect(c1.endConnection == nil)
        #expect(c2.endConnection == nil)
        #expect(slide.connectionTargetIds == [2])
    }
}
