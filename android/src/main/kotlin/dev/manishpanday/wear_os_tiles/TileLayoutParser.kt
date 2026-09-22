package dev.manishpanday.wear_os_tiles

import android.content.ComponentName
import android.content.Context
import androidx.wear.protolayout.ActionBuilders
import androidx.wear.protolayout.ColorBuilders.ColorProp
import androidx.wear.protolayout.ColorBuilders.argb
import androidx.wear.protolayout.DeviceParametersBuilders.DeviceParameters
import androidx.wear.protolayout.DimensionBuilders
import androidx.wear.protolayout.DimensionBuilders.degrees
import androidx.wear.protolayout.DimensionBuilders.dp
import androidx.wear.protolayout.DimensionBuilders.sp
import androidx.wear.protolayout.LayoutElementBuilders
import androidx.wear.protolayout.LayoutElementBuilders.LayoutElement
import androidx.wear.protolayout.ModifiersBuilders
import androidx.wear.protolayout.material.Button
import androidx.wear.protolayout.material.ButtonColors
import androidx.wear.protolayout.material.Chip
import androidx.wear.protolayout.material.ChipColors
import androidx.wear.protolayout.material.CircularProgressIndicator
import androidx.wear.protolayout.material.Colors
import androidx.wear.protolayout.material.ProgressIndicatorColors
import org.json.JSONArray
import org.json.JSONObject

/** Thrown when stored layout JSON does not match the wire format. */
class TileLayoutFormatException(message: String) : IllegalArgumentException(message)

/** Result of parsing a stored tile layout. */
data class ParsedTile(
    val root: LayoutElement,
    val freshnessMillis: Long,
    /** Drawable resource names referenced by images, chip icons and buttons. */
    val imageResources: Set<String>,
    /** Action id -> "load" / "launch". */
    val actions: Map<String, String>,
)

/**
 * Converts the JSON wire format written by the Dart `TileLayout` model into
 * ProtoLayout elements. Mirrors `lib/src/tile_layout.dart`.
 *
 * @param launchActivity activity opened by `launch` actions; when null,
 *   launch actions degrade to load actions (the click is still queued).
 */
class TileLayoutParser(
    private val context: Context,
    private val deviceParameters: DeviceParameters,
    private val tileId: String,
    private val launchActivity: ComponentName?,
) {
    private val images = linkedSetOf<String>()
    private val actions = linkedMapOf<String, String>()

    fun parse(json: String): ParsedTile {
        images.clear()
        actions.clear()
        val obj = try {
            JSONObject(json)
        } catch (e: org.json.JSONException) {
            throw TileLayoutFormatException("Invalid JSON: ${e.message}")
        }
        val version = obj.optInt("v", WIRE_VERSION)
        if (version != WIRE_VERSION) {
            throw TileLayoutFormatException("Unsupported layout version $version")
        }
        val freshness = obj.optLong("freshnessMs", 0L)
        val root = element(obj.requireObject("root"), 1)
        return ParsedTile(root, maxOf(0L, freshness), images.toSet(), actions.toMap())
    }

    private fun element(json: JSONObject, depth: Int): LayoutElement {
        if (depth > MAX_DEPTH) throw TileLayoutFormatException("Layout deeper than $MAX_DEPTH")
        return when (val type = json.requireString("type")) {
            "column" -> column(json, depth)
            "row" -> row(json, depth)
            "box" -> box(json, depth)
            "text" -> text(json)
            "spacer" -> spacer(json)
            "image" -> image(json)
            "arc" -> arc(json)
            "circularProgress" -> circularProgress(json)
            "chip" -> chip(json)
            "button" -> button(json)
            else -> throw TileLayoutFormatException("Unknown element type \"$type\"")
        }
    }

    private fun children(json: JSONObject, depth: Int): List<LayoutElement> {
        val array = json.optJSONArray("children") ?: JSONArray()
        return (0 until array.length()).map { element(array.getJSONObject(it), depth + 1) }
    }

    private fun column(json: JSONObject, depth: Int): LayoutElement {
        val b = LayoutElementBuilders.Column.Builder()
            .setHorizontalAlignment(hAlign(json.optString("hAlign", "center")))
        json.containerDim("width")?.let { b.setWidth(it) }
        json.containerDim("height")?.let { b.setHeight(it) }
        modifiers(json)?.let { b.setModifiers(it) }
        children(json, depth).forEach { b.addContent(it) }
        return b.build()
    }

    private fun row(json: JSONObject, depth: Int): LayoutElement {
        val b = LayoutElementBuilders.Row.Builder()
            .setVerticalAlignment(vAlign(json.optString("vAlign", "center")))
        json.containerDim("width")?.let { b.setWidth(it) }
        json.containerDim("height")?.let { b.setHeight(it) }
        modifiers(json)?.let { b.setModifiers(it) }
        children(json, depth).forEach { b.addContent(it) }
        return b.build()
    }

    private fun box(json: JSONObject, depth: Int): LayoutElement {
        val b = LayoutElementBuilders.Box.Builder()
            .setHorizontalAlignment(hAlign(json.optString("hAlign", "center")))
            .setVerticalAlignment(vAlign(json.optString("vAlign", "center")))
        json.containerDim("width")?.let { b.setWidth(it) }
        json.containerDim("height")?.let { b.setHeight(it) }
        modifiers(json)?.let { b.setModifiers(it) }
        children(json, depth).forEach { b.addContent(it) }
        return b.build()
    }

    private fun fontStyle(json: JSONObject): LayoutElementBuilders.FontStyle {
        val b = LayoutElementBuilders.FontStyle.Builder()
        json.optColor("color")?.let { b.setColor(it) }
        json.optDoubleOrNull("fontSize")?.let { b.setSize(sp(it.toFloat())) }
        b.setWeight(
            when (json.optString("fontWeight", "normal")) {
                "medium" -> LayoutElementBuilders.FONT_WEIGHT_MEDIUM
                "bold" -> LayoutElementBuilders.FONT_WEIGHT_BOLD
                "normal" -> LayoutElementBuilders.FONT_WEIGHT_NORMAL
                else -> throw TileLayoutFormatException("Unknown fontWeight")
            },
        )
        if (json.optBoolean("italic", false)) b.setItalic(true)
        return b.build()
    }

    private fun text(json: JSONObject): LayoutElement {
        val b = LayoutElementBuilders.Text.Builder()
            .setText(json.requireString("text"))
            .setFontStyle(fontStyle(json))
            .setMultilineAlignment(
                when (json.optString("textAlign", "center")) {
                    "start" -> LayoutElementBuilders.TEXT_ALIGN_START
                    "end" -> LayoutElementBuilders.TEXT_ALIGN_END
                    "center" -> LayoutElementBuilders.TEXT_ALIGN_CENTER
                    else -> throw TileLayoutFormatException("Unknown textAlign")
                },
            )
            .setOverflow(LayoutElementBuilders.TEXT_OVERFLOW_ELLIPSIZE)
        json.optIntOrNull("maxLines")?.let { b.setMaxLines(it) }
        modifiers(json)?.let { b.setModifiers(it) }
        return b.build()
    }

    private fun spacer(json: JSONObject): LayoutElement {
        val b = LayoutElementBuilders.Spacer.Builder()
            .setWidth(dp(json.optDouble("width", 0.0).toFloat()))
            .setHeight(dp(json.optDouble("height", 0.0).toFloat()))
        modifiers(json)?.let { b.setModifiers(it) }
        return b.build()
    }

    // Images are referenced by resource id and served from
    // WearTileService.onTileResourcesRequest, the same mechanism the
    // protolayout-material Chip/Button icons use. ProtoLayout 1.4 deprecates
    // the id-based Image builder in favour of scope-registered resources,
    // which material (non-M3) components cannot use, so one consistent path
    // is kept here.
    @Suppress("DEPRECATION")
    private fun image(json: JSONObject): LayoutElement {
        val resource = json.requireString("resource")
        images.add(resource)
        val b = LayoutElementBuilders.Image.Builder()
            .setResourceId(resource)
            .setWidth(json.imageDim("width") ?: dp(24f))
            .setHeight(json.imageDim("height") ?: dp(24f))
            .setContentScaleMode(
                when (json.optString("contentScale", "fit")) {
                    "crop" -> LayoutElementBuilders.CONTENT_SCALE_MODE_CROP
                    "fillBounds" -> LayoutElementBuilders.CONTENT_SCALE_MODE_FILL_BOUNDS
                    "fit" -> LayoutElementBuilders.CONTENT_SCALE_MODE_FIT
                    else -> throw TileLayoutFormatException("Unknown contentScale")
                },
            )
        json.optColor("tint")?.let {
            b.setColorFilter(LayoutElementBuilders.ColorFilter.Builder().setTint(it).build())
        }
        modifiers(json)?.let { b.setModifiers(it) }
        return b.build()
    }

    private fun arc(json: JSONObject): LayoutElement {
        val b = LayoutElementBuilders.Arc.Builder()
            .setAnchorAngle(degrees(json.optDouble("anchorAngle", 0.0).toFloat()))
            .setAnchorType(
                when (json.optString("anchorType", "start")) {
                    "center" -> LayoutElementBuilders.ARC_ANCHOR_CENTER
                    "end" -> LayoutElementBuilders.ARC_ANCHOR_END
                    "start" -> LayoutElementBuilders.ARC_ANCHOR_START
                    else -> throw TileLayoutFormatException("Unknown anchorType")
                },
            )
        modifiers(json)?.let { b.setModifiers(it) }
        val array = json.optJSONArray("children") ?: JSONArray()
        for (i in 0 until array.length()) {
            b.addContent(arcChild(array.getJSONObject(i)))
        }
        return b.build()
    }

    private fun arcChild(json: JSONObject): LayoutElementBuilders.ArcLayoutElement {
        return when (val type = json.requireString("type")) {
            "arcLine" -> LayoutElementBuilders.ArcLine.Builder()
                .setLength(degrees(json.requireDouble("length").toFloat()))
                .setThickness(dp(json.optDouble("thickness", 4.0).toFloat()))
                .setColor(json.optColor("color") ?: argb(WHITE))
                .setStrokeCap(
                    if (json.optString("strokeCap", "butt") == "round") {
                        LayoutElementBuilders.STROKE_CAP_ROUND
                    } else {
                        LayoutElementBuilders.STROKE_CAP_BUTT
                    },
                )
                .build()
            "arcSpacer" -> LayoutElementBuilders.ArcSpacer.Builder()
                .setLength(degrees(json.requireDouble("length").toFloat()))
                .build()
            "arcText" -> LayoutElementBuilders.ArcText.Builder()
                .setText(json.requireString("text"))
                .setFontStyle(fontStyle(json))
                .build()
            else -> throw TileLayoutFormatException("Unknown arc element type \"$type\"")
        }
    }

    private fun circularProgress(json: JSONObject): LayoutElement {
        val defaults = ProgressIndicatorColors.progressIndicatorColors(Colors.DEFAULT)
        val b = CircularProgressIndicator.Builder()
            .setProgress(json.requireDouble("progress").toFloat().coerceIn(0f, 1f))
            .setCircularProgressIndicatorColors(
                ProgressIndicatorColors(
                    json.optColor("indicatorColor") ?: defaults.indicatorColor,
                    json.optColor("trackColor") ?: defaults.trackColor,
                ),
            )
        json.optDoubleOrNull("strokeWidth")?.let { b.setStrokeWidth(it.toFloat()) }
        json.optDoubleOrNull("startAngle")?.let { b.setStartAngle(it.toFloat()) }
        json.optDoubleOrNull("endAngle")?.let { b.setEndAngle(it.toFloat()) }
        json.optStringOrNull("contentDescription")?.let { b.setContentDescription(it) }
        return b.build()
    }

    private fun chip(json: JSONObject): LayoutElement {
        val clickable = clickable(json.requireObject("action"))
        val secondary = json.optString("style", "primary") == "secondary"
        val base = if (secondary) {
            ChipColors.secondaryChipColors(Colors.DEFAULT)
        } else {
            ChipColors.primaryChipColors(Colors.DEFAULT)
        }
        val content = json.optColor("contentColor")
        val colors = ChipColors(
            json.optColor("backgroundColor") ?: base.backgroundColor,
            content ?: base.iconColor,
            content ?: base.contentColor,
            content ?: base.secondaryContentColor,
        )
        val label = json.requireString("label")
        val b = Chip.Builder(context, clickable, deviceParameters)
            .setPrimaryLabelContent(label)
            .setChipColors(colors)
            .setContentDescription(json.optStringOrNull("contentDescription") ?: label)
        json.optStringOrNull("secondaryLabel")?.let { b.setSecondaryLabelContent(it) }
        json.optStringOrNull("icon")?.let {
            images.add(it)
            b.setIconContent(it)
        }
        json.containerDim("width")?.let { b.setWidth(it) }
        return b.build()
    }

    private fun button(json: JSONObject): LayoutElement {
        val clickable = clickable(json.requireObject("action"))
        val secondary = json.optString("style", "primary") == "secondary"
        val base = if (secondary) {
            ButtonColors.secondaryButtonColors(Colors.DEFAULT)
        } else {
            ButtonColors.primaryButtonColors(Colors.DEFAULT)
        }
        val b = Button.Builder(context, clickable).setButtonColors(
            ButtonColors(
                json.optColor("backgroundColor") ?: base.backgroundColor,
                json.optColor("contentColor") ?: base.contentColor,
            ),
        )
        val text = json.optStringOrNull("text")
        val icon = json.optStringOrNull("icon")
        val image = json.optStringOrNull("image")
        when {
            text != null -> b.setTextContent(text)
            icon != null -> {
                images.add(icon)
                b.setIconContent(icon)
            }
            image != null -> {
                images.add(image)
                b.setImageContent(image)
            }
            else -> throw TileLayoutFormatException("Button needs text, icon or image")
        }
        json.optDoubleOrNull("size")?.let { b.setSize(it.toFloat()) }
        (json.optStringOrNull("contentDescription") ?: text)?.let { b.setContentDescription(it) }
        return b.build()
    }

    private fun modifiers(json: JSONObject): ModifiersBuilders.Modifiers? {
        val m = json.optJSONObject("modifiers") ?: return null
        val b = ModifiersBuilders.Modifiers.Builder()
        m.optJSONObject("padding")?.let { p ->
            b.setPadding(
                ModifiersBuilders.Padding.Builder()
                    .setStart(dp(p.optDouble("start", 0.0).toFloat()))
                    .setTop(dp(p.optDouble("top", 0.0).toFloat()))
                    .setEnd(dp(p.optDouble("end", 0.0).toFloat()))
                    .setBottom(dp(p.optDouble("bottom", 0.0).toFloat()))
                    .setRtlAware(true)
                    .build(),
            )
        }
        val background = m.optColor("background")
        if (background != null) {
            val bg = ModifiersBuilders.Background.Builder().setColor(background)
            m.optDoubleOrNull("cornerRadius")?.let {
                bg.setCorner(ModifiersBuilders.Corner.Builder().setRadius(dp(it.toFloat())).build())
            }
            b.setBackground(bg.build())
        }
        m.optJSONObject("action")?.let { b.setClickable(clickable(it)) }
        m.optStringOrNull("contentDescription")?.let {
            b.setSemantics(ModifiersBuilders.Semantics.Builder().setContentDescription(it).build())
        }
        return b.build()
    }

    private fun clickable(action: JSONObject): ModifiersBuilders.Clickable {
        val id = action.requireString("id")
        if (id.isEmpty()) throw TileLayoutFormatException("Action id must not be empty")
        val type = action.optString("type", "load")
        val launch = launchActivity
        val onClick: ActionBuilders.Action = if (type == "launch" && launch != null) {
            actions[id] = "launch"
            ActionBuilders.LaunchAction.Builder()
                .setAndroidActivity(
                    ActionBuilders.AndroidActivity.Builder()
                        .setPackageName(launch.packageName)
                        .setClassName(launch.className)
                        .addKeyToExtraMapping(WearServiceRegistry.EXTRA_KIND, stringExtra(WearEvent.KIND_TILE))
                        .addKeyToExtraMapping(WearServiceRegistry.EXTRA_TARGET_ID, stringExtra(tileId))
                        .addKeyToExtraMapping(WearServiceRegistry.EXTRA_CLICKABLE_ID, stringExtra(id))
                        .build(),
                )
                .build()
        } else if (type == "launch" || type == "load") {
            actions[id] = "load"
            ActionBuilders.LoadAction.Builder().build()
        } else {
            throw TileLayoutFormatException("Unknown action type \"$type\"")
        }
        return ModifiersBuilders.Clickable.Builder().setId(id).setOnClick(onClick).build()
    }

    private fun stringExtra(value: String) =
        ActionBuilders.AndroidStringExtra.Builder().setValue(value).build()

    private fun hAlign(value: String): Int = when (value) {
        "start" -> LayoutElementBuilders.HORIZONTAL_ALIGN_START
        "end" -> LayoutElementBuilders.HORIZONTAL_ALIGN_END
        "center" -> LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER
        else -> throw TileLayoutFormatException("Unknown hAlign \"$value\"")
    }

    private fun vAlign(value: String): Int = when (value) {
        "top" -> LayoutElementBuilders.VERTICAL_ALIGN_TOP
        "bottom" -> LayoutElementBuilders.VERTICAL_ALIGN_BOTTOM
        "center" -> LayoutElementBuilders.VERTICAL_ALIGN_CENTER
        else -> throw TileLayoutFormatException("Unknown vAlign \"$value\"")
    }

    companion object {
        const val WIRE_VERSION = 1
        const val MAX_DEPTH = 30
        private const val WHITE = 0xFFFFFFFF.toInt()

        /**
         * Collects drawable names referenced by a stored layout without
         * building it (used to answer resource requests, which do not need a
         * full render).
         */
        fun collectImageResources(json: String): Set<String> {
            val out = linkedSetOf<String>()
            fun walk(node: JSONObject) {
                when (node.optString("type")) {
                    "image" -> node.optStringOrNull("resource")?.let { out.add(it) }
                    "chip" -> node.optStringOrNull("icon")?.let { out.add(it) }
                    "button" -> {
                        node.optStringOrNull("icon")?.let { out.add(it) }
                        node.optStringOrNull("image")?.let { out.add(it) }
                    }
                }
                val children = node.optJSONArray("children") ?: return
                for (i in 0 until children.length()) {
                    children.optJSONObject(i)?.let { walk(it) }
                }
            }
            try {
                JSONObject(json).optJSONObject("root")?.let { walk(it) }
            } catch (e: org.json.JSONException) {
                return emptySet()
            }
            return out
        }
    }
}

private fun JSONObject.requireString(key: String): String {
    if (!has(key) || isNull(key)) throw TileLayoutFormatException("Missing \"$key\"")
    return getString(key)
}

private fun JSONObject.requireObject(key: String): JSONObject =
    optJSONObject(key) ?: throw TileLayoutFormatException("Missing object \"$key\"")

private fun JSONObject.requireDouble(key: String): Double {
    if (!has(key) || isNull(key)) throw TileLayoutFormatException("Missing \"$key\"")
    return getDouble(key)
}

private fun JSONObject.optDoubleOrNull(key: String): Double? =
    if (has(key) && !isNull(key)) getDouble(key) else null

private fun JSONObject.optIntOrNull(key: String): Int? =
    if (has(key) && !isNull(key)) getInt(key) else null

private fun JSONObject.optStringOrNull(key: String): String? =
    if (has(key) && !isNull(key)) getString(key) else null

/** Colours travel as unsigned 32-bit ARGB, which may exceed Int range. */
private fun JSONObject.optColor(key: String): ColorProp? =
    if (has(key) && !isNull(key)) argb(getLong(key).toInt()) else null

private fun JSONObject.dimension(key: String): Any? {
    if (!has(key) || isNull(key)) return null
    val raw = get(key)
    if (raw is String) {
        return when (raw) {
            "expand" -> DimensionBuilders.expand()
            "wrap" -> DimensionBuilders.wrap()
            else -> throw TileLayoutFormatException("Unknown dimension \"$raw\"")
        }
    }
    val obj = raw as? JSONObject ?: throw TileLayoutFormatException("Bad dimension for \"$key\"")
    return when {
        obj.has("dp") -> dp(obj.getDouble("dp").toFloat())
        obj.has("weight") -> DimensionBuilders.weight(obj.getDouble("weight").toFloat())
        else -> throw TileLayoutFormatException("Bad dimension for \"$key\"")
    }
}

private fun JSONObject.containerDim(key: String): DimensionBuilders.ContainerDimension? =
    dimension(key)?.let {
        it as? DimensionBuilders.ContainerDimension
            ?: throw TileLayoutFormatException("\"$key\" is not a container dimension")
    }

private fun JSONObject.imageDim(key: String): DimensionBuilders.ImageDimension? =
    dimension(key)?.let {
        it as? DimensionBuilders.ImageDimension
            ?: throw TileLayoutFormatException("\"$key\" is not supported for images")
    }
