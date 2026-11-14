package com.gd.atp

import android.content.Context
import android.os.Build
import android.os.Environment
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * The Godot projects GDatp can open, and new ones made for it: in GDatp's own storage, in the Project Manager's list,
 * and in shared Documents when the person gave GDatp all files access. Works with no editor running.
 */
class GDatpProjects(private val context: Context) {

	/** One project: its folder, and what its project.godot says. */
	data class Project(val name: String, val path: String, val mainScene: String?, val changed: Long) {
		fun toJson(): JSONObject = JSONObject()
			.put("name", name)
			.put("path", path)
			.put("main_scene", mainScene ?: JSONObject.NULL)
			.put("changed", changed)
	}

	/** Where new projects go: GDatp's own storage, which needs no permission. */
	private val home: File get() = File(context.filesDir, "projects")

	/** Where a deleted project waits to be restored, beside the projects. */
	private val trash: File get() = File(context.filesDir, "projects-trash")

	private val projectList: File get() = File(context.filesDir, "godot/projects.cfg")

	fun all(): List<Project> {
		val folders = linkedSetOf<File>()
		home.listFiles()?.filter { File(it, PROJECT_FILE).isFile }?.forEach { folders += it.canonicalFile }
		listedPaths().map(::File).filter { File(it, PROJECT_FILE).isFile }.forEach { folders += it.canonicalFile }
		documents()?.listFiles()?.filter { File(it, PROJECT_FILE).isFile }?.forEach { folders += it.canonicalFile }
		return folders.mapNotNull(::read).sortedByDescending { it.changed }
	}

	/** The project called [nameOrPath], by its name, its folder's name or its folder's path. */
	fun find(nameOrPath: String): Project? {
		val wanted = nameOrPath.trim().removeSuffix("/").removeSuffix("/$PROJECT_FILE")
		if (wanted.startsWith("/")) return read(File(wanted))
		return all().firstOrNull { it.name.equals(wanted, ignoreCase = true) } ?: all().firstOrNull { File(it.path).name.equals(wanted, ignoreCase = true) }
	}

	/**
	 * Makes a new project from [template] (2d, 3d or empty) for [renderer], with the settings and files Godot's Project
	 * Manager gives a new project (its default icon, Git and editor settings), and lists it in the Project Manager.
	 */
	fun create(name: String, template: String, portrait: Boolean, pixelArt: Boolean, renderer: String = DEFAULT_RENDERER): Project {
		require(name.isNotBlank()) { "a project needs a name" }
		require(template in TEMPLATES) { "template is one of ${TEMPLATES.joinToString()}" }
		require(renderer in RENDERERS) { "renderer is one of ${RENDERERS.keys.joinToString()}" }
		val folder = freeFolder(slug(name))
		check(folder.mkdirs()) { "GDatp could not make the folder ${folder.path}" }
		File(folder, PROJECT_FILE).writeText(projectGodot(name, template, portrait, pixelArt, renderer))
		mainScene(template)?.let { File(folder, MAIN_SCENE).writeText(it) }
		context.assets.open(ICON_ASSET).use { icon -> File(folder, ICON).outputStream().use(icon::copyTo) }
		File(folder, ".gitignore").writeText("# Godot 4+ specific ignores\n.godot/\n/android/\n")
		File(folder, ".gitattributes").writeText("# Normalize EOL for all files that Git considers text files.\n* text=auto eol=lf\n")
		File(folder, ".editorconfig").writeText("root = true\n\n[*]\ncharset = utf-8\n")
		val project = read(folder) ?: error("the new project at ${folder.path} could not be read back")
		remember(project)
		return project
	}

	/** Adds [project] to the Project Manager's list, so the person finds it there too. */
	fun remember(project: Project) {
		val path = File(project.path).canonicalPath
		if (path in listedPaths()) return
		projectList.parentFile?.mkdirs()
		val before = if (projectList.isFile) projectList.readText().trimEnd() + "\n\n" else ""
		projectList.writeText("$before[$path]\n\nfavorite=false\n")
	}

	fun toJson(projects: List<Project>): JSONArray = JSONArray().apply { projects.forEach { put(it.toJson()) } }

	/** [projects] with what each one's plan says it is, so a new game can be made different from them. */
	fun withDesigns(projects: List<Project>): JSONArray = JSONArray().apply {
		projects.forEach { project ->
			val entry = project.toJson()
			designOf(project)?.let { entry.put("design", it) }
			put(entry)
		}
	}

	private fun designOf(project: Project): JSONObject? {
		val file = File(project.path, DESIGN_FILE)
		if (!file.isFile) return null
		val found = JSONObject()
		DESIGN_LINE.findAll(file.readText().take(DESIGN_READ_CHARS)).forEach { match ->
			val key = match.groupValues[1].lowercase().replace(' ', '_')
			if (!found.has(key)) found.put(key, match.groupValues[2].trim().take(DESIGN_LINE_CHARS))
		}
		return found.takeIf { it.length() > 0 }
	}

	/** [project]'s renderer, what it holds and the room it takes, leaving out Godot's import cache. */
	fun info(project: Project): JSONObject {
		val folder = File(project.path)
		val files = filesOf(folder)
		val method = RENDERING_METHOD.find(File(folder, PROJECT_FILE).readText())?.groupValues?.get(1) ?: GODOT_DEFAULT_METHOD
		return project.toJson()
			.put("renderer", RENDERERS.entries.firstOrNull { it.value.first == method }?.key ?: method)
			.put("bytes", files.sumOf { it.length() })
			.put("files", files.size)
			.put("scenes", files.count { it.extension in SCENE_EXTENSIONS })
			.put("scripts", files.count { it.extension == "gd" })
			.put("in_gdatp_storage", inHome(folder))
	}

	/** Gives [project] the name [name]; its folder keeps its own. */
	fun rename(project: Project, name: String): Project {
		require(name.isNotBlank()) { "a project needs a name" }
		val folder = File(project.path)
		named(folder, name)
		return read(folder) ?: error("the renamed project at ${folder.path} could not be read back")
	}

	/** A copy of [project] called [name] in GDatp's storage, without Godot's import cache, which it rebuilds on opening. */
	fun duplicate(project: Project, name: String): Project {
		require(name.isNotBlank()) { "a copy needs a name" }
		val source = File(project.path)
		val needs = filesOf(source).sumOf { it.length() }
		home.mkdirs()
		check(home.usableSpace > needs + RESERVE_BYTES) { "the copy needs ${needs / MIB} MiB and the phone has ${home.usableSpace / MIB} MiB free" }
		val folder = freeFolder(slug(name))
		try {
			source.walkTopDown().onEnter { it.name != CACHE }.forEach { file ->
				val target = File(folder, file.relativeTo(source).path)
				if (file.isDirectory) target.mkdirs() else file.copyTo(target)
			}
		} catch (e: java.io.IOException) {
			// A copy cut short is not a project, so it is not left behind as one.
			folder.deleteRecursively()
			throw e
		}
		named(folder, name)
		val copy = read(folder) ?: error("the copy at ${folder.path} could not be read back")
		remember(copy)
		return copy
	}

	/**
	 * Moves [project] into GDatp's trash, where [restore] finds it for [TRASH_DAYS] days, and takes it off the Project
	 * Manager's list. Only a project in GDatp's own storage is moved; one elsewhere is the person's to remove.
	 */
	fun delete(project: Project): JSONObject {
		val folder = File(project.path)
		require(inHome(folder)) { "GDatp deletes only projects in its own storage; ${project.path} is left where it is" }
		trash.mkdirs()
		val deleted = File(trash, "${folder.name}$STAMP${System.currentTimeMillis()}")
		check(folder.renameTo(deleted)) { "GDatp could not move ${folder.path} to its trash" }
		forget(folder.canonicalPath)
		emptyOldTrash()
		return deletedJson(deleted) ?: JSONObject().put("name", project.name)
	}

	/** The projects in GDatp's trash, most recently deleted first. */
	fun deleted(): List<JSONObject> {
		emptyOldTrash()
		return trashed().mapNotNull(::deletedJson)
	}

	/** Brings back the most recently deleted project called [nameOrFolder] into GDatp's storage, and lists it again. */
	fun restore(nameOrFolder: String): Project {
		val wanted = nameOrFolder.trim()
		val folder = trashed().firstOrNull { read(it)?.name.equals(wanted, ignoreCase = true) }
			?: trashed().firstOrNull { it.name.substringBefore(STAMP).equals(wanted, ignoreCase = true) }
			?: throw IllegalArgumentException("GDatp's trash has no project '$wanted'")
		home.mkdirs()
		val target = freeFolder(folder.name.substringBefore(STAMP))
		check(folder.renameTo(target)) { "GDatp could not move ${folder.path} back to ${target.path}" }
		val project = read(target) ?: error("the restored project at ${target.path} could not be read back")
		remember(project)
		return project
	}

	private fun trashed(): List<File> =
		trash.listFiles()?.filter { it.isDirectory && STAMP in it.name }?.sortedByDescending(::deletedAt).orEmpty()

	private fun deletedAt(folder: File): Long = folder.name.substringAfterLast(STAMP).toLongOrNull() ?: folder.lastModified()

	private fun deletedJson(folder: File): JSONObject? {
		val project = read(folder) ?: return null
		val at = deletedAt(folder)
		return JSONObject().put("name", project.name).put("folder", folder.name.substringBefore(STAMP))
			.put("deleted", at).put("kept_until", at + TRASH_DAYS * DAY_MS)
	}

	/** Removes what has been in the trash longer than [TRASH_DAYS] days, so it does not grow without end. */
	private fun emptyOldTrash() {
		val oldest = System.currentTimeMillis() - TRASH_DAYS * DAY_MS
		trashed().filter { deletedAt(it) < oldest }.forEach { it.deleteRecursively() }
	}

	/** Takes [path] off the Project Manager's list. */
	private fun forget(path: String) {
		if (!projectList.isFile) return
		val sections = projectList.readText().split(Regex("""\n(?=\[)""")).map { it.trim() }.filter { it.isNotEmpty() }
		val kept = sections.filterNot { it.lineSequence().first().trim() == "[$path]" }
		if (kept.size != sections.size) projectList.writeText(kept.joinToString("\n\n", postfix = "\n"))
	}

	/** Sets the name in [folder]'s project.godot. */
	private fun named(folder: File, name: String) {
		val file = File(folder, PROJECT_FILE)
		val line = "config/name=\"${quoted(name)}\""
		val text = file.readText()
		file.writeText(
			when {
				NAME_LINE.containsMatchIn(text) -> text.replace(NAME_LINE, Regex.escapeReplacement(line))
				"[application]" in text -> text.replaceFirst("[application]\n", "[application]\n\n$line\n")
				else -> text.trimEnd() + "\n\n[application]\n\n$line\n"
			},
		)
	}

	private fun filesOf(folder: File): List<File> = folder.walkTopDown().onEnter { it.name != CACHE }.filter { it.isFile }.toList()

	private fun inHome(folder: File): Boolean = folder.canonicalFile.parentFile == home.canonicalFile

	private fun quoted(name: String): String = name.replace("\\", "\\\\").replace("\"", "\\\"")

	private fun read(folder: File): Project? {
		val file = File(folder, PROJECT_FILE)
		if (!file.isFile) return null
		val text = runCatching { file.readText() }.getOrNull() ?: return null
		val name = Regex("""^config/name="(.*)"$""", RegexOption.MULTILINE).find(text)?.groupValues?.get(1) ?: folder.name
		val main = Regex("""^run/main_scene="(.*)"$""", RegexOption.MULTILINE).find(text)?.groupValues?.get(1)
		val changed = filesOf(folder).maxOfOrNull { it.lastModified() } ?: file.lastModified()
		return Project(name, folder.canonicalPath, main, changed)
	}

	private fun listedPaths(): List<String> = runCatching {
		projectList.readLines().mapNotNull { line -> line.trim().takeIf { it.startsWith("[/") && it.endsWith("]") }?.removeSurrounding("[", "]") }
	}.getOrDefault(emptyList())

	private fun documents(): File? {
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && !Environment.isExternalStorageManager()) return null
		return Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOCUMENTS).takeIf { it.isDirectory }
	}

	private fun freeFolder(slug: String): File {
		var folder = File(home, slug)
		var n = 2
		while (folder.exists()) folder = File(home, "$slug-${n++}")
		return folder
	}

	private fun slug(name: String): String =
		name.lowercase().replace(Regex("[^a-z0-9]+"), "-").trim('-').take(40).ifEmpty { "game" }

	private fun projectGodot(name: String, template: String, portrait: Boolean, pixelArt: Boolean, renderer: String): String {
		val (width, height) = if (portrait) 720 to 1280 else 1280 to 720
		val (method, feature) = RENDERERS.getValue(renderer)
		return buildString {
			append("; Engine configuration file.\n")
			append("; It's best edited using the editor UI and not directly,\n")
			append("; since the parameters that go here are not all obvious.\n")
			append(";\n; Format:\n;   [section] ; section goes between []\n;   param=value ; assign values to parameters\n\n")
			append("config_version=5\n\n")
			append("[application]\n\n")
			append("config/name=\"${quoted(name)}\"\n")
			if (template != "empty") append("run/main_scene=\"res://$MAIN_SCENE\"\n")
			append("config/features=PackedStringArray(\"4.7\", \"$feature\")\n")
			append("config/icon=\"res://$ICON\"\n\n")
			append("[display]\n\n")
			append("window/size/viewport_width=$width\n")
			append("window/size/viewport_height=$height\n")
			append("window/stretch/mode=\"canvas_items\"\n")
			append("window/stretch/aspect=\"expand\"\n")
			append("window/handheld/orientation=${if (portrait) 1 else 0}\n\n")
			// The Project Manager gives every new project EditorNode::get_initial_settings(): the stretch settings above,
			// Jolt for 3D physics and Direct3D 12 on Windows. Without them a project runs Godot Physics in 3D and Vulkan on
			// Windows.
			append("[physics]\n\n")
			append("3d/physics_engine=\"Jolt Physics\"\n\n")
			append("[rendering]\n\n")
			append("renderer/rendering_method=\"$method\"\n")
			// Phones run a project with its mobile renderer setting, so a Compatibility project sets that one too.
			if (method == "gl_compatibility") append("renderer/rendering_method.mobile=\"gl_compatibility\"\n")
			append("rendering_device/driver.windows=\"d3d12\"\n")
			if (pixelArt) append("textures/canvas_textures/default_texture_filter=0\n")
		}
	}

	private fun mainScene(template: String): String? = when (template) {
		"2d" -> "[gd_scene format=3]\n\n[node name=\"Main\" type=\"Node2D\"]\n"
		"3d" -> buildString {
			append("[gd_scene format=3]\n\n")
			append("[sub_resource type=\"Environment\" id=\"Environment_main\"]\n")
			append("background_mode = 1\nbackground_color = Color(0.45, 0.62, 0.85, 1)\n")
			append("ambient_light_source = 2\nambient_light_color = Color(0.55, 0.55, 0.6, 1)\n\n")
			append("[node name=\"Main\" type=\"Node3D\"]\n\n")
			append("[node name=\"Sun\" type=\"DirectionalLight3D\" parent=\".\"]\n")
			append("rotation = Vector3(-0.8, 0.6, 0)\nshadow_enabled = true\n\n")
			append("[node name=\"WorldEnvironment\" type=\"WorldEnvironment\" parent=\".\"]\n")
			append("environment = SubResource(\"Environment_main\")\n\n")
			append("[node name=\"Camera3D\" type=\"Camera3D\" parent=\".\"]\n")
			append("position = Vector3(0, 3, 6)\nrotation = Vector3(-0.35, 0, 0)\n")
		}
		else -> null
	}

	companion object {
		const val PROJECT_FILE = "project.godot"
		private const val MAIN_SCENE = "main.tscn"
		private const val ICON = "icon.svg"
		/** The engine's default project icon, copied into the assets when GDatp is built. */
		private const val ICON_ASSET = "gdatp/project_icon.svg"
		val TEMPLATES = listOf("2d", "3d", "empty")
		/** The plan a game keeps in its project, read back so that the next game can differ from it. */
		private const val DESIGN_FILE = "DESIGN.md"
		private val DESIGN_LINE = Regex("""^\W*(pitch|core verb|the one thing|look)\W+(.+)$""", setOf(RegexOption.IGNORE_CASE, RegexOption.MULTILINE))
		private const val DESIGN_READ_CHARS = 6_000
		private const val DESIGN_LINE_CHARS = 200
		const val DEFAULT_RENDERER = "compatibility"
		const val RENDERER_3D = "mobile"
		/** How long a deleted project stays in GDatp's trash. */
		const val TRASH_DAYS = 30L
		private const val DAY_MS = 86_400_000L
		/** Between a deleted project's folder name and the time it was deleted, in the trash. */
		private const val STAMP = "@"
		/** Godot's import cache, which a project rebuilds and which is left out of its size and copies. */
		private const val CACHE = ".godot"
		/** Room a copy leaves free on the phone. */
		private const val RESERVE_BYTES = 256L * 1024 * 1024
		private const val MIB = 1024L * 1024
		/** The rendering method Godot uses for a project that names none. */
		private const val GODOT_DEFAULT_METHOD = "forward_plus"
		private val SCENE_EXTENSIONS = setOf("tscn", "scn")
		private val NAME_LINE = Regex("""^config/name=".*"$""", RegexOption.MULTILINE)
		private val RENDERING_METHOD = Regex("""^renderer/rendering_method="(.*)"$""", RegexOption.MULTILINE)

		/** The renderers a new project can use: the rendering method it sets, and the feature Godot records for it. */
		val RENDERERS = mapOf(
			"compatibility" to ("gl_compatibility" to "GL Compatibility"),
			"mobile" to ("mobile" to "Mobile"),
			"forward_plus" to ("forward_plus" to "Forward Plus"),
		)
	}
}
