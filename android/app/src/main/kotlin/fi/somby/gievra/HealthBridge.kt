package fi.somby.gievra

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.records.HeartRateRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.records.TotalCaloriesBurnedRecord
import androidx.health.connect.client.records.metadata.Metadata
import androidx.health.connect.client.request.AggregateRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import androidx.health.connect.client.units.Energy
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

    /** Kehitysversion testitiedot emulaattorille (vain debug-manifestissa on kirjoitusluvat). */
    val writePermissions = setOf(
        HealthPermission.getWritePermission(ExerciseSessionRecord::class),
        HealthPermission.getWritePermission(HeartRateRecord::class),
        HealthPermission.getWritePermission(TotalCaloriesBurnedRecord::class),
        HealthPermission.getWritePermission(StepsRecord::class),
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

    private fun appLabel(context: Context, pkg: String): String = try {
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

    /** Syke (keskiarvo, maksimi), kalorit ja askeleet aikaväliltä. */
    private suspend fun stats(context: Context, start: Instant, end: Instant): Map<String, Any?> {
        val c = client(context)
        val hr = c.readRecords(
            ReadRecordsRequest(HeartRateRecord::class, TimeRangeFilter.between(start, end), pageSize = 5000),
        ).records.flatMap { r -> r.samples.filter { !it.time.isBefore(start) && !it.time.isAfter(end) } }
        val kcal = try {
            c.aggregate(
                AggregateRequest(setOf(TotalCaloriesBurnedRecord.ENERGY_TOTAL), TimeRangeFilter.between(start, end)),
            )[TotalCaloriesBurnedRecord.ENERGY_TOTAL]?.inKilocalories
        } catch (e: Throwable) {
            null
        }
        val steps = try {
            c.aggregate(AggregateRequest(setOf(StepsRecord.COUNT_TOTAL), TimeRangeFilter.between(start, end)))[
                StepsRecord.COUNT_TOTAL
            ]
        } catch (e: Throwable) {
            null
        }
        return mapOf(
            "steps" to steps?.toInt(),
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
            ) + stats(context, s.startTime, s.endTime)
        }
        val own = stats(context, start, end)
        if ((own["hrCount"] as Int) > 0) {
            out += mapOf("kind" to "heartRate", "start" to startMs, "end" to endMs, "app" to "") + own
        }
        return out
    }

    /** Kehitysversio: keksitty harjoitus sykkeineen emulaattorin testaukseen. */
    suspend fun debugInsert(context: Context, startMs: Long, endMs: Long, type: Int, bpm: Int) {
        val start = Instant.ofEpochMilli(startMs)
        val end = Instant.ofEpochMilli(endMs)
        val zone = ZoneOffset.systemDefault().rules.getOffset(start)
        val samples = generateSequence(start) { it.plusSeconds(30) }.takeWhile { it.isBefore(end) }
            .mapIndexed { i, t -> HeartRateRecord.Sample(t, (bpm + (i % 9) * 3 - 12).toLong()) }.toList()
        val meta = Metadata.manualEntry()
        client(context).insertRecords(
            listOf(
                ExerciseSessionRecord(start, zone, end, zone, meta, type, "Testi"),
                HeartRateRecord(start, zone, end, zone, samples, meta),
                TotalCaloriesBurnedRecord(start, zone, end, zone, Energy.kilocalories(420.0), meta),
                StepsRecord(start, zone, end, zone, 5600, meta),
            ),
        )
    }
}
