package app.localdrop.localdrop

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.media.MediaMetadataRetriever
import android.os.Build
import java.io.ByteArrayOutputStream
import java.io.File
import kotlin.math.max
import kotlin.math.roundToInt

/** JPEG thumbnails for files the engine cannot decode itself (videos, HEIC). */
object Thumbnails {
    fun create(path: String, video: Boolean, maxSize: Int): ByteArray? {
        val bitmap = (if (video) videoFrame(path, maxSize) else image(path, maxSize)) ?: return null
        val scaled = scale(bitmap, maxSize)
        val out = ByteArrayOutputStream()
        scaled.compress(Bitmap.CompressFormat.JPEG, 80, out)
        if (scaled !== bitmap) scaled.recycle()
        bitmap.recycle()
        return out.toByteArray()
    }

    private fun videoFrame(path: String, maxSize: Int): Bitmap? {
        val r = MediaMetadataRetriever()
        return try {
            r.setDataSource(path)
            val atUs = 1_000_000L
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                r.getScaledFrameAtTime(atUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC, maxSize, maxSize)
            } else {
                r.getFrameAtTime(atUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
            } ?: r.frameAtTime
        } finally {
            r.release()
        }
    }

    private fun image(path: String, maxSize: Int): Bitmap? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            // ImageDecoder handles HEIC/HEIF and applies EXIF orientation.
            val src = ImageDecoder.createSource(File(path))
            return ImageDecoder.decodeBitmap(src) { decoder, info, _ ->
                val w = info.size.width
                val h = info.size.height
                val s = max(w, h).toFloat() / maxSize
                if (s > 1f) decoder.setTargetSize((w / s).roundToInt().coerceAtLeast(1), (h / s).roundToInt().coerceAtLeast(1))
                decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
            }
        }
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        var sample = 1
        while (max(bounds.outWidth, bounds.outHeight) / (sample * 2) >= maxSize) sample *= 2
        return BitmapFactory.decodeFile(path, BitmapFactory.Options().apply { inSampleSize = sample })
    }

    private fun scale(b: Bitmap, maxSize: Int): Bitmap {
        val s = max(b.width, b.height).toFloat() / maxSize
        if (s <= 1f) return b
        return Bitmap.createScaledBitmap(b, (b.width / s).roundToInt().coerceAtLeast(1), (b.height / s).roundToInt().coerceAtLeast(1), true)
    }
}
