import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wear_os_tiles/wear_os_tiles.dart';

import 'layouts.dart';

void main() => runApp(const StepGoalApp());

/// Wear OS example: a manual step and water logger whose state is mirrored
/// to two tiles and two complications.
class StepGoalApp extends StatelessWidget {
  /// Creates the app.
  const StepGoalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Step Goal',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF8AB4F8),
        scaffoldBackgroundColor: Colors.black,
        visualDensity: VisualDensity.compact,
      ),
      home: const StepGoalHome(),
    );
  }
}

/// Main screen.
class StepGoalHome extends StatefulWidget {
  /// Creates the screen.
  const StepGoalHome({super.key});

  @override
  State<StepGoalHome> createState() => _StepGoalHomeState();
}

class _StepGoalHomeState extends State<StepGoalHome> {
  static const int _stepGoal = 10000;
  static const int _waterGoal = 8;

  int _steps = 0;
  int _glasses = 0;
  bool _ready = false;
  String? _error;
  List<String> _tileIds = const [];
  List<String> _complicationIds = const [];
  final List<String> _log = [];
  final List<StreamSubscription<Object>> _subs = [];

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      // Restore the last pushed values so the app, tiles and complications
      // agree after a restart.
      final steps = await WearComplications.get(stepsComplicationId);
      final water = await WearComplications.get(waterComplicationId);
      final tileIds = await WearTiles.registeredTileIds();
      final complicationIds = await WearComplications.registeredIds();
      if (!mounted) return;
      setState(() {
        _steps = steps?.value?.round() ?? 0;
        _glasses = int.tryParse(water?.text?.split('/').first ?? '') ?? 0;
        _tileIds = tileIds;
        _complicationIds = complicationIds;
        _ready = true;
      });
      // Subscribe after restoring; clicks that launched the app are buffered
      // natively until this point.
      _subs
        ..add(WearTiles.clicks.listen(_onTileClick))
        ..add(WearComplications.taps.listen(_onComplicationTap));
      await _push();
    } on PlatformException catch (e) {
      if (mounted) setState(() => _error = e.message ?? e.code);
    }
  }

  void _onTileClick(TileClickEvent event) {
    _addLog(
      'tile ${event.tileId}: ${event.clickableId} (${event.source.name})',
    );
    switch (event.clickableId) {
      case TileClicks.add250:
        _changeSteps(250);
      case TileClicks.addGlass:
        _changeGlasses(1);
    }
  }

  void _onComplicationTap(ComplicationTapEvent event) =>
      _addLog('complication ${event.complicationId} tapped');

  void _addLog(String line) {
    final time = TimeOfDay.now().format(context);
    setState(() {
      _log.insert(0, '$time $line');
      if (_log.length > 8) _log.removeLast();
    });
  }

  void _changeSteps(int delta) {
    setState(() => _steps = (_steps + delta).clamp(0, 999999));
    _push();
  }

  void _changeGlasses(int delta) {
    setState(() => _glasses = (_glasses + delta).clamp(0, 99));
    _push();
  }

  void _reset() {
    setState(() {
      _steps = 0;
      _glasses = 0;
    });
    _push();
  }

  Future<void> _push() async {
    try {
      await WearTiles.updateTile(
        stepsTileId,
        stepsTile(steps: _steps, goal: _stepGoal),
      );
      await WearTiles.updateTile(
        waterTileId,
        waterTile(glasses: _glasses, goal: _waterGoal),
      );
      await WearComplications.update(
        stepsComplicationId,
        stepsComplication(steps: _steps, goal: _stepGoal),
      );
      await WearComplications.update(
        waterComplicationId,
        waterComplication(glasses: _glasses, goal: _waterGoal),
      );
      if (mounted && _error != null) setState(() => _error = null);
    } on PlatformException catch (e) {
      if (mounted) setState(() => _error = e.message ?? e.code);
    } on TileLayoutException catch (e) {
      if (mounted) setState(() => _error = e.problems.join('\n'));
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!_ready && _error == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      body: ListView(
        // Generous horizontal padding keeps content inside a round screen.
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
        children: [
          Text(
            formatSteps(_steps),
            key: const Key('steps'),
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium,
          ),
          Text(
            'of ${formatSteps(_stepGoal)} steps',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              FilledButton(
                key: const Key('add250'),
                onPressed: () => _changeSteps(250),
                child: const Text('+250'),
              ),
              FilledButton.tonal(
                onPressed: () => _changeSteps(1000),
                child: const Text('+1k'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '$_glasses / $_waterGoal glasses',
            key: const Key('water'),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'Remove a glass',
                onPressed: () => _changeGlasses(-1),
                icon: const Icon(Icons.remove),
              ),
              IconButton.filled(
                tooltip: 'Log a glass',
                onPressed: () => _changeGlasses(1),
                icon: const Icon(Icons.water_drop),
              ),
            ],
          ),
          TextButton(onPressed: _reset, child: const Text('Reset day')),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                _error!,
                key: const Key('error'),
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          const Divider(),
          Text(
            'Tiles: ${_tileIds.join(', ')}\n'
            'Complications: ${_complicationIds.join(', ')}',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Text(
            _log.isEmpty
                ? 'Tap a tile button or complication to see events here.'
                : _log.join('\n'),
            key: const Key('log'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
