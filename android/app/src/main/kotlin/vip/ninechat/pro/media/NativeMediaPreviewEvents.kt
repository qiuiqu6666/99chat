package vip.ninechat.pro.media

import io.flutter.plugin.common.EventChannel

object NativeMediaPreviewEvents {
    var sink: EventChannel.EventSink? = null

    fun emit(result: Map<String, Any?>) {
        sink?.success(result)
    }

    fun emitOperation(operation: String, item: NativeMediaItem?, index: Int) {
        emit(mapOf("reason" to "operation", "operation" to operation,
            "messageId" to item?.messageId, "finalIndex" to index))
    }
}
