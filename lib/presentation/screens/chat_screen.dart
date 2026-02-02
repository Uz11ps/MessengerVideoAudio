import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:messenger_app/data/models/message_model.dart';
import 'package:messenger_app/data/models/chat_model.dart';
import 'package:messenger_app/data/repositories/chat_repository.dart';
import 'package:messenger_app/logic/blocs/chat_bloc.dart';
import 'package:messenger_app/logic/blocs/auth_bloc.dart';
import 'package:messenger_app/presentation/screens/call_screen.dart';
import 'package:messenger_app/core/encryption_service.dart';
import 'package:intl/intl.dart';

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
      final currentUserId = (authBloc.state as AuthAuthenticated).user.id;
      final chat = widget.chat;
      
      if (chat != null && chat.isGroup) {
        // Групповой звонок
        final participantIds = chat.participants.where((id) => id != currentUserId).toList();
        print('ChatDetailScreen: Starting group $type call with ${participantIds.length} participants');
        chatRepo.startGroupCall(participantIds, widget.chatId, type);
      } else {
        // Обычный звонок
        final participants = widget.chatId.split('_');
        final otherUserId = participants.firstWhere(
          (id) => id != currentUserId,
          orElse: () => participants.first,
        );
        print('ChatDetailScreen: Starting $type call to $otherUserId');
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
      print('Error starting call: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ошибка при начале звонка')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.chat?.isGroup == true 
          ? (widget.chat?.groupName ?? 'Групповой чат')
          : 'Чат'),
        actions: [
          IconButton(
            icon: const Icon(Icons.videocam),
            onPressed: () => _showCallTypeSelection(context),
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
                      final isMe = message.senderId == (context.read<AuthBloc>().state as AuthAuthenticated).user.id;
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

  Widget _buildMessageItem(MessageModel message, bool isMe) {
    return Align(
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
            if (message.type == MessageType.text) 
              Text(EncryptionService.decrypt(message.text ?? '')),
            if (message.type == MessageType.image) 
              Image.network('http://83.166.246.225:3000${message.mediaUrl!}', width: 200),
            if (message.type == MessageType.audio) 
              IconButton(
                icon: const Icon(Icons.play_arrow),
                onPressed: () => _playAudio(message.mediaUrl!),
              ),
            if (message.type == MessageType.file) 
              const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.attach_file), Text('Файл')]),
            const SizedBox(height: 4),
            Text(
              DateFormat('HH:mm').format(message.timestamp),
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.attach_file),
            onPressed: () async {
              final result = await FilePicker.platform.pickFiles();
              if (result != null && result.files.single.path != null) {
                final file = File(result.files.single.path!);
                final extension = result.files.single.extension?.toLowerCase();
                
                MessageType type = MessageType.file;
                if (['jpg', 'jpeg', 'png', 'gif'].contains(extension)) {
                  type = MessageType.image;
                }

                if (mounted) {
                  context.read<ChatBloc>().add(ChatMessageSent(
                    chatId: widget.chatId,
                    type: type,
                    file: file,
                  ));
                }
              }
            },
          ),
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: const InputDecoration(hintText: 'Сообщение...'),
              onChanged: (val) => setState(() {}),
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
                  context.read<ChatBloc>().add(ChatMessageSent(chatId: widget.chatId, text: text));
                  _messageController.clear();
                  setState(() {});
                }
              },
            ),
        ],
      ),
    );
  }
}
