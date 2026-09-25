# Changelog

All notable changes to pptx-swift will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### ⚠️ Source-breaking and behavior changes

- `SlideElement` gains two cases, `.connector` and `.raw` (#9): an exhaustive `switch` over `SlideElement` no longer compiles until it handles them.
- `ShapeFill` gains `.raw(String)` (#12): an exhaustive `switch` over `ShapeFill` no longer compiles until it handles it. `PptxReader` now produces a typed fill **only** when it reproduces the source XML completely — `<a:noFill/>`, or a `<a:solidFill>` holding exactly one `srgbClr`/`schemeClr` with only a `val` and no child (no `lumMod`/`lumOff`/`alpha`/`tint`/`shade`/… color transform). Everything else is `.raw`: `gradFill`/`blipFill`/`pattFill`/`grpFill`, and a solid fill in `sysClr`/`prstClr`/`hslClr`/`scrgbClr` or with a color transform. A shape whose fill was read as `.schemeColor(name:)` before because the transforms were ignored now reads as `.raw`.
- `Shape.geometry` (and the new `Connector.geometry`) is now a computed view of the new stored `geometryDefinition: GeometryDefinition` (#12). Reading and assigning it compiles unchanged. Assigning a value different from the current view replaces the geometry with that preset and clears the adjustments; assigning the current view back changes nothing (a custom path and adjustments are kept). A preset whose `prst` is not in `ShapeGeometry` reads as `.unknown` and a custom path as `.custom`; assigning either sentinel to a preset makes `PptxWriter.write` refuse to save.
- `ShapeOutline.color` reads only the line's own `<a:solidFill><a:srgbClr val>`; before it took the first `srgbClr` anywhere under `<a:ln>` (for example a gradient stop).
- `PptxWriter.write` refuses more presentations (`PPTXError.writeError`, nothing written), each listed up front by `Presentation.writeBlockers` (below). A presentation that saved before by silently dropping or corrupting content now fails to save instead: a raw `spPr`/`grpSpPr`/`p:style` fragment that references a relationship, such as a picture-filled shape (#12 review C1); a chart, SmartArt diagram or OLE object (#15); a raw fragment that does not parse; a sentinel preset geometry. Two of this repo's fixtures, `header.pptx` and `comment.pptx`, each hold three embedded OLE objects and can no longer be saved as a whole.
- `PptxWriter` now writes `Shape.outline` (#12 review H1). It was read but never written before, so a shape built in code with an outline gains an `<a:ln>` in its output.

### Added

- `Connector` models `p:cxnSp` (a connector/arrow) — `id`, `name`, `geometryDefinition`/`geometry` (with the read-only `adjustments`, the `a:avLst`/`a:gd` routing adjustments of a bent/curved connector; `init` still takes `adjustments:`), `position`, `size`, `rotation`/`flipHorizontal`/`flipVertical` (via the same `a:xfrm` handling `Shape`/`Picture` use), `fill`, `outline` (line color/width, `headEnd`/`tailEnd` arrow styles), `startConnection`/`endConnection` (`a:stCxn`/`a:endCxn`, the shapes and connection-site indices the connector is wired to), `styleXML`, `effectXML`/`scene3dXML`/`sp3dXML`/`extLstXML` and `blackWhiteMode` (#9, #11, #12). `SlideElement` gains a `.connector` case. `ShapeGeometry` gains the 9 bent/curved connector presets (`straightConnector1`, `bentConnector2-5`, `curvedConnector2-5`); `ShapeOutline` gains `headEnd`/`tailEnd: LineEndStyle?`.
- `RawSlideElement` models any `p:spTree`/`p:grpSp` child `PptxReader` does not recognize as a typed structure (`mc:AlternateContent`, `p:contentPart`, a `p:graphicFrame` that is not a table, or any future kind) — `localName`, a self-contained `xml` string (every namespace binding the fragment inherited, including the unprefixed default namespace, is re-declared on its own root so it stays well-formed wherever it is spliced), every `cNvPr/@id` found in its subtree, and whether it references a relationship. `SlideElement` gains a `.raw` case. `SlideElement.allElementIds` / `Slide.allElementIds` return every id on a slide including ones inside `.raw` elements, for id-collision-avoiding allocators that could not otherwise see them (#9, #6's lesson).
- `PPTXError.rawElementGeometryUnsupported(shapeId:)`: thrown by `Slide.setGeometry(ofElementId:...)` when the id names (or lives inside) a `.raw` element, which has no typed geometry to set.
- `Shape.styleXML` / `Connector.styleXML`: the exact original `p:style` (`CT_ShapeStyle`) XML, self-contained (same mechanism as `RawSlideElement.xml`) — a theme style reference (`lnRef`/`fillRef`/`effectRef`/`fontRef`, each an `<a:schemeClr>` plus a style-matrix index) many PowerPoint-authored shapes and connectors rely on *instead of* an explicit `<a:ln>`/fill for their actual rendered color (#11). Kept verbatim rather than parsed into typed fields — resolving a `schemeClr` to an actual color needs the theme part. `nil` when there is no `p:style`; `PptxWriter` writes it back at `CT_Shape`'s/`CT_Connector`'s schema position (after `spPr`, before `txBody` for `Shape`; as the last child for `Connector`) and omits the tag entirely when `nil`. Explicit values in `spPr` override `p:style`, so this only restores a shape's appearance together with the `spPr` fidelity below.
- `GeometryDefinition` (#12): the whole `EG_Geometry` choice as one value — `.preset(String, adjustments: [GeometryAdjustment])` keeps a `<a:prstGeom>`'s `prst` string as-is (including values `ShapeGeometry` does not list, such as `chevron`) and its `a:avLst` guides; `.custom(String)` is a `<a:custGeom>` (free-form path) kept as self-contained XML. `Shape.geometryDefinition` / `Connector.geometryDefinition` store it; `Shape.adjustments` / `Connector.adjustments` are read-only views of the preset's guides, and `Shape.init` takes `adjustments:`.
- `Shape`/`Connector` gain `effectXML` (`<a:effectLst>`/`<a:effectDag>`), `scene3dXML`, `sp3dXML`, `extLstXML`; `GroupShape` gains `fill: ShapeFill?`, `effectXML`, `scene3dXML`, `extLstXML` — the `CT_ShapeProperties`/`CT_GroupShapeProperties` children with no typed model, kept as raw, self-contained XML and written back at their schema position (#12). `Picture` is out of scope (PsychQuant/pptx-swift#14).
- `Shape.blackWhiteMode` / `Connector.blackWhiteMode` / `GroupShape.blackWhiteMode`: the `bwMode` attribute of `p:spPr`/`p:grpSpPr` (`ST_BlackWhiteMode`), round-tripped as a string.
- `ShapeOutline.sourceXML`: the original `<a:ln>` an outline was read from (`nil` for an outline built in code). See *Fixed* for how the writer uses it.
- `WriteBlocker` and `Presentation.writeBlockers`: every reason `PptxWriter.write` would refuse to save the presentation **in its current state** — slide index, element kind/id/name, and a closed set of reasons (`unsupportedMedia`, `relationshipReference(location:attributes:)`, `malformedPassthroughXML(location:)`, `invalidPresetGeometry(prst:)`). `PptxWriter.write` throws the first one's `description`; a caller can list them all when a file is opened. Replacing the offending content (for example assigning a typed fill over a picture fill, or deleting a chart) clears the blocker.
- `Slide.connectionTargetIds` and `Slide.detachConnections(from:)`: the shape ids that typed connectors (including those inside groups) are glued to, and a way to release the bindings to a set of ids. A connector binds to an id, not to a shape, so a consumer that deletes a shape and later gives a new element the same id would silently re-glue the connector to it.

### Changed

- `GroupShape.containsElement(id:)` now checks `SlideElement.allElementIds` (covers every id in a `.raw` element's subtree, not just its first) instead of a single `elementId` per element.
- Only a `p:graphicFrame` holding a table (`a:graphic/a:graphicData/a:tbl`) is read as a typed `.graphicFrame`; any other graphicFrame (chart, SmartArt, OLE object, …) is read as `.raw` (#15). `Slide.setGeometry(ofElementId:...)` on one of those now throws `rawElementGeometryUnsupported`.
- `PptxWriter` checks every slide it writes as a last line of defense: an `r:` attribute anywhere other than a picture's own `p:pic/p:blipFill/a:blip` (under `p:spTree`/`p:grpSp` only — the one place the writer allocates relationships) makes the write fail, so a stale relationship Id can never reach the output even if a future passthrough field were missing from `writeBlockers`.

### Fixed

- `PptxReader` recognizes `p:cxnSp` (connectors) instead of silently dropping them — before, any connector vanished the moment `PptxWriter` rewrote the slide, with no error (#9). `PptxWriter` writes them back via `serializeConnector`.
- `PptxReader`/`PptxWriter` no longer silently drop `mc:AlternateContent`, `p:contentPart`, or any other unrecognized `p:spTree`/`p:grpSp` child — they round-trip as self-contained raw XML via `RawSlideElement` (#9). A `.raw` element that references a relationship (most commonly `p:contentPart`'s `r:id`) makes `PptxWriter.write` refuse: each slide's `.rels` is rebuilt from scratch, with no safe way to know whether the original `rId` is still valid or collides with a freshly-allocated one. Since this release the check also parses the element's `xml`, so a hand-built value that understates `referencesRelationship` is refused too.
- `PptxWriter` writes a table cell's text body as `<a:txBody>` (DrawingML), not `<p:txBody>` (PresentationML) — `CT_TableCell` (`a:tc`) requires the former per ECMA-376 (#10). The wrong namespace made LibreOffice's stricter importer stop rendering everything in the shape tree from the mistagged table onward.
- A shape or connector whose only color comes from `p:style` (no explicit `<a:ln>`/fill in `spPr`) no longer loses that color on a round trip (#11), via `Shape.styleXML`/`Connector.styleXML` above.
- A shape drawn with a custom/free-form outline (`<a:custGeom>`) no longer silently turns into a plain rectangle on a round trip (#12), via `GeometryDefinition.custom`.
- The explicit `spPr` values that override `p:style` survive a round trip (#12 review H1). `<a:ln>` is written for `Shape` (it never was) and kept for `Shape` and `Connector` as its original XML: untouched, it is written back verbatim — dash pattern, join style, `cap`/`cmpd`/`algn`, theme color, color transforms, `noFill`, line gradient and all (the #13 losses); after a typed edit, only the edited parts (`w`, the line fill, `headEnd`, `tailEnd`) are rewritten inside the original. Before, an explicit "no outline" (`<a:ln><a:noFill/>`) next to PowerPoint's default `lnRef idx="2"` came back with the theme's outline, a red 6 pt outline became a thin theme outline, and a `schemeClr tx1` 3 pt connector became a thin accent line. A `sysClr`/`prstClr`/`hslClr`/`scrgbClr` solid fill, which vanished entirely (letting `p:style`'s fill show through — a white `sysClr window` fill rendered accent blue), and a color transform on a `schemeClr`/`srgbClr` fill, which was silently dropped, now round-trip verbatim as `.raw`.
- Assigning a typed value now always takes effect (#12 review H2). Typed and raw were two separate fields with raw written first, so `shape.fill = .solid(...)` on a gradient- or picture-filled shape read from a file — che-pptx-mcp's `set_shape_fill` — reported success and changed nothing; `shape.geometry = ...` on a custom-path shape likewise. They are now one value each (`ShapeFill`, `GeometryDefinition`), so the "both set" state cannot exist.
- A picture-filled shape no longer comes back showing a different picture or a dangling `rId` (#12 review C1). Its `<a:blipFill r:embed>` was written verbatim while the slide's relationships were renumbered, so the Id either named nothing or named whatever the writer had just allocated for a picture on the same slide; `PptxWriter.write` now refuses (see `writeBlockers`) until the fill is replaced. The same holds for relationship references in any other passthrough fragment (`effectLst`/`effectDag` blends, `extLst` hidden fills, `grpSpPr` fills, `p:style`), judged by the attribute's namespace, not its prefix.
- A preset outside `ShapeGeometry` (such as `chevron`) keeps its `prst` instead of being written as the invalid `prst="unknown"` (the shape disappeared in LibreOffice and PowerPoint asks to repair the file), and a `Shape`'s `a:avLst` adjustments survive (a `roundRect` with `adj=50000` was written as a small-radius rounded rectangle) (#12 review M1).
- A connector's own `spPr` fill (`solidFill`/`noFill`) and the `bwMode` attribute of `spPr`/`grpSpPr` survive a round trip (#12 review L1, L2).
- A chart, SmartArt diagram or OLE object (a non-table `p:graphicFrame`) is no longer silently deleted on save (#15): it was read as a typed graphicFrame with no table, which the writer skipped. It is now read as `.raw`, and because it references its part through a relationship, `PptxWriter.write` refuses and names it instead of dropping it.
- `ShapeFill.gradient(stops:)` is written as `<a:gradFill><a:gsLst>…</a:gsLst></a:gradFill>`; it was silently skipped before. Fewer than two stops throws `PPTXError.writeError` (`a:gsLst` requires two).

### Known limitations

- **Refusing, not renumbering.** Content whose passthrough XML references a relationship (a picture fill, a chart/SmartArt/OLE graphicFrame, ink, an image inside `mc:AlternateContent`, …) makes the whole presentation unsavable until that content is replaced or removed. Reallocating those relationships and rewriting the Ids inside the raw XML is PsychQuant/pptx-swift#16.
- **Pictures' own `spPr`** (PsychQuant/pptx-swift#14): a `p:pic`'s geometry, fill, outline, effects, 3-D and `bwMode` are still not modeled — `PptxWriter` always writes `<a:prstGeom prst="rect">` for a picture, so a picture cropped to a circle or with a border loses it.
- **Tables** (PsychQuant/pptx-swift#17): merged cells (`gridSpan`/`rowSpan`/`hMerge`/`vMerge`), `a:tcPr` (cell fill, borders, margins) and `a:tblPr` (`tableStyleId`, `firstRow`, `bandRow`, …) are lost on a round trip. More generally, every text body's `a:bodyPr` attributes (anchor, insets, autofit) are not kept, in shapes as well as tables.
- **`<a:ln>` after a typed edit** (the rest of PsychQuant/pptx-swift#13): setting `ShapeOutline.color` replaces the whole line fill with a plain solid `srgbClr` (a gradient, a theme color or a color transform on the line is gone — that is what setting a color means), and setting it to `nil` removes the line fill so `p:style`'s `lnRef` applies. The typed view cannot *read* a theme-colored or gradient line's color (`color == nil`). An outline built in code, with no `sourceXML`, can only express `w`, an `srgbClr` color and the two line ends.
- **Theme formatting**: `PptxWriter` writes its own theme, master and layout rather than the source's, so a `p:style` `effectRef` that points at the source theme's effect styles (a shadow, for example) renders with the written theme's instead. Observed in LibreOffice renders of the #12 review's probe (the shadows on `cropped.pptx`'s rectangles are gone before and after this release alike).
- `Slide.detachConnections(from:)`/`connectionTargetIds` see typed connectors only; a connector inside a `.raw` element (for example in an `mc:AlternateContent` branch) is opaque to them.

## [0.5.0] - 2026-09-24

### Added

- `Shape`, `Picture`, `GraphicFrame` and `GroupShape` model `a:xfrm` (`GraphicFrame`'s is `p:xfrm`, same `a:CT_Transform2D` type) `rot` / `flipH` / `flipV` as `rotation: Int` (`ST_Angle`, 60,000ths of a degree, read as-is with no range restriction), `flipHorizontal: Bool`, `flipVertical: Bool` (#7). `init` parameters default to `0` / `false` / `false`, so existing calls compile unchanged. `PptxReader` reads all three from the element's own attributes (not its `off`/`ext` children); `PptxWriter` writes them back, omitting the attribute entirely when it equals the schema default, so an unrotated, unflipped element's `<a:xfrm>`/`<p:xfrm>` opening tag stays byte-identical to before this change. `PptxWriter` normalizes `rotation` into the canonical `[0, 21_600_000)` range (one full turn) via Euclidean modulo before writing — `ST_Angle` is an unrestricted `xsd:int`, so a value outside that range is schema-valid but names the same angle as its residue inside it; `PptxReader` never normalizes on the way in.
- `GraphicFrame.rotation` / `flipHorizontal` / `flipVertical` document a real-world caveat (MS-OI29500 §20.1.7.6): the standard permits these attributes on a `graphicFrame`'s `p:xfrm` and pptx-swift round-trips them correctly, but real Microsoft PowerPoint ignores them when rendering a table/chart/SmartArt, while LibreOffice applies them (verified with headless `--convert-to pdf`).

## [0.4.0] - 2026-09-24

### Fixed

- `PptxWriter` writes group shapes (#5). A `p:grpSp` used to serialize as nothing, so saving a presentation that contained a group silently dropped the group and every shape, picture and text box inside it. Groups now round-trip with nesting at any depth and their transform (`a:off` / `a:ext` / `a:chOff` / `a:chExt`). Pictures inside a group get image relationships from the same per-slide allocation as top-level pictures (one relationship per distinct media part; no duplicate or dangling `rId`).

### Added

- `GroupShape.childOffset` / `childExtent` (`a:chOff` / `a:chExt`). The `init` parameters default to `nil`, meaning equal to `position` / `size` (no scaling), so existing calls compile unchanged.
- `Picture.externalImageTarget` for a linked picture (`<a:blip r:link>`), read only when the relationship is `TargetMode="External"`. `r:embed` and `r:link` are independent optional attributes of `CT_Blip` and may both be present (PowerPoint's "Insert and Link" keeps an embedded cache plus the link); the writer writes both.
- `Slide.containsUnsupportedMedia`: the slide contains any DrawingML `EG_Media` element (`audioFile`, `videoFile`, `wavAudioFile`, `audioCd`, `quickTimeFile`) or a transition sound (`p:snd`). Namespaces are checked, not only local names.

### Changed

- **`PptxWriter.write` now throws `PPTXError.writeError` for a presentation with audio, video or a transition sound on any slide**, before creating any file. pptx-swift does not model playback (`p:timing`, `p14:media`), so such a slide used to be saved with its playback silently lost; it is now refused instead. A presentation that saved before may therefore fail to save now.

## [0.3.0] - 2026-09-24

### Added

- `PictureSourceRect` models a picture's crop, its `blipFill` `<a:srcRect>` (#2): `left` / `top` / `right` / `bottom` in thousandths of a percent (`100_000` = 100 %; negative extends), with `visibleWidthFraction` / `visibleHeightFraction`. `Picture.sourceRect` holds it (`init` parameter defaults to `nil`). `PptxReader` reads both the integer form (`52941`) and the strict percent-string form (`52.941%`); `PptxWriter` writes it back between `a:blip` and `a:stretch`, so a crop now survives a round trip.
- `NativeAspect.visibleDimensions(pixelWidth:pixelHeight:crop:)` returns the size of the part a crop leaves visible. It throws `PPTXError.invalidParameter("pixelDimensions", …)` for a non-positive pixel size and `PPTXError.invalidParameter("srcRect", …)` when the crop leaves nothing visible or an edge does not fit `xsd:int`.
- `PictureSourceRect.isRepresentable`: every edge fits `xsd:int`. `PptxWriter` throws `PPTXError.writeError` for a picture whose crop is not representable (it could not be read back), leaving the destination untouched.
- `MediaFile.packageContentType` (`init` parameter defaults to `nil`): the content type the source package declared for the part, filled in by `PptxReader`.
- `NativeAspect.fittedSize(keeping:of:pixelWidth:pixelHeight:crop:)` takes an optional crop (default `nil`, so existing calls compile unchanged) and keeps the aspect of the visible part.

### Fixed

- `PptxWriter` links every picture it writes to its media part (#1). Each slide's `slideN.xml.rels` now carries one image relationship per distinct media part its pictures use (`rId1` stays the slide layout; images take `rId2` upward), and `r:embed` points at that relationship. Before this, `r:embed` kept the Id from the source package or the caller, and no image relationship was written at all, so every saved picture — inserted in memory or read from a file — pointed at a missing relationship and PowerPoint had to repair the file.
- Every `ppt/media/` part gets a content type (#1), chosen in this order: the format ImageIO identifies the bytes as; the type the source package declared for the part (new `MediaFile.packageContentType`, read from `[Content_Types].xml`); the extension table; `application/octet-stream`. A type that matches the extension table is registered as a `Default`, any other as a per-part `Override`, so a PNG stored as `photo.svg` stays `image/png` and an EMF the package typed by `Override` keeps `image/x-emf`. Before this, only `png` and `jpeg`/`jpg` were registered, so a package holding a `gif`, `wmf`, `pdf` or `mp3` part was invalid.
- Media file names are no longer used as paths (#1). A `MediaFile.fileName` that is not a safe part name (anything other than ASCII letters, digits, `.`, `_`, `-`; a leading or trailing `.`; an `xml`/`rels` extension) or that equals another one case-insensitively is written as `imageN.<ext>`. Before this, a name such as `../../x.png` was written outside `ppt/media/`. Names PowerPoint itself produces (`image1.png`, …) are kept.
- Only the first `MediaFile` per `fileName` is written, matching `Presentation.mediaFile(for:)`; before, a later duplicate silently replaced the bytes a picture resolved to.
- `NativeAspect.pixelDimensions(of:)` reports the image as displayed (#2): an EXIF orientation of 5–8 (a 90° or 270° turn) swaps width and height. A portrait photo stored as a landscape pixel grid used to be measured, and fitted, as landscape.
- `NativeAspect.fittedSize` no longer fits a cropped picture to the whole image's aspect when given the picture's crop (#2).

### Changed

- A picture whose `mediaFileName` names a file not in `Presentation.images` now makes `PptxWriter.write` throw `PPTXError.writeError` (nothing is written to the destination) instead of saving an `r:embed` that points at nothing (#1).
- A picture with `mediaFileName == nil` is written as `<a:blip/>` with no `r:embed` (#1). `Picture.imageRelationshipId` is no longer written; it is the Id from the source package and is not meaningful in the written one.
- `MediaFile.contentType` knows more extensions (`jpe`, `jfif`, `svg`, `wdp`, `pdf`, `mp3`, `m4a`, `wav`, `mp4`, `mov`); unknown extensions still return `application/octet-stream`.

## [0.2.0] - 2026-09-24

Metric geometry slice of PsychQuant/macdoc#90 (Spectra change `pptx-geometry-tools`).

### ⚠️ Source-breaking: new `PPTXError` cases

`PPTXError` gains two cases:

- `undecodableImage(String)` — ImageIO cannot read pixel dimensions (including EMF/WMF vector metafiles).
- `groupGeometryUnsupported(shapeId: Int)` — geometry was set on a group or on an element inside a group.

`PPTXError` is a non-frozen public enum, so any **exhaustive `switch` over it stops compiling**. Migration: add the two cases to the switch, or add a `default:` branch. Code that only uses `localizedDescription` / `errorDescription` or pattern-matches with `if case` is unaffected.

### Added

- `PPTXMetric` (`Geometry/MetricGeometry.swift`): `emu(fromCm:)` (throws) and `cm(fromEmu:)` (total). The ratio is exactly 360,000 EMU per cm, and cm → EMU rounds half away from zero. The supported range is the OOXML `ST_Coordinate` range: `minCoordinateEmu`, `maxCoordinateEmu` and `coordinateRangeEmu`. Values that are non-finite or out of range throw `PPTXError.invalidParameter` rather than trapping. Every EMU in range round-trips exactly.
- Centimeter accessors: `Position.xCm` / `yCm`, `Size.widthCm` / `heightCm`, `SlideSize.widthCm` / `heightCm`. The throwing initializers `Position(xCm:yCm:)` and `Size(widthCm:heightCm:)` validate their input the same way.
- `PPTXMetric.geometry(xCm:yCm:widthCm:heightCm:)` validates a cm rectangle, and requires width and height to be greater than 0.
- `MetricGeometryMutable` protocol with `setGeometry(xCm:yCm:widthCm:heightCm:) throws`. `Shape`, `Picture` and `GraphicFrame` conform to it.
- `Slide.locateElement(id:)` returns a `SlideElementLocation`. `Slide.setGeometry(ofElementId:xCm:yCm:widthCm:heightCm:)` rejects groups and group children with `groupGeometryUnsupported`.
- `NativeAspect.pixelDimensions(of:)` reads the pixel size from the image header through ImageIO. `NativeAspect.fittedSize(keeping:of:pixelWidth:pixelHeight:)` keeps the anchored side and derives the other from the image's aspect ratio. Both sides are validated against the coordinate range. `AspectAnchor` is `width` or `height`.
- `Picture.mediaFileName` is optional, and the `init` parameter defaults to `nil`. `Presentation.mediaFile(for:)` returns the media part a picture embeds.

### Fixed

- `PptxReader` resolves a picture's `r:embed` relationship by OPC rules. The target is resolved relative to the slide part. A leading `/` means the package root. Targets are percent-decoded, and `.` / `..` segments are normalised. External relationships are ignored. Only an existing regular file directly under `ppt/media/` is accepted.
- `PptxReader` no longer fails to open a package whose `ppt/media/` contains a subdirectory. Resolving a picture's media and reading `Presentation.images` share one check. A media part must be a regular file: it is tested with `lstat`, so symbolic links, FIFOs, sockets and devices are never followed or opened. Its real path must also lie directly inside the package's own `ppt/media`, and a `ppt` or `ppt/media` that is itself a symbolic link yields no media.

## [0.1.0] - 2026-04-22

### Added

- Initial release: PresentationML (`.pptx`) reader and writer — slides, shapes, pictures, tables, groups, notes, transitions, theme, slide masters and layouts.
