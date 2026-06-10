package com.hapticway.hapticway

import android.annotation.SuppressLint
import android.content.Context
import android.media.Image
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLSurface
import android.opengl.GLES11Ext
import android.opengl.GLES20
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.util.DisplayMetrics
import android.view.Surface
import android.view.WindowManager
import com.google.ar.core.ArCoreApk
import com.google.ar.core.Config
import com.google.ar.core.Frame
import com.google.ar.core.Session
import com.google.ar.core.TrackingState
import com.google.ar.core.exceptions.NotYetAvailableException
import com.google.ar.core.exceptions.SessionPausedException
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

/**
 * §6.1 — ARCore depth integration.
 *
 * Owns the back camera exclusively (Flutter camera plugin is not used while
 * this channel is active). Provides:
 *  - MethodChannel "hapticway/depth"  : start() → textureId, stop(), sampleDepth(nx,ny)
 *  - EventChannel  "hapticway/frames" : streams YUV_420_888 maps for TFLite inference
 *
 * Camera preview is delivered via Flutter's ImageConsumer API so the Dart side
 * can display it with a Texture widget. Inference frames travel via EventChannel
 * so the existing background-isolate inference pipeline is unchanged.
 */
class ArDepthChannel(
    private val context: Context,
    flutterEngine: FlutterEngine,
) {
    companion object {
        const val METHOD_CH = "hapticway/depth"
        const val FRAME_CH  = "hapticway/frames"
    }

    private val textureRegistry: TextureRegistry = flutterEngine.renderer
    private val methodCh = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CH)
    private val frameCh  = EventChannel(flutterEngine.dartExecutor.binaryMessenger, FRAME_CH)

    // ARCore
    private var session: Session? = null

    // EGL offscreen context so ARCore can write camera frames to a GL OES texture.
    // ARCore requires a GL texture name even when we don't render a scene.
    private var eglDisplay: EGLDisplay = EGL14.EGL_NO_DISPLAY
    private var eglSurface: EGLSurface = EGL14.EGL_NO_SURFACE
    private var eglCtx: EGLContext     = EGL14.EGL_NO_CONTEXT
    private var cameraTexId = 0

    // Flutter preview texture — ImageTextureEntry is the Flutter 3.10+ API
    // that accepts android.media.Image directly via pushImage().
    private var imageConsumer: TextureRegistry.ImageTextureEntry? = null

    // Inference frame stream
    private var frameSink: EventChannel.EventSink? = null

    // Background thread for ARCore frame loop
    private var loopThread: HandlerThread? = null
    private var loopHandler: Handler? = null
    @Volatile private var running = false

    // Latest cached depth data (depth image is typically 160×90 or 240×180)
    @Volatile private var depthData: ShortArray? = null
    @Volatile private var depthW = 0
    @Volatile private var depthH = 0

    init {
        methodCh.setMethodCallHandler(::handleMethod)
        frameCh.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(args: Any?, sink: EventChannel.EventSink?) { frameSink = sink }
            override fun onCancel(args: Any?) { frameSink = null }
        })
    }

    // ── Method channel dispatch ───────────────────────────────────────────────

    private fun handleMethod(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start"       -> start(result)
            "stop"        -> { stop(); result.success(null) }
            "sampleDepth" -> {
                val nx = (call.argument<Any>("nx") as Number).toFloat()
                val ny = (call.argument<Any>("ny") as Number).toFloat()
                result.success(sampleDepth(nx, ny))
            }
            else -> result.notImplemented()
        }
    }

    // ── Start ─────────────────────────────────────────────────────────────────

    @SuppressLint("MissingPermission")
    private fun start(result: MethodChannel.Result) {
        try {
            val avail = ArCoreApk.getInstance().checkAvailability(context)
            if (avail.isTransient) {
                result.error("AR_TRANSIENT", "ARCore availability check in progress", null); return
            }
            if (avail != ArCoreApk.Availability.SUPPORTED_INSTALLED) {
                result.error("AR_UNAVAILABLE", avail.name, null); return
            }

            // Flutter ImageTextureEntry must be created on the platform thread.
            val ic = textureRegistry.createImageTexture()
            imageConsumer = ic

            // Start the background thread before any EGL/GL work.
            val t = HandlerThread("ar-depth-loop")
            t.start()
            val h = Handler(t.looper)
            loopThread = t
            loopHandler = h

            val mainHandler = Handler(Looper.getMainLooper())

            // EGL context must be created AND made current on the same thread that
            // will call session.update(). Post all GL + ARCore setup to the HandlerThread
            // so eglMakeCurrent() binds the context there, not on the calling thread.
            h.post {
                try {
                    setupEgl()

                    val s = Session(context)
                    s.configure(Config(s).apply {
                        depthMode           = Config.DepthMode.AUTOMATIC
                        updateMode          = Config.UpdateMode.LATEST_CAMERA_IMAGE
                        focusMode           = Config.FocusMode.AUTO
                        lightEstimationMode = Config.LightEstimationMode.DISABLED
                        planeFindingMode    = Config.PlaneFindingMode.DISABLED
                    })
                    s.setCameraTextureName(cameraTexId)
                    s.resume()

                    // ARCore needs valid display geometry to configure its image pipeline.
                    // Without it the CPU image manager logs "invalid width: 0" and may
                    // refuse to acquire camera images.
                    @Suppress("DEPRECATION")
                    val dm = DisplayMetrics().also {
                        (context.getSystemService(Context.WINDOW_SERVICE) as WindowManager)
                            .defaultDisplay.getRealMetrics(it)
                    }
                    s.setDisplayGeometry(Surface.ROTATION_0, dm.widthPixels, dm.heightPixels)

                    session = s
                    running = true

                    // Reply to MethodChannel on the main thread (required by Flutter).
                    mainHandler.post { result.success(ic.id()) }

                    frameLoop()
                } catch (e: Exception) {
                    mainHandler.post {
                        result.error("AR_START_ERROR", "${e.javaClass.simpleName}: ${e.message}", null)
                    }
                }
            }
        } catch (e: Exception) {
            result.error("AR_START_ERROR", "${e.javaClass.simpleName}: ${e.message}", null)
        }
    }

    // ── Frame loop ────────────────────────────────────────────────────────────

    private fun frameLoop() {
        if (!running) return
        val s = session ?: return

        try {
            val frame = s.update()

            // Depth image (may not be available on every frame)
            if (frame.camera.trackingState == TrackingState.TRACKING) {
                try {
                    frame.acquireDepthImage16Bits().use { di ->
                        val buf = di.planes[0].buffer.asShortBuffer()
                        val arr = ShortArray(buf.remaining()).also { buf.get(it) }
                        depthData = arr
                        depthW = di.width
                        depthH = di.height
                    }
                } catch (_: NotYetAvailableException) {
                    // Depth not ready yet — keep previous value
                }
            }

            // Camera image — used for inference only.
            // Images must be closed immediately after the YUV bytes are copied;
            // deferring close() via pushImage() keeps the buffer "outstanding" from
            // ARCore's perspective and exhausts the pool (ResourceExhaustedException).
            val img: Image? = try {
                frame.acquireCameraImage()
            } catch (_: NotYetAvailableException) { null }
              catch (_: com.google.ar.core.exceptions.ResourceExhaustedException) { null }

            if (img != null) {
                img.use { sendInferenceFrame(it) }  // closes img when sendInferenceFrame returns
            }

        } catch (_: SessionPausedException) {
            // App backgrounded — stop the loop; onResume will restart it
            return
        } catch (_: Exception) {
            // Transient error — continue looping
        }

        if (running) loopHandler?.postDelayed(::frameLoop, 33L) // ~30 fps
    }

    // ── Inference frame sending ───────────────────────────────────────────────

    private fun sendInferenceFrame(img: Image) {
        val sink = frameSink ?: return
        val p0 = img.planes[0]; val p1 = img.planes[1]; val p2 = img.planes[2]
        fun readPlane(p: Image.Plane): ByteArray {
            val buf = p.buffer
            return ByteArray(buf.remaining()).also { buf.get(it) }
        }
        sink.success(mapOf(
            "y"             to readPlane(p0),
            "u"             to readPlane(p1),
            "v"             to readPlane(p2),
            "width"         to img.width,
            "height"        to img.height,
            "yRowStride"    to p0.rowStride,
            "uvRowStride"   to p1.rowStride,
            "uvPixelStride" to p1.pixelStride,
        ))
    }

    // ── Depth sampling ────────────────────────────────────────────────────────

    /**
     * Sample depth at a normalised image coordinate (0–1, 0–1).
     * Returns distance in metres, or -1.0 if unavailable / low confidence.
     *
     * ARCore Raw Depth16 encoding:
     *   bits  0-12 : depth in millimetres
     *   bits 13-15 : confidence level (0 = invalid, 7 = highest)
     */
    fun sampleDepth(nx: Float, ny: Float): Double {
        val data = depthData ?: return -1.0
        val px = (nx * depthW).toInt().coerceIn(0, depthW - 1)
        val py = (ny * depthH).toInt().coerceIn(0, depthH - 1)
        val idx = py * depthW + px
        if (idx >= data.size) return -1.0
        val raw  = data[idx].toInt() and 0xFFFF
        val mm   = raw and 0x1FFF
        val conf = (raw ushr 13) and 0x7
        if (conf == 0 || mm == 0) return -1.0
        return mm / 1000.0
    }

    // ── Stop ──────────────────────────────────────────────────────────────────

    fun stop() {
        running = false
        loopHandler?.removeCallbacksAndMessages(null)
        // releaseEgl() calls glDeleteTextures and eglMakeCurrent — must run on the
        // HandlerThread where the EGL context is current. quitSafely() drains the
        // queue (including this post) before stopping the thread.
        loopHandler?.post { releaseEgl() }
        loopThread?.quitSafely()
        loopThread?.join(1000)
        loopThread = null; loopHandler = null
        session?.pause(); session?.close(); session = null
        imageConsumer?.release(); imageConsumer = null
        depthData = null
    }

    // ── EGL helpers ───────────────────────────────────────────────────────────

    private fun setupEgl() {
        eglDisplay = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
        check(eglDisplay != EGL14.EGL_NO_DISPLAY) { "eglGetDisplay failed" }
        val ver = IntArray(2)
        EGL14.eglInitialize(eglDisplay, ver, 0, ver, 1)

        val cfgAttribs = intArrayOf(
            EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
            EGL14.EGL_SURFACE_TYPE,    EGL14.EGL_PBUFFER_BIT,
            EGL14.EGL_NONE,
        )
        val configs = arrayOfNulls<EGLConfig>(1)
        val nCfg = IntArray(1)
        EGL14.eglChooseConfig(eglDisplay, cfgAttribs, 0, configs, 0, 1, nCfg, 0)
        check(nCfg[0] > 0) { "No suitable EGL config found" }

        val ctxAttribs = intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE)
        eglCtx = EGL14.eglCreateContext(eglDisplay, configs[0], EGL14.EGL_NO_CONTEXT, ctxAttribs, 0)

        val pbuf = intArrayOf(EGL14.EGL_WIDTH, 1, EGL14.EGL_HEIGHT, 1, EGL14.EGL_NONE)
        eglSurface = EGL14.eglCreatePbufferSurface(eglDisplay, configs[0], pbuf, 0)
        EGL14.eglMakeCurrent(eglDisplay, eglSurface, eglSurface, eglCtx)

        // Camera OES texture that ARCore writes captured frames into
        val tex = IntArray(1)
        GLES20.glGenTextures(1, tex, 0)
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, tex[0])
        cameraTexId = tex[0]
    }

    private fun releaseEgl() {
        if (eglDisplay == EGL14.EGL_NO_DISPLAY) return
        EGL14.eglMakeCurrent(eglDisplay, eglSurface, eglSurface, eglCtx)
        if (cameraTexId != 0) {
            GLES20.glDeleteTextures(1, intArrayOf(cameraTexId), 0)
            cameraTexId = 0
        }
        EGL14.eglMakeCurrent(eglDisplay, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT)
        EGL14.eglDestroySurface(eglDisplay, eglSurface)
        EGL14.eglDestroyContext(eglDisplay, eglCtx)
        EGL14.eglTerminate(eglDisplay)
        eglDisplay = EGL14.EGL_NO_DISPLAY
        eglSurface = EGL14.EGL_NO_SURFACE
        eglCtx     = EGL14.EGL_NO_CONTEXT
    }
}
