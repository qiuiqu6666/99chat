package vip.ninechat.pro.notification

import android.app.NotificationManager
import android.content.Context
import android.graphics.Bitmap
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.LruCache
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

/** Optional enrichment: publication and cancellation never wait for the network. */
internal object NotificationAvatarUpdates {
    private val main = Handler(Looper.getMainLooper())
    private val cache = LruCache<String, Bitmap>(48)
    private val worker = ThreadPoolExecutor(
        1, 1, 30, TimeUnit.SECONDS, ArrayBlockingQueue<Runnable>(32),
        ThreadPoolExecutor.DiscardPolicy(),
    ).apply { allowCoreThreadTimeOut(true) }

    fun enqueue(context: Context, id: Int, token: String, url: String?) {
        val key = url?.trim().orEmpty()
        if (key.isEmpty() || Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        worker.execute {
            val bitmap = cache.get(key) ?: NotificationAvatarLoader.load(context, key).also {
                cache.put(key, it)
            }
            main.post {
                // An old avatar must never revive a dismissed notification or
                // overwrite a newer message that reused its notification id.
                try {
                    val manager = context.getSystemService(NotificationManager::class.java)
                    val current = manager.activeNotifications.firstOrNull {
                        it.id == id && it.notification.extras.getString("avatarToken") == token
                    } ?: return@post
                    val update = NotificationCompat.Builder(context, current.notification)
                        .setLargeIcon(bitmap).setOnlyAlertOnce(true).setSilent(true).build()
                    NotificationManagerCompat.from(context).notify(id, update)
                } catch (_: SecurityException) { }
            }
        }
    }
}
