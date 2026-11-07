package fi.somby.gievra

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/// Palautusajastin: tarkka hälytys (AlarmManager), joka näyttää ilmoituksen äänellä ja värinällä myös silloin,
/// kun näyttö on pois päältä tai käyttäjä on toisessa sovelluksessa. Ääni valitaan asetuksista; jokaisella
/// äänellä on oma ilmoituskanava, koska kanavan ääntä ei voi muuttaa jälkikäteen.
object RestAlarm {
    private const val REQUEST = 4711
    private const val NOTIFICATION = 4712
    val sounds = mapOf("pling" to R.raw.rest_pling, "boop" to R.raw.rest_boop, "chime" to R.raw.rest_chime)
    private val vibration = longArrayOf(0, 250, 150, 250)

    private fun channelId(sound: String) = "rest_$sound"

    /// Kanavan nimi ja kuvaus tulevat sovelluksen kielellä (suomi / pohjoissaame); ne päivittyvät, ääni ei.
    var channelName = "Palautus ohi"
    var channelDesc = "Palautusajastin: sarjojen välinen tauko on ohi"

    private fun ensureChannel(ctx: Context, sound: String) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = ctx.getSystemService(NotificationManager::class.java)
        val label = "$channelName · $sound"
        nm.getNotificationChannel(channelId(sound))?.let {
            if (it.name != label || it.description != channelDesc) {
                it.name = label
                it.description = channelDesc
                nm.createNotificationChannel(it) // nimen ja kuvauksen päivitys
            }
            return
        }
        val ch = NotificationChannel(channelId(sound), label, NotificationManager.IMPORTANCE_HIGH)
        ch.description = channelDesc
        ch.enableVibration(true)
        ch.vibrationPattern = vibration
        val res = sounds[sound]
        if (res == null) {
            ch.setSound(null, null) // vain värinä
        } else {
            val uri = Uri.parse("${ContentResolver.SCHEME_ANDROID_RESOURCE}://${ctx.packageName}/$res")
            val attrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION_EVENT)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            ch.setSound(uri, attrs)
        }
        nm.createNotificationChannel(ch)
    }

    private fun alarmIntent(ctx: Context, title: String, body: String, sound: String): PendingIntent {
        val i = Intent(ctx, RestAlarmReceiver::class.java)
            .putExtra("title", title)
            .putExtra("body", body)
            .putExtra("sound", sound)
        return PendingIntent.getBroadcast(
            ctx, REQUEST, i, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    fun schedule(ctx: Context, seconds: Int, title: String, body: String, sound: String) {
        ensureChannel(ctx, sound)
        val am = ctx.getSystemService(AlarmManager::class.java)
        val at = System.currentTimeMillis() + seconds * 1000L
        val pi = alarmIntent(ctx, title, body, sound)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !am.canScheduleExactAlarms()) {
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi) // ei tarkkaa lupaa: voi myöhästyä hieman
        } else {
            am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
        }
    }

    fun cancel(ctx: Context) {
        val am = ctx.getSystemService(AlarmManager::class.java)
        am.cancel(alarmIntent(ctx, "", "", ""))
        NotificationManagerCompat.from(ctx).cancel(NOTIFICATION)
    }

    fun show(ctx: Context, title: String, body: String, sound: String) {
        ensureChannel(ctx, sound)
        val open = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)?.let {
            PendingIntent.getActivity(ctx, REQUEST + 1, it, PendingIntent.FLAG_IMMUTABLE)
        }
        val n = NotificationCompat.Builder(ctx, channelId(sound))
            .setSmallIcon(R.drawable.ic_rest)
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVibrate(vibration)
            .setAutoCancel(true)
            .setTimeoutAfter(60_000)
            .apply { if (open != null) setContentIntent(open) }
            .build()
        try {
            NotificationManagerCompat.from(ctx).notify(NOTIFICATION, n)
        } catch (e: SecurityException) {
            // Ilmoituslupa puuttuu: sovelluksen sisäinen ilmoitus riittää.
        }
    }
}

class RestAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        RestAlarm.show(
            ctx,
            intent.getStringExtra("title") ?: "Gievra",
            intent.getStringExtra("body") ?: "",
            intent.getStringExtra("sound") ?: "pling",
        )
    }
}
