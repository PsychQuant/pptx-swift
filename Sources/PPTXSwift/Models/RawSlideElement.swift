import Foundation

/// A child of a shape tree (`p:spTree` or `p:grpSp`) pptx-swift does not
/// model as a typed structure — `mc:AlternateContent`, `p:contentPart`, or
/// any future element kind the reader does not recognize. Its exact original
/// XML is kept verbatim so a round trip never silently drops it
/// (PsychQuant/pptx-swift#9: before this, an element the reader's `switch`
/// did not name fell to `default: break` and vanished with no error).
public struct RawSlideElement: Equatable {
    /// The element's local name (`"AlternateContent"`, `"contentPart"`, …),
    /// kept for diagnostics only — every unmodeled kind is treated
    /// identically by the reader and writer.
    public var localName: String
    /// The element's exact original XML, self-contained: every namespace
    /// binding this subtree inherited (not locally re-declared on its own
    /// root) is re-declared as an `xmlns:`／`xmlns` attribute on this
    /// string's own root element, so it stays well-formed when spliced
    /// verbatim into the output slide XML — regardless of what that slide's
    /// own root happens to declare. `XMLElement.xmlString` on a node
    /// detached from its parsed document does *not* re-declare namespaces
    /// the node only inherited from an ancestor (verified empirically; not
    /// documented behavior), so a plain `element.xmlString` here would
    /// silently produce a fragment with unbound prefixes such as `mc:` the
    /// moment it left the document that happened to declare them. See
    /// `PptxReader.selfContainedXMLString(for:)` for the exact mechanism —
    /// every inherited binding is declared unconditionally, not only ones a
    /// lexical scan judges "used", because OOXML can name a namespace
    /// dependency in places a scan cannot see (e.g. `mc:Choice`'s `Requires`
    /// attribute *value* is a list of prefixes, not an element／attribute
    /// name).
    public var xml: String
    /// Every `cNvPr/@id` found anywhere inside this element's subtree
    /// (an `mc:AlternateContent` can bundle more than one — a `Choice` and
    /// a `Fallback` branch each declaring their own). Lets id allocation
    /// elsewhere on the slide avoid colliding with an id this element
    /// carries but pptx-swift cannot otherwise see (PsychQuant/pptx-swift#6's
    /// lesson: a consumer that switches on `SlideElement` without knowing
    /// about `.raw` would allocate straight through these ids).
    public var elementIds: [Int]
    /// Whether any attribute anywhere inside this element's subtree belongs
    /// to the relationships namespace (`r:id`, `r:embed`, `r:link`, …) —
    /// most commonly `p:contentPart`'s `r:id` (it names nothing else) or an
    /// image inside an `mc:AlternateContent` branch. `PptxWriter` refuses to
    /// write a slide containing such an element rather than risk a dangling
    /// reference or an id collision with a relationship it allocates fresh
    /// for pictures on the same slide — see the decision note on
    /// `PptxWriter.validateSupportedContent`. `PptxReader` always computes
    /// this correctly from `xml`'s actual content; a `RawSlideElement` built
    /// by hand (not via `PptxReader`) is trusted as-is — `PptxWriter` checks
    /// this flag, not `xml` itself, so a hand-built value that understates it
    /// (`false` while `xml` really does reference a relationship) can still
    /// produce an unsafe file.
    public var referencesRelationship: Bool

    public init(localName: String, xml: String, elementIds: [Int] = [], referencesRelationship: Bool = false) {
        self.localName = localName
        self.xml = xml
        self.elementIds = elementIds
        self.referencesRelationship = referencesRelationship
    }
}
