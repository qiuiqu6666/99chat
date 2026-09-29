package vip.ninechat.pro.ime

import android.view.WindowManager.LayoutParams
import org.junit.Assert.assertEquals
import org.junit.Test

class ImeInsetsPolicyTest {
    @Test fun legacyWindowRequestsResizeAndPreservesStateFlags() {
        val flags = LayoutParams.SOFT_INPUT_STATE_ALWAYS_HIDDEN or LayoutParams.SOFT_INPUT_ADJUST_NOTHING
        assertEquals(LayoutParams.SOFT_INPUT_STATE_ALWAYS_HIDDEN or LayoutParams.SOFT_INPUT_ADJUST_RESIZE,
            ImeInsetsPolicy.softInputMode(29, flags))
        assertEquals(flags, ImeInsetsPolicy.softInputMode(30, flags))
        assertEquals(flags, ImeInsetsPolicy.softInputMode(36, flags))
    }

    @Test fun visibleFrameRecoversMissingLegacyInsets() {
        assertEquals(600, ImeInsetsPolicy.legacyHeight(0, 60, 1800, 1260, 90, 3f))
    }

    @Test fun systemBarsAndClosedKeyboardDoNotCreateASpacer() {
        assertEquals(0, ImeInsetsPolicy.legacyHeight(0, 60, 1800, 1770, 90, 3f))
        assertEquals(0, ImeInsetsPolicy.legacyHeight(0, 60, 1800, 1860, 90, 3f))
    }

    @Test fun invalidOrUnlaidOutFramesDoNotCreateAKeyboard() {
        assertEquals(0, ImeInsetsPolicy.legacyHeight(0, 60, 1800, 0, 90, 3f))
        assertEquals(0, ImeInsetsPolicy.legacyHeight(0, 60, 0, 1260, 90, 3f))
    }

    @Test fun platformHeightTakesPriorityOverGeometry() {
        assertEquals(450, ImeInsetsPolicy.legacyHeight(450, 60, 1800, 1260, 90, 3f))
    }
}
