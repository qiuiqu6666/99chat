package vip.ninechat.pro.image

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapRegionDecoder
import android.graphics.Rect
import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import java.io.File
import kotlin.math.max

class ImageRegionDecoderPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(
            binding.binaryMessenger,
            "ninechat/image_region_decoder",
            StandardMethodCodec.INSTANCE,
            binding.binaryMessenger.makeBackgroundTaskQueue(),
        )
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "decodeRegion") {
            result.notImplemented()
            return
        }
        decodeRegion(call, result)
    }

    private fun decodeRegion(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")?.trim().orEmpty()
        val srcLeft = call.argument<Int>("srcLeft") ?: 0
        val srcTop = call.argument<Int>("srcTop") ?: 0
        val srcWidth = call.argument<Int>("srcWidth") ?: 0
        val srcHeight = call.argument<Int>("srcHeight") ?: 0
        val dstWidth = (call.argument<Int>("dstWidth") ?: 0).coerceAtLeast(1)
        val dstHeight = (call.argument<Int>("dstHeight") ?: 0).coerceAtLeast(1)
        if (path.isEmpty() || srcWidth <= 0 || srcHeight <= 0) {
            result.error("invalid_args", "region required", null)
            return
        }
        val file = File(path)
        if (!file.exists() || !file.isFile) {
            result.error("not_found", "image not found", null)
            return
        }
        try {
            val bitmap = decodeRegionBitmap(
                path,
                Rect(srcLeft, srcTop, srcLeft + srcWidth, srcTop + srcHeight),
                dstWidth,
                dstHeight,
            ) ?: run {
                result.error("unsupported_format", "region decode failed", null)
                return
            }
            val scaled = if (bitmap.width == dstWidth && bitmap.height == dstHeight) {
                bitmap
            } else {
                val resized = Bitmap.createScaledBitmap(bitmap, dstWidth, dstHeight, true)
                if (resized !== bitmap) {
                    bitmap.recycle()
                }
                resized
            }
            val argb = scaled.copy(Bitmap.Config.ARGB_8888, false)
            if (argb !== scaled) {
                scaled.recycle()
            }
            val pixels = IntArray(argb.width * argb.height)
            argb.getPixels(pixels, 0, argb.width, 0, 0, argb.width, argb.height)
            val rgba = ByteArray(pixels.size * 4)
            var i = 0
            for (pixel in pixels) {
                rgba[i++] = ((pixel shr 16) and 0xFF).toByte()
                rgba[i++] = ((pixel shr 8) and 0xFF).toByte()
                rgba[i++] = (pixel and 0xFF).toByte()
                rgba[i++] = ((pixel ushr 24) and 0xFF).toByte()
            }
            val width = argb.width
            val height = argb.height
            argb.recycle()
            result.success(
                mapOf(
                    "bytes" to rgba,
                    "width" to width,
                    "height" to height,
                ),
            )
        } catch (e: Exception) {
            result.error("decode_failed", e.message, null)
        }
    }

    private fun decodeRegionBitmap(
        path: String,
        rect: Rect,
        dstWidth: Int,
        dstHeight: Int,
    ): Bitmap? {
        val sample = sampleSize(rect.width(), rect.height(), dstWidth, dstHeight)
        val opts = BitmapFactory.Options().apply {
            inPreferredConfig = Bitmap.Config.ARGB_8888
            inSampleSize = sample
        }
        try {
            val decoder = if (Build.VERSION.SDK_INT >= 31) {
                BitmapRegionDecoder.newInstance(path)
            } else {
                @Suppress("DEPRECATION")
                BitmapRegionDecoder.newInstance(path, false)
            } ?: return null
            return try {
                decoder.decodeRegion(rect, opts)
            } finally {
                decoder.recycle()
            }
        } catch (_: Exception) {
        }
        if (Build.VERSION.SDK_INT >= 28) {
            val source = android.graphics.ImageDecoder.createSource(File(path))
            return android.graphics.ImageDecoder.decodeBitmap(source) { decoder, _, _ ->
                decoder.setTargetSize(dstWidth, dstHeight)
                decoder.setCrop(rect)
                decoder.allocator = android.graphics.ImageDecoder.ALLOCATOR_SOFTWARE
            }
        }
        return null
    }

    private fun sampleSize(srcW: Int, srcH: Int, dstW: Int, dstH: Int): Int {
        var sample = 1
        while (srcW / (sample * 2) >= dstW && srcH / (sample * 2) >= dstH) {
            sample *= 2
        }
        return max(1, sample)
    }
}
