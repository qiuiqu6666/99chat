package vip.ninechat.pro.ime

import android.app.Activity
import android.graphics.Rect
import android.os.Build
import android.view.View
import android.view.ViewTreeObserver
import android.view.Window
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsAnimationCompat
import androidx.core.view.WindowInsetsCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class AndroidImeInsetsPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler,
    ActivityAware {
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var activity: Activity? = null
    private var eventSink: EventChannel.EventSink? = null
    private var attachedView: View? = null
    private var attachedWindow: Window? = null
    private var originalSoftInputMode: Int? = null
    private val layoutListener = ViewTreeObserver.OnGlobalLayoutListener { emit() }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel = MethodChannel(binding.binaryMessenger, "ninechat/ime_insets")
        methodChannel.setMethodCallHandler(this)
        eventChannel = EventChannel(binding.binaryMessenger, "ninechat/ime_insets_events")
        eventChannel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "get") {
            result.success(currentPayload())
        } else {
            result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        emit()
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        attachToDecorView()
    }

    override fun onDetachedFromActivityForConfigChanges() {
        detachFromDecorView()
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        attachToDecorView()
    }

    override fun onDetachedFromActivity() {
        detachFromDecorView()
        activity = null
    }

    private fun attachToDecorView() {
        detachFromDecorView()
        val window = activity?.window ?: return
        val view = window.decorView
        attachedWindow = window
        originalSoftInputMode = window.attributes.softInputMode
        // Pre-R IME insets need resize notifications even though Flutter itself
        // lays out edge-to-edge and owns the input bar's bottom spacer.
        window.setSoftInputMode(ImeInsetsPolicy.softInputMode(
            Build.VERSION.SDK_INT, window.attributes.softInputMode,
        ))
        attachedView = view
        ViewCompat.setOnApplyWindowInsetsListener(view) { _, insets ->
            emit(insets)
            insets
        }
        ViewCompat.setWindowInsetsAnimationCallback(
            view,
            object : WindowInsetsAnimationCompat.Callback(
                DISPATCH_MODE_CONTINUE_ON_SUBTREE,
            ) {
                override fun onProgress(
                    insets: WindowInsetsCompat,
                    runningAnimations: MutableList<WindowInsetsAnimationCompat>,
                ): WindowInsetsCompat {
                    emit(insets)
                    return insets
                }

                override fun onEnd(animation: WindowInsetsAnimationCompat) {
                    emit()
                }
            },
        )
        if (Build.VERSION.SDK_INT < 30) {
            view.viewTreeObserver.addOnGlobalLayoutListener(layoutListener)
        }
        ViewCompat.requestApplyInsets(view)
        emit()
    }

    private fun detachFromDecorView() {
        val view = attachedView ?: return
        ViewCompat.setOnApplyWindowInsetsListener(view, null)
        ViewCompat.setWindowInsetsAnimationCallback(view, null)
        if (view.viewTreeObserver.isAlive) {
            view.viewTreeObserver.removeOnGlobalLayoutListener(layoutListener)
        }
        originalSoftInputMode?.let { mode ->
            val window = attachedWindow
            if (window?.attributes?.softInputMode ==
                ImeInsetsPolicy.softInputMode(Build.VERSION.SDK_INT, mode)) {
                window.setSoftInputMode(mode)
            }
        }
        originalSoftInputMode = null
        attachedWindow = null
        attachedView = null
    }

    private fun currentPayload(eventInsets: WindowInsetsCompat? = null): Map<String, Any> {
        val view = attachedView ?: activity?.window?.decorView
        if (view == null) {
            return mapOf(
                "visible" to false,
                "imeHeight" to 0.0,
                "device" to Build.MODEL,
            )
        }
        val density = view.resources.displayMetrics.density.let { if (it == 0f) 1f else it }
        val insets = eventInsets ?: ViewCompat.getRootWindowInsets(view)
        val reportedHeight = insets?.getInsets(WindowInsetsCompat.Type.ime())?.bottom ?: 0
        var heightPx = reportedHeight
        if (Build.VERSION.SDK_INT < 30 && reportedHeight == 0) {
            val frame = Rect()
            val location = IntArray(2)
            view.getWindowVisibleDisplayFrame(frame)
            view.getLocationOnScreen(location)
            // Independent legacy fallback. Coordinates are window-relative;
            // status/navigation bars alone must never be mistaken for an IME.
            heightPx = ImeInsetsPolicy.legacyHeight(
                reportedHeight, location[1], view.height, frame.bottom,
                insets?.getInsets(WindowInsetsCompat.Type.navigationBars())?.bottom ?: 0,
                density,
            )
        }
        return mapOf(
            "visible" to (insets?.isVisible(WindowInsetsCompat.Type.ime()) == true ||
                heightPx / density > 40.0),
            "imeHeight" to heightPx / density.toDouble(),
            "device" to Build.MODEL,
            "sdk" to Build.VERSION.SDK_INT,
        )
    }

    private fun emit(insets: WindowInsetsCompat? = null) {
        eventSink?.success(currentPayload(insets))
    }
}
