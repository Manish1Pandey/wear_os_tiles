## 0.1.0

* Initial release.
* Declarative Dart tile layout model (Column, Row, Box, Text, Spacer, Image,
  Arc with ArcLine/ArcSpacer/ArcText, CircularProgressIndicator, Chip, Button)
  with JSON round trip and validation.
* Generic `WearTileService` (androidx.wear.tiles 1.6.2, protolayout 1.4.2)
  rendering the stored layout, with freshness interval and drawable resources.
* `WearTiles.updateTile` / `getTile` / `clearTile` / `registeredTileIds` and a
  `clicks` stream for launch and load actions.
* Generic `WearComplicationService` (complications data source 1.3.0) with
  SHORT_TEXT, LONG_TEXT and RANGED_VALUE; `WearComplications.update` and a
  `taps` stream.
* Multiple tiles/complications through one-line manifest-declared subclasses.
