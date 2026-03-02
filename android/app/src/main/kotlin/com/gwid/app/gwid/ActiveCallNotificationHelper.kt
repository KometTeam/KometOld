package com.gwid.app.gwid

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/**
 * Отображает постоянное уведомление во время активного звонка.
 * Содержит кнопки «Выкл. микро / Вкл. микро» и «Сбросить».
 * Держит приложение в foreground-приоритете, не позволяя системе убить процесс.
 */
class ActiveCallNotificationHelper(private val context: Context) {

    companion object {
        const val ACTIVE_CALL_CHANNEL_ID   = "active_call"
        const val ACTIVE_CALL_CHANNEL_NAME = "Активный звонок"
        const val ACTIVE_CALL_NOTIFICATION_ID = 1001

        const val ACTION_MUTE_CALL     = "com.gwid.app.ACTION_MUTE_CALL"
        const val ACTION_UNMUTE_CALL   = "com.gwid.app.ACTION_UNMUTE_CALL"
        const val ACTION_END_CALL_ONGOING = "com.gwid.app.ACTION_END_CALL_ONGOING"

        const val EXTRA_CONTACT_NAME   = "contact_name"
        const val EXTRA_IS_MUTED       = "is_muted"
    }

    init {
        createActiveCallChannel()
    }

    private fun createActiveCallChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val importance = NotificationManager.IMPORTANCE_LOW // тихое, без звука
            val channel = NotificationChannel(
                ACTIVE_CALL_CHANNEL_ID,
                ACTIVE_CALL_CHANNEL_NAME,
                importance
            ).apply {
                description = "Уведомление во время активного звонка"
                enableVibration(false)
                setShowBadge(false)
                setSound(null, null)
                enableLights(false)
            }
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(channel)
        }
    }

    /**
     * Показывает / обновляет ongoing-уведомление активного звонка.
     *
     * @param contactName Имя собеседника
     * @param isMuted     Текущее состояние микрофона
     * @param durationSec Длительность звонка в секундах (для текста)
     */
    fun showOrUpdateNotification(
        contactName: String,
        isMuted: Boolean,
        durationSec: Int = 0
    ) {
        val notification = buildNotification(contactName, isMuted, durationSec)
        try {
            NotificationManagerCompat.from(context)
                .notify(ACTIVE_CALL_NOTIFICATION_ID, notification)
        } catch (e: SecurityException) {
            android.util.Log.e("ActiveCallNotif", "Нет разрешения на уведомление", e)
        }
    }

    /** Строит объект уведомления без отображения. */
    fun buildNotification(
        contactName: String,
        isMuted: Boolean,
        durationSec: Int = 0
    ): Notification {
        // Intent — открыть приложение при нажатии на само уведомление
        val openAppIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val openAppPendingIntent = PendingIntent.getActivity(
            context, 0, openAppIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Кнопка «Выкл. микро» / «Вкл. микро»
        val muteAction   = if (isMuted) ACTION_UNMUTE_CALL else ACTION_MUTE_CALL
        val muteLabel    = if (isMuted) "Вкл. микро" else "Выкл. микро"
        val muteIcon     = if (isMuted)
            android.R.drawable.ic_btn_speak_now
        else
            android.R.drawable.ic_lock_silent_mode

        val muteIntent = Intent(muteAction).apply {
            putExtra(EXTRA_CONTACT_NAME, contactName)
            putExtra(EXTRA_IS_MUTED, isMuted)
        }
        val mutePendingIntent = PendingIntent.getBroadcast(
            context, 10, muteIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Кнопка «Сбросить»
        val endIntent = Intent(ACTION_END_CALL_ONGOING).apply {
            putExtra(EXTRA_CONTACT_NAME, contactName)
        }
        val endPendingIntent = PendingIntent.getBroadcast(
            context, 11, endIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Текст длительности
        val durationText = formatDuration(durationSec)
        val contentText  = if (isMuted) "Микрофон выключен · $durationText" else durationText

        return NotificationCompat.Builder(context, ACTIVE_CALL_CHANNEL_ID)
            .setSmallIcon(R.drawable.notification_icon)
            .setContentTitle("Звонок с $contactName")
            .setContentText(contentText)
            .setOngoing(true)           // нельзя смахнуть
            .setAutoCancel(false)
            .setShowWhen(false)
            .setOnlyAlertOnce(true)     // не пищит при каждом update
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentIntent(openAppPendingIntent)
            .addAction(muteIcon, muteLabel, mutePendingIntent)
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "Сбросить",
                endPendingIntent
            )
            .build()
    }

    /** Убирает ongoing-уведомление (звонок завершён). */
    fun cancelNotification() {
        NotificationManagerCompat.from(context).cancel(ACTIVE_CALL_NOTIFICATION_ID)
    }

    private fun formatDuration(seconds: Int): String {
        val m = seconds / 60
        val s = seconds % 60
        return "%d:%02d".format(m, s)
    }
}
