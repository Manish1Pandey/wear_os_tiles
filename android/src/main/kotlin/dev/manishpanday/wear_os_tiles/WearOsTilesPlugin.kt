package dev.manishpanday.wear_os_tiles

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import androidx.wear.tiles.TileService
import androidx.wear.watchface.complications.datasource.ComplicationDataSourceUpdateRequester
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry

/** Flutter entry point: stores tiles/complications and relays interactions. */
class WearOsTilesPlugin :
    FlutterPlugin,
    MethodCallHandler,
    ActivityAware,
    EventChannel.StreamHandler,
    PluginRegistry.NewIntentListener {

    private lateinit var context: Context
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private val mainHandler = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private var activityBinding: ActivityPluginBinding? = null

    /** Launch-intent events captured before Dart started listening. */
    private val pendingLaunchEvents = mutableListOf<WearEvent>()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL)
        methodChannel.setMethodCallHandler(this)
        eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL)
        eventChannel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        sink = null
        WearTilesStore.eventListener = null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        try {
            when (call.method) {
                "updateTile" -> updateTile(call.requireArg("tileId"), call.requireArg("layout"), result)
                "getTile" -> result.success(WearTilesStore.getTile(context, call.requireArg("tileId")))
                "clearTile" -> clearTile(call.requireArg("tileId"), result)
                "registeredTileIds" ->
                    result.success(WearServiceRegistry.tileServices(context).keys.toList())
                "updateComplication" ->
                    updateComplication(call.requireArg("id"), call.requireArg("data"), result)
                "getComplication" ->
                    result.success(WearTilesStore.getComplication(context, call.requireArg("id")))
                "clearComplication" -> clearComplication(call.requireArg("id"), result)
                "registeredComplicationIds" ->
                    result.success(WearServiceRegistry.complicationServices(context).keys.toList())
                else -> result.notImplemented()
            }
        } catch (e: IllegalArgumentException) {
            result.error("invalid_argument", e.message, null)
        }
    }

    private fun updateTile(tileId: String, layout: String, result: Result) {
        val services = WearServiceRegistry.tileServices(context)
        val component = services[tileId]
        if (component == null) {
            result.error(
                "unknown_tile",
                "No tile service is registered for tile id '$tileId'. Registered: ${services.keys}",
                null,
            )
            return
        }
        if (!WearTilesStore.putTile(context, tileId, layout)) {
            result.error("storage_failed", "Could not persist the layout for '$tileId'", null)
            return
        }
        requestTileUpdate(component.className)
        result.success(null)
    }

    private fun clearTile(tileId: String, result: Result) {
        WearTilesStore.removeTile(context, tileId)
        WearServiceRegistry.tileServices(context)[tileId]?.let { requestTileUpdate(it.className) }
        result.success(null)
    }

    private fun requestTileUpdate(className: String) {
        val serviceClass = Class.forName(className).asSubclass(TileService::class.java)
        TileService.getUpdater(context).requestUpdate(serviceClass)
    }

    private fun updateComplication(id: String, data: String, result: Result) {
        val services = WearServiceRegistry.complicationServices(context)
        val component = services[id]
        if (component == null) {
            result.error(
                "unknown_complication",
                "No complication data source is registered for id '$id'. Registered: ${services.keys}",
                null,
            )
            return
        }
        if (!WearTilesStore.putComplication(context, id, data)) {
            result.error("storage_failed", "Could not persist complication '$id'", null)
            return
        }
        ComplicationDataSourceUpdateRequester.create(context, component).requestUpdateAll()
        result.success(null)
    }

    private fun clearComplication(id: String, result: Result) {
        WearTilesStore.removeComplication(context, id)
        WearServiceRegistry.complicationServices(context)[id]?.let {
            ComplicationDataSourceUpdateRequester.create(context, it).requestUpdateAll()
        }
        result.success(null)
    }

    // --- Events ---------------------------------------------------------

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
        WearTilesStore.eventListener = { mainHandler.post { flush() } }
        flush()
    }

    override fun onCancel(arguments: Any?) {
        sink = null
        WearTilesStore.eventListener = null
    }

    /** Delivers buffered launch events and queued load clicks, each once. */
    private fun flush() {
        val out = sink ?: return
        val launches = pendingLaunchEvents.toList()
        pendingLaunchEvents.clear()
        launches.forEach { out.success(it.toMap()) }
        WearTilesStore.drainEvents(context).forEach { out.success(it.toMap()) }
    }

    // --- Activity -------------------------------------------------------

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addOnNewIntentListener(this)
        handleIntent(binding.activity.intent)
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivity() {
        activityBinding?.removeOnNewIntentListener(this)
        activityBinding = null
    }

    override fun onNewIntent(intent: Intent): Boolean {
        handleIntent(intent)
        return false
    }

    private fun handleIntent(intent: Intent?) {
        val event = eventFromIntent(intent) ?: return
        // Consume the extras so a re-attach (e.g. rotation) does not repeat it.
        intent?.removeExtra(WearServiceRegistry.EXTRA_KIND)
        intent?.removeExtra(WearServiceRegistry.EXTRA_TARGET_ID)
        intent?.removeExtra(WearServiceRegistry.EXTRA_CLICKABLE_ID)
        pendingLaunchEvents.add(event)
        flush()
    }

    companion object {
        const val METHOD_CHANNEL = "dev.manishpanday.wear_os_tiles/methods"
        const val EVENT_CHANNEL = "dev.manishpanday.wear_os_tiles/events"

        /** Extracts a tile/complication interaction from a launch intent. */
        internal fun eventFromIntent(intent: Intent?, now: Long = System.currentTimeMillis()): WearEvent? {
            if (intent == null) return null
            val kind = intent.getStringExtra(WearServiceRegistry.EXTRA_KIND) ?: return null
            val target = intent.getStringExtra(WearServiceRegistry.EXTRA_TARGET_ID) ?: return null
            return when (kind) {
                WearEvent.KIND_TILE -> {
                    val clickable = intent.getStringExtra(WearServiceRegistry.EXTRA_CLICKABLE_ID)
                        ?: intent.getStringExtra(TileService.EXTRA_CLICKABLE_ID)
                        ?: return null
                    WearEvent(kind, target, clickable, WearEvent.SOURCE_LAUNCH, now)
                }
                WearEvent.KIND_COMPLICATION ->
                    WearEvent(kind, target, null, WearEvent.SOURCE_TAP, now)
                else -> null
            }
        }
    }
}

private fun MethodCall.requireArg(name: String): String =
    argument<String>(name) ?: throw IllegalArgumentException("Missing argument '$name'")
