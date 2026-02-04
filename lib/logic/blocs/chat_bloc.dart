import 'dart:async';
import 'dart:io';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:messenger_app/data/models/chat_model.dart';
import 'package:messenger_app/data/models/message_model.dart';
import 'package:messenger_app/data/repositories/chat_repository.dart';

// Events
abstract class ChatEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class ChatListStarted extends ChatEvent {}

class ChatMessagesStarted extends ChatEvent {
  final String chatId;
  ChatMessagesStarted(this.chatId);
  @override
  List<Object?> get props => [chatId];
}

class ChatMessageSent extends ChatEvent {
  final String chatId;
  final String? text;
  final MessageType type;
  final File? file;
  final String? replyToMessageId;

  ChatMessageSent({
    required this.chatId,
    this.text,
    this.type = MessageType.text,
    this.file,
    this.replyToMessageId,
  });

  @override
  List<Object?> get props => [chatId, text, type, file, replyToMessageId];
}

class ChatMessageDeleted extends ChatEvent {
  final String chatId;
  final String messageId;

  ChatMessageDeleted({
    required this.chatId,
    required this.messageId,
  });

  @override
  List<Object?> get props => [chatId, messageId];
}

// States
abstract class ChatState extends Equatable {
  @override
  List<Object?> get props => [];
}

class ChatInitial extends ChatState {}

class ChatListLoaded extends ChatState {
  final List<ChatModel> chats;
  ChatListLoaded(this.chats);
  @override
  List<Object?> get props => [chats];
}

class ChatMessagesLoaded extends ChatState {
  final List<MessageModel> messages;
  ChatMessagesLoaded(this.messages);
  @override
  List<Object?> get props => [messages];
}

class ChatFailure extends ChatState {
  final String message;
  ChatFailure(this.message);
  @override
  List<Object?> get props => [message];
}

// Bloc
class ChatBloc extends Bloc<ChatEvent, ChatState> {
  final ChatRepository _chatRepository;
  List<MessageModel> _currentMessages = [];
  StreamSubscription? _messageSubscription;
  StreamSubscription? _chatsSubscription;
  StreamSubscription? _messageDeletedSubscription;

  ChatBloc({required ChatRepository chatRepository})
      : _chatRepository = chatRepository,
        super(ChatInitial()) {
    
    _messageSubscription = _chatRepository.onNewMessageStream.listen((message) {
      if (!isClosed) {
        add(_InternalMessageReceived(message));
      }
    }, onError: (e) {});

    // Подписываемся на события удаления сообщений
    _messageDeletedSubscription = _chatRepository.onMessageDeleted.listen((messageId) {
      if (!isClosed) {
        _currentMessages = _currentMessages.where((m) => m.id != messageId).toList();
        if (state is ChatMessagesLoaded) {
          emit(ChatMessagesLoaded(List.from(_currentMessages)));
        }
      }
    }, onError: (e) {});

    on<ChatListStarted>((event, emit) async {
      final initialChats = await _chatRepository.fetchChats();
      _chatRepository.joinAllChats(initialChats);
      emit(ChatListLoaded(initialChats));
      
      // Отменяем старую подписку если есть
      await _chatsSubscription?.cancel();
      _chatsSubscription = _chatRepository.getChats().listen((chats) {
        if (!isClosed) {
          add(_InternalChatsUpdated(chats));
        }
      });
    });

    on<_InternalChatsUpdated>((event, emit) {
      if (!isClosed) {
        emit(ChatListLoaded(event.chats));
      }
    });

    on<ChatMessagesStarted>((event, emit) async {
      emit(ChatInitial());
      try {
        _currentMessages = await _chatRepository.fetchMessages(event.chatId);
        emit(ChatMessagesLoaded(List.from(_currentMessages)));
      } catch (e) {
        emit(ChatFailure(e.toString()));
      }
    });

    on<_InternalMessageReceived>((event, emit) {
      if (!isClosed) {
        // Проверяем, нет ли уже такого сообщения (дубликаты от сокетов)
        if (!_currentMessages.any((m) => m.id == event.message.id)) {
          _currentMessages = [event.message, ..._currentMessages];
          emit(ChatMessagesLoaded(List.from(_currentMessages)));
        }
      }
    });

    on<ChatMessageSent>((event, emit) async {
      try {
        await _chatRepository.sendMessage(
          chatId: event.chatId,
          text: event.text,
          type: event.type,
          file: event.file,
          replyToMessageId: event.replyToMessageId,
        );
      } catch (e) {
        if (!isClosed) emit(ChatFailure(e.toString()));
      }
    });

    on<ChatMessageDeleted>((event, emit) {
      if (!isClosed) {
        _currentMessages = _currentMessages.where((m) => m.id != event.messageId).toList();
        emit(ChatMessagesLoaded(List.from(_currentMessages)));
      }
    });
  }

  @override
  Future<void> close() {
    _messageSubscription?.cancel();
    _chatsSubscription?.cancel();
    _messageDeletedSubscription?.cancel();
    return super.close();
  }
}

class _InternalMessageReceived extends ChatEvent {
  final MessageModel message;
  _InternalMessageReceived(this.message);
  @override
  List<Object?> get props => [message];
}

class _InternalChatsUpdated extends ChatEvent {
  final List<ChatModel> chats;
  _InternalChatsUpdated(this.chats);
  @override
  List<Object?> get props => [chats];
}
