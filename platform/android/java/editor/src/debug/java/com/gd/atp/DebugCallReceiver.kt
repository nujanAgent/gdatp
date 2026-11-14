package com.gd.atp

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.nujan_agent.atp.provider.AtpCall
import com.nujan_agent.atp.provider.AtpCaller
import kotlinx.coroutines.runBlocking
import kotlin.concurrent.thread

/**
 * Lets a developer call the editor's tools from a computer while GDatp is developed:
 * `adb shell am broadcast -n com.gd.atp/com.gd.atp.DebugCallReceiver --es tool status --es args '{}'`
 * prints the answer as the broadcast's data. Only holders of `DUMP`, which the shell has, may send it.
 * The tools written in Kotlin answer as a host would see them; the rest go straight to the editor, so a picture stays a path.
 */
class DebugCallReceiver : BroadcastReceiver() {

	override fun onReceive(context: Context, intent: Intent) {
		val tool = intent.getStringExtra("tool") ?: "status"
		val args = intent.getStringExtra("args") ?: "{}"
		val result = goAsync()
		thread(name = "GDatp debug call") {
			val answer = if (tool in APP_TOOLS) appTool(context, tool, args) else GDatpPlugin.current?.call(tool, args, 8_000)
				?: """{"error":"no_editor","message":"no editor runs in GDatp's process"}"""
			Log.i("GDatp", "debug call $tool -> $answer")
			result.resultData = answer
			result.finish()
		}
	}

	private fun appTool(context: Context, tool: String, args: String): String {
		val caller = AtpCaller(context.packageName, "", false)
		val found = GDatpTools(context.applicationContext).tools(caller).first { it.name == tool }
		return runBlocking { found.handler.call(AtpCall(tool, args, caller)) }.text
	}

	private companion object {
		val APP_TOOLS = setOf("parts", "guide", "projects", "projects_edit", "project_create", "project_open", "assets", "export", "run")
	}
}
