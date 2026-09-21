package record.wilson.flutter.com.flutter_plugin_record

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.util.Log
import cafe.adriel.androidaudioconverter.AndroidAudioConverter
import cafe.adriel.androidaudioconverter.callback.IConvertCallback
import cafe.adriel.androidaudioconverter.callback.ILoadCallback
import cafe.adriel.androidaudioconverter.model.AudioFormat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry
import record.wilson.flutter.com.flutter_plugin_record.utils.*
import java.io.File
import java.util.*


class FlutterPluginRecordPlugin : FlutterPlugin, MethodCallHandler, ActivityAware ,PluginRegistry.RequestPermissionsResultListener {

    lateinit var channel: MethodChannel
    private lateinit var call: MethodCall
    private lateinit var voicePlayPath: String
    private var recorderUtil: RecorderUtil? = null
    private var recordMp3:Boolean=false;

    @Volatile
    private var audioHandler: AudioHandler? = null
    @Volatile
    private var activeRecordSessionId: String? = null

    var activity:Activity? = null

    companion object {
//        //support embedding v1
//        @JvmStatic
//        fun registerWith(registrar: Registrar) {
//            val plugin = initPlugin(registrar.messenger())
//            plugin.activity= registrar.activity()
//            registrar.addRequestPermissionsResultListener(plugin)
//        }

        private fun initPlugin(binaryMessenger: BinaryMessenger):FlutterPluginRecordPlugin {
            val channel = createMethodChannel(binaryMessenger)
            val plugin = FlutterPluginRecordPlugin()
            channel.setMethodCallHandler(plugin)
            plugin.channel = channel
            return plugin
        }

        private fun createMethodChannel(binaryMessenger: BinaryMessenger):MethodChannel{
            return  MethodChannel(binaryMessenger, "flutter_plugin_record");
        }
    }
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
       val methodChannel = createMethodChannel(binding.binaryMessenger)
        methodChannel.setMethodCallHandler(this)
        channel=methodChannel
    }



    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        initActivityBinding(binding)
    }

    private fun initActivityBinding(binding: ActivityPluginBinding) {
        binding.addRequestPermissionsResultListener(this)
        activity=binding.activity
    }


    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        initActivityBinding(binding)
    }

    override fun onDetachedFromActivityForConfigChanges() {
    }
    override fun onDetachedFromActivity() {
    }


    override  fun onMethodCall(call: MethodCall, result: Result) {
        this.call = call
        when (call.method) {
            "init" -> { init(); result.success(null) }
            "initRecordMp3" -> { initRecordMp3(); result.success(null) }
            "start" -> { start(); result.success(null) }
            "startByWavPath" -> { startByWavPath(); result.success(null) }
            "stop" -> { stop(); result.success(null) }
            "play" -> { play(); result.success(null) }
            "pause" -> { pause(); result.success(null) }
            "playByPath" -> { playByPath(); result.success(null) }
            "stopPlay" -> { stopPlay(); result.success(null) }
            else -> result.notImplemented()
        }
    }



    //初始化wav转 MP3
    private fun initWavToMp3(){
        AndroidAudioConverter.load(activity?.applicationContext, object : ILoadCallback {
            override fun onSuccess() {
                // Great!
                Log.d("android", "  AndroidAudioConverter onSuccess")
            }

            override fun onFailure(error: Exception) {
                // FFmpeg is not supported by device
                Log.d("android", "  AndroidAudioConverter onFailure")
            }
        })

    }

    private fun initRecord() {
        if (audioHandler != null) {
            audioHandler?.release()
            audioHandler = null
        }
        audioHandler = AudioHandler.createHandler(AudioHandler.Frequency.F_22050)

        Log.d("android voice  ", "init")
        val id = call.argument<String>("id")
        val m1 = HashMap<String, String>()
        m1["id"] = id!!
        m1["result"] = "success"
        channel.invokeMethod("onInit", m1)

    }

    private fun stopPlay() {
        recorderUtil?.stopPlay()
    }
    //暂停播放
    private fun pause() {
        val isPlaying= recorderUtil?.pausePlay()
        val _id = call.argument<String>("id")
        val m1 = HashMap<String, String>()
        m1["id"] = _id!!
        m1["result"] = "success"
        m1["isPlaying"] = isPlaying.toString()
        channel.invokeMethod("pausePlay", m1)
    }

    private fun play() {

        recorderUtil = RecorderUtil(voicePlayPath)
        recorderUtil!!.addPlayStateListener { playState ->
            print(playState)
            val _id = call.argument<String>("id")
            val m1 = HashMap<String, String>()
            m1["id"] = _id!!
            m1["playPath"] = voicePlayPath
            m1["playState"] = playState.toString()
            channel.invokeMethod("onPlayState", m1)
        }
        recorderUtil!!.playVoice()
        Log.d("android voice  ", "play")
        val _id = call.argument<String>("id")
        val m1 = HashMap<String, String>()
        m1["id"] = _id!!
        channel.invokeMethod("onPlay", m1)
    }

    private fun playByPath() {
        val path = call.argument<String>("path")
        recorderUtil = RecorderUtil(path)
        recorderUtil!!.addPlayStateListener { playState ->
            val _id = call.argument<String>("id")
            val m1 = HashMap<String, String>()
            m1["id"] = _id!!
            m1["playPath"] = path.toString();
            m1["playState"] = playState.toString()
            channel.invokeMethod("onPlayState", m1)
        }
        recorderUtil!!.playVoice()

        Log.d("android voice  ", "play")
        val _id = call.argument<String>("id")
        val m1 = HashMap<String, String>()
        m1["id"] = _id!!
        channel.invokeMethod("onPlay", m1)
    }

    @Synchronized
    private fun stop() {
        val requestedSessionId = call.argument<String>("sessionId") ?: ""
        if (activeRecordSessionId == requestedSessionId &&
                audioHandler?.isRecording == true) {
            audioHandler?.stopRecord()
        }
        Log.d("android voice  ", "stop")
    }

    @Synchronized
    private fun start() {
        var packageManager = activity?.packageManager
        var packageName = activity?.packageName ?: ""
        var permission = PackageManager.PERMISSION_GRANTED == packageManager?.checkPermission(Manifest.permission.RECORD_AUDIO, packageName)
        if (permission) {
            val requestId = call.argument<String>("id") ?: return
            val sessionId = call.argument<String>("sessionId") ?: ""
            if (activeRecordSessionId != null || audioHandler?.isRecording == true) {
                notifyRecordFailed("record_busy", requestId, sessionId, false)
                return
            }
            if(audioHandler == null) {
                initRecord();
            }
            Log.d("android voice  ", "start")
            activeRecordSessionId = sessionId
            audioHandler?.startRecord(MessageRecordListener(requestId, sessionId))
        } else {
            notifyStartFailed("permission_denied")
        }

    }

    @Synchronized
    private fun startByWavPath() {
        var packageManager = activity?.packageManager
        var packageName = activity?.packageName ?: ""
        var permission = PackageManager.PERMISSION_GRANTED == packageManager?.checkPermission(Manifest.permission.RECORD_AUDIO, packageName)
        if (permission) {
            Log.d("android voice  ", "start")
            val requestId = call.argument<String>("id") ?: return
            val sessionId = call.argument<String>("sessionId") ?: ""
            val wavPath = call.argument<String>("wavPath")
            if (wavPath.isNullOrBlank()) {
                notifyRecordFailed("invalid_record_path", requestId, sessionId, false)
                return
            }
            if (activeRecordSessionId != null || audioHandler?.isRecording == true) {
                notifyRecordFailed("record_busy", requestId, sessionId, false)
                return
            }
            if (audioHandler == null) {
                initRecord()
            }
            activeRecordSessionId = sessionId
            audioHandler?.startRecord(
                    MessageRecordListenerByPath(wavPath, requestId, sessionId))
        } else {
            notifyStartFailed("permission_denied")
        }

    }

    private fun notifyStartFailed(reason: String) {
        Log.w("FlutterPluginRecord", "start blocked: $reason")
        notifyRecordFailed(
                reason,
                call.argument<String>("id") ?: "",
                call.argument<String>("sessionId") ?: "",
                false)
    }

    private fun notifyRecordFailed(
            reason: String,
            requestId: String,
            sessionId: String,
            releaseSession: Boolean = true) {
        Log.e("FlutterPluginRecord", "record failed: $reason")
        val payload = HashMap<String, String>()
        payload["id"] = requestId
        payload["sessionId"] = sessionId
        payload["result"] = reason
        activity?.runOnUiThread {
            channel.invokeMethod("onRecordFail", payload)
            if (releaseSession && activeRecordSessionId == sessionId) {
                activeRecordSessionId = null
            }
        }
    }

    private fun notifyRecordStarted(requestId: String, sessionId: String) {
        if (activeRecordSessionId != sessionId) return
        val payload = HashMap<String, String>()
        payload["id"] = requestId
        payload["sessionId"] = sessionId
        payload["result"] = "success"
        activity?.runOnUiThread { channel.invokeMethod("onStart", payload) }
    }

    private fun notifyRecordStopped(
            recordFile: File,
            audioTime: Double,
            requestId: String,
            sessionId: String) {
        if (activeRecordSessionId != sessionId) return
        val payload = HashMap<String, String>()
        payload["id"] = requestId
        payload["sessionId"] = sessionId
        payload["voicePath"] = recordFile.path
        payload["audioTimeLength"] = audioTime.toString()
        payload["result"] = "success"
        activity?.runOnUiThread {
            channel.invokeMethod("onStop", payload)
            if (activeRecordSessionId == sessionId) {
                activeRecordSessionId = null
            }
        }
    }

    private fun isValidAudioFile(file: File?): Boolean {
        return file != null && file.exists() && file.canRead() && file.length() > 44L
    }


    private fun init() {
        recordMp3=false
    }
    private fun initRecordMp3(){
        recordMp3=true
        if (hasRecordAudioPermission()) {
            initRecord()
        }
        initWavToMp3()
    }

    private fun hasRecordAudioPermission(): Boolean {
        val packageManager = activity?.packageManager ?: return false
        val packageName = activity?.packageName ?: return false
        return PackageManager.PERMISSION_GRANTED == packageManager.checkPermission(
            Manifest.permission.RECORD_AUDIO,
            packageName
        )
    }


    //自定义路径
    private inner class MessageRecordListenerByPath(
            private val wavPath: String,
            private val requestId: String,
            private val sessionId: String) : AudioHandler.RecordListener {
        override fun onStop(recordFile: File?, audioTime: Double?) {
            if (!isValidAudioFile(recordFile) || audioTime == null || audioTime <= 0.0) {
                notifyRecordFailed("invalid_recording", requestId, sessionId)
                return
            }
            if (recordFile != null) {
                voicePlayPath = recordFile.path
                if (recordMp3){

                    val callback: IConvertCallback = object : IConvertCallback {
                        override fun onSuccess(convertedFile: File) {

                            if (!isValidAudioFile(convertedFile)) {
                                notifyRecordFailed("invalid_converted_audio", requestId, sessionId)
                                return
                            }

                            Log.d("android", "  ConvertCallback ${convertedFile.path}")

                            notifyRecordStopped(convertedFile, audioTime, requestId, sessionId)
                        }

                        override fun onFailure(error: java.lang.Exception) {
                            Log.d("android", "  ConvertCallback $error")
                            notifyRecordFailed("audio_conversion_failed", requestId, sessionId)
                        }
                    }
                    AndroidAudioConverter.with(activity?.applicationContext)
                            .setFile(recordFile)
                            .setFormat(AudioFormat.MP3)
                            .setCallback(callback)
                            .convert()

                }else{
                    notifyRecordStopped(recordFile, audioTime, requestId, sessionId)

                }
            }

        }


        override fun getFilePath(): String {
            return wavPath;
        }

        private val fileName: String
        private val cacheDirectory: File


        init {
            cacheDirectory = FileTool.getIndividualAudioCacheDirectory(activity)
            fileName = UUID.randomUUID().toString()
        }

        override fun onStart() {
            LogUtils.LOGE("MessageRecordListener onStart on start record")
            notifyRecordStarted(requestId, sessionId)
        }

        override fun onVolume(db: Double) {
            LogUtils.LOGE("MessageRecordListener onVolume " + db / 100)
            if (activeRecordSessionId != sessionId) return
            val m1 = HashMap<String, Any>()
            m1["id"] = requestId
            m1["sessionId"] = sessionId
            m1["amplitude"] = db / 100
            m1["result"] = "success"

            activity?.runOnUiThread { channel.invokeMethod("onAmplitude", m1) }


        }

        override fun onError(error: Int) {
            LogUtils.LOGE("MessageRecordListener onError $error")
            notifyRecordFailed("record_error_$error", requestId, sessionId)
        }
    }


    private inner class MessageRecordListener(
            private val requestId: String,
            private val sessionId: String) : AudioHandler.RecordListener {
        override fun onStop(recordFile: File?, audioTime: Double?) {
            LogUtils.LOGE("MessageRecordListener onStop $recordFile")
            if (!isValidAudioFile(recordFile) || audioTime == null || audioTime <= 0.0) {
                notifyRecordFailed("invalid_recording", requestId, sessionId)
                return
            }
            if (recordFile != null) {
                voicePlayPath = recordFile.path
                if (recordMp3){
                    val callback: IConvertCallback = object : IConvertCallback {
                        override fun onSuccess(convertedFile: File) {

                            if (!isValidAudioFile(convertedFile)) {
                                notifyRecordFailed("invalid_converted_audio", requestId, sessionId)
                                return
                            }

                            Log.d("android", "  ConvertCallback ${convertedFile.path}")

                            notifyRecordStopped(convertedFile, audioTime, requestId, sessionId)
                        }

                        override fun onFailure(error: java.lang.Exception) {
                            Log.d("android", "  ConvertCallback $error")
                            notifyRecordFailed("audio_conversion_failed", requestId, sessionId)
                        }
                    }
                    AndroidAudioConverter.with(activity?.applicationContext)
                            .setFile(recordFile)
                            .setFormat(AudioFormat.MP3)
                            .setCallback(callback)
                            .convert()

                }else{
                    notifyRecordStopped(recordFile, audioTime, requestId, sessionId)

                }
            }

        }


        override fun getFilePath(): String {
            val file = File(cacheDirectory, fileName)
            return file.absolutePath
        }

        private val fileName: String
        private val cacheDirectory: File


        init {
            cacheDirectory = FileTool.getIndividualAudioCacheDirectory(activity)
            fileName = UUID.randomUUID().toString()
        }

        override fun onStart() {
            LogUtils.LOGE("MessageRecordListener onStart on start record")
            notifyRecordStarted(requestId, sessionId)
        }

        override fun onVolume(db: Double) {
            LogUtils.LOGE("MessageRecordListener onVolume " + db / 100)
            if (activeRecordSessionId != sessionId) return
            val m1 = HashMap<String, Any>()
            m1["id"] = requestId
            m1["sessionId"] = sessionId
            m1["amplitude"] = db / 100
            m1["result"] = "success"

            activity?.runOnUiThread { channel.invokeMethod("onAmplitude", m1) }


        }

        override fun onError(error: Int) {
            LogUtils.LOGE("MessageRecordListener onError $error")
            notifyRecordFailed("record_error_$error", requestId, sessionId)
        }
    }




    // 权限监听回调
    override fun onRequestPermissionsResult(p0: Int, p1: Array<out String>, p2: IntArray): Boolean {
        if (p0 == 1) {
            if (p2?.get(0) == PackageManager.PERMISSION_GRANTED) {
//                initRecord()
                return true
            } else {
                Log.w("FlutterPluginRecord", "RECORD_AUDIO permission denied")
            }
            return false
        }

        return false
    }

    

}
