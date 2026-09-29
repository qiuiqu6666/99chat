package vip.ninechat.pro.notification

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import vip.ninechat.pro.R
import java.net.HttpURLConnection
import java.net.URL

object NotificationAvatarLoader {
    fun load(context: Context, avatarUrl: String?): Bitmap {
        val remote = resolveAbsoluteUrl(avatarUrl?.trim().orEmpty())
        if (remote.isNotEmpty()) {
            try {
                val connection = URL(remote).openConnection() as HttpURLConnection
                connection.connectTimeout = 2000
                connection.readTimeout = 2000
                connection.instanceFollowRedirects = true
                connection.setRequestProperty("User-Agent", "99Chat/1.0")
                try {
                    val bytes = connection.inputStream.use { stream ->
                        val out = java.io.ByteArrayOutputStream()
                        val buffer = ByteArray(8192)
                        while (true) {
                            val count = stream.read(buffer)
                            if (count < 0) break
                            if (out.size() + count > 2 * 1024 * 1024) {
                                throw java.io.IOException("avatar too large")
                            }
                            out.write(buffer, 0, count)
                        }
                        out.toByteArray()
                    }
                    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                    BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
                    val options = BitmapFactory.Options().apply { inSampleSize = 1 }
                    while (maxOf(bounds.outWidth, bounds.outHeight) / options.inSampleSize > 256) {
                        options.inSampleSize *= 2
                    }
                    BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)?.let { return it }
                } finally {
                    connection.disconnect()
                }
            } catch (_: Exception) {
                // fall through to platform logo
            }
        }
        return BitmapFactory.decodeResource(context.resources, R.mipmap.ic_launcher)
            ?: Bitmap.createBitmap(1, 1, Bitmap.Config.ARGB_8888)
    }

    private fun resolveAbsoluteUrl(raw: String): String {
        if (raw.isEmpty()) {
            return ""
        }
        if (raw.startsWith("http://") || raw.startsWith("https://")) {
            return raw
        }
        return raw
    }
}
