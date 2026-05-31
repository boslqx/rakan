package com.example.rakan

import android.content.Context
import android.view.View
import androidx.camera.view.PreviewView
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

// Flutter cannot natively render Android Views like PreviewView.
// PlatformViewFactory registers a native Android View that Flutter
class CameraPreviewFactory(
    private val previewViewProvider: () -> PreviewView?
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return CameraPreviewView(context, previewViewProvider)
    }
}

class CameraPreviewView(
    private val context: Context,
    private val previewViewProvider: () -> PreviewView?
) : PlatformView {

    // Use provided PreviewView or create a new one
    private val previewView: PreviewView =
        previewViewProvider() ?: PreviewView(context)

    override fun getView(): View = previewView

    override fun dispose() {}
}