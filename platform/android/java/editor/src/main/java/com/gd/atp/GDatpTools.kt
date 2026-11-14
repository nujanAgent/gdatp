package com.gd.atp

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import com.nujan_agent.atp.provider.AtpCall
import com.nujan_agent.atp.provider.AtpCaller
import com.nujan_agent.atp.provider.AtpImage
import com.nujan_agent.atp.provider.AtpResult
import com.nujan_agent.atp.provider.AtpTool
import com.nujan_agent.atp.provider.AtpToolSource
import com.nujan_agent.atp.provider.AtpUiOutcome
import com.nujan_agent.atp.wire.Atp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import org.godotengine.editor.GodotEditor
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * GDatp's tools as ATP offers them to a connected app: the definitions in `assets/gdatp/tools.json`, in MCP's own
 * `tools/list` shape. `status` and the project tools answer here, with or without the editor; every other tool is
 * carried out by the tool host in the open project through [GDatpPlugin.call], once the editor is on screen, the only
 * place its main loop runs. The provider XML names this class with `entry`.
 */
class GDatpTools(private val context: Context) : AtpToolSource {

	private val projects = GDatpProjects(context)
	private val assets = GDatpAssets()

	/** Which guide topics have been read, in storage that outlives the editor's restart. */
	private val guideLog = File(context.cacheDir, "gdatp/guide-read")

	/** What the last look at each scene of the running game measured as wrong. */
	private val lookProblems = java.util.concurrent.ConcurrentHashMap<String, List<String>>()
	@Volatile private var lastTry: Tried? = null

	/** There since guide start was last read and until a project is made from it, so each new game begins with a reading of its own. */
	private val startUnused = File(context.cacheDir, "gdatp/guide-start-unused")

	/** Written when an opening starts, in storage that outlives the editor's restart, for [status] to wait on. */
	private val openingFile = File(context.cacheDir, "gdatp/opening")

	/** The project this process is restarting into and when that began; the restart ends the process, and this with it. */
	@Volatile
	private var restartingInto: Pair<String, Long>? = null

	private val parts = GDatpParts(context)
	private val tools: List<AtpTool> = context.assets.open(DEFINITIONS).bufferedReader().use { it.readText() }.let(::parse)

	/** How the tools fit together for a model building a game, from `assets/gdatp/instructions.md`. */
	private val guide: String? = runCatching { context.assets.open(GUIDE).bufferedReader().use { it.readText() } }.getOrNull()

	override fun tools(caller: AtpCaller): List<AtpTool> = tools

	override fun instructions(): String? = guide

	override fun turnEnded(caller: AtpCaller, turn: String) = GDatpInstallOffer.turnEnded(context, caller.packageName, turn)

	private fun parse(text: String): List<AtpTool> {
		val list = JSONObject(text).getJSONArray("tools")
		return (0 until list.length()).map { i ->
			val tool = list.getJSONObject(i)
			val name = tool.getString("name")
			AtpTool(
				name = name,
				description = tool.getString("description"),
				inputSchema = tool.getJSONObject("inputSchema").toString(),
				group = tool.optJSONObject("_meta")?.optString(Atp.META_GROUP)?.takeIf { it.isNotEmpty() },
				annotations = tool.optJSONObject("annotations")?.toString(),
			) { call -> run(name, call) }
		}
	}

	private suspend fun run(name: String, call: AtpCall): AtpResult {
		restarting()?.let { project -> if (name != "projects" && name != "guide" && name != "assets" && name != "parts") return restartingAnswer(name, project) }
		val arguments = runCatching { JSONObject(call.arguments) }.getOrDefault(JSONObject())
		return when (name) {
			"status" -> status()
			"projects" -> listProjects(arguments)
			"guide" -> guideTopic(arguments)
			"projects_edit" -> editProjects(arguments, call)
			"project_create" -> create(arguments, call)
			"project_open" -> open(arguments, call)
			"screenshot" -> withPicture(withLookCheck(editorTool(name, call)))
			"run" -> withAudit(arguments, editorTool(name, call))
			"image_edit" -> withPicture(editorTool(name, call))
			"script_edit", "scene_edit", "files_edit" -> withTryOwed(editorTool(name, call))
			"assets" -> withContext(Dispatchers.IO) { assetsTool(arguments, call) }
			"parts" -> partsTool(arguments, call)
			"export" -> exportGame(arguments, call)
			else -> editorTool(name, call)
		}
	}

	/** A run's answer, with what the project still lacks of a complete game whenever it is started. */
	private suspend fun withAudit(arguments: JSONObject, result: AtpResult): AtpResult {
		if (result.isError || arguments.optString("op") !in STARTING_OPS) return result
		val answer = runCatching { JSONObject(result.text) }.getOrNull() ?: return result
		if (arguments.optString("op") == TRY_OP) rememberTry(answer)
		return audited(answer) ?: result
	}

	/** A change's answer, saying when it leaves code nobody has played: a model that stops after an edit has not seen it work. */
	private suspend fun withTryOwed(result: AtpResult): AtpResult {
		if (result.isError) return result
		val answer = runCatching { JSONObject(result.text) }.getOrNull() ?: return result
		val project = openProjectFolder() ?: return result
		if (withContext(Dispatchers.IO) { tryProblems(project) } != listOf(NOT_TRIED_YET)) return result
		return AtpResult(answer.put("unfinished", JSONArray(listOf(NOT_TRIED_YET))).toString())
	}

	private suspend fun rememberTry(answer: JSONObject) {
		val project = openProjectFolder() ?: return
		val errors = answer.optJSONArray("errors") ?: JSONArray()
		// A game that never went live has not been tried, unless it stopped at an error.
		if (!answer.has("played_s") && errors.length() == 0) return
		val broke = List(errors.length()) { errors.optJSONObject(it)?.optString("message").orEmpty() }.filter { it.isNotEmpty() }.distinct()
		lastTry = Tried(withContext(Dispatchers.IO) { GDatpAudit.codeMark(project) }, broke.take(TRY_ERRORS_LISTED))
	}

	/** What the last try says of the code as it stands, or that none has run on it. */
	private fun tryProblems(project: File): List<String> {
		val tried = lastTry
		if (tried == null || tried.code != GDatpAudit.codeMark(project)) return listOf(NOT_TRIED_YET)
		return tried.broke.map { "Playing it broke: $it" }
	}

	/** A look at the running game, with what it measured held against the game until a later look at that scene finds otherwise. */
	private suspend fun withLookCheck(result: AtpResult): AtpResult {
		if (result.isError) return result
		val answer = runCatching { JSONObject(result.text) }.getOrNull() ?: return result
		val found = answer.optJSONArray("look_check") ?: return result
		lookProblems[answer.optString("scene")] = List(found.length()) { found.getString(it) }
		answer.remove("look_check")
		answer.put("look_for", GDatpLook.question(openProjectFolder(), answer.optInt("burst", 1), answer.optInt("every_ms", 0)))
		return audited(answer) ?: result
	}

	private suspend fun openProjectFolder(): File? {
		val editor = GDatpPlugin.current ?: return null
		return openStatus(editor)?.optString("project_path")?.takeIf { it.isNotEmpty() }?.let(::File)
	}

	/** [answer] with what the open project still lacks, or null with no project open. */
	private suspend fun audited(answer: JSONObject): AtpResult? {
		val editor = GDatpPlugin.current ?: return null
		val path = openStatus(editor)?.optString("project_path").orEmpty()
		if (path.isEmpty()) return null
		val missing = withContext(Dispatchers.IO) { GDatpAudit.missing(File(path), guideTopicsRead()) } +
			lookProblems.flatMap { (scene, found) -> found.map { "$scene: $it" } } +
			listOf(NOT_LOOKED_YET).filter { lookProblems.isEmpty() } +
			withContext(Dispatchers.IO) { tryProblems(File(path)) }
		answer.put("unfinished", JSONArray(missing))
		answer.put(
			"complete_check",
			if (missing.isEmpty()) "The basics of a complete game are here. Now play it to a real end, and compare a screenshot with what you studied."
			else "Keep building: do what unfinished lists before reporting, or say in your report why this game does not need one of them. Running again changes nothing: change the game first. What a screenshot found goes when a later screenshot of that scene finds it gone.",
		)
		return AtpResult(answer.toString())
	}

	/** The guide topics read lately, kept in storage that outlives the editor's restart when a project opens. */
	private fun guideTopicsRead(): Set<String> {
		if (!guideLog.isFile || System.currentTimeMillis() - guideLog.lastModified() > GUIDE_REMEMBERED_MS) return emptySet()
		return guideLog.readLines().filter { it.isNotBlank() }.toSet()
	}

	private fun rememberGuideTopic(topic: String) {
		// Reading start begins a new game, so what was read for the last one no longer counts.
		val before = if (topic == GUIDE_START) emptySet() else guideTopicsRead()
		guideLog.parentFile?.mkdirs()
		guideLog.writeText((before + topic).joinToString("\n"))
		if (topic == GUIDE_START) startUnused.writeText("")
	}

	/** The tool host's answer with the picture it saved in GDatp's cache attached, so the caller's model can look at it. */
	private fun withPicture(result: AtpResult): AtpResult {
		if (result.isError) return result
		val answer = runCatching { JSONObject(result.text) }.getOrNull() ?: return result
		val file = File(answer.optString("path"))
		if (!file.isFile) return result
		val bytes = file.readBytes()
		file.delete()
		answer.remove("path")
		answer.put("picture", "attached")
		return AtpResult(answer.toString(), images = listOf(AtpImage("image/png", bytes)))
	}

	private suspend fun status(): AtpResult {
		// While project_open restarts the editor and the project imports, status waits for it, within LOAD_MS: answering
		// closed or importing in that gap reads as though the opening failed, and invites opening it again.
		val opening = openingFile.isFile && System.currentTimeMillis() - openingFile.lastModified() < OPENING_MS
		val until = if (opening) System.currentTimeMillis() + LOAD_MS else 0L
		if (opening) {
			waitFor(LOAD_MS) { GDatpPlugin.current?.let { it.isHostListening || it.isProjectManager } == true }
		}
		val editor = GDatpPlugin.current
		// A project opening on screen is waited for as the other tools wait for it, so one status answers once it is ready.
		if (!opening && editor != null && editor.isOnScreen && !editor.isProjectManager && !editor.isHostListening) {
			waitFor(LOAD_MS) { editor.isHostListening }
		}
		val (state, next) = when {
			editor == null -> "closed" to NEW_OR_EARLIER
			!editor.isOnScreen -> "not_on_screen" to "Any editor tool brings the editor to the front first."
			editor.isProjectManager -> "project_manager" to NEW_OR_EARLIER
			!editor.isHostListening -> "loading_project" to "The editor is still opening the project; a project imports its files " +
				"the first time it opens. Call status again."
			else -> return hostStatus(editor, until).also { openingFile.delete() }
		}
		val answer = JSONObject().put("editor", state).put("earlier_projects", projects.all().size).put("next", next)
		return AtpResult(answer.toString())
	}

	/** The host's status, given once the project has finished importing or [until] has passed. */
	private suspend fun hostStatus(editor: GDatpPlugin, until: Long): AtpResult {
		while (System.currentTimeMillis() < until && hostReadiness(editor) == "importing") delay(IMPORT_POLL_MS)
		return hostCall(editor, "status", "{}")
	}

	private fun hostReadiness(editor: GDatpPlugin): String =
		runCatching { JSONObject(editor.call("status", """{"readiness_only":true}""", STATUS_MS)).optString("readiness") }.getOrDefault("")

	private suspend fun editorTool(name: String, call: AtpCall, arguments: String = call.arguments): AtpResult {
		val editor = editorOnScreen(call)
			?: return failed("not_on_screen", "GDatp's editor could not come to the front. Ask the person to open GDatp, then try again.")
		if (!editor.isHostListening) {
			if (editor.isProjectManager) return noProject()
			if (!waitFor(LOAD_MS) { editor.isHostListening }) {
				return failed("loading_project", "The editor is still opening the project; call status in a few seconds.")
			}
		}
		return hostCall(editor, name, arguments)
	}

	/** The projects; with `project`, that project's details; with `deleted`, GDatp's trash. */
	private fun listProjects(arguments: JSONObject): AtpResult {
		val wanted = arguments.optString("project").trim()
		if (wanted.isNotEmpty()) {
			val project = projects.find(wanted) ?: return noProject("There is no project '$wanted'.")
			return AtpResult(JSONObject().put("project", projects.info(project)).toString())
		}
		if (arguments.optBoolean("deleted")) {
			val trash = JSONArray(projects.deleted())
			return AtpResult(JSONObject().put("deleted", trash).put("kept_days", GDatpProjects.TRASH_DAYS).toString())
		}
		return AtpResult(JSONObject().put("projects", projects.withDesigns(projects.all())).put("next", NEW_OR_EARLIER).toString())
	}

	/**
	 * The open project as an APK, signed with this install's own key and copied to the phone's Downloads. A person installs it from
	 * there or shares it; a store wants their own signing key, which the editor's Project > Export can use.
	 */
	private suspend fun exportGame(arguments: JSONObject, call: AtpCall): AtpResult {
		val editor = editorOnScreen(call) ?: return failed("not_on_screen", "GDatp's editor could not come to the front. Ask the person to open GDatp, then try again.")
		if (!editor.isHostListening) return noProject()
		val open = openStatus(editor) ?: return failed("not_checked", "GDatp could not tell which project is open; call status, then try again.")
		val project = File(open.optString("project_path"))
		val title = arguments.optString("name").trim().ifEmpty { open.optString("project").ifEmpty { project.name } }
		val slug = title.lowercase().replace(Regex("[^a-z0-9]+"), "-").trim('-').take(EXPORT_NAME_CHARS).ifEmpty { "game" }
		val export = GDatpExport(context)
		val prepared = withContext(Dispatchers.IO) {
			val template = export.template()
			if (template == null) null else template to export.signing()
		} ?: return failed("no_template", "This build of GDatp carries no game template, so it cannot export.")
		val output = File(context.filesDir, "gdatp/export/$slug.apk").apply { delete() }
		val version = arguments.optInt("version", 1).coerceIn(1, EXPORT_MAX_VERSION)
		val params = JSONObject()
			.put("settings", export.settings(title, slug, prepared.first, prepared.second, version))
			.put("path", output.path)
			.put("exclude", "study/*,*.md,*.import.bak")
		val answer = runCatching { JSONObject(editor.call("export_game", params.toString(), EXPORT_MS)) }.getOrNull()
			?: return failed("export_failed", "The export gave no answer.")
		if (answer.has("error")) return AtpResult(answer.toString(), isError = true)
		if (!output.isFile) return failed("export_failed", "The exporter finished, but wrote no file: ${answer.optJSONArray("messages")}")
		val uri = withContext(Dispatchers.IO) { export.toDownloads(output, "$slug.apk") }
		val result = JSONObject().put("exported", "$slug.apk").put("bytes", output.length()).put("folder", "Download/GDatp")
			.put("signing", "Signed with a key made on this phone, good for installing and sharing; a store needs the person's own key.")
			.put("messages", answer.optJSONArray("messages") ?: JSONArray())
		if (arguments.optBoolean("install") && uri != null) {
			result.put("install", GDatpInstallOffer.request(context, call.caller.packageName, call.turn, uri))
		}
		return AtpResult(result.toString())
	}

	/** `list` and `show` need no open project; `add` places what is asked for in the open one and has the editor pick it up. */
	private suspend fun partsTool(arguments: JSONObject, call: AtpCall): AtpResult {
		val params = paramsOf(arguments) ?: arguments
		val op = arguments.optString("op")
		if (op == "list") {
			val answer = JSONObject().put("parts", parts.list())
				.put("next", "parts add places the ones this game needs and says how to use each. They are systems, not a game: what you write on them is the game.")
			return AtpResult(answer.toString())
		}
		if (op != "add" && op != "show") return failed("unknown_op", "op is list, add or show; '$op' is not.")
		val names = params.optJSONArray("names")
		val wanted = List(names?.length() ?: 0) { names!!.getString(it).trim().removeSuffix(".gd") }.filter { it.isNotEmpty() }
		if (wanted.isEmpty()) return failed("missing", "parts $op needs 'names': a list of part names from parts list.")
		val unknown = parts.unknown(wanted)
		if (unknown.isNotEmpty()) return failed("unknown_part", "There is no part ${unknown.joinToString()}. parts list names them.")
		if (op == "show") return AtpResult(JSONObject().put("parts", parts.show(wanted)).toString())
		val editor = editorOnScreen(call) ?: return failed("not_on_screen", "GDatp's editor could not come to the front. Ask the person to open GDatp, then try again.")
		if (!editor.isHostListening && (editor.isProjectManager || !waitFor(LOAD_MS) { editor.isHostListening })) return noProject()
		val open = openStatus(editor) ?: return failed("not_checked", "GDatp could not tell which project is open; call status, then try again.")
		val added = withContext(Dispatchers.IO) { parts.add(wanted, File(open.optString("project_path"))) }
		runCatching { editor.call("assets_placed", JSONObject().put("first", "").toString(), ASSET_IMPORT_MS) }
		val answer = JSONObject().put("added", added)
			.put("next", "Each part's use says how to wire it in. Now write what makes this game its own: its rules, goals, enemies, levels and look. Leave parts as they are unless this game needs them changed.")
		return AtpResult(answer.toString())
	}

	/** `search` and `look` need no open project; `fetch` places what is chosen in the open one and has the editor import it. */
	private suspend fun assetsTool(arguments: JSONObject, call: AtpCall): AtpResult {
		val params = paramsOf(arguments) ?: arguments
		val source = params.optString("source").trim().lowercase()
		val id = params.optString("id").trim()
		val url = params.optString("url").trim()
		return try {
			when (val op = arguments.optString("op")) {
				"search" -> {
					val found = assets.search(source, params.optString("query").trim(), params.optString("type").trim(), params.optInt("limit", ASSETS_LISTED).coerceIn(1, ASSETS_MAX_LISTED))
					val next = if (found.isEmpty()) "Nothing matched; try fewer or plainer words." else "assets look shows a preview; assets fetch places one in the project."
					AtpResult(JSONObject().put("found", JSONArray(found.map { it.toJson() })).put("next", next).toString())
				}
				"look" -> AtpResult(JSONObject().put("picture", "attached").put("source", source.ifEmpty { url }).put("id", id).toString(), images = listOf(AtpImage(pictureType(url), assets.preview(source, id, url))))
				"fetch" -> fetchAsset(params, source, id, url, call)
				else -> failed("unknown_op", "op is search, look or fetch; '$op' is not.")
			}
		} catch (e: IllegalArgumentException) {
			failed("refused", e.message ?: "refused")
		} catch (e: org.json.JSONException) {
			failed("unexpected_answer", "The source did not answer as expected: ${e.message}. Try another asset, or a smaller resolution.")
		} catch (e: java.io.IOException) {
			failed("network", e.message ?: e.javaClass.simpleName)
		}
	}

	private fun pictureType(url: String): String {
		val path = url.substringBefore('?').lowercase()
		return when {
			path.endsWith(".jpg") || path.endsWith(".jpeg") -> "image/jpeg"
			path.endsWith(".webp") -> "image/webp"
			else -> "image/png"
		}
	}

	private suspend fun fetchAsset(params: JSONObject, source: String, id: String, url: String, call: AtpCall): AtpResult {
		val editor = editorOnScreen(call) ?: return failed("not_on_screen", "GDatp's editor could not come to the front. Ask the person to open GDatp, then try again.")
		if (!editor.isHostListening && (editor.isProjectManager || !waitFor(LOAD_MS) { editor.isHostListening })) return noProject()
		val open = openStatus(editor) ?: return failed("not_checked", "GDatp could not tell which project is open; call status, then try again.")
		val placed = assets.fetch(source, id, url, params.optString("resolution").trim(), params.optString("license").trim(), params.optString("credit").trim(), params.optString("into") == GDatpAssets.STUDY_FOLDER, open.optString("project_path"))
		val answer = JSONObject().put("folder", placed.folder).put("files", JSONArray(placed.files)).put("bytes", placed.bytes).put("license", placed.licence).put("credit", placed.credit)
			.put("credits_file", "res://${GDatpAssets.CREDITS}")
		if (params.optString("into") == GDatpAssets.STUDY_FOLDER) {
			answer.put("next", "Godot ignores this folder. files_read reads it; write your own version, then delete the folder with files_edit.")
		} else {
			val first = placed.files.firstOrNull { it.substringAfterLast('.', "").lowercase() in IMPORTED_KINDS }
			val imported = runCatching { JSONObject(editor.call("assets_placed", JSONObject().put("first", first ?: "").toString(), ASSET_IMPORT_MS)) }.getOrNull()
			answer.put("imported", imported?.optBoolean("imported") ?: false).put("next", "Use these paths in scenes; project first import of large files takes a while, so status shows when it is done.")
		}
		return AtpResult(answer.toString())
	}

	/** How to make things: with no topic the list of them, each with its first line, or one topic's text. Needs no open project. */
	private fun guideTopic(arguments: JSONObject): AtpResult {
		val wanted = arguments.optString("topic").trim().lowercase().removeSuffix(".md")
		val topics = context.assets.list(GUIDE_TOPICS).orEmpty().map { it.removeSuffix(".md") }.sorted()
		fun text(topic: String) = context.assets.open("$GUIDE_TOPICS/$topic.md").bufferedReader().use { it.readText() }
		if (wanted.isEmpty()) {
			val listing = topics.joinToString("\n") { "$it: ${text(it).lineSequence().first().removePrefix("# ")}" }
			return AtpResult("Read only the topics this game needs, with guide topic:\n$listing")
		}
		if (wanted in topics) {
			rememberGuideTopic(wanted)
			return AtpResult(text(wanted))
		}
		val near = topics.filter { topic -> wanted.split('_', ' ', '-').any { it.length > 2 && topic.contains(it) } }
		return failed("unknown_topic", "There is no topic '$wanted'. " + if (near.isEmpty()) "guide with no topic lists them." else "Near it: ${near.joinToString()}.")
	}

	/** `rename`, `duplicate`, `delete` and `restore`. The project open in the editor is not renamed or deleted under it. */
	private suspend fun editProjects(arguments: JSONObject, call: AtpCall): AtpResult {
		val op = arguments.optString("op")
		val params = paramsOf(arguments) ?: arguments
		val wanted = params.optString("project").trim()
		if (wanted.isEmpty()) return failed("missing_project", "projects_edit needs params.project, a project's name or folder.")
		val name = params.optString("name").trim()
		return try {
			when (op) {
				"restore" -> AtpResult(JSONObject().put("restored", projects.restore(wanted).toJson()).put("next", "project_open opens it.").toString())
				"rename", "duplicate", "delete" -> {
					val project = projects.find(wanted) ?: return noProject("There is no project '$wanted'.")
					if (op != "duplicate") openInEditor(project, call)?.let { return it }
					if (op != "delete" && name.isEmpty()) return failed("missing_name", "$op needs params.name.")
					val answer = when (op) {
						"rename" -> JSONObject().put("renamed", projects.rename(project, name).toJson())
						"duplicate" -> JSONObject().put("copy", projects.duplicate(project, name).toJson())
							.put("next", "project_open opens it; it imports its files the first time.")
						else -> JSONObject().put("deleted", projects.delete(project))
							.put("next", "projects_edit restore brings it back; projects with deleted: true lists the trash.")
					}
					AtpResult(answer.toString())
				}
				else -> failed("unknown_op", "op is rename, duplicate, delete or restore.")
			}
		} catch (e: IllegalArgumentException) {
			failed("refused", e.message ?: "refused")
		} catch (e: IllegalStateException) {
			failed("failed", e.message ?: "failed")
		} catch (e: java.io.IOException) {
			failed("failed", e.message ?: e.javaClass.simpleName)
		}
	}

	/**
	 * A refusal when [project] is the one open in the editor, or when GDatp cannot tell, since a change under the open
	 * project is undone or lost when the editor saves. Null when it is safe to go on.
	 */
	private suspend fun openInEditor(project: GDatpProjects.Project, call: AtpCall): AtpResult? {
		if (GDatpPlugin.current.let { it == null || it.isProjectManager }) return null
		val editor = editorOnScreen(call)
		val open = if (editor != null && waitFor(LOAD_MS) { editor.isHostListening }) openStatus(editor) else null
		return when {
			open == null -> failed("not_checked", "GDatp could not tell which project the editor has open; call status, then try again.")
			sameProject(open, project) -> failed("project_open", "'${project.name}' is open in the editor. Open another project with project_open first.")
			else -> null
		}
	}

	private suspend fun create(arguments: JSONObject, call: AtpCall): AtpResult {
		val name = arguments.optString("name").trim()
		if (name.isEmpty()) return failed("missing", "project_create needs 'name'.")
		val template = arguments.optString("template", "2d").ifBlank { "2d" }
		if (template !in GDatpProjects.TEMPLATES) return failed("bad_template", "template is one of ${GDatpProjects.TEMPLATES.joinToString()}.")
		if (template != "empty" && !startUnused.isFile) {
			return failed("read_guide_first", "Read guide with topic start before making a project: it says what to decide and write first. Template empty makes a bare project for other work.")
		}
		val renderer = arguments.optString("renderer").ifBlank { if (template == "3d") GDatpProjects.RENDERER_3D else GDatpProjects.DEFAULT_RENDERER }
		if (renderer !in GDatpProjects.RENDERERS) return failed("bad_renderer", "renderer is one of ${GDatpProjects.RENDERERS.keys.joinToString()}.")
		val project = projects.create(
			name = name,
			template = template,
			portrait = arguments.optString("orientation") == "portrait",
			pixelArt = arguments.optBoolean("pixel_art", false),
			renderer = renderer,
		)
		startUnused.delete()
		lookProblems.clear()
		lastTry = null
		val answer = JSONObject().put("created", project.toJson()).put("renderer", renderer)
		if (template != "empty") answer.put("parts_here", withContext(Dispatchers.IO) { parts.addEveryGameParts(File(project.path)) })
		answer.put("files", JSONArray(File(project.path).list().orEmpty().sorted()))
			.put("next", "There is no game in it, and that is yours to build. parts_here is already in res://parts, tested on phones: use these for controls, menus, sound and feel instead of writing your own, and each one's use says how. Write res://DESIGN.md, then build the core verb first. parts list shows more, such as heroes, levels from text and a voxel world. The window starts at ${if (arguments.optString("orientation") == "portrait") "720x1280" else "1280x720"} and grows to fit a phone of any shape, so lay everything out from get_viewport_rect().size, never from a number of your own.")
		if (arguments.optBoolean("open", true)) {
			opening(project, call, answer)
		} else {
			answer.put("next", "project_open opens it; until then the editor's other tools work on the project that is open.")
		}
		return AtpResult(answer.toString(), isError = answer.has("error"))
	}

	private suspend fun open(arguments: JSONObject, call: AtpCall): AtpResult {
		val wanted = arguments.optString("name").ifBlank { arguments.optString("path") }.trim()
		if (wanted.isEmpty()) return noProject("project_open needs 'name' or 'path'.")
		val project = projects.find(wanted) ?: return noProject("There is no project '$wanted'.")
		// A model told a new game means a new project still opens an earlier one with the same name, and a flag in the schema it simply
		// sets. The code exists only in this refusal, so going on means having read it.
		val code = openCode(project)
		if (arguments.optString("confirm") != code && !isOpenNow(project)) {
			return failed(
				"earlier_game",
				"'${project.name}' is a game made earlier, and opening it lets this work change it. If the person asked to make or create a game, even with this very name, it is a new game: use project_create with that name, which makes a new project and leaves this one alone. Only if the person asked to change, fix or continue this existing game, call project_open again with confirm: \"$code\".",
			)
		}
		projects.remember(project)
		// What was read and seen for another game does not count for this one.
		guideLog.delete()
		lookProblems.clear()
		lastTry = null
		val answer = JSONObject().put("project", project.toJson())
		opening(project, call, answer)
		return AtpResult(answer.toString(), isError = answer.has("error"))
	}

	/**
	 * Opens [project] in the editor. With no editor running it starts straight into the project. With the editor running
	 * it is brought on screen, this answer is sent, and then it restarts into the project, as Godot does to switch projects.
	 */
	private suspend fun opening(project: GDatpProjects.Project, call: AtpCall, answer: JSONObject) {
		val view = Intent(Intent.ACTION_VIEW, Uri.fromFile(File(project.path, GDatpProjects.PROJECT_FILE)), context, GodotEditor::class.java)
		if (GDatpPlugin.current == null) {
			markOpening()
			if (call.ui.show(view, REASON_OPEN) == AtpUiOutcome.SHOWN) {
				answer.put("opening", true).put("next", "The editor is starting into it. $STATUS_WAITS A new project imports first.")
			} else {
				answer.put("error", "not_shown").put("message", "GDatp could not come to the front. Ask the person to open GDatp, then call project_open again.")
			}
			return
		}
		val editor = editorOnScreen(call)
		if (editor == null) {
			answer.put("error", "not_shown").put("message", "GDatp could not come to the front. Ask the person to open GDatp, then call project_open again.")
			return
		}
		if (editor.isHostListening) {
			// The switch restarts the editor, which loses what nobody saved, so it waits for the person to save it.
			val open = openStatus(editor)
			if (open == null) {
				answer.put("error", "not_checked").put("message", "GDatp could not check the open project for unsaved work; call project_open again in a moment.")
				return
			}
			if (sameProject(open, project)) {
				answer.put("already_open", true).put("next", "status shows what is open.")
				return
			}
			val unsaved = unsavedWork(open)
			if (unsaved.isNotEmpty()) {
				answer.put("error", "unsaved_work").put("unsaved", JSONArray(unsaved))
					.put("message", "The open project has changes nobody saved: ${unsaved.joinToString()}. Switching would lose them. " +
						"Ask the person to save or discard them in the editor, then call project_open again.")
				return
			}
		}
		markOpening()
		restartingInto = project.name to System.currentTimeMillis()
		Handler(Looper.getMainLooper()).postDelayed({
			runCatching { context.startActivity(Intent(view).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }.onFailure { restartingInto = null }
		}, SWITCH_AFTER_MS)
		answer.put("opening", true).put("next", "The editor restarts into it, which takes a few seconds. $STATUS_WAITS")
	}

	private fun markOpening() {
		runCatching { openingFile.parentFile?.mkdirs(); openingFile.writeText(System.currentTimeMillis().toString()) }
	}

	/** The project this process is restarting into, while that restart is still to come. */
	private fun restarting(): String? = restartingInto?.takeIf { System.currentTimeMillis() - it.second < OPENING_MS }?.first

	/**
	 * The answer to a call that arrives between project_open's answer and the restart that ends this process: carried out,
	 * it would act on the project being closed, or be cut off by the restart with its outcome unknown.
	 */
	private fun restartingAnswer(name: String, project: String): AtpResult = if (name == "status") {
		AtpResult(
			JSONObject().put("editor", "restarting").put("project", project)
				.put("next", "The editor is restarting into $project; call status again, which waits for it to open and import.").toString(),
		)
	} else {
		failed("restarting", "The editor is restarting into $project, so $name did not run. Call status, which waits for the project " +
			"to open and import, then call $name again.")
	}

	/** The editor on screen, brought there through the call when it is not; null when it could not be. */
	private suspend fun editorOnScreen(call: AtpCall): GDatpPlugin? {
		GDatpPlugin.current?.takeIf { it.isOnScreen }?.let { return it }
		if (call.ui.show(Intent(context, GodotEditor::class.java), REASON_SHOW) != AtpUiOutcome.SHOWN) return null
		waitFor(SHOW_MS) { GDatpPlugin.current?.isOnScreen == true }
		return GDatpPlugin.current?.takeIf { it.isOnScreen }
	}

	/** The tool host's status of the open project, or null when it does not answer. */
	private fun openStatus(editor: GDatpPlugin): JSONObject? =
		runCatching { JSONObject(editor.call("status", "{}", STATUS_MS)) }.getOrNull()?.takeUnless { it.has("error") }

	private fun openCode(project: GDatpProjects.Project): String = "%06x".format(project.path.hashCode() and 0xFFFFFF)

	private fun isOpenNow(project: GDatpProjects.Project): Boolean {
		val editor = GDatpPlugin.current?.takeIf { it.isHostListening } ?: return false
		return openStatus(editor)?.let { sameProject(it, project) } == true
	}

	private fun sameProject(open: JSONObject, project: GDatpProjects.Project): Boolean {
		val path = open.optString("project_path").trimEnd('/')
		return path.isNotEmpty() && File(path).canonicalPath == File(project.path).canonicalPath
	}

	/** The open project's scenes and scripts with changes nobody saved, which a switch would lose. */
	private fun unsavedWork(open: JSONObject): List<String> =
		listOf("unsaved_scenes", "unsaved_scripts").flatMap { key ->
			open.optJSONArray(key)?.let { list -> (0 until list.length()).map(list::optString) }.orEmpty()
		}.filter { it.isNotBlank() }

	private fun hostCall(editor: GDatpPlugin, name: String, arguments: String): AtpResult {
		val answer = editor.call(name, arguments, waitMs(name, arguments))
		val failed = runCatching { JSONObject(answer).has("error") }.getOrDefault(true)
		return AtpResult(answer, isError = failed)
	}

	/**
	 * How long to wait for the tool host's answer to [name]. exec's code may run for the `seconds` its call gives it,
	 * which the host holds to 1 to [EXEC_SECONDS_MAX], so exec waits that long and [EXEC_MARGIN_MS] more, and never less
	 * than its own entry in [TIMEOUT_MS], which covers code run in the game.
	 */
	private fun waitMs(name: String, arguments: String): Long {
		val fixed = TIMEOUT_MS[name] ?: DEFAULT_TIMEOUT_MS
		if (name != "exec") return fixed
		val call = runCatching { JSONObject(arguments) }.getOrNull() ?: return fixed
		val seconds = (paramsOf(call)?.opt("seconds") ?: call.opt("seconds"))?.toString()?.toDoubleOrNull() ?: return fixed
		return maxOf(fixed, (seconds.coerceIn(1.0, EXEC_SECONDS_MAX) * 1000).toLong() + EXEC_MARGIN_MS)
	}

	/** The call's `params`, sent as an object or as a JSON string, as the tool host reads them; null when it has none. */
	private fun paramsOf(arguments: JSONObject): JSONObject? = arguments.optJSONObject("params")
		?: arguments.optString("params").takeIf { it.startsWith("{") }?.let { runCatching { JSONObject(it) }.getOrNull() }

	private fun noProject(message: String = "No project is open in the editor."): AtpResult {
		val answer = JSONObject()
			.put("error", "no_project")
			.put("message", message)
			.put("earlier_projects", projects.all().size)
			.put("next", "project_open opens one of these by name; project_create makes a new one.")
		return AtpResult(answer.toString(), isError = true)
	}

	private fun failed(code: String, message: String): AtpResult =
		AtpResult(JSONObject().put("error", code).put("message", message).toString(), isError = true)

	private suspend fun waitFor(ms: Long, condition: () -> Boolean): Boolean {
		val until = System.currentTimeMillis() + ms
		while (System.currentTimeMillis() < until) {
			if (condition()) return true
			delay(POLL_MS)
		}
		return condition()
	}

	private companion object {
		const val DEFINITIONS = "gdatp/tools.json"
		const val GUIDE = "gdatp/instructions.md"
		const val GUIDE_TOPICS = "gdatp/guide"
		const val EXPORT_MS = 5L * 60 * 1000
		const val EXPORT_NAME_CHARS = 40
		const val EXPORT_MAX_VERSION = 1_000_000
		const val GUIDE_REMEMBERED_MS = 12L * 60 * 60 * 1000
		const val GUIDE_START = "start"
		const val NOT_LOOKED_YET = "Nobody has looked at this game running: screenshot target game shows it, and a look at it says what is wrong."
		const val NEW_OR_EARLIER = "A request to make a game is a new game: project_create, even when an earlier one has a similar name. project_open is for changing an earlier game when asked to."
		const val TRY_OP = "try"
		const val TRY_ERRORS_LISTED = 4
		const val NOT_TRIED_YET = "Nobody has played this code past its first screen: run try does, and lists what broke."
		val STARTING_OPS = setOf("play", "restart", TRY_OP)
		const val ASSETS_LISTED = 12
		const val ASSETS_MAX_LISTED = 40
		const val ASSET_IMPORT_MS = 25_000L
		val IMPORTED_KINDS = setOf("png", "jpg", "jpeg", "webp", "svg", "glb", "gltf", "ogg", "mp3", "wav", "ttf", "otf", "hdr")
		const val DEFAULT_TIMEOUT_MS = 30_000L
		const val STATUS_MS = 5_000L
		const val SHOW_MS = 8_000L
		const val LOAD_MS = 30_000L
		/** How long an opening counts as under way: status waits for the editor, and the old process answers restarting. */
		const val OPENING_MS = 60_000L
		const val SWITCH_AFTER_MS = 600L
		const val POLL_MS = 200L
		const val IMPORT_POLL_MS = 500L
		const val LISTED = 30
		const val REASON_SHOW = "GDatp's editor carries out its tools only while it is on screen."
		const val REASON_OPEN = "GDatp opens the project in its editor."
		/** What follows an opening: status waits for the project itself, so polling it only repeats the same answer. */
		const val STATUS_WAITS = "status waits up to ${LOAD_MS / 1000} s for the project to open and import; call it again only if it " +
			"still says loading_project or importing."

		/** The longest time limit exec gives code in the editor, as host.gd's EXEC_SECONDS_MAX holds `seconds`. */
		const val EXEC_SECONDS_MAX = 240.0
		/** What exec's wait adds to its code's time limit, for compiling the code and answering, as 40 s does for 30. */
		const val EXEC_MARGIN_MS = 10_000L

		/**
		 * The tools that wait on a running game get longer than the tool host's own limits for them; run steps a paused
		 * game up to 600 frames, one round trip each. exec's is its least: [waitMs] follows its code's time limit.
		 */
		val TIMEOUT_MS = mapOf(
			"run" to 120_000L, "input" to 75_000L, "exec" to 40_000L, "game_read" to 45_000L, "game_edit" to 20_000L,
			// A game screenshot may start the game first, and a burst spans up to twelve seconds of play.
			"screenshot" to 60_000L,
		)
	}
}

/** What a run try found, and the code it found it in. */
private class Tried(val code: Long, val broke: List<String>)
