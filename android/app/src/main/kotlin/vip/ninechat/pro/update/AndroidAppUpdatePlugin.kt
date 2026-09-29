package vip.ninechat.pro.update

import android.app.Activity
import android.app.DownloadManager
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Executors

/** Transfers belong to Android, not the Activity or Flutter engine. */
class AndroidAppUpdatePlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {
    private lateinit var context: Context
    private lateinit var channel: MethodChannel
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var activity: Activity? = null
    @Volatile private var attached = false
    private val prefs get() = context.getSharedPreferences("app_update_v1", Context.MODE_PRIVATE)
    private val manager get() = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
    private var validatedFile: String? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        attached = true
        channel = MethodChannel(binding.binaryMessenger, "ninechat/app_update")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        attached = false
        channel.setMethodCallHandler(null)
        worker.shutdown()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) { activity = binding.activity }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) { activity = binding.activity }
    override fun onDetachedFromActivityForConfigChanges() { activity = null }
    override fun onDetachedFromActivity() { activity = null }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method !in setOf("ensure", "status", "cancel", "install")) {
            result.notImplemented()
            return
        }
        // APK parsing, signature checks and DownloadManager queries may block.
        worker.execute {
            try {
                when (call.method) {
                    "ensure" -> reply(result, ensure(call))
                    "status" -> reply(result, status())
                    "cancel" -> { clearDownload(); reply(result, null) }
                    "install" -> {
                        val key = call.argument<String>("key") ?: ""
                        val current = status(revalidate = true)
                        val request = readRequest()
                        if (request == null || request.optString("key") != key || current["state"] != "ready") {
                            reply(result, "not_ready")
                        } else {
                            val file = targetFile(key)
                            main.post {
                                if (attached) {
                                    if (readRequest()?.optString("key") != key || !file.isFile) result.success("not_ready")
                                    else install(file, call.argument<Boolean>("requestPermission") == true, result)
                                }
                            }
                        }
                    }
                }
            } catch (error: Exception) {
                // Do not log signed download URLs or metadata contents.
                Log.w("AppUpdate", "operation=${call.method} failed=${error.javaClass.simpleName}")
                main.post {
                    if (attached) result.error("update_unavailable", "Update operation unavailable", null)
                }
            }
        }
    }

    private fun reply(result: MethodChannel.Result, value: Any?) {
        main.post { if (attached) result.success(value) }
    }

    private fun readRequest(): JSONObject? = prefs.getString("request", null)?.let {
        try { JSONObject(it) } catch (_: Exception) { null }
    }

    private fun targetFile(key: String): File {
        require(key.matches(Regex("[a-f0-9]{64}")))
        val root = requireNotNull(context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS))
        return File(File(root, "app-updates"), "$key.apk")
    }

    private fun ensure(call: MethodCall): Map<String, Any> {
        val key = requireNotNull(call.argument<String>("key"))
        val url = requireNotNull(call.argument<String>("url"))
        val uri = Uri.parse(url)
        require(uri.scheme in setOf("http", "https") && !uri.host.isNullOrBlank() && uri.userInfo == null)
        val request = JSONObject().apply {
            put("key", key)
            put("url", url)
            put("version", requireNotNull(call.argument<String>("version")))
            put("build", call.argument<Number>("build")?.toLong() ?: 0L)
            put("mandatory", call.argument<Boolean>("mandatory") == true)
            put("notes", call.argument<String>("notes") ?: "")
        }
        val file = targetFile(key)
        if (readRequest()?.optString("key") == key) {
            // Policy/changelog can change without forcing another download.
            check(prefs.edit().putString("request", request.toString()).commit())
            val current = status()
            if (current["state"] in setOf("ready", "running", "queued", "paused", "installed") ||
                (current["state"] == "failed" && call.argument<Boolean>("retry") != true)) return current
        }
        clearDownload()
        check(file.parentFile!!.isDirectory || file.parentFile!!.mkdirs())
        if (file.exists()) check(file.delete())
        val download = DownloadManager.Request(uri)
            .setTitle("99chat ${request.getString("version")}")
            .setDescription("正在下载更新，完成后可安装")
            .setMimeType("application/vnd.android.package-archive")
            .setAllowedOverMetered(call.argument<Boolean>("allowMetered") == true)
            .setAllowedOverRoaming(false)
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
            .setDestinationInExternalFilesDir(context, Environment.DIRECTORY_DOWNLOADS, "app-updates/$key.apk")
        // Persist metadata before enqueue. If the process dies between enqueue
        // and ID persistence, adopt the owned destination on the next startup.
        check(prefs.edit().putString("request", request.toString()).commit())
        val id = manager.enqueue(download)
        if (!prefs.edit().putLong("downloadId", id).commit()) {
            manager.remove(id)
            error("Unable to save download")
        }
        Log.i("AppUpdate", "download_enqueued id=$id build=${request.optLong("build")}")
        return status()
    }

    private fun downloadId(request: JSONObject): Long {
        val saved = prefs.getLong("downloadId", -1L)
        if (saved >= 0) return saved
        val destination = Uri.fromFile(targetFile(request.getString("key"))).toString()
        manager.query(DownloadManager.Query())?.use { cursor ->
            while (cursor.moveToNext()) {
                if (cursor.getString(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_LOCAL_URI)) == destination) {
                    val id = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_ID))
                    check(prefs.edit().putLong("downloadId", id).commit())
                    return id
                }
            }
        }
        return -1L
    }

    private fun status(revalidate: Boolean = false): Map<String, Any> {
        val request = readRequest() ?: return mapOf("state" to "missing")
        val metadata = request.keys().asSequence().associateWith { request.get(it) }
        fun response(state: String, reason: String = "", received: Long = 0, total: Long = 0) =
            mapOf("state" to state, "reason" to reason, "received" to received, "total" to total, "request" to metadata)
        val id = downloadId(request)
        if (id < 0) return response("missing")
        manager.query(DownloadManager.Query().setFilterById(id))?.use { cursor ->
            if (!cursor.moveToFirst()) return response("missing")
            val state = cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
            val reason = cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_REASON))
            val received = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR))
            val total = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES))
            if (state == DownloadManager.STATUS_SUCCESSFUL) {
                val file = targetFile(request.getString("key"))
                if (!file.isFile || file.length() <= 0 || (total > 0 && file.length() != total)) {
                    return response("failed", "incomplete_apk")
                }
                val fingerprint = "${file.path}:${file.length()}:${file.lastModified()}"
                if (revalidate || fingerprint != validatedFile) {
                    val error = validateApk(file, request)
                    if (error != null) return response(if (error == "already_installed") "installed" else "failed", error)
                    validatedFile = fingerprint
                    Log.i("AppUpdate", "apk_verified id=$id build=${request.optLong("build")}")
                }
                return response("ready", received = received, total = total)
            }
            return response(when (state) {
                DownloadManager.STATUS_PENDING -> "queued"
                DownloadManager.STATUS_RUNNING -> "running"
                DownloadManager.STATUS_PAUSED -> "paused"
                else -> "failed"
            }, reason.toString(), received, total)
        }
        return response("missing")
    }

    @Suppress("DEPRECATION")
    private fun validateApk(file: File, request: JSONObject): String? {
        val pm = context.packageManager
        val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
        val archive = pm.getPackageArchiveInfo(file.path, flags) ?: return "invalid_apk"
        val installed = pm.getPackageInfo(context.packageName, flags)
        val expectedBuild = request.optLong("build")
        return ApkUpdatePolicy.rejection(
            expectedPackage = context.packageName, actualPackage = archive.packageName,
            installedBuild = versionCode(installed), actualBuild = versionCode(archive), expectedBuild = expectedBuild,
            expectedVersion = request.getString("version"), actualVersion = archive.versionName ?: "",
            installedSigners = signers(installed, false), archiveSigners = signers(archive, false),
            archiveHistory = signers(archive, true),
        )
    }

    @Suppress("DEPRECATION")
    private fun versionCode(info: PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()

    @Suppress("DEPRECATION")
    private fun signers(info: PackageInfo, history: Boolean): Set<String> {
        val signatures = if (Build.VERSION.SDK_INT >= 28) {
            val signing = info.signingInfo
            if (history && signing?.hasMultipleSigners() == false) signing.signingCertificateHistory
            else signing?.apkContentsSigners
        } else info.signatures
        return signatures?.map { signature ->
            MessageDigest.getInstance("SHA-256").digest(signature.toByteArray()).joinToString("") { "%02x".format(it) }
        }?.toSet() ?: emptySet()
    }

    private fun install(file: File, requestPermission: Boolean, result: MethodChannel.Result) {
        val host = activity
        if (host == null || host.isFinishing || host.isDestroyed || !host.hasWindowFocus()) {
            result.success("not_foreground")
            return
        }
        try {
            if (Build.VERSION.SDK_INT >= 26 && !context.packageManager.canRequestPackageInstalls()) {
                if (requestPermission) {
                    host.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${context.packageName}")))
                }
                Log.i("AppUpdate", if (requestPermission) "install_permission_requested" else "install_permission_denied")
                result.success(if (requestPermission) "permission_required" else "permission_denied")
                return
            }
            val uri = FileProvider.getUriForFile(context, "${context.packageName}.app_updates", file)
            host.startActivity(Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                clipData = ClipData.newRawUri("99chat update", uri)
            })
            Log.i("AppUpdate", "installer_opened")
            result.success("installer_opened")
        } catch (error: Exception) {
            Log.w("AppUpdate", "installer_open_failed=${error.javaClass.simpleName}")
            result.success("unavailable")
        }
    }

    private fun clearDownload() {
        val request = readRequest()
        if (request != null) {
            val id = downloadId(request)
            if (id >= 0) manager.remove(id)
            targetFile(request.getString("key")).delete()
        }
        validatedFile = null
        check(prefs.edit().clear().commit())
    }
}
