package com.hapticway.hapticway

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Navigation aid: detection must not die to the screen timeout —
        // screen-off delivers paused, which stops the whole pipeline. The flag
        // only holds while this window is visible, so backgrounding/locking
        // still sleeps the screen normally.
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ArDepthChannel(this, flutterEngine)
    }
}
