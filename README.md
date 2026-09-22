# wear_os_tiles

Wear OS **Tiles** and watch-face **Complications** for Flutter apps.

Flutter can run on Wear OS, but tiles and complications are native Android
services that the system binds to while your Flutter UI is usually not running.
Until now no maintained package filled that gap: `wear` covers ambient mode and
screen shape, and `wear_ongoing_activity` covers ongoing activities. Neither
handles tiles or complications. This package is part of the long-standing Wear
OS support request [flutter/flutter#2057](https://github.com/flutter/flutter/issues/2057).
There is no separate Flutter issue for tiles or complications.

How it works:

1. You describe a tile in Dart with a declarative `TileLayout` (a practical
   subset of ProtoLayout).
2. `WearTiles.updateTile` validates it, stores it as JSON in the app's
   SharedPreferences, and calls `TileService.getUpdater(context).requestUpdate(...)`.
3. A generic Kotlin `WearTileService` bundled in this plugin
   (androidx.wear.tiles 1.6.2 + androidx.wear.protolayout 1.4.2) reads the
   stored JSON and renders it with ProtoLayout whenever the system asks.

Complications work the same way through a generic
`ComplicationDataSourceService` and `ComplicationDataSourceUpdateRequester`.

## Install

```yaml
dependencies:
  wear_os_tiles: ^0.1.0
```

Your Android app must target Wear OS. Set `minSdk` to at least 26 (the library
minimum); Wear OS 3 means 30 in practice:

```kotlin
// android/app/build.gradle.kts
defaultConfig { minSdk = 30 }
```

```xml
<!-- android/app/src/main/AndroidManifest.xml -->
<uses-feature android:name="android.hardware.type.watch" />
<application ...>
  <meta-data android:name="com.google.android.wearable.standalone" android:value="true" />
```

The plugin's manifest already declares one tile (id `default`) and one
complication data source (id `default`), with the required permissions,
intent filters and metadata. They merge into your app automatically.

## Usage

### A tile

```dart
import 'package:wear_os_tiles/wear_os_tiles.dart';

final layout = TileLayout(
  freshness: const Duration(minutes: 30), // optional periodic re-render
  root: TileBox(
    width: TileDimension.expand,
    height: TileDimension.expand,
    children: [
      TileArc.progress(progress: 0.62, color: const Color(0xFF8AB4F8)),
      TileColumn(children: [
        const TileImage('ic_steps'), // res/drawable/ic_steps.xml in your app
        const TileText('6,200', fontSize: 30, fontWeight: TileFontWeight.bold),
        const TileText('of 10,000 steps', fontSize: 13, color: Color(0xFFAAAAAA)),
        const TileSpacer(height: 8),
        const TileButton(action: TileAction.launch('add_250'), text: '+250'),
      ]),
    ],
  ),
);

await WearTiles.updateTile(WearTiles.defaultTileId, layout);
```

Elements: `TileColumn`, `TileRow`, `TileBox`, `TileText`, `TileSpacer`,
`TileImage` (drawable bundled in the app), `TileArc` with `ArcLine`,
`ArcSpacer` and `ArcText` (plus the `TileArc.progress` helper), and three
protolayout-material components: `TileCircularProgress`, `TileChip` and
`TileButton`. Containers and leaves take `TileModifiers` (padding,
background colour, corner radius, content description, click action).

Invalid layouts throw `TileLayoutException` before anything is sent. Its
`problems` list reports each issue with a path, for example
`root.children[1].action.id: duplicate action id "go"`.

### Tile clicks

- `TileAction.launch(id)` opens your app's launcher activity. The click reaches
  `WearTiles.clicks` right away, including on a cold start.
- `TileAction.load(id)` reloads the tile in place. The service queues the click
  (up to 50) and delivers it the next time your app listens.

```dart
WearTiles.clicks.listen((e) {
  if (e.clickableId == 'add_250') addSteps(250);
});
```

Each event is delivered once. Listen early, for example in `initState` of
your root widget.

### Complications

```dart
await WearComplications.update(
  WearComplications.defaultId,
  const ComplicationData.rangedValue(value: 6200, max: 10000, text: '6.2k', title: 'Steps'),
);
WearComplications.taps.listen((e) => print('tapped ${e.complicationId}'));
```

Supported types are `shortText`, `longText` and `rangedValue`. When a watch face
asks for a different type, the service converts where the conversion makes
sense:

- ranged value to short or long text (it uses `text`, or the value itself)
- short text to long text, and long text to short text

Any other request gets "no data". The data source is push-only
(`UPDATE_PERIOD_SECONDS = 0`), so updates come from your Dart calls.

### More tiles or complication sources

Android requires every tile and every complication provider to be a service
declared in the manifest. To add one, write a one-line Kotlin subclass and
give it an id:

```kotlin
// android/app/src/main/kotlin/.../WaterTileService.kt
class WaterTileService : dev.manishpanday.wear_os_tiles.WearTileService()
```

```xml
<service android:name=".WaterTileService" android:exported="true"
    android:label="Water" android:icon="@drawable/ic_water"
    android:permission="com.google.android.wearable.permission.BIND_TILE_PROVIDER">
  <intent-filter><action android:name="androidx.wear.tiles.action.BIND_TILE_PROVIDER" /></intent-filter>
  <meta-data android:name="androidx.wear.tiles.PREVIEW" android:resource="@drawable/water_preview" />
  <meta-data android:name="dev.manishpanday.wear_os_tiles.TILE_ID" android:value="water" />
</service>
```

Then call `WearTiles.updateTile('water', ...)`. For a complication, subclass
`WearComplicationService`. Its service needs:

- the `BIND_COMPLICATION_PROVIDER` permission
- the `ACTION_COMPLICATION_UPDATE_REQUEST` intent filter
- `SUPPORTED_TYPES` metadata
- meta-data `dev.manishpanday.wear_os_tiles.COMPLICATION_ID`

The example app shows both. `WearTiles.registeredTileIds()` and
`WearComplications.registeredIds()` list what the merged manifest declares.

### Customising labels and preview images

The built-in services use Android resources that your app can override by
defining resources with the same name:

| Resource | Used for |
|---|---|
| `@string/wear_os_tiles_tile_label` | Tile name in the tile picker |
| `@string/wear_os_tiles_tile_description` | Tile description |
| `@drawable/wear_os_tiles_tile_preview` | Tile picker preview image. Replace it with a screenshot of your tile (PNG or vector). |
| `@drawable/wear_os_tiles_tile_icon` | Tile icon |
| `@string/wear_os_tiles_empty_tile_text` | Shown until the app stores a layout (tapping opens the app) |
| `@string/wear_os_tiles_complication_label` | Data source name in the watch-face editor |
| `@drawable/wear_os_tiles_complication_icon` | Data source icon |
| `@string/wear_os_tiles_complication_preview_text` / `_title` | Preview data in the complication picker |

To remove a built-in service you don't need, add
`<service android:name="dev.manishpanday.wear_os_tiles.WearTileService" tools:node="remove" />`
to your app's manifest.

Tile drawables are looked up by name at runtime. If you enable resource
shrinking, keep them with `res/raw/keep.xml`:
`<resources xmlns:tools="http://schemas.android.com/tools" tools:keep="@drawable/ic_steps,@drawable/ic_water" />`.

## Platform support

| Platform | Support |
|---|---|
| Android: Wear OS 3+ (API 30+) | Full. Library minSdk is 26. |
| Android phones and tablets | Compiles, and calls succeed, but phones have no tile or complication host |
| iOS / watchOS | Not supported |
| Web, macOS, Windows, Linux | Not supported |

## Limitations

- **No Dart when the app isn't running.** The services render the last layout
  or data your app stored. No headless Flutter engine is started when a tile
  or complication is requested. A freshness tick re-renders the same stored
  layout.
- **Load-action clicks are delayed.** If the app process is dead, they wait in
  a queue (max 50) until the app next listens.
- **Only part of ProtoLayout is supported.** There are no Material 3
  expressive components, animations, dynamic data expressions, timelines, or
  images from the network or Flutter assets (only drawables bundled in the
  app).
- **Three complication types only.** No image, goal-progress or
  weighted-elements types.
- **No watchOS.** watchOS complications (ClockKit/WidgetKit) are out of scope.
- **Every tile or complication id needs a manifest-declared service.** You
  can't create them from Dart at runtime.

See [SPEC.md](SPEC.md) for the full requirements and the Can/Cannot table.

## Example

`example/` is a Wear OS app ("Step Goal") that uses every element, both
action types, two tiles and two complications (ranged value and short text).
