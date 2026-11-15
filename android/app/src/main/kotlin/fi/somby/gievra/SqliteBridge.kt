package fi.somby.gievra

import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteStatement
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * FitNotes-varmuuskopion luku ja kirjoitus Androidin omalla SQLitellä (ei omaa 1,7 Mt:n libsqlite3.so:ta APK:ssa).
 * Dart-puoli: lib/sql_db.dart. Työ omassa säikeessään, jottei käyttöliittymä jumiudu isossa tuonnissa.
 * NO_LOCALIZED_COLLATORS: Android ei lisää omaa android_metadata-taulua (FitNotes-skeema luo sen itse).
 */
class SqliteBridge : MethodChannel.MethodCallHandler {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val open = HashMap<Int, SQLiteDatabase>()
    private var nextId = 1

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        worker.execute {
            try {
                val value = handle(call)
                main.post { result.success(value) }
            } catch (e: Exception) {
                main.post { result.error("sqlite", e.message ?: e.javaClass.simpleName, null) }
            }
        }
    }

    private fun db(call: MethodCall): SQLiteDatabase =
        open[call.argument<Int>("db")] ?: throw IllegalStateException("database not open")

    private fun handle(call: MethodCall): Any? = when (call.method) {
        "open" -> {
            val readOnly = call.argument<Boolean>("readOnly") == true
            val flags = SQLiteDatabase.NO_LOCALIZED_COLLATORS or
                if (readOnly) SQLiteDatabase.OPEN_READONLY else SQLiteDatabase.CREATE_IF_NECESSARY
            val d = SQLiteDatabase.openDatabase(call.argument<String>("path")!!, null, flags)
            val id = nextId++
            open[id] = d
            id
        }
        "select" -> {
            val args = call.argument<List<Any?>>("args") ?: emptyList()
            db(call).rawQueryWithFactory({ _, driver, table, query ->
                bindAll(query, args)
                android.database.sqlite.SQLiteCursor(driver, table, query)
            }, call.argument<String>("sql")!!, null, "").use { rows(it) }
        }
        "execute" -> {
            val d = db(call)
            d.compileStatement(call.argument<String>("sql")!!).use { st ->
                bindAll(st, call.argument<List<Any?>>("args") ?: emptyList())
                st.execute()
            }
            d.compileStatement("SELECT last_insert_rowid()").use { it.simpleQueryForLong() }
        }
        "executeMany" -> {
            val d = db(call)
            d.compileStatement(call.argument<String>("sql")!!).use { st ->
                for (row in call.argument<List<List<Any?>>>("rows") ?: emptyList()) {
                    st.clearBindings()
                    bindAll(st, row)
                    st.execute()
                }
            }
            null
        }
        "begin" -> { db(call).beginTransaction(); null }
        "commit" -> {
            val d = db(call)
            d.setTransactionSuccessful()
            d.endTransaction()
            null
        }
        "close" -> {
            open.remove(call.argument<Int>("db"))?.let { d ->
                if (d.inTransaction()) d.endTransaction() // keskeytynyt kirjoitus perutaan
                d.close()
            }
            null
        }
        else -> throw IllegalArgumentException("unknown method ${call.method}")
    }

    private fun bindAll(st: android.database.sqlite.SQLiteProgram, args: List<Any?>) {
        args.forEachIndexed { i, v ->
            val n = i + 1
            when (v) {
                null -> st.bindNull(n)
                is Int -> st.bindLong(n, v.toLong())
                is Long -> st.bindLong(n, v)
                is Double -> st.bindDouble(n, v)
                is Boolean -> st.bindLong(n, if (v) 1 else 0)
                else -> st.bindString(n, v.toString())
            }
        }
    }

    private fun rows(c: Cursor): List<Map<String, Any?>> {
        val names = c.columnNames
        val out = ArrayList<Map<String, Any?>>(c.count)
        while (c.moveToNext()) {
            val row = HashMap<String, Any?>(names.size)
            for (i in names.indices) {
                row[names[i]] = when (c.getType(i)) {
                    Cursor.FIELD_TYPE_NULL -> null
                    Cursor.FIELD_TYPE_INTEGER -> c.getLong(i)
                    Cursor.FIELD_TYPE_FLOAT -> c.getDouble(i)
                    Cursor.FIELD_TYPE_BLOB -> c.getBlob(i)
                    else -> c.getString(i)
                }
            }
            out.add(row)
        }
        return out
    }
}
