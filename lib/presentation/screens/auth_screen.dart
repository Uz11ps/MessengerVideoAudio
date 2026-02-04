import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:messenger_app/logic/blocs/auth_bloc.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  
  String? _verificationId;
  bool _isEmailAuth = false;
  bool _isRegister = false;

  void _resetState() {
    setState(() {
      _verificationId = null;
      // НЕ сбрасываем _isEmailAuth, чтобы пользователь оставался на экране входа по почте
      _isRegister = false;
    });
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthOtpSent) {
          setState(() {
            _verificationId = state.verificationId;
            _isEmailAuth = false; 
          });
          // Показываем уведомление об успешной отправке SMS
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              ScaffoldMessenger.of(context).clearSnackBars();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'SMS код отправлен на ваш номер телефона',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 3),
                  behavior: SnackBarBehavior.floating,
                  margin: EdgeInsets.all(16),
                ),
              );
            }
          });
        } else if (state is AuthFailure) {
          // Уведомления об ошибках теперь показываются в main.dart
          // Здесь только логируем для отладки
        } else if (state is AuthAuthenticated) {
          // Показываем уведомление об успешной авторизации
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              ScaffoldMessenger.of(context).clearSnackBars();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    _isRegister ? 'Регистрация успешна! Вход выполнен.' : 'Вход выполнен успешно!',
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  backgroundColor: Colors.green,
                  duration: const Duration(seconds: 3),
                  behavior: SnackBarBehavior.floating,
                  margin: const EdgeInsets.all(16),
                ),
              );
            }
          });
          // После успешной регистрации НЕ сбрасываем _isEmailAuth, чтобы пользователь остался на экране входа по почте
          if (_isRegister) {
            setState(() {
              _isRegister = false; // Переключаем на режим входа
              // Очищаем поля пароля, но оставляем email
              _passwordController.clear();
              _nameController.clear();
            });
          } else {
            _resetState();
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isEmailAuth 
            ? (_isRegister ? 'Регистрация' : 'Вход по почте') 
            : 'Вход по номеру'
          ),
        ),
        body: BlocBuilder<AuthBloc, AuthState>(
          builder: (context, state) {
            if (state is AuthLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            if (state is AuthAuthenticated) {
              return const Center(child: Text('Успешный вход!'));
            }

            if (!_isEmailAuth) {
              if (state is AuthOtpSent || _verificationId != null) {
                return _buildOtpInput();
              }
              return _buildPhoneInput();
            } else {
              return _buildEmailInput();
            }
          },
        ),
      ),
    );
  }

  Widget _buildPhoneInput() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextField(
            controller: _phoneController,
            decoration: const InputDecoration(
              labelText: 'Номер телефона',
              hintText: '+79001234567',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              final phone = _phoneController.text.trim();
              if (phone.isNotEmpty) {
                context.read<AuthBloc>().add(AuthPhoneSubmitted(phone));
              }
            },
            child: const Text('Получить код'),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => setState(() => _isEmailAuth = true),
            child: const Text('Войти по почте'),
          ),
        ],
      ),
    );
  }

  Widget _buildOtpInput() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextField(
            controller: _otpController,
            decoration: const InputDecoration(
              labelText: 'Код из SMS',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              final code = _otpController.text.trim();
              if (code.isNotEmpty && _verificationId != null) {
                context.read<AuthBloc>().add(AuthOtpSubmitted(_verificationId!, code));
              }
            },
            child: const Text('Войти'),
          ),
          TextButton(
            onPressed: () => setState(() => _verificationId = null),
            child: const Text('Изменить номер'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmailInput() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_isRegister) ...[
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Имя',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: _emailController,
            decoration: const InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _passwordController,
            decoration: const InputDecoration(
              labelText: 'Пароль',
              border: OutlineInputBorder(),
            ),
            obscureText: true,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              final email = _emailController.text.trim();
              final password = _passwordController.text.trim();
              final name = _nameController.text.trim();
              
              // Валидация перед отправкой
              if (email.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Введите email'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              
              if (password.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Введите пароль'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              
              if (_isRegister && password.length < 6) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Пароль должен содержать минимум 6 символов'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              
              // Простая валидация формата email
              if (!email.contains('@') || !email.contains('.')) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Некорректный формат email'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              
              context.read<AuthBloc>().add(AuthEmailSubmitted(
                email: email, 
                password: password,
                isRegister: _isRegister,
                displayName: name,
              ));
            },
            child: Text(_isRegister ? 'Зарегистрироваться' : 'Войти'),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => setState(() => _isRegister = !_isRegister),
            child: Text(_isRegister ? 'Уже есть аккаунт? Войти' : 'Нет аккаунта? Регистрация'),
          ),
          TextButton(
            onPressed: () => setState(() => _isEmailAuth = false),
            child: const Text('Войти по номеру телефона'),
          ),
        ],
      ),
    );
  }
}
