import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'json_utils.dart';
import 'tile_layout.dart' show TileLayoutException;

/// Complication types supported by the plugin's data source.
enum WearComplicationType {
  /// Short text (about 7 characters) with an optional title.
  shortText,

  /// A line of longer text with an optional title.
  longText,

  /// A value within a range, drawn by the watch face as a gauge.
  rangedValue,
}

/// Data a watch-face complication shows.
///
/// The plugin's `WearComplicationService` declares support for
/// `SHORT_TEXT`, `LONG_TEXT` and `RANGED_VALUE`. When the watch face asks for
/// a type different from [type], the service converts where it is natural:
/// ranged value -> short/long text (using [text], or the value itself),
/// short text <-> long text. Other requests receive "no data".
@immutable
class ComplicationData {
  const ComplicationData._({
    required this.type,
    required this.text,
    this.title,
    this.contentDescription,
    this.value,
    this.min,
    this.max,
    this.tapLaunchesApp = true,
  });

  /// Short text data (keep [text] to about 7 characters).
  const ComplicationData.shortText({
    required String text,
    String? title,
    String? contentDescription,
    bool tapLaunchesApp = true,
  }) : this._(
         type: WearComplicationType.shortText,
         text: text,
         title: title,
         contentDescription: contentDescription,
         tapLaunchesApp: tapLaunchesApp,
       );

  /// Long text data.
  const ComplicationData.longText({
    required String text,
    String? title,
    String? contentDescription,
    bool tapLaunchesApp = true,
  }) : this._(
         type: WearComplicationType.longText,
         text: text,
         title: title,
         contentDescription: contentDescription,
         tapLaunchesApp: tapLaunchesApp,
       );

  /// Ranged value data: [value] between [min] and [max], with optional short
  /// [text] and [title] drawn inside the gauge.
  const ComplicationData.rangedValue({
    required double value,
    double min = 0,
    required double max,
    String? text,
    String? title,
    String? contentDescription,
    bool tapLaunchesApp = true,
  }) : this._(
         type: WearComplicationType.rangedValue,
         value: value,
         min: min,
         max: max,
         text: text,
         title: title,
         contentDescription: contentDescription,
         tapLaunchesApp: tapLaunchesApp,
       );

  /// The type this data was created as.
  final WearComplicationType type;

  /// Main text (required for short/long text, optional for ranged value).
  final String? text;

  /// Optional title shown with the text.
  final String? title;

  /// Accessibility description; defaults to the text on the device.
  final String? contentDescription;

  /// Current value (ranged value only).
  final double? value;

  /// Range minimum (ranged value only).
  final double? min;

  /// Range maximum (ranged value only).
  final double? max;

  /// Whether tapping the complication opens the app and emits a
  /// `ComplicationTapEvent`.
  final bool tapLaunchesApp;

  /// Returns every validation problem; empty when valid.
  List<String> problems() {
    final p = <String>[];
    switch (type) {
      case WearComplicationType.shortText:
      case WearComplicationType.longText:
        if (text == null || text!.isEmpty) p.add('text: must not be empty');
      case WearComplicationType.rangedValue:
        final v = value, lo = min, hi = max;
        if (v == null || !v.isFinite) p.add('value: must be finite');
        if (lo == null || !lo.isFinite) p.add('min: must be finite');
        if (hi == null || !hi.isFinite) p.add('max: must be finite');
        if (lo != null && hi != null && lo.isFinite && hi.isFinite) {
          if (hi <= lo) p.add('max: must be greater than min');
          if (v != null && v.isFinite && (v < lo || v > hi)) {
            p.add('value: must be between min ($lo) and max ($hi)');
          }
        }
    }
    return p;
  }

  /// Throws [TileLayoutException] if [problems] is not empty.
  void validate() {
    final found = problems();
    if (found.isNotEmpty) throw TileLayoutException(found);
  }

  /// Converts to the JSON wire format read by the Kotlin data source.
  Map<String, Object?> toJson() => compact({
    'type': type.name,
    'text': text,
    'title': title,
    'contentDescription': contentDescription,
    'value': value,
    'min': min,
    'max': max,
    'tapLaunchesApp': tapLaunchesApp,
  });

  /// Encodes as a JSON string.
  String toJsonString() => jsonEncode(toJson());

  /// Parses from JSON.
  factory ComplicationData.fromJson(Map<String, Object?> json) {
    final type = readEnum(
      json,
      'type',
      WearComplicationType.values,
      WearComplicationType.shortText,
    );
    return ComplicationData._(
      type: type,
      text: readOptString(json, 'text'),
      title: readOptString(json, 'title'),
      contentDescription: readOptString(json, 'contentDescription'),
      value: readOptDouble(json, 'value'),
      min: readOptDouble(json, 'min'),
      max: readOptDouble(json, 'max'),
      tapLaunchesApp: readOptBool(json, 'tapLaunchesApp') ?? true,
    );
  }

  /// Parses from a JSON string.
  factory ComplicationData.fromJsonString(String source) =>
      ComplicationData.fromJson(asJsonMap(jsonDecode(source), 'complication'));

  @override
  bool operator ==(Object other) =>
      other is ComplicationData &&
      other.type == type &&
      other.text == text &&
      other.title == title &&
      other.contentDescription == contentDescription &&
      other.value == value &&
      other.min == min &&
      other.max == max &&
      other.tapLaunchesApp == tapLaunchesApp;

  @override
  int get hashCode => Object.hash(
    type,
    text,
    title,
    contentDescription,
    value,
    min,
    max,
    tapLaunchesApp,
  );

  @override
  String toString() => 'ComplicationData(${toJsonString()})';
}
