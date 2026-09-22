import 'package:flutter_test/flutter_test.dart';
import 'package:wear_os_tiles/wear_os_tiles.dart';

void main() {
  group('ComplicationData JSON', () {
    test('short text round trip', () {
      const data = ComplicationData.shortText(
        text: '3/8',
        title: 'Water',
        contentDescription: '3 of 8',
        tapLaunchesApp: false,
      );
      final back = ComplicationData.fromJsonString(data.toJsonString());
      expect(back, data);
      expect(back.type, WearComplicationType.shortText);
      expect(back.tapLaunchesApp, isFalse);
    });

    test('long text round trip', () {
      const data = ComplicationData.longText(text: 'Next: stand-up 10:30');
      expect(ComplicationData.fromJson(data.toJson()), data);
      expect(data.toJson().containsKey('title'), isFalse);
    });

    test('ranged value round trip and wire keys', () {
      const data = ComplicationData.rangedValue(
        value: 6200,
        max: 10000,
        text: '6.2k',
        title: 'Steps',
      );
      final json = data.toJson();
      expect(json['type'], 'rangedValue');
      expect(json['min'], 0);
      expect(json['max'], 10000);
      expect(ComplicationData.fromJson(json), data);
      expect(ComplicationData.fromJson(json).hashCode, data.hashCode);
    });

    test('rejects unknown type', () {
      expect(
        () => ComplicationData.fromJson({'type': 'photo'}),
        throwsFormatException,
      );
    });
  });

  group('ComplicationData validation', () {
    test('valid data has no problems', () {
      expect(const ComplicationData.shortText(text: 'a').problems(), isEmpty);
      expect(
        const ComplicationData.rangedValue(value: 0, max: 1).problems(),
        isEmpty,
      );
    });

    test('text types need text', () {
      expect(
        const ComplicationData.shortText(text: '').problems().single,
        startsWith('text'),
      );
      expect(
        () => const ComplicationData.longText(text: '').validate(),
        throwsA(isA<TileLayoutException>()),
      );
    });

    test('ranged value checks range and finiteness', () {
      expect(
        const ComplicationData.rangedValue(value: 5, min: 5, max: 5).problems(),
        contains('max: must be greater than min'),
      );
      expect(
        const ComplicationData.rangedValue(
          value: 11,
          max: 10,
        ).problems().single,
        startsWith('value: must be between'),
      );
      expect(
        const ComplicationData.rangedValue(
          value: double.nan,
          max: 10,
        ).problems().single,
        'value: must be finite',
      );
      expect(
        const ComplicationData.rangedValue(
          value: 1,
          min: double.negativeInfinity,
          max: 10,
        ).problems().single,
        'min: must be finite',
      );
    });
  });
}
