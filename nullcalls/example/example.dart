import 'package:maxcalls_dart/maxcalls_dart.dart';

/// Пример использования maxcalls_dart для Komet Client
void main() async {
  // Инициализация клиента с debug логированием
  final calls = Calls(debug: true);

  // Устанавливаем параметры сессии
  // В реальном приложении эти значения должны сохраняться в SharedPreferences
  calls.setSessionParams(
    mtInstanceId: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',
    clientSessionId: 1,
    deviceId: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',
  );

  try {
    // === Вариант 1: Авторизация с номером телефона ===
    
    print('📱 Запрашиваем код верификации...');
    final phoneNumber = '+79001234567'; // Замените на свой номер
    final verificationToken = await calls.requestVerification(phoneNumber);
    
    print('✅ Код верификации отправлен на $phoneNumber');
    print('Токен верификации: $verificationToken');
    
    // В реальном приложении здесь нужно получить код от пользователя
    print('Введите код из SMS:');
    final code = '123456'; // Замените на реальный код
    
    await calls.enterCode(verificationToken, code);
    print('✅ Авторизация успешна!');

    // === Вариант 2: Авторизация с сохраненным токеном ===
    // final savedToken = 'ваш-сохраненный-токен';
    // await calls.loginWithToken(savedToken);
    // print('✅ Вход выполнен с сохраненным токеном');

    // === Исходящий звонок ===
    
    print('\n📞 Совершаем исходящий звонок...');
    final targetUserId = 'user-id-to-call'; // Замените на реальный ID
    
    try {
      final connection = await calls.call(targetUserId, isVideo: false);
      
      print('✅ Звонок установлен!');
      print('Local stream: ${connection.localStream}');
      print('Remote stream: ${connection.remoteStream}');
      print('Connection state: ${connection.connectionState}');
      
      // Ждем установления соединения
      await connection.waitForConnection();
      print('✅ WebRTC соединение установлено!');
      
      // Работаем со звонком...
      // В Flutter можно отобразить видео используя RTCVideoRenderer
      
      // Завершаем звонок
      await connection.close();
      print('📞 Звонок завершен');
      
    } catch (e) {
      print('❌ Ошибка при звонке: $e');
    }

    // === Ожидание входящего звонка ===
    
    print('\n⏳ Ждем входящий звонок (блокирующий вызов)...');
    final incomingConnection = await calls.waitForCall();
    
    print('✅ Получен входящий звонок!');
    print('Local stream: ${incomingConnection.localStream}');
    print('Remote stream: ${incomingConnection.remoteStream}');
    
    // Ждем установления соединения
    await incomingConnection.waitForConnection();
    print('✅ Входящий звонок принят!');
    
    // Работаем со звонком...
    
    // Завершаем звонок
    await incomingConnection.close();
    print('📞 Входящий звонок завершен');

  } catch (e) {
    print('❌ Ошибка: $e');
  } finally {
    // Закрываем соединение
    await calls.close();
    print('\n👋 Соединение закрыто');
  }
}

/// Пример интеграции с Komet Client
void kometClientIntegration() async {
  // В Komet Client можно использовать те же параметры сессии
  // что и для основного ApiService
  
  /*
  final prefs = await SharedPreferences.getInstance();
  
  final calls = Calls(debug: true);
  calls.setSessionParams(
    mtInstanceId: prefs.getString('session_mt_instanceid'),
    clientSessionId: prefs.getInt('session_client_session_id'),
    deviceId: prefs.getString('spoof_deviceid'),
  );
  
  // Используем тот же auth token
  final authToken = prefs.getString('authToken');
  if (authToken != null) {
    await calls.loginWithToken(authToken);
  }
  
  // Теперь можно совершать звонки
  // Пример исходящего звонка
  final connection = await calls.call('target-user-id');
  
  // Отобразить UI звонка с видео/аудио
  // showCallScreen(connection.localStream, connection.remoteStream);
  
  // Пример входящего звонка
  final incomingConnection = await calls.waitForCall();
  // showIncomingCallScreen(incomingConnection.localStream, incomingConnection.remoteStream);
  */
}
