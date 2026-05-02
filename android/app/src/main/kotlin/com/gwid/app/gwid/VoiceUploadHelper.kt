package com.gwid.app.gwid

import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/**
 * Helper для управления уведомлениями загрузки голосовых сообщений
 */
class VoiceUploadHelper(private val context: Context) {

    companion object {
        const val CHANNEL_ID = "voice_upload"
        const val CHANNEL_NAME = "Отправка голосовых"
        const val CHANNEL_DESC = "Уведомления о процессе отправки голосовых сообщений"
    }

    init {
        createNotificationChannel()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val importance = NotificationManager.IMPORTANCE_LOW
            val channel = android.app.NotificationChannel(CHANNEL_ID, CHANNEL_NAME, importance).apply {
                description = CHANNEL_DESC
                enableVibration(false)
                setShowBadge(false)
                setSound(null, null)
            }
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    /**
     * Показать уведомление о загрузке голосового сообщения
     */
    fun showUploadNotification(
        uploadId: String,
        chatId: Long,
        progress: Int = 0
    ): Int {
        val notificationId = uploadId.hashCode()

        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("chat_id", chatId)
            putExtra("payload", "chat_$chatId")
        }

        val pendingIntent = PendingIntent.getActivity(
            context,
            notificationId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.notification_icon)
            .setContentTitle("Отправка голосового сообщения")
            .setContentText("Загрузка: $progress%")
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setProgress(100, progress, false)
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .setAutoCancel(false)

        try {
            NotificationManagerCompat.from(context).notify(notificationId, builder.build())
        } catch (e: SecurityException) {
            android.util.Log.e("VoiceUploadHelper", "Нет разрешения на уведомления: ${e.message}")
        }

        return notificationId
    }

    /**
     * Обновить прогресс загрузки
     */
    fun updateProgress(uploadId: String, chatId: Long, progress: Int) {
        showUploadNotification(uploadId, chatId, progress)
    }

    /**
     * Показать уведомление об успешной загрузке
     */
    fun showSuccessNotification(uploadId: String, chatId: Long) {
        val notificationId = uploadId.hashCode()

        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("chat_id", chatId)
            putExtra("payload", "chat_$chatId")
        }

        val pendingIntent = PendingIntent.getActivity(
            context,
            notificationId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.notification_icon)
            .setContentTitle("Голосовое сообщение отправлено")
            .setContentText("Сообщение успешно отправлено")
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)

        try {
            NotificationManagerCompat.from(context).notify(notificationId, builder.build())
            // Автоматически скрываем через 2 секунды
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                cancelNotification(notificationId)
            }, 2000)
        } catch (e: SecurityException) {
            android.util.Log.e("VoiceUploadHelper", "Нет разрешения на уведомления: ${e.message}")
        }
    }

    /**
     * Показать уведомление об ошибке
     */
    fun showErrorNotification(uploadId: String, chatId: Long, errorMessage: String) {
        val notificationId = uploadId.hashCode()

        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("chat_id", chatId)
            putExtra("payload", "chat_$chatId")
        }

        val pendingIntent = PendingIntent.getActivity(
            context,
            notificationId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.notification_icon)
            .setContentTitle("Ошибка отправки голосового")
            .setContentText(errorMessage)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)

        try {
            NotificationManagerCompat.from(context).notify(notificationId, builder.build())
        } catch (e: SecurityException) {
            android.util.Log.e("VoiceUploadHelper", "Нет разрешения на уведомления: ${e.message}")
        }
    }

    /**
     * Отменить уведомление
     */
    fun cancelNotification(notificationId: Int) {
        try {
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.cancel(notificationId)
        } catch (e: Exception) {
            android.util.Log.e("VoiceUploadHelper", "Ошибка отмены уведомления: ${e.message}")
        }
    }

    /**
     * Отменить уведомление по uploadId
     */
    fun cancelNotificationByUploadId(uploadId: String) {
        cancelNotification(uploadId.hashCode())
    }
}
