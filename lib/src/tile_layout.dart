import 'dart:convert';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';

import 'json_utils.dart';

/// Version of the JSON wire format shared with the Kotlin renderer.
const int tileWireFormatVersion = 1;

/// Maximum nesting depth accepted by [TileLayout.validate].
///
/// ProtoLayout renderers reject deeper trees; 30 is the documented renderer
/// limit, counting the root element as depth 1.
const int maxTileLayoutDepth = 30;

final RegExp _tileIdPattern = RegExp(r'^[A-Za-z0-9_.\-]{1,64}$');
final RegExp _resourcePattern = RegExp(r'^[a-z][a-z0-9_]*$');

/// Returns true when [id] is a valid tile or complication id: 1-64 characters
/// from `A-Z a-z 0-9 _ . -`.
bool isValidWearId(String id) => _tileIdPattern.hasMatch(id);

/// Thrown when a [TileLayout] (or complication data) fails validation.
///
/// [problems] lists every issue found, each prefixed with a JSON-path-like
/// location such as `root.children[1].action.id`.
class TileLayoutException implements Exception {
  /// Creates an exception carrying the list of validation [problems].
  const TileLayoutException(this.problems);

  /// Every validation problem that was found.
  final List<String> problems;

  @override
  String toString() => 'TileLayoutException:\n  ${problems.join('\n  ')}';
}

/// A complete tile: the root element plus refresh policy.
///
/// Serialised as `{"v":1,"freshnessMs":<int>,"root":{...}}`.
@immutable
class TileLayout {
  /// Creates a tile layout with the given [root] element.
  ///
  /// [freshness] is how often the system should re-request the tile from the
  /// plugin's `TileService` on its own; [Duration.zero] (the default) means
  /// only when the app calls `WearTiles.updateTile`.
  const TileLayout({required this.root, this.freshness = Duration.zero});

  /// The root element of the tile.
  final TileElement root;

  /// Automatic refresh interval; zero disables automatic refresh.
  final Duration freshness;

  /// Converts this layout to its JSON wire format.
  Map<String, Object?> toJson() => {
    'v': tileWireFormatVersion,
    'freshnessMs': freshness.inMilliseconds,
    'root': root.toJson(),
  };

  /// Encodes this layout as a JSON string.
  String toJsonString() => jsonEncode(toJson());

  /// Parses a layout from its JSON wire format.
  ///
  /// Throws [FormatException] if the JSON is malformed or has an unsupported
  /// version.
  factory TileLayout.fromJson(Map<String, Object?> json) {
    final version = readOptInt(json, 'v') ?? tileWireFormatVersion;
    if (version != tileWireFormatVersion) {
      throw FormatException('Unsupported tile layout version $version');
    }
    return TileLayout(
      root: TileElement.fromJson(asJsonMap(json['root'], 'root')),
      freshness: Duration(milliseconds: readOptInt(json, 'freshnessMs') ?? 0),
    );
  }

  /// Parses a layout from a JSON string produced by [toJsonString].
  factory TileLayout.fromJsonString(String source) =>
      TileLayout.fromJson(asJsonMap(jsonDecode(source), 'layout'));

  /// Returns every validation problem; empty when the layout is valid.
  List<String> problems() {
    final v = _Validator();
    if (freshness.isNegative) v.add('freshness', 'must not be negative');
    root._validate(v, 'root', 1);
    return List.unmodifiable(v.problems);
  }

  /// Throws [TileLayoutException] if [problems] is not empty.
  void validate() {
    final found = problems();
    if (found.isNotEmpty) throw TileLayoutException(found);
  }

  /// All action ids used in the layout, in document order.
  List<String> get actionIds {
    final ids = <String>[];
    root._collectActions(ids);
    return ids;
  }

  @override
  bool operator ==(Object other) =>
      other is TileLayout && other.root == root && other.freshness == freshness;

  @override
  int get hashCode => Object.hash(root, freshness);

  @override
  String toString() => 'TileLayout(${toJsonString()})';
}

class _Validator {
  final List<String> problems = [];
  final Set<String> actionIds = {};

  void add(String path, String message) => problems.add('$path: $message');

  void nonNegative(String path, double? value) {
    if (value == null) return;
    if (!value.isFinite || value < 0) {
      add(path, 'must be a finite value >= 0 (got $value)');
    }
  }

  void unit(String path, double value) {
    if (!value.isFinite || value < 0 || value > 1) {
      add(path, 'must be between 0 and 1 (got $value)');
    }
  }

  void positive(String path, double? value) {
    if (value == null) return;
    if (!value.isFinite || value <= 0) {
      add(path, 'must be a finite value > 0 (got $value)');
    }
  }

  void resource(String path, String? name) {
    if (name == null) return;
    if (!_resourcePattern.hasMatch(name)) {
      add(
        path,
        'must be an Android drawable name matching [a-z][a-z0-9_]* '
        '(got "$name")',
      );
    }
  }

  void action(String path, TileAction? action) {
    if (action == null) return;
    final id = action.id;
    if (id.isEmpty) {
      add('$path.id', 'must not be empty');
    } else if (id.length > 64) {
      add('$path.id', 'must be at most 64 characters');
    } else if (!actionIds.add(id)) {
      add('$path.id', 'duplicate action id "$id"');
    }
  }

  void dimension(String path, TileDimension? d, {bool allowWrap = true}) {
    if (d == null) return;
    switch (d.kind) {
      case TileDimensionKind.dp:
        nonNegative(path, d.value);
      case TileDimensionKind.weight:
        positive(path, d.value);
      case TileDimensionKind.wrap:
        if (!allowWrap) add(path, 'wrap is not supported here');
      case TileDimensionKind.expand:
        break;
    }
  }

  void modifiers(String path, TileModifiers? m) {
    if (m == null) return;
    final p = m.padding;
    if (p != null) {
      nonNegative('$path.padding.start', p.start);
      nonNegative('$path.padding.top', p.top);
      nonNegative('$path.padding.end', p.end);
      nonNegative('$path.padding.bottom', p.bottom);
    }
    nonNegative('$path.cornerRadius', m.cornerRadius);
    action('$path.action', m.action);
  }

  void depth(String path, int depth) {
    if (depth > maxTileLayoutDepth) {
      add(path, 'nesting depth $depth exceeds $maxTileLayoutDepth');
    }
  }
}

/// How a clickable element behaves when tapped.
enum TileActionType {
  /// The tile reloads in place. The click is queued and delivered to Dart
  /// the next time the app listens to `WearTiles.clicks`.
  load,

  /// The app's launcher activity opens and the click is delivered to Dart
  /// immediately.
  launch,
}

/// A click action attached to an element, identified by [id].
@immutable
class TileAction {
  /// Creates an action of the given [type].
  const TileAction(this.id, this.type);

  /// A click that reloads the tile in place (ProtoLayout `LoadAction`).
  const TileAction.load(this.id) : type = TileActionType.load;

  /// A click that opens the app (ProtoLayout `LaunchAction`).
  const TileAction.launch(this.id) : type = TileActionType.launch;

  /// Identifier reported back to Dart in `TileClickEvent.clickableId`.
  final String id;

  /// What happens on tap.
  final TileActionType type;

  /// Converts this action to JSON.
  Map<String, Object?> toJson() => {'id': id, 'type': type.name};

  /// Parses an action from JSON.
  factory TileAction.fromJson(Map<String, Object?> json) => TileAction(
    readString(json, 'id'),
    readEnum(json, 'type', TileActionType.values, TileActionType.load),
  );

  @override
  bool operator ==(Object other) =>
      other is TileAction && other.id == id && other.type == type;

  @override
  int get hashCode => Object.hash(id, type);
}

/// Kinds of [TileDimension].
enum TileDimensionKind {
  /// A fixed size in density-independent pixels.
  dp,

  /// Fill the space offered by the parent.
  expand,

  /// Size to content.
  wrap,

  /// Share the remaining space of a Row/Column proportionally.
  weight,
}

/// A width or height of a layout element.
@immutable
class TileDimension {
  const TileDimension._(this.kind, this.value);

  /// A fixed size in dp.
  const TileDimension.dp(double dp) : this._(TileDimensionKind.dp, dp);

  /// A proportional share of the remaining space in a Row or Column.
  const TileDimension.weight(double weight)
    : this._(TileDimensionKind.weight, weight);

  /// Fill the parent.
  static const TileDimension expand = TileDimension._(
    TileDimensionKind.expand,
    0,
  );

  /// Size to content.
  static const TileDimension wrap = TileDimension._(TileDimensionKind.wrap, 0);

  /// The kind of dimension.
  final TileDimensionKind kind;

  /// The dp size or weight; 0 for [expand] and [wrap].
  final double value;

  /// Converts to JSON: `{"dp":n}`, `{"weight":n}`, `"expand"` or `"wrap"`.
  Object toJson() => switch (kind) {
    TileDimensionKind.dp => {'dp': value},
    TileDimensionKind.weight => {'weight': value},
    TileDimensionKind.expand => 'expand',
    TileDimensionKind.wrap => 'wrap',
  };

  /// Parses a dimension from JSON.
  static TileDimension fromJson(Object? json) {
    if (json == 'expand') return expand;
    if (json == 'wrap') return wrap;
    final map = asJsonMap(json, 'dimension');
    if (map.containsKey('dp')) return TileDimension.dp(readDouble(map, 'dp'));
    if (map.containsKey('weight')) {
      return TileDimension.weight(readDouble(map, 'weight'));
    }
    throw FormatException('Unknown dimension $json');
  }

  static TileDimension? _opt(Map<String, Object?> json, String key) =>
      json[key] == null ? null : fromJson(json[key]);

  @override
  bool operator ==(Object other) =>
      other is TileDimension && other.kind == kind && other.value == value;

  @override
  int get hashCode => Object.hash(kind, value);
}

/// Padding in dp around an element's content.
@immutable
class TilePadding {
  /// Creates padding with individual edges.
  const TilePadding({
    this.start = 0,
    this.top = 0,
    this.end = 0,
    this.bottom = 0,
  });

  /// The same padding on every edge.
  const TilePadding.all(double value)
    : start = value,
      top = value,
      end = value,
      bottom = value;

  /// Horizontal and vertical padding.
  const TilePadding.symmetric({double horizontal = 0, double vertical = 0})
    : start = horizontal,
      end = horizontal,
      top = vertical,
      bottom = vertical;

  /// Leading edge padding (RTL aware).
  final double start;

  /// Top padding.
  final double top;

  /// Trailing edge padding (RTL aware).
  final double end;

  /// Bottom padding.
  final double bottom;

  /// Converts to JSON.
  Map<String, Object?> toJson() => {
    'start': start,
    'top': top,
    'end': end,
    'bottom': bottom,
  };

  /// Parses from JSON.
  factory TilePadding.fromJson(Map<String, Object?> json) => TilePadding(
    start: readOptDouble(json, 'start') ?? 0,
    top: readOptDouble(json, 'top') ?? 0,
    end: readOptDouble(json, 'end') ?? 0,
    bottom: readOptDouble(json, 'bottom') ?? 0,
  );

  @override
  bool operator ==(Object other) =>
      other is TilePadding &&
      other.start == start &&
      other.top == top &&
      other.end == end &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(start, top, end, bottom);
}

/// Decoration and behaviour shared by most elements.
@immutable
class TileModifiers {
  /// Creates modifiers; every field is optional.
  const TileModifiers({
    this.padding,
    this.backgroundColor,
    this.cornerRadius,
    this.action,
    this.contentDescription,
  });

  /// Inner padding.
  final TilePadding? padding;

  /// Background fill colour.
  final Color? backgroundColor;

  /// Background corner radius in dp (needs [backgroundColor] to be visible).
  final double? cornerRadius;

  /// Click behaviour.
  final TileAction? action;

  /// Accessibility label read by TalkBack.
  final String? contentDescription;

  /// Converts to JSON.
  Map<String, Object?> toJson() => compact({
    'padding': padding?.toJson(),
    'background': backgroundColor == null
        ? null
        : colorToJson(backgroundColor!),
    'cornerRadius': cornerRadius,
    'action': action?.toJson(),
    'contentDescription': contentDescription,
  });

  /// Parses from JSON.
  factory TileModifiers.fromJson(Map<String, Object?> json) => TileModifiers(
    padding: json['padding'] == null
        ? null
        : TilePadding.fromJson(asJsonMap(json['padding'], 'padding')),
    backgroundColor: readOptColor(json, 'background'),
    cornerRadius: readOptDouble(json, 'cornerRadius'),
    action: json['action'] == null
        ? null
        : TileAction.fromJson(asJsonMap(json['action'], 'action')),
    contentDescription: readOptString(json, 'contentDescription'),
  );

  static TileModifiers? _opt(Map<String, Object?> json) =>
      json['modifiers'] == null
      ? null
      : TileModifiers.fromJson(asJsonMap(json['modifiers'], 'modifiers'));

  @override
  bool operator ==(Object other) =>
      other is TileModifiers &&
      other.padding == padding &&
      other.backgroundColor == backgroundColor &&
      other.cornerRadius == cornerRadius &&
      other.action == action &&
      other.contentDescription == contentDescription;

  @override
  int get hashCode => Object.hash(
    padding,
    backgroundColor,
    cornerRadius,
    action,
    contentDescription,
  );
}

/// Horizontal alignment of children.
enum TileHorizontalAlignment {
  /// Leading edge.
  start,

  /// Centre.
  center,

  /// Trailing edge.
  end,
}

/// Vertical alignment of children.
enum TileVerticalAlignment {
  /// Top.
  top,

  /// Centre.
  center,

  /// Bottom.
  bottom,
}

/// Font weight for text.
enum TileFontWeight {
  /// Regular weight.
  normal,

  /// Medium weight.
  medium,

  /// Bold weight.
  bold,
}

/// Horizontal alignment of multi-line text.
enum TileTextAlign {
  /// Leading edge.
  start,

  /// Centre.
  center,

  /// Trailing edge.
  end,
}

/// How an image is scaled into its bounds.
enum TileContentScale {
  /// Scale uniformly to fit inside the bounds.
  fit,

  /// Scale uniformly to fill the bounds, cropping overflow.
  crop,

  /// Stretch to fill the bounds exactly.
  fillBounds,
}

/// Visual style of a material chip or button.
enum TileComponentStyle {
  /// Primary (filled with the theme's primary colour).
  primary,

  /// Secondary (surface-coloured).
  secondary,
}

String _childPath(String path, int i) => '$path.children[$i]';

/// Base class of every element that can appear in a tile layout.
///
/// Each subclass has a distinct `type` discriminator in JSON.
@immutable
sealed class TileElement {
  const TileElement();

  /// The JSON discriminator of this element.
  String get type;

  /// Converts this element to JSON (includes `"type"`).
  Map<String, Object?> toJson();

  /// Parses any element from JSON, dispatching on `"type"`.
  static TileElement fromJson(Map<String, Object?> json) {
    final type = readString(json, 'type');
    return switch (type) {
      'column' => TileColumn._fromJson(json),
      'row' => TileRow._fromJson(json),
      'box' => TileBox._fromJson(json),
      'text' => TileText._fromJson(json),
      'spacer' => TileSpacer._fromJson(json),
      'image' => TileImage._fromJson(json),
      'arc' => TileArc._fromJson(json),
      'circularProgress' => TileCircularProgress._fromJson(json),
      'chip' => TileChip._fromJson(json),
      'button' => TileButton._fromJson(json),
      _ => throw FormatException('Unknown tile element type "$type"'),
    };
  }

  void _validate(_Validator v, String path, int depth);

  void _collectActions(List<String> ids);
}

List<TileElement> _children(Map<String, Object?> json) => [
  for (final c in readList(json, 'children'))
    TileElement.fromJson(asJsonMap(c, 'child')),
];

void _validateChildren(
  _Validator v,
  String path,
  int depth,
  List<TileElement> children,
) {
  for (var i = 0; i < children.length; i++) {
    children[i]._validate(v, _childPath(path, i), depth + 1);
  }
}

/// Lays out children vertically (ProtoLayout `Column`).
final class TileColumn extends TileElement {
  /// Creates a column.
  const TileColumn({
    required this.children,
    this.horizontalAlignment = TileHorizontalAlignment.center,
    this.width,
    this.height,
    this.modifiers,
  });

  /// Children, top to bottom.
  final List<TileElement> children;

  /// Horizontal alignment of children.
  final TileHorizontalAlignment horizontalAlignment;

  /// Width; wraps content when null.
  final TileDimension? width;

  /// Height; wraps content when null.
  final TileDimension? height;

  /// Decoration and click behaviour.
  final TileModifiers? modifiers;

  @override
  String get type => 'column';

  @override
  Map<String, Object?> toJson() => compact({
    'type': type,
    'children': [for (final c in children) c.toJson()],
    'hAlign': horizontalAlignment.name,
    'width': width?.toJson(),
    'height': height?.toJson(),
    'modifiers': modifiers?.toJson(),
  });

  static TileColumn _fromJson(Map<String, Object?> json) => TileColumn(
    children: _children(json),
    horizontalAlignment: readEnum(
      json,
      'hAlign',
      TileHorizontalAlignment.values,
      TileHorizontalAlignment.center,
    ),
    width: TileDimension._opt(json, 'width'),
    height: TileDimension._opt(json, 'height'),
    modifiers: TileModifiers._opt(json),
  );

  @override
  void _validate(_Validator v, String path, int depth) {
    v.depth(path, depth);
    v.dimension('$path.width', width);
    v.dimension('$path.height', height);
    v.modifiers('$path.modifiers', modifiers);
    _validateChildren(v, path, depth, children);
  }

  @override
  void _collectActions(List<String> ids) {
    if (modifiers?.action != null) ids.add(modifiers!.action!.id);
    for (final c in children) {
      c._collectActions(ids);
    }
  }

  @override
  bool operator ==(Object other) =>
      other is TileColumn &&
      listEquals(other.children, children) &&
      other.horizontalAlignment == horizontalAlignment &&
      other.width == width &&
      other.height == height &&
      other.modifiers == modifiers;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(children),
    horizontalAlignment,
    width,
    height,
    modifiers,
  );
}

/// Lays out children horizontally (ProtoLayout `Row`).
final class TileRow extends TileElement {
  /// Creates a row.
  const TileRow({
    required this.children,
    this.verticalAlignment = TileVerticalAlignment.center,
    this.width,
    this.height,
    this.modifiers,
  });

  /// Children, leading to trailing.
  final List<TileElement> children;

  /// Vertical alignment of children.
  final TileVerticalAlignment verticalAlignment;

  /// Width; wraps content when null.
  final TileDimension? width;

  /// Height; wraps content when null.
  final TileDimension? height;

  /// Decoration and click behaviour.
  final TileModifiers? modifiers;

  @override
  String get type => 'row';

  @override
  Map<String, Object?> toJson() => compact({
    'type': type,
    'children': [for (final c in children) c.toJson()],
    'vAlign': verticalAlignment.name,
    'width': width?.toJson(),
    'height': height?.toJson(),
    'modifiers': modifiers?.toJson(),
  });

  static TileRow _fromJson(Map<String, Object?> json) => TileRow(
    children: _children(json),
    verticalAlignment: readEnum(
      json,
      'vAlign',
      TileVerticalAlignment.values,
      TileVerticalAlignment.center,
    ),
    width: TileDimension._opt(json, 'width'),
    height: TileDimension._opt(json, 'height'),
    modifiers: TileModifiers._opt(json),
  );

  @override
  void _validate(_Validator v, String path, int depth) {
    v.depth(path, depth);
    v.dimension('$path.width', width);
    v.dimension('$path.height', height);
    v.modifiers('$path.modifiers', modifiers);
    _validateChildren(v, path, depth, children);
  }

  @override
  void _collectActions(List<String> ids) {
    if (modifiers?.action != null) ids.add(modifiers!.action!.id);
    for (final c in children) {
      c._collectActions(ids);
    }
  }

  @override
  bool operator ==(Object other) =>
      other is TileRow &&
      listEquals(other.children, children) &&
      other.verticalAlignment == verticalAlignment &&
      other.width == width &&
      other.height == height &&
      other.modifiers == modifiers;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(children),
    verticalAlignment,
    width,
    height,
    modifiers,
  );
}

/// Stacks children on top of each other (ProtoLayout `Box`).
final class TileBox extends TileElement {
  /// Creates a box.
  const TileBox({
    required this.children,
    this.horizontalAlignment = TileHorizontalAlignment.center,
    this.verticalAlignment = TileVerticalAlignment.center,
    this.width,
    this.height,
    this.modifiers,
  });

  /// Children, painted in order (last on top).
  final List<TileElement> children;

  /// Horizontal alignment of children.
  final TileHorizontalAlignment horizontalAlignment;

  /// Vertical alignment of children.
  final TileVerticalAlignment verticalAlignment;

  /// Width; wraps content when null.
  final TileDimension? width;

  /// Height; wraps content when null.
  final TileDimension? height;

  /// Decoration and click behaviour.
  final TileModifiers? modifiers;

  @override
  String get type => 'box';

  @override
  Map<String, Object?> toJson() => compact({
    'type': type,
    'children': [for (final c in children) c.toJson()],
    'hAlign': horizontalAlignment.name,
    'vAlign': verticalAlignment.name,
    'width': width?.toJson(),
    'height': height?.toJson(),
    'modifiers': modifiers?.toJson(),
  });

  static TileBox _fromJson(Map<String, Object?> json) => TileBox(
    children: _children(json),
    horizontalAlignment: readEnum(
      json,
      'hAlign',
      TileHorizontalAlignment.values,
      TileHorizontalAlignment.center,
    ),
    verticalAlignment: readEnum(
      json,
      'vAlign',
      TileVerticalAlignment.values,
      TileVerticalAlignment.center,
    ),
    width: TileDimension._opt(json, 'width'),
    height: TileDimension._opt(json, 'height'),
    modifiers: TileModifiers._opt(json),
  );

  @override
  void _validate(_Validator v, String path, int depth) {
    v.depth(path, depth);
    v.dimension('$path.width', width);
    v.dimension('$path.height', height);
    v.modifiers('$path.modifiers', modifiers);
    _validateChildren(v, path, depth, children);
  }

  @override
  void _collectActions(List<String> ids) {
    if (modifiers?.action != null) ids.add(modifiers!.action!.id);
    for (final c in children) {
      c._collectActions(ids);
    }
  }

  @override
  bool operator ==(Object other) =>
      other is TileBox &&
      listEquals(other.children, children) &&
      other.horizontalAlignment == horizontalAlignment &&
      other.verticalAlignment == verticalAlignment &&
      other.width == width &&
      other.height == height &&
      other.modifiers == modifiers;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(children),
    horizontalAlignment,
    verticalAlignment,
    width,
    height,
    modifiers,
  );
}

/// A run of text (ProtoLayout `Text`).
final class TileText extends TileElement {
  /// Creates a text element.
  const TileText(
    this.text, {
    this.color,
    this.fontSize,
    this.fontWeight = TileFontWeight.normal,
    this.italic = false,
    this.maxLines,
    this.textAlign = TileTextAlign.center,
    this.modifiers,
  });

  /// The text to show.
  final String text;

  /// Text colour; the system default (white) when null.
  final Color? color;

  /// Font size in sp; the system default when null.
  final double? fontSize;

  /// Font weight.
  final TileFontWeight fontWeight;

  /// Whether the text is italic.
  final bool italic;

  /// Maximum number of lines before truncation with an ellipsis.
  final int? maxLines;

  /// Alignment of multi-line text.
  final TileTextAlign textAlign;

  /// Decoration and click behaviour.
  final TileModifiers? modifiers;

  @override
  String get type => 'text';

  @override
  Map<String, Object?> toJson() => compact({
    'type': type,
    'text': text,
    'color': color == null ? null : colorToJson(color!),
    'fontSize': fontSize,
    'fontWeight': fontWeight.name,
    'italic': italic ? true : null,
    'maxLines': maxLines,
    'textAlign': textAlign.name,
    'modifiers': modifiers?.toJson(),
  });

  static TileText _fromJson(Map<String, Object?> json) => TileText(
    readString(json, 'text'),
    color: readOptColor(json, 'color'),
    fontSize: readOptDouble(json, 'fontSize'),
    fontWeight: readEnum(
      json,
      'fontWeight',
      TileFontWeight.values,
      TileFontWeight.normal,
    ),
    italic: readOptBool(json, 'italic') ?? false,
    maxLines: readOptInt(json, 'maxLines'),
    textAlign: readEnum(
      json,
      'textAlign',
      TileTextAlign.values,
      TileTextAlign.center,
    ),
    modifiers: TileModifiers._opt(json),
  );

  @override
  void _validate(_Validator v, String path, int depth) {
    v.depth(path, depth);
    v.positive('$path.fontSize', fontSize);
    if (maxLines != null && maxLines! < 1) {
      v.add('$path.maxLines', 'must be >= 1 (got $maxLines)');
    }
    v.modifiers('$path.modifiers', modifiers);
  }

  @override
  void _collectActions(List<String> ids) {
    if (modifiers?.action != null) ids.add(modifiers!.action!.id);
  }

  @override
  bool operator ==(Object other) =>
      other is TileText &&
      other.text == text &&
      other.color == color &&
      other.fontSize == fontSize &&
      other.fontWeight == fontWeight &&
      other.italic == italic &&
      other.maxLines == maxLines &&
      other.textAlign == textAlign &&
      other.modifiers == modifiers;

  @override
  int get hashCode => Object.hash(
    text,
    color,
    fontSize,
    fontWeight,
    italic,
    maxLines,
    textAlign,
    modifiers,
  );
}

/// Empty space of a fixed size in dp (ProtoLayout `Spacer`).
final class TileSpacer extends TileElement {
  /// Creates a spacer.
  const TileSpacer({this.width = 0, this.height = 0, this.modifiers});

  /// Width in dp.
  final double width;

  /// Height in dp.
  final double height;

  /// Decoration and click behaviour.
  final TileModifiers? modifiers;

  @override
  String get type => 'spacer';

  @override
  Map<String, Object?> toJson() => compact({
    'type': type,
    'width': width,
    'height': height,
    'modifiers': modifiers?.toJson(),
  });

  static TileSpacer _fromJson(Map<String, Object?> json) => TileSpacer(
    width: readOptDouble(json, 'width') ?? 0,
    height: readOptDouble(json, 'height') ?? 0,
    modifiers: TileModifiers._opt(json),
  );

  @override
  void _validate(_Validator v, String path, int depth) {
    v.depth(path, depth);
    v.nonNegative('$path.width', width);
    v.nonNegative('$path.height', height);
    v.modifiers('$path.modifiers', modifiers);
  }

  @override
  void _collectActions(List<String> ids) {
    if (modifiers?.action != null) ids.add(modifiers!.action!.id);
  }

  @override
  bool operator ==(Object other) =>
      other is TileSpacer &&
      other.width == width &&
      other.height == height &&
      other.modifiers == modifiers;

  @override
  int get hashCode => Object.hash(width, height, modifiers);
}

/// An image from a drawable bundled in the Android app (`res/drawable`).
///
/// [resource] is the drawable's resource name, e.g. `ic_steps` for
/// `res/drawable/ic_steps.xml`. Vector drawables and PNGs are supported.
final class TileImage extends TileElement {
  /// Creates an image element.
  const TileImage(
    this.resource, {
    this.width = const TileDimension.dp(24),
    this.height = const TileDimension.dp(24),
    this.contentScale = TileContentScale.fit,
    this.tint,
    this.modifiers,
  });

  /// Android drawable resource name.
  final String resource;

  /// Width (dp, expand or weight; not wrap).
  final TileDimension width;

  /// Height (dp, expand or weight; not wrap).
  final TileDimension height;

  /// Scaling mode.
  final TileContentScale contentScale;

  /// Optional tint applied to the image.
  final Color? tint;

  /// Decoration and click behaviour.
  final TileModifiers? modifiers;

  @override
  String get type => 'image';

  @override
  Map<String, Object?> toJson() => compact({
    'type': type,
    'resource': resource,
    'width': width.toJson(),
    'height': height.toJson(),
    'contentScale': contentScale.name,
    'tint': tint == null ? null : colorToJson(tint!),
    'modifiers': modifiers?.toJson(),
  });

  static TileImage _fromJson(Map<String, Object?> json) => TileImage(
    readString(json, 'resource'),
    width: TileDimension._opt(json, 'width') ?? const TileDimension.dp(24),
    height: TileDimension._opt(json, 'height') ?? const TileDimension.dp(24),
    contentScale: readEnum(
      json,
      'contentScale',
      TileContentScale.values,
      TileContentScale.fit,
    ),
    tint: readOptColor(json, 'tint'),
    modifiers: TileModifiers._opt(json),
  );

  @override
  void _validate(_Validator v, String path, int depth) {
    v.depth(path, depth);
    v.resource('$path.resource', resource);
    v.dimension('$path.width', width, allowWrap: false);
    v.dimension('$path.height', height, allowWrap: false);
    v.modifiers('$path.modifiers', modifiers);
  }

  @override
  void _collectActions(List<String> ids) {
    if (modifiers?.action != null) ids.add(modifiers!.action!.id);
  }

  @override
  bool operator ==(Object other) =>
      other is TileImage &&
      other.resource == resource &&
      other.width == width &&
      other.height == height &&
      other.contentScale == contentScale &&
      other.tint == tint &&
      other.modifiers == modifiers;

  @override
  int get hashCode =>
      Object.hash(resource, width, height, contentScale, tint, modifiers);
}

/// Where an arc's content is anchored relative to [TileArc.anchorAngle].
enum TileArcAnchor {
  /// Content starts at the anchor angle.
  start,

  /// Content is centred on the anchor angle.
  center,

  /// Content ends at the anchor angle.
  end,
}

/// Round-screen arc container (ProtoLayout `Arc`).
///
/// Children are drawn one after another along a circle, clockwise, starting
/// from [anchorAngle] (0 degrees = 12 o'clock).
final class TileArc extends TileElement {
  /// Creates an arc with explicit children.
  const TileArc({
    required this.children,
    this.anchorAngle = 0,
    this.anchorType = TileArcAnchor.start,
    this.modifiers,
  });

  /// A full-circle progress ring: a [progress] (0..1) segment in [color]
  /// followed by the remaining track in [trackColor].
  factory TileArc.progress({
    required double progress,
    required Color color,
    Color trackColor = const Color(0xFF333333),
    double thickness = 6,
    double anchorAngle = 0,
    TileModifiers? modifiers,
  }) {
    final done = (progress.isFinite ? progress : 0).clamp(0.0, 1.0) * 360.0;
    return TileArc(
      anchorAngle: anchorAngle,
      modifiers: modifiers,
      children: [
        if (done > 0)
          ArcLine(
            length: done,
            thickness: thickness,
            color: color,
            strokeCap: ArcStrokeCap.round,
          ),
        if (done < 360)
          ArcLine(length: 360 - done, thickness: thickness, color: trackColor),
      ],
    );
  }

  /// Arc children.
  final List<TileArcElement> children;

  /// Anchor angle in degrees clockwise from 12 o'clock.
  final double anchorAngle;

  /// How content is placed relative to [anchorAngle].
  final TileArcAnchor anchorType;

  /// Decoration and click behaviour.
  final TileModifiers? modifiers;

  @override
  String get type => 'arc';

  @override
  Map<String, Object?> toJson() => compact({
    'type': type,
    'children': [for (final c in children) c.toJson()],
    'anchorAngle': anchorAngle,
    'anchorType': anchorType.name,
    'modifiers': modifiers?.toJson(),
  });

  static TileArc _fromJson(Map<String, Object?> json) => TileArc(
    children: [
      for (final c in readList(json, 'children'))
        TileArcElement.fromJson(asJsonMap(c, 'arc child')),
    ],
    anchorAngle: readOptDouble(json, 'anchorAngle') ?? 0,
    anchorType: readEnum(
      json,
      'anchorType',
      TileArcAnchor.values,
      TileArcAnchor.start,
    ),
    modifiers: TileModifiers._opt(json),
  );

  @override
  void _validate(_Validator v, String path, int depth) {
    v.depth(path, depth);
    if (!anchorAngle.isFinite) v.add('$path.anchorAngle', 'must be finite');
    v.modifiers('$path.modifiers', modifiers);
    var total = 0.0;
    for (var i = 0; i < children.length; i++) {
      final p = _childPath(path, i);
      final c = children[i];
      c._validate(v, p);
      total += c._angularLength;
    }
    if (total > 360.0001) {
      v.add('$path.children', 'total arc length $total exceeds 360 degrees');
    }
  }

  @override
  void _collectActions(List<String> ids) {
    if (modifiers?.action != null) ids.add(modifiers!.action!.id);
  }

  @override
  bool operator ==(Object other) =>
      other is TileArc &&
      listEquals(other.children, children) &&
      other.anchorAngle == anchorAngle &&
      other.anchorType == anchorType &&
      other.modifiers == modifiers;

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(children), anchorAngle, anchorType, modifiers);
}

/// Line end style for [ArcLine].
enum ArcStrokeCap {
  /// Flat ends.
  butt,

  /// Rounded ends.
  round,
}

/// An element that can be placed inside a [TileArc].
@immutable
sealed class TileArcElement {
  const TileArcElement();

  /// Converts to JSON (includes `"type"`).
  Map<String, Object?> toJson();

  /// Parses any arc child from JSON.
  static TileArcElement fromJson(Map<String, Object?> json) {
    final type = readString(json, 'type');
    return switch (type) {
      'arcLine' => ArcLine(
        length: readDouble(json, 'length'),
        thickness: readOptDouble(json, 'thickness') ?? 4,
        color: readOptColor(json, 'color') ?? const Color(0xFFFFFFFF),
        strokeCap: readEnum(
          json,
          'strokeCap',
          ArcStrokeCap.values,
          ArcStrokeCap.butt,
        ),
      ),
      'arcSpacer' => ArcSpacer(length: readDouble(json, 'length')),
      'arcText' => ArcText(
        readString(json, 'text'),
        color: readOptColor(json, 'color'),
        fontSize: readOptDouble(json, 'fontSize'),
      ),
      _ => throw FormatException('Unknown arc element type "$type"'),
    };
  }

  double get _angularLength;

  void _validate(_Validator v, String path);
}

/// A coloured segment of an arc (ProtoLayout `ArcLine`).
final class ArcLine extends TileArcElement {
  /// Creates an arc line of [length] degrees.
  const ArcLine({
    required this.length,
    this.thickness = 4,
    this.color = const Color(0xFFFFFFFF),
    this.strokeCap = ArcStrokeCap.butt,
  });

  /// Sweep in degrees (0..360).
  final double length;

  /// Stroke thickness in dp.
  final double thickness;

  /// Line colour.
  final Color color;

  /// End cap style.
  final ArcStrokeCap strokeCap;

  @override
  Map<String, Object?> toJson() => {
    'type': 'arcLine',
    'length': length,
    'thickness': thickness,
    'color': colorToJson(color),
    'strokeCap': strokeCap.name,
  };

  @override
  double get _angularLength => length.isFinite ? length : 0;

  @override
  void _validate(_Validator v, String path) {
    if (!length.isFinite || length < 0 || length > 360) {
      v.add('$path.length', 'must be between 0 and 360 degrees (got $length)');
    }
    v.nonNegative('$path.thickness', thickness);
  }

  @override
  bool operator ==(Object other) =>
      other is ArcLine &&
      other.length == length &&
      other.thickness == thickness &&
      other.color == color &&
      other.strokeCap == strokeCap;

  @override
  int get hashCode => Object.hash(length, thickness, color, strokeCap);
}

/// An empty gap along an arc (ProtoLayout `ArcSpacer`).
final class ArcSpacer extends TileArcElement {
  /// Creates a gap of [length] degrees.
  const ArcSpacer({required this.length});

  /// Gap in degrees (0..360).
  final double length;

  @override
  Map<String, Object?> toJson() => {'type': 'arcSpacer', 'length': length};

  @override
  double get _angularLength => length.isFinite ? length : 0;

  @override
  void _validate(_Validator v, String path) {
    if (!length.isFinite || length < 0 || length > 360) {
      v.add('$path.length', 'must be between 0 and 360 degrees (got $length)');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ArcSpacer && other.length == length;

  @override
  int get hashCode => length.hashCode;
}

/// Text that follows the curve of an arc (ProtoLayout `ArcText`).
final class ArcText extends TileArcElement {
  /// Creates curved text.
  const ArcText(this.text, {this.color, this.fontSize});

  /// The text.
  final String text;

  /// Text colour.
  final Color? color;

  /// Font size in sp.
  final double? fontSize;

  @override
  Map<String, Object?> toJson() => compact({
    'type': 'arcText',
    'text': text,
    'color': color == null ? null : colorToJson(color!),
    'fontSize': fontSize,
  });

  // Curved text length depends on font metrics; it is not counted towards
  // the 360 degree budget.
  @override
  double get _angularLength => 0;

  @override
  void _validate(_Validator v, String path) {
    v.positive('$path.fontSize', fontSize);
  }

  @override
  bool operator ==(Object other) =>
      other is ArcText &&
      other.text == text &&
      other.color == color &&
      other.fontSize == fontSize;

  @override
  int get hashCode => Object.hash(text, color, fontSize);
}

/// Material circular progress ring (protolayout-material
/// `CircularProgressIndicator`). It hugs the edge of the round screen.
final class TileCircularProgress extends TileElement {
  /// Creates a progress indicator showing [progress] (0..1).
  const TileCircularProgress({
    required this.progress,
    this.indicatorColor,
    this.trackColor,
    this.strokeWidth,
    this.startAngle,
    this.endAngle,
    this.contentDescription,
  });

  /// Progress between 0 and 1.
  final double progress;

  /// Colour of the filled part; theme primary when null.
  final Color? indicatorColor;

  /// Colour of the track; theme default when null.
  final Color? trackColor;

  /// Stroke width in dp.
  final double? strokeWidth;

  /// Start angle in degrees (0 = 12 o'clock).
  final double? startAngle;

  /// End angle in degrees.
  final double? endAngle;

  /// Accessibility label.
  final String? contentDescription;

  @override
  String get type => 'circularProgress';

  @override
  Map<String, Object?> toJson() => compact({
    'type': type,
    'progress': progress,
    'indicatorColor': indicatorColor == null
        ? null
        : colorToJson(indicatorColor!),
    'trackColor': trackColor == null ? null : colorToJson(trackColor!),
    'strokeWidth': strokeWidth,
    'startAngle': startAngle,
    'endAngle': endAngle,
    'contentDescription': contentDescription,
  });

  static TileCircularProgress _fromJson(Map<String, Object?> json) =>
      TileCircularProgress(
        progress: readDouble(json, 'progress'),
        indicatorColor: readOptColor(json, 'indicatorColor'),
        trackColor: readOptColor(json, 'trackColor'),
        strokeWidth: readOptDouble(json, 'strokeWidth'),
        startAngle: readOptDouble(json, 'startAngle'),
        endAngle: readOptDouble(json, 'endAngle'),
        contentDescription: readOptString(json, 'contentDescription'),
      );

  @override
  void _validate(_Validator v, String path, int depth) {
    v.depth(path, depth);
    v.unit('$path.progress', progress);
    v.positive('$path.strokeWidth', strokeWidth);
    if (startAngle != null && !startAngle!.isFinite) {
      v.add('$path.startAngle', 'must be finite');
    }
    if (endAngle != null && !endAngle!.isFinite) {
      v.add('$path.endAngle', 'must be finite');
    }
    if (startAngle != null && endAngle != null && endAngle! <= startAngle!) {
      v.add('$path.endAngle', 'must be greater than startAngle');
    }
  }

  @override
  void _collectActions(List<String> ids) {}

  @override
  bool operator ==(Object other) =>
      other is TileCircularProgress &&
      other.progress == progress &&
      other.indicatorColor == indicatorColor &&
      other.trackColor == trackColor &&
      other.strokeWidth == strokeWidth &&
      other.startAngle == startAngle &&
      other.endAngle == endAngle &&
      other.contentDescription == contentDescription;

  @override
  int get hashCode => Object.hash(
    progress,
    indicatorColor,
    trackColor,
    strokeWidth,
    startAngle,
    endAngle,
    contentDescription,
  );
}

/// Material chip: a pill-shaped, clickable label with optional secondary
/// label and icon (protolayout-material `Chip`).
final class TileChip extends TileElement {
  /// Creates a chip.
  const TileChip({
    required this.label,
    required this.action,
    this.secondaryLabel,
    this.iconResource,
    this.style = TileComponentStyle.primary,
    this.backgroundColor,
    this.contentColor,
    this.width,
    this.contentDescription,
  });

  /// Primary label.
  final String label;

  /// Click behaviour (required: chips are always clickable).
  final TileAction action;

  /// Optional second line.
  final String? secondaryLabel;

  /// Optional icon: Android drawable resource name.
  final String? iconResource;

  /// Colour style when no explicit colours are set.
  final TileComponentStyle style;

  /// Overrides the style's background colour.
  final Color? backgroundColor;

  /// Overrides the style's content (label and icon) colour.
  final Color? contentColor;

  /// Width (dp or expand); the material default when null.
  final TileDimension? width;

  /// Accessibility label; defaults to the label text.
  final String? contentDescription;

  @override
  String get type => 'chip';

  @override
  Map<String, Object?> toJson() => compact({
    'type': type,
    'label': label,
    'action': action.toJson(),
    'secondaryLabel': secondaryLabel,
    'icon': iconResource,
    'style': style.name,
    'backgroundColor': backgroundColor == null
        ? null
        : colorToJson(backgroundColor!),
    'contentColor': contentColor == null ? null : colorToJson(contentColor!),
    'width': width?.toJson(),
    'contentDescription': contentDescription,
  });

  static TileChip _fromJson(Map<String, Object?> json) => TileChip(
    label: readString(json, 'label'),
    action: TileAction.fromJson(asJsonMap(json['action'], 'action')),
    secondaryLabel: readOptString(json, 'secondaryLabel'),
    iconResource: readOptString(json, 'icon'),
    style: readEnum(
      json,
      'style',
      TileComponentStyle.values,
      TileComponentStyle.primary,
    ),
    backgroundColor: readOptColor(json, 'backgroundColor'),
    contentColor: readOptColor(json, 'contentColor'),
    width: TileDimension._opt(json, 'width'),
    contentDescription: readOptString(json, 'contentDescription'),
  );

  @override
  void _validate(_Validator v, String path, int depth) {
    v.depth(path, depth);
    if (label.isEmpty) v.add('$path.label', 'must not be empty');
    v.resource('$path.icon', iconResource);
    v.action('$path.action', action);
    final w = width;
    if (w != null &&
        w.kind != TileDimensionKind.dp &&
        w.kind != TileDimensionKind.expand) {
      v.add('$path.width', 'must be dp or expand');
    }
    v.dimension('$path.width', width);
  }

  @override
  void _collectActions(List<String> ids) => ids.add(action.id);

  @override
  bool operator ==(Object other) =>
      other is TileChip &&
      other.label == label &&
      other.action == action &&
      other.secondaryLabel == secondaryLabel &&
      other.iconResource == iconResource &&
      other.style == style &&
      other.backgroundColor == backgroundColor &&
      other.contentColor == contentColor &&
      other.width == width &&
      other.contentDescription == contentDescription;

  @override
  int get hashCode => Object.hash(
    label,
    action,
    secondaryLabel,
    iconResource,
    style,
    backgroundColor,
    contentColor,
    width,
    contentDescription,
  );
}

/// Material circular button showing exactly one of [text], [iconResource] or
/// [imageResource] (protolayout-material `Button`).
final class TileButton extends TileElement {
  /// Creates a button.
  const TileButton({
    required this.action,
    this.text,
    this.iconResource,
    this.imageResource,
    this.style = TileComponentStyle.primary,
    this.backgroundColor,
    this.contentColor,
    this.size,
    this.contentDescription,
  });

  /// Click behaviour.
  final TileAction action;

  /// Short text content (1-3 characters fit best).
  final String? text;

  /// Icon content: Android drawable resource name (tinted).
  final String? iconResource;

  /// Image content: Android drawable resource name (untinted, cropped).
  final String? imageResource;

  /// Colour style when no explicit colours are set.
  final TileComponentStyle style;

  /// Overrides the style's background colour.
  final Color? backgroundColor;

  /// Overrides the style's content colour.
  final Color? contentColor;

  /// Diameter in dp; the material default (52dp) when null.
  final double? size;

  /// Accessibility label; strongly recommended for icon/image buttons.
  final String? contentDescription;

  @override
  String get type => 'button';

  @override
  Map<String, Object?> toJson() => compact({
    'type': type,
    'action': action.toJson(),
    'text': text,
    'icon': iconResource,
    'image': imageResource,
    'style': style.name,
    'backgroundColor': backgroundColor == null
        ? null
        : colorToJson(backgroundColor!),
    'contentColor': contentColor == null ? null : colorToJson(contentColor!),
    'size': size,
    'contentDescription': contentDescription,
  });

  static TileButton _fromJson(Map<String, Object?> json) => TileButton(
    action: TileAction.fromJson(asJsonMap(json['action'], 'action')),
    text: readOptString(json, 'text'),
    iconResource: readOptString(json, 'icon'),
    imageResource: readOptString(json, 'image'),
    style: readEnum(
      json,
      'style',
      TileComponentStyle.values,
      TileComponentStyle.primary,
    ),
    backgroundColor: readOptColor(json, 'backgroundColor'),
    contentColor: readOptColor(json, 'contentColor'),
    size: readOptDouble(json, 'size'),
    contentDescription: readOptString(json, 'contentDescription'),
  );

  @override
  void _validate(_Validator v, String path, int depth) {
    v.depth(path, depth);
    final count = [
      text,
      iconResource,
      imageResource,
    ].where((e) => e != null).length;
    if (count != 1) {
      v.add(path, 'exactly one of text, icon or image must be set');
    }
    if (text != null && text!.isEmpty) v.add('$path.text', 'must not be empty');
    v.resource('$path.icon', iconResource);
    v.resource('$path.image', imageResource);
    v.positive('$path.size', size);
    v.action('$path.action', action);
  }

  @override
  void _collectActions(List<String> ids) => ids.add(action.id);

  @override
  bool operator ==(Object other) =>
      other is TileButton &&
      other.action == action &&
      other.text == text &&
      other.iconResource == iconResource &&
      other.imageResource == imageResource &&
      other.style == style &&
      other.backgroundColor == backgroundColor &&
      other.contentColor == contentColor &&
      other.size == size &&
      other.contentDescription == contentDescription;

  @override
  int get hashCode => Object.hash(
    action,
    text,
    iconResource,
    imageResource,
    style,
    backgroundColor,
    contentColor,
    size,
    contentDescription,
  );
}
