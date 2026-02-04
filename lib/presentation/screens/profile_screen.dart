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
  late TextEditingController _emailController;
  late TextEditingController _phoneController;
  late TextEditingController _passwordController;
  late TextEditingController _otpController;
  String? _photoUrl;
  bool _isLoading = false;
  bool _isLinkingEmail = false;
  bool _isLinkingPhone = false;
  bool _waitingForOtp = false;

  @override
  void initState() {
    super.initState();
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      final user = authState.user;
      _nameController = TextEditingController(text: user.displayName);
      _statusController = TextEditingController(text: user.status);
      _emailController = TextEditingController(text: user.email ?? '');
      _phoneController = TextEditingController(text: user.phoneNumber ?? '');
      _passwordController = TextEditingController();
      _otpController = TextEditingController();
      _photoUrl = user.photoUrl;
    } else {
      _nameController = TextEditingController();
      _statusController = TextEditingController();
      _emailController = TextEditingController();
      _phoneController = TextEditingController();
      _passwordController = TextEditingController();
      _otpController = TextEditingController();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _statusController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _updateProfile() async {
    setState(() => _isLoading = true);
    final api = context.read<ApiService>();
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) {
      setState(() => _isLoading = false);
      return;
    }
    final user = authState.user;

    final result = await api.updateProfile(
      id: user.id,
      displayName: _nameController.text,
      status: _statusController.text,
      photoUrl: _photoUrl,
    );

    if (result['success'] && mounted) {
      // Обновляем состояние AuthBloc с новыми данными пользователя
      if (result['user'] != null) {
        context.read<AuthBloc>().add(AuthUserUpdated(result['user']));
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Профиль обновлен')),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['error'] ?? 'Ошибка обновления профиля')),
      );
    }
    setState(() => _isLoading = false);
  }

  Future<void> _linkEmail() async {
    if (_emailController.text.trim().isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Заполните email и пароль')),
      );
      return;
    }

    setState(() => _isLinkingEmail = true);
    final api = context.read<ApiService>();
    
    final result = await api.linkEmail(_emailController.text.trim(), _passwordController.text);
    
    if (result['success'] && mounted) {
      // Обновляем состояние AuthBloc
      if (result['user'] != null) {
        context.read<AuthBloc>().add(AuthUserUpdated(result['user']));
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['message'] ?? 'Почта успешно привязана')),
      );
      _passwordController.clear();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['message'] ?? 'Ошибка привязки почты')),
      );
    }
    setState(() => _isLinkingEmail = false);
  }

  Future<void> _sendOtpForPhone() async {
    if (_phoneController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите номер телефона')),
      );
      return;
    }

    setState(() => _isLinkingPhone = true);
    final api = context.read<ApiService>();
    
    final result = await api.sendOtp(_phoneController.text.trim());
    
    if (result['success'] && mounted) {
      setState(() {
        _waitingForOtp = true;
        _isLinkingPhone = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Код отправлен на номер телефона')),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['message'] ?? 'Ошибка отправки кода')),
      );
      setState(() => _isLinkingPhone = false);
    }
  }

  Future<void> _linkPhone() async {
    if (_otpController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите код подтверждения')),
      );
      return;
    }

    setState(() => _isLinkingPhone = true);
    final api = context.read<ApiService>();
    
    final result = await api.linkPhone(_phoneController.text.trim(), _otpController.text.trim());
    
    if (result['success'] && mounted) {
      // Обновляем состояние AuthBloc
      if (result['user'] != null) {
        context.read<AuthBloc>().add(AuthUserUpdated(result['user']));
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['message'] ?? 'Телефон успешно привязан')),
      );
      setState(() {
        _waitingForOtp = false;
        _otpController.clear();
      });
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['message'] ?? 'Ошибка привязки телефона')),
      );
    }
    setState(() => _isLinkingPhone = false);
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
      appBar: AppBar(
        title: const Text('Профиль'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              // Выходим из аккаунта - это автоматически вернет на экран авторизации
              context.read<AuthBloc>().add(AuthLoggedOut());
            },
          ),
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
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
                // Отображение и привязка почты
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.email),
                            const SizedBox(width: 8),
                            const Text('Email', style: TextStyle(fontWeight: FontWeight.bold)),
                            const Spacer(),
                            if (BlocBuilder<AuthBloc, AuthState>(
                              builder: (context, state) {
                                if (state is AuthAuthenticated) {
                                  return state.user.email != null
                                      ? const Chip(
                                          label: Text('Привязан'),
                                          backgroundColor: Colors.green,
                                          labelStyle: TextStyle(color: Colors.white),
                                        )
                                      : const Chip(
                                          label: Text('Не привязан'),
                                          backgroundColor: Colors.grey,
                                          labelStyle: TextStyle(color: Colors.white),
                                        );
                                }
                                return const SizedBox.shrink();
                              },
                            ) != null)
                              BlocBuilder<AuthBloc, AuthState>(
                                builder: (context, state) {
                                  if (state is AuthAuthenticated) {
                                    return state.user.email != null
                                        ? const Chip(
                                            label: Text('Привязан'),
                                            backgroundColor: Colors.green,
                                            labelStyle: TextStyle(color: Colors.white),
                                          )
                                        : const Chip(
                                            label: Text('Не привязан'),
                                            backgroundColor: Colors.grey,
                                            labelStyle: TextStyle(color: Colors.white),
                                          );
                                  }
                                  return const SizedBox.shrink();
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        BlocBuilder<AuthBloc, AuthState>(
                          builder: (context, state) {
                            if (state is AuthAuthenticated && state.user.email != null) {
                              return Text(state.user.email ?? '');
                            }
                            return Column(
                              children: [
                                TextField(
                                  controller: _emailController,
                                  decoration: const InputDecoration(
                                    labelText: 'Email',
                                    hintText: 'example@mail.com',
                                  ),
                                  keyboardType: TextInputType.emailAddress,
                                ),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: _passwordController,
                                  decoration: const InputDecoration(
                                    labelText: 'Пароль (минимум 6 символов)',
                                  ),
                                  obscureText: true,
                                ),
                                const SizedBox(height: 8),
                                ElevatedButton(
                                  onPressed: _isLinkingEmail ? null : _linkEmail,
                                  child: _isLinkingEmail
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : const Text('Привязать почту'),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Отображение и привязка телефона
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.phone),
                            const SizedBox(width: 8),
                            const Text('Телефон', style: TextStyle(fontWeight: FontWeight.bold)),
                            const Spacer(),
                            BlocBuilder<AuthBloc, AuthState>(
                              builder: (context, state) {
                                if (state is AuthAuthenticated) {
                                  return state.user.phoneNumber != null
                                      ? const Chip(
                                          label: Text('Привязан'),
                                          backgroundColor: Colors.green,
                                          labelStyle: TextStyle(color: Colors.white),
                                        )
                                      : const Chip(
                                          label: Text('Не привязан'),
                                          backgroundColor: Colors.grey,
                                          labelStyle: TextStyle(color: Colors.white),
                                        );
                                }
                                return const SizedBox.shrink();
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        BlocBuilder<AuthBloc, AuthState>(
                          builder: (context, state) {
                            if (state is AuthAuthenticated && state.user.phoneNumber != null) {
                              return Text(state.user.phoneNumber ?? '');
                            }
                            return Column(
                              children: [
                                TextField(
                                  controller: _phoneController,
                                  decoration: const InputDecoration(
                                    labelText: 'Номер телефона',
                                    hintText: '+79991234567',
                                  ),
                                  keyboardType: TextInputType.phone,
                                  enabled: !_waitingForOtp,
                                ),
                                if (_waitingForOtp) ...[
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: _otpController,
                                    decoration: const InputDecoration(
                                      labelText: 'Код подтверждения',
                                      hintText: '1234',
                                    ),
                                    keyboardType: TextInputType.number,
                                  ),
                                ],
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    if (!_waitingForOtp)
                                      Expanded(
                                        child: ElevatedButton(
                                          onPressed: _isLinkingPhone ? null : _sendOtpForPhone,
                                          child: _isLinkingPhone
                                              ? const SizedBox(
                                                  width: 20,
                                                  height: 20,
                                                  child: CircularProgressIndicator(strokeWidth: 2),
                                                )
                                              : const Text('Отправить код'),
                                        ),
                                      ),
                                    if (_waitingForOtp) ...[
                                      Expanded(
                                        child: OutlinedButton(
                                          onPressed: () {
                                            setState(() {
                                              _waitingForOtp = false;
                                              _otpController.clear();
                                            });
                                          },
                                          child: const Text('Отмена'),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: ElevatedButton(
                                          onPressed: _isLinkingPhone ? null : _linkPhone,
                                          child: _isLinkingPhone
                                              ? const SizedBox(
                                                  width: 20,
                                                  height: 20,
                                                  child: CircularProgressIndicator(strokeWidth: 2),
                                                )
                                              : const Text('Привязать'),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _isLoading ? null : _updateProfile,
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Сохранить профиль'),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () {
                    // Выходим из аккаунта - это автоматически вернет на экран авторизации
                    context.read<AuthBloc>().add(AuthLoggedOut());
                  },
                  icon: const Icon(Icons.logout),
                  label: const Text('Выйти'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                  ),
                ),
              ],
            ),
          ),
    );
  }
}
