package vip.ninechat.pro.media

data class NativeMediaItem(
    val messageId: String,
    val type: String,
    val remoteUrl: String?,
    val localPath: String?,
    val thumbnailUrl: String?,
    val width: Int,
    val height: Int,
    val durationMs: Long,
)
