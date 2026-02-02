import 'package:equatable/equatable.dart';

class UserModel extends Equatable {
  final String id;
  final String? phoneNumber;
  final String? email;
  final String? displayName;
  final String? photoUrl;
  final String? status;
  final DateTime? lastSeen;

  const UserModel({
    required this.id,
    this.phoneNumber,
    this.email,
    this.displayName,
    this.photoUrl,
    this.status,
    this.lastSeen,
  });

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['id'] ?? '',
      phoneNumber: map['phoneNumber'],
      email: map['email'],
      displayName: map['displayName'],
      photoUrl: map['photoUrl'],
      status: map['status'],
      lastSeen: map['lastSeen'] != null ? DateTime.fromMillisecondsSinceEpoch(map['lastSeen']) : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'phoneNumber': phoneNumber,
      'email': email,
      'displayName': displayName,
      'photoUrl': photoUrl,
      'status': status,
      'lastSeen': lastSeen?.millisecondsSinceEpoch,
    };
  }

  @override
  List<Object?> get props => [id, phoneNumber, email, displayName, photoUrl, status, lastSeen];
}
