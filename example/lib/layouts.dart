import 'package:flutter/painting.dart' show Color;
import 'package:wear_os_tiles/wear_os_tiles.dart';

/// Tile id of the plugin's built-in tile service (used for steps).
const String stepsTileId = WearTiles.defaultTileId;

/// Tile id of `WaterTileService` declared in the example manifest.
const String waterTileId = 'water';

/// Complication id of the plugin's built-in data source (steps, ranged).
const String stepsComplicationId = WearComplications.defaultId;

/// Complication id of `WaterComplicationService` (short text).
const String waterComplicationId = 'water';

/// Clickable ids used by the tiles.
abstract final class TileClicks {
  /// Launch action: open the app and add 250 steps.
  static const String add250 = 'add_250';

  /// Load action: reload the tile; queued for Dart.
  static const String refresh = 'refresh';

  /// Launch action: open the app and log a glass of water.
  static const String addGlass = 'add_glass';

  /// Launch action on the water title: just open the app.
  static const String openWater = 'open_water';
}

const Color _accent = Color(0xFF8AB4F8);
const Color _water = Color(0xFF4FC3F7);
const Color _muted = Color(0xFFAAAAAA);

/// Formats 12345 as "12,345".
String formatSteps(int steps) {
  final digits = steps.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// Steps tile: progress arc around the edge, icon, count, goal and two
/// buttons (launch "+250" and load "refresh").
TileLayout stepsTile({required int steps, required int goal}) {
  final progress = goal <= 0 ? 0.0 : (steps / goal).clamp(0.0, 1.0);
  return TileLayout(
    // Re-render every 30 minutes even without app updates.
    freshness: const Duration(minutes: 30),
    root: TileBox(
      width: TileDimension.expand,
      height: TileDimension.expand,
      children: [
        TileArc.progress(progress: progress, color: _accent, thickness: 6),
        TileColumn(
          children: [
            const TileImage(
              'ic_steps',
              width: TileDimension.dp(22),
              height: TileDimension.dp(22),
              tint: _accent,
            ),
            TileText(
              formatSteps(steps),
              fontSize: 30,
              fontWeight: TileFontWeight.bold,
            ),
            TileText(
              'of ${formatSteps(goal)} steps',
              fontSize: 13,
              color: _muted,
              maxLines: 1,
            ),
            const TileSpacer(height: 8),
            const TileRow(
              children: [
                TileButton(
                  action: TileAction.launch(TileClicks.add250),
                  text: '+250',
                  size: 44,
                  contentDescription: 'Add 250 steps',
                ),
                TileSpacer(width: 8),
                TileButton(
                  action: TileAction.load(TileClicks.refresh),
                  iconResource: 'ic_refresh',
                  style: TileComponentStyle.secondary,
                  size: 44,
                  contentDescription: 'Refresh',
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  );
}

/// Water tile: material progress ring with a gap at 12 o'clock holding a
/// curved label, a count and a chip.
TileLayout waterTile({required int glasses, required int goal}) {
  final progress = goal <= 0 ? 0.0 : (glasses / goal).clamp(0.0, 1.0);
  return TileLayout(
    root: TileBox(
      width: TileDimension.expand,
      height: TileDimension.expand,
      children: [
        TileCircularProgress(
          progress: progress,
          indicatorColor: _water,
          startAngle: 30,
          endAngle: 330,
          contentDescription: '$glasses of $goal glasses',
        ),
        const TileArc(
          anchorAngle: 0,
          anchorType: TileArcAnchor.center,
          children: [ArcText('WATER', color: _water, fontSize: 12)],
        ),
        TileColumn(
          children: [
            TileText(
              '$glasses / $goal',
              fontSize: 26,
              fontWeight: TileFontWeight.medium,
              modifiers: const TileModifiers(
                action: TileAction.launch(TileClicks.openWater),
                contentDescription: 'Open the app',
              ),
            ),
            const TileText('glasses today', fontSize: 12, color: _muted),
            const TileSpacer(height: 10),
            const TileChip(
              label: 'Log a glass',
              action: TileAction.launch(TileClicks.addGlass),
              iconResource: 'ic_water',
              width: TileDimension.dp(140),
            ),
          ],
        ),
      ],
    ),
  );
}

/// Ranged-value complication for steps. The range grows past the goal so
/// the exact count survives a restore via `WearComplications.get`.
ComplicationData stepsComplication({required int steps, required int goal}) {
  final shown = steps >= 1000
      ? '${(steps / 1000).toStringAsFixed(1)}k'
      : '$steps';
  return ComplicationData.rangedValue(
    value: steps.toDouble(),
    max: (steps > goal ? steps : goal).toDouble(),
    text: shown,
    title: 'Steps',
    contentDescription: '$steps of $goal steps',
  );
}

/// Short-text complication for water.
ComplicationData waterComplication({required int glasses, required int goal}) =>
    ComplicationData.shortText(
      text: '$glasses/$goal',
      title: 'Water',
      contentDescription: '$glasses of $goal glasses of water',
    );
