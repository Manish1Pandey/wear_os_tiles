import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'complication_data.dart';
import 'json_utils.dart';
import 'tile_layout.dart';

/// Method channel used by the plugin. Exposed for tests.
@visibleForTesting
const MethodChannel wearTilesMethodChannel = MethodChannel(
  'dev.manishpanday.wear_os_tiles/methods',
);

/// Event channel carrying tile clicks and complication taps. Exposed for
/// tests.
@visibleForTesting
const EventChannel wearTilesEventChannel = EventChannel(
  'dev.manishpanday.wear_os_tiles/events',
);

/// How a tile click reached the app.
enum TileClickSource {
  /// A `TileAction.launch` click that opened the app.
  launch,

  /// A `TileAction.load` click recorded by the tile service while the tile
  /// reloaded; delivered when the app next listens.
  load,
}

/// A click on a clickable tile element.
@immutable
class TileClickEvent {
  /// Creates an event (normally produced by the plugin).
  const TileClickEvent({
    required this.tileId,
    required this.clickableId,
    required this.source,
    required this.timestamp,
  });

  /// The tile id passed to [WearTiles.updateTile].
  final String tileId;

  /// The [TileAction.id] of the clicked element.
  final String clickableId;

  /// How the click was delivered.
  final TileClickSource source;

  /// When the click happened (device clock).
  final DateTime timestamp;

  @override
  bool operator ==(Object other) =>
      other is TileClickEvent &&
      other.tileId == tileId &&
      other.clickableId == clickableId &&
      other.source == source &&
      other.timestamp == timestamp;

  @override
  int get hashCode => Object.hash(tileId, clickableId, source, timestamp);

  @override
  String toString() =>
      'TileClickEvent($tileId/$clickableId, ${source.name}, $timestamp)';
}

/// A tap on a complication that opened the app.
@immutable
class ComplicationTapEvent {
  /// Creates an event (normally produced by the plugin).
  const ComplicationTapEvent({
    required this.complicationId,
    required this.timestamp,
  });

  /// The id passed to [WearComplications.update].
  final String complicationId;

  /// When the tap was delivered (device clock).
  final DateTime timestamp;

  @override
  bool operator ==(Object other) =>
      other is ComplicationTapEvent &&
      other.complicationId == complicationId &&
      other.timestamp == timestamp;

  @override
  int get hashCode => Object.hash(complicationId, timestamp);

  @override
  String toString() => 'ComplicationTapEvent($complicationId, $timestamp)';
}

Stream<Object>? _sharedEvents;

/// Single shared subscription to the native event channel. Every event is
/// delivered once by the platform, so both [WearTiles.clicks] and
/// [WearComplications.taps] are views of this one broadcast stream.
Stream<Object> _events() => _sharedEvents ??= wearTilesEventChannel
    .receiveBroadcastStream()
    .map(_decodeEvent)
    .where((e) => e != null)
    .cast<Object>();

Object? _decodeEvent(Object? raw) {
  if (raw is! Map) return null;
  final json = asJsonMap(raw, 'event');
  final ts = DateTime.fromMillisecondsSinceEpoch(
    readOptInt(json, 'timestampMs') ?? 0,
  );
  switch (json['kind']) {
    case 'tile':
      return TileClickEvent(
        tileId: readString(json, 'targetId'),
        clickableId: readString(json, 'clickableId'),
        source: readEnum(
          json,
          'source',
          TileClickSource.values,
          TileClickSource.launch,
        ),
        timestamp: ts,
      );
    case 'complication':
      return ComplicationTapEvent(
        complicationId: readString(json, 'targetId'),
        timestamp: ts,
      );
  }
  return null;
}

/// Resets the cached event stream. Only for tests that swap the mock
/// event handler between cases.
@visibleForTesting
void resetWearTilesEventStreamForTesting() => _sharedEvents = null;

void _checkId(String id, String what) {
  if (!isValidWearId(id)) {
    throw ArgumentError.value(
      id,
      what,
      'must be 1-64 characters of A-Z a-z 0-9 _ . -',
    );
  }
}

/// Wear OS Tiles backed by the plugin's generic `WearTileService`.
///
/// The plugin's own service is registered under tile id `default`. Declare
/// additional tile services in your app manifest (see README) to use more
/// ids.
abstract final class WearTiles {
  /// The tile id of the service shipped in the plugin manifest.
  static const String defaultTileId = 'default';

  /// Validates [layout], stores it for [tileId] and asks the system to
  /// re-request the tile.
  ///
  /// Throws [TileLayoutException] if the layout is invalid, [ArgumentError]
  /// for a malformed id, and [PlatformException] with code `unknown_tile`
  /// if no tile service is registered for [tileId].
  static Future<void> updateTile(String tileId, TileLayout layout) async {
    _checkId(tileId, 'tileId');
    layout.validate();
    await wearTilesMethodChannel.invokeMethod<void>('updateTile', {
      'tileId': tileId,
      'layout': layout.toJsonString(),
    });
  }

  /// Returns the layout currently stored for [tileId], or null.
  static Future<TileLayout?> getTile(String tileId) async {
    _checkId(tileId, 'tileId');
    final json = await wearTilesMethodChannel.invokeMethod<String>('getTile', {
      'tileId': tileId,
    });
    return json == null ? null : TileLayout.fromJsonString(json);
  }

  /// Removes the stored layout for [tileId]; the tile falls back to its
  /// "open the app" message.
  static Future<void> clearTile(String tileId) async {
    _checkId(tileId, 'tileId');
    await wearTilesMethodChannel.invokeMethod<void>('clearTile', {
      'tileId': tileId,
    });
  }

  /// Tile ids of every tile service declared in the app's merged manifest.
  static Future<List<String>> registeredTileIds() async {
    final ids = await wearTilesMethodChannel.invokeListMethod<String>(
      'registeredTileIds',
    );
    return ids ?? const [];
  }

  /// Clicks on tile elements that carry a [TileAction].
  ///
  /// Launch clicks (including the one that cold-started the app) and queued
  /// load clicks are each delivered once. Listen early, e.g. in `main`.
  static Stream<TileClickEvent> get clicks =>
      _events().where((e) => e is TileClickEvent).cast<TileClickEvent>();
}

/// Watch-face complications backed by the plugin's generic
/// `WearComplicationService`.
abstract final class WearComplications {
  /// The complication id of the data source shipped in the plugin manifest.
  static const String defaultId = 'default';

  /// Validates [data], stores it for [id] and asks every watch face showing
  /// that data source to refresh via `ComplicationDataSourceUpdateRequester`.
  ///
  /// Throws [TileLayoutException] if the data is invalid, [ArgumentError]
  /// for a malformed id and [PlatformException] with code
  /// `unknown_complication` if no data source is registered for [id].
  static Future<void> update(String id, ComplicationData data) async {
    _checkId(id, 'id');
    data.validate();
    await wearTilesMethodChannel.invokeMethod<void>('updateComplication', {
      'id': id,
      'data': data.toJsonString(),
    });
  }

  /// Returns the data currently stored for [id], or null.
  static Future<ComplicationData?> get(String id) async {
    _checkId(id, 'id');
    final json = await wearTilesMethodChannel.invokeMethod<String>(
      'getComplication',
      {'id': id},
    );
    return json == null ? null : ComplicationData.fromJsonString(json);
  }

  /// Removes stored data for [id]; watch faces then show "no data".
  static Future<void> clear(String id) async {
    _checkId(id, 'id');
    await wearTilesMethodChannel.invokeMethod<void>('clearComplication', {
      'id': id,
    });
  }

  /// Ids of every complication data source declared in the merged manifest.
  static Future<List<String>> registeredIds() async {
    final ids = await wearTilesMethodChannel.invokeListMethod<String>(
      'registeredComplicationIds',
    );
    return ids ?? const [];
  }

  /// Taps on complications whose data has `tapLaunchesApp` set.
  static Stream<ComplicationTapEvent> get taps => _events()
      .where((e) => e is ComplicationTapEvent)
      .cast<ComplicationTapEvent>();
}
