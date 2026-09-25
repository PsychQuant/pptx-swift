# Changelog

All notable changes to pptx-swift will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- `Connector` models `p:cxnSp` (a connector/arrow) — `id`, `name`, `geometry`, `position`, `size`, `rotation`/`flipHorizontal`/`flipVertical` (via the same `a:xfrm` handling `Shape`/`Picture` use), `outline` (line color/width, `headEnd`/`tailEnd` arrow styles), `startConnection`/`endConnection` (`a:stCxn`/`a:endCxn`, the shapes and connection-site indices the connector is wired to), and `adjustments` (`a:avLst`/`a:gd`, a bent/curved connector's routing adjustments). `SlideElement` gains a `.connector` case. `ShapeGeometry` gains the 9 bent/curved connector presets (`straightConnector1`, `bentConnector2-5`, `curvedConnector2-5`); `ShapeOutline` gains `headEnd`/`tailEnd: LineEndStyle?` (usable by any shape's `a:ln`, not just connectors — `parseShapeProperties` now reads them for `Shape`/`Picture` too, though `PptxWriter` does not yet write `Shape`'s outline at all, a pre-existing gap this does not change).
- `RawSlideElement` models any `p:spTree`/`p:grpSp` child `PptxReader` does not recognize as a typed structure (`mc:AlternateContent`, `p:contentPart`, or any future kind) — `localName`, a self-contained `xml` string (every namespace binding the fragment inherited, including the unprefixed default namespace, is re-declared on its own root so it stays well-formed wherever it is spliced), every `cNvPr/@id` found in its subtree, and whether it references a relationship. `SlideElement` gains a `.raw` case. `SlideElement.allElementIds` / `Slide.allElementIds` return every id on a slide including ones inside `.raw` elements, for id-collision-avoiding allocators that could not otherwise see them (#9, #6's lesson).
- `PPTXError.rawElementGeometryUnsupported(shapeId:)`: thrown by `Slide.setGeometry(ofElementId:...)` when the id names (or lives inside) a `.raw` element, which has no typed geometry to set.
- `Shape.styleXML` / `Connector.styleXML`: the exact original `p:style` (`CT_ShapeStyle`) XML, self-contained (same mechanism as `RawSlideElement.xml`) — a theme style reference (`lnRef`/`fillRef`/`effectRef`/`fontRef`, each an `<a:schemeClr>` plus a style-matrix index) many PowerPoint-authored shapes and connectors rely on *instead of* an explicit `<a:ln>`/fill for their actual rendered color (#11). Kept verbatim rather than parsed into typed fields — resolving a `schemeClr` to an actual color needs the theme part, a document-level resource neither type has access to. `nil` when there is no `p:style` (most synthetically-constructed shapes, and every shape/connector before #11); `PptxWriter` writes it back at `CT_Shape`'s/`CT_Connector`'s schema position (after `spPr`, before `txBody` for `Shape`; as the last child for `Connector`, which has no `txBody`) and omits the tag entirely when `nil`, so existing callers are unaffected.
- `Shape`/`Connector` gain `customGeometryXML`, `rawFillXML`, `effectXML`, `scene3dXML`, `sp3dXML`, `extLstXML`; `GroupShape` gains `rawFillXML`, `effectXML`, `scene3dXML`, `extLstXML` — the `CT_ShapeProperties`/`CT_GroupShapeProperties` children pptx-swift had no typed model for at all (#12): `<a:custGeom>` (the `EG_Geometry` alternative to `<a:prstGeom>` — free-form/custom outline paths), `<a:gradFill>`/`<a:blipFill>`/`<a:pattFill>`/`<a:grpFill>` (the `EG_FillProperties` alternatives to `<a:noFill>`/`<a:solidFill>`), `<a:effectLst>`/`<a:effectDag>` (`EG_EffectProperties`), `<a:scene3d>`, `<a:sp3d>`, `<a:extLst>`. Each is raw, self-contained XML (same mechanism as `styleXML`/`RawSlideElement.xml`), `nil` when absent. `customGeometryXML`/`rawFillXML` are mutually exclusive with `geometry`/`fill`'s typed output (`EG_Geometry`/`EG_FillProperties` are schema choices) — when set, `PptxWriter` writes them *instead of* `<a:prstGeom>`/the typed fill, never both. `Picture` is explicitly out of scope, same reasoning as `styleXML` (#11): `Picture` has never modeled its own `spPr`'s geometry/fill/outline as typed fields at all — `serializePicture` unconditionally writes `<a:prstGeom prst="rect">` regardless of the source shape — so raw-preserving the *other* siblings would not by itself fix a picture's actual round-trip fidelity; documented as a known limitation, not fixed here.

### Known limitations

- `Shape`/`Connector`'s `<a:ln>` (`CT_LineProperties`) is only partially modeled (`w`, an `srgbClr` color, `headEnd`/`tailEnd`) — `<a:prstDash>`/`<a:custDash>` (dash pattern), the `cap`/`cmpd`/`algn` attributes, `<a:round>`/`<a:bevel>`/`<a:miter>` (join style), a `schemeClr` line color (only `srgbClr` is read), and a gradient/pattern fill *for the line itself* all silently round-trip away today. Deliberately out of scope for #12 (per the coordinator's explicit permission to document rather than fix when the remaining surface is large): unlike the six fully-unmodeled children added above, `<a:ln>` is already partially reconstructed from typed fields on write, so "preserve what's unmodeled" would need surgical splicing into that reconstruction rather than a simple mutually-exclusive raw swap — a larger, separate task.

### Fixed

- `PptxReader` recognizes `p:cxnSp` (connectors) instead of silently dropping them — before, any connector vanished the moment `PptxWriter` rewrote the slide, with no error (#9). `PptxWriter` writes them back via `serializeConnector`.
- `PptxReader`/`PptxWriter` no longer silently drop `mc:AlternateContent`, `p:contentPart`, or any other unrecognized `p:spTree`/`p:grpSp` child — they round-trip as self-contained raw XML via `RawSlideElement` (#9). `PptxWriter.write` refuses (`PPTXError.writeError`) to write a slide containing a `.raw` element that references a relationship (most commonly `p:contentPart`'s `r:id`, which it consists of nothing else): pptx-swift's relationship allocation rebuilds each slide's `.rels` from scratch, with no safe way to know whether the original `rId` a `.raw` element's XML names is still valid or collides with a freshly-allocated one — refusing beats risking a dangling or misdirected reference.
- `PptxWriter` writes a table cell's text body as `<a:txBody>` (DrawingML), not `<p:txBody>` (PresentationML) — `CT_TableCell` (`a:tc`) requires the former per ECMA-376; `<p:txBody>` is `CT_Shape`'s own type (#10). The wrong namespace did not just mis-tag the table's own text: LibreOffice's stricter OOXML importer stopped rendering everything in the shape tree from the mistagged table onward (the table's own content, and any element that follows it in document order), discovered while verifying #9's connector round-trip against the `shapes.pptx` fixture (which has a table followed by connectors).
- A shape or connector whose only color comes from `p:style` (no explicit `<a:ln>`/fill in `spPr`) no longer loses that color on a round trip (#11). Discovered re-verifying #10 with a full LibreOffice round trip of `shapes.pptx`: all 3 of its connectors and its "Cloud" freeform shape get their color *only* from `p:style` — after a round trip through pptx-swift 0.5.0/0.6.0-pre-#11, none had any color information left anywhere in the written XML, and LibreOffice rendered every one with no visible stroke or fill (pixel-sampled: theme blue `(74,126,187)` before, pure white `(255,255,255)` after, at the same coordinates). Fixed via `Shape.styleXML`/`Connector.styleXML` above.
- A shape drawn with a custom/free-form outline (`<a:custGeom>`) no longer silently turns into a plain rectangle on a round trip (#12). Discovered fixing #11: `shapes.pptx`'s "Cloud" shape uses `<a:custGeom>`, not `<a:prstGeom>`; `parseShapeProperties` only ever looked for `<a:prstGeom>`, so `geometry` silently stayed at its default (`.rect`) and the custom path's data (`<a:gdLst>`/`<a:pathLst>`/`<a:cxnLst>`) was dropped entirely — invisible before #11 fixed the shape's *color* (an unfilled, uncolored shape's wrong outline is hard to see), and only became visually obvious once #11 landed and the "rectangle instead of a cloud" was suddenly plain to see in a LibreOffice render. Fixed via `Shape.customGeometryXML`/`Connector.customGeometryXML` above.

### Changed

- `GroupShape.containsElement(id:)` now checks `SlideElement.allElementIds` (covers every id in a `.raw` element's subtree, not just its first) instead of a single `elementId` per element.



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
