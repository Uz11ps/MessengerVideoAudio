import 'package:equatable/equatable.dart';

enum MessageType { text, audio, image, video, file }

class MessageModel extends Equatable {
  final String id;
  final String senderId;
  final String chatId;
  final String? text;
  final MessageType type;
  final String? mediaUrl;
  final DateTime timestamp;
  final String? replyToMessageId;

  const MessageModel({
    required this.id,
    required this.senderId,
    required this.chatId,
    this.text,
    required this.type,
    this.mediaUrl,
    required this.timestamp,
    this.replyToMessageId,
  });

  factory MessageModel.fromMap(Map<String, dynamic> map) {
    return MessageModel(
      id: map['id']?.toString() ?? '',
      senderId: map['senderId']?.toString() ?? '',
      chatId: map['chatId']?.toString() ?? '',
      text: map['text'],
      type: _parseMessageType(map['type']),
      mediaUrl: map['mediaUrl'],
      timestamp: _parseTimestamp(map['timestamp']),
      replyToMessageId: map['replyToMessageId'],
    );
  }

  static MessageType _parseMessageType(dynamic type) {
    final typeStr = type?.toString() ?? '';
    return MessageType.values.firstWhere(
      (e) => e.toString() == typeStr || e.name == typeStr,
      orElse: () => MessageType.text,
    );
  }

  static DateTime _parseTimestamp(dynamic timestamp) {
    if (timestamp == null) return DateTime.now();
    if (timestamp is int) {
      return DateTime.fromMillisecondsSinceEpoch(timestamp);
    }
    if (timestamp is String) {
      return DateTime.tryParse(timestamp) ?? DateTime.now();
    }
    return DateTime.now();
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'senderId': senderId,
      'chatId': chatId,
      'text': text,
      'type': type.name,
      'mediaUrl': mediaUrl,
      'timestamp': timestamp.millisecondsSinceEpoch,
      if (replyToMessageId != null) 'replyToMessageId': replyToMessageId,
    };
  }

  @override
  List<Object?> get props => [id, senderId, chatId, text, type, mediaUrl, timestamp, replyToMessageId];
}
