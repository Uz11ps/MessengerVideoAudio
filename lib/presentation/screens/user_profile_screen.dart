import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:messenger_app/data/models/user_model.dart';
import 'package:intl/intl.dart';

class UserProfileScreen extends StatelessWidget {
  final UserModel user;

  const UserProfileScreen({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Профиль пользователя'),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 20),
            // Аватар
            CircleAvatar(
              radius: 60,
              backgroundImage: user.photoUrl != null
                  ? CachedNetworkImageProvider('http://83.166.246.225:3000${user.photoUrl}')
                  : null,
              child: user.photoUrl == null
                  ? Text(
                      user.displayName?.substring(0, 1).toUpperCase() ?? 'U',
                      style: const TextStyle(fontSize: 40),
                    )
                  : null,
            ),
            const SizedBox(height: 20),
            // Имя
            Text(
              user.displayName ?? 'Без имени',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            // Статус
            if (user.status != null && user.status!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  user.status!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600], fontSize: 16),
                ),
              ),
            const SizedBox(height: 32),
            // Информация
            _buildInfoTile(
              icon: Icons.phone,
              label: 'Телефон',
              value: user.phoneNumber ?? 'Не указан',
            ),
            _buildInfoTile(
              icon: Icons.email,
              label: 'Email',
              value: user.email ?? 'Не указан',
            ),
            if (user.lastSeen != null)
              _buildInfoTile(
                icon: Icons.access_time,
                label: 'Был(а) в сети',
                value: DateFormat('dd.MM.yyyy HH:mm').format(user.lastSeen!),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoTile({required IconData icon, required String label, required String value}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Card(
        child: ListTile(
          leading: Icon(icon),
          title: Text(label),
          subtitle: Text(value),
        ),
      ),
    );
  }
}
