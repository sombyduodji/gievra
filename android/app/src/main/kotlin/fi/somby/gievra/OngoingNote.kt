package fi.somby.gievra

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Build
import android.os.SystemClock
import android.view.View
import android.widget.RemoteViews
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/**
 * Sovelluksen ainoa "treeni käynnissä" -ilmoitus pudotusvalikossa: laji ja kulunut aika, esim. "Salitreeni käynnissä"
 * tai "Juoksu käynnissä". Sama ilmoitus (sama tunniste) palvelee salitreeniä, liikunnan ajanottoa ja GPS-lenkkiä:
 * GPS-palvelu käyttää sitä etualan ilmoituksenaan, joten kahta ilmoitusta ei koskaan ole. Palautusajastin on oma
 * erillinen ilmoituksensa (RestAlarm). Aika kulkee Androidin omalla kellolla (chronometer), joten sovelluksen ei
 * tarvitse päivittää ilmoitusta eikä olla auki. Hiljainen ja matala tärkeys; napautus avaa sovelluksen.
 *
 * Elävä näkymä ([Live]): lajin taustakuva (sali, juoksu, kävely, muu) kuten musiikkisoittimissa, kello, syke
 * sykealueen värillä, keskisyke/maksimi/kalorit sekä tilannerivi (sali: liike ja sarjat tai palautuksen
 * lähtölaskenta; GPS: matka ja vauhti). Dart päivittää sykkeen noin 5 s välein.
 */
object OngoingNote {
    const val CHANNEL = "ongoing"
    const val ID = 4242

    /** Elävän näkymän sisältö; tyhjä merkkijono = rivi piilossa. [zone] 0–4 tai −1, [restEndMs] 0 = ei lähtölaskentaa,
     *  [restStartMs] 0 = ei kulunutta aikaa (sykkeen mukaan odotettaessa kello laskee ylöspäin tauon alusta). */
    data class Live(
        val kind: String,
        val hr: String,
        val zone: Int,
        val zoneText: String,
        val kcal: String,
        val stats: String,
        val line: String,
        val restEndMs: Long,
        val line2: String,
        val restStartMs: Long = 0L,
    ) {
        companion object {
            fun from(m: Map<*, *>?): Live? = m?.let {
                Live(
                    it["kind"] as? String ?: "other",
                    it["hr"] as? String ?: "",
                    (it["zone"] as? Number)?.toInt() ?: -1,
                    it["zoneText"] as? String ?: "",
                    it["kcal"] as? String ?: "",
                    it["stats"] as? String ?: "",
                    it["line"] as? String ?: "",
                    (it["restEnd"] as? Number)?.toLong() ?: 0L,
                    it["line2"] as? String ?: "",
                    (it["restStart"] as? Number)?.toLong() ?: 0L,
                )
            }
        }
    }

    private data class State(
        val title: String,
        val startMs: Long,
        val paused: Boolean,
        val pausedText: String,
        val channelName: String,
        val live: Live?,
    )

    /** Dartin viimeksi pyytämä tila (null = piilotettu). GPS-palvelun loppuessa ilmoitus palautetaan tähän. */
    @Volatile private var last: State? = null

    /** Lukitusnäytön versio (Dartin kielellä): vain "Treeni käynnissä" ja kello, ei sykettä, kaloreita eikä liikettä. */
    @Volatile var publicTitle: String = "Gievra"

    /** Väliaikainen ilmoitus etualan palvelun pakolliseen startForeground-kutsuun, kun treeniä ei enää ole.
     *  Kanavan nimi säilyy (build luo kanavan uudelleen annetulla nimellä). */
    fun placeholder(ctx: Context): Notification =
        build(ctx, "Gievra", System.currentTimeMillis(), true, "", channelName(ctx) ?: "Gievra")

    /** Olemassa olevan kanavan (käyttäjän kielellä luotu) nimi, tai null. */
    fun channelName(ctx: Context): String? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            ctx.getSystemService(NotificationManager::class.java).getNotificationChannel(CHANNEL)?.name?.toString()
        } else {
            null
        }

    fun build(
        ctx: Context,
        title: String,
        startMs: Long,
        paused: Boolean,
        pausedText: String,
        channelName: String,
        live: Live? = null,
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
        // Android 14+ sallii etualan palvelun ilmoituksen pyyhkäisyn: palautetaan se heti (treeni pitää sovelluksen hereillä).
        val restore = PendingIntent.getBroadcast(
            ctx, ID + 1, Intent(ctx, OngoingRestoreReceiver::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val b = NotificationCompat.Builder(ctx, CHANNEL)
            .setDeleteIntent(restore)
            .setSmallIcon(R.drawable.ic_rest)
            .setContentTitle(title)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_WORKOUT)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE) // GPS: heti, ei 10 s viiveellä
            .apply { if (open != null) setContentIntent(open) }
        val pub = NotificationCompat.Builder(ctx, CHANNEL)
            .setSmallIcon(R.drawable.ic_rest)
            .setContentTitle(publicTitle)
            .setCategory(NotificationCompat.CATEGORY_WORKOUT)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .apply { if (open != null) setContentIntent(open) }
        if (paused) pub.setShowWhen(false) else pub.setUsesChronometer(true).setWhen(startMs).setShowWhen(true)
        b.setVisibility(NotificationCompat.VISIBILITY_PRIVATE).setPublicVersion(pub.build())
        if (paused) {
            b.setContentText(pausedText).setShowWhen(false)
        } else {
            b.setUsesChronometer(true).setWhen(startMs).setShowWhen(true)
        }
        if (live != null) {
            b.setCustomContentView(views(ctx, R.layout.note_live_small, title, startMs, paused, pausedText, live))
            b.setCustomBigContentView(views(ctx, R.layout.note_live_big, title, startMs, paused, pausedText, live))
            // Android 12+ vaatii järjestelmän kehyksen; vanhemmissa kuva täyttää koko ilmoituksen.
            if (Build.VERSION.SDK_INT >= 31) b.setStyle(NotificationCompat.DecoratedCustomViewStyle())
            b.setShowWhen(false)
        }
        return b.build()
    }

    private fun views(
        ctx: Context,
        layout: Int,
        title: String,
        startMs: Long,
        paused: Boolean,
        pausedText: String,
        l: Live,
    ): RemoteViews {
        val v = RemoteViews(ctx.packageName, layout)
        val big = layout == R.layout.note_live_big
        v.setImageViewResource(
            R.id.bg,
            when (l.kind) {
                "gym" -> R.drawable.note_bg_gym
                "run" -> R.drawable.note_bg_run
                "walk" -> R.drawable.note_bg_walk
                else -> R.drawable.note_bg_other
            },
        )
        // Kello: Chronometerin pohja on käynnistyksestä laskettua aikaa (elapsedRealtime), ei seinäkelloa.
        if (paused) {
            v.setViewVisibility(R.id.clock, View.GONE)
            v.setViewVisibility(R.id.paused, View.VISIBLE)
            v.setTextViewText(R.id.paused, pausedText)
        } else {
            val base = SystemClock.elapsedRealtime() - (System.currentTimeMillis() - startMs)
            v.setViewVisibility(R.id.clock, View.VISIBLE)
            v.setViewVisibility(R.id.paused, View.GONE)
            v.setChronometer(R.id.clock, base, null, true)
        }
        text(v, R.id.hr, l.hr)
        if (l.hr.isNotEmpty()) {
            val z = l.zone
            v.setInt(R.id.hr, "setBackgroundResource", if (z in 0..4) PILLS[z] else R.drawable.note_pill)
            v.setTextColor(R.id.hr, if (z in 0..4) ZONE_FG[z] else Color.WHITE)
        }
        text(v, R.id.kcal, l.kcal)
        if (!big) return v
        text(v, R.id.title, title)
        text(v, R.id.zone, l.zoneText)
        text(v, R.id.stats, l.stats)
        text(v, R.id.line, l.line)
        val now = System.currentTimeMillis()
        val rest = l.restEndMs > now || l.restStartMs > 0
        if (l.restStartMs > 0) {
            // Sykkeen mukaan: kulunut aika tauon alusta.
            v.setViewVisibility(R.id.rest, View.VISIBLE)
            v.setChronometer(R.id.rest, SystemClock.elapsedRealtime() - (now - l.restStartMs), null, true)
            if (Build.VERSION.SDK_INT >= 24) v.setChronometerCountDown(R.id.rest, false)
        } else if (l.restEndMs > now && Build.VERSION.SDK_INT >= 24) {
            v.setViewVisibility(R.id.rest, View.VISIBLE)
            v.setChronometer(R.id.rest, SystemClock.elapsedRealtime() + (l.restEndMs - now), null, true)
            v.setChronometerCountDown(R.id.rest, true)
        } else {
            v.setViewVisibility(R.id.rest, View.GONE)
        }
        v.setViewVisibility(R.id.lineBox, if (l.line.isEmpty() && !rest) View.GONE else View.VISIBLE)
        text(v, R.id.line2, l.line2)
        return v
    }

    private fun text(v: RemoteViews, id: Int, s: String) {
        v.setViewVisibility(id, if (s.isEmpty()) View.GONE else View.VISIBLE)
        v.setTextViewText(id, s)
    }

    private val PILLS = intArrayOf(
        R.drawable.note_pill_0, R.drawable.note_pill_1, R.drawable.note_pill_2, R.drawable.note_pill_3,
        R.drawable.note_pill_4,
    )

    // Samat kuin sovelluksen sykealueiden tekstivärit (hr_ui.dart _zoneFg).
    private val ZONE_FG = intArrayOf(
        0xFF444441.toInt(), 0xFF0C447C.toInt(), 0xFF633806.toInt(), 0xFF712B13.toInt(), 0xFF791F1F.toInt(),
    )

    /** [paused]: kello pysähtyy ja tekstinä on [pausedText] (esim. "tauolla · 12:31"). */
    fun show(
        ctx: Context,
        title: String,
        startMs: Long,
        paused: Boolean,
        pausedText: String,
        channelName: String,
        live: Live? = null,
    ) {
        last = State(title, startMs, paused, pausedText, channelName, live)
        post(ctx, build(ctx, title, startMs, paused, pausedText, channelName, live))
        WorkoutService.ensure(ctx) // pitää sovelluksen hereillä treenin ajan (ks. WorkoutService)
    }

    /** Treeni-ilmoitus on pyydetty näkyviin (hide ei ole poistanut sitä). */
    val active: Boolean get() = last != null

    /** Dartin viimeksi pyytämä ilmoitus (WorkoutService käyttää sitä etualan ilmoituksenaan) tai null. */
    fun current(ctx: Context): Notification? {
        val s = last ?: return null
        return build(ctx, s.title, s.startMs, s.paused, s.pausedText, s.channelName, s.live)
    }

    fun hide(ctx: Context) {
        last = null
        WorkoutService.stop(ctx)
        NotificationManagerCompat.from(ctx).cancel(ID) // GPS-palvelun aikana Android ei poista; poistuu palvelun mukana
    }

    /** GPS-palvelu loppui (ja vei ilmoituksen mukanaan): näytetään taas Dartin viimeksi pyytämä tila, jos sellainen on. */
    fun restore(ctx: Context) {
        val s = last ?: return
        post(ctx, build(ctx, s.title, s.startMs, s.paused, s.pausedText, s.channelName, s.live))
        WorkoutService.ensure(ctx)
    }

    private fun post(ctx: Context, n: Notification) {
        try {
            NotificationManagerCompat.from(ctx).notify(ID, n)
        } catch (e: SecurityException) {
            // ei ilmoituslupaa: treeni toimii ilman ilmoitusta
        }
    }
}

/** Treeni-ilmoitus pyyhkäistiin pois kesken treenin: näytetään se uudelleen (ks. OngoingNote.build). */
class OngoingRestoreReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        if (OngoingNote.active) OngoingNote.restore(ctx)
    }
}
