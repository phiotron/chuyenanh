package com.phuong.pdfoffice

import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Nhận file mở từ app khác: "Mở bằng" (ACTION_VIEW), "Chia sẻ tới" (ACTION_SEND / SEND_MULTIPLE).
 *
 * Kênh `com.phuong.pdfoffice/incoming`:
 *  - `takeInitial` -> Map `{paths: List<String>, failed: Int, unsupported: Int}`: file của intent
 *    đã mở app (khởi động lạnh). Trả một lần rồi xoá; mở bình thường thì `paths` rỗng.
 *    `failed` = lỗi đọc / quá dung lượng; `unsupported` = đuôi lạ.
 *  - Native -> Dart `onFiles(Map)`: cùng dạng, gọi khi app đang chạy và nhận intent mới.
 *
 * Mỗi URI được chép vào `cacheDir/incoming/` (tên an toàn, tối đa [MAX_BYTES]/file) trên luồng
 * nền; Dart chép tiếp sang thư mục bền. Intent lối tắt [ShortcutChannel.ACTION_OPEN_PDF] và
 * MAIN bị bỏ qua (kênh lối tắt lo).
 *
 * URI được "chụp" ngay khi nhận intent vì `ShortcutChannel.takeInitialPath` đổi action của
 * intent khởi động thành MAIN — đọc trễ sẽ mất dữ liệu.
 */
class IncomingFilesChannel(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.phuong.pdfoffice/incoming"
        const val MAX_BYTES = 200L * 1024 * 1024
        private const val DIR_NAME = "incoming"
        private const val MAX_NAME_LENGTH = 120

        /** Bản sao trong cache cũ hơn mức này bị dọn khi nhận lô mới. */
        private const val CACHE_TTL_MS = 24L * 60 * 60 * 1000

        /** Khớp `documentExtensions` + `imageExtensions` (lib/core/utils/doc_type.dart). */
        private val ALLOWED_EXTENSIONS = setOf(
            "pdf", "doc", "docx", "xls", "xlsx", "csv", "ppt", "pptx", "txt",
            "jpg", "jpeg", "png", "webp", "heic", "heif", "bmp", "gif",
        )

        /** MimeTypeMap không có sẵn đủ loại Office trên mọi máy. */
        private val MIME_EXTENSIONS = mapOf(
            "application/pdf" to "pdf",
            "application/msword" to "doc",
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document" to "docx",
            "application/vnd.ms-excel" to "xls",
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" to "xlsx",
            "application/vnd.ms-powerpoint" to "ppt",
            "application/vnd.openxmlformats-officedocument.presentationml.presentation" to "pptx",
            "text/plain" to "txt",
            // CSV: nhieu app gui mot trong ba mime duoi day.
            "text/csv" to "csv",
            "text/comma-separated-values" to "csv",
            "application/csv" to "csv",
            "image/jpeg" to "jpg",
            "image/png" to "png",
            "image/webp" to "webp",
            "image/heic" to "heic",
            "image/heif" to "heif",
            "image/bmp" to "bmp",
            "image/gif" to "gif",
        )
    }

    /** Một lô dữ liệu lấy từ intent (chưa chép). */
    private data class Pending(val uris: List<Uri>, val text: String?)

    private val channel = MethodChannel(messenger, CHANNEL)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()

    /** Lô của intent khởi động; Dart lấy qua `takeInitial`. */
    private var initial: Pending? = null

    @Volatile
    private var disposed = false

    init {
        channel.setMethodCallHandler(this)
    }

    /** Gọi từ `configureFlutterEngine` với intent mở Activity. */
    fun handleLaunchIntent(intent: Intent?) {
        initial = extract(intent)?.also { consume(intent) }
    }

    /** Gọi từ `onNewIntent`: chép rồi đẩy sang Dart. */
    fun handleNewIntent(intent: Intent?) {
        val pending = extract(intent) ?: return
        consume(intent)
        process(pending) { payload ->
            if (!disposed) channel.invokeMethod("onFiles", payload)
        }
    }

    fun dispose() {
        disposed = true
        channel.setMethodCallHandler(null)
        initial = null
        executor.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "takeInitial" -> {
                val pending = initial
                initial = null
                if (pending == null) {
                    result.success(payload(emptyList(), 0))
                } else {
                    process(pending) { result.success(it) }
                }
            }
            else -> result.notImplemented()
        }
    }

    // ---------------------------------------------------------------- đọc intent

    private fun extract(intent: Intent?): Pending? {
        if (intent == null) return null
        // Mở lại từ danh sách gần đây: intent cũ được trả lại nguyên vẹn -> không nhập lại.
        if (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) return null
        val uris = when (intent.action) {
            Intent.ACTION_VIEW -> listOfNotNull(intent.data)
            Intent.ACTION_SEND -> listOfNotNull(streamExtra(intent)).ifEmpty { clipUris(intent) }
            Intent.ACTION_SEND_MULTIPLE -> streamListExtra(intent).ifEmpty { clipUris(intent) }
            // ACTION_MAIN, ShortcutChannel.ACTION_OPEN_PDF, khác: không phải việc của kênh này.
            else -> return null
        }
        val text = if (intent.action == Intent.ACTION_SEND && uris.isEmpty()) {
            intent.getStringExtra(Intent.EXTRA_TEXT)?.takeIf { it.isNotBlank() }
        } else {
            null
        }
        if (uris.isEmpty() && text == null) return null
        return Pending(uris, text)
    }

    @Suppress("DEPRECATION")
    private fun streamExtra(intent: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri
        }

    @Suppress("DEPRECATION")
    private fun streamListExtra(intent: Intent): List<Uri> {
        val list: List<Uri>? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
        }
        return list.orEmpty().filterNotNull()
    }

    private fun clipUris(intent: Intent): List<Uri> {
        val clip = intent.clipData ?: return emptyList()
        return (0 until clip.itemCount).mapNotNull { clip.getItemAt(it)?.uri }
    }

    /** Xoá dấu vết để không nhập lại khi Activity được dựng lại. */
    private fun consume(intent: Intent?) {
        intent ?: return
        intent.action = Intent.ACTION_MAIN
        intent.data = null
        intent.removeExtra(Intent.EXTRA_STREAM)
        intent.removeExtra(Intent.EXTRA_TEXT)
    }

    // ---------------------------------------------------------------- chép vào cache

    /** Chép trên luồng nền, trả kết quả về luồng chính (MethodChannel yêu cầu). */
    private fun process(pending: Pending, done: (Map<String, Any>) -> Unit) {
        val task = Runnable {
            val dir = File(context.cacheDir, DIR_NAME)
            dir.mkdirs()
            cleanOld(dir)
            val paths = mutableListOf<String>()
            var failed = 0
            var unsupported = 0
            for (uri in pending.uris) {
                try {
                    val file = copyUri(uri, dir)
                    if (file != null) paths.add(file.absolutePath) else failed++
                } catch (e: UnsupportedTypeException) {
                    unsupported++
                } catch (e: Exception) {
                    // IOException, SecurityException (mất quyền đọc URI), quá dung lượng…
                    failed++
                }
            }
            pending.text?.let { text ->
                val file = try {
                    writeText(text, dir)
                } catch (e: IOException) {
                    null
                }
                if (file != null) paths.add(file.absolutePath) else failed++
            }
            val result = payload(paths, failed, unsupported)
            mainHandler.post { done(result) }
        }
        try {
            executor.execute(task)
        } catch (e: Exception) {
            // Executor đã tắt (Activity huỷ): báo về rỗng để Dart không treo.
            mainHandler.post { done(payload(emptyList(), pending.uris.size)) }
        }
    }

    private fun payload(paths: List<String>, failed: Int, unsupported: Int = 0): Map<String, Any> =
        mapOf("paths" to paths, "failed" to failed, "unsupported" to unsupported)

    /** Đuôi / mime không thuộc loại app mở được. */
    private class UnsupportedTypeException : Exception()

    private fun copyUri(uri: Uri, dir: File): File? {
        if (!isReadableSource(uri)) return null
        val resolver = context.contentResolver
        var displayName: String? = null
        var size = -1L
        if (uri.scheme == ContentResolver.SCHEME_CONTENT) {
            try {
                resolver.query(
                    uri,
                    arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE),
                    null,
                    null,
                    null,
                )?.use { c ->
                    if (c.moveToFirst()) {
                        val nameIdx = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        if (nameIdx >= 0 && !c.isNull(nameIdx)) displayName = c.getString(nameIdx)
                        val sizeIdx = c.getColumnIndex(OpenableColumns.SIZE)
                        if (sizeIdx >= 0 && !c.isNull(sizeIdx)) size = c.getLong(sizeIdx)
                    }
                }
            } catch (e: Exception) {
                // Provider không hỗ trợ query (hiếm): vẫn thử đọc, tên lấy theo mime.
            }
        } else {
            displayName = uri.lastPathSegment
        }
        if (size > MAX_BYTES) return null

        val mime = resolver.getType(uri)
        val name = safeName(displayName, mime) ?: throw UnsupportedTypeException()
        val target = uniqueFile(dir, name)
        val input = resolver.openInputStream(uri) ?: return null
        try {
            input.use { ins ->
                target.outputStream().use { out ->
                    val buffer = ByteArray(64 * 1024)
                    var total = 0L
                    while (true) {
                        val n = ins.read(buffer)
                        if (n < 0) break
                        total += n
                        // SIZE có thể thiếu/sai: đếm thật khi chép.
                        if (total > MAX_BYTES) throw IOException("too large")
                        out.write(buffer, 0, n)
                    }
                }
            }
        } catch (e: Exception) {
            target.delete()
            throw e
        }
        return target
    }

    /**
     * Chặn URI trỏ vào dữ liệu riêng của chính app (file:// trong dataDir, hoặc content:// của
     * FileProvider của app): app khác không được dùng ta để chép file riêng ra ngoài.
     */
    private fun isReadableSource(uri: Uri): Boolean {
        return when (uri.scheme) {
            ContentResolver.SCHEME_CONTENT -> {
                val authority = uri.authority ?: return false
                val provider = try {
                    context.packageManager.resolveContentProvider(authority, 0)
                } catch (e: Exception) {
                    null
                }
                provider?.packageName != context.packageName
            }
            ContentResolver.SCHEME_FILE -> {
                val path = uri.path ?: return false
                val file = try {
                    File(path).canonicalFile
                } catch (e: IOException) {
                    return false
                }
                val privateRoots = listOfNotNull(
                    context.applicationInfo.dataDir,
                    context.filesDir.parent,
                    context.cacheDir.parent,
                ).mapNotNull { root ->
                    try {
                        File(root).canonicalPath
                    } catch (e: IOException) {
                        null
                    }
                }
                privateRoots.none { root ->
                    file.path == root || file.path.startsWith(root + File.separator)
                }
            }
            else -> false
        }
    }

    /** Tên hiển thị -> tên file an toàn có đuôi được hỗ trợ; null nếu đuôi lạ. */
    private fun safeName(displayName: String?, mime: String?): String? {
        var name = (displayName ?: "")
            .substringAfterLast('/')
            .substringAfterLast('\\')
            .replace(Regex("[\\u0000-\\u001F\\u007F:*?\"<>|]"), "_")
            .trim()
            .trimStart('.')
        var ext = name.substringAfterLast('.', "").lowercase()
        if (ext !in ALLOWED_EXTENSIONS) {
            val fromMime = mime?.lowercase()?.let { m ->
                MIME_EXTENSIONS[m] ?: MimeTypeMap.getSingleton().getExtensionFromMimeType(m)
            }?.lowercase()
            if (fromMime == null || fromMime !in ALLOWED_EXTENSIONS) return null
            ext = fromMime
            if (name.isEmpty()) name = "file"
            name = "$name.$ext"
        }
        var base = name.substring(0, name.length - ext.length - 1).trim()
        if (base.isEmpty()) base = "file"
        if (base.length > MAX_NAME_LENGTH) base = base.take(MAX_NAME_LENGTH)
        return "$base.$ext"
    }

    /** `a.pdf`, `a (1).pdf`, … trong [dir]. */
    private fun uniqueFile(dir: File, name: String): File {
        val base = name.substringBeforeLast('.')
        val ext = name.substringAfterLast('.')
        var i = 0
        while (true) {
            val candidate = File(dir, if (i == 0) name else "$base ($i).$ext")
            if (!candidate.exists()) return candidate
            i++
        }
    }

    /** Chia sẻ đoạn văn bản (không kèm file) -> lưu thành .txt. */
    private fun writeText(text: String, dir: File): File? {
        val bytes = text.toByteArray(Charsets.UTF_8)
        if (bytes.size > MAX_BYTES) return null
        val target = uniqueFile(dir, "shared_text_${System.currentTimeMillis()}.txt")
        target.writeBytes(bytes)
        return target
    }

    private fun cleanOld(dir: File) {
        val cutoff = System.currentTimeMillis() - CACHE_TTL_MS
        dir.listFiles()?.forEach { f ->
            if (f.isFile && f.lastModified() < cutoff) f.delete()
        }
    }
}
