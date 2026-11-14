package com.gd.atp

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * Tested systems a game is built on, carried in the app and copied into a project when asked for. A part does one thing every game
 * needs, such as touch controls or a sky, and holds no game: no scene, no rules, no content. A free model cannot write these well,
 * and what it writes instead is what makes its games look unfinished, so its effort goes into what makes this game different.
 */
internal class GDatpParts(private val context: Context) {

	/** Every part with the one line that says what it is. */
	fun list(): JSONArray {
		val listed = JSONArray()
		for (name in names()) {
			listed.put(JSONObject().put("part", name).put("what", header(text(name)).firstOrNull().orEmpty()))
		}
		return listed
	}

	/** How to use each of [wanted], and those it needs, as its header says; [unknown] is left to the caller to report. */
	fun show(wanted: List<String>): JSONArray {
		val shown = JSONArray()
		for (name in withNeeds(wanted)) {
			shown.put(JSONObject().put("part", name).put("path", resPath(name)).put("use", header(text(name)).joinToString("\n")))
		}
		return shown
	}

	/**
	 * Places [wanted] and what they need in [project], and says how to use each. A part already there is left alone, since the project
	 * may have changed it.
	 */
	fun add(wanted: List<String>, project: File): JSONArray {
		val folder = File(project, FOLDER).apply { mkdirs() }
		val added = JSONArray()
		for (name in withNeeds(wanted)) {
			val file = File(folder, "$name$KIND")
			val kept = file.isFile
			if (!kept) file.writeText(text(name))
			added.put(JSONObject().put("part", name).put("path", resPath(name)).put("already_here", kept).put("use", header(text(name)).joinToString("\n")))
		}
		return added
	}

	fun unknown(wanted: List<String>): List<String> = wanted.filter { it !in names() }

	/** Places what nearly every game needs in a new [project]. They do nothing until the game's code uses them. */
	fun addEveryGameParts(project: File): JSONArray = add(EVERY_GAME, project)

	private fun names(): List<String> = context.assets.list(ASSETS).orEmpty().filter { it.endsWith(KIND) }.map { it.removeSuffix(KIND) }.sorted()

	private fun text(name: String): String = context.assets.open("$ASSETS/$name$KIND").bufferedReader().use { it.readText() }

	/** [wanted] with every part their code preloads, needed ones first. A part's header shows preloads as examples, so it does not count. */
	private fun withNeeds(wanted: List<String>): List<String> {
		val seen = HashSet<String>()
		val ordered = ArrayList<String>()
		fun visit(name: String) {
			if (!seen.add(name)) return
			text(name).lineSequence().filterNot { it.startsWith(DOC) }.flatMap { NEED.findAll(it) }.map { it.groupValues[1] }.toList().forEach(::visit)
			ordered += name
		}
		wanted.forEach(::visit)
		return ordered
	}

	/** The `##` lines at the top of a part, with the mark taken off. */
	private fun header(text: String): List<String> = text.lineSequence()
		.dropWhile { !it.startsWith(DOC) }
		.takeWhile { it.startsWith(DOC) }
		.map { it.removePrefix(DOC).removePrefix(" ") }
		.toList()

	private fun resPath(name: String) = "res://$FOLDER/$name$KIND"

	companion object {
		const val FOLDER = "parts"
		private const val ASSETS = "gdatp/parts"
		private const val KIND = ".gd"
		private const val DOC = "##"
		private val NEED = Regex("""preload\("res://parts/(\w+)\.gd"\)""")
		private val EVERY_GAME = listOf("touch", "screens", "sfx", "juice", "save", "paint")
	}
}
