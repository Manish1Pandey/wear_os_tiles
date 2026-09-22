import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wear_os_tiles/wear_os_tiles.dart';
import 'package:wear_os_tiles_example/layouts.dart';
import 'package:wear_os_tiles_example/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Map<String, String> store;
  late List<MethodCall> calls;
  late MockStreamHandlerEventSink? sink;

  setUp(() {
    calls = [];
    sink = null;
    store = {
      'c:default': stepsComplication(steps: 1200, goal: 10000).toJsonString(),
      'c:water': waterComplication(glasses: 3, goal: 8).toJsonString(),
    };
    messenger.setMockMethodCallHandler(wearTilesMethodChannel, (call) async {
      calls.add(call);
      final args = (call.arguments as Map?)?.cast<String, Object?>() ?? {};
      switch (call.method) {
        case 'getComplication':
          return store['c:${args['id']}'];
        case 'updateComplication':
          store['c:${args['id']}'] = args['data']! as String;
          return null;
        case 'updateTile':
          store['t:${args['tileId']}'] = args['layout']! as String;
          return null;
        case 'registeredTileIds':
          return ['default', 'water'];
        case 'registeredComplicationIds':
          return ['default', 'water'];
      }
      return null;
    });
  });

  // Must run inside the test body: the mock stream's controller has to live
  // in the test's fake-async zone for pumps to deliver its events.
  void installEventChannel() {
    messenger.setMockStreamHandler(
      wearTilesEventChannel,
      MockStreamHandler.inline(
        onListen: (args, s) {
          sink = s;
        },
      ),
    );
  }

  tearDown(() {
    messenger.setMockMethodCallHandler(wearTilesMethodChannel, null);
    messenger.setMockStreamHandler(wearTilesEventChannel, null);
    resetWearTilesEventStreamForTesting();
  });

  testWidgets('restores state and pushes tiles and complications', (
    tester,
  ) async {
    installEventChannel();
    await tester.pumpWidget(const StepGoalApp());
    await tester.pumpAndSettle();

    expect(find.text('1,200'), findsOneWidget);
    expect(find.text('3 / 8 glasses'), findsOneWidget);
    expect(find.textContaining('Tiles: default, water'), findsOneWidget);

    final steps = TileLayout.fromJsonString(store['t:default']!);
    expect(steps, stepsTile(steps: 1200, goal: 10000));
    final water = TileLayout.fromJsonString(store['t:water']!);
    expect(water, waterTile(glasses: 3, goal: 8));
    expect(water.problems(), isEmpty);
  });

  testWidgets('in-app button updates the tile and complication', (
    tester,
  ) async {
    installEventChannel();
    await tester.pumpWidget(const StepGoalApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('add250')));
    await tester.pumpAndSettle();

    expect(find.text('1,450'), findsOneWidget);
    final data = ComplicationData.fromJsonString(store['c:default']!);
    expect(data.value, 1450);
    expect(data.text, '1.4k');
  });

  testWidgets('tile launch click adds steps and is logged', (tester) async {
    installEventChannel();
    await tester.pumpWidget(const StepGoalApp());
    await tester.pumpAndSettle();
    expect(sink, isNotNull);

    sink!.success({
      'kind': 'tile',
      'targetId': 'default',
      'clickableId': TileClicks.add250,
      'source': 'launch',
      'timestampMs': 0,
    });
    sink!.success({
      'kind': 'tile',
      'targetId': 'water',
      'clickableId': TileClicks.addGlass,
      'source': 'launch',
      'timestampMs': 0,
    });
    sink!.success({
      'kind': 'complication',
      'targetId': 'default',
      'source': 'tap',
      'timestampMs': 0,
    });
    await tester.pumpAndSettle();

    expect(find.text('1,450'), findsOneWidget);
    expect(find.text('4 / 8 glasses'), findsOneWidget);
    expect(find.textContaining('default: add_250 (launch)'), findsOneWidget);
    expect(find.textContaining('complication default tapped'), findsOneWidget);
    expect(ComplicationData.fromJsonString(store['c:water']!).text, '4/8');
  });

  testWidgets('platform errors are shown', (tester) async {
    messenger.setMockMethodCallHandler(wearTilesMethodChannel, (call) async {
      if (call.method == 'updateTile') {
        throw PlatformException(code: 'unknown_tile', message: 'no service');
      }
      if (call.method.startsWith('registered')) return <String>[];
      return null;
    });
    installEventChannel();
    await tester.pumpWidget(const StepGoalApp());
    await tester.pumpAndSettle();
    expect(find.text('no service'), findsOneWidget);
  });
}
