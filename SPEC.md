# wear_os_tiles — Specification

Written before any code. This is the contract the implementation and the tests are held to.

## 1. Purpose

Flutter apps can run on Wear OS, but there is no maintained way for a Flutter app to put
content on the two surfaces a user sees most on a watch without opening the app:

* **Tiles** — the swipeable cards next to the watch face (rendered by the system from a
  ProtoLayout description, never by Flutter).
* **Complications** — the small data slots on a watch face (supplied by a
  `ComplicationDataSourceService`).

Both are *native Android services* that the system binds to while the Flutter app is usually
not running. `wear_os_tiles` bridges the gap: Dart describes a tile or complication declaratively,
the description is stored on the device, and generic Kotlin services shipped in the plugin
render that stored description whenever the system asks.

## 2. Functional requirements

| ID | Requirement |
|----|-------------|
| FR-1 | Dart exposes a declarative, immutable tile layout model covering a practical subset of ProtoLayout: `Column`, `Row`, `Box`, `Text`, `Spacer`, `Image` (bundled Android drawable), `Arc` with `ArcLine` / `ArcSpacer` / `ArcText` children, material `CircularProgressIndicator`, material primary/secondary `Chip`, material `Button`. |
| FR-2 | Containers and leaf elements accept modifiers: padding, background colour, corner radius, content description and a clickable action. |
| FR-3 | A clickable action is either `load` (tile reloads in place; the click is queued for Dart) or `launch` (the app's launcher activity opens and the click is delivered to Dart). Every action carries a non-empty string id, unique within a layout. |
| FR-4 | The layout model serialises to JSON and parses back to an equal object (`fromJson(toJson(x)) == x`). |
| FR-5 | The layout model validates itself before sending: tile id format, unique non-empty action ids, progress in [0, 1], non-negative finite dimensions, arc lengths in [0, 360], drawable name format, button content rules, nesting depth <= 30, freshness >= 0. Violations raise `TileLayoutException` listing every problem with a JSON-path-like location. |
| FR-6 | `WearTiles.updateTile(tileId, layout)` validates, stores the JSON in the app's SharedPreferences (synchronous commit), and calls `TileService.getUpdater(context).requestUpdate(serviceClass)` for the tile service registered under `tileId`. |
| FR-7 | The plugin ships a generic `WearTileService` (androidx.wear.tiles 1.6.2 + androidx.wear.protolayout 1.4.2) that reads the stored layout for its tile id, renders it with ProtoLayout, applies the stored freshness interval, and serves drawable resources referenced by `Image`, `Chip` icons and `Button` icons/images. With no stored layout it shows a configurable "open the app" message that launches the app. |
| FR-8 | Multiple tiles: the plugin's service is tile id `default`. An app adds more tiles by declaring a one-line Kotlin subclass of `WearTileService` in its manifest with meta-data `dev.manishpanday.wear_os_tiles.TILE_ID`. `WearTiles.registeredTileIds()` lists them. Updating an unknown id fails with `PlatformException(code: 'unknown_tile')`. |
| FR-9 | Tile clicks reach Dart through `WearTiles.clicks` (stream). Launch clicks arrive via the activity's launch intent (cold start) or `onNewIntent` (warm). Load clicks are persisted by the service and delivered the next time Dart listens (or immediately if the app is alive). Each event is delivered once. |
| FR-10 | Dart exposes a complication data model with `ComplicationData.shortText`, `.longText`, `.rangedValue` (text, title, content description, value/min/max), JSON round trip and validation. |
| FR-11 | `WearComplications.update(id, data)` validates, stores the data and calls `ComplicationDataSourceUpdateRequester.create(context, component).requestUpdateAll()` for the data source registered under `id`. |
| FR-12 | The plugin ships a generic `WearComplicationService` (androidx.wear.watchface.complications.datasource 1.3.0) supporting `SHORT_TEXT`, `LONG_TEXT`, `RANGED_VALUE`, push-only (`UPDATE_PERIOD_SECONDS = 0`). It answers the type the watch face requests from the stored data when the conversion is lossless or natural (ranged → short/long text, short ↔ long text); otherwise it answers `NoData`. It supplies preview data for the watch-face picker. |
| FR-13 | Tapping a complication (optional, default on) launches the app; the tap is delivered to Dart through `WearComplications.taps`. |
| FR-14 | Stored tiles / complications can be read back (`getTile`, `getComplication`) and cleared (`clearTile`, `clearComplication`). |
| FR-15 | The plugin manifest declares both services with the required permissions, intent filters and metadata. Labels, the tile preview image, the complication icon and the empty-tile text are Android resources the app can override by name (documented in README). |

## 3. Can / Cannot

| Can | Cannot (and why) |
|-----|------------------|
| Render a Dart-described tile with the listed elements on Wear OS 3+ (API 30+; library minSdk 26). | Render Flutter widgets inside a tile — tiles are drawn by the system from ProtoLayout, not by Flutter. |
| Update the tile/complication any time the Flutter app (or a Dart background isolate the app already runs) calls the API. | Run Dart code when the tile or complication is requested while the app is not running. The services render the **last stored** description; no headless Flutter engine is started. |
| Deliver launch-action clicks and complication taps to Dart immediately. | Deliver load-action clicks to Dart while the app process is dead — they are queued (max 50) and delivered on next listen. |
| Periodically re-request the tile (freshness interval) — useful for time-based content re-rendered from the stored layout. | Change content on a freshness tick unless Dart stored a new layout; the re-render uses the same stored JSON. |
| Complications: SHORT_TEXT, LONG_TEXT, RANGED_VALUE, with title, content description and tap-to-open. | Other complication types (SMALL_IMAGE, PHOTO_IMAGE, MONOCHROMATIC_IMAGE, GOAL_PROGRESS, WEIGHTED_ELEMENTS), timelines, or dynamic (platform-data) expressions. |
| Images from drawables bundled in the app (`res/drawable`). | Network images or Flutter assets inside tiles (ProtoLayout needs Android resources or inline bytes; inline bytes are out of scope). |
| Several tiles/complication sources per app via tiny manifest-declared subclasses. | Declare new tiles purely from Dart at runtime — Android requires every tile/complication provider to be a manifest-declared service. |
| Android / Wear OS. | iOS, watchOS complications (ClockKit / WidgetKit) — out of scope; web/desktop have no equivalent. |
| Material (protolayout-material) Chip, Button, CircularProgressIndicator. | Material 3 expressive tile components, animations, dynamic data bindings, state/`LoadAction` request-state payloads. |

## 4. Public API sketch (Dart)

```dart
// Tiles
abstract final class WearTiles {
  static Future<void> updateTile(String tileId, TileLayout layout);
  static Future<TileLayout?> getTile(String tileId);
  static Future<void> clearTile(String tileId);
  static Future<List<String>> registeredTileIds();
  static Stream<TileClickEvent> get clicks;
}

class TileLayout { TileLayout({required TileElement root, Duration freshness = Duration.zero}); ... }
sealed class TileElement { Map<String, Object?> toJson(); static TileElement fromJson(Map json); }
TileColumn / TileRow / TileBox / TileText / TileSpacer / TileImage / TileArc
  (children: ArcLine / ArcSpacer / ArcText, helper TileArc.progress)
TileCircularProgress / TileChip / TileButton
TileModifiers, TilePadding, TileDimension (dp / expand / wrap / weight)
TileAction.load(id) / TileAction.launch(id)
TileLayoutException(List<String> problems)

// Complications
abstract final class WearComplications {
  static Future<void> update(String id, ComplicationData data);
  static Future<ComplicationData?> get(String id);
  static Future<void> clear(String id);
  static Future<List<String>> registeredIds();
  static Stream<ComplicationTapEvent> get taps;
}
ComplicationData.shortText(...) / .longText(...) / .rangedValue(...)
```

Wire format: `{"v":1,"freshnessMs":int,"root":{"type":"column",...}}` — documented in
`lib/src/tile_layout.dart`, mirrored by `TileLayoutParser.kt`.

## 5. Platform matrix

| Platform | Support |
|----------|---------|
| Android — Wear OS 3+ (API 30+) | Full (library minSdk 26) |
| Android phones/tablets | Compiles; services are declared but phones have no tile/complication host, calls succeed but nothing is shown |
| iOS / watchOS | Not supported (out of scope) |
| Web, macOS, Windows, Linux | Not supported |

## 6. Verification plan

* Dart: JSON round-trip for every element, validation failure cases, mocked MethodChannel and
  EventChannel tests for every API method and event decoding.
* Kotlin: Robolectric unit tests parsing the JSON wire format into ProtoLayout elements
  (including material components that need a `Context`) and complication data mapping.
* Build: `flutter build apk --debug` for the Wear OS example.
* Runtime on a Wear OS emulator only if a Wear system image is installed.
