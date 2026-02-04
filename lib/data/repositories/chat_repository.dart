import 'dart:async';
import 'dart:io';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:messenger_app/core/api_service.dart';
import 'package:messenger_app/data/models/chat_model.dart';
import 'package:messenger_app/data/models/message_model.dart';
import 'package:messenger_app/data/models/user_model.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'package:messenger_app/core/encryption_service.dart';

class ChatRepository {
  final ApiService _apiService;
  final String currentUserId;
  final String token;
  late IO.Socket _socket;
  
  final _messageController = StreamController<MessageModel>.broadcast();
  final _chatsController = StreamController<List<ChatModel>>.broadcast();
  final _callController = StreamController<Map<String, dynamic>>.broadcast();
  final _messageDeletedController = StreamController<String>.broadcast();

  ChatRepository({
    required ApiService apiService,
    required this.currentUserId, 
    required this.token
  }) : _apiService = apiService {
    _initSocket();
  }

  void _initSocket() {
    // Используем порт 3000 для Socket.io
    _socket = IO.io('http://83.166.246.225:3000', 
      IO.OptionBuilder()
        .setTransports(['websocket'])
        .setAuth({'token': token})
        .enableForceNew() // Принудительно новое соединение
        .build()
    );

    _socket.onConnect((_) {
      // При подключении сразу запрашиваем чаты и подписываемся на них
      fetchChats().then((chats) {
        _chatsController.add(chats);
        joinAllChats(chats);
      });
    });

    _socket.onConnectError((data) {
      // Ошибка подключения
    });

    _socket.on('new_message', (data) {
      try {
        final message = MessageModel.fromMap(data);
        _messageController.add(message);
        
        // При получении сообщения обновляем список чатов
        fetchChats().then((chats) {
          _chatsController.add(chats);
        }).catchError((e) {});
      } catch (e) {
        // Ошибка обработки сообщения
      }
    });

    _socket.on('incoming_call', (data) {
      _callController.add(data);
    });

    _socket.on('incoming_group_call', (data) {
      _callController.add({...data, 'isGroup': true});
    });

    // Добавим обработку события создания нового чата
    _socket.on('chat_created', (data) {
      fetchChats().then((chats) {
        _chatsController.add(chats);
        joinAllChats(chats);
      });
    });

    // Обработка удаления сообщения
    _socket.on('message_deleted', (data) {
      try {
        final messageId = data['messageId'];
        if (messageId != null) {
          _messageDeletedController.add(messageId);
        }
      } catch (e) {
        // Ошибка обработки удаления сообщения
      }
    });

    // Обработка удаления группы
    _socket.on('group_deleted', (data) {
      fetchChats().then((chats) {
        _chatsController.add(chats);
      });
    });

    // Обработка выхода из группы
    _socket.on('group_left', (data) {
      fetchChats().then((chats) {
        _chatsController.add(chats);
      });
    });
  }

  void joinAllChats(List<ChatModel> chats) {
    for (var chat in chats) {
      _socket.emit('join_chat', chat.id);
    }
  }

  Stream<MessageModel> get onNewMessage => _messageController.stream;
  Stream<Map<String, dynamic>> get onIncomingCall => _callController.stream;
  Stream<String> get onMessageDeleted => _messageDeletedController.stream;

  Future<List<UserModel>> searchUsers(String query) async {
    final results = await _apiService.searchUsers(query);
    return results.map((u) => UserModel.fromMap(u)).toList();
  }

  Future<ChatModel> createChat(String otherUserId) async {
    final result = await _apiService.createChat([currentUserId, otherUserId]);
    return ChatModel.fromMap(result);
  }

  Future<ChatModel> createGroupChat(List<String> participants, String groupName) async {
    final result = await _apiService.createGroupChat(participants, groupName, currentUserId);
    return ChatModel.fromMap(result);
  }

  Future<UserModel?> getUserById(String userId) async {
    try {
      final response = await http.get(
        Uri.parse('http://83.166.246.225:3000/api/users/$userId'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        return UserModel.fromMap(jsonDecode(response.body));
      }
    } catch (e) {
      // Ошибка получения пользователя
    }
    return null;
  }

  Future<Map<String, UserModel>> getUsersByIds(List<String> userIds) async {
    final Map<String, UserModel> usersMap = {};
    for (final userId in userIds) {
      final user = await getUserById(userId);
      if (user != null) {
        usersMap[userId] = user;
      }
    }
    return usersMap;
  }

  void startCall(String toUserId, String chatId, String type) {
    _socket.emit('call_user', {
      'to': toUserId,
      'channelName': chatId,
      'type': type,
    });
  }

  void startGroupCall(List<String> participantIds, String chatId, String type) {
    _socket.emit('group_call', {
      'participants': participantIds,
      'channelName': chatId,
      'type': type,
    });
  }

  Future<List<ChatModel>> fetchChats() async {
    try {
      final response = await http.get(
        Uri.parse('http://83.166.246.225:3000/api/chats'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        List<dynamic> data = jsonDecode(response.body);
        return data.map((c) => ChatModel.fromMap(c)).toList();
      }
    } catch (e) {
      // Ошибка получения чатов
    }
    return [];
  }

  Future<List<MessageModel>> fetchMessages(String chatId) async {
    _socket.emit('join_chat', chatId);
    final response = await http.get(
      Uri.parse('http://83.166.246.225:3000/api/chats/$chatId/messages'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode == 200) {
      List<dynamic> data = jsonDecode(response.body);
      return data.map((m) => MessageModel.fromMap(m)).toList();
    }
    return [];
  }

  Stream<List<ChatModel>> getChats() {
    // Сразу загружаем текущие чаты
    fetchChats().then((chats) => _chatsController.add(chats));
    return _chatsController.stream;
  }

  Stream<MessageModel> get onNewMessageStream => _messageController.stream;

  Future<void> sendMessage({
    required String chatId,
    String? text,
    MessageType type = MessageType.text,
    File? file,
    String? replyToMessageId,
  }) async {
    String? mediaUrl;
    if (file != null) {
      mediaUrl = await _apiService.uploadFile(file);
    }

    final messageData = {
      'chatId': chatId,
      'text': text != null ? EncryptionService.encrypt(text) : null,
      'type': type.toString().split('.').last,
      'mediaUrl': mediaUrl,
      if (replyToMessageId != null) 'replyToMessageId': replyToMessageId,
    };
    
    _socket.emit('send_message', messageData);
  }

  Future<bool> addParticipantToGroup(String chatId, String userId) async {
    return await _apiService.addParticipantToGroup(chatId, userId);
  }

  Future<bool> removeParticipantFromGroup(String chatId, String userId) async {
    return await _apiService.removeParticipantFromGroup(chatId, userId);
  }

  Future<bool> deleteGroup(String chatId) async {
    return await _apiService.deleteGroup(chatId);
  }

  Future<Map<String, dynamic>> deleteMessage(String chatId, String messageId) async {
    return await _apiService.deleteMessage(chatId, messageId);
  }

  void acceptCall(String chatId) {
    print('ChatRepository: Sending call_accepted for chatId: $chatId, from: $currentUserId');
    _socket.emit('call_accepted', {
      'chatId': chatId,
      'from': currentUserId,
    });
  }

  void dispose() {
    _socket.dispose();
    _messageController.close();
    _callController.close();
    _messageDeletedController.close();
  }
}
