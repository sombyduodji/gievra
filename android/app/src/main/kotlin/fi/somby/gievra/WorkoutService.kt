package fi.somby.gievra

import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Treeni käynnissä: sama treeni-ilmoitus (OngoingNote) etualan palveluna, jottei puhelin jäädytä sovellusta taustalla
 * (esim. Samsungin Freecess jäädytti sovelluksen 30 s kuluttua, jolloin palautusajastimen hälytys ei tullut eikä
 * sykevyön lukemia saatu). Ei uutta ilmoitusta: palvelu käyttää treenin omaa ilmoitusta ja päättyy treenin mukana.
 * GPS-lenkin aikana GpsService omistaa saman ilmoituksen, ja tämä palvelu odottaa.
 */
class WorkoutService : Service() {
    companion object {
        @Volatile var running = false

        /** Käynnistää palvelun, jos treeni-ilmoitus näkyy eikä GPS-palvelu jo pidä sovellusta hereillä. */
        fun ensure(ctx: Context) {
            if (running || GpsService.running) return
            val i = Intent(ctx, WorkoutService::class.java)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) ctx.startForegroundService(i) else ctx.startService(i)
            } catch (e: Exception) {
                // Taustalta ei voi käynnistää (Android 12+): ilmoitus näkyy silti, palvelu käynnistyy seuraavalla kerralla.
            }
        }

        @Volatile private var instance: WorkoutService? = null

        /** Sykevyö yhdistyi tai katkesi: etualan tyyppi uudelleen (connectedDevice mukaan tai pois). */
        fun refreshType(ctx: Context) {
            val s = instance ?: return
            val n = OngoingNote.current(ctx) ?: return
            try {
                s.foreground(n)
            } catch (_: Exception) {
                // Androidin rajoitus (esim. tyyppi ei sallittu tässä tilassa): palvelu jatkaa entisellä tyypillä.
            }
        }

        fun stop(ctx: Context) {
            if (running) ctx.stopService(Intent(ctx, WorkoutService::class.java))
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // startForegroundService() vaatii startForeground()-kutsun aina, myös kun palvelua ei enää tarvita: muuten
        // Android kaataa sovelluksen ("did not then call Service.startForeground()"). Näin kävi, kun GPS-palvelu
        // ehti käynnistyä tämän käynnistyksen ja onStartCommandin väliin (päivätesti 14.11., Android 11).
        val current = OngoingNote.current(this)
        val n = current ?: OngoingNote.placeholder(this)
        try {
            foreground(n)
        } catch (e: Exception) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (current == null || GpsService.running) {
            // Ei treeniä (ilmoitus pois) tai GPS-palvelu pitää jo saman ilmoituksen (se jää näkyviin).
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(if (current == null) STOP_FOREGROUND_REMOVE else STOP_FOREGROUND_DETACH)
            } else {
                @Suppress("DEPRECATION") stopForeground(current == null)
            }
            stopSelf()
            return START_NOT_STICKY
        }
        running = true
        instance = this
        // Jos Android lopettaa sovelluksen, palvelua ei käynnistetä uudelleen (treenin tila on sovelluksessa).
        return START_NOT_STICKY
    }

    /** Etualalle; sykevyön ollessa valittuna myös connectedDevice (Bluetooth taustalla, ks. HeartRateBle.fgsType). */
    fun foreground(n: android.app.Notification) {
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(OngoingNote.ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE or HeartRateBle.fgsType(this))
        } else {
            // Android 13 ja vanhemmat: manifestin tyypit (specialUse ja connectedDevice) sellaisinaan.
            startForeground(OngoingNote.ID, n)
        }
    }

    override fun onDestroy() {
        running = false
        instance = null
        // Treeni päättyi: ilmoitus pois (etualan palvelun ilmoitusta ei voi perua muualta). GPS-lenkki alkoi: ilmoitus
        // jää, ja GPS-palvelu ottaa sen.
        val keep = OngoingNote.active
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(if (keep) STOP_FOREGROUND_DETACH else STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION") stopForeground(!keep)
        }
        super.onDestroy()
    }
}
