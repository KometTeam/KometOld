package com.gwid.app.gwid

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import io.flutter.plugin.common.MethodChannel

class CallActionReceiver : BroadcastReceiver() {
    
    companion object {
        private var methodChannel: MethodChannel? = null
        
        fun setMethodChannel(channel: MethodChannel) {
            methodChannel = channel
        }
    }
    
    override fun onReceive(context: Context, intent: Intent) {
        val conversationId = intent.getStringExtra(CallNotificationHelper.EXTRA_CONVERSATION_ID)
        
        when (intent.action) {
            CallNotificationHelper.ACTION_ANSWER -> {
                android.util.Log.d("CallActionReceiver", "Answer call: $conversationId")
                
                // Отменяем уведомление
                CallNotificationHelper(context).cancelIncomingCallNotification()
                
                // Отправляем событие в Flutter
                methodChannel?.invokeMethod("onCallAnswered", mapOf(
                    "conversationId" to conversationId
                ))
                
                // Открываем приложение
                val launchIntent = Intent(context, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                    putExtra(CallNotificationHelper.EXTRA_CONVERSATION_ID, conversationId)
                    putExtra("answer_call", true)
                }
                context.startActivity(launchIntent)
            }
            
            CallNotificationHelper.ACTION_DECLINE -> {
                android.util.Log.d("CallActionReceiver", "Decline call: $conversationId")
                
                // Отменяем уведомление
                CallNotificationHelper(context).cancelIncomingCallNotification()
                
                // Отправляем событие в Flutter
                methodChannel?.invokeMethod("onCallDeclined", mapOf(
                    "conversationId" to conversationId
                ))
            }

            // ── Кнопка «Выкл. микро» из ongoing-уведомления ──────────────────────
            ActiveCallNotificationHelper.ACTION_MUTE_CALL -> {
                android.util.Log.d("CallActionReceiver", "Mute call from notification")
                methodChannel?.invokeMethod("onCallMuteToggled", mapOf("isMuted" to true))
            }

            // ── Кнопка «Вкл. микро» из ongoing-уведомления ───────────────────────
            ActiveCallNotificationHelper.ACTION_UNMUTE_CALL -> {
                android.util.Log.d("CallActionReceiver", "Unmute call from notification")
                methodChannel?.invokeMethod("onCallMuteToggled", mapOf("isMuted" to false))
            }

            // ── Кнопка «Сбросить» из ongoing-уведомления ─────────────────────────
            ActiveCallNotificationHelper.ACTION_END_CALL_ONGOING -> {
                android.util.Log.d("CallActionReceiver", "End call from notification")
                // Убираем само уведомление немедленно
                ActiveCallNotificationHelper(context).cancelNotification()
                methodChannel?.invokeMethod("onCallEndedFromNotification", null)
                // Открываем приложение чтобы CallScreen мог корректно закрыться
                val launchIntent = Intent(context, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                }
                context.startActivity(launchIntent)
            }
        }
    }
}
