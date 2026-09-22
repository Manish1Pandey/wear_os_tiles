package dev.manishpanday.wear_os_tiles_example

import dev.manishpanday.wear_os_tiles.WearComplicationService

/**
 * Second complication data source, bound by manifest meta-data
 * `dev.manishpanday.wear_os_tiles.COMPLICATION_ID = water` to
 * `WearComplications.update('water', ...)` in Dart.
 */
class WaterComplicationService : WearComplicationService()
