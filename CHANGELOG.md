# Changelog

All notable changes to pptx-swift will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

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
