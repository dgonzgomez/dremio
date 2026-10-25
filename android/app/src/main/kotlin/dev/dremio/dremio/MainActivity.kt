package dev.dremio.dremio

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

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
                problemWith(File(cacheDir, "updates/dremio.apk"))?.let { return@setMethodCallHandler result.error("install", it, null) }
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

    /** Why the system installer would reject [apk] as an update to this app, checked up front so the message is clear. */
    @Suppress("DEPRECATION")
    private fun problemWith(apk: File): String? {
        val archive = packageManager.getPackageArchiveInfo(apk.path, PackageManager.GET_SIGNATURES)
            ?: return "The download is damaged. Try again."
        if (archive.packageName != packageName) return "That download isn't Dremio."
        val installed = packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNATURES).signatures?.toSet()
        val incoming = archive.signatures?.toSet()
        if (incoming.isNullOrEmpty() || incoming != installed) {
            return "This update is signed with a different key than the installed app, so Android won't install it over it. Uninstall Dremio and install the new APK."
        }
        return null
    }
}
