package dev.manishpanday.wear_os_tiles

import android.content.ComponentName
import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.wear.protolayout.ActionBuilders
import androidx.wear.protolayout.DeviceParametersBuilders
import androidx.wear.protolayout.DimensionBuilders
import androidx.wear.protolayout.LayoutElementBuilders
import androidx.wear.protolayout.material.Button
import androidx.wear.protolayout.material.Chip
import androidx.wear.protolayout.material.CircularProgressIndicator
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Parses the JSON wire format produced by the Dart model (same shape as
 * `TileLayout.toJsonString()`) into real ProtoLayout objects.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class TileLayoutParserTest {

    private lateinit var context: Context
    private val device = DeviceParametersBuilders.DeviceParameters.Builder()
        .setScreenWidthDp(192)
        .setScreenHeightDp(192)
        .setScreenDensity(2f)
        .setScreenShape(DeviceParametersBuilders.SCREEN_SHAPE_ROUND)
        .build()
    private val launch = ComponentName("com.example.app", "com.example.app.MainActivity")

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
    }

    private fun parser(launchActivity: ComponentName? = launch) =
        TileLayoutParser(context, device, "steps", launchActivity)

    // Mirrors example/lib/layouts.dart stepsTile(steps: 6200, goal: 10000).
    private val stepsJson = """
        {"v":1,"freshnessMs":1800000,"root":{"type":"box","children":[
          {"type":"arc","children":[
            {"type":"arcLine","length":223.2,"thickness":6.0,"color":4287280376,"strokeCap":"round"},
            {"type":"arcLine","length":136.8,"thickness":6.0,"color":4281545523,"strokeCap":"butt"}],
           "anchorAngle":0.0,"anchorType":"start"},
          {"type":"column","children":[
            {"type":"image","resource":"ic_steps","width":{"dp":22.0},"height":{"dp":22.0},"contentScale":"fit","tint":4287280376},
            {"type":"text","text":"6,200","fontSize":30.0,"fontWeight":"bold","textAlign":"center"},
            {"type":"text","text":"of 10,000 steps","color":4289374890,"fontSize":13.0,"fontWeight":"normal","maxLines":1,"textAlign":"center"},
            {"type":"spacer","width":0.0,"height":8.0},
            {"type":"row","children":[
              {"type":"button","action":{"id":"add_250","type":"launch"},"text":"+250","style":"primary","size":44.0,"contentDescription":"Add 250 steps"},
              {"type":"spacer","width":8.0,"height":0.0},
              {"type":"button","action":{"id":"refresh","type":"load"},"icon":"ic_refresh","style":"secondary","size":44.0}],
             "vAlign":"center"}],
           "hAlign":"center"}],
         "hAlign":"center","vAlign":"center","width":"expand","height":"expand",
         "modifiers":{"padding":{"start":2.0,"top":2.0,"end":2.0,"bottom":2.0},"background":4278190080,"cornerRadius":8.0,"contentDescription":"Steps"}}}
    """.trimIndent()

    @Test
    fun parsesStepsTileIntoProtoLayout() {
        val parsed = parser().parse(stepsJson)

        assertEquals(1_800_000L, parsed.freshnessMillis)
        assertEquals(setOf("ic_steps", "ic_refresh"), parsed.imageResources)
        assertEquals(mapOf("add_250" to "launch", "refresh" to "load"), parsed.actions)

        val box = parsed.root as LayoutElementBuilders.Box
        assertTrue(box.width is DimensionBuilders.ExpandedDimensionProp)
        assertEquals(0xFF000000.toInt(), box.modifiers!!.background!!.color!!.argb)
        assertEquals(8f, box.modifiers!!.background!!.corner!!.radius!!.value, 0f)
        assertEquals(2f, box.modifiers!!.padding!!.start!!.value, 0f)
        assertEquals("Steps", box.modifiers!!.semantics!!.contentDescription!!.value)
        assertEquals(2, box.contents.size)

        val arc = box.contents[0] as LayoutElementBuilders.Arc
        val lines = arc.contents.map { it as LayoutElementBuilders.ArcLine }
        assertEquals(223.2f, lines[0].length!!.value, 0.001f)
        assertEquals(LayoutElementBuilders.STROKE_CAP_ROUND, lines[0].strokeCap!!.value)
        assertEquals(0xFF8AB4F8.toInt(), lines[0].color!!.argb)
        assertEquals(6f, lines[1].thickness!!.value, 0f)

        val column = box.contents[1] as LayoutElementBuilders.Column
        assertEquals(5, column.contents.size)
        val image = column.contents[0] as LayoutElementBuilders.Image
        assertEquals("ic_steps", image.resourceId!!.value)
        assertEquals(0xFF8AB4F8.toInt(), image.colorFilter!!.tint!!.argb)
        val count = column.contents[1] as LayoutElementBuilders.Text
        assertEquals("6,200", count.text!!.value)
        assertEquals(30f, count.fontStyle!!.size!!.value, 0f)
        assertEquals(LayoutElementBuilders.FONT_WEIGHT_BOLD, count.fontStyle!!.weight!!.value)
        val goal = column.contents[2] as LayoutElementBuilders.Text
        assertEquals(1, goal.maxLines!!.value)
        assertEquals(0xFFAAAAAA.toInt(), goal.fontStyle!!.color!!.argb)
        val spacer = column.contents[3] as LayoutElementBuilders.Spacer
        assertEquals(8f, (spacer.height as DimensionBuilders.DpProp).value, 0f)

        val row = column.contents[4] as LayoutElementBuilders.Row
        val plus = Button.fromLayoutElement(row.contents[0])!!
        assertEquals("add_250", plus.clickable.id)
        val launchAction = plus.clickable.onClick as ActionBuilders.LaunchAction
        val activity = launchAction.androidActivity!!
        assertEquals("com.example.app", activity.packageName)
        assertEquals("com.example.app.MainActivity", activity.className)
        assertEquals(
            "add_250",
            (activity.keyToExtraMapping[WearServiceRegistry.EXTRA_CLICKABLE_ID] as ActionBuilders.AndroidStringExtra).value,
        )
        assertEquals(
            "steps",
            (activity.keyToExtraMapping[WearServiceRegistry.EXTRA_TARGET_ID] as ActionBuilders.AndroidStringExtra).value,
        )
        assertEquals("Add 250 steps", plus.contentDescription!!.value)
        val refresh = Button.fromLayoutElement(row.contents[2])!!
        assertTrue(refresh.clickable.onClick is ActionBuilders.LoadAction)
        assertEquals("ic_refresh", refresh.iconContent)
    }

    @Test
    fun parsesMaterialChipAndProgress() {
        val json = """
            {"v":1,"root":{"type":"box","children":[
              {"type":"circularProgress","progress":0.375,"indicatorColor":4283417591,"startAngle":30.0,"endAngle":330.0,"contentDescription":"3 of 8"},
              {"type":"arc","children":[{"type":"arcText","text":"WATER","color":4283417591,"fontSize":12.0},{"type":"arcSpacer","length":10.0}],"anchorAngle":0.0,"anchorType":"center"},
              {"type":"chip","label":"Log a glass","secondaryLabel":"250 ml","action":{"id":"add_glass","type":"launch"},"icon":"ic_water","style":"primary","width":{"dp":140.0}}
            ]}}
        """.trimIndent()
        val parsed = parser().parse(json)
        assertEquals(0L, parsed.freshnessMillis)
        assertEquals(setOf("ic_water"), parsed.imageResources)

        val box = parsed.root as LayoutElementBuilders.Box
        val progress = CircularProgressIndicator.fromLayoutElement(box.contents[0])!!
        // The material component stores progress as swept degrees of its span.
        assertEquals(0.375f * 300f, progress.progress.value, 0.001f)
        assertEquals(30f, progress.startAngle.value, 0f)
        assertEquals(330f, progress.endAngle.value, 0f)
        assertEquals(0xFF4FC3F7.toInt(), progress.circularProgressIndicatorColors.indicatorColor.argb)

        val arc = box.contents[1] as LayoutElementBuilders.Arc
        assertEquals(LayoutElementBuilders.ARC_ANCHOR_CENTER, arc.anchorType!!.value)
        assertEquals("WATER", (arc.contents[0] as LayoutElementBuilders.ArcText).text!!.value)
        assertEquals(10f, (arc.contents[1] as LayoutElementBuilders.ArcSpacer).length!!.value, 0f)

        val chip = Chip.fromLayoutElement(box.contents[2])!!
        assertEquals("Log a glass", chip.primaryLabelContent)
        assertEquals("250 ml", chip.secondaryLabelContent)
        assertEquals("ic_water", chip.iconContent)
        assertEquals("add_glass", chip.clickable.id)
        assertEquals(140f, (chip.width as DimensionBuilders.DpProp).value, 0f)
    }

    @Test
    fun launchActionsDegradeToLoadWithoutLauncherActivity() {
        val json = """{"v":1,"root":{"type":"text","text":"x","modifiers":{"action":{"id":"a","type":"launch"}}}}"""
        val parsed = parser(launchActivity = null).parse(json)
        val text = parsed.root as LayoutElementBuilders.Text
        assertTrue(text.modifiers!!.clickable!!.onClick is ActionBuilders.LoadAction)
        assertEquals(mapOf("a" to "load"), parsed.actions)
    }

    @Test
    fun rejectsMalformedLayouts() {
        val bad = listOf(
            "not json",
            """{"v":2,"root":{"type":"spacer"}}""",
            """{"v":1}""",
            """{"v":1,"root":{"type":"slider"}}""",
            """{"v":1,"root":{"type":"text"}}""",
            """{"v":1,"root":{"type":"column","hAlign":"middle"}}""",
            """{"v":1,"root":{"type":"image","resource":"a","width":"wrap"}}""",
            """{"v":1,"root":{"type":"button","action":{"id":"a"}}}""",
            """{"v":1,"root":{"type":"chip","label":"x","action":{"id":"","type":"load"}}}""",
        )
        for (json in bad) {
            try {
                parser().parse(json)
                fail("Expected failure for $json")
            } catch (e: TileLayoutFormatException) {
                // expected
            }
        }
    }

    @Test
    fun rejectsExcessiveDepth() {
        var json = """{"type":"spacer"}"""
        repeat(TileLayoutParser.MAX_DEPTH) { json = """{"type":"box","children":[$json]}""" }
        try {
            parser().parse("""{"v":1,"root":$json}""")
            fail("Expected depth failure")
        } catch (e: TileLayoutFormatException) {
            assertTrue(e.message!!.contains("deeper"))
        }
    }

    @Test
    fun collectsImageResourcesWithoutRendering() {
        assertEquals(setOf("ic_steps", "ic_refresh"), TileLayoutParser.collectImageResources(stepsJson))
        assertEquals(emptySet<String>(), TileLayoutParser.collectImageResources("broken"))
    }

    @Test
    fun launchIntentEventsAreDecoded() {
        val tile = android.content.Intent()
            .putExtra(WearServiceRegistry.EXTRA_KIND, WearEvent.KIND_TILE)
            .putExtra(WearServiceRegistry.EXTRA_TARGET_ID, "steps")
            .putExtra(WearServiceRegistry.EXTRA_CLICKABLE_ID, "add_250")
        assertEquals(
            WearEvent("tile", "steps", "add_250", "launch", 5L),
            WearOsTilesPlugin.eventFromIntent(tile, now = 5L),
        )
        val complication = android.content.Intent()
            .putExtra(WearServiceRegistry.EXTRA_KIND, WearEvent.KIND_COMPLICATION)
            .putExtra(WearServiceRegistry.EXTRA_TARGET_ID, "default")
        assertEquals(
            WearEvent("complication", "default", null, "tap", 7L),
            WearOsTilesPlugin.eventFromIntent(complication, now = 7L),
        )
        assertNull(WearOsTilesPlugin.eventFromIntent(android.content.Intent()))
    }

    @Test
    fun eventQueueIsBoundedAndDrainedOnce() {
        repeat(WearTilesStore.MAX_PENDING_EVENTS + 5) {
            WearTilesStore.recordEvent(context, WearEvent("tile", "t", "c$it", "load", it.toLong()))
        }
        val drained = WearTilesStore.drainEvents(context)
        assertEquals(WearTilesStore.MAX_PENDING_EVENTS, drained.size)
        assertEquals("c5", drained.first().clickableId)
        assertTrue(WearTilesStore.drainEvents(context).isEmpty())
    }
}
