package dev.manishpanday.wear_os_tiles

import androidx.wear.watchface.complications.data.ComplicationType
import androidx.wear.watchface.complications.data.LongTextComplicationData
import androidx.wear.watchface.complications.data.NoDataComplicationData
import androidx.wear.watchface.complications.data.RangedValueComplicationData
import androidx.wear.watchface.complications.data.ShortTextComplicationData
import androidx.test.core.app.ApplicationProvider
import androidx.wear.watchface.complications.data.ComplicationText
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** Maps Dart's `ComplicationData.toJson()` output to androidx complication data. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ComplicationDataMapperTest {

    private val resources = ApplicationProvider.getApplicationContext<android.content.Context>().resources

    /** ComplicationText.toString() is redacted; resolve the real text. */
    private fun ComplicationText?.str(): String = this!!.getTextAt(resources, Instant.now()).toString()

    private val ranged = StoredComplication.parse(
        """{"type":"rangedValue","text":"6.2k","title":"Steps","contentDescription":"6200 of 10000 steps","value":6200.0,"min":0.0,"max":10000.0,"tapLaunchesApp":true}""",
    )
    private val short = StoredComplication.parse(
        """{"type":"shortText","text":"3/8","title":"Water","tapLaunchesApp":false}""",
    )

    @Test
    fun rangedValueAnswersRangedRequests() {
        val data = ComplicationDataMapper.map(ranged, ComplicationType.RANGED_VALUE, null)
        data as RangedValueComplicationData
        assertEquals(6200f, data.value, 0f)
        assertEquals(0f, data.min, 0f)
        assertEquals(10000f, data.max, 0f)
        assertEquals("6.2k", data.text.str())
        assertEquals("Steps", data.title.str())
        assertEquals("6200 of 10000 steps", data.contentDescription.str())
    }

    @Test
    fun rangedValueConvertsToText() {
        val s = ComplicationDataMapper.map(ranged, ComplicationType.SHORT_TEXT, null)
        assertEquals("6.2k", (s as ShortTextComplicationData).text.str())
        val l = ComplicationDataMapper.map(ranged, ComplicationType.LONG_TEXT, null)
        assertEquals("6.2k", (l as LongTextComplicationData).text.str())

        val noText = ranged.copy(text = null, value = 42f)
        val formatted = ComplicationDataMapper.map(noText, ComplicationType.SHORT_TEXT, null)
        assertEquals("42", (formatted as ShortTextComplicationData).text.str())
        assertEquals("2.5", ComplicationDataMapper.formatValue(2.5f))
    }

    @Test
    fun textDataCannotBecomeRanged() {
        val s = ComplicationDataMapper.map(short, ComplicationType.SHORT_TEXT, null)
        s as ShortTextComplicationData
        assertEquals("3/8", s.text.str())
        assertEquals("Water", s.title.str())
        assertTrue(ComplicationDataMapper.map(short, ComplicationType.LONG_TEXT, null) is LongTextComplicationData)
        assertTrue(ComplicationDataMapper.map(short, ComplicationType.RANGED_VALUE, null) is NoDataComplicationData)
        assertTrue(ComplicationDataMapper.map(short, ComplicationType.SMALL_IMAGE, null) is NoDataComplicationData)
    }

    @Test
    fun valueIsClampedIntoRange() {
        val over = ranged.copy(value = 12000f)
        val data = ComplicationDataMapper.map(over, ComplicationType.RANGED_VALUE, null)
        assertEquals(10000f, (data as RangedValueComplicationData).value, 0f)
    }

    @Test
    fun previewDataExistsForSupportedTypes() {
        assertTrue(ComplicationDataMapper.preview(ComplicationType.SHORT_TEXT, "60%", "App") is ShortTextComplicationData)
        assertTrue(ComplicationDataMapper.preview(ComplicationType.LONG_TEXT, "60%", "App") is LongTextComplicationData)
        assertTrue(ComplicationDataMapper.preview(ComplicationType.RANGED_VALUE, "60%", "App") is RangedValueComplicationData)
        assertNull(ComplicationDataMapper.preview(ComplicationType.PHOTO_IMAGE, "60%", "App"))
    }

    @Test(expected = IllegalArgumentException::class)
    fun unknownTypeIsRejected() {
        StoredComplication.parse("""{"type":"photo"}""")
    }
}
