import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const String baseUrl = 'http://83.166.246.225:3000';
  static const String _tokenKey = 'auth_token';
  static const String _userKey = 'auth_user';
  String? _token;

  String? get token => _token;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_tokenKey);
  }

  Future<void> setToken(String token) async {
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    if (token.isNotEmpty) {
      await prefs.setString(_tokenKey, token);
    } else {
      await prefs.remove(_tokenKey);
      await prefs.remove(_userKey);
    }
  }

  Future<Map<String, dynamic>?> getSavedUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString(_userKey);
    if (userJson != null) {
      return jsonDecode(userJson);
    }
    return null;
  }

  Future<void> saveUser(Map<String, dynamic> user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, jsonEncode(user));
  }

  Future<void> clearAuth() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
    _token = null;
  }

  Future<Map<String, dynamic>> sendOtp(String phoneNumber) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/send-otp'),
        body: jsonEncode({'phoneNumber': phoneNumber}),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));
      
      final data = jsonDecode(response.body);
      
      // Если статус не 200, возвращаем ошибку с сообщением от сервера
      if (response.statusCode != 200) {
        return {
          'success': false,
          'message': data['error'] ?? data['message'] ?? 'Ошибка отправки SMS. Попробуйте еще раз.'
        };
      }
      
      return data;
    } catch (e) {
      return {'success': false, 'message': 'Ошибка подключения к серверу. Проверьте интернет.'};
    }
  }

  Future<Map<String, dynamic>> verifyOtp(String phoneNumber, String code, {String? displayName}) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/verify-otp'),
        body: jsonEncode({
          'phoneNumber': phoneNumber, 
          'code': code,
          'displayName': displayName
        }),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));
      
      final data = jsonDecode(response.body);
      
      // Если статус не 200, возвращаем ошибку с сообщением от сервера
      if (response.statusCode != 200) {
        return {
          'success': false,
          'message': data['message'] ?? 'Неверный код подтверждения. Попробуйте еще раз.'
        };
      }
      
      if (data['success'] == true && data['token'] != null) {
        await setToken(data['token']);
        if (data['user'] != null) {
          await saveUser(data['user']);
        }
      }
      return data;
    } catch (e) {
      return {'success': false, 'message': 'Ошибка подключения к серверу. Проверьте интернет.'};
    }
  }

  Future<Map<String, dynamic>> loginEmail(String email, String password) async {
    try {
      // Нормализуем email: убираем пробелы и приводим к нижнему регистру
      final normalizedEmail = email.trim().toLowerCase();
      
      if (normalizedEmail.isEmpty || password.isEmpty) {
        return {
          'success': false,
          'message': 'Email и пароль обязательны для заполнения'
        };
      }
      
      // Простая валидация формата email
      if (!normalizedEmail.contains('@') || !normalizedEmail.contains('.')) {
        return {
          'success': false,
          'message': 'Некорректный формат email. Проверьте правильность ввода.'
        };
      }
      
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/email-login'),
        body: jsonEncode({'email': normalizedEmail, 'password': password}),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));
      
      final data = jsonDecode(response.body);
      
      // Если статус не 200, возвращаем ошибку с сообщением от сервера
      if (response.statusCode != 200) {
        return {
          'success': false,
          'message': data['message'] ?? 'Ошибка входа. Проверьте email и пароль.'
        };
      }
      
      if (data['success'] == true && data['token'] != null) {
        await setToken(data['token']);
        if (data['user'] != null) {
          await saveUser(data['user']);
        }
      } else {
        // Если success != true, но статус 200, все равно возвращаем ошибку
        return {
          'success': false,
          'message': data['message'] ?? 'Ошибка входа. Проверьте email и пароль.'
        };
      }
      return data;
    } catch (e) {
      return {'success': false, 'message': 'Ошибка подключения к серверу. Проверьте интернет соединение.'};
    }
  }

  Future<Map<String, dynamic>> registerEmail(String email, String password, String displayName) async {
    try {
      // Нормализуем email: убираем пробелы и приводим к нижнему регистру
      final normalizedEmail = email.trim().toLowerCase();
      
      if (normalizedEmail.isEmpty || password.isEmpty) {
        return {
          'success': false,
          'message': 'Email и пароль обязательны для заполнения'
        };
      }
      
      // Простая валидация формата email
      if (!normalizedEmail.contains('@') || !normalizedEmail.contains('.')) {
        return {
          'success': false,
          'message': 'Некорректный формат email. Проверьте правильность ввода.'
        };
      }
      
      // Валидация пароля
      if (password.length < 6) {
        return {
          'success': false,
          'message': 'Пароль должен содержать минимум 6 символов'
        };
      }
      
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/email-register'),
        body: jsonEncode({
          'email': normalizedEmail, 
          'password': password, 
          'displayName': displayName.trim()
        }),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));
      
      final data = jsonDecode(response.body);
      
      // Если статус не 200, возвращаем ошибку с сообщением от сервера
      if (response.statusCode != 200) {
        return {
          'success': false,
          'message': data['message'] ?? data['error'] ?? 'Ошибка регистрации. Попробуйте еще раз.'
        };
      }
      
      // Проверяем успешность операции
      if (data['success'] == true && data['token'] != null) {
        await setToken(data['token']);
        if (data['user'] != null) {
          await saveUser(data['user']);
        }
        return data;
      } else {
        // Если success != true, но статус 200, все равно возвращаем ошибку
        return {
          'success': false,
          'message': data['message'] ?? data['error'] ?? 'Ошибка регистрации. Попробуйте еще раз.'
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Ошибка подключения к серверу. Проверьте интернет соединение.'};
    }
  }

  Future<List<dynamic>> searchUsers(String query) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/users/search?query=$query'),
      headers: {'Authorization': 'Bearer $_token'},
    );
    return jsonDecode(response.body);
  }

  Future<Map<String, dynamic>> createChat(List<String> participants) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/chats/create'),
      body: jsonEncode({'participants': participants}),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token'
      },
    );
    return jsonDecode(response.body);
  }

  Future<Map<String, dynamic>> createGroupChat(List<String> participants, String groupName, String adminId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/chats/group'),
      body: jsonEncode({
        'participants': participants,
        'groupName': groupName,
        'adminId': adminId,
      }),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token'
      },
    );
    return jsonDecode(response.body);
  }

  Future<Map<String, dynamic>> updateProfile({
    required String id,
    String? displayName,
    String? status,
    String? photoUrl,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/users/update'),
      body: jsonEncode({
        'id': id,
        'displayName': displayName,
        'status': status,
        'photoUrl': photoUrl,
      }),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token'
      },
    );
    return jsonDecode(response.body);
  }

  Future<Map<String, dynamic>> linkEmail(String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/users/link-email'),
        body: jsonEncode({
          'email': email,
          'password': password,
        }),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token'
        },
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'message': 'Ошибка подключения: ${e.toString()}'};
    }
  }

  Future<Map<String, dynamic>> linkPhone(String phoneNumber, String code) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/users/link-phone'),
        body: jsonEncode({
          'phoneNumber': phoneNumber,
          'code': code,
        }),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token'
        },
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'message': 'Ошибка подключения: ${e.toString()}'};
    }
  }

  Future<String?> uploadFile(File file) async {
    var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/api/upload'));
    request.files.add(await http.MultipartFile.fromPath('file', file.path));
    var response = await request.send();
    if (response.statusCode == 200) {
      final resBody = await response.stream.bytesToString();
      return jsonDecode(resBody)['url'];
    }
    return null;
  }

  Future<bool> addParticipantToGroup(String chatId, String userId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/chats/$chatId/add-participant'),
        body: jsonEncode({'userId': userId}),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token'
        },
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<bool> removeParticipantFromGroup(String chatId, String userId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/chats/$chatId/remove-participant'),
        body: jsonEncode({'userId': userId}),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token'
        },
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<bool> deleteGroup(String chatId) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/api/chats/$chatId'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<Map<String, dynamic>> deleteMessage(String chatId, String messageId) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/api/chats/$chatId/messages/$messageId'),
        headers: {
          'Authorization': 'Bearer $_token',
          'Content-Type': 'application/json',
        },
      );
      
      if (response.statusCode == 200) {
        // Проверяем, что ответ действительно JSON
        final contentType = response.headers['content-type'] ?? '';
        if (contentType.contains('application/json')) {
          try {
            final body = jsonDecode(response.body);
            return {'success': true, ...body};
          } catch (e) {
            return {'success': true};
          }
        }
        return {'success': true};
      } else {
        // Проверяем, что ответ JSON перед парсингом
        final contentType = response.headers['content-type'] ?? '';
        if (contentType.contains('application/json')) {
          try {
            final body = jsonDecode(response.body);
            return {
              'success': false,
              'error': body['error'] ?? body['message'] ?? 'Ошибка при удалении сообщения'
            };
          } catch (e) {
            return {
              'success': false,
              'error': 'Ошибка сервера (${response.statusCode})'
            };
          }
        } else {
          // Сервер вернул HTML или другой формат
          return {
            'success': false,
            'error': 'Сервер вернул неверный формат ответа (${response.statusCode}). Попробуйте позже.'
          };
        }
      }
    } catch (e) {
      return {
        'success': false,
        'error': 'Ошибка сети: ${e.toString()}'
      };
    }
  }
}
