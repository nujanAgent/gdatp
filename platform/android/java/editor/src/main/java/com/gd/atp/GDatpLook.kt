package com.gd.atp

import java.io.File

/**
 * What a looker is asked about a frame of the running game. Asked to describe one, a vision model finds a pleasant scene in a broken
 * frame; asked to judge it, the same model names what is wrong. Its list is advice for the model building the game: no score is asked
 * for, since a free vision model gives a good frame and a flat one nearly the same number, and what can be measured is measured by
 * the frame check in the game helper.
 */
internal object GDatpLook {
	private val PLAN_LINES = Regex("""(?im)^\W*(Pitch|Look)\W.*$""")

	/**
	 * The question for one frame, or for a burst of [frames] taken [everyMs] apart, which is judged across time: what one
	 * frame cannot show is what moves, what should and does not, and what flickers or vanishes.
	 */
	fun question(project: File?, frames: Int = 1, everyMs: Int = 0): String {
		val plan = project?.let { File(it, "DESIGN.md") }?.takeIf { it.isFile }?.readText().orEmpty()
		val meant = PLAN_LINES.findAll(plan).take(2).joinToString(" ") { it.value.trim() }.take(MAX_PLAN)
		return buildString {
			if (frames > 1) {
				append("These are $frames frames from a game being made, $everyMs ms apart, numbered in reading order, left to right ")
				append("and then down. ")
			} else {
				append("This is a frame from a game being made, about to be shown to the public. ")
			}
			if (meant.isNotEmpty()) append("The plan says: ").append(meant).append(" ")
			append("Judge it as a strict game art director would.\n")
			if (frames > 1) {
				append("1. Say in one line what happens across the frames: what moves, and how. If nothing moves, say so.\n")
				append("2. List everything that looks wrong over time, naming the frame: something that should move and does not, ")
				append("flicker, a jump or a teleport, something that vanishes or pops in, a camera that shakes or drifts, ")
				append("and anything in a single frame that looks broken or unfinished. Most serious first.\n")
			} else {
				append("1. Say in one line what the player is looking at. If you cannot tell, say so.\n")
				append("2. List everything that looks broken, unfinished or wrong: unlit or black areas, missing textures, flat colours, ")
				append("holes in geometry, a camera inside something, overlapping or tiny text, an interface that looks like a default, ")
				append("and anything that does not match the plan. Most serious first.\n")
			}
			append("Be blunt. Do not praise what is merely present.")
		}
	}

	private const val MAX_PLAN = 500
}
