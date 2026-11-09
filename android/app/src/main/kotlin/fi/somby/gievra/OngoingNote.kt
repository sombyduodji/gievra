package fi.somby.gievra

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/**
 * Sovelluksen ainoa "treeni käynnissä" -ilmoitus pudotusvalikossa: laji ja kulunut aika, esim. "Salitreeni käynnissä"
 * tai "Juoksu käynnissä". Sama ilmoitus (sama tunniste) palvelee salitreeniä, liikunnan ajanottoa ja GPS-lenkkiä:
 * GPS-palvelu käyttää sitä etualan ilmoituksenaan, joten kahta ilmoitusta ei koskaan ole. Palautusajastin on oma
 * erillinen ilmoituksensa (RestAlarm). Aika kulkee Androidin omalla kellolla (chronometer), joten sovelluksen ei
 * tarvitse päivittää ilmoitusta eikä olla auki. Hiljainen ja matala tärkeys; napautus avaa sovelluksen.
 */
object OngoingNote {
    const val CHANNEL = "ongoing"
    const val ID = 4242

    private data class State(
        val title: String,
        val startMs: Long,
        val paused: Boolean,
        val pausedText: String,
        val channelName: String,
    )

    /** Dartin viimeksi pyytämä tila (null = piilotettu). GPS-palvelun loppuessa ilmoitus palautetaan tähän. */
    @Volatile private var last: State? = null

    fun build(
        ctx: Context,
        title: String,
        startMs: Long,
        paused: Boolean,
        pausedText: String,
        channelName: String,
    ): Notification {
        val nm = ctx.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(CHANNEL, channelName, NotificationManager.IMPORTANCE_LOW)
            ch.setShowBadge(false)
            nm.createNotificationChannel(ch)
            nm.deleteNotificationChannel("gps_recording") // 0.4.2:n erillinen GPS-ilmoitus
        }
        val open = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)?.let {
            PendingIntent.getActivity(ctx, ID, it, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        }
        val b = NotificationCompat.Builder(ctx, CHANNEL)
            .setSmallIcon(R.drawable.ic_rest)
            .setContentTitle(title)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_WORKOUT)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE) // GPS: heti, ei 10 s viiveellä
            .apply { if (open != null) setContentIntent(open) }
        if (paused) {
            b.setContentText(pausedText).setShowWhen(false)
        } else {
            b.setUsesChronometer(true).setWhen(startMs).setShowWhen(true)
        }
        return b.build()
    }

    /** [paused]: kello pysähtyy ja tekstinä on [pausedText] (esim. "tauolla · 12:31"). */
    fun show(ctx: Context, title: String, startMs: Long, paused: Boolean, pausedText: String, channelName: String) {
        last = State(title, startMs, paused, pausedText, channelName)
        post(ctx, build(ctx, title, startMs, paused, pausedText, channelName))
    }

    fun hide(ctx: Context) {
        last = null
        NotificationManagerCompat.from(ctx).cancel(ID) // GPS-palvelun aikana Android ei poista; poistuu palvelun mukana
    }

    /** GPS-palvelu loppui (ja vei ilmoituksen mukanaan): näytetään taas Dartin viimeksi pyytämä tila, jos sellainen on. */
    fun restore(ctx: Context) {
        val s = last ?: return
        post(ctx, build(ctx, s.title, s.startMs, s.paused, s.pausedText, s.channelName))
    }

    private fun post(ctx: Context, n: Notification) {
        try {
            NotificationManagerCompat.from(ctx).notify(ID, n)
        } catch (e: SecurityException) {
            // ei ilmoituslupaa: treeni toimii ilman ilmoitusta
        }
    }
}
