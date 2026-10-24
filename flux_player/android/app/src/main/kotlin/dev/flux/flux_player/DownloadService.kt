package dev.flux.flux_player

import android.app.*
import android.content.*
import android.os.*
import android.net.Uri
import org.json.JSONArray
import org.json.JSONObject
import java.io.*
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID
import java.util.concurrent.*
import java.util.concurrent.atomic.AtomicLong
import kotlin.math.min

/**
 * Foreground Android downloader. Part files and task metadata survive activity closure.
 * Parallel ranges require HTTP 206 + a valid Content-Range. Non-range servers use one stream.
 * This service does NOT download DRM content, torrents, or adaptive streaming manifests.
 */
class DownloadService : Service() {
    private data class Job(
        val id: String, val url: String, val name: String, val parts: Int,
        @Volatile var status: String = "queued",
        @Volatile var downloaded: Long = 0,
        @Volatile var total: Long = 0,
        @Volatile var path: String = "",
        @Volatile var error: String = "",
        @Volatile var etag: String = ""
    ) {
        fun json() = JSONObject().apply {
            put("id", id); put("url", url); put("name", name); put("parts", parts)
            put("status", status); put("downloaded", downloaded); put("total", total)
            put("path", path); put("error", error); put("etag", etag)
        }
        fun map(): Map<String, Any?> = mapOf(
            "id" to id, "url" to url, "name" to name, "parts" to parts,
            "status" to status, "downloaded" to downloaded, "total" to total,
            "path" to path, "error" to error
        )
    }

    companion object {
        private const val CHANNEL = "flux_downloads"
        private const val PREF = "flux_saved_jobs"
        private const val KEY = "jobs"

        fun list(context: Context): List<Map<String, Any?>> {
            val saved = context.getSharedPreferences(PREF, Context.MODE_PRIVATE)
                .getString(KEY, "[]") ?: "[]"
            return try {
                val arr = JSONArray(saved)
                (0 until arr.length()).map { idx ->
                    val obj = arr.getJSONObject(idx)
                    mapOf<String, Any?>(
                        "id" to obj.optString("id"),
                        "name" to obj.optString("name"),
                        "url" to obj.optString("url"),
                        "status" to obj.optString("status", "queued"),
                        "downloaded" to obj.optLong("downloaded"),
                        "total" to obj.optLong("total"),
                        "path" to obj.optString("path"),
                        "parts" to obj.optInt("parts", 1),
                        "error" to obj.optString("error")
                    )
                }
            } catch (ignored: Exception) { emptyList() }
        }
    }

    private val lock = Any()
    private val jobs = LinkedHashMap<String, Job>()
    private val runningIds = ConcurrentHashMap.newKeySet<String>()
    private val executor = Executors.newFixedThreadPool(2)

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        if (Build.VERSION.SDK_INT >= 26) {
            val channel = NotificationChannel(
                CHANNEL, "Active file downloads", NotificationManager.IMPORTANCE_LOW
            ).apply { description = "Background direct-link downloads" }
            (getSystemService(NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(channel)
        }
        val saved = getSharedPreferences(PREF, MODE_PRIVATE).getString(KEY, "[]") ?: "[]"
        try {
            val arr = JSONArray(saved)
            for (index in 0 until arr.length()) {
                val j = arr.getJSONObject(index)
                val job = Job(
                    id = j.getString("id"),
                    url = j.getString("url"),
                    name = j.getString("name"),
                    parts = j.optInt("parts", 8),
                    status = j.optString("status", "queued"),
                    downloaded = j.optLong("downloaded"),
                    total = j.optLong("total"),
                    path = j.optString("path"),
                    error = j.optString("error"),
                    etag = j.optString("etag")
                )
                jobs[job.id] = job
            }
        } catch (ignored: Exception) {}
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(41, notification())
        val command = intent?.action ?: "restore"
        val id = intent?.getStringExtra("id") ?: ""
        when (command) {
            "enqueue" -> {
                val rawUrl = intent?.getStringExtra("url") ?: ""
                if (rawUrl.startsWith("https://") || rawUrl.startsWith("http://")) {
                    val name = cleanName(intent?.getStringExtra("name").orEmpty(), rawUrl)
                    val job = Job(UUID.randomUUID().toString(), rawUrl, name,
                        (intent?.getIntExtra("parts", 8) ?: 8).coerceIn(1, 16))
                    synchronized(lock) { jobs[job.id] = job; persist() }
                    MainActivity.emit(job.map())
                    schedule(job)
                }
            }
            "pause" -> synchronized(lock) {
                jobs[id]?.let { if (it.status == "running" || it.status == "queued") {
                    it.status = "paused"; persist(); MainActivity.emit(it.map())
                }}
            }
            "resume" -> synchronized(lock) {
                jobs[id]?.let {
                    if (it.status == "paused" || it.status == "failed") {
                        it.status = "queued"; it.error = ""; persist(); schedule(it)
                    }
                }
            }
            "cancel" -> synchronized(lock) {
                jobs[id]?.let {
                    it.status = "cancelled"
                    val base = workFolder(it)
                    base.deleteRecursively()
                    jobs.remove(id)
                    persist()
                    MainActivity.emit(mapOf("id" to id, "status" to "cancelled"))
                }
            }
            else -> {
                synchronized(lock) {
                    jobs.values.filter { it.status == "running" || it.status == "queued" }
                        .forEach { schedule(it) }
                }
            }
        }
        return START_STICKY
    }

    private fun cleanName(requested: String, url: String): String {
        val source = requested.ifBlank {
            Uri.parse(url).lastPathSegment ?: "download.bin"
        }
        return source.replace(Regex("[^a-zA-Z0-9._ -]"), "_")
            .trim('.', ' ').take(120).ifBlank { "download.bin" }
    }

    private fun notification(): Notification {
        val target = Intent(this, MainActivity::class.java)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            (if (Build.VERSION.SDK_INT >= 23) PendingIntent.FLAG_IMMUTABLE else 0)
        val pending = PendingIntent.getActivity(this, 0, target, flags)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL)
                      else @Suppress("DEPRECATION") Notification.Builder(this)
        return builder.setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle("Flux Download & Play")
            .setContentText("Download service is active")
            .setContentIntent(pending).setOngoing(true).build()
    }

    private fun workFolder(job: Job): File {
        return File(getExternalFilesDir(null) ?: filesDir, "flux_parts/" + job.id)
    }

    private fun outputFolder(): File {
        return File(getExternalFilesDir(null) ?: filesDir, "FluxDownloads").apply { mkdirs() }
    }

    private fun persist() {
        synchronized(lock) {
            val data = JSONArray()
            jobs.values.forEach { data.put(it.json()) }
            getSharedPreferences(PREF, MODE_PRIVATE).edit().putString(KEY, data.toString()).apply()
        }
    }

    private fun report(job: Job) {
        persist()
        MainActivity.emit(job.map())
    }

    private fun schedule(job: Job) {
        if (!runningIds.add(job.id)) return
        executor.execute {
            try {
                synchronized(lock) {
                    if (job.status != "queued" && job.status != "running") return@execute
                    job.status = "running"
                    report(job)
                }
                download(job)
                if (job.status == "running") {
                    job.status = "completed"
                    job.downloaded = job.total.coerceAtLeast(job.downloaded)
                    report(job)
                }
            } catch (e: Exception) {
                if (job.status == "running") {
                    job.status = "failed"
                    job.error = e.message?.take(180) ?: "Download failed"
                    report(job)
                } else {
                    report(job)
                }
            } finally {
                runningIds.remove(job.id)
                // A quick pause -> resume can mark a running task queued while its
                // old worker is still shutting down. Start the new worker here.
                if (job.status == "queued") schedule(job)
                if (runningIds.isEmpty()) {
                    val waiting = synchronized(lock) {
                        jobs.values.any { it.status == "queued" || it.status == "running" }
                    }
                    if (!waiting) stopSelf()
                }
            }
        }
    }

    private data class Probe(val size: Long, val ranges: Boolean, val etag: String)

    private fun connect(url: String, range: String? = null): HttpURLConnection {
        val conn = URL(url).openConnection() as HttpURLConnection
        conn.instanceFollowRedirects = true
        conn.connectTimeout = 18000
        conn.readTimeout = 25000
        conn.setRequestProperty("Accept-Encoding", "identity")
        conn.setRequestProperty("User-Agent", "FluxDownload/0.1 (Android)")
        if (range != null) conn.setRequestProperty("Range", range)
        return conn
    }

    private fun probe(job: Job): Probe {
        val conn = connect(job.url, "bytes=0-0")
        return try {
            val code = conn.responseCode
            if (code !in 200..299) throw IOException("Server returned HTTP $code")
            val contentRange = conn.getHeaderField("Content-Range").orEmpty()
            val match = Regex("bytes\\s+0-0/(\\d+)", RegexOption.IGNORE_CASE).find(contentRange)
            val rangeOK = code == 206 && match != null
            val size = if (rangeOK) match!!.groupValues[1].toLong()
                       else conn.contentLengthLong
            Probe(size, rangeOK, conn.getHeaderField("ETag").orEmpty())
        } finally { conn.disconnect() }
    }

    private fun download(job: Job) {
        val folder = workFolder(job).apply { mkdirs() }
        val meta = probe(job)
        if (job.etag.isNotBlank() && meta.etag.isNotBlank() && job.etag != meta.etag) {
            folder.deleteRecursively()
            folder.mkdirs()
        }
        // Changing content length invalidates existing range checkpoints.
        if (job.total > 0 && meta.size > 0 && job.total != meta.size) {
            folder.deleteRecursively()
            folder.mkdirs()
        }
        job.etag = meta.etag
        job.total = meta.size.coerceAtLeast(0L)
        val parts = if (meta.ranges && meta.size > 0L)
            min(job.parts, min(meta.size, 16L).toInt()) else 1
        // A server losing Range support invalidates old multi-part checkpoints.
        if (parts == 1 && !meta.ranges) {
            folder.listFiles()?.filter { it.name.endsWith(".part") }?.forEach { it.delete() }
        }
        report(job)
        val pool = Executors.newFixedThreadPool(parts)
        var lastEmit = System.currentTimeMillis()
        val bytesNow = AtomicLong(0)
        try {
            val futures = (0 until parts).map { index ->
                pool.submit(Callable {
                    val start = (meta.size / parts) * index
                    val end = if (index == parts - 1) meta.size - 1
                              else (meta.size / parts) * (index + 1) - 1
                    val file = File(folder, "$index.part")
                    val expected = if (meta.size > 0) end - start + 1 else -1L
                    if (expected >= 0 && file.length() > expected) file.delete()
                    var offset = file.length()
                    if (!meta.ranges && offset > 0) { file.delete(); offset = 0 }
                    if (expected >= 0 && offset == expected) return@Callable
                    if (job.status != "running") throw InterruptedIOException("Paused")
                    val header = if (meta.ranges)
                        "bytes=${start + offset}-$end" else null
                    val conn = connect(job.url, header)
                    try {
                        val status = conn.responseCode
                        if (meta.ranges && status != 206) {
                            throw IOException("Range rejected: HTTP $status")
                        }
                        if (!meta.ranges && status != 200) {
                            throw IOException("Download returned HTTP $status")
                        }
                        FileOutputStream(file, true).use { output ->
                            conn.inputStream.use { input ->
                                val buffer = ByteArray(128 * 1024)
                                while (true) {
                                    if (job.status != "running") throw InterruptedIOException("Paused")
                                    val count = input.read(buffer)
                                    if (count < 0) break
                                    output.write(buffer, 0, count)
                                    bytesNow.addAndGet(count.toLong())
                                    val now = System.currentTimeMillis()
                                    synchronized(lock) {
                                        if (now - lastEmit > 650) {
                                            lastEmit = now
                                            job.downloaded = folder.listFiles()
                                                ?.filter { it.name.endsWith(".part") }
                                                ?.sumOf { it.length() } ?: 0L
                                            report(job)
                                        }
                                    }
                                }
                            }
                        }
                    } finally { conn.disconnect() }
                    if (expected >= 0 && file.length() != expected) {
                        throw IOException("Incomplete segment $index")
                    }
                })
            }
            for (f in futures) f.get()
        } finally { pool.shutdownNow() }
        if (job.status != "running") throw InterruptedIOException("Paused")
        // Keep the segments until the merged file has been completed successfully.
        val output = File(outputFolder(), job.id.take(8) + "_" + job.name)
        val merging = File(output.parentFile, output.name + ".assembling")
        try {
            FileOutputStream(merging).use { target ->
                for (i in 0 until parts) {
                    if (job.status != "running") throw InterruptedIOException("Paused")
                    File(folder, "$i.part").inputStream().use { src ->
                        src.copyTo(target, 128 * 1024)
                    }
                }
                target.fd.sync()
            }
            if (job.total > 0 && merging.length() != job.total) {
                throw IOException("Merged file size mismatch")
            }
            if (!merging.renameTo(output)) throw IOException("Cannot save output file")
            job.path = output.absolutePath
            job.downloaded = output.length()
            job.total = output.length()
            folder.deleteRecursively()
        } finally { if (merging.exists()) merging.delete() }
    }

    override fun onDestroy() {
        executor.shutdownNow()
        super.onDestroy()
    }
}
