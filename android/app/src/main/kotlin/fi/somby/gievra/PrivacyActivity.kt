package fi.somby.gievra

import android.app.Activity
import android.graphics.Typeface
import android.os.Bundle
import android.util.TypedValue
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/// Health Connectin "Tietosuojakäytäntö" / "Miksi sovellus pyytää lupia" (yötesti 18.11.: linkki avasi Gievran
/// Health Connectin taakse, eikä mitään näkynyt). Kevyt natiivinäkymä Health Connectin omassa tehtävässä: ei
/// Flutter-moottoria, joten se aukeaa heti eikä sekoita käynnissä olevaa treeniä. Kieli sama kuin sovelluksessa
/// (SharedPreferences "flutter.lang"). Jos kieltä ei ole tallennettu, sovellus on suomeksi (lib/app_state.dart
/// lukee oletuksena 'fi'), joten tämäkin on suomeksi: ennen laitteen kieli, ja englanninkielisellä puhelimella
/// näkymä oli englanniksi suomenkielisen sovelluksen keskellä (Nothing-testi 18.11.).
class PrivacyActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val lang = try {
            getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE).getString("flutter.lang", null)
        } catch (_: Exception) {
            null
        } ?: "fi"
        val t = privacyTexts[lang] ?: privacyTexts["fi"]!!
        val dp = { v: Int -> TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v.toFloat(), resources.displayMetrics).toInt() }
        val col = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(24), dp(20), dp(24))
        }
        col.addView(TextView(this).apply {
            text = t.title
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 22f)
            setTypeface(typeface, Typeface.BOLD)
            isFocusable = true
            if (android.os.Build.VERSION.SDK_INT >= 28) isAccessibilityHeading = true
        })
        for ((i, p) in t.paragraphs.withIndex()) {
            col.addView(TextView(this).apply {
                text = p
                setTextSize(TypedValue.COMPLEX_UNIT_SP, if (i == 0) 17f else 16f)
                setPadding(0, dp(if (p.startsWith("•")) 6 else 14), 0, 0)
                setLineSpacing(0f, 1.15f)
            })
        }
        col.addView(Button(this).apply {
            text = t.close
            setOnClickListener { finish() }
        }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
            topMargin = dp(20)
        })
        val scroll = ScrollView(this).apply {
            addView(col)
            fitsSystemWindows = true
        }
        setContentView(scroll)
        title = t.title
        actionBar?.hide()
        // Ei yläpalkkia (otsikko oli kahdesti, testi 18.11.); vaaleassa teemassa tummat tilarivin kuvakkeet.
        val night = (resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK) ==
            android.content.res.Configuration.UI_MODE_NIGHT_YES
        if (!night && android.os.Build.VERSION.SDK_INT >= 30) {
            window.insetsController?.setSystemBarsAppearance(
                android.view.WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS or
                    android.view.WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS,
                android.view.WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS or
                    android.view.WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS,
            )
        }
    }
}

class PrivacyText(val title: String, val paragraphs: List<String>, val close: String)

/// Sama sisältö kuin sovelluksen Lisää → Tietoja → Tietosuoja (pidä samana). Saamen tarkistaa puhuja.
val privacyTexts = mapOf(
    "fi" to PrivacyText(
        "Gievra ja terveystiedot",
        listOf(
            "Gievra lukee Health Connectista vain ne tiedot, joihin annat luvan, ja vain niihin toimintoihin, jotka itse otat käyttöön:",
            "• Liikunta, syke, kalorit ja matka: kellon tai sykemittarin treenien tuonti ja treenin sykekäyrä.",
            "• Askeleet: päivän askeleet ja askeltavoite.",
            "• Uni: Uni-kortti (oletuksena pois).",
            "• Sykevälivaihtelu (HRV), hengitystiheys, happisaturaatio ja ihon lämpötila: yöarvot Palautuminen-kortissa (oletuksena pois).",
            "• Yön syke: Palautuminen-kortti (oletuksena pois).",
            "• Historia: vanhemmat askeleet ja unet vain, kun itse pyydät.",
            "Tiedot tallentuvat vain valitsemaasi kansioon tavallisina tiedostoina (treenit, askeleet.md, uni.md). Gievra ei kirjoita Health Connectiin.",
            "Sovelluksessa ei ole tiliä, mainoksia eikä analytiikkaa, eikä se lähetä tietoja minnekään. Varmuuskopiot ja jakaminen tehdään vain, kun itse teet ne.",
            "Luvat voi perua milloin tahansa Health Connectin asetuksista. Jo tallennetut tiedot jäävät kansioosi, josta voit poistaa ne.",
        ),
        "Sulje",
    ),
    "en" to PrivacyText(
        "Gievra and health data",
        listOf(
            "Gievra reads from Health Connect only the data you allow, and only for features you turn on yourself:",
            "• Exercise, heart rate, calories and distance: importing workouts from a watch or heart rate monitor, and the workout heart rate graph.",
            "• Steps: daily steps and the steps goal.",
            "• Sleep: the Sleep card (off by default).",
            "• Heart rate variability (HRV), breathing rate, oxygen saturation and skin temperature: night metrics in the Recovery card (off by default).",
            "• Night heart rate: the Recovery card (off by default).",
            "• History: older steps and sleep only when you ask for them.",
            "The data is saved only in the folder you chose, as plain files (workouts, askeleet.md, uni.md). Gievra does not write to Health Connect.",
            "The app has no account, ads or analytics, and it sends no data anywhere. Backups and sharing happen only when you do them yourself.",
            "You can revoke the permissions at any time in Health Connect settings. Data already saved stays in your folder, where you can delete it.",
        ),
        "Close",
    ),
    "se" to PrivacyText(
        "Gievra ja dearvvašvuođadieđut",
        listOf(
            "Gievra lohká Health Connectas dušše daid dieđuid, maidda don addát lobi, ja dušše daid doaimmaid várás, maid ieš váldát atnui:",
            "• Lihkadeapmi, pulsa, kaloriijat ja gaska: diimmu dahje pulsamihttára hárjehallamiid sisafievrrideapmi ja hárjehallama pulsakurva.",
            "• Lávkkit: beaivvi lávkkit ja lávkemihttu.",
            "• Oađđin: Oađđin-kárta (álgoárvu eret).",
            "• HRV, vuoiŋŋahanfrekveansa, oksygenašuvdna ja liikki temperatuvra: ijaárvvut Vuoiŋŋasteapmi-kárttas (álgoárvu eret).",
            "• Ija pulsa: Vuoiŋŋasteapmi-kárta (álgoárvu eret).",
            "• Historjá: boarráset lávkkit ja oađđimat dušše go ieš bivddát.",
            "Dieđut vurkejuvvojit dušše dan máhppii, man don válljet, dábálaš fiilan (hárjehallamat, askeleet.md, uni.md). Gievra ii čále Health Connectii.",
            "Prográmmas ii leat konto, ii reklámat iige dieđuid čohkken, iige dat sádde dieđuid gosage. Sihkkarastinmáŋggus ja juogadeapmi dahkkojit dušše go ieš dagat daid.",
            "Sáhtát geassit lobiid ruovttoluotta goas beare Health Connecta ásahusain. Juo vurkejuvvon dieđut bissot du máhpas, gos sáhtát sihkkut daid.",
        ),
        "Gidde",
    ),
)
