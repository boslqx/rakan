package com.example.rakan

import com.example.rakan.TargetTracker.Outcome
import com.example.rakan.TargetTracker.Person
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TargetTrackerTest {
    private val w = 640
    private val h = 480
    private val red = floatArrayOf(0.8f, 0.1f, 0.1f)
    private val blue = floatArrayOf(0.1f, 0.1f, 0.8f)

    private fun person(index: Int, x: Float, y: Float, size: Float, colour: FloatArray? = red) =
        Person(index, x, y, size, area = size * size * 6f, visibility = 0.9f, colour = colour)

    /** Feeds [frames] identical frames ~33 ms apart, starting at [startMs]. */
    private fun TargetTracker.feed(people: List<Person>, frames: Int, startMs: Long = 0): Outcome {
        var out: Outcome = Outcome.NoOne
        for (f in 0 until frames) out = update(people, w, h, startMs + f * 33L)
        return out
    }

    @Test
    fun locksOntoBiggestCentralPerson() {
        val t = TargetTracker()
        val user = person(1, 320f, 240f, 120f)
        val passerBy = person(0, 80f, 240f, 60f, blue)
        val out = t.feed(listOf(passerBy, user), TargetTracker.ACQUIRE_FRAMES)
        assertTrue(t.isLocked)
        assertEquals(Outcome.Target(1), out)
    }

    @Test
    fun staysOnUserWhenAnotherPersonComesCloser() {
        val t = TargetTracker()
        t.feed(listOf(person(0, 320f, 240f, 100f)), TargetTracker.ACQUIRE_FRAMES)
        // Someone bigger walks in at the edge; MediaPipe now lists them first.
        val out = t.update(
            listOf(person(0, 560f, 240f, 160f, blue), person(1, 325f, 245f, 100f)),
            w, h, TargetTracker.ACQUIRE_FRAMES * 33L,
        )
        assertEquals(Outcome.Target(1), out)
    }

    @Test
    fun reportsLostInsteadOfSwitching() {
        val t = TargetTracker()
        t.feed(listOf(person(0, 320f, 240f, 100f)), TargetTracker.ACQUIRE_FRAMES)
        // User blocked; only a stranger far away is visible.
        val out = t.update(listOf(person(0, 560f, 240f, 100f, blue)), w, h, 400)
        assertEquals(Outcome.Lost, out)
    }

    @Test
    fun reacquiresUserWhoMovedAfterLongLoss() {
        val t = TargetTracker()
        t.feed(listOf(person(0, 320f, 240f, 100f)), TargetTracker.ACQUIRE_FRAMES)
        val later = 300 + TargetTracker.RELAX_AFTER_MS
        // Back, but in a new spot; a stranger in a different shirt is also there.
        val out = t.update(
            listOf(person(0, 300f, 240f, 100f, blue), person(1, 520f, 240f, 105f, red)),
            w, h, later,
        )
        assertEquals(Outcome.Target(1), out)
    }

    @Test
    fun refusesSameBuildStrangerInDifferentShirtAfterLongLoss() {
        val t = TargetTracker()
        t.feed(listOf(person(0, 320f, 240f, 100f)), TargetTracker.ACQUIRE_FRAMES)
        val out = t.update(listOf(person(0, 500f, 240f, 100f, blue)), w, h, 5000)
        assertEquals(Outcome.Lost, out)
    }

    @Test
    fun followsNormalMovementDuringASquat() {
        val t = TargetTracker()
        t.feed(listOf(person(0, 320f, 200f, 100f)), TargetTracker.ACQUIRE_FRAMES)
        var y = 200f
        var ts = TargetTracker.ACQUIRE_FRAMES * 33L
        repeat(30) {
            y += 4f // hips drop ~120 px over a second
            ts += 33
            assertEquals(Outcome.Target(0), t.update(listOf(person(0, 320f, y, 95f)), w, h, ts))
        }
    }

    @Test
    fun doesNotLockWhileBestPersonKeepsChanging() {
        val t = TargetTracker()
        val a = person(0, 200f, 240f, 100f)
        val b = person(0, 440f, 240f, 100f)
        repeat(TargetTracker.ACQUIRE_FRAMES * 2) { f ->
            t.update(listOf(if (f % 2 == 0) a else b), w, h, f * 33L)
        }
        assertFalse(t.isLocked)
    }

    @Test
    fun describeRejectsHiddenTorso() {
        val pts = List(33) { TargetTracker.Pt(0.5f, 0.5f, 0.9f) }.toMutableList()
        pts[23] = TargetTracker.Pt(0.5f, 0.8f, 0.1f)
        assertEquals(null, TargetTracker.describe(0, pts, w, h, null))
    }
}
