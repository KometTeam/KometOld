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
        }
    }
}
