package dev.manishpanday.wear_os_tiles

import android.app.PendingIntent
import android.content.ComponentName
import android.content.Intent
import android.util.Log
import androidx.wear.watchface.complications.data.ComplicationData
import androidx.wear.watchface.complications.data.ComplicationType
import androidx.wear.watchface.complications.data.NoDataComplicationData
import androidx.wear.watchface.complications.datasource.ComplicationDataSourceService
import androidx.wear.watchface.complications.datasource.ComplicationRequest

/**
 * Generic complication data source serving the data Dart stored with
 * `WearComplications.update`. Supports SHORT_TEXT, LONG_TEXT and
 * RANGED_VALUE; it is push-only (the manifest sets
 * `UPDATE_PERIOD_SECONDS` to 0) because updates come from Dart.
 *
 * The plugin manifest registers this class for complication id `default`.
 * Declare subclasses with meta-data
 * `dev.manishpanday.wear_os_tiles.COMPLICATION_ID` for more data sources.
 */
open class WearComplicationService : ComplicationDataSourceService() {

    /** The Dart-side complication id this data source serves. */
    protected val complicationId: String by lazy {
        WearServiceRegistry.idForService(
            this,
            ComponentName(this, javaClass),
            WearServiceRegistry.META_COMPLICATION_ID,
        )
    }

    override fun onComplicationRequest(
        request: ComplicationRequest,
        listener: ComplicationRequestListener,
    ) {
        val json = WearTilesStore.getComplication(this, complicationId)
        val data: ComplicationData = if (json == null) {
            NoDataComplicationData()
        } else {
            try {
                ComplicationDataMapper.map(
                    StoredComplication.parse(json),
                    request.complicationType,
                    tapIntent(),
                )
            } catch (e: Exception) {
                Log.e(TAG, "Stored data for complication '$complicationId' is invalid: ${e.message}")
                NoDataComplicationData()
            }
        }
        listener.onComplicationData(data)
    }

    override fun getPreviewData(type: ComplicationType): ComplicationData? =
        ComplicationDataMapper.preview(
            type,
            getString(R.string.wear_os_tiles_complication_preview_text),
            getString(R.string.wear_os_tiles_complication_preview_title),
        )

    /** Opens the launcher activity and reports the tap to Dart. */
    private fun tapIntent(): PendingIntent? {
        val launch = packageManager.getLaunchIntentForPackage(packageName) ?: return null
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        launch.putExtra(WearServiceRegistry.EXTRA_KIND, WearEvent.KIND_COMPLICATION)
        launch.putExtra(WearServiceRegistry.EXTRA_TARGET_ID, complicationId)
        return PendingIntent.getActivity(
            this,
            ("complication:$complicationId").hashCode(),
            launch,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    private companion object {
        const val TAG = "WearComplicationService"
    }
}
