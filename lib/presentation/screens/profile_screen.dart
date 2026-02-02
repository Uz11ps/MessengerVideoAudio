import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:messenger_app/core/api_service.dart';
import 'package:messenger_app/logic/blocs/auth_bloc.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late TextEditingController _nameController;
  late TextEditingController _statusController;
  String? _photoUrl;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final user = (context.read<AuthBloc>().state as AuthAuthenticated).user;
    _nameController = TextEditingController(text: user.displayName);
    _statusController = TextEditingController(text: user.status);
    _photoUrl = user.photoUrl;
  }

  Future<void> _updateProfile() async {
    setState(() => _isLoading = true);
    final api = context.read<ApiService>();
    final user = (context.read<AuthBloc>().state as AuthAuthenticated).user;

    final result = await api.updateProfile(
      id: user.id,
      displayName: _nameController.text,
      status: _statusController.text,
      photoUrl: _photoUrl,
    );

    if (result['success'] && mounted) {
      // В идеале здесь нужно обновить состояние AuthBloc, но для простоты:
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Профиль обновлен')),
      );
    }
    setState(() => _isLoading = false);
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      final url = await context.read<ApiService>().uploadFile(File(image.path));
      setState(() => _photoUrl = url);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Профиль')),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                GestureDetector(
                  onTap: _pickImage,
                  child: CircleAvatar(
                    radius: 50,
                    backgroundImage: _photoUrl != null 
                        ? NetworkImage('http://83.166.246.225:3000$_photoUrl') 
                        : null,
                    child: _photoUrl == null ? const Icon(Icons.camera_alt, size: 40) : null,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Имя'),
                ),
                TextField(
                  controller: _statusController,
                  decoration: const InputDecoration(labelText: 'Статус'),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _updateProfile,
                  child: const Text('Сохранить'),
                ),
              ],
            ),
          ),
    );
  }
}
