package vip.ninechat.pro.ime

import android.view.WindowManager
import kotlin.math.max

internal object ImeInsetsPolicy {
    fun softInputMode(sdk: Int, current: Int): Int =
        if (sdk < 30) {
            (current and WindowManager.LayoutParams.SOFT_INPUT_MASK_ADJUST.inv()) or
                WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE
        } else current

    fun legacyHeight(
        reportedHeight: Int,
        windowTop: Int,
        windowHeight: Int,
        visibleBottom: Int,
        navigationBottom: Int,
        density: Float,
    ): Int {
        if (reportedHeight > 0) return reportedHeight
        if (windowHeight <= 0 || visibleBottom <= windowTop) return 0
        val covered = (windowTop + windowHeight - visibleBottom).coerceIn(0, windowHeight)
        val threshold = max(navigationBottom + 40f * density, windowHeight * 0.15f)
        return if (covered > threshold) covered else 0
    }
}
