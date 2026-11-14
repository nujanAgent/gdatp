package com.gd.atp

import java.io.File

/**
 * What a project still lacks of a complete game, read from its files and given with each run of it. A model tends to stop once
 * something runs, and it follows what a tool's answer says more surely than instructions it read earlier. These are signs, not
 * proof, so an item can be answered by saying why this game does not need it.
 */
internal object GDatpAudit {

	/** Changes when the game's code does: its scripts and scenes, by name, size and time. */
	fun codeMark(project: File): Long = project.walkTopDown()
		.onEnter { it.name !in SKIPPED_FOLDERS && it.name != GDatpParts.FOLDER }
		.filter { it.isFile && it.extension in CODE_KINDS }
		.sumOf { (it.path.hashCode() * 31L + it.length()) * 31L + it.lastModified() }

	/** The things to do next, most basic first; empty when every sign is there. */
	fun missing(project: File, guideTopics: Set<String>): List<String> {
		val files = project.walkTopDown()
			.onEnter { it.name !in SKIPPED_FOLDERS && it.name != GDatpParts.FOLDER }
			.filter { it.isFile }
			.toList()
		val code = files.filter { it.extension in CODE_KINDS && it.length() <= MAX_READ_BYTES }.joinToString("\n") { it.readText() }
		val gameLines = files.filter { it.extension == "gd" && it.length() <= MAX_READ_BYTES }.sumOf { file -> file.readLines().count { it.isNotBlank() } }
		fun uses(vararg parts: String) = parts.any { code.contains("parts/$it.gd") }
		val art = files.count { it.extension in ART_KINDS && it.name != ICON }
		// Reading and studying shape a game before it is written; asked of a written one, they only delay the change at hand.
		val building = gameLines < ENOUGH_GAME_LINES
		val found = mutableListOf<String>()
		if (building && (GUIDE_START !in guideTopics || guideTopics.size < ENOUGH_TOPICS)) {
			found += "Read more of guide: you have read ${guideTopics.size} topic(s). Read start, this game's genre_ topic, its style_ topic, and the sys_ topics for what it uses."
		}
		val design = File(project, DESIGN_FILE).takeIf { it.isFile }?.readText().orEmpty()
		if (design.isEmpty()) {
			found += "There is no res://DESIGN.md. Write the plan: guide start says what it holds."
		} else {
			DESIGN_LABELS.filter { !Regex("""^\W*$it\W""", setOf(RegexOption.IGNORE_CASE, RegexOption.MULTILINE)).containsMatchIn(design) }
				.takeIf { it.isNotEmpty() }
				?.let { found += "DESIGN.md has no line starting ${it.joinToString(", ") { label -> "$label:" }}. For Studied, look at real examples first (guide study)." }
		}
		if (building && !studyKept(project)) {
			found += "Nothing you studied is kept in res://${GDatpAssets.STUDY_FOLDER}. Look at real pictures of what this game is like with the host's web and picture tools, then keep the ones you learned from: assets fetch with url and into study. A Studied line from memory is not study (guide study)."
		}
		if (building) found += "Only $gameLines lines of this game's own code so far. Parts are not a game: write what it is made of, such as its goal, what stands in the way, its levels or waves, and what the player earns."
		if (!code.contains(SCENE_CHANGE) && !uses("screens")) found += "Nothing changes scene or restarts: add a way in, an end and a way to play again (parts add screens, guide sys_flow)."
		if (!code.contains(".paused") && !uses("screens")) found += "There is no pause (parts add screens, guide sys_flow)."
		if (!code.contains(TOUCH) && !uses("touch")) found += "Nothing here reads a touch: this is played on a phone (parts add touch, guide sys_touch)."
		if (files.none { it.extension in SOUND_KINDS } && !code.contains("AudioStreamGenerator") && !uses("sfx", "music")) found += "There is no sound (parts add sfx music, or audio_edit; guide sys_audio)."
		if (art == 0 && files.none { it.extension == "gdshader" } && !code.contains(DRAWN) && !uses("paint", "sky", "level2d", "backdrop2d", "voxel_world")) found += "There is no art: plain shapes only. Apply the plan's look (parts add paint sky level2d backdrop2d, guide style_ topics, image_edit, world3d_edit model)."
		if (!code.contains(MOTION) && !uses("juice")) found += "Nothing moves with feeling: no tweens or particles (parts add juice, guide sys_juice, sys_particles)."
		if (!code.contains("user://") && !uses("save", "screens")) found += "Nothing is saved between runs (parts add save, guide sys_save)."
		return found + neverRuns(project, files) + runsTwice(files) + tapsTwice(project, files)
	}

	/**
	 * A script reading a tap as a screen touch and as a mouse press. A phone sends each touch as both unless the project turns
	 * that off, so what it does happens twice: a toggle tapped twice has not changed, and no run reports an error.
	 */
	private fun tapsTwice(project: File, files: List<File>): List<String> {
		if (File(project, PROJECT_FILE).takeIf { it.isFile }?.readText().orEmpty().contains(MOUSE_FROM_TOUCH_OFF)) return emptyList()
		return files.filter { it.extension == "gd" && it.length() <= MAX_READ_BYTES }
			.filter { script -> script.readText().let { "InputEventScreenTouch" in it && "InputEventMouseButton" in it && "is_touchscreen_available" !in it } }
			.map { "res://${it.relativeTo(project).invariantSeparatorsPath} reads both InputEventScreenTouch and InputEventMouseButton. A phone sends each tap as both, so what it does happens twice: a toggle tapped twice has not changed. Read InputEventScreenTouch alone (guide sys_touch)." }
	}

	/**
	 * Code written and never reached: scripts nothing loads, and checks for a method no script that runs has. A model that adds a
	 * feature this way reports it done, and it fails silently, so a run finds no error.
	 */
	private fun neverRuns(project: File, files: List<File>): List<String> {
		val texts = files.filter { (it.extension in CODE_KINDS || it.name == PROJECT_FILE) && it.length() <= MAX_READ_BYTES }.associateWith { it.readText() }
		val unused = files.filter { it.extension == "gd" }.filter { script ->
			val className = CLASS_NAME.find(texts[script].orEmpty())?.groupValues?.get(1)
			texts.none { (other, text) -> other != script && (script.name in text || (className != null && Regex("""\b$className\b""").containsMatchIn(text))) }
		}
		val running = (texts - unused.toSet()).values.joinToString("\n")
		val parts = File(project, GDatpParts.FOLDER).listFiles().orEmpty().filter { it.extension == "gd" }.joinToString("\n") { it.readText() }
		val absent = HAS_METHOD.findAll(running).map { it.groupValues[1] }.distinct()
			.filter { !Regex("""func\s+$it\b""").containsMatchIn(running + parts) }
		return unused.map { "res://${it.relativeTo(project).invariantSeparatorsPath} is used by nothing: no scene holds it and no script loads it, so what it does never happens. Attach it, or move what it does into code that runs." } +
			absent.map { "Code asks has_method(\"$it\"), and no script that runs has func $it, so what depends on it never happens. Write the method where it will be called, and call it directly." }.toList()
	}

	/** A script that is an autoload and is also on a scene's node: each runs it, with its own copy of everything it makes. */
	private fun runsTwice(files: List<File>): List<String> {
		val settings = files.firstOrNull { it.name == PROJECT_FILE }?.readText().orEmpty()
		val scenes = files.filter { it.extension == "tscn" && it.length() <= MAX_READ_BYTES }.map { it.readText() }
		return AUTOLOAD.findAll(settings.substringAfter("[autoload]", "").substringBefore("\n[")).map { it.groupValues[1] }
			.filter { script -> script.endsWith(".gd") && scenes.any { "path=\"$script\"" in it } }
			.map { "$it is an autoload and is also on a node in a scene, so it runs twice, each with its own copy of everything it makes. Keep what is shared in a script of its own, such as res://game_state.gd, and make that the autoload." }
			.toList()
	}

	/** Whether a picture, model, sound or project fetched to study is in the project, by its contents: a file written there is not something looked at. */
	private fun studyKept(project: File): Boolean = File(project, GDatpAssets.STUDY_FOLDER).walkTopDown().any { it.isFile && (it.name == PROJECT_FILE || isFetchedKind(it)) }

	private fun isFetchedKind(file: File): Boolean {
		val head = ByteArray(FETCHED_HEADS.maxOf { it.size })
		val read = file.inputStream().use { it.read(head) }
		return FETCHED_HEADS.any { kind -> read >= kind.size && kind.indices.all { head[it] == kind[it] } }
	}

	/** How PNG, JPEG, GIF, WebP or WAV, glTF binary and Ogg files begin. */
	private val FETCHED_HEADS = listOf(
		byteArrayOf(0x89.toByte(), 0x50, 0x4E, 0x47),
		byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 0xFF.toByte()),
		"GIF8".toByteArray(),
		"RIFF".toByteArray(),
		"glTF".toByteArray(),
		"OggS".toByteArray(),
	)
	private const val PROJECT_FILE = "project.godot"
	private val CLASS_NAME = Regex("""(?m)^class_name\s+(\w+)""")
	private val AUTOLOAD = Regex("""(?m)^\w+="\*?(res://[^"]+)"""")
	private val HAS_METHOD = Regex("""has_method\(\s*"(\w+)"\s*\)""")
	private val SKIPPED_FOLDERS = setOf(".godot", "addons", GDatpAssets.STUDY_FOLDER, ".git")
	private val CODE_KINDS = setOf("gd", "tscn", "tres")
	private val ART_KINDS = setOf("png", "jpg", "jpeg", "webp", "svg", "glb", "gltf")
	private val SOUND_KINDS = setOf("wav", "ogg", "mp3")
	private val DESIGN_LABELS = listOf("Pitch", "Core verb", "The one thing", "Studied", "Look")
	private val SCENE_CHANGE = Regex("""change_scene|reload_current_scene""")
	private val TOUCH = Regex("""TouchScreenButton|InputEventScreen|type="Button"|Button\.new|_gui_input|\.pressed\.connect""")
	private val DRAWN = Regex("""func _draw\(|world3d|MeshInstance3D|Polygon2D|Line2D""")
	private const val MOUSE_FROM_TOUCH_OFF = "emulate_mouse_from_touch=false"
	private val MOTION = Regex("""create_tween|CPUParticles|GPUParticles|AnimationPlayer|AnimatedSprite""")
	private const val DESIGN_FILE = "DESIGN.md"
	private const val ICON = "icon.svg"
	private const val GUIDE_START = "start"
	private const val ENOUGH_TOPICS = 3
	private const val ENOUGH_GAME_LINES = 200
	private const val MAX_READ_BYTES = 512L * 1024
}
