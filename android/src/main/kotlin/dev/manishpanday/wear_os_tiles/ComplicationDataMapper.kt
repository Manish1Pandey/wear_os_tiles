package dev.manishpanday.wear_os_tiles

import android.app.PendingIntent
import androidx.wear.watchface.complications.data.ComplicationData
import androidx.wear.watchface.complications.data.ComplicationType
import androidx.wear.watchface.complications.data.LongTextComplicationData
import androidx.wear.watchface.complications.data.NoDataComplicationData
import androidx.wear.watchface.complications.data.PlainComplicationText
import androidx.wear.watchface.complications.data.RangedValueComplicationData
import androidx.wear.watchface.complications.data.ShortTextComplicationData
import org.json.JSONObject
import java.util.Locale

/** Complication data stored by Dart (`ComplicationData.toJson`). */
internal data class StoredComplication(
    val type: String,
    val text: String?,
    val title: String?,
    val contentDescription: String?,
    val value: Float?,
    val min: Float?,
    val max: Float?,
    val tapLaunchesApp: Boolean,
) {
    companion object {
        const val SHORT_TEXT = "shortText"
        const val LONG_TEXT = "longText"
        const val RANGED_VALUE = "rangedValue"

        fun parse(json: String): StoredComplication {
            val o = JSONObject(json)
            fun str(k: String) = if (o.has(k) && !o.isNull(k)) o.getString(k) else null
            fun num(k: String) = if (o.has(k) && !o.isNull(k)) o.getDouble(k).toFloat() else null
            val type = o.optString("type", SHORT_TEXT)
            require(type == SHORT_TEXT || type == LONG_TEXT || type == RANGED_VALUE) {
                "Unknown complication type \"$type\""
            }
            return StoredComplication(
                type = type,
                text = str("text"),
                title = str("title"),
                contentDescription = str("contentDescription"),
                value = num("value"),
                min = num("min"),
                max = num("max"),
                tapLaunchesApp = o.optBoolean("tapLaunchesApp", true),
            )
        }
    }
}

/**
 * Builds the `ComplicationData` a watch face asked for from stored data.
 *
 * Conversion rules: ranged value -> short/long text (its text, or the
 * formatted value); short text <-> long text. Anything else yields
 * [NoDataComplicationData].
 */
internal object ComplicationDataMapper {

    fun map(
        stored: StoredComplication,
        requested: ComplicationType,
        tapAction: PendingIntent?,
    ): ComplicationData {
        val tap = if (stored.tapLaunchesApp) tapAction else null
        val displayText = stored.text ?: stored.value?.let { formatValue(it) }
        val description = plain(stored.contentDescription ?: displayText ?: stored.title ?: "")
        return when (requested) {
            ComplicationType.SHORT_TEXT -> {
                if (displayText.isNullOrEmpty()) return NoDataComplicationData()
                ShortTextComplicationData.Builder(plain(displayText), description)
                    .apply {
                        stored.title?.let { setTitle(plain(it)) }
                        tap?.let { setTapAction(it) }
                    }
                    .build()
            }
            ComplicationType.LONG_TEXT -> {
                if (displayText.isNullOrEmpty()) return NoDataComplicationData()
                LongTextComplicationData.Builder(plain(displayText), description)
                    .apply {
                        stored.title?.let { setTitle(plain(it)) }
                        tap?.let { setTapAction(it) }
                    }
                    .build()
            }
            ComplicationType.RANGED_VALUE -> {
                val value = stored.value
                val min = stored.min
                val max = stored.max
                if (stored.type != StoredComplication.RANGED_VALUE ||
                    value == null || min == null || max == null || max <= min
                ) {
                    return NoDataComplicationData()
                }
                RangedValueComplicationData.Builder(value.coerceIn(min, max), min, max, description)
                    .apply {
                        stored.text?.let { setText(plain(it)) }
                        stored.title?.let { setTitle(plain(it)) }
                        tap?.let { setTapAction(it) }
                    }
                    .build()
            }
            else -> NoDataComplicationData()
        }
    }

    /** Sample data shown in the watch-face complication picker. */
    fun preview(requested: ComplicationType, sampleText: String, sampleTitle: String): ComplicationData? =
        when (requested) {
            ComplicationType.SHORT_TEXT ->
                ShortTextComplicationData.Builder(plain(sampleText), plain(sampleText))
                    .setTitle(plain(sampleTitle))
                    .build()
            ComplicationType.LONG_TEXT ->
                LongTextComplicationData.Builder(plain("$sampleTitle $sampleText"), plain(sampleText))
                    .build()
            ComplicationType.RANGED_VALUE ->
                RangedValueComplicationData.Builder(60f, 0f, 100f, plain(sampleText))
                    .setText(plain(sampleText))
                    .setTitle(plain(sampleTitle))
                    .build()
            else -> null
        }

    fun formatValue(value: Float): String =
        if (value == value.toLong().toFloat()) value.toLong().toString() else String.format(Locale.US, "%.1f", value)

    private fun plain(text: CharSequence) = PlainComplicationText.Builder(text).build()
}
