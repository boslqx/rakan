package com.example.rakan

import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/**
 * Picks the user out of everyone MediaPipe sees and stays on them.
 *
 * MediaPipe finds people but does not know who is who, so in a busy gym it
 * can jump to someone walking past. This class decides who the user is:
 *
 *  1. Acquire — the biggest, most central, most visible person, once they
 *     have stayed the best choice for [ACQUIRE_FRAMES] frames in a row.
 *  2. Track — each frame, the person nearest the user's last position with
 *     a similar torso size (and shirt colour) is the user.
 *  3. Lost — if no one matches, report [Outcome.Lost] rather than switch to
 *     someone else; the app pauses rep counting until the user is back.
 *  4. Re-acquire — after [RELAX_AFTER_MS] lost, a match may be anywhere in
 *     frame but must still have a similar size and shirt colour.
 *
 * Pure Kotlin (no Android types) so it can be unit tested on the JVM.
 * Not thread-safe: call it from one thread (MediaPipe's result listener).
 */
class TargetTracker {

    /** One landmark, normalised 0..1 like MediaPipe gives it. */
    data class Pt(val x: Float, val y: Float, val visibility: Float)

    /** A detected person's features, in pixels. */
    class Person(
        /** Index into MediaPipe's result list. */
        val index: Int,
        val centreX: Float,
        val centreY: Float,
        /** Shoulder-midpoint to hip-midpoint distance, px. */
        val size: Float,
        /** Box around the visible landmarks, px². */
        val area: Float,
        /** Mean visibility of shoulders, hips and knees. */
        val visibility: Float,
        /** Mean torso colour, RGB 0..1, or null if it couldn't be sampled. */
        val colour: FloatArray?,
    )

    sealed class Outcome {
        /** Send this person (index into MediaPipe's result list). */
        data class Target(val index: Int) : Outcome()

        /** Nobody usable in frame, and nobody locked yet. */
        object NoOne : Outcome()

        /** The locked user isn't in frame; anyone else visible is ignored. */
        object Lost : Outcome()
    }

    private class Track(
        var centreX: Float,
        var centreY: Float,
        var size: Float,
        var colour: FloatArray?,
        var lastSeenMs: Long,
    )

    private var locked: Track? = null
    private var pending: Track? = null
    private var pendingFrames = 0

    val isLocked: Boolean get() = locked != null

    fun reset() {
        locked = null
        pending = null
        pendingFrames = 0
    }

    fun update(people: List<Person>, frameWidth: Int, frameHeight: Int, timestampMs: Long): Outcome {
        val target = locked
        return if (target == null) {
            acquire(people, frameWidth, frameHeight, timestampMs)
        } else {
            follow(target, people, frameWidth, frameHeight, timestampMs)
        }
    }

    private fun acquire(people: List<Person>, w: Int, h: Int, ts: Long): Outcome {
        val best = people.maxByOrNull { acquireScore(it, w, h) } ?: run {
            pending = null
            pendingFrames = 0
            return Outcome.NoOne
        }

        val p = pending
        if (p != null && isSamePerson(p, best, maxStepSizes = 1.0f, sizeLo = 0.7f, sizeHi = 1.43f)) {
            pendingFrames++
            p.absorb(best, ts)
        } else {
            pending = best.toTrack(ts)
            pendingFrames = 1
        }

        if (pendingFrames >= ACQUIRE_FRAMES) {
            locked = pending
            pending = null
            pendingFrames = 0
        }
        // Shown before the lock lands too, so the skeleton appears at once.
        // The countdown keeps these frames away from rep counting.
        return Outcome.Target(best.index)
    }

    private fun follow(t: Track, people: List<Person>, w: Int, h: Int, ts: Long): Outcome {
        val gapMs = (ts - t.lastSeenMs).coerceAtLeast(0)
        val relaxed = gapMs > RELAX_AFTER_MS

        // How far the user may have moved since last seen, in torso lengths.
        val maxStep = if (relaxed) {
            Float.MAX_VALUE
        } else {
            min(MAX_STEP_CAP, STEP_BASE + STEP_PER_100MS * gapMs / 100f)
        }
        val sizeLo = if (relaxed) 0.6f else 0.75f
        val sizeHi = if (relaxed) 1.67f else 1.33f

        var bestPerson: Person? = null
        var bestCost = Float.MAX_VALUE
        for (person in people) {
            val ratio = person.size / t.size
            if (ratio < sizeLo || ratio > sizeHi) continue

            val step = hypot(person.centreX - t.centreX, person.centreY - t.centreY) / t.size
            if (step > maxStep) continue

            val colourDist = colourDistance(t.colour, person.colour)
            // A stranger of the same build is the main risk once relaxed,
            // so their shirt must match too.
            if (relaxed && colourDist != null && colourDist > RELAXED_COLOUR_GATE) continue

            val cost = step + 2f * abs(ln(ratio)) + 1.5f * (colourDist ?: 0f)
            if (cost < bestCost) {
                bestCost = cost
                bestPerson = person
            }
        }

        val match = bestPerson ?: return Outcome.Lost
        t.absorb(match, ts)
        return Outcome.Target(match.index)
    }

    private fun isSamePerson(t: Track, p: Person, maxStepSizes: Float, sizeLo: Float, sizeHi: Float): Boolean {
        val ratio = p.size / t.size
        if (ratio < sizeLo || ratio > sizeHi) return false
        return hypot(p.centreX - t.centreX, p.centreY - t.centreY) / t.size <= maxStepSizes
    }

    private fun Track.absorb(p: Person, ts: Long) {
        centreX = p.centreX
        centreY = p.centreY
        size = 0.8f * size + 0.2f * p.size
        val c = p.colour
        val old = colour
        colour = when {
            c == null -> old
            old == null -> c.copyOf()
            // Slow blend: lighting shifts as the user moves.
            else -> FloatArray(3) { i -> 0.9f * old[i] + 0.1f * c[i] }
        }
        lastSeenMs = ts
    }

    private fun Person.toTrack(ts: Long) =
        Track(centreX, centreY, size, colour?.copyOf(), ts)

    companion object {
        /** Frames the same person must stay best before being locked (~0.3 s). */
        const val ACQUIRE_FRAMES = 8

        /** Lost this long, a match may come from anywhere in frame. */
        const val RELAX_AFTER_MS = 1500L

        private const val STEP_BASE = 0.4f
        private const val STEP_PER_100MS = 0.6f
        private const val MAX_STEP_CAP = 2.5f

        /** Colour distance (0..1) above which a relaxed match is refused. */
        private const val RELAXED_COLOUR_GATE = 0.25f

        private const val L_SHOULDER = 11
        private const val R_SHOULDER = 12
        private const val L_HIP = 23
        private const val R_HIP = 24
        private const val L_KNEE = 25
        private const val R_KNEE = 26

        /**
         * Builds a [Person] from one MediaPipe pose, or null if the torso
         * isn't visible enough to track.
         */
        fun describe(index: Int, lm: List<Pt>, frameWidth: Int, frameHeight: Int, colour: FloatArray?): Person? {
            if (lm.size <= R_KNEE) return null
            val torso = listOf(lm[L_SHOULDER], lm[R_SHOULDER], lm[L_HIP], lm[R_HIP])
            if (torso.any { it.visibility < 0.3f }) return null

            val w = frameWidth.toFloat()
            val h = frameHeight.toFloat()
            val shX = (lm[L_SHOULDER].x + lm[R_SHOULDER].x) / 2f * w
            val shY = (lm[L_SHOULDER].y + lm[R_SHOULDER].y) / 2f * h
            val hipX = (lm[L_HIP].x + lm[R_HIP].x) / 2f * w
            val hipY = (lm[L_HIP].y + lm[R_HIP].y) / 2f * h
            val size = hypot(hipX - shX, hipY - shY)
            if (size < 1f) return null

            var minX = Float.MAX_VALUE
            var minY = Float.MAX_VALUE
            var maxX = -Float.MAX_VALUE
            var maxY = -Float.MAX_VALUE
            for (p in lm) {
                if (p.visibility < 0.5f) continue
                minX = min(minX, p.x * w); maxX = max(maxX, p.x * w)
                minY = min(minY, p.y * h); maxY = max(maxY, p.y * h)
            }
            val area = if (maxX > minX && maxY > minY) (maxX - minX) * (maxY - minY) else size * size

            val key = intArrayOf(L_SHOULDER, R_SHOULDER, L_HIP, R_HIP, L_KNEE, R_KNEE)
            val visibility = key.map { lm[it].visibility }.average().toFloat()

            return Person(index, (shX + hipX) / 2f, (shY + hipY) / 2f, size, area, visibility, colour)
        }

        /** Bigger, more central and more visible scores higher. */
        fun acquireScore(p: Person, frameWidth: Int, frameHeight: Int): Float {
            val areaShare = (p.area / (frameWidth.toFloat() * frameHeight)).coerceIn(0f, 1f)
            val halfDiag = hypot(frameWidth / 2f, frameHeight / 2f)
            val offCentre = hypot(p.centreX - frameWidth / 2f, p.centreY - frameHeight / 2f) / halfDiag
            val centrality = (1f - offCentre).coerceAtLeast(0.05f)
            return areaShare * centrality * p.visibility
        }

        /** 0 = same colour, 1 = black vs white. Null if either is unknown. */
        fun colourDistance(a: FloatArray?, b: FloatArray?): Float? {
            if (a == null || b == null) return null
            val dr = a[0] - b[0]
            val dg = a[1] - b[1]
            val db = a[2] - b[2]
            return sqrt(dr * dr + dg * dg + db * db) / sqrt(3f)
        }
    }
}
