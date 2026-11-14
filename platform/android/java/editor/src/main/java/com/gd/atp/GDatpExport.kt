package com.gd.atp

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.math.BigInteger
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.SecureRandom
import java.security.Signature
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * What exporting a game to an APK needs that the engine's own exporter does not bring on a phone: the release template, carried in
 * GDatp's assets, and a signing key. The key is made on this phone the first time and stays in GDatp's private storage: it is good
 * for installing and sharing, and a store wants the person's own key.
 */
internal class GDatpExport(private val context: Context) {

	/** A keystore and how to open it. */
	data class Signing(val keystore: File, val alias: String, val password: String)

	private val folder: File get() = File(context.filesDir, "gdatp/export")

	/** The release template on disk, copied from the assets once; null when this build of GDatp carries none. */
	fun template(): File? {
		val file = File(folder, TEMPLATE)
		val asset = "$TEMPLATE_ASSETS/$TEMPLATE"
		val installed = context.packageManager.getPackageInfo(context.packageName, 0).lastUpdateTime
		if (file.isFile && file.lastModified() >= installed) return file
		return runCatching {
			folder.mkdirs()
			context.assets.open(asset).use { input -> file.outputStream().use(input::copyTo) }
			file
		}.getOrNull()
	}

	/** This install's signing key, made the first time it is asked for. */
	fun signing(): Signing {
		val keystore = File(folder, KEYSTORE)
		val secret = File(folder, KEYSTORE_SECRET)
		if (keystore.isFile && secret.isFile) return Signing(keystore, ALIAS, secret.readText())
		folder.mkdirs()
		val password = ByteArray(PASSWORD_BYTES).also(SecureRandom()::nextBytes).joinToString("") { "%02x".format(it) }
		val pair = KeyPairGenerator.getInstance("RSA").apply { initialize(KEY_BITS) }.generateKeyPair()
		val certificate = selfSigned(pair)
		val store = KeyStore.getInstance("PKCS12").apply { load(null, null) }
		store.setKeyEntry(ALIAS, pair.private, password.toCharArray(), arrayOf(certificate))
		keystore.outputStream().use { store.store(it, password.toCharArray()) }
		secret.writeText(password)
		return Signing(keystore, ALIAS, password)
	}

	/**
	 * A copy of [apk] in the phone's Downloads, where the person can find it and share it; its address there, or null. It
	 * replaces the copy an earlier export of this game left, since each is a whole game and a model exports several times.
	 * Android lets an app remove only what it wrote, so a copy from before a reinstall stays and this one lands beside it.
	 */
	fun toDownloads(apk: File, name: String): Uri? {
		if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
		val folder = Environment.DIRECTORY_DOWNLOADS + "/GDatp"
		runCatching {
			context.contentResolver.delete(
				MediaStore.Downloads.EXTERNAL_CONTENT_URI,
				"${MediaStore.Downloads.DISPLAY_NAME}=? AND ${MediaStore.Downloads.RELATIVE_PATH}=?",
				arrayOf(name, "$folder/"),
			)
		}
		val values = ContentValues().apply {
			put(MediaStore.Downloads.DISPLAY_NAME, name)
			put(MediaStore.Downloads.MIME_TYPE, APK_TYPE)
			put(MediaStore.Downloads.RELATIVE_PATH, folder)
		}
		val uri = context.contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values) ?: return null
		context.contentResolver.openOutputStream(uri)?.use { out -> apk.inputStream().use { it.copyTo(out) } }
		return uri
	}

	/** The settings an Android export takes for [title], read by the engine's own exporter. */
	fun settings(title: String, slug: String, template: File, signing: Signing, version: Int): JSONObject = JSONObject()
		.put("gradle_build/use_gradle_build", false)
		.put("custom_template/release", template.path)
		.put("architectures/arm64-v8a", true)
		.put("architectures/armeabi-v7a", false)
		.put("architectures/x86", false)
		.put("architectures/x86_64", false)
		.put("package/unique_name", "$PACKAGE_PREFIX.${slug.replace("-", "").ifEmpty { "game" }.let { if (it.first().isDigit()) "g$it" else it }}")
		.put("package/name", title)
		.put("package/signed", true)
		.put("version/code", version)
		.put("version/name", "1.$version")
		.put("keystore/release", signing.keystore.path)
		.put("keystore/release_user", signing.alias)
		.put("keystore/release_password", signing.password)

	private fun selfSigned(pair: java.security.KeyPair): X509Certificate {
		val algorithm = der(TAG_SEQUENCE, oid(SHA256_WITH_RSA) + der(TAG_NULL, ByteArray(0)))
		val name = der(TAG_SEQUENCE, der(TAG_SET, der(TAG_SEQUENCE, oid(COMMON_NAME) + der(TAG_UTF8, "GDatp game".toByteArray()))))
		val now = System.currentTimeMillis()
		val validity = der(TAG_SEQUENCE, time(now - DAY_MS) + time(now + VALID_YEARS * YEAR_MS))
		val body = der(
			TAG_SEQUENCE,
			der(TAG_VERSION, der(TAG_INTEGER, byteArrayOf(2))) +
				der(TAG_INTEGER, BigInteger(SERIAL_BITS, SecureRandom()).setBit(SERIAL_BITS - 2).toByteArray()) +
				algorithm + name + validity + name + pair.public.encoded,
		)
		val signature = Signature.getInstance("SHA256withRSA").apply {
			initSign(pair.private)
			update(body)
		}.sign()
		val whole = der(TAG_SEQUENCE, body + algorithm + der(TAG_BIT_STRING, byteArrayOf(0) + signature))
		return CertificateFactory.getInstance("X.509").generateCertificate(whole.inputStream()) as X509Certificate
	}

	private fun time(millis: Long): ByteArray {
		val utc = TimeZone.getTimeZone("UTC")
		val year = SimpleDateFormat("yyyy", Locale.US).apply { timeZone = utc }.format(Date(millis)).toInt()
		// X.509 keeps two-digit years for dates before 2050.
		return if (year < 2050) {
			der(TAG_UTC_TIME, SimpleDateFormat("yyMMddHHmmss'Z'", Locale.US).apply { timeZone = utc }.format(Date(millis)).toByteArray())
		} else {
			der(TAG_GENERALIZED_TIME, SimpleDateFormat("yyyyMMddHHmmss'Z'", Locale.US).apply { timeZone = utc }.format(Date(millis)).toByteArray())
		}
	}

	private fun oid(parts: IntArray): ByteArray {
		val out = ByteArrayOutputStream()
		out.write(parts[0] * 40 + parts[1])
		for (part in parts.drop(2)) {
			val bytes = mutableListOf(part and 0x7f)
			var rest = part ushr 7
			while (rest > 0) {
				bytes.add(0, (rest and 0x7f) or 0x80)
				rest = rest ushr 7
			}
			bytes.forEach(out::write)
		}
		return der(TAG_OID, out.toByteArray())
	}

	private fun der(tag: Int, content: ByteArray): ByteArray {
		val out = ByteArrayOutputStream()
		out.write(tag)
		if (content.size < 0x80) {
			out.write(content.size)
		} else {
			val length = BigInteger.valueOf(content.size.toLong()).toByteArray().dropWhile { it == 0.toByte() }
			out.write(0x80 or length.size)
			length.forEach { out.write(it.toInt()) }
		}
		out.write(content)
		return out.toByteArray()
	}

	companion object {
		const val APK_TYPE = "application/vnd.android.package-archive"
		private const val TEMPLATE_ASSETS = "gdatp/export"
		private const val TEMPLATE = "android_release.apk"
		private const val KEYSTORE = "sharing.p12"
		private const val KEYSTORE_SECRET = "sharing.secret"
		private const val ALIAS = "game"
		private const val PACKAGE_PREFIX = "com.gdatp.game"
		private const val PASSWORD_BYTES = 24
		private const val KEY_BITS = 2048
		private const val SERIAL_BITS = 64
		private const val DAY_MS = 86_400_000L
		private const val YEAR_MS = 365 * DAY_MS
		private const val VALID_YEARS = 30L
		private val SHA256_WITH_RSA = intArrayOf(1, 2, 840, 113549, 1, 1, 11)
		private val COMMON_NAME = intArrayOf(2, 5, 4, 3)
		private const val TAG_INTEGER = 0x02
		private const val TAG_BIT_STRING = 0x03
		private const val TAG_NULL = 0x05
		private const val TAG_OID = 0x06
		private const val TAG_UTF8 = 0x0c
		private const val TAG_UTC_TIME = 0x17
		private const val TAG_GENERALIZED_TIME = 0x18
		private const val TAG_SEQUENCE = 0x30
		private const val TAG_SET = 0x31
		private const val TAG_VERSION = 0xa0
	}
}

/**
 * Android's installer for a game exported with `install`, offered once the turn that exported it ends: a model exports as it goes,
 * and the person is asked once, for the last game. It comes up at once when the editor is on screen, since Android lets only an app
 * on screen open a screen, and otherwise the next time the editor comes to the front, within [KEPT_MS] of the turn's end.
 */
internal object GDatpInstallOffer {
	private class Offer(val caller: String, val turn: String?, val apk: Uri, val since: Long)

	/** The last export a turn asked to install, until that turn ends. */
	private var asked: Offer? = null

	/** An export whose turn has ended, until the editor is on screen to offer it. */
	private var due: Offer? = null

	/** Notes the install [caller]'s export asked for, and returns what the export's answer says of it. */
	@Synchronized
	fun request(context: Context, caller: String, turn: String?, apk: Uri): String {
		if (turn == null) {
			// A caller that names no turns never says one has ended, so the installer comes up now.
			due = Offer(caller, null, apk, System.currentTimeMillis())
			offer(context)
			return "Android's installer is asking the person."
		}
		asked = Offer(caller, turn, apk, System.currentTimeMillis())
		return "Android's installer asks the person once this turn ends, for the last game exported in it. Test a change with run try, and export again only once the game has changed."
	}

	/** [caller]'s turn [turn] has ended: the last game it asked to install is offered now, or as soon as the editor is on screen. */
	@Synchronized
	fun turnEnded(context: Context, caller: String, turn: String) {
		val ended = asked?.takeIf { it.caller == caller && it.turn == turn } ?: return
		asked = null
		due = Offer(ended.caller, ended.turn, ended.apk, System.currentTimeMillis())
		offer(context)
	}

	/** Brings up the installer for the game that is due, when the editor is on screen; the editor calls this as it comes to the front. */
	@Synchronized
	fun offer(context: Context) {
		val pending = due ?: return
		if (System.currentTimeMillis() - pending.since > KEPT_MS) {
			due = null
			return
		}
		if (GDatpPlugin.current?.isOnScreen != true) return
		due = null
		val install = Intent(Intent.ACTION_VIEW).setDataAndType(pending.apk, GDatpExport.APK_TYPE)
			.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
		Handler(Looper.getMainLooper()).post { runCatching { context.startActivity(install) } }
	}

	private const val KEPT_MS = 30 * 60_000L
}
