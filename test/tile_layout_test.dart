import 'dart:convert';
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:wear_os_tiles/wear_os_tiles.dart';

/// A layout using every element and every optional field at least once.
TileLayout fullLayout() => TileLayout(
  freshness: const Duration(minutes: 15),
  root: TileBox(
    width: TileDimension.expand,
    height: TileDimension.expand,
    horizontalAlignment: TileHorizontalAlignment.start,
    verticalAlignment: TileVerticalAlignment.bottom,
    modifiers: const TileModifiers(
      padding: TilePadding(start: 1, top: 2, end: 3, bottom: 4),
      backgroundColor: Color(0xFF102030),
      cornerRadius: 12,
      contentDescription: 'root',
    ),
    children: [
      TileArc.progress(progress: 0.25, color: const Color(0xFF00FF00)),
      const TileArc(
        anchorAngle: 90,
        anchorType: TileArcAnchor.center,
        modifiers: TileModifiers(action: TileAction.load('arc')),
        children: [
          ArcLine(length: 40, thickness: 3, color: Color(0x80FF0000)),
          ArcSpacer(length: 10),
          ArcText('curved', color: Color(0xFFFFFFFF), fontSize: 11),
        ],
      ),
      TileColumn(
        horizontalAlignment: TileHorizontalAlignment.end,
        width: const TileDimension.dp(120),
        height: TileDimension.wrap,
        children: [
          const TileImage(
            'ic_steps',
            width: TileDimension.dp(20),
            height: TileDimension.expand,
            contentScale: TileContentScale.crop,
            tint: Color(0xFFABCDEF),
            modifiers: TileModifiers(action: TileAction.launch('img')),
          ),
          const TileText(
            'Hello',
            color: Color(0xFFFFFFFF),
            fontSize: 20,
            fontWeight: TileFontWeight.bold,
            italic: true,
            maxLines: 2,
            textAlign: TileTextAlign.start,
          ),
          const TileSpacer(width: 4, height: 8),
          const TileRow(
            verticalAlignment: TileVerticalAlignment.top,
            width: TileDimension.weight(2),
            children: [
              TileButton(action: TileAction.launch('b1'), text: '+1', size: 40),
              TileButton(
                action: TileAction.load('b2'),
                iconResource: 'ic_refresh',
                style: TileComponentStyle.secondary,
                backgroundColor: Color(0xFF111111),
                contentColor: Color(0xFFEEEEEE),
                contentDescription: 'refresh',
              ),
              TileButton(action: TileAction.load('b3'), imageResource: 'photo'),
            ],
          ),
          const TileChip(
            label: 'Open',
            secondaryLabel: 'details',
            action: TileAction.launch('chip'),
            iconResource: 'ic_open',
            style: TileComponentStyle.secondary,
            backgroundColor: Color(0xFF222222),
            contentColor: Color(0xFFDDDDDD),
            width: TileDimension.expand,
            contentDescription: 'open app',
          ),
        ],
      ),
      const TileCircularProgress(
        progress: 0.5,
        indicatorColor: Color(0xFF0000FF),
        trackColor: Color(0xFF333333),
        strokeWidth: 5,
        startAngle: 10,
        endAngle: 350,
        contentDescription: 'half',
      ),
    ],
  ),
);

void main() {
  group('JSON round trip', () {
    test('full layout survives toJson -> fromJson', () {
      final layout = fullLayout();
      final back = TileLayout.fromJson(layout.toJson());
      expect(back, equals(layout));
      expect(back.hashCode, equals(layout.hashCode));
    });

    test('full layout survives a JSON string round trip', () {
      final layout = fullLayout();
      final text = layout.toJsonString();
      expect(TileLayout.fromJsonString(text), equals(layout));
      // Stable encoding: re-encoding the parsed layout gives the same bytes.
      expect(TileLayout.fromJsonString(text).toJsonString(), equals(text));
    });

    test('wire format has the documented shape', () {
      final json =
          jsonDecode(fullLayout().toJsonString()) as Map<String, Object?>;
      expect(json['v'], tileWireFormatVersion);
      expect(json['freshnessMs'], 15 * 60 * 1000);
      final root = json['root']! as Map<String, Object?>;
      expect(root['type'], 'box');
      expect(root['width'], 'expand');
      final children = root['children']! as List;
      expect((children[0] as Map)['type'], 'arc');
      expect((children[2] as Map)['type'], 'column');
      expect((children[2] as Map)['width'], {'dp': 120.0});
      expect((children[3] as Map)['type'], 'circularProgress');
      final modifiers = root['modifiers']! as Map;
      // Colours are unsigned 32-bit ARGB.
      expect(modifiers['background'], 0xFF102030);
    });

    test('optional fields are omitted from JSON', () {
      final json = const TileText('x').toJson();
      expect(json.keys, containsAll(['type', 'text']));
      expect(json.containsKey('color'), isFalse);
      expect(json.containsKey('modifiers'), isFalse);
      expect(json.containsKey('italic'), isFalse);
    });

    test('defaults are applied when parsing minimal JSON', () {
      final e = TileElement.fromJson({'type': 'image', 'resource': 'a'});
      expect(e, const TileImage('a'));
      final layout = TileLayout.fromJson({
        'root': {'type': 'spacer'},
      });
      expect(layout.freshness, Duration.zero);
      expect(layout.root, const TileSpacer());
    });

    test('rejects unknown element types and versions', () {
      expect(
        () => TileElement.fromJson({'type': 'slider'}),
        throwsFormatException,
      );
      expect(
        () => TileLayout.fromJson({
          'v': 99,
          'root': {'type': 'spacer'},
        }),
        throwsFormatException,
      );
      expect(
        () => TileElement.fromJson({'type': 'text', 'text': 3}),
        throwsFormatException,
      );
      expect(
        () => TileElement.fromJson({
          'type': 'arc',
          'children': [
            {'type': 'arcBlob'},
          ],
        }),
        throwsFormatException,
      );
      expect(() => TileDimension.fromJson('huge'), throwsFormatException);
    });
  });

  group('TileArc.progress', () {
    test('splits the circle into progress and track', () {
      final arc = TileArc.progress(
        progress: 0.25,
        color: const Color(0xFF00FF00),
      );
      final lines = arc.children.cast<ArcLine>();
      expect(lines.map((l) => l.length), [90, 270]);
      expect(lines.first.strokeCap, ArcStrokeCap.round);
    });

    test('clamps and handles 0 and 1', () {
      expect(
        TileArc.progress(progress: 0, color: const Color(0xFFFFFFFF)).children,
        hasLength(1),
      );
      final full = TileArc.progress(
        progress: 5,
        color: const Color(0xFFFFFFFF),
      );
      expect(full.children, hasLength(1));
      expect((full.children.single as ArcLine).length, 360);
      expect(
        TileLayout(
          root: TileArc.progress(
            progress: double.nan,
            color: const Color(0xFFFFFFFF),
          ),
        ).problems(),
        isEmpty,
      );
    });
  });

  group('validation', () {
    test('full layout is valid', () {
      expect(fullLayout().problems(), isEmpty);
      expect(fullLayout().validate, returnsNormally);
    });

    test('collects action ids in document order', () {
      expect(fullLayout().actionIds, ['arc', 'img', 'b1', 'b2', 'b3', 'chip']);
    });

    test('duplicate and empty action ids are reported with paths', () {
      const layout = TileLayout(
        root: TileColumn(
          children: [
            TileButton(action: TileAction.load('a'), text: '1'),
            TileButton(action: TileAction.launch('a'), text: '2'),
            TileChip(label: 'c', action: TileAction.load('')),
          ],
        ),
      );
      final problems = layout.problems();
      expect(problems, hasLength(2));
      expect(problems[0], startsWith('root.children[1].action.id'));
      expect(problems[0], contains('duplicate'));
      expect(problems[1], startsWith('root.children[2].action.id'));
      expect(
        () => layout.validate(),
        throwsA(
          isA<TileLayoutException>().having(
            (e) => e.problems,
            'problems',
            hasLength(2),
          ),
        ),
      );
    });

    test('progress, dimensions and arc lengths are range checked', () {
      const layout = TileLayout(
        freshness: Duration(seconds: -1),
        root: TileBox(
          width: TileDimension.dp(-1),
          height: TileDimension.weight(0),
          children: [
            TileCircularProgress(progress: 1.5, startAngle: 90, endAngle: 10),
            TileArc(children: [ArcLine(length: 400), ArcSpacer(length: -5)]),
            TileArc(children: [ArcLine(length: 200), ArcLine(length: 200)]),
            TileImage('ok', width: TileDimension.wrap),
            TileText('x', fontSize: 0, maxLines: 0),
            TileSpacer(width: double.infinity),
          ],
        ),
      );
      final p = layout.problems().join('\n');
      expect(p, contains('freshness'));
      expect(p, contains('root.width'));
      expect(p, contains('root.height'));
      expect(p, contains('root.children[0].progress'));
      expect(p, contains('root.children[0].endAngle'));
      expect(p, contains('root.children[1].children[0].length'));
      expect(p, contains('root.children[1].children[1].length'));
      expect(p, contains('root.children[2].children: total arc length 400'));
      expect(p, contains('root.children[3].width: wrap is not supported'));
      expect(p, contains('root.children[4].fontSize'));
      expect(p, contains('root.children[4].maxLines'));
      expect(p, contains('root.children[5].width'));
    });

    test('drawable names must be valid Android resource names', () {
      const layout = TileLayout(
        root: TileColumn(
          children: [
            TileImage('Bad-Name'),
            TileChip(
              label: 'x',
              action: TileAction.load('x'),
              iconResource: '1icon',
            ),
          ],
        ),
      );
      final p = layout.problems();
      expect(p, hasLength(2));
      expect(p[0], startsWith('root.children[0].resource'));
      expect(p[1], startsWith('root.children[1].icon'));
    });

    test('buttons need exactly one kind of content', () {
      const none = TileButton(action: TileAction.load('a'));
      const two = TileButton(
        action: TileAction.load('b'),
        text: 'x',
        iconResource: 'ic',
      );
      expect(
        const TileLayout(root: none).problems().single,
        contains('exactly one'),
      );
      expect(
        const TileLayout(root: two).problems().single,
        contains('exactly one'),
      );
    });

    test('chip width must be dp or expand and label non-empty', () {
      const chip = TileChip(
        label: '',
        action: TileAction.load('a'),
        width: TileDimension.weight(1),
      );
      final p = const TileLayout(root: chip).problems().join('\n');
      expect(p, contains('root.label'));
      expect(p, contains('root.width: must be dp or expand'));
    });

    test('nesting deeper than the renderer limit is rejected', () {
      TileElement nested = const TileText('leaf');
      for (var i = 0; i < maxTileLayoutDepth; i++) {
        nested = TileBox(children: [nested]);
      }
      final p = TileLayout(root: nested).problems();
      expect(p, hasLength(1));
      expect(p.single, contains('nesting depth ${maxTileLayoutDepth + 1}'));

      TileElement ok = const TileText('leaf');
      for (var i = 0; i < maxTileLayoutDepth - 1; i++) {
        ok = TileBox(children: [ok]);
      }
      expect(TileLayout(root: ok).problems(), isEmpty);
    });

    test('ids', () {
      expect(isValidWearId('default'), isTrue);
      expect(isValidWearId('steps.v2-a_b'), isTrue);
      expect(isValidWearId(''), isFalse);
      expect(isValidWearId('has space'), isFalse);
      expect(isValidWearId('x' * 65), isFalse);
    });

    test('exception toString lists problems', () {
      const e = TileLayoutException(['a: bad', 'b: worse']);
      expect(e.toString(), contains('a: bad'));
      expect(e.toString(), contains('b: worse'));
    });
  });
}
