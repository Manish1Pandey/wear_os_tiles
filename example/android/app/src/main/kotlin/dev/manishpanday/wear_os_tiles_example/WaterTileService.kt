package dev.manishpanday.wear_os_tiles_example

import dev.manishpanday.wear_os_tiles.WearTileService

/**
 * Second tile of the example. The whole implementation is inherited; the
 * manifest meta-data `dev.manishpanday.wear_os_tiles.TILE_ID = water` binds it to
 * `WearTiles.updateTile('water', ...)` in Dart.
 */
class WaterTileService : WearTileService()
