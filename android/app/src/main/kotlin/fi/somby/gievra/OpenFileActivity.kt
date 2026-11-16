package fi.somby.gievra

import android.app.Activity
import android.content.ClipData
import android.content.Intent
import android.net.Uri
import android.os.Bundle

/// "Avaa sovelluksella" ja "Jaa → Gievra" (yötesti 16.11., käyttäjä: läpikulkuaktiviteetti). Ilman tätä Android
/// käynnisti toisen MainActivityn (ja toisen Flutter-moottorin) lähettäjän tehtävään, kun Gievra oli jo käynnissä:
/// kaksi Gievraa samoissa tiedostoissa. Tämä näkymätön aktiviteetti välittää aikomuksen olemassa olevalle
/// MainActivitylle (onNewIntent) tai käynnistää sen, jos Gievra ei ole käynnissä, ja sulkeutuu heti.
class OpenFileActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val src = intent
        // Uudelleenluonti (esim. prosessi tapettu ja palautettu): ei välitetä toista kertaa.
        if (savedInstanceState == null && src != null &&
            (src.action == Intent.ACTION_VIEW || src.action == Intent.ACTION_SEND)
        ) {
            // Sama aikomus kuin käynnistimen kuvakkeella (MAIN + LAUNCHER, ei dataa), tiedosto lisätietona
            // (testikierros 16.11.): jos Gievra ei ollut käynnissä, tehtävän pohja-aikomukseksi jäi aiemmin VIEW +
            // tiedosto. Silloin Takaisin-poistumisen jälkeen kuvake teki toisen Gievra-kortin Viimeisimpiin, ja vanha
            // kortti avasi tiedoston tuonnin uudelleen (ja toisen MainActivityn ensimmäisen rinnalle).
            val uri: Uri? = when (src.action) {
                Intent.ACTION_VIEW -> src.data
                else -> {
                    @Suppress("DEPRECATION")
                    src.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                }
            }
            val fwd = Intent(Intent.ACTION_MAIN).apply {
                addCategory(Intent.CATEGORY_LAUNCHER)
                setClass(this@OpenFileActivity, MainActivity::class.java)
                putExtra(MainActivity.EXTRA_OPEN, Intent(src).apply { setClipData(null) })
                // Lukuoikeus siirtyy MainActivitylle leikepöytätiedon osoitteen mukana (tämän aktiviteetin oma lupa
                // päättyy sen sulkeutuessa).
                if (uri != null) clipData = ClipData.newRawUri("", uri)
                // NEW_TASK + CLEAR_TOP + SINGLE_TOP: käynnissä oleva Gievra tuodaan esiin ja saa tiedoston
                // onNewIntentissä; uutta MainActivitya ei luoda sen päälle.
                addFlags(
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
                )
            }
            try {
                startActivity(fwd)
            } catch (_: SecurityException) {
                // Lähettäjä ei antanut lukuoikeutta, jota voisi siirtää eteenpäin: avataan ilman, jolloin MainActivity
                // yrittää lukea omilla oikeuksillaan ja kertoo, jos tiedostoa ei voi avata (ei hiljaista umpikujaa).
                try {
                    fwd.clipData = null
                    fwd.flags = fwd.flags and Intent.FLAG_GRANT_READ_URI_PERMISSION.inv()
                    startActivity(fwd)
                } catch (_: Exception) {
                }
            } catch (_: Exception) {
            }
        }
        finish()
    }
}
