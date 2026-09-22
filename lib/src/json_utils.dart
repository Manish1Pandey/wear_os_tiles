import 'dart:ui' show Color;

/// Internal helpers for reading the JSON wire format defensively.
///
/// Every reader throws a [FormatException] naming the offending key, so a
/// corrupt stored layout is reported instead of silently mis-parsed.
Map<String, Object?> asJsonMap(Object? value, String what) {
  if (value is Map) {
    return value.map((key, v) => MapEntry(key.toString(), v));
  }
  throw FormatException('Expected a JSON object for $what, got $value');
}

/// Reads a required string.
String readString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String) return value;
  throw FormatException('Expected string "$key", got $value');
}

/// Reads an optional string.
String? readOptString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null || value is String) return value as String?;
  throw FormatException('Expected string "$key", got $value');
}

/// Reads a required number as double.
double readDouble(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is num) return value.toDouble();
  throw FormatException('Expected number "$key", got $value');
}

/// Reads an optional number as double.
double? readOptDouble(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is num) return value.toDouble();
  throw FormatException('Expected number "$key", got $value');
}

/// Reads an optional integer.
int? readOptInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is int) return value;
  if (value is num && value == value.roundToDouble()) return value.toInt();
  throw FormatException('Expected integer "$key", got $value');
}

/// Reads an optional bool.
bool? readOptBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null || value is bool) return value as bool?;
  throw FormatException('Expected bool "$key", got $value');
}

/// Reads an optional ARGB colour stored as a 32-bit integer.
Color? readOptColor(Map<String, Object?> json, String key) {
  final value = readOptInt(json, key);
  return value == null ? null : Color(value & 0xFFFFFFFF);
}

/// Encodes a colour as a 32-bit ARGB integer.
int colorToJson(Color color) => color.toARGB32();

/// Reads an enum by its [Enum.name].
T readEnum<T extends Enum>(
  Map<String, Object?> json,
  String key,
  List<T> values,
  T fallback,
) {
  final value = json[key];
  if (value == null) return fallback;
  for (final v in values) {
    if (v.name == value) return v;
  }
  throw FormatException('Unknown value "$value" for "$key"');
}

/// Reads a JSON list.
List<Object?> readList(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return const [];
  if (value is List) return value;
  throw FormatException('Expected list "$key", got $value');
}

/// Removes null values so the wire format stays compact.
Map<String, Object?> compact(Map<String, Object?> map) =>
    Map.of(map)..removeWhere((_, v) => v == null);
