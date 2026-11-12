package fi.somby.gievra

import android.content.ClipData
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import androidx.health.connect.client.PermissionController
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import java.io.File

class MainActivity : FlutterActivity() {
    private var openChannel: MethodChannel? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var healthResult: MethodChannel.Result? = null
    private var healthAsked: Set<String> = emptySet()
    private val healthContract = PermissionController.createRequestPermissionResultContract()

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    @Deprecated("FlutterActivity ei tue ActivityResult-rekisteriä; Health Connectin lupakysely palaa tänne")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != HEALTH_REQUEST) return
        val granted = try {
            healthContract.parseResult(resultCode, data)
        } catch (e: Exception) {
            emptySet()
        }
        healthResult?.success(granted.containsAll(healthAsked))
        healthResult = null
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != HEALTH_REQUEST) return
        val granted = permissions.filterIndexed { i, _ -> grantResults.getOrNull(i) == PackageManager.PERMISSION_GRANTED }.toSet()
        healthResult?.success(granted.containsAll(healthAsked))
        healthResult = null
    }

    companion object {
        private const val HEALTH_REQUEST = 4711
    }
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
        // Käynnissä oleva treeni pudotusvalikossa (OngoingNote.kt).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fi.somby.gievra/ongoing").setMethodCallHandler { call, result ->
            when (call.method) {
                "show" -> {
                    OngoingNote.show(
                        this,
                        call.argument<String>("title") ?: "Gievra",
                        (call.argument<Number>("start") ?: System.currentTimeMillis()).toLong(),
                        call.argument<Boolean>("paused") == true,
                        call.argument<String>("pausedText") ?: "",
                        call.argument<String>("channel") ?: "Gievra",
                    )
                    result.success(null)
                }
                "hide" -> {
                    OngoingNote.hide(this)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        // Karttatiedoston SHA-256 (tuonti tiedostosta): laitteiston kiihdyttämä MessageDigest taustasäikeessä,
        // edistyminen takaisin Dartille noin 4 Mt:n välein.
        val hashChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fi.somby.gievra/hash")
        hashChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "sha256" -> {
                    val path = call.argument<String>("path") ?: return@setMethodCallHandler result.error("hash", "path", null)
                    val id = call.argument<Int>("id") ?: 0
                    scope.launch {
                        try {
                            val hex = kotlinx.coroutines.withContext(Dispatchers.IO) {
                                val md = java.security.MessageDigest.getInstance("SHA-256")
                                val buf = ByteArray(1 shl 20)
                                var done = 0L
                                var reported = 0L
                                File(path).inputStream().use { input ->
                                    while (true) {
                                        val n = input.read(buf)
                                        if (n < 0) break
                                        md.update(buf, 0, n)
                                        done += n
                                        if (done - reported >= (4L shl 20)) {
                                            reported = done
                                            val d = done
                                            runOnUiThread { hashChannel.invokeMethod("progress", mapOf("id" to id, "bytes" to d)) }
                                        }
                                    }
                                }
                                md.digest().joinToString("") { "%02x".format(it) }
                            }
                            result.success(hex)
                        } catch (e: Exception) {
                            result.error("hash", e.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
        // Health Connect (ks. HealthBridge.kt): saatavuus, luvat ja treenin aikavälin ehdokkaat.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fi.somby.gievra/health").setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> result.success(HealthBridge.status(this))
                "historyAvailable" -> result.success(HealthBridge.historyAvailable(this))
                "granted" -> scope.launch {
                    try {
                        val need = when {
                            call.argument<Boolean>("history") == true -> HealthBridge.historyPermissions
                            call.argument<Boolean>("steps") == true -> HealthBridge.stepsPermissions
                            call.argument<Boolean>("import") == true -> HealthBridge.importPermissions
                            else -> HealthBridge.readPermissions
                        }
                        result.success(HealthBridge.granted(this@MainActivity).containsAll(need))
                    } catch (e: Exception) {
                        result.error("health", e.message, null)
                    }
                }
                "request" -> {
                    val write = call.argument<Boolean>("write") == true && BuildConfig.DEBUG
                    val read = when {
                        call.argument<Boolean>("history") == true -> HealthBridge.historyPermissions
                        call.argument<Boolean>("steps") == true -> HealthBridge.stepsPermissions
                        call.argument<Boolean>("import") == true -> HealthBridge.importPermissions
                        else -> HealthBridge.readPermissions
                    }
                    healthAsked = if (write) read + HealthBridge.writePermissions else read
                    healthResult = result
                    try {
                        if (android.os.Build.VERSION.SDK_INT >= 34) {
                            // Android 14+: Health Connect -luvat ovat tavallisia ajonaikaisia lupia.
                            requestPermissions(healthAsked.toTypedArray(), HEALTH_REQUEST)
                        } else {
                            @Suppress("DEPRECATION")
                            startActivityForResult(healthContract.createIntent(this, healthAsked), HEALTH_REQUEST)
                        }
                    } catch (e: Exception) {
                        healthResult = null
                        result.error("health", e.message, null)
                    }
                }
                "sessions" -> scope.launch {
                    try {
                        val start = (call.argument<Number>("start") ?: 0).toLong()
                        val end = (call.argument<Number>("end") ?: 0).toLong()
                        result.success(HealthBridge.sessions(this@MainActivity, start, end))
                    } catch (e: Exception) {
                        result.error("health", e.message, null)
                    }
                }
                "stepRecords" -> scope.launch {
                    try {
                        val start = (call.argument<Number>("start") ?: 0).toLong()
                        val end = (call.argument<Number>("end") ?: 0).toLong()
                        result.success(HealthBridge.stepRecords(this@MainActivity, start, end))
                    } catch (e: Exception) {
                        result.error("health", e.message, null)
                    }
                }
                "dailySteps" -> scope.launch {
                    try {
                        result.success(HealthBridge.dailySteps(this@MainActivity, call.argument<String>("from")!!, call.argument<String>("to")!!))
                    } catch (e: Exception) {
                        result.error("health", e.message, null)
                    }
                }
                "deviceSteps" -> scope.launch {
                    try {
                        result.success(
                            HealthBridge.deviceSteps(
                                this@MainActivity,
                                call.argument<String>("date")!!,
                                (call.argument<Number>("start") ?: 0).toLong(),
                                (call.argument<Number>("end") ?: 0).toLong(),
                                call.argument<String>("label")!!,
                            ),
                        )
                    } catch (e: Exception) {
                        result.error("health", e.message, null)
                    }
                }
                "stepsInRange" -> scope.launch {
                    try {
                        val start = (call.argument<Number>("start") ?: 0).toLong()
                        val end = (call.argument<Number>("end") ?: 0).toLong()
                        result.success(HealthBridge.stepsInRange(this@MainActivity, start, end))
                    } catch (e: Exception) {
                        result.error("health", e.message, null)
                    }
                }
                "dayStepsByApp" -> scope.launch {
                    try {
                        result.success(HealthBridge.dayStepsByApp(this@MainActivity, call.argument<String>("date")!!))
                    } catch (e: Exception) {
                        result.error("health", e.message, null)
                    }
                }
                "rangeStats" -> scope.launch {
                    try {
                        val start = (call.argument<Number>("start") ?: 0).toLong()
                        val end = (call.argument<Number>("end") ?: 0).toLong()
                        result.success(HealthBridge.rangeStats(this@MainActivity, start, end, call.argument<String>("pkg")))
                    } catch (e: Exception) {
                        result.error("health", e.message, null)
                    }
                }
                "candidates" -> scope.launch {
                    try {
                        val start = (call.argument<Number>("start") ?: 0).toLong()
                        val end = (call.argument<Number>("end") ?: 0).toLong()
                        result.success(HealthBridge.candidates(this@MainActivity, start, end))
                    } catch (e: Exception) {
                        result.error("health", e.message, null)
                    }
                }
                "debugInsert" -> {
                    if (!BuildConfig.DEBUG) return@setMethodCallHandler result.notImplemented()
                    scope.launch {
                        try {
                            HealthBridge.debugInsert(
                                this@MainActivity,
                                (call.argument<Number>("start") ?: 0).toLong(),
                                (call.argument<Number>("end") ?: 0).toLong(),
                                call.argument<Int>("type") ?: 56,
                                call.argument<Int>("bpm") ?: 140,
                            )
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("health", e.message, null)
                        }
                    }
                }
                "settings" -> {
                    try {
                        startActivity(Intent("androidx.health.ACTION_HEALTH_CONNECT_SETTINGS"))
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fi.somby.gievra/email").setMethodCallHandler { call, result ->
            if (call.method == "device") {
                // Vikailmoituksen diagnostiikka: valmistaja, malli ja Android-versio (ei tunnisteita).
                result.success("${android.os.Build.MANUFACTURER} ${android.os.Build.MODEL}, Android ${android.os.Build.VERSION.RELEASE} (SDK ${android.os.Build.VERSION.SDK_INT})")
                return@setMethodCallHandler
            }
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
