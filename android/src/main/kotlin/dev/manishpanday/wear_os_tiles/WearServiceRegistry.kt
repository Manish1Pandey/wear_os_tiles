package dev.manishpanday.wear_os_tiles

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import android.os.Build
import androidx.wear.tiles.TileService
import androidx.wear.watchface.complications.datasource.ComplicationDataSourceService

/**
 * Maps the string ids used from Dart to the manifest-declared services that
 * render them. A service takes part when it declares the meta-data
 * [META_TILE_ID] / [META_COMPLICATION_ID]; the plugin's own services declare
 * [DEFAULT_ID].
 */
internal object WearServiceRegistry {
    const val META_TILE_ID = "dev.manishpanday.wear_os_tiles.TILE_ID"
    const val META_COMPLICATION_ID = "dev.manishpanday.wear_os_tiles.COMPLICATION_ID"
    const val DEFAULT_ID = "default"

    /** Intent extras put on launch intents created by tiles/complications. */
    const val EXTRA_KIND = "dev.manishpanday.wear_os_tiles.KIND"
    const val EXTRA_TARGET_ID = "dev.manishpanday.wear_os_tiles.TARGET_ID"
    const val EXTRA_CLICKABLE_ID = "dev.manishpanday.wear_os_tiles.CLICKABLE_ID"

    fun tileServices(context: Context): Map<String, ComponentName> =
        query(context, TileService.ACTION_BIND_TILE_PROVIDER, META_TILE_ID)

    fun complicationServices(context: Context): Map<String, ComponentName> = query(
        context,
        ComplicationDataSourceService.ACTION_COMPLICATION_UPDATE_REQUEST,
        META_COMPLICATION_ID,
    )

    /** The id a running service instance serves, read from its meta-data. */
    fun idForService(context: Context, component: ComponentName, key: String): String {
        return try {
            val info = if (Build.VERSION.SDK_INT >= 33) {
                context.packageManager.getServiceInfo(
                    component,
                    PackageManager.ComponentInfoFlags.of(PackageManager.GET_META_DATA.toLong()),
                )
            } else {
                @Suppress("DEPRECATION")
                context.packageManager.getServiceInfo(component, PackageManager.GET_META_DATA)
            }
            info.metaData?.let { idFrom(it, key) } ?: DEFAULT_ID
        } catch (e: PackageManager.NameNotFoundException) {
            DEFAULT_ID
        }
    }

    private fun query(context: Context, action: String, key: String): Map<String, ComponentName> {
        val intent = Intent(action).setPackage(context.packageName)
        val infos: List<ResolveInfo> = if (Build.VERSION.SDK_INT >= 33) {
            context.packageManager.queryIntentServices(
                intent,
                PackageManager.ResolveInfoFlags.of(PackageManager.GET_META_DATA.toLong()),
            )
        } else {
            @Suppress("DEPRECATION")
            context.packageManager.queryIntentServices(intent, PackageManager.GET_META_DATA)
        }
        val result = linkedMapOf<String, ComponentName>()
        for (info in infos) {
            val service = info.serviceInfo ?: continue
            val id = service.metaData?.let { idFrom(it, key) } ?: continue
            result[id] = ComponentName(service.packageName, service.name)
        }
        return result
    }

    /**
     * Reads an id from manifest meta-data. aapt stores purely numeric values
     * as integers, so those are accepted and converted back to strings.
     */
    private fun idFrom(metaData: android.os.Bundle, key: String): String? {
        if (!metaData.containsKey(key)) return null
        metaData.getString(key)?.let { return it }
        val number = metaData.getInt(key, Int.MIN_VALUE)
        return if (number == Int.MIN_VALUE) null else number.toString()
    }

    /** The app's launcher activity, used as the target of launch actions. */
    fun launchActivity(context: Context): ComponentName? =
        context.packageManager.getLaunchIntentForPackage(context.packageName)?.component
}
