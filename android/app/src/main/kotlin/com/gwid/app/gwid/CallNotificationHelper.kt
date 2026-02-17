package com.gwid.app.gwid

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

class CallNotificationHelper(private val context: Context) {
    
    companion object {
        const val CALL_CHANNEL_ID = "incoming_calls"
        const val CALL_CHANNEL_NAME = "Входящие звонки"
        const val CALL_NOTIFICATION_ID = 999
        
        const val ACTION_ANSWER = "com.gwid.app.ACTION_ANSWER_CALL"
        const val ACTION_DECLINE = "com.gwid.app.ACTION_DECLINE_CALL"
        
        const val EXTRA_CONVERSATION_ID = "conversation_id"
        const val EXTRA_CALLER_NAME = "caller_name"
        const val EXTRA_CALLER_ID = "caller_id"
    }
    
    init {
        createCallChannel()
    }
    
    private fun createCallChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val importance = NotificationManager.IMPORTANCE_HIGH
            val channel = NotificationChannel(CALL_CHANNEL_ID, CALL_CHANNEL_NAME, importance).apply {
                description = "Уведомления о входящих звонках"
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 1000, 500, 1000)
                setSound(null, null) // Отключаем звук, т.к. будет рингтон
                setShowBadge(false)
            }
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }
    
    fun showIncomingCallNotification(
        conversationId: String,
        callerName: String,
        callerId: Long,
        avatarPath: String? = null
    ) {
        // Intent для открытия приложения
        val fullScreenIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_CONVERSATION_ID, conversationId)
            putExtra(EXTRA_CALLER_NAME, callerName)
            putExtra(EXTRA_CALLER_ID, callerId)
            putExtra("show_incoming_call", true)
        }
        
        val fullScreenPendingIntent = PendingIntent.getActivity(
            context,
            0,
            fullScreenIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        // Intent для ответа
        val answerIntent = Intent(ACTION_ANSWER).apply {
            putExtra(EXTRA_CONVERSATION_ID, conversationId)
            putExtra(EXTRA_CALLER_NAME, callerName)
            putExtra(EXTRA_CALLER_ID, callerId)
        }
        val answerPendingIntent = PendingIntent.getBroadcast(
            context,
            1,
            answerIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        // Intent для отклонения
        val declineIntent = Intent(ACTION_DECLINE).apply {
            putExtra(EXTRA_CONVERSATION_ID, conversationId)
        }
        val declinePendingIntent = PendingIntent.getBroadcast(
            context,
            2,
            declineIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        // Создаём notification
        val builder = NotificationCompat.Builder(context, CALL_CHANNEL_ID)
            .setSmallIcon(R.drawable.notification_icon)
            .setContentTitle("Входящий звонок")
            .setContentText(callerName)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setOngoing(true)
            .setAutoCancel(false)
            .setFullScreenIntent(fullScreenPendingIntent, true)
            .addAction(
                android.R.drawable.ic_menu_call,
                "Ответить",
                answerPendingIntent
            )
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "Отклонить",
                declinePendingIntent
            )
        
        // Для Android 12+ используем CallStyle
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // TODO: Добавить Person и CallStyle для более красивого UI
        }
        
        try {
            val notificationManager = NotificationManagerCompat.from(context)
            notificationManager.notify(CALL_NOTIFICATION_ID, builder.build())
        } catch (e: SecurityException) {
            android.util.Log.e("CallNotificationHelper", "Permission denied for notification", e)
        }
    }
    
    fun cancelIncomingCallNotification() {
        val notificationManager = NotificationManagerCompat.from(context)
        notificationManager.cancel(CALL_NOTIFICATION_ID)
    }
}
