import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wear_os_tiles/wear_os_tiles.dart';

const _layout = TileLayout(
  root: TileColumn(
    children: [
      TileText('42'),
      TileButton(action: TileAction.launch('go'), text: '+'),
    ],
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;
  late Map<String, Object?> stored;

  setUp(() {
    calls = [];
    stored = {};
    messenger.setMockMethodCallHandler(wearTilesMethodChannel, (call) async {
      calls.add(call);
      final args = (call.arguments as Map?)?.cast<String, Object?>() ?? {};
      switch (call.method) {
        case 'updateTile':
          if (args['tileId'] == 'missing') {
            throw PlatformException(code: 'unknown_tile', message: 'nope');
          }
          stored['tile:${args['tileId']}'] = args['layout'];
          return null;
        case 'getTile':
          return stored['tile:${args['tileId']}'];
        case 'clearTile':
          stored.remove('tile:${args['tileId']}');
          return null;
        case 'registeredTileIds':
          return ['default', 'water'];
        case 'updateComplication':
          if (args['id'] == 'missing') {
            throw PlatformException(code: 'unknown_complication');
          }
          stored['c:${args['id']}'] = args['data'];
          return null;
        case 'getComplication':
          return stored['c:${args['id']}'];
        case 'clearComplication':
          stored.remove('c:${args['id']}');
          return null;
        case 'registeredComplicationIds':
          return ['default'];
      }
      throw MissingPluginException();
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(wearTilesMethodChannel, null);
    messenger.setMockStreamHandler(wearTilesEventChannel, null);
    resetWearTilesEventStreamForTesting();
  });

  group('WearTiles', () {
    test('updateTile sends id and JSON layout', () async {
      await WearTiles.updateTile('default', _layout);
      expect(calls.single.method, 'updateTile');
      final args = calls.single.arguments as Map;
      expect(args['tileId'], 'default');
      expect(TileLayout.fromJsonString(args['layout'] as String), _layout);
    });

    test('getTile returns the stored layout, clearTile removes it', () async {
      expect(await WearTiles.getTile('default'), isNull);
      await WearTiles.updateTile('default', _layout);
      expect(await WearTiles.getTile('default'), _layout);
      await WearTiles.clearTile('default');
      expect(await WearTiles.getTile('default'), isNull);
    });

    test('invalid layouts never reach the platform', () async {
      const bad = TileLayout(root: TileCircularProgress(progress: 2));
      await expectLater(
        WearTiles.updateTile('default', bad),
        throwsA(isA<TileLayoutException>()),
      );
      expect(calls, isEmpty);
    });

    test('invalid ids are rejected before the platform call', () async {
      await expectLater(
        WearTiles.updateTile('bad id', _layout),
        throwsArgumentError,
      );
      await expectLater(WearTiles.getTile(''), throwsArgumentError);
      await expectLater(WearTiles.clearTile('a/b'), throwsArgumentError);
      expect(calls, isEmpty);
    });

    test('platform errors propagate', () async {
      await expectLater(
        WearTiles.updateTile('missing', _layout),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'unknown_tile',
          ),
        ),
      );
    });

    test('registeredTileIds', () async {
      expect(await WearTiles.registeredTileIds(), ['default', 'water']);
    });
  });

  group('WearComplications', () {
    const data = ComplicationData.rangedValue(value: 3, max: 8, text: '3');

    test('update sends id and JSON data; get/clear round trip', () async {
      await WearComplications.update('default', data);
      final args = calls.single.arguments as Map;
      expect(calls.single.method, 'updateComplication');
      expect(args['id'], 'default');
      expect(ComplicationData.fromJsonString(args['data'] as String), data);
      expect(await WearComplications.get('default'), data);
      await WearComplications.clear('default');
      expect(await WearComplications.get('default'), isNull);
    });

    test('invalid data is rejected locally', () async {
      await expectLater(
        WearComplications.update(
          'default',
          const ComplicationData.rangedValue(value: 9, max: 8),
        ),
        throwsA(isA<TileLayoutException>()),
      );
      await expectLater(
        WearComplications.update('no spaces allowed', data),
        throwsArgumentError,
      );
      expect(calls, isEmpty);
    });

    test('unknown id error propagates', () async {
      await expectLater(
        WearComplications.update('missing', data),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'unknown_complication',
          ),
        ),
      );
    });

    test('registeredIds', () async {
      expect(await WearComplications.registeredIds(), ['default']);
    });
  });

  group('events', () {
    void emit(List<Object?> events) {
      messenger.setMockStreamHandler(
        wearTilesEventChannel,
        MockStreamHandler.inline(
          onListen: (args, sink) {
            for (final e in events) {
              sink.success(e);
            }
          },
        ),
      );
    }

    test('tile clicks and complication taps are decoded and split', () async {
      emit([
        {
          'kind': 'tile',
          'targetId': 'default',
          'clickableId': 'go',
          'source': 'launch',
          'timestampMs': 1000,
        },
        {
          'kind': 'complication',
          'targetId': 'default',
          'clickableId': null,
          'source': 'tap',
          'timestampMs': 2000,
        },
        {
          'kind': 'tile',
          'targetId': 'water',
          'clickableId': 'refresh',
          'source': 'load',
          'timestampMs': 3000,
        },
        // Unknown kinds and malformed payloads are ignored.
        {'kind': 'watchface', 'targetId': 'x'},
        'garbage',
      ]);

      final clicks = <TileClickEvent>[];
      final taps = <ComplicationTapEvent>[];
      final s1 = WearTiles.clicks.listen(clicks.add);
      final s2 = WearComplications.taps.listen(taps.add);
      await pumpEventQueue();

      expect(clicks, [
        TileClickEvent(
          tileId: 'default',
          clickableId: 'go',
          source: TileClickSource.launch,
          timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
        ),
        TileClickEvent(
          tileId: 'water',
          clickableId: 'refresh',
          source: TileClickSource.load,
          timestamp: DateTime.fromMillisecondsSinceEpoch(3000),
        ),
      ]);
      expect(taps, [
        ComplicationTapEvent(
          complicationId: 'default',
          timestamp: DateTime.fromMillisecondsSinceEpoch(2000),
        ),
      ]);
      await s1.cancel();
      await s2.cancel();
    });

    test('native listen happens once for both streams', () async {
      var listens = 0;
      var cancels = 0;
      messenger.setMockStreamHandler(
        wearTilesEventChannel,
        MockStreamHandler.inline(
          onListen: (args, sink) => listens++,
          onCancel: (args) => cancels++,
        ),
      );
      final a = WearTiles.clicks.listen((_) {});
      final b = WearComplications.taps.listen((_) {});
      await pumpEventQueue();
      expect(listens, 1);
      await a.cancel();
      await pumpEventQueue();
      expect(cancels, 0);
      await b.cancel();
      await pumpEventQueue();
      expect(cancels, 1);
    });
  });
}
