package app.localdrop.localdrop

import android.Manifest
import android.content.Intent
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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.localdrop/native").setMethodCallHandler { call, result ->
            when (call.method) {
                "startHosting" -> {
                    requestNotificationPermission()
                    val intent = Intent(this, HostingService::class.java)
                        .putExtra(HostingService.EXTRA_TITLE, call.argument<String>("title") ?: "LocalDrop")
                    ContextCompat.startForegroundService(this, intent)
                    result.success(null)
                }
                "stopHosting" -> {
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
