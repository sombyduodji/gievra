package fi.somby.gievra

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.DistanceRecord
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.records.HeartRateRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.records.TotalCaloriesBurnedRecord
import androidx.health.connect.client.records.metadata.DataOrigin
import androidx.health.connect.client.records.metadata.Metadata
import androidx.health.connect.client.request.AggregateRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import androidx.health.connect.client.units.Energy
import androidx.health.connect.client.units.Length
import java.time.Duration
import java.time.Instant
import java.time.ZoneOffset

/**
 * Health Connect (Android): vain luku, vain pyydettäessä ja vain treenin aikaväliltä. Gievra ei tuo kaikkea
 * historiaa: käyttäjä painaa treenin jälkeen "Health Connect", ja tästä haetaan aikaväliä lähellä olevat
 * harjoitukset (kellon sovellus kirjoittaa ne Health Connectiin) sykkeineen ja kaloreineen. Tiedot pysyvät
 * laitteella; mitään ei lähetetä verkkoon.
 */
object HealthBridge {
    /** Luettavat tiedot: harjoitukset, syke, kokonaiskalorit ja askeleet. */
    val readPermissions = setOf(
        HealthPermission.getReadPermission(ExerciseSessionRecord::class),
        HealthPermission.getReadPermission(HeartRateRecord::class),
        HealthPermission.getReadPermission(TotalCaloriesBurnedRecord::class),
        HealthPermission.getReadPermission(StepsRecord::class),
    )

    /** Tehdyn liikunnan lisääminen (asetus, oletus pois): lisäksi matka. Kysytään vasta, kun toimintoa käytetään. */
    val importPermissions = readPermissions + HealthPermission.getReadPermission(DistanceRecord::class)

    /** Kehitysversion testitiedot emulaattorille (vain debug-manifestissa on kirjoitusluvat). */
    val writePermissions = setOf(
        HealthPermission.getWritePermission(ExerciseSessionRecord::class),
        HealthPermission.getWritePermission(HeartRateRecord::class),
        HealthPermission.getWritePermission(TotalCaloriesBurnedRecord::class),
        HealthPermission.getWritePermission(StepsRecord::class),
        HealthPermission.getWritePermission(DistanceRecord::class),
    )

    /** available, update (Health Connect -sovellus pitää asentaa tai päivittää) tai unavailable. */
    fun status(context: Context): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return "unavailable"
        return when (HealthConnectClient.getSdkStatus(context)) {
            HealthConnectClient.SDK_AVAILABLE -> "available"
            HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED -> "update"
            else -> "unavailable"
        }
    }

    fun client(context: Context) = HealthConnectClient.getOrCreate(context)

    suspend fun granted(context: Context): Set<String> = client(context).permissionController.getGrantedPermissions()

    /** Puhelimen oma askelmittari (Android 14+): ei sovellusta, Dart kääntää merkinnän (@phone). */
    private fun appLabel(context: Context, pkg: String): String =
        if (pkg.startsWith("com.android.healthconnect.phone")) "@phone" else appLabelOf(context, pkg)

    private fun appLabelOf(context: Context, pkg: String): String = try {
        val pm = context.packageManager
        pm.getApplicationLabel(pm.getApplicationInfo(pkg, PackageManager.ApplicationInfoFlags.of(0))).toString()
    } catch (e: Throwable) {
        try {
            @Suppress("DEPRECATION")
            context.packageManager.getApplicationLabel(context.packageManager.getApplicationInfo(pkg, 0)).toString()
        } catch (e2: Throwable) {
            pkg
        }
    }

    /**
     * Syke (keskiarvo, maksimi), kalorit, askeleet ja matka aikaväliltä.
     *
     * [origin] = harjoituksen tallentaneen sovelluksen paketti. Askeleet, matka ja kalorit luetaan ensin saman
     * sovelluksen tietueista (osuus aikavälille), koska Health Connectin kokonaissumma poistaa päällekkäisyydet
     * sovellusten etusijan mukaan: esim. kävelymaton sovelluksen 12 058 askelta korvautuisivat puhelimen samalla
     * ajalla laskemilla muutamalla askeleella. Jos sovellus ei tallentanut niitä, käytetään kokonaissummaa.
     */
    private suspend fun stats(context: Context, start: Instant, end: Instant, origin: String? = null): Map<String, Any?> {
        val c = client(context)
        val hr = c.readRecords(
            ReadRecordsRequest(HeartRateRecord::class, TimeRangeFilter.between(start, end), pageSize = 5000),
        ).records.flatMap { r -> r.samples.filter { !it.time.isBefore(start) && !it.time.isAfter(end) } }
        val span = TimeRangeFilter.between(start, end)
        val origins = if (origin == null) emptySet() else setOf(DataOrigin(origin))

        /**
         * Saman sovelluksen tietueiden summa aikavälillä ilman päällekkäisyyksiä: kukin tietue vain siltä osin, jota
         * aiemmin lasketut eivät jo kata (sovellus voi tallentaa sekä koko harjoituksen summan että minuuttikohtaiset
         * tietueet). Arvo jaetaan tietueen ajalle tasaisesti. Lasketaan kahdessa järjestyksessä (pisin ensin ja lyhin
         * ensin) ja valitaan suurempi: pitkä, harva tietue (esim. Oura) ei saa peittää minuuttitietoja, eikä toisaalta
         * koko harjoituksen summa jää pois, jos minuuttitietoja on vain osalta ajasta.
         */
        fun sumOnce(
            items: List<Triple<Instant, Instant, Double>>,
            from: Instant = start,
            to: Instant = end,
        ): Double {
            fun pass(ordered: List<Triple<Instant, Instant, Double>>): Double {
                val covered = mutableListOf<Pair<Long, Long>>()
                var total = 0.0
                for ((rs, re, v) in ordered) {
                    val a = maxOf(rs, from).toEpochMilli()
                    val b = minOf(re, to).toEpochMilli()
                    if (b <= a) continue
                    // Peittämätön osa: yhdistetään jo katetut välit, jotta päällekkäiset eivät vähennä kahdesti.
                    var free = b - a
                    var cur = a
                    for ((ca, cb) in covered.sortedBy { it.first }) {
                        val s0 = maxOf(cur, ca)
                        val e0 = minOf(b, cb)
                        if (e0 > s0) {
                            free -= e0 - s0
                            cur = e0
                        }
                    }
                    val len = re.toEpochMilli() - rs.toEpochMilli()
                    total += if (len <= 0) (if (free > 0) v else 0.0) else v * maxOf(0L, free).toDouble() / len
                    covered += a to b
                }
                return total
            }
            val dur = { t: Triple<Instant, Instant, Double> -> t.second.toEpochMilli() - t.first.toEpochMilli() }
            return maxOf(pass(items.sortedByDescending(dur)), pass(items.sortedBy(dur)))
        }

        suspend fun ownSteps(): Long? = if (origins.isEmpty()) null else try {
            val rs = c.readRecords(ReadRecordsRequest(StepsRecord::class, span, dataOriginFilter = origins, pageSize = 5000))
            sumOnce(rs.records.map { Triple(it.startTime, it.endTime, it.count.toDouble()) }).toLong().takeIf { it > 0 }
        } catch (e: Throwable) {
            null
        }

        suspend fun ownMeters(): Double? = if (origins.isEmpty()) null else try {
            val rs = c.readRecords(ReadRecordsRequest(DistanceRecord::class, span, dataOriginFilter = origins, pageSize = 5000))
            sumOnce(rs.records.map { Triple(it.startTime, it.endTime, it.distance.inMeters) }).takeIf { it > 0 }
        } catch (e: Throwable) {
            null
        }

        suspend fun ownKcal(): Double? = if (origins.isEmpty()) null else try {
            val rs = c.readRecords(
                ReadRecordsRequest(TotalCaloriesBurnedRecord::class, span, dataOriginFilter = origins, pageSize = 5000),
            )
            sumOnce(rs.records.map { Triple(it.startTime, it.endTime, it.energy.inKilocalories) }).takeIf { it > 0 }
        } catch (e: Throwable) {
            null
        }

        val kcal = ownKcal() ?: try {
            c.aggregate(AggregateRequest(setOf(TotalCaloriesBurnedRecord.ENERGY_TOTAL), span))[
                TotalCaloriesBurnedRecord.ENERGY_TOTAL
            ]?.inKilocalories
        } catch (e: Throwable) {
            null
        }
        // Askeleet: jokaisen sovelluksen tietueet erikseen (päällekkäisyydet poistettuina) ja suurin summa. Health
        // Connectin kokonaissumma ei riitä: se laskee vain prioriteettilistan sovellukset (Oura: 69 askelta, vaikka
        // minuuttitietueita oli 1 075). Kävelymatto: oma 12 058 > puhelimen 111.
        var stepRecords: List<StepsRecord> = emptyList()
        suspend fun stepsBySource(): Map<String, Double> = try {
            val all = mutableListOf<StepsRecord>()
            var token: String? = null
            do {
                val r = c.readRecords(ReadRecordsRequest(StepsRecord::class, span, pageSize = 5000, pageToken = token))
                all += r.records
                token = r.pageToken
            } while (token != null && all.size < 50000)
            stepRecords = all
            all.groupBy { it.metadata.dataOrigin.packageName }
                .mapValues { (_, rs) -> sumOnce(rs.map { Triple(it.startTime, it.endTime, it.count.toDouble()) }) }
        } catch (e: Throwable) {
            emptyMap()
        }
        val bySource = stepsBySource()

        // Koko aikaväli minuuteittain: kunkin minuutin askeleet siltä sovellukselta, joka laski eniten, ja minuutit
        // yhteen. Oikea summa myös, kun osan ajasta laski Oura ja osan puhelin; samaa minuuttia ei lasketa kahdesti.
        fun perMinuteBest(): Double {
            val bySrc = stepRecords.groupBy { it.metadata.dataOrigin.packageName }.values
                .map { rs -> rs.map { Triple(it.startTime, it.endTime, it.count.toDouble()) } }
            if (bySrc.isEmpty()) return 0.0
            var t = start
            var sum = 0.0
            while (t.isBefore(end)) {
                val next = minOf(t.plusSeconds(60), end)
                sum += bySrc.maxOf { sumOnce(it, t, next) }
                t = next
            }
            return sum
        }
        val minuteBest = if (Duration.between(start, end).toHours() <= 12) perMinuteBest() else 0.0
        val own = ownSteps()
        val total = try {
            c.aggregate(AggregateRequest(setOf(StepsRecord.COUNT_TOTAL), span))[StepsRecord.COUNT_TOTAL]
        } catch (e: Throwable) {
            null
        }
        val steps = (listOfNotNull(own?.toDouble(), total?.toDouble(), minuteBest) + bySource.values)
            .maxOrNull()?.takeIf { it > 0 }?.toLong()
        val meters = ownMeters() ?: try {
            c.aggregate(AggregateRequest(setOf(DistanceRecord.DISTANCE_TOTAL), span))[DistanceRecord.DISTANCE_TOTAL]
                ?.inMeters
        } catch (e: Throwable) {
            null // ei lupaa matkaan tai ei tietoa
        }
        return mapOf(
            "meters" to meters,
            "steps" to steps?.toInt(),
            // Vianetsintään: askeleet sovelluksittain ja Health Connectin kokonaissumma.
            "stepsBySource" to bySource.map { (k, v) -> "${appLabel(context, k)}: ${v.toLong()}" }.joinToString(", ") +
                (if (minuteBest > 0) ", minuuteittain paras: ${minuteBest.toLong()}" else "") +
                (if (total != null) ", Health Connect yhteensä: $total" else ""),
            "hrAvg" to if (hr.isEmpty()) null else hr.map { it.beatsPerMinute }.average().toInt(),
            "hrMax" to hr.maxOfOrNull { it.beatsPerMinute }?.toInt(),
            "hrCount" to hr.size,
            "kcal" to kcal?.toInt(),
        )
    }

    /**
     * Ehdokkaat treenille [startMs, endMs]: Health Connectin harjoitukset 3 tunnin sisällä (lähin ensin Dartissa)
     * sekä pelkkä sykedata treenin omalta ajalta (jos kello tallensi sykkeen ilman harjoitusta).
     */
    suspend fun candidates(context: Context, startMs: Long, endMs: Long): List<Map<String, Any?>> {
        val start = Instant.ofEpochMilli(startMs)
        val end = Instant.ofEpochMilli(endMs)
        val window = TimeRangeFilter.between(start.minusSeconds(3 * 3600), end.plusSeconds(3 * 3600))
        val sessions = client(context).readRecords(ReadRecordsRequest(ExerciseSessionRecord::class, window)).records
        val out = mutableListOf<Map<String, Any?>>()
        for (s in sessions) {
            out += mapOf(
                "kind" to "session",
                "start" to s.startTime.toEpochMilli(),
                "end" to s.endTime.toEpochMilli(),
                "title" to s.title,
                "type" to s.exerciseType,
                "app" to appLabel(context, s.metadata.dataOrigin.packageName),
            ) + stats(context, s.startTime, s.endTime, s.metadata.dataOrigin.packageName)
        }
        val own = stats(context, start, end)
        if ((own["hrCount"] as Int) > 0) {
            out += mapOf("kind" to "heartRate", "start" to startMs, "end" to endMs, "app" to "") + own
        }
        return out
    }

    /**
     * Tehty liikunta päivältä [startMs, endMs): Health Connectin harjoitukset, jotka alkavat välillä, tunnisteineen
     * (Gievra ei näytä jo lisättyjä) ja harjoituksen ajan syke, kalorit, askeleet ja matka.
     */
    suspend fun sessions(context: Context, startMs: Long, endMs: Long): List<Map<String, Any?>> {
        val start = Instant.ofEpochMilli(startMs)
        val end = Instant.ofEpochMilli(endMs)
        val records = client(context).readRecords(
            ReadRecordsRequest(ExerciseSessionRecord::class, TimeRangeFilter.between(start.minusSeconds(86400), end)),
        ).records.filter { !it.startTime.isBefore(start) && it.startTime.isBefore(end) }
        return records.sortedBy { it.startTime }.map { s ->
            mapOf(
                "kind" to "session",
                "id" to s.metadata.id,
                "start" to s.startTime.toEpochMilli(),
                "end" to s.endTime.toEpochMilli(),
                "title" to s.title,
                "type" to s.exerciseType,
                "app" to appLabel(context, s.metadata.dataOrigin.packageName),
            ) + stats(context, s.startTime, s.endTime, s.metadata.dataOrigin.packageName)
        }
    }

    /**
     * Päivän askeltietueet sellaisinaan (Gievra etsii niistä yhtenäiset kävelyt ilman harjoitusta, lib/health.dart):
     * alku, loppu, askeleet ja tallentanut sovellus.
     */
    suspend fun stepRecords(context: Context, startMs: Long, endMs: Long): List<Map<String, Any?>> {
        val span = TimeRangeFilter.between(Instant.ofEpochMilli(startMs), Instant.ofEpochMilli(endMs))
        val out = mutableListOf<Map<String, Any?>>()
        var token: String? = null
        val labels = mutableMapOf<String, String>()
        do {
            val r = client(context).readRecords(ReadRecordsRequest(StepsRecord::class, span, pageSize = 5000, pageToken = token))
            for (x in r.records) {
                val pkg = x.metadata.dataOrigin.packageName
                out += mapOf(
                    "start" to x.startTime.toEpochMilli(),
                    "end" to x.endTime.toEpochMilli(),
                    "count" to x.count,
                    "pkg" to pkg,
                    "app" to labels.getOrPut(pkg) { appLabel(context, pkg) },
                )
            }
            token = r.pageToken
        } while (token != null && out.size < 50000)
        return out
    }

    /** Aikavälin syke, kalorit, askeleet ja matka sovellukselta [pkg] (askelista tehty liikunta). */
    suspend fun rangeStats(context: Context, startMs: Long, endMs: Long, pkg: String?): Map<String, Any?> =
        stats(context, Instant.ofEpochMilli(startMs), Instant.ofEpochMilli(endMs), pkg)

    /** Kehitysversio: keksitty harjoitus sykkeineen emulaattorin testaukseen. */
    suspend fun debugInsert(context: Context, startMs: Long, endMs: Long, type: Int, bpm: Int) {
        val start = Instant.ofEpochMilli(startMs)
        val end = Instant.ofEpochMilli(endMs)
        val zone = ZoneOffset.systemDefault().rules.getOffset(start)
        val samples = generateSequence(start) { it.plusSeconds(30) }.takeWhile { it.isBefore(end) }
            .mapIndexed { i, t -> HeartRateRecord.Sample(t, (bpm + (i % 9) * 3 - 12).toLong()) }.toList()
        val meta = Metadata.manualEntry()
        if (type < 0) {
            // Pelkät askeleet minuutin tietueina (kävelymatto ilman harjoitusta), tahti [bpm] askelta minuutissa.
            val steps = generateSequence(start) { it.plusSeconds(60) }.takeWhile { it.isBefore(end) }
                .map { StepsRecord(it, zone, it.plusSeconds(60), zone, bpm.toLong(), meta) }.toList()
            client(context).insertRecords(steps)
            return
        }
        client(context).insertRecords(
            listOf(
                ExerciseSessionRecord(start, zone, end, zone, meta, type, "Testi"),
                HeartRateRecord(start, zone, end, zone, samples, meta),
                TotalCaloriesBurnedRecord(start, zone, end, zone, Energy.kilocalories(420.0), meta),
                StepsRecord(start, zone, end, zone, 5600, meta),
                DistanceRecord(start, zone, end, zone, Length.meters(4200.0), meta),
            ),
        )
    }
}
