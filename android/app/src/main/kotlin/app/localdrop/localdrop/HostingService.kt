package app.localdrop.localdrop

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat

/**
 * Keeps a hosted session running while the LocalDrop UI is closed.
 *
 * The Rust server lives in the app process (not in the Flutter UI), so it
 * keeps serving after the activity is closed or swiped away as long as this
 * foreground service keeps the process alive. The session only stops when the
 * host ends it in the app ("stopHosting" clears the saved config).
 *
 * If Android kills and later recreates the process (START_STICKY), the
 * service restarts the server itself through JNI with the saved resume
 * config — same session, PIN and media — before any UI is opened.
 * Holds a Wi-Fi lock and a partial wake lock so transfers continue with the
 * screen off. It never controls the hotspot.
 */
class HostingService : Service() {
    private var wifiLock: WifiManager.WifiLock? = null
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val saved = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        intent?.getStringExtra(EXTRA_CONFIG)?.let { config ->
            saved.edit()
                .putString(KEY_CONFIG, config)
                .putString(KEY_TITLE, intent.getStringExtra(EXTRA_TITLE) ?: "LocalDrop")
                .apply()
        }
        val config = saved.getString(KEY_CONFIG, null)
        val title = saved.getString(KEY_TITLE, null) ?: intent?.getStringExtra(EXTRA_TITLE) ?: "LocalDrop"
        if (config == null) {
            // No session to keep alive (it was ended).
            stopSelf()
            return START_NOT_STICKY
        }
        try {
            createChannel()
            val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE else 0
            ServiceCompat.startForeground(this, NOTIFICATION_ID, buildNotification(title), type)
        } catch (e: Exception) {
            // e.g. Android 12+ refusing a foreground start from the background.
            Log.w(TAG, "Could not enter foreground; the session resumes when the app is opened", e)
            stopSelf()
            return START_NOT_STICKY
        }
        acquireLocks()
        ensureServerRunning(config)
        return START_STICKY
    }

    /** Restarts the server if the process was recreated without the UI. */
    private fun ensureServerRunning(config: String) {
        if (!loadEngine()) return
        Thread {
            try {
                if (!nativeIsRunning()) {
                    val result = nativeStart(config)
                    Log.i(TAG, "Restarted hosted session: $result")
                }
            } catch (e: Throwable) {
                Log.e(TAG, "Failed to restart hosted session", e)
            }
        }.start()
    }

    private fun buildNotification(title: String): Notification {
        val open = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return NotificationCompat.Builder(this, CHANNEL)
            .setContentTitle("Hosting “$title”")
            .setContentText("Your session keeps running. Open LocalDrop to end it.")
            .setSmallIcon(android.R.drawable.stat_sys_upload)
            .setOngoing(true)
            .setContentIntent(open)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun acquireLocks() {
        if (wifiLock == null) {
            val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            @Suppress("DEPRECATION")
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) WifiManager.WIFI_MODE_FULL_LOW_LATENCY else WifiManager.WIFI_MODE_FULL_HIGH_PERF
            wifiLock = wm.createWifiLock(mode, "LocalDrop:hosting").apply { setReferenceCounted(false); acquire() }
        }
        if (wakeLock == null) {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "LocalDrop:hosting").apply {
                setReferenceCounted(false)
                acquire()
            }
        }
    }

    override fun onDestroy() {
        wifiLock?.takeIf { it.isHeld }?.release()
        wakeLock?.takeIf { it.isHeld }?.release()
        wifiLock = null
        wakeLock = null
        super.onDestroy()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(NotificationManager::class.java)
            if (nm.getNotificationChannel(CHANNEL) == null) {
                nm.createNotificationChannel(
                    NotificationChannel(CHANNEL, "Active session", NotificationManager.IMPORTANCE_LOW).apply {
                        description = "Shown while this phone hosts a LocalDrop session"
                    },
                )
            }
        }
    }

    companion object {
        const val EXTRA_TITLE = "title"
        const val EXTRA_CONFIG = "config"
        private const val TAG = "LocalDrop"
        private const val PREFS = "localdrop_hosting"
        private const val KEY_CONFIG = "config"
        private const val KEY_TITLE = "title"
        private const val CHANNEL = "hosting"
        private const val NOTIFICATION_ID = 7
        private var engineLoaded = false

        fun clearSaved(context: Context) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().clear().apply()
        }

        @Synchronized
        private fun loadEngine(): Boolean {
            if (!engineLoaded) {
                engineLoaded = try {
                    System.loadLibrary("localdrop_engine")
                    true
                } catch (e: UnsatisfiedLinkError) {
                    Log.e(TAG, "Engine library missing", e)
                    false
                }
            }
            return engineLoaded
        }

        /** Implemented in Rust (native/engine/src/ffi.rs, `android` module). */
        @JvmStatic external fun nativeStart(config: String): String

        @JvmStatic external fun nativeIsRunning(): Boolean
    }
}
