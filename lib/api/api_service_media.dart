part of 'api_service.dart';

extension ApiServiceMedia on ApiService {
  // sendVoiceMessage перенесена в основной файл api_service.dart

  Future<Profile?> updateProfileText(
    String firstName,
    String lastName,
    String description,
  ) async {
    try {
      await waitUntilOnline();

      final Map<String, dynamic> payload = {
        "firstName": firstName,
        "lastName": lastName,
        "description": description,
      };

      final int seq = await _sendMessage(16, payload);
      _log(
        '➡️ SEND: opcode=16, payload=${truncatePayloadObjectForLog(payload)}',
      );

      final response = await messages.firstWhere(
        (msg) => msg['seq'] == seq && msg['opcode'] == 16,
      );

      final Map<String, dynamic>? respPayload =
          response['payload'] as Map<String, dynamic>?;

      if (respPayload == null) {
        throw Exception('Пустой ответ сервера на изменение профиля');
      }

      if (respPayload.containsKey('error')) {
        final humanMessage =
            respPayload['localizedMessage'] ??
            respPayload['message'] ??
            respPayload['title'] ??
            respPayload['error'];
        throw Exception(humanMessage.toString());
      }

      final profileJson = respPayload['profile'];
      if (profileJson is Map<String, dynamic>) {
        _lastChatsPayload ??= {
          'chats': <dynamic>[],
          'contacts': <dynamic>[],
          'profile': null,
          'presence': null,
          'config': null,
        };
        _lastChatsPayload!['profile'] = profileJson;

        return Profile.fromJson(profileJson);
      }
    } catch (e) {
      _log('❌ Ошибка при обновлении профиля через opcode 16: $e');
    }
    return null;
  }

  Future<Profile?> updateProfilePhoto(String firstName, String lastName) async {
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
      if (image == null) return null;

      print("Запрашиваем URL для загрузки фото...");
      final int seq = await _sendMessage(80, {"count": 1});
      final response = await messages.firstWhere((msg) => msg['seq'] == seq);
      final String uploadUrl = response['payload']['url'];
      print("URL получен: $uploadUrl");

      print("Загружаем фото на сервер...");
      var request = http.MultipartRequest('POST', Uri.parse(uploadUrl));
      request.files.add(await http.MultipartFile.fromPath('file', image.path));
      var streamedResponse = await request.send();
      var httpResponse = await http.Response.fromStream(streamedResponse);

      if (httpResponse.statusCode != 200) {
        throw Exception("Ошибка загрузки фото: ${httpResponse.body}");
      }

      final uploadResult = jsonDecode(httpResponse.body);
      final String photoToken = uploadResult['photos'].values.first['token'];
      print("Фото загружено, получен токен: $photoToken");

      print("Привязываем фото к профилю...");
      final payload = {
        "firstName": firstName,
        "lastName": lastName,
        "photoToken": photoToken,
        "avatarType": "USER_AVATAR",
      };
      final int seq16 = await _sendMessage(16, payload);
      print("Запрос на смену аватара отправлен.");

      final resp16 = await messages.firstWhere(
        (msg) => msg['seq'] == seq16 && msg['opcode'] == 16,
      );

      final Map<String, dynamic>? respPayload16 =
          resp16['payload'] as Map<String, dynamic>?;

      if (respPayload16 == null) {
        throw Exception('Пустой ответ сервера на смену аватара');
      }

      if (respPayload16.containsKey('error')) {
        final humanMessage =
            respPayload16['localizedMessage'] ??
            respPayload16['message'] ??
            respPayload16['title'] ??
            respPayload16['error'];
        throw Exception(humanMessage.toString());
      }

      final profileJson = respPayload16['profile'];
      if (profileJson is Map<String, dynamic>) {
        _lastChatsPayload ??= {
          'chats': <dynamic>[],
          'contacts': <dynamic>[],
          'profile': null,
          'presence': null,
          'config': null,
        };
        _lastChatsPayload!['profile'] = profileJson;

        final profile = Profile.fromJson(profileJson);
        await ProfileCacheService().syncWithServerProfile(profile);
        return profile;
      }
    } catch (e) {
      print("!!! Ошибка в процессе смены аватара: $e");
    }
    return null;
  }

  Future<Map<String, dynamic>> fetchPresetAvatars() async {
    await waitUntilOnline();

    final int seq = await _sendMessage(25, {});
    _log('➡️ SEND: opcode=25, payload={}');

    final resp = await messages.firstWhere(
      (msg) => msg['seq'] == seq && msg['opcode'] == 25,
    );

    final payload = resp['payload'] as Map<String, dynamic>?;
    return payload ?? <String, dynamic>{};
  }

  Future<Profile?> setPresetAvatar({
    required String firstName,
    required String lastName,
    required int photoId,
  }) async {
    try {
      await waitUntilOnline();

      final payload = {
        "firstName": firstName,
        "lastName": lastName,
        "photoId": photoId,
        "avatarType": "PRESET_AVATAR",
      };

      final int seq16 = await _sendMessage(16, payload);
      _log(
        '➡️ SEND: opcode=16 (PRESET_AVATAR), payload=${truncatePayloadObjectForLog(payload)}',
      );

      final resp16 = await messages.firstWhere(
        (msg) => msg['seq'] == seq16 && msg['opcode'] == 16,
      );

      final Map<String, dynamic>? respPayload16 =
          resp16['payload'] as Map<String, dynamic>?;

      if (respPayload16 == null) {
        throw Exception('Пустой ответ сервера на установку пресет‑аватара');
      }

      if (respPayload16.containsKey('error')) {
        final humanMessage =
            respPayload16['localizedMessage'] ??
            respPayload16['message'] ??
            respPayload16['title'] ??
            respPayload16['error'];
        throw Exception(humanMessage.toString());
      }

      final profileJson = respPayload16['profile'];
      if (profileJson is Map<String, dynamic>) {
        _lastChatsPayload ??= {
          'chats': <dynamic>[],
          'contacts': <dynamic>[],
          'profile': null,
          'presence': null,
          'config': null,
        };
        _lastChatsPayload!['profile'] = profileJson;

        return Profile.fromJson(profileJson);
      }
    } catch (e) {
      _log('❌ Ошибка при установке пресет‑аватара: $e');
    }
    return null;
  }

  Future<void> sendPhotoMessage(
    int chatId, {
    String? localPath,
    String? caption,
    int? cidOverride,
    int? senderId,
  }) async {
    try {
      XFile? image;
      if (localPath != null) {
        image = XFile(localPath);
      } else {
        final picker = ImagePicker();
        image = await picker.pickImage(source: ImageSource.gallery);
        if (image == null) return;
      }

      await waitUntilOnline();

      final int seq80 = await _sendMessage(80, {"count": 1});
      final resp80 = await messages.firstWhere((m) => m['seq'] == seq80);
      final String uploadUrl = resp80['payload']['url'];

      var request = http.MultipartRequest('POST', Uri.parse(uploadUrl));
      request.files.add(await http.MultipartFile.fromPath('file', image.path));
      var streamed = await request.send();
      var httpResp = await http.Response.fromStream(streamed);
      if (httpResp.statusCode != 200) {
        throw Exception(
          'Ошибка загрузки фото: ${httpResp.statusCode} ${httpResp.body}',
        );
      }
      final uploadJson = jsonDecode(httpResp.body) as Map<String, dynamic>;
      final Map photos = uploadJson['photos'] as Map;
      if (photos.isEmpty) throw Exception('Не получен токен фото');
      final String photoToken = (photos.values.first as Map)['token'];

      // Шифруем caption если в чате включено шифрование. Сами байты фото
      // не шифруются (полный encrypted-upload не перенесён из 0.4.1).
      String? processedCaption = caption;
      try {
        final cfg = await ChatEncryptionService.getConfigForChat(chatId);
        if (caption != null &&
            caption.trim().isNotEmpty &&
            cfg != null &&
            cfg.sendEncrypted &&
            ChatEncryptionService.hasNewKey(cfg) &&
            !ChatEncryptionService.isEncryptedMessage(caption)) {
          processedCaption = ChatEncryptionService.encryptWithPassword(
            cfg.password,
            caption.trim(),
            profileName: cfg.obfuscationProfile,
          );
        }
      } catch (_) {}

      final int cid = cidOverride ?? DateTime.now().millisecondsSinceEpoch;
      final payload = {
        "chatId": chatId,
        "message": {
          "text": processedCaption?.trim() ?? "",
          "cid": cid,
          "elements": [],
          "attaches": [
            {"_type": "PHOTO", "photoToken": photoToken},
          ],
        },
        "notify": true,
      };

      clearChatsCache();

      if (localPath != null) {
        _emitLocal({
          'ver': 11,
          'cmd': 1,
          'seq': -1,
          'opcode': 128,
          'payload': {
            'chatId': chatId,
            'message': {
              'id': 'local_$cid',
              'sender': senderId ?? 0,
              'time': DateTime.now().millisecondsSinceEpoch,
              'text': processedCaption?.trim() ?? '',
              'type': 'USER',
              'cid': cid,
              'attaches': [
                {'_type': 'PHOTO', 'url': 'file://$localPath'},
              ],
            },
          },
        });
      }

      _sendMessage(64, payload);
    } catch (e) {
      print('Ошибка отправки фото-сообщения: $e');
    }
  }

  Future<void> sendPhotoMessages(
    int chatId, {
    required List<String> localPaths,
    String? caption,
    int? senderId,
  }) async {
    if (localPaths.isEmpty) return;
    try {
      await waitUntilOnline();

      final encSvc = EncryptedFileService.instance;

      // Шифруем caption (текстовую часть фото-сообщения), если в чате
      // включено шифрование.
      String? processedCaption = caption;
      try {
        final cfg = await ChatEncryptionService.getConfigForChat(chatId);
        if (caption != null &&
            caption.trim().isNotEmpty &&
            cfg != null &&
            cfg.sendEncrypted &&
            ChatEncryptionService.hasNewKey(cfg) &&
            !ChatEncryptionService.isEncryptedMessage(caption)) {
          processedCaption = ChatEncryptionService.encryptWithPassword(
            cfg.password,
            caption.trim(),
            profileName: cfg.obfuscationProfile,
          );
        }
      } catch (_) {}

      // Фото делим на два потока:
      //   encrypted → FILE API (opcode 87): MAX не транскодирует CRPT-blob
      //   plain     → PHOTO API (opcode 80): стандартный путь
      final List<String> encryptedPaths = []; // оригинальные пути
      final List<String> encTempPaths = [];   // temp CRPT-файлы (удалить после)
      final List<String> plainPaths = [];

      for (final path in localPaths) {
        try {
          final enc = await encSvc.encryptForUpload(
            chatId: chatId,
            originalPath: path,
          );
          if (enc != null) {
            encryptedPaths.add(path);
            encTempPaths.add(enc);
          } else {
            plainPaths.add(path);
          }
        } catch (_) {
          // Если шифрование почему-то упало — отправляем plain (best-effort).
          plainPaths.add(path);
        }
      }

      if (plainPaths.isNotEmpty) {
        final int cid = DateTime.now().millisecondsSinceEpoch;
        _emitLocal({
          'ver': 11,
          'cmd': 1,
          'seq': -1,
          'opcode': 128,
          'payload': {
            'chatId': chatId,
            'message': {
              'id': 'local_$cid',
              'sender': senderId ?? 0,
              'time': DateTime.now().millisecondsSinceEpoch,
              'text': caption?.trim() ?? '', // локально показываем оригинал
              'type': 'USER',
              'cid': cid,
              'attaches': [
                for (final p in plainPaths)
                  {'_type': 'PHOTO', 'url': 'file://$p'},
              ],
            },
          },
        });

        final List<Map<String, String>> photoTokens = [];
        for (final path in plainPaths) {
          final int seq80 = await _sendMessage(80, {"count": 1});
          final resp80 = await messages.firstWhere((m) => m['seq'] == seq80);
          final String uploadUrl = resp80['payload']['url'];

          var request = http.MultipartRequest('POST', Uri.parse(uploadUrl));
          request.files.add(await http.MultipartFile.fromPath('file', path));
          var streamed = await request.send();
          var httpResp = await http.Response.fromStream(streamed);
          if (httpResp.statusCode != 200) {
            throw Exception(
              'Ошибка загрузки фото: ${httpResp.statusCode} ${httpResp.body}',
            );
          }
          final uploadJson = jsonDecode(httpResp.body) as Map<String, dynamic>;
          final Map photos = uploadJson['photos'] as Map;
          if (photos.isEmpty) throw Exception('Не получен токен фото');
          final String photoToken = (photos.values.first as Map)['token'];
          photoTokens.add({"token": photoToken});
        }

        final payload = {
          "chatId": chatId,
          "message": {
            "text": processedCaption?.trim() ?? "",
            "cid": cid,
            "elements": [],
            "attaches": [
              for (final t in photoTokens)
                {"_type": "PHOTO", "photoToken": t["token"]},
            ],
          },
          "notify": true,
        };

        clearChatsCache();

        final queueItem = QueueItem(
          id: 'photo_$cid',
          type: QueueItemType.sendMessage,
          opcode: 64,
          payload: payload,
          createdAt: DateTime.now(),
          persistent: true,
          chatId: chatId,
          cid: cid,
        );

        unawaited(
          _sendMessage(64, payload)
              .then((_) {
                _queueService.removeFromQueue(queueItem.id);
              })
              .catchError((e) {
                print('Ошибка отправки фото: $e');
                _queueService.addToQueue(queueItem);
              }),
        );
      }

      for (int i = 0; i < encTempPaths.length; i++) {
        final encPath = encTempPaths[i];
        final origPath = encryptedPaths[i];

        // try/finally расширен на pre-upload-await'ы (getConfigForChat,
        // File.length()), чтобы при любом сбое temp CRPT-файл удалялся.
        try {
          final origName = origPath.split(RegExp(r'[/\\]')).last;
          final cfg2 = await ChatEncryptionService.getConfigForChat(chatId);
          final ext = cfg2?.encryptedFileExtension ?? 'bin';
          final nameProfile = cfg2?.encryptedFileNameProfile ?? 'file_seq';
          final uploadName =
              encSvc.encryptedFileName(origName, ext, profile: nameProfile);
          final origSize = await File(origPath).length();

          final int cid = DateTime.now().millisecondsSinceEpoch + i;

          // Локальное preview — показываем оригинальный файл
          _emitLocal({
            'ver': 11,
            'cmd': 1,
            'seq': -1,
            'opcode': 128,
            'payload': {
              'chatId': chatId,
              'message': {
                'id': 'local_$cid',
                'sender': senderId ?? 0,
                'time': DateTime.now().millisecondsSinceEpoch,
                'text': caption?.trim() ?? '', // локально оригинал
                'type': 'USER',
                'cid': cid,
                'attaches': [
                  {
                    '_type': 'FILE',
                    '_komet_enc': true,
                    'name': origName,
                    'size': origSize,
                    'url': 'file://$origPath',
                  },
                ],
              },
            },
          });

          final int seq87 = await _sendMessage(87, {"count": 1});
          final resp87 = await messages.firstWhere((m) => m['seq'] == seq87);
          if (resp87['payload'] == null ||
              resp87['payload']['info'] == null ||
              (resp87['payload']['info'] as List).isEmpty) {
            throw Exception('Неверный ответ на Opcode 87');
          }
          final uploadInfo = (resp87['payload']['info'] as List).first;
          final String uploadUrl = uploadInfo['url'];
          final int fileId = uploadInfo['fileId'];

          // Heartbeat (opcode 65) пока идёт upload — иначе MAX считает,
          // что мы отвалились, и фейлит загрузку.
          Timer? hb = Timer.periodic(const Duration(seconds: 5), (_) {
            _sendMessage(65, {"chatId": chatId, "type": "FILE"});
          });

          try {
            var request = http.MultipartRequest('POST', Uri.parse(uploadUrl));
            request.files.add(
              await http.MultipartFile.fromPath(
                'file',
                encPath,
                filename: uploadName,
              ),
            );
            var streamed = await request.send();
            var httpResp = await http.Response.fromStream(streamed);
            if (httpResp.statusCode != 200) {
              throw Exception('Upload error ${httpResp.statusCode}');
            }

            await messages
                .timeout(const Duration(seconds: 30))
                .firstWhere(
                  (m) =>
                      m['opcode'] == 136 && m['payload']['fileId'] == fileId,
                );
            hb.cancel();

            // Сохраняем оригинальное имя в meta-сервис, чтобы при получении
            // сообщения с тем же fileId bubble показал нормальное имя файла,
            // а не маскировочное "file_xxx.bin".
            await KometEncMetaService.instance.saveOriginalName(
              fileId,
              origName,
            );
            KometEncMetaService.instance.cacheNameSync(fileId, origName);

            // Помечаем файл как уже "скачанный" — он у нас локально.
            FileDownloadProgressService().updateProgress(
              fileId.toString(),
              1.0,
            );
            // Расшифрованная версия = оригинальный origPath.
            KometEncMetaService.instance.cacheDecPath(fileId, origPath);
            // Сохраняем мапинг fileId→origPath чтобы пережил перезапуск.
            try {
              final prefs2 = await SharedPreferences.getInstance();
              final fileIdMap2 =
                  prefs2.getStringList('file_id_to_path_map') ?? [];
              fileIdMap2.removeWhere((m) => m.startsWith('$fileId:'));
              fileIdMap2.add('$fileId:$origPath');
              await prefs2.setStringList('file_id_to_path_map', fileIdMap2);
            } catch (_) {}
            // Если это изображение — кэшируем байты для превью
            final ext2 = origName.split('.').last.toLowerCase();
            if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic']
                .contains(ext2)) {
              try {
                final origFile = File(origPath);
                final size2 = await origFile.length();
                if (size2 <= 10 * 1024 * 1024) {
                  final previewBytes = await origFile.readAsBytes();
                  KometEncMetaService.instance.cachePreview(
                    fileId,
                    previewBytes,
                  );
                }
              } catch (_) {}
            }

            final payload = {
              "chatId": chatId,
              "message": {
                "text": processedCaption?.trim() ?? "",
                "cid": cid,
                "elements": [],
                "attaches": [
                  {
                    "_type": "FILE",
                    "_komet_enc": true,
                    "fileId": fileId,
                    "originalName": origName,
                  },
                ],
              },
              "notify": true,
            };
            clearChatsCache();
            unawaited(
              _sendMessage(64, payload).catchError((e) {
                print('Ошибка отправки зашифрованного фото-файла: $e');
              }),
            );
          } finally {
            hb.cancel();
            try {
              await File(encPath).delete();
            } catch (_) {}
          }
        } catch (e) {
          print('Ошибка отправки зашифрованного фото[$i]: $e');
          try {
            await File(encPath).delete();
          } catch (_) {}
        }
      }
    } catch (e) {
      print('Ошибка отправки фото-сообщений: $e');
    }
  }

  Future<void> sendFileMessage(
    int chatId, {
    String? caption,
    int? senderId,
  }) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
      );

      if (result == null || result.files.single.path == null) {
        print("Выбор файла отменен");
        return;
      }

      final String origPath = result.files.single.path!;
      final String origName = result.files.single.name;
      final int origSize = result.files.single.size;

      await waitUntilOnline();

      // Шифруем caption (текстовая часть).
      String? processedCaption = caption;
      try {
        final cfg = await ChatEncryptionService.getConfigForChat(chatId);
        if (caption != null &&
            caption.trim().isNotEmpty &&
            cfg != null &&
            cfg.sendEncrypted &&
            ChatEncryptionService.hasNewKey(cfg) &&
            !ChatEncryptionService.isEncryptedMessage(caption)) {
          processedCaption = ChatEncryptionService.encryptWithPassword(
            cfg.password,
            caption.trim(),
            profileName: cfg.obfuscationProfile,
          );
        }
      } catch (_) {}

      // Шифруем байты файла, если в чате включено шифрование.
      // Если шифрование не настроено / выключено — encryptForUpload вернёт
      // null, и файл уйдёт в открытом виде (как было в 0.4.2 до мержа).
      final encSvc = EncryptedFileService.instance;
      String? encTempPath;
      String filePath = origPath; // что реально заливаем
      String fileName = origName; // имя при upload
      int fileSize = origSize; // размер при upload
      bool isEncrypted = false;
      try {
        final tmp = await encSvc.encryptForUpload(
          chatId: chatId,
          originalPath: origPath,
        );
        if (tmp != null) {
          encTempPath = tmp;
          filePath = tmp;
          // Маскируем имя файла перед сервером по выбранному пользователем
          // профилю (e.g. `file_..._....bin`, `Document_4827.bin`,
          // `IMG_20260315_142233.bin` и т.д.).
          final cfg2 = await ChatEncryptionService.getConfigForChat(chatId);
          final ext = cfg2?.encryptedFileExtension ?? 'bin';
          final nameProfile = cfg2?.encryptedFileNameProfile ?? 'file_seq';
          fileName =
              encSvc.encryptedFileName(origName, ext, profile: nameProfile);
          fileSize = await File(tmp).length();
          isEncrypted = true;
        }
      } catch (e) {
        print('Не удалось зашифровать файл, шлём plain: $e');
      }

      final int cid = DateTime.now().millisecondsSinceEpoch;
      // Локальное preview — показываем оригинал (имя/путь оригинального файла).
      _emitLocal({
        'ver': 11,
        'cmd': 1,
        'seq': -1,
        'opcode': 128,
        'payload': {
          'chatId': chatId,
          'message': {
            'id': 'local_$cid',
            'sender': senderId ?? 0,
            'time': DateTime.now().millisecondsSinceEpoch,
            'text': caption?.trim() ?? '', // локально оригинал caption
            'type': 'USER',
            'cid': cid,
            'attaches': [
              {
                '_type': 'FILE',
                if (isEncrypted) '_komet_enc': true,
                'name': origName, // оригинальное имя в локальном превью
                'size': origSize,
                'url': 'file://$origPath',
              },
            ],
          },
        },
      });

      final int seq87 = await _sendMessage(87, {"count": 1});
      final resp87 = await messages.firstWhere((m) => m['seq'] == seq87);

      if (resp87['payload'] == null ||
          resp87['payload']['info'] == null ||
          (resp87['payload']['info'] as List).isEmpty) {
        throw Exception('Неверный ответ на Opcode 87: отсутствует "info"');
      }

      final uploadInfo = (resp87['payload']['info'] as List).first;
      final String uploadUrl = uploadInfo['url'];
      final int fileId = uploadInfo['fileId'];
      final String token = uploadInfo['token'];

      print('Получен fileId: $fileId, token: $token и URL: $uploadUrl');

      Timer? heartbeatTimer;
      heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        _sendMessage(65, {"chatId": chatId, "type": "FILE"});
        print('Heartbeat отправлен для загрузки файла');
      });

      try {
        var request = http.MultipartRequest('POST', Uri.parse(uploadUrl));
        // При шифровании передаём filename = fileName (маскировочное),
        // иначе — обычный путь.
        if (isEncrypted) {
          request.files.add(
            await http.MultipartFile.fromPath(
              'file',
              filePath,
              filename: fileName,
            ),
          );
        } else {
          request.files.add(
            await http.MultipartFile.fromPath('file', filePath),
          );
        }
        var streamed = await request.send();
        var httpResp = await http.Response.fromStream(streamed);
        if (httpResp.statusCode != 200) {
          throw Exception(
            'Ошибка загрузки файла: ${httpResp.statusCode} ${httpResp.body}',
          );
        }

        print('Файл успешно загружен на сервер. Ожидаем подтверждение...');

        final uploadCompleteMsg = await messages
            .timeout(const Duration(seconds: 30))
            .firstWhere(
              (msg) =>
                  msg['opcode'] == 136 && msg['payload']['fileId'] == fileId,
            );

        print(
          'Получено подтверждение загрузки файла: ${uploadCompleteMsg['payload']}',
        );

        heartbeatTimer.cancel();

        if (isEncrypted) {
          // Сохраняем оригинальное имя в meta-сервис, чтобы при получении
          // сообщения с тем же fileId bubble показал нормальное имя.
          await KometEncMetaService.instance.saveOriginalName(
            fileId,
            origName,
          );
          KometEncMetaService.instance.cacheNameSync(fileId, origName);

          // Помечаем файл как уже "скачанный" — он у нас локально.
          FileDownloadProgressService().updateProgress(
            fileId.toString(),
            1.0,
          );
          KometEncMetaService.instance.cacheDecPath(fileId, origPath);
          try {
            final prefs2 = await SharedPreferences.getInstance();
            final fileIdMap2 =
                prefs2.getStringList('file_id_to_path_map') ?? [];
            fileIdMap2.removeWhere((m) => m.startsWith('$fileId:'));
            fileIdMap2.add('$fileId:$origPath');
            await prefs2.setStringList('file_id_to_path_map', fileIdMap2);
          } catch (_) {}
          // Если это изображение — кэшируем превью.
          final ext2 = origName.split('.').last.toLowerCase();
          if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic']
              .contains(ext2)) {
            try {
              final origFile = File(origPath);
              final size2 = await origFile.length();
              if (size2 <= 10 * 1024 * 1024) {
                final previewBytes = await origFile.readAsBytes();
                KometEncMetaService.instance.cachePreview(
                  fileId,
                  previewBytes,
                );
              }
            } catch (_) {}
          }
        }

        final payload = {
          "chatId": chatId,
          "message": {
            "text": processedCaption?.trim() ?? "",
            "cid": cid,
            "elements": [],
            "attaches": [
              if (isEncrypted)
                {
                  "_type": "FILE",
                  "_komet_enc": true,
                  "fileId": fileId,
                  "originalName": origName,
                }
              else
                {"_type": "FILE", "fileId": fileId},
            ],
          },
          "notify": true,
        };

        clearChatsCache();

        final queueItem = QueueItem(
          id: 'file_$cid',
          type: QueueItemType.sendMessage,
          opcode: 64,
          payload: payload,
          createdAt: DateTime.now(),
          persistent: true,
          chatId: chatId,
          cid: cid,
        );

        unawaited(
          _sendMessage(64, payload)
              .then((_) {
                _queueService.removeFromQueue(queueItem.id);
              })
              .catchError((e) {
                print('Ошибка отправки файла: $e');
                _queueService.addToQueue(queueItem);
              }),
        );
        print('Сообщение о файле (Opcode 64) отправлено.');
      } finally {
        heartbeatTimer.cancel();
        // Удаляем temp-CRPT файл.
        if (encTempPath != null) {
          try {
            await File(encTempPath).delete();
          } catch (_) {}
        }
      }
    } catch (e) {
      print('Ошибка отправки файла: $e');
    }
  }

  Future<void> sendContactMessage(
    int chatId, {
    required int contactId,
    int? senderId,
  }) async {
    try {
      await waitUntilOnline();

      final int cid = DateTime.now().millisecondsSinceEpoch;

      _emitLocal({
        'ver': 11,
        'cmd': 1,
        'seq': -1,
        'opcode': 128,
        'payload': {
          'chatId': chatId,
          'message': {
            'id': 'local_$cid',
            'sender': senderId ?? 0,
            'time': DateTime.now().millisecondsSinceEpoch,
            'text': '',
            'type': 'USER',
            'cid': cid,
            'attaches': [
              {'_type': 'CONTACT', 'contactId': contactId},
            ],
          },
        },
      });

      final payload = {
        "chatId": chatId,
        "message": {
          "text": "",
          "cid": cid,
          "elements": [],
          "attaches": [
            {"_type": "CONTACT", "contactId": contactId},
          ],
        },
        "notify": true,
      };

      final queueItem = QueueItem(
        id: 'contact_$cid',
        type: QueueItemType.sendMessage,
        opcode: 64,
        payload: payload,
        createdAt: DateTime.now(),
        persistent: true,
        chatId: chatId,
        cid: cid,
      );

      unawaited(
        _sendMessage(64, payload)
            .then((_) {
              _queueService.removeFromQueue(queueItem.id);
            })
            .catchError((e) {
              print('Ошибка отправки контакта: $e');
              _queueService.addToQueue(queueItem);
            }),
      );
    } catch (e) {
      print('Ошибка отправки контакта: $e');
    }
  }

  Future<String> getVideoUrl(int videoId, int chatId, String messageId) async {
    await waitUntilOnline();

    final payload = {
      "videoId": videoId,
      "chatId": chatId,
      "messageId": int.tryParse(messageId) ?? 0,
    };

    try {
      // Use tracked request-response flow to avoid stream race with firstWhere.
      final response = await sendRequest(83, payload).timeout(const Duration(seconds: 15));
      print('Запрашиваем URL для videoId: $videoId');

      if (response['cmd'] == 3) {
        throw Exception(
          'Ошибка получения URL видео: ${response['payload']?['message']}',
        );
      }

      final videoPayload = response['payload'] as Map<String, dynamic>?;
      if (videoPayload == null) {
        throw Exception('Получен пустой payload для видео');
      }

      String? videoUrl =
          videoPayload['MP4_720'] as String? ??
          videoPayload['MP4_480'] as String? ??
          videoPayload['MP4_1080'] as String? ??
          videoPayload['MP4_360'] as String?;

      if (videoUrl == null) {
        final mp4Key = videoPayload.keys.firstWhere(
          (k) => k.startsWith('MP4_'),
          orElse: () => '',
        );
        if (mp4Key.isNotEmpty) {
          videoUrl = videoPayload[mp4Key] as String?;
        }
      }

      if (videoUrl != null) {
        print('URL для videoId: $videoId успешно получен.');
        return videoUrl;
      } else {
        throw Exception('Не найден ни один MP4 URL в ответе');
      }
    } on TimeoutException {
      print('Таймаут ожидания URL для videoId: $videoId');
      throw Exception('Сервер не ответил на запрос видео вовремя');
    } catch (e) {
      print('Ошибка в getVideoUrl: $e');
      rethrow;
    }
  }
}
