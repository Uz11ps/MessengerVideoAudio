import 'package:messenger_app/core/api_service.dart';
import 'package:messenger_app/data/models/user_model.dart';

class AuthRepository {
  final ApiService _apiService;
  UserModel? _currentUser;

  AuthRepository({required ApiService apiService}) : _apiService = apiService;

  UserModel? get currentUser => _currentUser;

  Future<Map<String, dynamic>> sendOtp(String phoneNumber) async {
    final result = await _apiService.sendOtp(phoneNumber);
    return result;
  }

  Future<UserModel?> verifyOtp(String phoneNumber, String code) async {
    final result = await _apiService.verifyOtp(phoneNumber, code);
    if (result['success']) {
      if (result['token'] != null) {
        await _apiService.setToken(result['token']);
      }
      _currentUser = UserModel.fromMap(result['user']);
      await _apiService.saveUser(result['user']);
      return _currentUser;
    }
    // Бросаем исключение с конкретным сообщением об ошибке
    final errorMessage = result['message'] ?? 'Неверный код подтверждения';
    throw Exception(errorMessage);
  }

  Future<UserModel?> loginEmail(String email, String password) async {
    final result = await _apiService.loginEmail(email, password);
    if (result['success']) {
      if (result['token'] != null) {
        await _apiService.setToken(result['token']);
      }
      _currentUser = UserModel.fromMap(result['user']);
      await _apiService.saveUser(result['user']);
      return _currentUser;
    }
    // Передаем конкретное сообщение об ошибке от сервера
    final errorMessage = result['message'] ?? 'Ошибка входа';
    throw Exception(errorMessage);
  }

  Future<UserModel?> registerEmail(String email, String password, String displayName) async {
    final result = await _apiService.registerEmail(email, password, displayName);
    if (result['success']) {
      if (result['token'] != null) {
        await _apiService.setToken(result['token']);
      }
      _currentUser = UserModel.fromMap(result['user']);
      await _apiService.saveUser(result['user']);
      return _currentUser;
    }
    // Передаем конкретное сообщение об ошибке от сервера
    final errorMessage = result['message'] ?? 'Ошибка регистрации';
    throw Exception(errorMessage);
  }

  Future<void> signOut() async {
    _currentUser = null;
    await _apiService.clearAuth();
  }

  Future<UserModel?> loadSavedUser() async {
    final userData = await _apiService.getSavedUser();
    if (userData != null) {
      _currentUser = UserModel.fromMap(userData);
      return _currentUser;
    }
    return null;
  }
}
