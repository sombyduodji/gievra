package fi.somby.gievra

import android.content.ClipData
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var openChannel: MethodChannel? = null
    private var pendingText: String? = null

    /// Avattu tai jaettu tiedosto (ohjelmapohja .gmd) tekstinä. Enintään 1 Mt; sisällön tarkistaa Dart.
    private fun textFromIntent(intent: Intent?): String? {
        if (intent == null) return null
        val uri: Uri? = when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND -> {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
            }
            else -> null
        }
        if (uri == null) return if (intent.action == Intent.ACTION_SEND) intent.getStringExtra(Intent.EXTRA_TEXT) else null
        return try {
            contentResolver.openInputStream(uri)?.use { s ->
                val bytes = s.readBytes()
                if (bytes.size > 1_000_000) null else String(bytes, Charsets.UTF_8)
            }
        } catch (e: Exception) {
            null
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        textFromIntent(intent)?.let { openChannel?.invokeMethod("open", it) }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingText = textFromIntent(intent)
        openChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fi.somby.gievra/open").also { ch ->
            ch.setMethodCallHandler { call, result ->
                if (call.method == "initial") {
                    result.success(pendingText)
                    pendingText = null
                } else {
                    result.notImplemented()
                }
            }
        }
        // Vikailmoitus: sähköposti vastaanottajalla, aiheella, tekstillä ja liitteillä (Gmail ym.).
        // mailto: ei tue liitteitä, joten käytetään ACTION_SEND(_MULTIPLE)-aikomusta ja FileProvideria.
        // Palautusajastin: hälytys ja ilmoitus (ks. RestAlarm.kt).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fi.somby.gievra/rest").setMethodCallHandler { call, result ->
            val title = call.argument<String>("title") ?: "Gievra"
            val body = call.argument<String>("body") ?: ""
            val sound = call.argument<String>("sound") ?: "pling"
            call.argument<String>("channel")?.let { RestAlarm.channelName = it }
            call.argument<String>("channelDesc")?.let { RestAlarm.channelDesc = it }
            when (call.method) {
                "schedule" -> RestAlarm.schedule(this, call.argument<Int>("seconds") ?: 60, title, body, sound)
                "cancel" -> RestAlarm.cancel(this)
                "preview" -> RestAlarm.show(this, title, body, sound)
                else -> return@setMethodCallHandler result.notImplemented()
            }
            result.success(null)
        }
        // Reitin tallennus (ks. GpsService.kt): paikannukset tapahtumina, ohjaus metodeina.
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "fi.somby.gievra/gps").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, events: EventChannel.EventSink) {
                    GpsService.sink = { events.success(it) }
                }

                override fun onCancel(args: Any?) {
                    GpsService.sink = null
                }
            },
        )
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fi.somby.gievra/gpsctl").setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    GpsService.start(
                        this,
                        call.argument<String>("title") ?: "Gievra",
                        call.argument<String>("text") ?: "",
                        call.argument<String>("channel") ?: "GPS",
                    )
                    result.success(null)
                }
                "stop" -> {
                    GpsService.stop(this)
                    result.success(null)
                }
                "running" -> result.success(GpsService.running)
                "enabled" -> result.success(GpsService.gpsEnabled(this))
                "rawPath" -> result.success(GpsService.rawFile(this).path)
                "settings" -> {
                    startActivity(Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fi.somby.gievra/email").setMethodCallHandler { call, result ->
            if (call.method != "send") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            try {
                val to = call.argument<String>("to") ?: ""
                val subject = call.argument<String>("subject") ?: ""
                val body = call.argument<String>("body") ?: ""
                val paths = call.argument<List<String>>("paths") ?: emptyList()
                val uris = ArrayList<Uri>(paths.map { FileProvider.getUriForFile(this, "$packageName.reports", File(it)) })
                val intent = Intent(if (uris.size > 1) Intent.ACTION_SEND_MULTIPLE else Intent.ACTION_SEND).apply {
                    type = if (uris.isEmpty()) "message/rfc822" else "*/*"
                    putExtra(Intent.EXTRA_EMAIL, arrayOf(to))
                    putExtra(Intent.EXTRA_SUBJECT, subject)
                    putExtra(Intent.EXTRA_TEXT, body)
                    if (uris.size == 1) putExtra(Intent.EXTRA_STREAM, uris[0])
                    if (uris.size > 1) putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
                    if (uris.isNotEmpty()) {
                        clipData = ClipData.newRawUri("", uris[0]).also { c -> uris.drop(1).forEach { c.addItem(ClipData.Item(it)) } }
                    }
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                startActivity(Intent.createChooser(intent, subject).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
                result.success(true)
            } catch (e: Exception) {
                result.error("email", e.message, null)
            }
        }
    }
}
