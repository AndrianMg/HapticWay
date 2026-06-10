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
import com.google.ar.core.Session
import com.google.ar.core.TrackingState
import com.google.ar.core.exceptions.NotYetAvailableException
import com.google.ar.core.exceptions.ResourceExhaustedException
import com.google.ar.core.exceptions.SessionPausedException
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer

/**
 * §6.1 — ARCore depth integration.
 *
 * Camera preview: ARCore writes each frame into an OES texture (cameraTexId)
 * during session.update(). We render that OES texture to a Flutter
 * SurfaceTextureEntry via a minimal GLES2 shader, which Flutter composites in
 * the Texture widget. Camera images (acquireCameraImage) are closed immediately
 * after the YUV bytes are copied for inference — never held open — to keep
 * ARCore's CPU image buffer pool from exhausting.
 *
 * EGL/GL work runs entirely on HandlerThread("ar-depth-loop") so that the EGL
 * context is always current on the thread that calls session.update().
 */
class ArDepthChannel(
    private val context: Context,
    flutterEngine: FlutterEngine,
) {
    companion object {
        const val METHOD_CH = "hapticway/depth"
        const val FRAME_CH  = "hapticway/frames"

        // Minimal OES texture pass-through shaders.
        private const val VERT_SRC = """
            attribute vec2 aPos;
            attribute vec2 aUV;
            varying   vec2 vUV;
            void main() { gl_Position = vec4(aPos, 0.0, 1.0); vUV = aUV; }
        """
        private const val FRAG_SRC = """
            #extension GL_OES_EGL_image_external : require
            precision mediump float;
            uniform samplerExternalOES uTex;
            varying vec2 vUV;
            void main() { gl_FragColor = texture2D(uTex, vUV); }
        """

        // Fullscreen triangle-strip quad.
        // Texture coords rotate 90° CW to match portrait display / landscape sensor.
        // Layout per vertex: posX, posY, uvX, uvY
        private val QUAD = floatArrayOf(
            -1f, -1f,  0f, 1f,
             1f, -1f,  0f, 0f,
            -1f,  1f,  1f, 1f,
             1f,  1f,  1f, 0f,
        )
    }

    private val textureRegistry: TextureRegistry = flutterEngine.renderer
    private val methodCh = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CH)
    private val frameCh  = EventChannel(flutterEngine.dartExecutor.binaryMessenger, FRAME_CH)

    // ARCore
    private var session: Session? = null

    // EGL
    private var eglDisplay: EGLDisplay = EGL14.EGL_NO_DISPLAY
    private var eglPbuffer: EGLSurface = EGL14.EGL_NO_SURFACE  // 1×1 min surface for session.update()
    private var eglPreview: EGLSurface = EGL14.EGL_NO_SURFACE  // window surface → Flutter SurfaceTexture
    private var eglCtx: EGLContext     = EGL14.EGL_NO_CONTEXT
    private var cameraTexId = 0                                 // OES texture ARCore writes into

    // GL preview shader
    private var glProgram   = 0
    private var aPos        = 0
    private var aUV         = 0
    private var uTex        = 0
    private var quadBuf: FloatBuffer? = null

    // Flutter SurfaceTextureEntry that backs the Texture widget
    private var previewEntry: TextureRegistry.SurfaceTextureEntry? = null
    private var previewW = 0
    private var previewH = 0

    // EventChannel sink for YUV inference frames
    private var frameSink: EventChannel.EventSink? = null

    // Background thread for ARCore frame loop
    private var loopThread: HandlerThread? = null
    private var loopHandler: Handler? = null
    @Volatile private var running = false

    // Latest cached depth image data
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

            // Screen metrics — needed to size the EGL window surface.
            @Suppress("DEPRECATION")
            val dm = DisplayMetrics().also {
                (context.getSystemService(Context.WINDOW_SERVICE) as WindowManager)
                    .defaultDisplay.getRealMetrics(it)
            }
            previewW = dm.widthPixels
            previewH = dm.heightPixels

            // SurfaceTextureEntry: Flutter's consumer for the preview.
            // Must be created on the platform thread.
            val entry = textureRegistry.createSurfaceTexture()
            previewEntry = entry

            val t = HandlerThread("ar-depth-loop")
            t.start()
            val h = Handler(t.looper)
            loopThread = t
            loopHandler = h

            val mainHandler = Handler(Looper.getMainLooper())

            // All EGL/GL and ARCore setup must run on the HandlerThread so that the
            // EGL context is current on the thread that calls session.update().
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
                    s.setDisplayGeometry(Surface.ROTATION_0, previewW, previewH)
                    session = s
                    running = true

                    mainHandler.post { result.success(entry.id()) }
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
            val frame = s.update()  // ARCore writes latest camera frame into cameraTexId OES texture

            // Blit OES texture → EGL window surface → Flutter SurfaceTexture → Texture widget
            renderPreview()

            // Depth (only available while ARCore is tracking the environment)
            if (frame.camera.trackingState == TrackingState.TRACKING) {
                try {
                    frame.acquireDepthImage16Bits().use { di ->
                        val buf = di.planes[0].buffer.asShortBuffer()
                        val arr = ShortArray(buf.remaining()).also { buf.get(it) }
                        depthData = arr
                        depthW = di.width
                        depthH = di.height
                    }
                } catch (_: NotYetAvailableException) {}
            }

            // YUV camera image for TFLite inference.
            // Close immediately after copying bytes — holding the image open starves
            // ARCore's CPU image buffer pool (ResourceExhaustedException).
            val img = try {
                frame.acquireCameraImage()
            } catch (_: NotYetAvailableException) { null }
              catch (_: ResourceExhaustedException)  { null }

            img?.use { sendInferenceFrame(it) }

        } catch (_: SessionPausedException) { return }
          catch (_: Exception) {}

        if (running) loopHandler?.postDelayed(::frameLoop, 33L)
    }

    // ── Preview rendering ─────────────────────────────────────────────────────

    private fun renderPreview() {
        if (eglPreview == EGL14.EGL_NO_SURFACE || glProgram == 0) return

        EGL14.eglMakeCurrent(eglDisplay, eglPreview, eglPreview, eglCtx)

        GLES20.glViewport(0, 0, previewW, previewH)
        GLES20.glUseProgram(glProgram)

        val buf = quadBuf!!
        val stride = 4 * 4   // 4 floats × 4 bytes per vertex
        buf.position(0)
        GLES20.glVertexAttribPointer(aPos, 2, GLES20.GL_FLOAT, false, stride, buf)
        GLES20.glEnableVertexAttribArray(aPos)
        buf.position(2)
        GLES20.glVertexAttribPointer(aUV, 2, GLES20.GL_FLOAT, false, stride, buf)
        GLES20.glEnableVertexAttribArray(aUV)

        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, cameraTexId)
        GLES20.glUniform1i(uTex, 0)

        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)

        GLES20.glDisableVertexAttribArray(aPos)
        GLES20.glDisableVertexAttribArray(aUV)

        EGL14.eglSwapBuffers(eglDisplay, eglPreview)

        // Restore pbuffer as current surface for session.update() on the next frame
        EGL14.eglMakeCurrent(eglDisplay, eglPbuffer, eglPbuffer, eglCtx)
    }

    // ── Inference frame sending ───────────────────────────────────────────────

    private fun sendInferenceFrame(img: Image) {
        val sink = frameSink ?: return
        val p0 = img.planes[0]; val p1 = img.planes[1]; val p2 = img.planes[2]
        fun readPlane(p: Image.Plane): ByteArray =
            ByteArray(p.buffer.remaining()).also { p.buffer.get(it) }
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
     *   bits 13-15 : confidence (0 = invalid, 7 = highest)
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
        // GL/EGL teardown must run on the HandlerThread that owns the context.
        // quitSafely() drains the queue (including this post) before stopping.
        loopHandler?.post { releaseGl() }
        loopThread?.quitSafely()
        loopThread?.join(1000)
        loopThread = null; loopHandler = null
        session?.pause(); session?.close(); session = null
        previewEntry?.release(); previewEntry = null
        depthData = null
    }

    // ── EGL / GL setup ────────────────────────────────────────────────────────

    private fun setupEgl() {
        eglDisplay = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
        check(eglDisplay != EGL14.EGL_NO_DISPLAY) { "eglGetDisplay failed" }
        val ver = IntArray(2)
        EGL14.eglInitialize(eglDisplay, ver, 0, ver, 1)

        val cfgAttribs = intArrayOf(
            EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
            EGL14.EGL_SURFACE_TYPE,    EGL14.EGL_PBUFFER_BIT or EGL14.EGL_WINDOW_BIT,
            EGL14.EGL_NONE,
        )
        val configs = arrayOfNulls<EGLConfig>(1)
        val nCfg = IntArray(1)
        EGL14.eglChooseConfig(eglDisplay, cfgAttribs, 0, configs, 0, 1, nCfg, 0)
        check(nCfg[0] > 0) { "No suitable EGL config" }

        val ctxAttribs = intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE)
        eglCtx = EGL14.eglCreateContext(eglDisplay, configs[0], EGL14.EGL_NO_CONTEXT, ctxAttribs, 0)

        // 1×1 pbuffer — default surface for session.update() frames
        val pbuf = intArrayOf(EGL14.EGL_WIDTH, 1, EGL14.EGL_HEIGHT, 1, EGL14.EGL_NONE)
        eglPbuffer = EGL14.eglCreatePbufferSurface(eglDisplay, configs[0], pbuf, 0)

        // Window surface backed by Flutter's SurfaceTexture for camera preview output
        val st = previewEntry!!.surfaceTexture()
        st.setDefaultBufferSize(previewW, previewH)
        eglPreview = EGL14.eglCreateWindowSurface(eglDisplay, configs[0], st,
            intArrayOf(EGL14.EGL_NONE), 0)

        // Make pbuffer current on this thread (HandlerThread)
        EGL14.eglMakeCurrent(eglDisplay, eglPbuffer, eglPbuffer, eglCtx)

        // OES texture that ARCore writes camera frames into
        val tex = IntArray(1)
        GLES20.glGenTextures(1, tex, 0)
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, tex[0])
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
            GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
            GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
        cameraTexId = tex[0]

        // Compile OES preview shader
        fun compileShader(type: Int, src: String): Int {
            val id = GLES20.glCreateShader(type)
            GLES20.glShaderSource(id, src)
            GLES20.glCompileShader(id)
            val st2 = IntArray(1)
            GLES20.glGetShaderiv(id, GLES20.GL_COMPILE_STATUS, st2, 0)
            check(st2[0] == GLES20.GL_TRUE) {
                "Shader compile failed: ${GLES20.glGetShaderInfoLog(id)}"
            }
            return id
        }
        val vs = compileShader(GLES20.GL_VERTEX_SHADER,   VERT_SRC)
        val fs = compileShader(GLES20.GL_FRAGMENT_SHADER, FRAG_SRC)
        glProgram = GLES20.glCreateProgram().also {
            GLES20.glAttachShader(it, vs); GLES20.glAttachShader(it, fs)
            GLES20.glLinkProgram(it)
        }
        GLES20.glDeleteShader(vs); GLES20.glDeleteShader(fs)

        aPos = GLES20.glGetAttribLocation(glProgram,  "aPos")
        aUV  = GLES20.glGetAttribLocation(glProgram,  "aUV")
        uTex = GLES20.glGetUniformLocation(glProgram, "uTex")

        quadBuf = ByteBuffer.allocateDirect(QUAD.size * 4)
            .order(ByteOrder.nativeOrder()).asFloatBuffer()
            .also { it.put(QUAD); it.position(0) }
    }

    // ── EGL / GL teardown ─────────────────────────────────────────────────────

    private fun releaseGl() {
        if (eglDisplay == EGL14.EGL_NO_DISPLAY) return
        EGL14.eglMakeCurrent(eglDisplay, eglPbuffer, eglPbuffer, eglCtx)
        if (glProgram != 0) { GLES20.glDeleteProgram(glProgram); glProgram = 0 }
        if (cameraTexId != 0) {
            GLES20.glDeleteTextures(1, intArrayOf(cameraTexId), 0); cameraTexId = 0
        }
        EGL14.eglMakeCurrent(eglDisplay,
            EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT)
        if (eglPreview != EGL14.EGL_NO_SURFACE) {
            EGL14.eglDestroySurface(eglDisplay, eglPreview)
            eglPreview = EGL14.EGL_NO_SURFACE
        }
        if (eglPbuffer != EGL14.EGL_NO_SURFACE) {
            EGL14.eglDestroySurface(eglDisplay, eglPbuffer)
            eglPbuffer = EGL14.EGL_NO_SURFACE
        }
        EGL14.eglDestroyContext(eglDisplay, eglCtx)
        EGL14.eglTerminate(eglDisplay)
        eglDisplay = EGL14.EGL_NO_DISPLAY
        eglCtx     = EGL14.EGL_NO_CONTEXT
    }
}
