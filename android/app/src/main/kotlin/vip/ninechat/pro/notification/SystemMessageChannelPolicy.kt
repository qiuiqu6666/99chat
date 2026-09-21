package vip.ninechat.pro.notification

internal object SystemMessageChannelPolicy {
    const val SOUND_VIBRATE = "system_message_sound_vibrate"
    const val SOUND = "system_message_sound"
    const val VIBRATE = "system_message_vibrate"
    const val SILENT = "system_message_silent"

    fun channelId(playSound: Boolean, playVibration: Boolean): String =
        when {
            playSound && playVibration -> SOUND_VIBRATE
            playSound -> SOUND
            playVibration -> VIBRATE
            else -> SILENT
        }
}
