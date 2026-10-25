package dev.dremio.dremio

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dremio/update").setMethodCallHandler { call, result ->
            if (call.method != "install") return@setMethodCallHandler result.notImplemented()
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
                    startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")))
                    return@setMethodCallHandler result.success(false)
                }
                val apk = Uri.parse("content://$packageName.update/dremio.apk")
                startActivity(
                    Intent(Intent.ACTION_VIEW)
                        .setDataAndType(apk, UpdateProvider.APK)
                        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK),
                )
                result.success(true)
            } catch (e: Exception) {
                result.error("install", e.message, null)
            }
        }
    }
}
