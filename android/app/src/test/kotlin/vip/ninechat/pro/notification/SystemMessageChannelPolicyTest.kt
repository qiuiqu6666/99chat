package vip.ninechat.pro.notification

import org.junit.Assert.assertEquals
import org.junit.Test

class SystemMessageChannelPolicyTest {
    @Test
    fun soundAndVibrationUseCombinedChannel() {
        assertEquals(
            "system_message_sound_vibrate",
            SystemMessageChannelPolicy.channelId(true, true),
        )
    }

    @Test
    fun soundOnlyUsesSoundChannel() {
        assertEquals(
            "system_message_sound",
            SystemMessageChannelPolicy.channelId(true, false),
        )
    }

    @Test
    fun vibrationOnlyUsesVibrateChannel() {
        assertEquals(
            "system_message_vibrate",
            SystemMessageChannelPolicy.channelId(false, true),
        )
    }

    @Test
    fun silentUsesSilentChannel() {
        assertEquals(
            "system_message_silent",
            SystemMessageChannelPolicy.channelId(false, false),
        )
    }
}
