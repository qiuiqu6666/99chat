package vip.ninechat.pro.media

import android.graphics.BitmapFactory
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Build
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Button
import android.widget.LinearLayout
import android.provider.MediaStore
import android.content.ContentValues
import android.os.Environment
import androidx.activity.OnBackPressedCallback
import androidx.activity.ComponentActivity
import androidx.media3.common.MediaItem
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import androidx.viewpager2.widget.ViewPager2
import androidx.recyclerview.widget.RecyclerView
import android.window.OnBackInvokedDispatcher
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

class NativeMediaPreviewActivity : ComponentActivity() {
    private lateinit var pager: ViewPager2
    private lateinit var items: List<NativeMediaItem>
    private var currentIndex = 0
    private var player: ExoPlayer? = null
    private var playerView: PlayerView? = null
    private val executor = Executors.newCachedThreadPool()
    private var finished = false
    private var downY = 0f
    private var dismissing = false
    private lateinit var counter: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = android.graphics.Color.BLACK
        window.navigationBarColor = android.graphics.Color.BLACK
        items = try {
            parseItems(intent.getStringExtra(EXTRA_ITEMS).orEmpty())
        } catch (_: Exception) {
            emptyList()
        }
        currentIndex = intent.getIntExtra(EXTRA_INDEX, 0).coerceIn(0, (items.size - 1).coerceAtLeast(0))
        if (items.isEmpty()) {
            finishPreview("error", null, "empty_media_list")
            return
        }
        val root = FrameLayout(this).apply { setBackgroundColor(android.graphics.Color.BLACK) }
        pager = ViewPager2(this).apply {
            orientation = ViewPager2.ORIENTATION_HORIZONTAL
            offscreenPageLimit = 1
            adapter = MediaPagerAdapter()
            setCurrentItem(currentIndex, false)
            registerOnPageChangeCallback(object : ViewPager2.OnPageChangeCallback() {
                override fun onPageSelected(position: Int) {
                    currentIndex = position
                    updateCounter()
                    attachVideoIfNeeded(position)
                }
            })
        }
        root.addView(pager, FrameLayout.LayoutParams(-1, -1))
        val close = TextView(this).apply {
            text = "×"
            textSize = 36f
            setTextColor(android.graphics.Color.WHITE)
            gravity = Gravity.CENTER
            setPadding(20, 16, 20, 16)
            setOnClickListener { finishPreview("close", currentItem()?.messageId, null) }
        }
        val closeParams = FrameLayout.LayoutParams(72, 72, Gravity.TOP or Gravity.START)
        root.addView(close, closeParams)
        counter = TextView(this).apply {
            setTextColor(android.graphics.Color.WHITE)
            textSize = 16f
            gravity = Gravity.CENTER
            setShadowLayer(4f, 0f, 1f, android.graphics.Color.BLACK)
        }
        root.addView(counter, FrameLayout.LayoutParams(140, 72, Gravity.TOP or Gravity.CENTER_HORIZONTAL))
        root.addView(Button(this).apply {
            text = "保存"
            setOnClickListener { saveCurrentImage() }
        }, FrameLayout.LayoutParams(96, 64, Gravity.TOP or Gravity.END))
        val actions = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(16, 8, 16, 24)
            addView(actionButton("转发") { emitOperation("forward") })
            addView(actionButton("编辑") { emitOperation("edit") })
            addView(actionButton("删除") { emitOperation("delete") })
        }
        root.addView(actions, FrameLayout.LayoutParams(-1, 72, Gravity.BOTTOM))
        updateCounter()
        pager.getChildAt(0)?.setOnTouchListener { view, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downY = event.rawY
                    false
                }
                MotionEvent.ACTION_UP -> {
                    val delta = event.rawY - downY
                    if (delta > 180f && !dismissing && currentItem()?.type != "video") {
                        dismissing = true
                        root.animate().alpha(0f).setDuration(180L).withEndAction {
                            finishPreview("swipe", currentItem()?.messageId, null)
                        }.start()
                        true
                    } else false
                }
                else -> false
            }
        }
        setContentView(root)
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                finishPreview("back", currentItem()?.messageId, null)
            }
        })
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            onBackInvokedDispatcher.registerOnBackInvokedCallback(
                OnBackInvokedDispatcher.PRIORITY_DEFAULT,
            ) {
                finishPreview("back", currentItem()?.messageId, null)
            }
        }
        attachVideoIfNeeded(currentIndex)
    }

    private fun attachVideoIfNeeded(position: Int) {
        releasePlayer()
        val item = items.getOrNull(position) ?: return
        if (item.type != "video") return
        val recycler = pager.getChildAt(0) as? RecyclerView ?: return
        val holder = recycler.findViewHolderForAdapterPosition(position) as? VideoHolder
            ?: return
        val view = holder.playerView
        val p = ExoPlayer.Builder(this).build()
        p.setMediaItem(MediaItem.fromUri(resolveUri(item)))
        p.prepare()
        p.playWhenReady = true
        view.player = p
        player = p
        playerView = view
    }

    private fun resolveUri(item: NativeMediaItem): Uri =
        if (!item.localPath.isNullOrBlank()) Uri.parse(item.localPath) else Uri.parse(item.remoteUrl.orEmpty())

    private fun releasePlayer() {
        playerView?.player = null
        player?.release()
        player = null
        playerView = null
    }

    private fun currentItem() = items.getOrNull(currentIndex)

    private fun updateCounter() {
        if (::counter.isInitialized) counter.text = "${currentIndex + 1} / ${items.size}"
    }

    private fun actionButton(label: String, action: () -> Unit) = Button(this).apply {
        text = label
        setOnClickListener { action() }
        layoutParams = LinearLayout.LayoutParams(0, 64, 1f)
    }

    private fun emitOperation(operation: String) {
        NativeMediaPreviewEvents.emitOperation(operation, currentItem(), currentIndex)
    }

    private fun saveCurrentImage() {
        val item = currentItem() ?: return
        if (item.type == "video" || item.localPath.isNullOrBlank()) return
        val source = java.io.File(item.localPath!!)
        if (!source.exists()) return
        try {
            val values = ContentValues().apply {
                put(MediaStore.Images.Media.DISPLAY_NAME, "ninechat_${System.currentTimeMillis()}.jpg")
                put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    put(MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/NineChat")
                    put(MediaStore.Images.Media.IS_PENDING, 1)
                }
            }
            val uri = contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values) ?: return
            contentResolver.openOutputStream(uri)?.use { out -> source.inputStream().use { it.copyTo(out) } }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val done = ContentValues().apply { put(MediaStore.Images.Media.IS_PENDING, 0) }
                contentResolver.update(uri, done, null, null)
            }
        } catch (_: Exception) { }
    }

    private fun finishPreview(reason: String, messageId: String?, error: String?) {
        if (finished) return
        finished = true
        val result = Intent().apply {
            putExtra("reason", reason)
            putExtra("finalIndex", currentIndex)
            putExtra("messageId", messageId)
            putExtra("playbackPositionMs", player?.currentPosition ?: 0L)
            putExtra("errorCode", error)
        }
        setResult(RESULT_OK, result)
        NativeMediaPreviewEvents.emit(
            mapOf(
                "reason" to reason,
                "finalIndex" to currentIndex,
                "messageId" to messageId,
                "playbackPositionMs" to (player?.currentPosition ?: 0L),
                "errorCode" to error,
            ),
        )
        releasePlayer()
        executor.shutdownNow()
        finish()
    }

    override fun onDestroy() {
        releasePlayer()
        executor.shutdownNow()
        super.onDestroy()
    }

    private inner class MediaPagerAdapter :
        androidx.recyclerview.widget.RecyclerView.Adapter<androidx.recyclerview.widget.RecyclerView.ViewHolder>() {
        override fun getItemCount() = items.size
        override fun getItemViewType(position: Int) = if (items[position].type == "video") 1 else 0
        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): androidx.recyclerview.widget.RecyclerView.ViewHolder {
            // ViewPager2 validates every page root at attach time. Using a
            // plain FrameLayout here lets RecyclerView create wrap-content
            // params on some Android versions, which causes an immediate
            // "Pages must fill the whole ViewPager2" crash.
            val frame = FrameLayout(parent.context).apply {
                setBackgroundColor(android.graphics.Color.BLACK)
                layoutParams = RecyclerView.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT,
                )
            }
            return if (viewType == 1) {
                val view = PlayerView(parent.context).apply { tag = "video:${parent.childCount}"; useController = true }
                frame.addView(view, FrameLayout.LayoutParams(-1, -1))
                VideoHolder(frame, view)
            } else {
                val image = ZoomableImageView(parent.context).apply { setBackgroundColor(android.graphics.Color.BLACK) }
                frame.addView(image, FrameLayout.LayoutParams(-1, -1))
                ImageHolder(frame, image)
            }
        }
        override fun onBindViewHolder(holder: androidx.recyclerview.widget.RecyclerView.ViewHolder, position: Int) {
            val item = items[position]
            if (holder is ImageHolder) loadImage(item, holder.image)
            if (holder is VideoHolder) holder.playerView.tag = "video:$position"
        }
    }

    private class ImageHolder(view: View, val image: ImageView) : androidx.recyclerview.widget.RecyclerView.ViewHolder(view)
    private class VideoHolder(view: View, val playerView: PlayerView) : androidx.recyclerview.widget.RecyclerView.ViewHolder(view)

    private fun loadImage(item: NativeMediaItem, target: ImageView) {
        val path = item.localPath
        if (!path.isNullOrBlank()) {
            target.setImageBitmap(BitmapFactory.decodeFile(path))
            return
        }
        val url = item.remoteUrl ?: return
        executor.execute {
            try {
                val conn = URL(url).openConnection() as HttpURLConnection
                conn.connectTimeout = 10000
                conn.readTimeout = 15000
                val bitmap = conn.inputStream.use { BitmapFactory.decodeStream(it) }
                target.post { target.setImageBitmap(bitmap) }
            } catch (_: Exception) {
                target.post { target.setImageDrawable(null) }
            }
        }
    }

    private fun parseItems(raw: String): List<NativeMediaItem> {
        if (raw.isBlank()) return emptyList()
        val array = JSONArray(raw)
        return (0 until array.length()).map { i ->
            val item = array.getJSONObject(i)
            NativeMediaItem(item.optString("messageId"), item.optString("type"), item.optString("remoteUrl").ifBlank { null }, item.optString("localPath").ifBlank { null }, item.optString("thumbnailUrl").ifBlank { null }, item.optInt("width"), item.optInt("height"), item.optLong("durationMs"))
        }
    }

    companion object {
        const val EXTRA_ITEMS = "native_media_items"
        const val EXTRA_INDEX = "native_media_index"
    }
}
