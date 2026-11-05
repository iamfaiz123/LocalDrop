package app.localdrop.localdrop

import android.Manifest
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.core.content.IntentCompat
import android.content.pm.PackageManager
import android.os.Build
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Hosts the Flutter UI and implements the `app.localdrop/native` channel:
 * foreground hosting service, keep-screen-on and native thumbnails.
 */
class MainActivity : FlutterActivity() {
    private val worker = Executors.newSingleThreadExecutor()
    private var importChannel: MethodChannel? = null

    /** Last received trip update; Dart pulls it with "takePending". */
    @Volatile private var pendingImport: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIncoming(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIncoming(intent)
    }

    /** Reads a shared .ldtrip file or message text (from WhatsApp etc.). */
    private fun handleIncoming(intent: Intent?) {
        if (intent == null) return
        val uri: Uri? = when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND -> IntentCompat.getParcelableExtra(intent, Intent.EXTRA_STREAM, Uri::class.java)
            else -> null
        }
        val text = if (intent.action == Intent.ACTION_SEND) intent.getStringExtra(Intent.EXTRA_TEXT) else null
        if (uri == null && text == null) return
        worker.execute {
            val content = try {
                uri?.let { u ->
                    contentResolver.openInputStream(u)?.use { input ->
                        val bytes = input.readBytes()
                        if (bytes.size > 5_000_000) null else String(bytes, Charsets.UTF_8)
                    }
                } ?: text
            } catch (e: Exception) {
                null
            }
            if (content != null) {
                pendingImport = content
                runOnUiThread { importChannel?.invokeMethod("incoming", null) }
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        importChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.localdrop/import").also { ch ->
            ch.setMethodCallHandler { call, result ->
                if (call.method == "takePending") {
                    result.success(pendingImport)
                    pendingImport = null
                } else {
                    result.notImplemented()
                }
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.localdrop/native").setMethodCallHandler { call, result ->
            when (call.method) {
                "startHosting" -> {
                    requestNotificationPermission()
                    val intent = Intent(this, HostingService::class.java)
                        .putExtra(HostingService.EXTRA_TITLE, call.argument<String>("title") ?: "LocalDrop")
                        .putExtra(HostingService.EXTRA_CONFIG, call.argument<String>("config"))
                    ContextCompat.startForegroundService(this, intent)
                    result.success(null)
                }
                "stopHosting" -> {
                    // Session ended by the user: forget it so it is never restarted.
                    HostingService.clearSaved(this)
                    stopService(Intent(this, HostingService::class.java))
                    result.success(null)
                }
                "keepScreenOn" -> {
                    if (call.argument<Boolean>("on") == true) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                    result.success(null)
                }
                "thumbnail" -> {
                    val path = call.argument<String>("path")
                    val video = call.argument<Boolean>("video") ?: false
                    val max = call.argument<Int>("maxSize") ?: 480
                    if (path == null) {
                        result.error("bad_args", "path is required", null)
                        return@setMethodCallHandler
                    }
                    worker.execute {
                        val bytes = try {
                            Thumbnails.create(path, video, max)
                        } catch (e: Exception) {
                            null
                        }
                        runOnUiThread { result.success(bytes) }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), 41)
        }
    }

    override fun onDestroy() {
        worker.shutdown()
        super.onDestroy()
    }
}
