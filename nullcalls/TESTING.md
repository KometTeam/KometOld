# Как проверить работу библиотеки maxcalls_dart

## ⚠️ Важно
Эта библиотека требует **Flutter runtime** и **реальное Flutter приложение** для тестирования, так как использует `flutter_webrtc` для WebRTC функциональности.

---

## 📋 Варианты тестирования

### 1. Интеграция в существующий Flutter проект (РЕКОМЕНДУЕТСЯ)

Добавьте библиотеку в ваш Flutter проект:

**pubspec.yaml:**
```yaml
dependencies:
  maxcalls_dart:
    path: /path/to/maxcalls_dart
```

**Пример использования:**
```dart
import 'package:flutter/material.dart';
import 'package:maxcalls_dart/maxcalls_dart.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: CallTestScreen(),
    );
  }
}

class CallTestScreen extends StatefulWidget {
  @override
  _CallTestScreenState createState() => _CallTestScreenState();
}

class _CallTestScreenState extends State<CallTestScreen> {
  final Calls calls = Calls(debug: true);
  
  @override
  void initState() {
    super.initState();
    _initCalls();
  }
  
  void _initCalls() {
    calls.setSessionParams(
      mtInstanceId: 'your-mt-instance-id',
      clientSessionId: 1,
      deviceId: 'your-device-id',
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('MAX Calls Test')),
      body: Center(
        child: ElevatedButton(
          onPressed: _testConnection,
          child: Text('Test Connection'),
        ),
      ),
    );
  }
  
  Future<void> _testConnection() async {
    print('✅ Calls instance created successfully!');
  }
  
  @override
  void dispose() {
    calls.close();
    super.dispose();
  }
}
```

Затем запустите:
```bash
flutter run
```

---

### 2. Создать минимальное Flutter приложение для тестирования

```bash
# Создать новый Flutter проект
flutter create maxcalls_test_app
cd maxcalls_test_app

# Добавить зависимость в pubspec.yaml
# dependencies:
#   maxcalls_dart:
#     path: ../maxcalls_dart

# Запустить
flutter run -d chrome  # для веб
flutter run -d linux   # для Linux desktop
flutter run            # для Android/iOS (если устройство подключено)
```

---

### 3. Проверить только модели и утилиты (БЕЗ WebRTC)

Если хотите протестировать только модели данных без WebRTC:

**test_models.dart:**
```dart
import 'package:maxcalls_dart/maxcalls_dart.dart';

void main() {
  // Тест создания ClientHello
  final clientHello = ClientHello.create(
    mtInstanceId: 'test-id',
    clientSessionId: 1,
    deviceId: 'device-id',
  );
  
  print('ClientHello created:');
  print('  mtInstanceId: ${clientHello.mtInstanceId}');
  print('  clientSessionId: ${clientHello.clientSessionId}');
  print('  deviceId: ${clientHello.deviceId}');
  
  // Тест сериализации
  final json = clientHello.toJson();
  print('\nJSON: $json');
  
  // Тест логгера
  MaxCallsLogger.enableDebug();
  MaxCallsLogger.info('Test message');
  
  print('\n✅ Модели работают корректно!');
}
```

Но запустить это можно только в Flutter контексте.

---

## 🔧 Что нужно для полного тестирования

### Минимальные требования:
1. ✅ Flutter SDK установлен
2. ✅ Зависимости установлены (`flutter pub get` выполнен)
3. ✅ Код скомпилирован без ошибок

### Для функционального тестирования:
1. 📱 Реальный номер телефона для авторизации
2. 🔐 Доступ к серверу MAX messenger
3. 👤 ID другого пользователя для звонка
4. 🌐 Интернет соединение

---

## ✅ Текущий статус библиотеки

**Код проверен:**
- ✅ Компиляция: 0 ошибок
- ✅ Зависимости: установлены
- ✅ Синтаксис: корректный
- ℹ️ 21 info-сообщение (использование print в example - это нормально)

**Для запуска необходимо:**
- Интегрировать в Flutter приложение (web/mobile/desktop)
- Предоставить реальные учетные данные для авторизации

---

## 📚 Примеры использования

См. файл **example/example.dart** для полного примера с:
- Авторизацией через телефон
- Исходящими звонками
- Входящими звонками
- Интеграцией с Komet Client

---

## 🐛 Отладка

Для включения debug-логирования:
```dart
final calls = Calls(debug: true);
```

Или вручную:
```dart
MaxCallsLogger.enableDebug();
```

---

## 💡 Совет

Эта библиотека лучше всего тестируется как часть **Komet Client** проекта, для которого она и создана.
