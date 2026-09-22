package dev.manishpanday.wear_os_tiles

import android.content.ComponentName
import android.content.res.Resources
import android.util.Log
import androidx.concurrent.futures.CallbackToFutureAdapter
import androidx.wear.protolayout.ActionBuilders
import androidx.wear.protolayout.ColorBuilders.argb
import androidx.wear.protolayout.DimensionBuilders.expand
import androidx.wear.protolayout.LayoutElementBuilders
import androidx.wear.protolayout.LayoutElementBuilders.LayoutElement
import androidx.wear.protolayout.ModifiersBuilders
import androidx.wear.protolayout.ResourceBuilders
import androidx.wear.protolayout.TimelineBuilders
import androidx.wear.tiles.RequestBuilders
import androidx.wear.tiles.TileBuilders
import androidx.wear.tiles.TileService
import com.google.common.util.concurrent.ListenableFuture

/**
 * Generic tile provider that renders the layout Dart stored with
 * `WearTiles.updateTile`.
 *
 * The plugin manifest registers this class for tile id `default`. To offer
 * more tiles, declare a subclass in your app (e.g.
 * `class StepsTileService : WearTileService()`) with meta-data
 * `dev.manishpanday.wear_os_tiles.TILE_ID` set to the id used from Dart.
 */
open class WearTileService : TileService() {

    /** The Dart-side tile id this service renders (from manifest meta-data). */
    protected val tileId: String by lazy {
        WearServiceRegistry.idForService(
            this,
            ComponentName(this, javaClass),
            WearServiceRegistry.META_TILE_ID,
        )
    }

    override fun onTileRequest(
        requestParams: RequestBuilders.TileRequest,
    ): ListenableFuture<TileBuilders.Tile> = CallbackToFutureAdapter.getFuture { completer ->
        try {
            completer.set(buildTile(requestParams))
        } catch (e: Exception) {
            completer.setException(e)
        }
        "WearTileService.onTileRequest($tileId)"
    }

    override fun onTileResourcesRequest(
        requestParams: RequestBuilders.ResourcesRequest,
    ): ListenableFuture<ResourceBuilders.Resources> = CallbackToFutureAdapter.getFuture { completer ->
        try {
            completer.set(buildResources(requestParams.version))
        } catch (e: Exception) {
            completer.setException(e)
        }
        "WearTileService.onTileResourcesRequest($tileId)"
    }

    private fun buildTile(request: RequestBuilders.TileRequest): TileBuilders.Tile {
        val json = WearTilesStore.getTile(this, tileId)
        val device = request.deviceConfiguration
        var freshness = 0L
        val root: LayoutElement = if (json == null) {
            emptyStateLayout()
        } else {
            try {
                val parsed = TileLayoutParser(
                    this,
                    device,
                    tileId,
                    WearServiceRegistry.launchActivity(this),
                ).parse(json)
                recordLoadClick(request, parsed)
                freshness = parsed.freshnessMillis
                parsed.root
            } catch (e: Exception) {
                // TileLayoutFormatException, JSONException or a builder rejecting a value.
                Log.e(TAG, "Stored layout for tile '$tileId' is invalid: ${e.message}")
                emptyStateLayout()
            }
        }
        return TileBuilders.Tile.Builder()
            .setResourcesVersion(resourcesVersion(json))
            .setFreshnessIntervalMillis(freshness)
            .setTileTimeline(TimelineBuilders.Timeline.fromLayoutElement(root))
            .build()
    }

    private fun recordLoadClick(request: RequestBuilders.TileRequest, parsed: ParsedTile) {
        val clicked = request.currentState?.lastClickableId.orEmpty()
        if (clicked.isEmpty() || parsed.actions[clicked] != "load") return
        WearTilesStore.recordEvent(
            this,
            WearEvent(
                kind = WearEvent.KIND_TILE,
                targetId = tileId,
                clickableId = clicked,
                source = WearEvent.SOURCE_LOAD,
                timestampMs = System.currentTimeMillis(),
            ),
        )
    }

    private fun buildResources(version: String): ResourceBuilders.Resources {
        val builder = ResourceBuilders.Resources.Builder().setVersion(version)
        val json = WearTilesStore.getTile(this, tileId) ?: return builder.build()
        for (name in TileLayoutParser.collectImageResources(json)) {
            val resId = drawableId(name)
            if (resId == 0) {
                Log.w(TAG, "Tile '$tileId' references missing drawable '$name'")
                continue
            }
            builder.addIdToImageMapping(
                name,
                ResourceBuilders.ImageResource.Builder()
                    .setAndroidResourceByResId(
                        ResourceBuilders.AndroidImageResourceByResId.Builder()
                            .setResourceId(resId)
                            .build(),
                    )
                    .build(),
            )
        }
        return builder.build()
    }

    // Drawables are addressed by name from Dart, so a name lookup is required.
    @android.annotation.SuppressLint("DiscouragedApi")
    private fun drawableId(name: String): Int = try {
        resources.getIdentifier(name, "drawable", packageName)
    } catch (e: Resources.NotFoundException) {
        0
    }

    /** Shown until Dart stores a layout; tapping opens the app. */
    private fun emptyStateLayout(): LayoutElement {
        val text = LayoutElementBuilders.Text.Builder()
            .setText(getString(R.string.wear_os_tiles_empty_tile_text))
            .setMaxLines(3)
            .setMultilineAlignment(LayoutElementBuilders.TEXT_ALIGN_CENTER)
            .setFontStyle(
                LayoutElementBuilders.FontStyle.Builder()
                    .setColor(argb(0xFFFFFFFF.toInt()))
                    .build(),
            )
            .build()
        val modifiers = ModifiersBuilders.Modifiers.Builder()
        WearServiceRegistry.launchActivity(this)?.let { launch ->
            modifiers.setClickable(
                ModifiersBuilders.Clickable.Builder()
                    .setId(EMPTY_STATE_CLICK_ID)
                    .setOnClick(
                        ActionBuilders.LaunchAction.Builder()
                            .setAndroidActivity(
                                ActionBuilders.AndroidActivity.Builder()
                                    .setPackageName(launch.packageName)
                                    .setClassName(launch.className)
                                    .build(),
                            )
                            .build(),
                    )
                    .build(),
            )
        }
        return LayoutElementBuilders.Box.Builder()
            .setWidth(expand())
            .setHeight(expand())
            .setModifiers(modifiers.build())
            .addContent(text)
            .build()
    }

    private fun resourcesVersion(json: String?): String =
        if (json == null) "empty" else Integer.toHexString(json.hashCode())

    private companion object {
        const val TAG = "WearTileService"
        const val EMPTY_STATE_CLICK_ID = "dev.manishpanday.wear_os_tiles.open_app"
    }
}
