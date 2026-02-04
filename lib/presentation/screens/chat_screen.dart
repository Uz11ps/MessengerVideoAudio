import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:messenger_app/data/models/message_model.dart';
import 'package:messenger_app/data/models/chat_model.dart';
import 'package:messenger_app/data/models/user_model.dart';
import 'package:messenger_app/data/repositories/chat_repository.dart';
import 'package:messenger_app/logic/blocs/chat_bloc.dart';
import 'package:messenger_app/logic/blocs/auth_bloc.dart';
import 'package:messenger_app/presentation/screens/call_screen.dart';
import 'package:messenger_app/presentation/screens/user_profile_screen.dart';
import 'package:messenger_app/presentation/screens/group_profile_screen.dart';
import 'package:messenger_app/core/encryption_service.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';

class ChatDetailScreen extends StatefulWidget {
  final String chatId;
  final ChatModel? chat;
  const ChatDetailScreen({super.key, required this.chatId, this.chat});

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final TextEditingController _messageController = TextEditingController();
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isRecording = false;
  MessageModel? _replyingToMessage;

  Future<UserModel?> _getOtherUser() async {
    if (widget.chat?.isGroup == true) return null;
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return null;
    final currentUserId = authState.user.id;
    final participants = widget.chatId.split('_');
    final otherUserId = participants.firstWhere(
      (id) => id != currentUserId,
      orElse: () => participants.first,
    );
    return context.read<ChatRepository>().getUserById(otherUserId);
  }

  MessageModel? _getReplyMessage(String messageId) {
    // Получаем сообщение из текущего списка сообщений
    final state = context.read<ChatBloc>().state;
    if (state is ChatMessagesLoaded) {
      try {
        return state.messages.firstWhere((m) => m.id == messageId);
      } catch (e) {
        return null;
      }
    }
    return null;
  }

  void _showProfile(BuildContext context) async {
    final chatRepo = context.read<ChatRepository>();
    final authBloc = context.read<AuthBloc>();
    
    if (widget.chat?.isGroup == true) {
      // Показываем профиль группы
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MultiRepositoryProvider(
            providers: [
              RepositoryProvider.value(value: chatRepo),
            ],
            child: MultiBlocProvider(
              providers: [
                BlocProvider.value(value: authBloc),
              ],
              child: GroupProfileScreen(chat: widget.chat!),
            ),
          ),
        ),
      );
    } else {
      // Показываем профиль пользователя
      final otherUser = await _getOtherUser();
      if (otherUser != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => UserProfileScreen(user: otherUser),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final directory = await getApplicationDocumentsDirectory();
        final path = '${directory.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _audioRecorder.start(const RecordConfig(), path: path);
        setState(() => _isRecording = true);
      }
    } catch (e) {
      debugPrint('Error starting recording: $e');
    }
  }

  Future<void> _stopRecording() async {
    try {
      final path = await _audioRecorder.stop();
      setState(() => _isRecording = false);
      if (path != null) {
        context.read<ChatBloc>().add(ChatMessageSent(
              chatId: widget.chatId,
              type: MessageType.audio,
              file: File(path),
            ));
      }
    } catch (e) {
      debugPrint('Error stopping recording: $e');
    }
  }

  void _playAudio(String url) async {
    await _audioPlayer.play(UrlSource('http://83.166.246.225:3000$url'));
  }

  void _showImageFullScreen(String url) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(backgroundColor: Colors.black),
          body: Center(
            child: InteractiveViewer(
              child: Image.network('http://83.166.246.225:3000$url'),
            ),
          ),
        ),
      ),
    );
  }

  void _playVideo(String url) {
    // В будущем можно использовать video_player пакет для полноценного видеоплеера
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Воспроизведение видео будет реализовано')),
    );
  }

  void _showCallTypeSelection(BuildContext context) {
    final chatRepo = context.read<ChatRepository>();
    final authBloc = context.read<AuthBloc>();

    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.video_call, color: Colors.blue),
              title: const Text('Видеозвонок'),
              onTap: () {
                Navigator.pop(context);
                _initiateCall(context, chatRepo, authBloc, 'video');
              },
            ),
            ListTile(
              leading: const Icon(Icons.call, color: Colors.green),
              title: const Text('Аудиозвонок'),
              onTap: () {
                Navigator.pop(context);
                _initiateCall(context, chatRepo, authBloc, 'audio');
              },
            ),
          ],
        ),
      ),
    );
  }

  void _initiateCall(BuildContext context, ChatRepository chatRepo, AuthBloc authBloc, String type) {
    try {
      final authState = authBloc.state;
      if (authState is! AuthAuthenticated) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ошибка авторизации')),
        );
        return;
      }
      final currentUserId = authState.user.id;
      final chat = widget.chat;
      
      if (chat != null && chat.isGroup) {
        // Групповой звонок
        final participantIds = chat.participants.where((id) => id != currentUserId).toList();
        chatRepo.startGroupCall(participantIds, widget.chatId, type);
      } else {
        // Обычный звонок
        final participants = widget.chatId.split('_');
        final otherUserId = participants.firstWhere(
          (id) => id != currentUserId,
          orElse: () => participants.first,
        );
        chatRepo.startCall(otherUserId, widget.chatId, type);
      }
      
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CallScreen(
            channelName: widget.chatId, 
            appId: '9f3bf11c90364991926390fae2a67c92', 
            callType: type,
            isGroupCall: chat?.isGroup ?? false,
            participantIds: chat?.participants ?? [],
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ошибка при начале звонка')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () => _showProfile(context),
          child: widget.chat?.isGroup == true
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.group, size: 20),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        widget.chat?.groupName ?? 'Групповой чат',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                )
              : FutureBuilder<UserModel?>(
                  future: _getOtherUser(),
                  builder: (context, snapshot) {
                    if (snapshot.hasData && snapshot.data != null) {
                      final user = snapshot.data!;
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundImage: user.photoUrl != null
                                ? CachedNetworkImageProvider('http://83.166.246.225:3000${user.photoUrl}')
                                : null,
                            child: user.photoUrl == null
                                ? Text(user.displayName?.substring(0, 1).toUpperCase() ?? 'U')
                                : null,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              user.displayName ?? user.email ?? user.phoneNumber ?? 'Пользователь',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      );
                    }
                    return const Text('Чат');
                  },
                ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.videocam),
            onPressed: () => _showCallTypeSelection(context),
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showProfile(context),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: BlocBuilder<ChatBloc, ChatState>(
              builder: (context, state) {
                if (state is ChatInitial) {
                  context.read<ChatBloc>().add(ChatMessagesStarted(widget.chatId));
                }
                if (state is ChatMessagesLoaded) {
                  return ListView.builder(
                    reverse: true,
                    itemCount: state.messages.length,
                    itemBuilder: (context, index) {
                      final message = state.messages[index];
                      final authState = context.read<AuthBloc>().state;
                      final isMe = authState is AuthAuthenticated && 
                                   message.senderId == authState.user.id;
                      return _buildMessageItem(message, isMe);
                    },
                  );
                }
                return const Center(child: CircularProgressIndicator());
              },
            ),
          ),
          _buildInputArea(),
        ],
      ),
    );
  }

  void _showMessageOptions(BuildContext context, MessageModel message, bool isMe) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Копировать'),
              onTap: () {
                Navigator.pop(context);
                if (message.type == MessageType.text && message.text != null) {
                  final decryptedText = EncryptionService.decrypt(message.text!);
                  Clipboard.setData(ClipboardData(text: decryptedText));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Сообщение скопировано')),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text('Ответить'),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _replyingToMessage = message;
                });
              },
            ),
            if (isMe) ...[
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Удалить', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _deleteMessage(message);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _deleteMessage(MessageModel message) async {
    try {
      final chatRepo = context.read<ChatRepository>();
      final result = await chatRepo.deleteMessage(widget.chatId, message.id);
      
      if (mounted) {
        if (result['success'] == true) {
          // Обновляем список сообщений через ChatBloc
          context.read<ChatBloc>().add(ChatMessageDeleted(
            chatId: widget.chatId,
            messageId: message.id,
          ));
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Сообщение удалено'), backgroundColor: Colors.green),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['error'] ?? 'Ошибка при удалении сообщения'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка при удалении сообщения: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildMessageItem(MessageModel message, bool isMe) {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) {
      return const SizedBox.shrink();
    }
    
    return GestureDetector(
      onLongPress: () => _showMessageOptions(context, message, isMe),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isMe ? Colors.blue[100] : Colors.grey[200],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              // Показываем ответ на сообщение если есть
              if (message.replyToMessageId != null) ...[
                Builder(
                  builder: (context) {
                    final replyMessage = _getReplyMessage(message.replyToMessageId!);
                    if (replyMessage != null) {
                      final currentUserId = authState.user.id;
                      final isReplyFromMe = replyMessage.senderId == currentUserId;
                      
                      return FutureBuilder<UserModel?>(
                        future: isReplyFromMe 
                            ? Future.value(authState.user)
                            : context.read<ChatRepository>().getUserById(replyMessage.senderId),
                        builder: (context, userSnapshot) {
                          String senderName = 'Пользователь';
                          String? senderPhotoUrl;
                          if (isReplyFromMe) {
                            senderName = 'Вы';
                            senderPhotoUrl = authState.user.photoUrl;
                          } else if (userSnapshot.hasData && userSnapshot.data != null) {
                            final user = userSnapshot.data!;
                            senderName = user.displayName ?? user.email ?? user.phoneNumber ?? 'Пользователь';
                            senderPhotoUrl = user.photoUrl;
                          }
                          
                          return Container(
                            padding: const EdgeInsets.all(10),
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: isMe 
                                  ? Colors.purple.shade50.withOpacity(0.3)
                                  : Colors.purple.shade100.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                              border: Border(
                                left: BorderSide(width: 4, color: Colors.purple.shade600),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Аватар отправителя оригинального сообщения
                                CircleAvatar(
                                  radius: 16,
                                  backgroundImage: senderPhotoUrl != null
                                      ? CachedNetworkImageProvider('http://83.166.246.225:3000$senderPhotoUrl')
                                      : null,
                                  child: senderPhotoUrl == null
                                      ? Text(
                                          senderName.isNotEmpty ? senderName[0].toUpperCase() : 'U',
                                          style: const TextStyle(fontSize: 12, color: Colors.white),
                                        )
                                      : null,
                                  backgroundColor: Colors.purple.shade600,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Имя отправителя
                                      Text(
                                        senderName,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.purple.shade700,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      // Текст оригинального сообщения
                                      Text(
                                        replyMessage.type == MessageType.text
                                            ? EncryptionService.decrypt(replyMessage.text ?? '')
                                            : replyMessage.type == MessageType.image
                                                ? '📷 Фото'
                                                : replyMessage.type == MessageType.video
                                                    ? '🎥 Видео'
                                                    : replyMessage.type == MessageType.audio
                                                        ? '🎤 Голосовое сообщение'
                                                        : replyMessage.type == MessageType.file
                                                            ? '📎 Файл'
                                                            : 'Медиа',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey.shade700,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ],
              if (message.type == MessageType.text) 
                Text(EncryptionService.decrypt(message.text ?? '')),
              if (message.type == MessageType.image) 
                GestureDetector(
                  onTap: () => _showImageFullScreen(message.mediaUrl!),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      'http://83.166.246.225:3000${message.mediaUrl!}',
                      width: 200,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          width: 200,
                          height: 200,
                          color: Colors.grey[300],
                          child: Center(
                            child: CircularProgressIndicator(
                              value: loadingProgress.expectedTotalBytes != null
                                  ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                  : null,
                            ),
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          width: 200,
                          height: 200,
                          color: Colors.grey[300],
                          child: const Icon(Icons.error),
                        );
                      },
                    ),
                  ),
                ),
              if (message.type == MessageType.video)
                GestureDetector(
                  onTap: () => _playVideo(message.mediaUrl!),
                  child: Container(
                    width: 200,
                    height: 150,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        const Icon(Icons.play_circle_filled, color: Colors.white, size: 50),
                        if (message.mediaUrl != null)
                          Positioned(
                            bottom: 8,
                            right: 8,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Icon(Icons.videocam, color: Colors.white, size: 16),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              if (message.type == MessageType.audio) 
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.play_arrow),
                      onPressed: () => _playAudio(message.mediaUrl!),
                    ),
                    const Text('Голосовое сообщение'),
                  ],
                ),
              if (message.type == MessageType.file) 
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.insert_drive_file),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        message.mediaUrl?.split('/').last ?? 'Файл',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 4),
              Text(
                DateFormat('HH:mm').format(message.timestamp),
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.attach_file),
            onSelected: (value) async {
              if (value == 'photo') {
                final picker = ImagePicker();
                final image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
                if (image != null && mounted) {
                  context.read<ChatBloc>().add(ChatMessageSent(
                    chatId: widget.chatId,
                    type: MessageType.image,
                    file: File(image.path),
                  ));
                }
              } else if (value == 'camera') {
                final picker = ImagePicker();
                final image = await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
                if (image != null && mounted) {
                  context.read<ChatBloc>().add(ChatMessageSent(
                    chatId: widget.chatId,
                    type: MessageType.image,
                    file: File(image.path),
                  ));
                }
              } else if (value == 'video') {
                final picker = ImagePicker();
                final video = await picker.pickVideo(source: ImageSource.gallery);
                if (video != null && mounted) {
                  context.read<ChatBloc>().add(ChatMessageSent(
                    chatId: widget.chatId,
                    type: MessageType.video,
                    file: File(video.path),
                  ));
                }
              } else if (value == 'video_camera') {
                final picker = ImagePicker();
                final video = await picker.pickVideo(source: ImageSource.camera);
                if (video != null && mounted) {
                  context.read<ChatBloc>().add(ChatMessageSent(
                    chatId: widget.chatId,
                    type: MessageType.video,
                    file: File(video.path),
                  ));
                }
              } else if (value == 'file') {
                final result = await FilePicker.platform.pickFiles(
                  type: FileType.any,
                  allowMultiple: false,
                );
                if (result != null && result.files.single.path != null && mounted) {
                  final file = File(result.files.single.path!);
                  final extension = result.files.single.extension?.toLowerCase();
                  
                  MessageType type = MessageType.file;
                  // Поддержка всех форматов изображений
                  if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'heif'].contains(extension)) {
                    type = MessageType.image;
                  }
                  // Поддержка всех форматов видео
                  else if (['mp4', 'mov', 'avi', 'mkv', 'wmv', 'flv', 'webm', '3gp', 'm4v'].contains(extension)) {
                    type = MessageType.video;
                  }

                  context.read<ChatBloc>().add(ChatMessageSent(
                    chatId: widget.chatId,
                    type: type,
                    file: file,
                  ));
                }
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'photo', child: Row(children: [Icon(Icons.photo), SizedBox(width: 8), Text('Фото из галереи')])),
              const PopupMenuItem(value: 'camera', child: Row(children: [Icon(Icons.camera_alt), SizedBox(width: 8), Text('Камера')])),
              const PopupMenuItem(value: 'video', child: Row(children: [Icon(Icons.videocam), SizedBox(width: 8), Text('Видео из галереи')])),
              const PopupMenuItem(value: 'video_camera', child: Row(children: [Icon(Icons.videocam), SizedBox(width: 8), Text('Видео с камеры')])),
              const PopupMenuItem(value: 'file', child: Row(children: [Icon(Icons.insert_drive_file), SizedBox(width: 8), Text('Файл')])),
            ],
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_replyingToMessage != null)
                  Container(
                    padding: const EdgeInsets.all(8),
                    margin: const EdgeInsets.only(bottom: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                      border: const Border(
                        left: BorderSide(width: 3, color: Colors.blue),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Ответ на:',
                                style: TextStyle(fontSize: 12, color: Colors.blue[700]),
                              ),
                              Text(
                                _replyingToMessage!.type == MessageType.text
                                    ? EncryptionService.decrypt(_replyingToMessage!.text ?? '')
                                    : 'Медиа',
                                style: const TextStyle(fontSize: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => setState(() => _replyingToMessage = null),
                        ),
                      ],
                    ),
                  ),
                TextField(
                  controller: _messageController,
                  decoration: const InputDecoration(hintText: 'Сообщение...'),
                  onChanged: (val) => setState(() {}),
                ),
              ],
            ),
          ),
          if (_messageController.text.isEmpty)
            GestureDetector(
              onLongPress: _startRecording,
              onLongPressUp: _stopRecording,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Icon(Icons.mic, color: _isRecording ? Colors.red : Colors.blue),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.send),
              onPressed: () {
                final text = _messageController.text.trim();
                if (text.isNotEmpty) {
                  context.read<ChatBloc>().add(ChatMessageSent(
                    chatId: widget.chatId,
                    text: text,
                    replyToMessageId: _replyingToMessage?.id,
                  ));
                  _messageController.clear();
                  setState(() {
                    _replyingToMessage = null;
                  });
                }
              },
            ),
        ],
      ),
    );
  }
}
