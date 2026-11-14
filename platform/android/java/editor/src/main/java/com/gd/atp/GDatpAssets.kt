package com.gd.atp

import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.util.zip.ZipInputStream

/**
 * Art, models, materials, fonts, sound and code from outside: searching sources with public interfaces, looking at a preview, and
 * placing what is chosen in a project with a line in its credits. Network and file work only; the editor imports afterwards.
 */
class GDatpAssets {

	/** One thing a source offers. */
	data class Found(val id: String, val name: String, val licence: String, val kind: String, val note: String) {
		fun toJson(): JSONObject = JSONObject().put("id", id).put("name", name).put("license", licence).put("type", kind).put("note", note)
	}

	/** What fetching placed in a project. */
	data class Placed(val folder: String, val files: List<String>, val bytes: Long, val licence: String, val credit: String)

	fun search(source: String, query: String, type: String, limit: Int): List<Found> = when (source) {
		POLY_HAVEN -> polyHavenSearch(query, type, limit)
		AMBIENT_CG -> ambientCgSearch(query, type, limit)
		GODOT -> godotSearch(query, type, limit)
		else -> throw IllegalArgumentException("source for search is $POLY_HAVEN, $AMBIENT_CG or $GODOT. To find anything else, search the web, then fetch with url.")
	}

	/** A preview picture's bytes, for the model to judge before fetching; at most [PREVIEW_MAX_BYTES]. */
	fun preview(source: String, id: String, url: String): ByteArray {
		val address = when {
			url.isNotEmpty() -> checkedAddress(url)
			source == POLY_HAVEN -> "https://cdn.polyhaven.com/asset_img/thumbs/${pathPart(id)}.png?width=768&height=768"
			source == AMBIENT_CG -> ambientCgPreview(id)
			source == GODOT -> JSONObject(text("$GODOT_API/asset/${pathPart(id)}")).getString("icon_url")
			else -> throw IllegalArgumentException("source is $POLY_HAVEN, $AMBIENT_CG, $GODOT, or give url.")
		}
		return bytes(address, PREVIEW_MAX_BYTES)
	}

	/** Downloads [id] from [source] into the project at [projectPath]; [study] places a project to read in a folder Godot ignores. */
	fun fetch(source: String, id: String, url: String, resolution: String, licence: String, credit: String, study: Boolean, projectPath: String): Placed {
		val project = File(projectPath)
		require(project.isDirectory) { "The open project's folder could not be found." }
		val placed = when {
			source == URL_SOURCE || url.isNotEmpty() -> fetchUrl(url, licence, credit, study, project)
			source == POLY_HAVEN -> fetchPolyHaven(id, resolution, project)
			source == AMBIENT_CG -> fetchAmbientCg(id, resolution, project)
			source == GODOT -> fetchGodot(id, study, project)
			else -> throw IllegalArgumentException("source is $POLY_HAVEN, $AMBIENT_CG, $GODOT or $URL_SOURCE.")
		}
		if (study) File(project, "$STUDY_FOLDER/.gdignore").apply { parentFile?.mkdirs() }.writeText("")
		if (!study) appendCredit(project, placed)
		return placed
	}

	private fun polyHavenSearch(query: String, type: String, limit: Int): List<Found> {
		val kind = type.ifEmpty { "models" }
		require(kind in setOf("hdris", "textures", "models")) { "type for $POLY_HAVEN is hdris, textures or models." }
		val all = JSONObject(text("$POLY_HAVEN_API/assets?t=$kind"))
		val words = query.lowercase().split(' ').filter { it.isNotBlank() }
		val hits = mutableListOf<Pair<Int, Found>>()
		all.keys().forEach { id ->
			val asset = all.getJSONObject(id)
			val heard = (asset.optString("name") + " " + id + " " + joined(asset.optJSONArray("tags")) + " " + joined(asset.optJSONArray("categories"))).lowercase()
			val score = words.count { it in heard }
			if (words.isEmpty() || score > 0) {
				val polycount = asset.optInt("polycount", 0)
				hits += score to Found(id, asset.optString("name"), "CC0", kind, if (polycount > 0) "$polycount triangles; check it fits a phone" else "from Poly Haven")
			}
		}
		return hits.sortedByDescending { it.first }.take(limit).map { it.second }
	}

	private fun ambientCgSearch(query: String, type: String, limit: Int): List<Found> {
		val kind = type.ifEmpty { "material" }
		val answer = JSONObject(text("$AMBIENT_CG_API/assets?type=${encoded(kind)}&q=${encoded(query)}&limit=$limit&include=title,tags"))
		val list = answer.getJSONArray("assets")
		return (0 until list.length()).map { i ->
			val asset = list.getJSONObject(i)
			Found(asset.getString("id"), asset.optString("title"), "CC0", kind, "from ambientCG; " + joined(asset.optJSONArray("tags")).take(TAGS_CHARS))
		}
	}

	private fun ambientCgPreview(id: String): String {
		val answer = JSONObject(text("$AMBIENT_CG_API/assets?id=${encoded(id)}&include=thumbnails"))
		val asset = answer.getJSONArray("assets").optJSONObject(0) ?: throw IllegalArgumentException("$AMBIENT_CG has no asset '$id'.")
		val thumbnails = asset.optJSONArray("thumbnails") ?: throw IOException("$AMBIENT_CG gives no preview for '$id'.")
		return thumbnails.optJSONObject(thumbnails.length() - 1)?.optString("url")?.takeIf { it.isNotEmpty() } ?: throw IOException("$AMBIENT_CG gives no preview for '$id'.")
	}

	private fun godotSearch(query: String, type: String, limit: Int): List<Found> {
		val kind = type.ifEmpty { "any" }
		require(kind in setOf("addon", "project", "any")) { "type for $GODOT is addon, project or any." }
		val answer = JSONObject(text("$GODOT_API/asset?filter=${encoded(query)}&type=$kind&godot_version=4.4&max_results=$limit"))
		val list = answer.getJSONArray("result")
		return (0 until list.length()).map { i ->
			val asset = list.getJSONObject(i)
			Found(asset.getString("asset_id"), asset.optString("title"), asset.optString("cost"), asset.optString("category"), "Godot ${asset.optString("godot_version")}, by ${asset.optString("author")}")
		}
	}

	private fun fetchPolyHaven(id: String, resolution: String, project: File): Placed {
		val safe = pathPart(id)
		val info = JSONObject(text("$POLY_HAVEN_API/info/$safe"))
		val files = JSONObject(text("$POLY_HAVEN_API/files/$safe"))
		val res = resolution.ifEmpty { "1k" }
		val folder = "assets/polyhaven/$safe"
		val wanted = linkedMapOf<String, String>()
		when (info.getInt("type")) {
			HAVEN_HDRI -> {
				val file = files.getJSONObject("hdri").getJSONObject(res).getJSONObject("hdr")
				wanted["$safe.hdr"] = file.getString("url")
			}
			HAVEN_TEXTURE -> HAVEN_MAPS.forEach { map ->
				val file = files.optJSONObject(map)?.optJSONObject(res)?.optJSONObject("jpg") ?: return@forEach
				wanted["${safe}_$map.jpg"] = file.getString("url")
			}
			else -> {
				val entry = files.getJSONObject("gltf").getJSONObject(res).getJSONObject("gltf")
				wanted["$safe.gltf"] = entry.getString("url")
				val include = entry.optJSONObject("include")
				include?.keys()?.forEach { path -> wanted[path] = include.getJSONObject(path).getString("url") }
			}
		}
		require(wanted.isNotEmpty()) { "$POLY_HAVEN offers no $res files for '$id'." }
		val out = File(project, folder)
		val paths = wanted.map { (relative, url) -> download(url, inside(out, relative)) ; "res://$folder/$relative" }
		return Placed("res://$folder", paths, sizeOf(out), "CC0", "${info.optString("name")} from Poly Haven (polyhaven.com), CC0")
	}

	private fun fetchAmbientCg(id: String, resolution: String, project: File): Placed {
		val answer = JSONObject(text("$AMBIENT_CG_API/assets?id=${encoded(id)}&include=title,downloads"))
		val asset = answer.getJSONArray("assets").optJSONObject(0) ?: throw IllegalArgumentException("$AMBIENT_CG has no asset '$id'.")
		val attributes = (resolution.ifEmpty { "1k" }).uppercase() + "-JPG"
		val downloads = asset.getJSONArray("downloads")
		val pick = (0 until downloads.length()).map { downloads.getJSONObject(it) }.let { all ->
			all.firstOrNull { it.optString("attributes") == attributes } ?: all.firstOrNull { it.optString("attributes").contains("1K") } ?: all.firstOrNull()
		} ?: throw IOException("$AMBIENT_CG lists no download for '$id'.")
		val folder = "assets/ambientcg/${pathPart(id)}"
		val out = File(project, folder)
		val files = unzip(pick.getString("url"), out, stripTop = false) { name -> AMBIENT_SKIPPED.none { name.endsWith(it, ignoreCase = true) } }
		return Placed("res://$folder", files.map { "res://$folder/$it" }, sizeOf(out), "CC0", "${asset.optString("title", id)} from ambientCG (ambientcg.com), CC0")
	}

	private fun fetchGodot(id: String, study: Boolean, project: File): Placed {
		val asset = JSONObject(text("$GODOT_API/asset/${pathPart(id)}"))
		val title = asset.optString("title", id)
		val licence = asset.optString("cost", "unknown")
		val credit = "$title by ${asset.optString("author")}, ${asset.optString("browse_url")}, $licence"
		val isProject = asset.optString("type") == "project"
		if (isProject && !study) throw IllegalArgumentException("'$title' is a whole project: fetch it with into: study to read it. A game here is written for itself rather than started from another.")
		if (study) {
			val folder = "$STUDY_FOLDER/${slug(title)}"
			val out = File(project, folder)
			val files = unzip(asset.getString("download_url"), out, stripTop = true) { true }
			return Placed("res://$folder", files.take(LISTED_FILES).map { "res://$folder/$it" }, sizeOf(out), licence, credit)
		}
		val files = unzip(asset.getString("download_url"), project, stripTop = true) { it.startsWith("addons/") }
		require(files.isNotEmpty()) { "'$title' holds no addons folder. fetch with into: study reads it." }
		return Placed("res://addons", files.take(LISTED_FILES).map { "res://$it" }, files.sumOf { File(project, it).length() }, licence, credit)
	}

	private fun fetchUrl(url: String, licence: String, credit: String, study: Boolean, project: File): Placed {
		require(url.isNotEmpty()) { "fetch with source url needs url: a direct https address to a file." }
		require(study || licence.isNotBlank()) { "fetch with url needs license: what the file's page says, such as CC0 or CC BY 4.0. Read it there first. A picture only to learn from goes in with into: study instead." }
		require(study || licence.uppercase().let { "NC" !in it.split('-', ' ', '/') }) { "A non-commercial licence is not used unless the person asks for it knowing what it means." }
		val address = checkedAddress(url)
		val name = URL(address).path.substringAfterLast('/').substringBefore('?').ifEmpty { "file" }
		val extension = name.substringAfterLast('.', "").lowercase()
		require(extension in URL_EXTENSIONS) { "A fetched file is one of: ${URL_EXTENSIONS.joinToString()}; '$name' is not." }
		val folder = (if (study) STUDY_FOLDER else "assets/fetched") + "/" + slug(name.substringBeforeLast('.'))
		val out = File(project, folder)
		val files = if (extension == "zip") {
			unzip(address, out, stripTop = false) { entry -> entry.substringAfterLast('.', "").lowercase() in URL_ZIP_KEPT }
		} else {
			download(address, inside(out, name))
			listOf(name)
		}
		return Placed("res://$folder", files.take(LISTED_FILES).map { "res://$folder/$it" }, sizeOf(out), if (study) STUDY_ONLY else licence, credit.ifBlank { address })
	}

	private fun appendCredit(project: File, placed: Placed) {
		val file = File(project, CREDITS)
		file.parentFile?.mkdirs()
		if (!file.isFile) file.writeText("# Credits\n\nWhat this game uses from elsewhere, and its licence.\n\n")
		if (placed.credit !in file.readText()) file.appendText("- ${placed.credit} (${placed.folder})\n")
	}

	private fun connect(address: String): HttpURLConnection {
		var current = address
		repeat(MAX_REDIRECTS) {
			val connection = URL(current).openConnection() as HttpURLConnection
			connection.instanceFollowRedirects = false
			connection.connectTimeout = CONNECT_MS
			connection.readTimeout = READ_MS
			connection.setRequestProperty("User-Agent", USER_AGENT)
			val code = connection.responseCode
			if (code in 300..399) {
				val next = connection.getHeaderField("Location") ?: throw IOException("$current redirected to nowhere.")
				connection.disconnect()
				current = checkedAddress(URL(URL(current), next).toString())
				return@repeat
			}
			if (code !in 200..299) {
				connection.disconnect()
				throw IOException("$current answered HTTP $code.")
			}
			return connection
		}
		throw IOException("$address redirected too many times.")
	}

	private fun text(address: String): String {
		val connection = connect(address)
		return try {
			connection.inputStream.bufferedReader().use { it.readText() }
		} finally {
			connection.disconnect()
		}
	}

	private fun bytes(address: String, limit: Long): ByteArray {
		val connection = connect(address)
		return try {
			require(connection.contentLengthLong <= limit) { "That file is over the ${limit / MIB} MB a preview may be." }
			connection.inputStream.use { input ->
				val out = java.io.ByteArrayOutputStream()
				val buffer = ByteArray(BUFFER)
				while (true) {
					val read = input.read(buffer)
					if (read < 0) break
					out.write(buffer, 0, read)
					require(out.size() <= limit) { "That file is over the ${limit / MIB} MB a preview may be." }
				}
				out.toByteArray()
			}
		} finally {
			connection.disconnect()
		}
	}

	private fun download(address: String, to: File) {
		val connection = connect(address)
		try {
			require(connection.contentLengthLong <= MAX_BYTES) { "That file is over the ${MAX_BYTES / MIB} MB limit; choose a smaller one." }
			to.parentFile?.mkdirs()
			connection.inputStream.use { input -> to.outputStream().use { out -> copyLimited(input, out) } }
		} catch (e: IOException) {
			to.delete()
			throw e
		} finally {
			connection.disconnect()
		}
	}

	private fun unzip(address: String, out: File, stripTop: Boolean, keep: (String) -> Boolean): List<String> {
		val connection = connect(address)
		val files = mutableListOf<String>()
		try {
			require(connection.contentLengthLong <= MAX_BYTES) { "That archive is over the ${MAX_BYTES / MIB} MB limit; choose a smaller one." }
			ZipInputStream(connection.inputStream.buffered()).use { zip ->
				while (true) {
					val entry = zip.nextEntry ?: break
					val name = if (stripTop) entry.name.substringAfter('/', "") else entry.name
					if (name.isEmpty() || entry.isDirectory || name.startsWith("__MACOSX/") || !keep(name)) continue
					val file = inside(out, name)
					file.parentFile?.mkdirs()
					file.outputStream().use { copyLimited(zip, it) }
					files += name
					require(files.size <= MAX_FILES) { "That archive holds more than $MAX_FILES files, which is too many for a phone." }
				}
			}
		} finally {
			connection.disconnect()
		}
		if (files.isEmpty()) throw IOException("The archive held nothing to place.")
		return files
	}

	private fun copyLimited(input: java.io.InputStream, out: java.io.OutputStream) {
		val buffer = ByteArray(BUFFER)
		var total = 0L
		while (true) {
			val read = input.read(buffer)
			if (read < 0) return
			out.write(buffer, 0, read)
			total += read
			require(total <= MAX_BYTES) { "That file is over the ${MAX_BYTES / MIB} MB limit; choose a smaller one." }
		}
	}

	/** [relative] under [folder], refusing a name that climbs out of it, as a hostile archive's might. */
	private fun inside(folder: File, relative: String): File {
		val file = File(folder, relative).canonicalFile
		require(file.path.startsWith(folder.canonicalPath + File.separator)) { "'$relative' points outside the project." }
		return file
	}

	private fun checkedAddress(address: String): String {
		val parsed = runCatching { URL(address) }.getOrNull() ?: throw IllegalArgumentException("'$address' is not an address.")
		require(parsed.protocol == "https") { "Only https addresses are fetched." }
		val host = parsed.host.lowercase()
		require(host.contains('.') && !host.endsWith(".local") && !host.endsWith(".internal") && host != "localhost" && !host.matches(NUMERIC_HOST)) { "Only public hosts are fetched from." }
		return parsed.toString()
	}

	private fun pathPart(id: String): String {
		require(id.isNotBlank() && id.all { it.isLetterOrDigit() || it in "_-." } && ".." !in id) { "'$id' is not an id from search." }
		return id
	}

	private fun encoded(value: String): String = java.net.URLEncoder.encode(value, "UTF-8")

	private fun joined(array: JSONArray?): String = array?.let { list -> (0 until list.length()).joinToString(" ") { list.optString(it) } }.orEmpty()

	private fun sizeOf(folder: File): Long = folder.walkTopDown().filter { it.isFile }.sumOf { it.length() }

	private fun slug(name: String): String = name.lowercase().replace(Regex("[^a-z0-9]+"), "-").trim('-').take(40).ifEmpty { "asset" }

	companion object {
		const val POLY_HAVEN = "polyhaven"
		const val AMBIENT_CG = "ambientcg"
		const val GODOT = "godot"
		const val URL_SOURCE = "url"
		const val STUDY_FOLDER = "study"
		private const val STUDY_ONLY = "kept to learn from, never in the game"
		const val CREDITS = "assets/CREDITS.md"
		private const val POLY_HAVEN_API = "https://api.polyhaven.com"
		private const val AMBIENT_CG_API = "https://ambientcg.com/api/v3"
		private const val GODOT_API = "https://godotengine.org/asset-library/api"
		/** Poly Haven asks that calls name the software making them. */
		private const val USER_AGENT = "GDatp"
		private const val HAVEN_HDRI = 0
		private const val HAVEN_TEXTURE = 1
		private val HAVEN_MAPS = listOf("Diffuse", "nor_gl", "Rough", "AO", "Displacement")
		private val AMBIENT_SKIPPED = listOf(".usda", ".usdc", ".mtlx", ".tres", ".blend")
		private val URL_EXTENSIONS = setOf("png", "jpg", "jpeg", "webp", "svg", "glb", "gltf", "bin", "ogg", "mp3", "wav", "ttf", "otf", "zip")
		private val URL_ZIP_KEPT = URL_EXTENSIONS - "zip" + setOf("txt", "md", "bmp", "tga", "obj", "mtl", "fbx")
		private val NUMERIC_HOST = Regex("""^[0-9.]+$|^\[.*]$""")
		private const val PREVIEW_MAX_BYTES = 8L * 1024 * 1024
		private const val MAX_BYTES = 200L * 1024 * 1024
		private const val MAX_FILES = 3000
		private const val MAX_REDIRECTS = 6
		private const val MIB = 1024L * 1024
		private const val BUFFER = 64 * 1024
		private const val CONNECT_MS = 15_000
		private const val READ_MS = 45_000
		private const val TAGS_CHARS = 80
		private const val LISTED_FILES = 40
	}
}
