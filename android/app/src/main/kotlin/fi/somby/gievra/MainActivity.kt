package fi.somby.gievra

import android.content.ClipData
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
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
import kotlinx.coroutines.withContext
import java.io.File

class MainActivity : FlutterActivity() {
    private var openChannel: MethodChannel? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var healthResult: MethodChannel.Result? = null
    private var healthAsked: Set<String> = emptySet()
    private val healthContract = PermissionController.createRequestPermissionResultContract()
    private var saveResult: MethodChannel.Result? = null
    private var saveSource: String? = null

    // Ilmoituksen painikkeiden kutsu tälle aktiviteetille; nollataan onDestroyssa, ettei staattinen kenttä pidä
    // tuhottua aktiviteettia ja sen kanavaa muistissa (vain jos uudempi aktiviteetti ei ole jo asettanut omaansa).
    private var noteCb: ((String) -> Unit)? = null

    override fun onDestroy() {
        if (live?.get() === this) live = null
        if (NoteActionReceiver.onAction === noteCb) NoteActionReceiver.onAction = null
        scope.cancel()
        super.onDestroy()
    }

    @Deprecated("FlutterActivity ei tue ActivityResult-rekisteriä; Health Connectin lupakysely palaa tänne")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == SAVE_REQUEST) {
            onSaveResult(resultCode, data)
            return
        }
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
        /// Käynnissä oleva MainActivity (toisen käynnistyksen vartija, ks. onCreate).
        private var live: java.lang.ref.WeakReference<MainActivity>? = null
        private const val HEALTH_REQUEST = 4711
        private const val SAVE_REQUEST = 4712

        /// OpenFileActivityn välittämä alkuperäinen VIEW/SEND-aikomus (itse aikomus on MAIN + LAUNCHER).
        const val EXTRA_OPEN = "fi.somby.gievra.OPEN"
    }
    private var pendingIntent: Intent? = null

    /// Näkymä palautettiin tallennetusta tilasta (prosessi tapettu taustalla): käynnistysaikomuksen tiedostoa ei
    /// avata toista kertaa.
    private var restored = false

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        restored = savedInstanceState != null
        // Toinen Gievra samaan aikaan (käyttäjä 16.11.: vartija): vanhojen versioiden Viimeisimmät-kortti (pohja-aikomus
        // VIEW/SEND) tai muu reitti käynnistää toisen MainActivityn ja toisen Flutter-moottorin samoihin tiedostoihin.
        // Käynnissä oleva tuodaan esiin ja tämä suljetaan heti: finish() onCreatessa ohittaa onStartin, joten Dart-koodi
        // ei käynnisty tässä toisessa moottorissa lainkaan.
        val other = live?.get()
        if (other != null && other !== this && !other.isFinishing && !other.isDestroyed) {
            super.onCreate(savedInstanceState)
            handOverTo(other)
            finish()
            return
        }
        live = java.lang.ref.WeakReference(this)
        super.onCreate(savedInstanceState)
    }

    /// Tuo käynnissä olevan Gievran tehtävän eteen; uusi tiedosto (ei historiasta) välitetään sille.
    private fun handOverTo(other: MainActivity) {
        // Juuri käynnissä olevan Gievran tehtävä eteen (tarkka tehtävä: Viimeisimmissä voi olla vanhoja Gievra-kortteja,
        // joihin käynnistimen aikomus voisi osua).
        try {
            val am = getSystemService(ACTIVITY_SERVICE) as android.app.ActivityManager
            val task = am.appTasks.firstOrNull { t ->
                val info = t.taskInfo ?: return@firstOrNull false
                val id = if (Build.VERSION.SDK_INT >= 29) info.taskId else @Suppress("DEPRECATION") info.persistentId
                id == other.taskId
            }
            android.util.Log.i("Gievra", "toinen MainActivity: tehtävä ${other.taskId} eteen (${task != null})")
            task?.moveToFront()
        } catch (e: Exception) {
            android.util.Log.w("Gievra", "toinen MainActivity: eteen tuonti epäonnistui", e)
        }
        val i = intent ?: return
        if (i.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) return
        if (i.action == Intent.ACTION_VIEW || i.action == Intent.ACTION_SEND || i.hasExtra(EXTRA_OPEN)) {
            other.onNewIntent(i)
        }
    }

    /// Avattavan tiedoston aikomus: OpenFileActivityn välittämä alkuperäinen tai (vanha tapa) suora VIEW/SEND.
    /// Viimeisimmät-näkymästä uudelleen käynnistetty tehtävä saa saman pohja-aikomuksen toiseen kertaan
    /// (LAUNCHED_FROM_HISTORY): sitä ei avata uudelleen (testikierros 16.11.: tuonnin esikatselu palasi).
    private fun openIntent(intent: Intent?): Intent? {
        if (intent == null) return null
        if (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) return null
        // Rikkinäiset tai tuntemattomat lisätiedot (BadParcelableException, yötesti 17.11.): ei kaadeta käynnissä
        // olevaa treeniä, vaan avataan ilman tiedostoa.
        return try {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra<Intent>(EXTRA_OPEN) ?: intent
        } catch (_: Exception) {
            null
        }
    }

    /// Avattu tai jaettu tiedosto ("Avaa sovelluksella", "Jaa → Gievra"). Tiedosto kopioidaan välimuistiin ja Dart saa
    /// polun ja nimen; tyypin tunnistaa sama koodi kuin Tuo tiedosto -painikkeessa (FitNotes, zip, csv, .md, .gmd).
    /// Jaettu pelkkä teksti välitetään tekstinä. Vain content://. Yli 500 Mt:n kopiointi lopetetaan (Dart ilmoittaa).
    private fun fileFromIntent(launch: Intent?): Map<String, Any?>? {
        val intent = openIntent(launch) ?: return null
        val failed = mapOf<String, Any?>("error" to true)
        val uri: Uri? = try {
            when (intent.action) {
                Intent.ACTION_VIEW -> intent.data
                Intent.ACTION_SEND -> {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                }
                else -> null
            }
        } catch (_: Exception) {
            return failed // rikkinäiset lisätiedot (yötesti 17.11.)
        }
        if (uri == null) {
            if (intent.action != Intent.ACTION_SEND) return null
            return try {
                intent.getStringExtra(Intent.EXTRA_TEXT)?.let { mapOf("text" to it) }
            } catch (_: Exception) {
                failed
            }
        }
        // Vain content://: file://-osoitteella toinen sovellus voisi saada Gievran (kaikkien tiedostojen lupa)
        // lukemaan tiedoston, johon sillä itsellään ei ole oikeutta.
        // Tiedosto, jota ei voi lukea: Dart näyttää ilmoituksen (aiemmin etusivu aukesi ilman selitystä).
        if (uri.scheme != "content") return failed
        return try {
            var name: String? = null
            contentResolver.query(uri, arrayOf(android.provider.OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                if (c.moveToFirst() && !c.isNull(0)) name = c.getString(0)
            }
            // Oma tiedosto joka avaukselle: nopea toinen avaus ei poista tai korvaa tiedostoa, jota Dart vielä lukee
            // (yötesti 16.11.). Yli 10 min vanhat edelliset avaukset siivotaan.
            val dir = File(cacheDir, "opened").apply { mkdirs() }
            val old = System.currentTimeMillis() - 10 * 60 * 1000
            dir.listFiles()?.forEach { if (it.lastModified() < old) it.deleteRecursively() }
            val out = File(dir, "file-${System.nanoTime()}")
            val limit = 500L * 1024 * 1024
            var size = 0L
            contentResolver.openInputStream(uri)?.use { input ->
                out.outputStream().use { o ->
                    val buf = ByteArray(64 * 1024)
                    while (size <= limit) {
                        val n = input.read(buf)
                        if (n < 0) break
                        o.write(buf, 0, n)
                        size += n
                    }
                }
            } ?: return failed
            mapOf("path" to out.path, "name" to (name ?: ""), "tooLarge" to (size > limit))
        } catch (e: Exception) {
            failed
        }
    }

    /// Varmuuskopion tallennus: käyttäjä valitsee paikan (SAF), tiedosto kopioidaan sinne ja luetaan takaisin.
    /// Tulos Dartiin: null = peruttu, muuten {"saved", "verified"}. verified = takaisin luettu SHA-256 täsmää.
    private fun onSaveResult(resultCode: Int, data: Intent?) {
        val r = saveResult ?: return
        val src = saveSource
        saveResult = null
        saveSource = null
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null || src == null) {
            r.success(null)
            return
        }
        scope.launch {
            val out = kotlinx.coroutines.withContext(Dispatchers.IO) { copyAndVerify(File(src), uri) }
            r.success(out)
        }
    }

    private fun copyAndVerify(src: File, uri: Uri): Map<String, Boolean> {
        fun digest(input: java.io.InputStream, copyTo: java.io.OutputStream? = null): ByteArray {
            val md = java.security.MessageDigest.getInstance("SHA-256")
            val buf = ByteArray(256 * 1024)
            while (true) {
                val n = input.read(buf)
                if (n < 0) break
                md.update(buf, 0, n)
                copyTo?.write(buf, 0, n)
            }
            return md.digest()
        }
        val written = try {
            val o = contentResolver.openOutputStream(uri, "wt") ?: return mapOf("saved" to false, "verified" to false)
            o.use { out -> src.inputStream().use { digest(it, out) } }
        } catch (e: Exception) {
            // Valitsin loi jo tyhjän tiedoston: poistetaan se, ettei jäljelle jää 0 tavun "varmuuskopiota".
            try {
                android.provider.DocumentsContract.deleteDocument(contentResolver, uri)
            } catch (_: Exception) {
            }
            return mapOf("saved" to false, "verified" to false)
        }
        val back = try {
            contentResolver.openInputStream(uri)?.use { digest(it) }
        } catch (e: Exception) {
            null
        }
        return mapOf("saved" to true, "verified" to (back != null && back.contentEquals(written)))
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Kopiointi taustalla (iso varmuuskopio ei jumita näkymää).
        scope.launch {
            val f = withContext(Dispatchers.IO) { fileFromIntent(intent) }
            f?.let { openChannel?.invokeMethod("open", it) }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingIntent = if (restored) null else intent
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fi.somby.gievra/sqlite").setMethodCallHandler(SqliteBridge())
        openChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fi.somby.gievra/open").also { ch ->
            ch.setMethodCallHandler { call, result ->
                if (call.method == "initial") {
                    val i = pendingIntent
                    pendingIntent = null
                    scope.launch { result.success(withContext(Dispatchers.IO) { fileFromIntent(i) }) }
                } else {
                    result.notImplemented()
                }
            }
        }
        // Vikailmoitus: sähköposti vastaanottajalla, aiheella, tekstillä ja liitteillä (Gmail ym.).
        // mailto: ei tue liitteitä, joten käytetään ACTION_SEND(_MULTIPLE)-aikomusta ja FileProvideria.
        // Palautusajastin: hälytys ja ilmoitus (ks. RestAlarm.kt).
        // Akunsäästö: saako Gievra toimia taustalla (palautusajastin ja sykevyö näyttö pois päältä).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fi.somby.gievra/save").setMethodCallHandler { call, result ->
            if (call.method != "saveVerified") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            if (saveResult != null) {
                result.error("busy", "save in progress", null)
                return@setMethodCallHandler
            }
            saveResult = result
            saveSource = call.argument<String>("path")
            val i = Intent(Intent.ACTION_CREATE_DOCUMENT)
                .addCategory(Intent.CATEGORY_OPENABLE)
                .setType(call.argument<String>("mime") ?: "application/octet-stream")
                .putExtra(Intent.EXTRA_TITLE, call.argument<String>("name") ?: "gievra.zip")
            try {
                @Suppress("DEPRECATION")
                startActivityForResult(i, SAVE_REQUEST)
            } catch (e: Exception) {
                saveResult = null
                saveSource = null
                result.error("noPicker", e.message, null)
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fi.somby.gievra/power").setMethodCallHandler { call, result ->
            val pm = getSystemService(PowerManager::class.java)
            when (call.method) {
                "status" -> result.success(
                    mapOf(
                        "exempt" to (pm?.isIgnoringBatteryOptimizations(packageName) == true),
                        "samsung" to Build.MANUFACTURER.equals("samsung", ignoreCase = true),
                    ),
                )
                // Androidin oma kysymys "Sallitaanko sovelluksen toimia aina taustalla?".
                "request" -> {
                    val ok = try {
                        startActivity(
                            Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName")),
                        )
                        true
                    } catch (e: Exception) {
                        false
                    }
                    result.success(ok)
                }
                // Sovelluksen tiedot (Akku → Rajoittamaton), jos kysymys ei aukea tai puhelin vaatii lisäksi oman asetuksen.
                "appSettings" -> {
                    try {
                        startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
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
        // Sykevyö Bluetoothilla (HeartRateBle.kt): tapahtumat virtana, ohjaus metodeina.
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "fi.somby.gievra/hr/events").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, events: EventChannel.EventSink) {
                    HeartRateBle.sink = { events.success(it) }
                }

                override fun onCancel(args: Any?) {
                    HeartRateBle.sink = null
                }
            },
        )
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fi.somby.gievra/hr").setMethodCallHandler { call, result ->
            when (call.method) {
                "supported" -> result.success(HeartRateBle.supported(this))
                "needsLocation" -> result.success(android.os.Build.VERSION.SDK_INT < 31)
                "permitted" -> result.success(HeartRateBle.permitted(this))
                "enabled" -> result.success(HeartRateBle.enabled(this))
                "scan" -> {
                    HeartRateBle.scan(this, call.argument<Int>("seconds") ?: 15)
                    result.success(null)
                }
                "stopScan" -> {
                    HeartRateBle.stopScan(this)
                    result.success(null)
                }
                "connect" -> {
                    HeartRateBle.connect(this, call.argument<String>("address") ?: "")
                    result.success(null)
                }
                "disconnect" -> {
                    HeartRateBle.disconnect()
                    result.success(null)
                }
                "enable" -> {
                    // Bluetooth pois päältä: järjestelmän oma kysely.
                    try {
                        startActivity(Intent(android.bluetooth.BluetoothAdapter.ACTION_REQUEST_ENABLE))
                    } catch (_: Exception) {
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        // Käynnissä oleva treeni pudotusvalikossa (OngoingNote.kt).
        val ongoingChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fi.somby.gievra/ongoing")
        // Ilmoituksen palautuspainikkeet Dartille (pääsäikeessä).
        val cb: (String) -> Unit = { a ->
            runOnUiThread { ongoingChannel.invokeMethod("noteAction", a) }
        }
        noteCb = cb
        NoteActionReceiver.onAction = cb
        ongoingChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "show" -> {
                    call.argument<String>("publicTitle")?.let { OngoingNote.publicTitle = it }
                    OngoingNote.show(
                        this,
                        call.argument<String>("title") ?: "Gievra",
                        (call.argument<Number>("start") ?: System.currentTimeMillis()).toLong(),
                        call.argument<Boolean>("paused") == true,
                        call.argument<String>("pausedText") ?: "",
                        call.argument<String>("channel") ?: "Gievra",
                        OngoingNote.Live.from(call.argument<Map<*, *>>("live")),
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
                            call.argument<Boolean>("sleep") == true && call.argument<Boolean>("history") == true -> HealthBridge.sleepHistoryPermissions
                            call.argument<Boolean>("sleep") == true -> HealthBridge.sleepPermissions
                            call.argument<Boolean>("metrics") == true -> HealthBridge.metricsPermissions(this@MainActivity)
                            call.argument<Boolean>("history") == true -> HealthBridge.historyPermissions
                            call.argument<Boolean>("heartRate") == true -> HealthBridge.heartRatePermissions
                            call.argument<Boolean>("steps") == true -> HealthBridge.stepsPermissions
                            call.argument<Boolean>("import") == true -> HealthBridge.importPermissions
                            else -> HealthBridge.readPermissions
                        }
                        val have = HealthBridge.granted(this@MainActivity)
                        // Yöarvot: riittää, että jokin arvo on sallittu (käyttäjä voi antaa vain osan).
                        result.success(if (call.argument<Boolean>("metrics") == true) need.any { it in have } else have.containsAll(need))
                    } catch (e: Exception) {
                        result.error("health", e.message, null)
                    }
                }
                "request" -> {
                    val write = call.argument<Boolean>("write") == true && BuildConfig.DEBUG
                    val read = when {
                        call.argument<Boolean>("sleep") == true && call.argument<Boolean>("history") == true -> HealthBridge.sleepHistoryPermissions
                        call.argument<Boolean>("sleep") == true -> HealthBridge.sleepPermissions
                        call.argument<Boolean>("metrics") == true -> HealthBridge.metricsPermissions(this)
                        call.argument<Boolean>("history") == true -> HealthBridge.historyPermissions
                        call.argument<Boolean>("heartRate") == true -> HealthBridge.heartRatePermissions
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
                "nightMetrics" -> scope.launch {
                    try {
                        @Suppress("UNCHECKED_CAST")
                        val w = (call.argument<List<Any>>("windows") ?: emptyList()).map { it as List<Any> }
                        result.success(HealthBridge.nightMetrics(this@MainActivity, w))
                    } catch (e: Exception) {
                        result.error("health", e.message, null)
                    }
                }
                "sleepSessions" -> scope.launch {
                    try {
                        val start = (call.argument<Number>("start") ?: 0).toLong()
                        val end = (call.argument<Number>("end") ?: 0).toLong()
                        result.success(HealthBridge.sleepSessions(this@MainActivity, start, end))
                    } catch (e: Exception) {
                        result.error("health", e.message, null)
                    }
                }
                "nightLowHr" -> scope.launch {
                    try {
                        result.success(
                            HealthBridge.nightLowHr(
                                this@MainActivity,
                                call.argument<String>("from")!!,
                                call.argument<String>("to")!!,
                                call.argument<String>("app"),
                            ),
                        )
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
