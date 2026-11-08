package fi.somby.gievra

import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
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
import androidx.core.app.NotificationCompat
import java.io.File
import java.io.FileWriter

/// Reitin tallennus: Androidin oma GPS (LocationManager, ei Googlen palveluita) kerran sekunnissa
/// etualapalveluna, joten tallennus jatkuu näytön sammuessa ja toisessa sovelluksessa. Jokainen paikannus
/// kirjoitetaan heti tiedostoon (gps-recording.csv), joten lenkki ei katoa, vaikka Android sulkisi sovelluksen;
/// Dart lukee tiedoston ja suodattaa reitin (lib/gps_filter.dart). Mitään ei lähetetä minnekään.
class GpsService : Service(), LocationListener {
    companion object {
        const val NOTIFICATION = 4720
        const val CHANNEL = "gps_recording"

        /// Dartin kuuntelija (EventChannel); null, kun sovellus ei ole auki.
        @Volatile var sink: ((Map<String, Any>) -> Unit)? = null
        @Volatile var running = false

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
        val channelName = intent?.getStringExtra("channel") ?: "GPS"
        val nm = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(CHANNEL, channelName, NotificationManager.IMPORTANCE_LOW)
            ch.setShowBadge(false)
            nm.createNotificationChannel(ch)
        }
        val open = packageManager.getLaunchIntentForPackage(packageName)?.let {
            PendingIntent.getActivity(this, NOTIFICATION, it, PendingIntent.FLAG_IMMUTABLE)
        }
        val n = NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_rest)
            .setContentTitle(title)
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_WORKOUT)
            .apply { if (open != null) setContentIntent(open) }
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
        } else {
            startForeground(NOTIFICATION, n)
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

    override fun onDestroy() {
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
        super.onDestroy()
    }
}
