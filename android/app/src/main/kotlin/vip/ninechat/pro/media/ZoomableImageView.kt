package vip.ninechat.pro.media

import android.content.Context
import android.graphics.Matrix
import android.util.AttributeSet
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import android.widget.ImageView
import kotlin.math.max
import kotlin.math.min

/** 原生媒体预览图片：双击、双指缩放和放大后拖动。 */
class ZoomableImageView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
) : ImageView(context, attrs) {
    private val matrixValues = FloatArray(9)
    private var scale = 1f
    private val matrixState = Matrix()
    private val scaleDetector = ScaleGestureDetector(context, object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
        override fun onScale(detector: ScaleGestureDetector): Boolean {
            val next = (scale * detector.scaleFactor).coerceIn(1f, 4f)
            val factor = next / scale
            scale = next
            matrixState.postScale(factor, factor, detector.focusX, detector.focusY)
            imageMatrix = matrixState
            return true
        }
    })
    private val gestureDetector = GestureDetector(context, object : GestureDetector.SimpleOnGestureListener() {
        override fun onDoubleTap(event: MotionEvent): Boolean {
            val target = if (scale > 1.05f) 1f else 2.5f
            val factor = target / scale
            scale = target
            matrixState.postScale(factor, factor, event.x, event.y)
            imageMatrix = matrixState
            return true
        }
        override fun onDown(event: MotionEvent): Boolean = true
        override fun onScroll(
            first: MotionEvent?,
            current: MotionEvent,
            distanceX: Float,
            distanceY: Float,
        ): Boolean {
            if (scale <= 1.05f) return false
            matrixState.postTranslate(-distanceX, -distanceY)
            imageMatrix = matrixState
            return true
        }
    })

    init {
        scaleType = ScaleType.MATRIX
        imageMatrix = matrixState
        isClickable = true
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        configureBaseMatrix()
    }

    override fun setImageDrawable(drawable: android.graphics.drawable.Drawable?) {
        super.setImageDrawable(drawable)
        post { configureBaseMatrix() }
    }

    private fun configureBaseMatrix() {
        val drawable = drawable ?: return
        if (width <= 0 || height <= 0 || drawable.intrinsicWidth <= 0 || drawable.intrinsicHeight <= 0) return
        val sx = width.toFloat() / drawable.intrinsicWidth.toFloat()
        val sy = height.toFloat() / drawable.intrinsicHeight.toFloat()
        val fit = min(sx, sy)
        matrixState.reset()
        matrixState.setScale(fit, fit)
        val renderedW = drawable.intrinsicWidth * fit
        val renderedH = drawable.intrinsicHeight * fit
        matrixState.postTranslate((width - renderedW) / 2f, (height - renderedH) / 2f)
        scale = 1f
        imageMatrix = matrixState
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        scaleDetector.onTouchEvent(event)
        gestureDetector.onTouchEvent(event)
        return true
    }

    override fun setImageMatrix(matrix: Matrix?) {
        super.setImageMatrix(matrix ?: Matrix())
    }

    fun resetZoom() {
        scale = 1f
        matrixState.reset()
        imageMatrix = matrixState
    }
}
