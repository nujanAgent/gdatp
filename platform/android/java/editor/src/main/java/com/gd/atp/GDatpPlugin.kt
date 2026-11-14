package com.gd.atp

import android.util.Log
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot
import org.json.JSONObject
import java.util.concurrent.CompletableFuture
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException
import java.util.concurrent.atomic.AtomicLong

/**
 * The editor's side of GDatp's tools. The editor runs GDatp's tool host, GDScript this plugin supplies from the APK
 * ([hostSource]), in every project it opens. A call made on any thread reaches the host as the `call_arrived`
 * signal, which Godot delivers on the engine's main thread, and the host answers through [reply].
 */
class GDatpPlugin(godot: Godot) : GodotPlugin(godot) {

	companion object {
		private const val TAG = "GDatp"
		const val NAME = "GDatp"
		private const val HOST_DIR = "gdatp"
		private const val HOST_ASSET = "$HOST_DIR/host.gd"
		private const val GAME_HELPER_ASSET = "gdatp/game_helper.gd"
		/** Parts that both the tool host and the game helper include. */
		private const val SHARED_PREFIX = "shared_"

		/** The plugin of the editor running in this process, or null while none runs. */
		@Volatile
		var current: GDatpPlugin? = null
			private set
	}

	private val callArrived = SignalInfo("call_arrived", String::class.java, String::class.java, String::class.java)
	private val waiting = ConcurrentHashMap<String, CompletableFuture<String>>()
	private val ids = AtomicLong()

	@Volatile
	private var onScreen = false

	@Volatile
	private var hostListening = false

	init {
		current = this
	}

	/** Whether the editor is on screen, the only time its main loop runs and it can carry out tools. */
	val isOnScreen: Boolean get() = onScreen

	/** Whether a project's tool host listens for calls: false in the Project Manager and while a project loads. */
	val isHostListening: Boolean get() = hostListening

	/** Whether this editor shows the Project Manager rather than a project. */
	val isProjectManager: Boolean get() = runCatching { godot.isProjectManagerHint() }.getOrDefault(false)

	override fun getPluginName() = NAME

	override fun getPluginSignals() = setOf(callArrived)

	override fun onMainStart() {
		onScreen = true
		GDatpInstallOffer.offer(context)
	}

	override fun onMainStop() {
		onScreen = false
		// Its main loop stops with it, so a call under way would wait out its whole time limit for an answer that cannot come.
		answerAll("left_the_screen", "the editor left the screen during this call, so it may not have finished. status shows where things stand; the next editor tool brings it back to the front")
	}

	override fun onMainDestroy() {
		if (current === this) current = null
		answerAll("closed", "the editor closed before it answered")
	}

	/**
	 * The tool host's GDScript, which the editor compiles and runs once a project is open: `host.gd`, then each
	 * `host_*.gd` part and each `shared_*.gd` part in name order, which add functions to the same script.
	 */
	@UsedByGodot
	fun hostSource(): String = joined(listOf(HOST_ASSET) + parts("host_") + parts(SHARED_PREFIX))

	/** GDatp's own storage, where files NuJan deletes from a project are kept so they can be restored. */
	@UsedByGodot
	fun filesDir(): String = context.filesDir.absolutePath

	/** GDatp's own version and the ATP spec version it speaks, as JSON, which status reports beside Godot's. */
	@UsedByGodot
	fun versions(): String = JSONObject()
		.put("gdatp", runCatching { context.packageManager.getPackageInfo(context.packageName, 0).versionName }.getOrNull().orEmpty())
		.put("atp_spec", com.nujan_agent.atp.wire.Atp.SPEC_VERSION)
		.toString()

	/**
	 * The game helper's GDScript, which the tool host sends into each game the editor starts: `game_helper.gd`, its
	 * `helper_*.gd` parts, and the `shared_*.gd` parts, so the running game reads and writes values as the editor does.
	 */
	@UsedByGodot
	fun gameHelperSource(): String = joined(listOf(GAME_HELPER_ASSET) + parts("helper_") + parts(SHARED_PREFIX))

	private fun parts(prefix: String): List<String> =
		context.assets.list(HOST_DIR).orEmpty().filter { it.startsWith(prefix) && it.endsWith(".gd") }.sorted().map { "$HOST_DIR/$it" }

	private fun joined(assets: List<String>): String =
		assets.joinToString("\n") { asset -> context.assets.open(asset).bufferedReader().use { it.readText() } }

	/** Called by the tool host once it listens for calls. */
	@UsedByGodot
	fun hostListening() {
		hostListening = true
	}

	/** The tool host's answer to the call [id], as JSON. */
	@UsedByGodot
	fun reply(id: String, answerJson: String) {
		waiting.remove(id)?.complete(answerJson)
	}

	/**
	 * Runs [tool] in the editor and returns the tool host's JSON answer. Without waiting, it answers with an error when
	 * the editor is off screen (its main loop does not run then) or no project is open (the Project Manager has no tool
	 * host); otherwise it waits up to [timeoutMs].
	 */
	fun call(tool: String, argsJson: String, timeoutMs: Long): String {
		if (!onScreen) return error("not_on_screen", "the editor is not on screen, so it cannot run tools")
		if (!hostListening) return error("no_project", "no project is open in the editor")
		val id = ids.incrementAndGet().toString()
		val answer = CompletableFuture<String>()
		waiting[id] = answer
		emitSignal(callArrived.name, id, tool, argsJson)
		return try {
			answer.get(timeoutMs, TimeUnit.MILLISECONDS)
		} catch (e: TimeoutException) {
			waiting.remove(id)
			Log.w(TAG, "No answer to $tool within $timeoutMs ms")
			error("timeout", "the editor did not answer within $timeoutMs ms")
		}
	}

	private fun answerAll(code: String, message: String) {
		val ids = waiting.keys.toList()
		for (id in ids) waiting.remove(id)?.complete(error(code, message))
	}

	private fun error(code: String, message: String) = JSONObject().put("error", code).put("message", message).toString()
}
