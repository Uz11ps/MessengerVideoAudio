import 'dart:convert';
import 'package:equatable/equatable.dart';

class ChatModel extends Equatable {
  final String id;
  final List<String> participants;
  final String? lastMessage;
  final DateTime? lastMessageTimestamp;
  final bool isGroup;
  final String? groupName;
  final String? groupAdminId;

  const ChatModel({
    required this.id,
    required this.participants,
    this.lastMessage,
    this.lastMessageTimestamp,
    this.isGroup = false,
    this.groupName,
    this.groupAdminId,
  });

  factory ChatModel.fromMap(Map<String, dynamic> map) {
    dynamic rawParticipants = map['participants'];
    List<String> participantsList = [];
    if (rawParticipants is String) {
      try {
        participantsList = List<String>.from(jsonDecode(rawParticipants));
      } catch (e) {
        participantsList = [rawParticipants];
      }
    } else if (rawParticipants is Iterable) {
      participantsList = List<String>.from(rawParticipants);
    }

    return ChatModel(
      id: map['id'] ?? '',
      participants: participantsList,
      lastMessage: map['lastMessage'],
      lastMessageTimestamp: map['lastMessageTimestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['lastMessageTimestamp'])
          : null,
      isGroup: map['isGroup'] == 1 || map['isGroup'] == true,
      groupName: map['groupName'],
      groupAdminId: map['groupAdminId'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'participants': jsonEncode(participants),
      'lastMessage': lastMessage,
      'lastMessageTimestamp': lastMessageTimestamp?.millisecondsSinceEpoch,
      'isGroup': isGroup ? 1 : 0,
      'groupName': groupName,
      'groupAdminId': groupAdminId,
    };
  }

  @override
  List<Object?> get props => [id, participants, lastMessage, lastMessageTimestamp, isGroup, groupName, groupAdminId];
}
