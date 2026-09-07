package com.example.grovio_supermart

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.grovio.supermart/upi"
    private var pendingResult: MethodChannel.Result? = null
    private val REQUEST_CODE_UPI = 1001

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "startUpiPayment") {
                val url = call.argument<String>("url")
                if (url != null) {
                    pendingResult = result
                    startUpiPayment(url)
                } else {
                    result.error("INVALID_URL", "UPI URL is null", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private fun startUpiPayment(url: String) {
        try {
            val intent = Intent(Intent.ACTION_VIEW)
            intent.data = Uri.parse(url)
            startActivityForResult(intent, REQUEST_CODE_UPI)
        } catch (e: Exception) {
            pendingResult?.error("UPI_ERROR", "No UPI app found", null)
            pendingResult = null
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_CODE_UPI) {
            if (data != null) {
                val response = data.getStringExtra("response") ?: "no_response"
                pendingResult?.success(response)
            } else {
                pendingResult?.success("failed")
            }
            pendingResult = null
        }
    }
}
