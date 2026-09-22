# wear_os_tiles example — Step Goal

A Wear OS app that logs steps and glasses of water and mirrors them to:

* the plugin's built-in tile (`default`): progress arc, icon, count, a
  launch-action `+250` button and a load-action refresh button;
* a second tile (`water`, `WaterTileService`): material circular progress,
  curved text and a chip;
* the built-in complication (`default`): ranged value;
* a second complication (`water`, `WaterComplicationService`): short text.

Run on a Wear OS emulator or watch (API 30+): `flutter run`. Then long-press
the watch face / swipe to the tiles carousel to add the "Steps" and "Water"
tiles, and pick "Steps goal" / "Water glasses" in a watch face's
complication editor.
