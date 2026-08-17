package cn.ylin314.animphoto

import android.Manifest
import android.app.Activity
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.media.ExifInterface
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

class MainActivity : FlutterActivity() {
    /** 缩略图解码线程池：避免在主线程解码导致 UI 卡顿。 */
    private val thumbnailExecutor = java.util.concurrent.Executors.newFixedThreadPool(4)
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingDeleteResult: MethodChannel.Result? = null
    private var pendingDeleteCount = 0

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        configureUpdateChannel(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cn.ylin314/media")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getDeviceBrand" -> result.success(Build.MANUFACTURER)
                    "hasMediaPermission" -> result.success(hasMediaPermission())
                    "requestMediaPermissions" -> requestMediaPermissions(result)
                    "scanImages" -> thumbnailExecutor.execute { scanImages(result) }
                    "getThumbnail" -> {
                        val path = call.argument<String>("path")
                        val max = call.argument<Int>("max") ?: 400
                        if (path == null) {
                            result.error("BAD_ARG", "path required", null)
                        } else {
                            // 后台线程解码，MethodChannel.Result 可跨线程回调
                            thumbnailExecutor.execute {
                                result.success(loadThumbnail(path, max))
                            }
                        }
                    }
                    "deleteImages" -> {
                        val ids = call.argument<List<Int>>("ids")
                        if (ids.isNullOrEmpty()) {
                            result.error("BAD_ARG", "ids required", null)
                        } else {
                            startDeleteImages(ids.map { it.toLong() }, result)
                        }
                    }
                    "shutdown" -> {
                        thumbnailExecutor.shutdown()
                        result.success(true)
                    }
                    "saveJpegToGallery" -> {
                        val path = call.argument<String>("path")
                        val name = call.argument<String>("name")
                        if (path == null || name == null) {
                            result.error("BAD_ARG", "path/name required", null)
                        } else {
                            result.success(saveJpegToGallery(path, name))
                        }
                    }
                    "saveVideoToGallery" -> {
                        val path = call.argument<String>("path")
                        val name = call.argument<String>("name")
                        if (path == null || name == null) {
                            result.error("BAD_ARG", "path/name required", null)
                        } else {
                            result.success(saveVideoToGallery(path, name))
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun currentAppVersion(): Map<String, Any> {
        val info = packageManager.getPackageInfo(packageName, 0)
        val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
        }
        return mapOf(
            "versionName" to (info.versionName ?: "0.0.0"),
            "versionCode" to code
        )
    }

    private fun startAppUpdate(url: String): Boolean {
        val uri = Uri.parse(url)
        if (uri.scheme != "http" && uri.scheme != "https") return false
        val browserIntent = Intent(Intent.ACTION_VIEW, uri).apply {
            addCategory(Intent.CATEGORY_BROWSABLE)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return try {
            startActivity(browserIntent)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun configureUpdateChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cn.ylin314/update")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getAppVersion" -> result.success(currentAppVersion())
                    "startAppUpdate" -> {
                        val url = call.argument<String>("url")
                        if (url.isNullOrBlank()) {
                            result.error("BAD_ARG", "url required", null)
                        } else {
                            result.success(startAppUpdate(url))
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun mediaPermissions(): Array<String> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            arrayOf(
                Manifest.permission.READ_MEDIA_IMAGES,
                Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED
            )
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            arrayOf(Manifest.permission.READ_MEDIA_IMAGES)
        } else {
            arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
        }

    private fun hasSelectedMediaPermission(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE &&
            checkSelfPermission(Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED) ==
            PackageManager.PERMISSION_GRANTED

    private fun hasImagePermission(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            checkSelfPermission(Manifest.permission.READ_MEDIA_IMAGES) == PackageManager.PERMISSION_GRANTED ||
                hasSelectedMediaPermission()
        } else {
            checkSelfPermission(Manifest.permission.READ_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
        }

    /** 主扫描只强制要求图片权限；未授权视频时仍可读取所有单文件动态照片。 */
    private fun hasMediaPermission(): Boolean = hasImagePermission()

    private fun requestMediaPermissions(result: MethodChannel.Result) {
        pendingPermissionResult?.error("CANCELLED", "permission request replaced", null)
        pendingPermissionResult = result
        requestPermissions(mediaPermissions(), 100)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 100) {
            pendingPermissionResult?.success(hasImagePermission())
            pendingPermissionResult = null
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 101) {
            val result = pendingDeleteResult
            pendingDeleteResult = null
            result?.success(
                if (resultCode == Activity.RESULT_OK) pendingDeleteCount else 0
            )
        }
    }

    private fun scanImages(result: MethodChannel.Result) {
        try {
            if (!hasMediaPermission()) {
                result.success(emptyList<Map<String, Any>>())
                return
            }
            val list = mutableListOf<Map<String, Any>>()
            val projection = arrayOf(
                MediaStore.Images.Media._ID,
                MediaStore.Images.Media.DISPLAY_NAME,
                MediaStore.Images.Media.DATA,
                MediaStore.Images.Media.SIZE,
                MediaStore.Images.Media.DATE_ADDED,
                MediaStore.Images.Media.DATE_MODIFIED,
                MediaStore.Images.Media.BUCKET_ID,
                MediaStore.Images.Media.BUCKET_DISPLAY_NAME
            )
            val sortOrder = "${MediaStore.Images.Media.DATE_ADDED} DESC"
            contentResolver.query(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                projection,
                null,
                null,
                sortOrder
            )?.use { c ->
                val idCol = c.getColumnIndexOrThrow(MediaStore.Images.Media._ID)
                val nameCol = c.getColumnIndexOrThrow(MediaStore.Images.Media.DISPLAY_NAME)
                val dataCol = c.getColumnIndexOrThrow(MediaStore.Images.Media.DATA)
                val sizeCol = c.getColumnIndexOrThrow(MediaStore.Images.Media.SIZE)
                val addedCol = c.getColumnIndexOrThrow(MediaStore.Images.Media.DATE_ADDED)
                val modifiedCol = c.getColumnIndexOrThrow(MediaStore.Images.Media.DATE_MODIFIED)
                val bucketIdCol = c.getColumnIndexOrThrow(MediaStore.Images.Media.BUCKET_ID)
                val bucketNameCol = c.getColumnIndexOrThrow(MediaStore.Images.Media.BUCKET_DISPLAY_NAME)
                while (c.moveToNext()) {
                    val id = c.getLong(idCol)
                    val displayName = c.getString(nameCol) ?: "image_$id.jpg"
                    val uri = ContentUris.withAppendedId(
                        MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                        id
                    )
                    val path = resolveMediaPath(
                        c.getString(dataCol),
                        uri,
                        c.getString(bucketIdCol),
                        displayName
                    ) ?: continue
                    list.add(
                        mapOf(
                            "id" to id,
                            "path" to path,
                            "size" to File(path).length(),
                            "added" to c.getLong(addedCol),
                            "modified" to c.getLong(modifiedCol),
                            "bucketId" to c.getString(bucketIdCol),
                            "bucketName" to c.getString(bucketNameCol)
                        )
                    )
                }
            }
            result.success(list)
        } catch (e: Exception) {
            result.error("SCAN_FAILED", e.message, null)
        }
    }

    /**
     * 优先使用 MediaStore.DATA；云媒体或受限媒体没有可读路径时，按相册+文件名
     * 物化到应用缓存。
     */
    private fun resolveMediaPath(
        dataPath: String?,
        uri: Uri,
        bucketId: String?,
        displayName: String
    ): String? {
        if (!dataPath.isNullOrBlank()) {
            val file = File(dataPath)
            if (file.exists() && file.canRead()) return file.absolutePath
        }
        return try {
            val safeBucket = (bucketId ?: "root").replace(Regex("[^A-Za-z0-9_-]"), "_")
            val safeName = displayName.replace(Regex("""[\\/:*?"<>|]"""), "_")
            val directory = File(cacheDir, "media_scan").apply { mkdirs() }
            val target = File(directory, "${safeBucket}_$safeName")
            contentResolver.openInputStream(uri)?.use { input ->
                target.outputStream().use { output -> input.copyTo(output) }
            } ?: return null
            target.absolutePath
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    /** 生成缩略图 JPEG 字节（按 max 边长降采样；API 28+ 用 ImageDecoder 快速解码）。 */
    private fun loadThumbnail(path: String, max: Int): ByteArray? {
        return try {
            val file = File(path)
            if (!file.exists()) return null
            var bmp: Bitmap? = null
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val src = ImageDecoder.createSource(file)
                bmp = ImageDecoder.decodeBitmap(src) { decoder, info, _ ->
                    val w = info.size.width
                    val h = info.size.height
                    val scale = max.toFloat() / maxOf(w, h)
                    if (scale < 1f) {
                        decoder.setTargetSize(
                            (w * scale).toInt().coerceAtLeast(1),
                            (h * scale).toInt().coerceAtLeast(1)
                        )
                    }
                    decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                }
            } else {
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeFile(path, bounds)
                if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
                var sample = 1
                while (bounds.outWidth / (sample * 2) >= max && bounds.outHeight / (sample * 2) >= max) {
                    sample *= 2
                }
                bmp = BitmapFactory.decodeFile(
                    path,
                    BitmapFactory.Options().apply { inSampleSize = sample }
                )
                if (bmp != null) {
                    val w = bmp.width
                    val h = bmp.height
                    val scale = max.toFloat() / maxOf(w, h)
                    if (scale < 1f) {
                        bmp = Bitmap.createScaledBitmap(
                            bmp,
                            (w * scale).toInt().coerceAtLeast(1),
                            (h * scale).toInt().coerceAtLeast(1),
                            true
                        )
                    }
                }
            }
            val bos = ByteArrayOutputStream()
            bmp?.compress(Bitmap.CompressFormat.JPEG, 80, bos)
            bmp?.recycle()
            bos.toByteArray()
        } catch (e: Exception) {
            null
        }
    }

    /** 把提取的视频写入系统相册（Movies/AnimPhoto），返回是否成功。 */
    private fun saveVideoToGallery(srcPath: String, displayName: String): Boolean {
        return try {
            val file = File(srcPath)
            if (!file.exists()) return false
            val resolver = contentResolver
            val values = ContentValues().apply {
                put(MediaStore.Video.Media.DISPLAY_NAME, displayName)
                put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
                put(
                    MediaStore.Video.Media.RELATIVE_PATH,
                    Environment.DIRECTORY_MOVIES + "/AnimPhoto"
                )
                put(MediaStore.Video.Media.IS_PENDING, 1)
            }
            val uri: Uri = resolver.insert(
                MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
                values
            ) ?: return false
            resolver.openOutputStream(uri)?.use { out ->
                file.inputStream().use { it.copyTo(out) }
            } ?: run {
                resolver.delete(uri, null, null)
                return false
            }
            values.clear()
            values.put(MediaStore.Video.Media.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            true
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    /** 一次发起系统批量删除确认；Android 11 以上必须由系统授权删除非自有媒体。 */
    private fun startDeleteImages(ids: List<Long>, result: MethodChannel.Result) {
        pendingDeleteResult?.error("CANCELLED", "delete request replaced", null)
        pendingDeleteResult = result
        pendingDeleteCount = ids.size
        val uris = ids
            .filter { it > 0 }
            .map {
                ContentUris.withAppendedId(
                    MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                    it
                )
            }
        if (uris.isEmpty()) {
            pendingDeleteResult = null
            pendingDeleteCount = 0
            result.success(0)
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                val deleteRequest = MediaStore.createDeleteRequest(contentResolver, uris)
                startIntentSenderForResult(
                    deleteRequest.intentSender,
                    101,
                    null,
                    0,
                    0,
                    0
                )
            } catch (e: Exception) {
                e.printStackTrace()
                pendingDeleteResult = null
                pendingDeleteCount = 0
                result.success(deleteImagesDirectly(uris))
            }
        } else {
            pendingDeleteResult = null
            pendingDeleteCount = 0
            result.success(deleteImagesDirectly(uris))
        }
    }

    private fun deleteImagesDirectly(uris: List<Uri>): Int {
        var deleted = 0
        for (uri in uris) {
            try {
                if (contentResolver.delete(uri, null, null) > 0) {
                    deleted++
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
        return deleted
    }

    /** 把转换产物写入系统相册（Pictures/AnimPhoto），返回是否成功。 */
    private fun saveJpegToGallery(srcPath: String, displayName: String): Boolean {
        return try {
            val file = File(srcPath)
            if (!file.exists()) return false
            val resolver = contentResolver
            val exif = ExifInterface(file.absolutePath)
            val dateTaken = parseExifDateTaken(exif)
            val width = exif.getAttributeInt(ExifInterface.TAG_IMAGE_WIDTH, 0)
            val height = exif.getAttributeInt(ExifInterface.TAG_IMAGE_LENGTH, 0)
            val orientation = exif.getAttributeInt(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.ORIENTATION_NORMAL
            )
            val values = ContentValues().apply {
                put(MediaStore.Images.Media.DISPLAY_NAME, displayName)
                put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
                put(
                    MediaStore.Images.Media.RELATIVE_PATH,
                    Environment.DIRECTORY_PICTURES + "/AnimPhoto"
                )
                put(MediaStore.Images.Media.DATE_TAKEN, dateTaken)
                put(MediaStore.Images.Media.SIZE, file.length())
                if (width > 0) put(MediaStore.Images.Media.WIDTH, width)
                if (height > 0) put(MediaStore.Images.Media.HEIGHT, height)
                put(MediaStore.Images.Media.ORIENTATION, orientation)
                put(MediaStore.Images.Media.IS_PENDING, 1)
            }
            val uri: Uri = resolver.insert(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                values
            ) ?: return false
            resolver.openOutputStream(uri)?.use { out ->
                file.inputStream().use { it.copyTo(out) }
            } ?: run {
                resolver.delete(uri, null, null)
                return false
            }
            values.clear()
            values.put(MediaStore.Images.Media.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            true
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    private fun parseExifDateTaken(exif: ExifInterface): Long {
        val raw = exif.getAttribute(ExifInterface.TAG_DATETIME_ORIGINAL)
            ?: exif.getAttribute(ExifInterface.TAG_DATETIME)
            ?: return System.currentTimeMillis()
        return try {
            val format = SimpleDateFormat("yyyy:MM:dd HH:mm:ss", Locale.US)
            format.timeZone = TimeZone.getDefault()
            format.parse(raw)?.time ?: System.currentTimeMillis()
        } catch (e: Exception) {
            System.currentTimeMillis()
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        thumbnailExecutor.shutdown()
    }
}
