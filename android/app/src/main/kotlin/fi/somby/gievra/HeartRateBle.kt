package fi.somby.gievra

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import java.util.UUID

// Sykevyö Bluetoothilla (standardi Heart Rate Service 0x180D, mittaus 0x2A37): Polar H10, Verity Sense, Garmin
// HRM-Dual/Pro ym. Haku, yhteys, sykeilmoitukset ja akun varaus (0x180F/0x2A19) kerran. Yhteys palautuu itsestään,
// jos vyö katoaa hetkeksi (autoConnect). Kaikki tapahtumat Dartiin yhtenä virtana [sink]: device, state, hr,
// battery, error. Luvat (BLUETOOTH_SCAN/CONNECT, Android 12+; vanhemmissa sijainti) pyytää Dart ennen kutsuja.
@SuppressLint("MissingPermission")
object HeartRateBle {
    private val HR_SERVICE: UUID = UUID.fromString("0000180d-0000-1000-8000-00805f9b34fb")
    private val HR_MEASUREMENT: UUID = UUID.fromString("00002a37-0000-1000-8000-00805f9b34fb")
    private val BATTERY_SERVICE: UUID = UUID.fromString("0000180f-0000-1000-8000-00805f9b34fb")
    private val BATTERY_LEVEL: UUID = UUID.fromString("00002a19-0000-1000-8000-00805f9b34fb")
    private val CCC: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

    var sink: ((Map<String, Any?>) -> Unit)? = null
    private val main = Handler(Looper.getMainLooper())
    private var gatt: BluetoothGatt? = null
    private var address: String? = null
    private var scanning = false
    private var appCtx: Context? = null

    /** Etualan palvelun lisätyyppi, kun vyö on valittu (Android 14+: connectedDevice). Ilman sitä esim. OnePlus
     *  (OxygenOS 16) katkaisi vyön noin 1,5 min kuluttua näytön lukitsemisesta, vaikka GPS jatkui (kaverin kävely
     *  14.11.: syke vain 2 % lenkistä). Tyyppi vaatii Bluetooth-luvan, joten vain kun se on annettu. */
    fun fgsType(ctx: Context): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && address != null && permitted(ctx)) {
            android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
        } else {
            0
        }

    /** Vyö yhdistyi tai katkaistiin: käynnissä olevat etualan palvelut päivittävät tyyppinsä. */
    private fun refreshServices() {
        val c = appCtx ?: return
        main.post {
            GpsService.refreshType(c)
            WorkoutService.refreshType(c)
        }
    }

    private fun emit(m: Map<String, Any?>) {
        main.post { sink?.invoke(m) }
    }

    private fun adapter(ctx: Context): BluetoothAdapter? =
        (ctx.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

    fun supported(ctx: Context) = adapter(ctx) != null

    /// Gievran oma lupatarkistus (permission_handler ilmoitti Android 17:ssä luvat myönnetyiksi, vaikka ne
    /// olivat kiellettyjä). Android 12+: BLUETOOTH_SCAN ja BLUETOOTH_CONNECT; 10–11: tarkka sijainti; 9 ja
    /// vanhemmat: karkea tai tarkka sijainti.
    fun permitted(ctx: Context): Boolean {
        fun has(p: String) = ctx.checkSelfPermission(p) == android.content.pm.PackageManager.PERMISSION_GRANTED
        return when {
            Build.VERSION.SDK_INT >= 31 ->
                has(android.Manifest.permission.BLUETOOTH_SCAN) && has(android.Manifest.permission.BLUETOOTH_CONNECT)
            Build.VERSION.SDK_INT >= 29 -> has(android.Manifest.permission.ACCESS_FINE_LOCATION)
            else -> has(android.Manifest.permission.ACCESS_FINE_LOCATION) ||
                has(android.Manifest.permission.ACCESS_COARSE_LOCATION)
        }
    }
    fun enabled(ctx: Context) = adapter(ctx)?.isEnabled == true

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            val d = result.device
            emit(
                mapOf(
                    "type" to "device",
                    "address" to d.address,
                    "name" to (result.scanRecord?.deviceName ?: d.name ?: d.address),
                    "rssi" to result.rssi,
                ),
            )
        }

        override fun onScanFailed(errorCode: Int) {
            scanning = false
            emit(mapOf("type" to "error", "error" to "scan $errorCode"))
        }
    }

    /// Haku sykevöistä [seconds] sekunnin ajan (vain laitteet, jotka mainostavat sykepalvelua).
    fun scan(ctx: Context, seconds: Int) {
        val scanner = adapter(ctx)?.bluetoothLeScanner ?: return emit(mapOf("type" to "error", "error" to "off"))
        stopScan(ctx)
        val filter = ScanFilter.Builder().setServiceUuid(ParcelUuid(HR_SERVICE)).build()
        val settings = ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build()
        try {
            scanner.startScan(listOf(filter), settings, scanCallback)
            scanning = true
            main.postDelayed({ stopScan(ctx) }, seconds * 1000L)
        } catch (e: SecurityException) {
            // Lupa puuttuu, vaikka lupakysely kertoi toista (Samsung Android 17, "älä kysy uudelleen"):
            // sovellus näyttää lupaviestin ja "Avaa sovelluksen luvat" -painikkeen raakavirheen sijaan.
            emit(mapOf("type" to "error", "error" to "permission"))
        } catch (e: Exception) {
            emit(mapOf("type" to "error", "error" to (e.message ?: "scan")))
        }
    }

    fun stopScan(ctx: Context) {
        if (!scanning) return
        scanning = false
        try {
            adapter(ctx)?.bluetoothLeScanner?.stopScan(scanCallback)
        } catch (_: Exception) {
        }
        emit(mapOf("type" to "scanDone"))
    }

    /// Yhdistää vyöhön (tai pitää yhteyden, jos sama vyö on jo yhdistetty).
    fun connect(ctx: Context, addr: String) {
        if (address == addr && gatt != null) return
        disconnect()
        val device: BluetoothDevice = try {
            adapter(ctx)?.getRemoteDevice(addr) ?: return emit(mapOf("type" to "error", "error" to "off"))
        } catch (e: Exception) {
            return emit(mapOf("type" to "error", "error" to "address"))
        }
        address = addr
        appCtx = ctx.applicationContext
        emit(mapOf("type" to "state", "state" to "connecting"))
        gatt = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                device.connectGatt(ctx.applicationContext, false, callback, BluetoothDevice.TRANSPORT_LE)
            } else {
                device.connectGatt(ctx.applicationContext, false, callback)
            }
        } catch (e: SecurityException) {
            // Yhteyslupa peruttu asetuksista vyön valinnan jälkeen.
            address = null
            emit(mapOf("type" to "state", "state" to "disconnected"))
            return emit(mapOf("type" to "error", "error" to "permission"))
        }
    }

    fun disconnect() {
        val g = gatt ?: return
        gatt = null
        address = null
        try {
            g.disconnect()
            g.close()
        } catch (_: Exception) {
        }
        emit(mapOf("type" to "state", "state" to "disconnected"))
        refreshServices()
    }

    private val callback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(g: BluetoothGatt, status: Int, newState: Int) {
            if (g != gatt) return
            when (newState) {
                BluetoothProfile.STATE_CONNECTED -> {
                    emit(mapOf("type" to "state", "state" to "connected"))
                    refreshServices()
                    g.discoverServices()
                }
                BluetoothProfile.STATE_DISCONNECTED -> {
                    emit(mapOf("type" to "state", "state" to "connecting"))
                    // Vyö katosi (kantama, akku, toinen sovellus): yritetään uudelleen, kunnes käyttäjä katkaisee.
                    try {
                        g.connect()
                    } catch (_: Exception) {
                    }
                }
            }
        }

        override fun onServicesDiscovered(g: BluetoothGatt, status: Int) {
            val ch = g.getService(HR_SERVICE)?.getCharacteristic(HR_MEASUREMENT)
            if (ch == null) {
                emit(mapOf("type" to "error", "error" to "noHeartRate"))
                return
            }
            g.setCharacteristicNotification(ch, true)
            val d = ch.getDescriptor(CCC) ?: return
            if (Build.VERSION.SDK_INT >= 33) {
                g.writeDescriptor(d, BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE)
            } else {
                @Suppress("DEPRECATION")
                d.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                @Suppress("DEPRECATION")
                g.writeDescriptor(d)
            }
        }

        override fun onDescriptorWrite(g: BluetoothGatt, d: BluetoothGattDescriptor, status: Int) {
            // Ilmoitukset päällä: akun varaus kerran (ei kaikilla vöillä).
            g.getService(BATTERY_SERVICE)?.getCharacteristic(BATTERY_LEVEL)?.let { g.readCharacteristic(it) }
        }

        @Deprecated("Android < 13")
        override fun onCharacteristicChanged(g: BluetoothGatt, ch: BluetoothGattCharacteristic) {
            @Suppress("DEPRECATION")
            handle(ch.uuid, ch.value ?: return)
        }

        override fun onCharacteristicChanged(g: BluetoothGatt, ch: BluetoothGattCharacteristic, value: ByteArray) =
            handle(ch.uuid, value)

        @Deprecated("Android < 13")
        override fun onCharacteristicRead(g: BluetoothGatt, ch: BluetoothGattCharacteristic, status: Int) {
            @Suppress("DEPRECATION")
            handle(ch.uuid, ch.value ?: return)
        }

        override fun onCharacteristicRead(g: BluetoothGatt, ch: BluetoothGattCharacteristic, value: ByteArray, status: Int) =
            handle(ch.uuid, value)
    }

    private fun handle(uuid: UUID, v: ByteArray) {
        when (uuid) {
            HR_MEASUREMENT -> parseHeartRate(v)?.let { (bpm, contact) ->
                emit(mapOf("type" to "hr", "bpm" to bpm, "contact" to contact, "t" to System.currentTimeMillis()))
            }
            BATTERY_LEVEL -> if (v.isNotEmpty()) emit(mapOf("type" to "battery", "percent" to (v[0].toInt() and 0xff)))
        }
    }

    /// Heart Rate Measurement: lippu-tavu (bitti 0: 16-bittinen arvo; bitit 1–2: ihokontakti tuettu/havaittu),
    /// sitten syke. Palauttaa (bpm, kontakti) tai null, jos arvo puuttuu. Kontakti null = vyö ei kerro.
    fun parseHeartRate(v: ByteArray): Pair<Int, Boolean?>? {
        if (v.size < 2) return null
        val flags = v[0].toInt() and 0xff
        val bpm = if (flags and 0x01 != 0) {
            if (v.size < 3) return null
            (v[1].toInt() and 0xff) or ((v[2].toInt() and 0xff) shl 8)
        } else {
            v[1].toInt() and 0xff
        }
        val contact = if (flags and 0x04 != 0) flags and 0x02 != 0 else null
        return if (bpm in 1..300) bpm to contact else null
    }
}
