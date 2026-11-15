package fi.somby.gievra

import android.annotation.SuppressLint
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import java.io.File
import java.io.FileWriter

/// Reitin tallennus: Androidin oma GPS (LocationManager, ei Googlen palveluita) kerran sekunnissa
/// etualapalveluna, joten tallennus jatkuu näytön sammuessa ja toisessa sovelluksessa. Jokainen paikannus
/// kirjoitetaan heti tiedostoon (gps-recording.csv), joten lenkki ei katoa, vaikka Android sulkisi sovelluksen;
/// Dart lukee tiedoston ja suodattaa reitin (lib/gps_filter.dart). Mitään ei lähetetä minnekään.
class GpsService : Service(), LocationListener {
    companion object {
        /** Sama ilmoitus kuin muilla käynnissä olevilla treeneillä (OngoingNote): sovelluksella on vain yksi. */
        const val NOTIFICATION = OngoingNote.ID

        /// Dartin kuuntelija (EventChannel); null, kun sovellus ei ole auki.
        @Volatile var sink: ((Map<String, Any>) -> Unit)? = null
        @Volatile var running = false
        @Volatile private var instance: GpsService? = null
        @Volatile private var lastNote: android.app.Notification? = null

        /** Sykevyö yhdistyi tai katkesi kesken lenkin: etualan tyyppi uudelleen (connectedDevice mukaan tai pois). */
        fun refreshType(ctx: Context) {
            val s = instance ?: return
            val n = OngoingNote.current(ctx) ?: lastNote ?: return
            try {
                s.foreground(n)
            } catch (_: Exception) {
            }
        }

        fun rawFile(ctx: Context) = File(ctx.filesDir, "gps-recording.csv")

        fun start(ctx: Context, title: String, text: String, channel: String) {
            val i = Intent(ctx, GpsService::class.java)
                .putExtra("title", title)
                .putExtra("text", text)
                .putExtra("channel", channel)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) ctx.startForegroundService(i) else ctx.startService(i)
        }

        fun stop(ctx: Context) {
            ctx.stopService(Intent(ctx, GpsService::class.java))
        }

        fun gpsEnabled(ctx: Context): Boolean =
            (ctx.getSystemService(Context.LOCATION_SERVICE) as LocationManager)
                .isProviderEnabled(LocationManager.GPS_PROVIDER)
    }

    private val main = Handler(Looper.getMainLooper())
    private var writer: FileWriter? = null
    private var title = "Gievra"
    private var text = ""

    override fun onBind(intent: Intent?): IBinder? = null

    @SuppressLint("MissingPermission") // lupa pyydetään Dartissa ennen käynnistystä
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        intent?.getStringExtra("title")?.let { title = it }
        intent?.getStringExtra("text")?.let { text = it }
        // Androidin uudelleenkäynnistämänä intent on null: kanavan nimi säilyy (muuten se nimettäisiin "GPS":ksi).
        val channelName = intent?.getStringExtra("channel") ?: OngoingNote.channelName(this) ?: "GPS"
        // Ensimmäinen sisältö (odotetaan signaalia); Dart päivittää sen heti lajiksi ja ajaksi (OngoingNote.show).
        WorkoutService.stop(this) // GPS-palvelu ottaa saman ilmoituksen (ja pitää sovelluksen hereillä)
        val n = OngoingNote.build(this, title, System.currentTimeMillis(), true, text, channelName)
        try {
            foreground(n)
        } catch (e: Exception) {
            // Android 14+: sijaintilupa peruttu tai uudelleenkäynnistys taustalta ei ole sallittu. Ei kaadeta
            // sovellusta eikä yritetä uudelleen; tallennetut paikannukset jäävät tiedostoon palautusta varten.
            emit(mapOf("status" to "permission"))
            stopSelf()
            return START_NOT_STICKY
        }
        if (!running) {
            try {
                writer = FileWriter(rawFile(this), true)
                val lm = getSystemService(Context.LOCATION_SERVICE) as LocationManager
                lm.requestLocationUpdates(LocationManager.GPS_PROVIDER, 1000L, 0f, this, Looper.getMainLooper())
                running = true
            } catch (e: SecurityException) {
                emit(mapOf("status" to "permission"))
                stopSelf()
                return START_NOT_STICKY
            }
        }
        // Jos Android sulkee palvelun muistin vähyyden vuoksi, se käynnistetään uudelleen ja tallennus jatkuu.
        return START_STICKY
    }

    override fun onLocationChanged(loc: Location) {
        val acc = if (loc.hasAccuracy()) loc.accuracy.toDouble() else 99.0
        try {
            writer?.apply {
                write("${loc.time},${loc.latitude},${loc.longitude},$acc\n")
                flush()
            }
        } catch (e: Exception) {
            // Levyvirhe: live-näkymä toimii silti.
        }
        emit(mapOf("t" to loc.time, "lat" to loc.latitude, "lon" to loc.longitude, "acc" to acc))
    }

    override fun onProviderDisabled(provider: String) = emit(mapOf("status" to "disabled"))
    override fun onProviderEnabled(provider: String) = emit(mapOf("status" to "enabled"))

    @Deprecated("Vanhat Android-versiot kutsuvat tätä")
    override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}

    private fun emit(m: Map<String, Any>) {
        main.post { sink?.invoke(m) }
    }

    /** Etualalle: sijainti ja sykevyön ollessa valittuna myös connectedDevice (ks. HeartRateBle.fgsType). */
    fun foreground(n: android.app.Notification) {
        lastNote = n
        instance = this
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIFICATION, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION or HeartRateBle.fgsType(this))
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
        } else {
            startForeground(NOTIFICATION, n)
        }
    }

    override fun onDestroy() {
        instance = null
        try {
            (getSystemService(Context.LOCATION_SERVICE) as LocationManager).removeUpdates(this)
        } catch (e: Exception) {
        }
        try {
            writer?.close()
        } catch (e: Exception) {
        }
        writer = null
        running = false
        // Palvelun etualan ilmoitus poistuu; jos esim. salitreeni on yhä käynnissä, sen ilmoitus palaa.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) stopForeground(STOP_FOREGROUND_REMOVE) else @Suppress("DEPRECATION") stopForeground(true)
        OngoingNote.restore(this)
        super.onDestroy()
    }
}
