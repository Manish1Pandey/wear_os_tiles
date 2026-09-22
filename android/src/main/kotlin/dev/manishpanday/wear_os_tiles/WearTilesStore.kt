package dev.manishpanday.wear_os_tiles

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject

/**
 * Persistent storage shared by the Flutter plugin and the tile / complication
 * services. All of them run in the app's process and read the same
 * SharedPreferences file, so a layout committed by Dart is visible to the
 * next tile request.
 */
internal object WearTilesStore {
    const val PREFS_NAME = "dev.manishpanday.wear_os_tiles"
    const val MAX_PENDING_EVENTS = 50

    private const val TILE_PREFIX = "tile:"
    private const val COMPLICATION_PREFIX = "complication:"
    private const val EVENTS_KEY = "pending_events"

    /**
     * Invoked (on the recording thread) after an event is appended, so a live
     * plugin instance can drain it immediately.
     */
    @Volatile
    var eventListener: (() -> Unit)? = null

    private fun prefs(context: Context): SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun putTile(context: Context, tileId: String, layoutJson: String): Boolean =
        prefs(context).edit().putString(TILE_PREFIX + tileId, layoutJson).commit()

    fun getTile(context: Context, tileId: String): String? =
        prefs(context).getString(TILE_PREFIX + tileId, null)

    fun removeTile(context: Context, tileId: String): Boolean =
        prefs(context).edit().remove(TILE_PREFIX + tileId).commit()

    fun putComplication(context: Context, id: String, dataJson: String): Boolean =
        prefs(context).edit().putString(COMPLICATION_PREFIX + id, dataJson).commit()

    fun getComplication(context: Context, id: String): String? =
        prefs(context).getString(COMPLICATION_PREFIX + id, null)

    fun removeComplication(context: Context, id: String): Boolean =
        prefs(context).edit().remove(COMPLICATION_PREFIX + id).commit()

    /** Appends an interaction event to the persistent queue (bounded). */
    fun recordEvent(context: Context, event: WearEvent) {
        synchronized(this) {
            val p = prefs(context)
            val current = parseQueue(p.getString(EVENTS_KEY, null))
            current.add(event)
            val trimmed = current.takeLast(MAX_PENDING_EVENTS)
            val array = JSONArray()
            trimmed.forEach { array.put(it.toJson()) }
            p.edit().putString(EVENTS_KEY, array.toString()).commit()
        }
        eventListener?.invoke()
    }

    /** Returns and removes every queued event, oldest first. */
    fun drainEvents(context: Context): List<WearEvent> = synchronized(this) {
        val p = prefs(context)
        val events = parseQueue(p.getString(EVENTS_KEY, null))
        if (events.isNotEmpty()) p.edit().remove(EVENTS_KEY).commit()
        events
    }

    private fun parseQueue(raw: String?): MutableList<WearEvent> {
        if (raw.isNullOrEmpty()) return mutableListOf()
        return try {
            val array = JSONArray(raw)
            (0 until array.length()).mapNotNull { WearEvent.fromJson(array.optJSONObject(it)) }
                .toMutableList()
        } catch (e: org.json.JSONException) {
            mutableListOf()
        }
    }
}

/** A tile click or complication tap destined for Dart. */
internal data class WearEvent(
    val kind: String,
    val targetId: String,
    val clickableId: String?,
    val source: String,
    val timestampMs: Long,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "kind" to kind,
        "targetId" to targetId,
        "clickableId" to clickableId,
        "source" to source,
        "timestampMs" to timestampMs,
    )

    fun toJson(): JSONObject = JSONObject().apply {
        put("kind", kind)
        put("targetId", targetId)
        if (clickableId != null) put("clickableId", clickableId)
        put("source", source)
        put("timestampMs", timestampMs)
    }

    companion object {
        const val KIND_TILE = "tile"
        const val KIND_COMPLICATION = "complication"
        const val SOURCE_LAUNCH = "launch"
        const val SOURCE_LOAD = "load"
        const val SOURCE_TAP = "tap"

        fun fromJson(json: JSONObject?): WearEvent? {
            if (json == null) return null
            val kind = json.optString("kind", "")
            val target = json.optString("targetId", "")
            if (kind.isEmpty() || target.isEmpty()) return null
            return WearEvent(
                kind = kind,
                targetId = target,
                clickableId = if (json.has("clickableId")) json.getString("clickableId") else null,
                source = json.optString("source", SOURCE_LAUNCH),
                timestampMs = json.optLong("timestampMs", 0L),
            )
        }
    }
}
