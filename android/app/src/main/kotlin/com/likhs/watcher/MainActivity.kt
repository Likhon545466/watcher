package com.likhs.watcher

import android.os.Build
import android.os.Bundle
import android.view.Surface
import android.view.SurfaceView
import android.view.View
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {

    private val targetHz = 120.0f

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applyHighRefreshRequests()
    }

    override fun onResume() {
        super.onResume()

        // Re-apply because some vendor builds reset refresh policy
        // when the Activity loses/regains focus.
        window.decorView.post {
            applyHighRefreshRequests()
        }

        window.decorView.postDelayed({
            applyHighRefreshRequests()
        }, 500L)

        window.decorView.postDelayed({
            requestFlutterSurfaceFrameRate()
        }, 1200L)
    }

    private fun applyHighRefreshRequests() {
        requestHighestDisplayMode()
        requestFlutterSurfaceFrameRate()
    }

    private fun requestHighestDisplayMode() {
        try {
            val params = window.attributes
            params.preferredRefreshRate = targetHz

            val currentDisplay = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                display
            } else {
                @Suppress("DEPRECATION")
                windowManager.defaultDisplay
            }

            val currentMode = currentDisplay?.mode

            if (currentDisplay != null && currentMode != null) {
                val bestMode = currentDisplay.supportedModes
                    .filter {
                        it.physicalWidth == currentMode.physicalWidth &&
                        it.physicalHeight == currentMode.physicalHeight
                    }
                    .maxByOrNull { it.refreshRate }

                if (bestMode != null && bestMode.refreshRate > 60.0f) {
                    params.preferredDisplayModeId = bestMode.modeId
                    params.preferredRefreshRate = bestMode.refreshRate
                }
            }

            window.attributes = params
        } catch (_: Throwable) {
            // Keep the app usable if a vendor implementation rejects this.
        }
    }

    private fun requestFlutterSurfaceFrameRate() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            return
        }

        try {
            val root = window.decorView.rootView
            applyFrameRateToSurfaceViews(root)
        } catch (_: Throwable) {
            // Safe fallback.
        }
    }

    private fun applyFrameRateToSurfaceViews(view: View) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            return
        }

        if (view is SurfaceView) {
            val surface = view.holder.surface

            if (surface != null && surface.isValid) {
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        surface.setFrameRate(
                            targetHz,
                            Surface.FRAME_RATE_COMPATIBILITY_DEFAULT,
                            Surface.CHANGE_FRAME_RATE_ALWAYS
                        )
                    } else {
                        surface.setFrameRate(
                            targetHz,
                            Surface.FRAME_RATE_COMPATIBILITY_DEFAULT
                        )
                    }
                } catch (_: Throwable) {
                    // Ignore vendor/API-specific failure.
                }
            }
        }

        if (view is android.view.ViewGroup) {
            for (i in 0 until view.childCount) {
                applyFrameRateToSurfaceViews(view.getChildAt(i))
            }
        }
    }
}
