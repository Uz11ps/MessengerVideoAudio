import 'package:messenger_app/core/api_service.dart';
import 'package:messenger_app/data/models/user_model.dart';

class AuthRepository {
  final ApiService _apiService;
  UserModel? _currentUser;

  AuthRepository({required ApiService apiService}) : _apiService = apiService;

  UserModel? get currentUser => _currentUser;

  Future<bool> sendOtp(String phoneNumber) async {
    final result = await _apiService.sendOtp(phoneNumber);
    return result['success'];
  }

  Future<UserModel?> verifyOtp(String phoneNumber, String code) async {
    final result = await _apiService.verifyOtp(phoneNumber, code);
    if (result['success']) {
      if (result['token'] != null) {
        _apiService.setToken(result['token']);
      }
      _currentUser = UserModel.fromMap(result['user']);
      return _currentUser;
    }
    return null;
  }

  Future<UserModel?> loginEmail(String email, String password) async {
    final result = await _apiService.loginEmail(email, password);
    if (result['success']) {
      if (result['token'] != null) {
        _apiService.setToken(result['token']);
      }
      _currentUser = UserModel.fromMap(result['user']);
      return _currentUser;
    }
    throw Exception(result['message'] ?? 'Ошибка входа');
  }

  Future<UserModel?> registerEmail(String email, String password, String displayName) async {
    final result = await _apiService.registerEmail(email, password, displayName);
    if (result['success']) {
      if (result['token'] != null) {
        _apiService.setToken(result['token']);
      }
      _currentUser = UserModel.fromMap(result['user']);
      return _currentUser;
    }
    throw Exception(result['message'] ?? 'Ошибка регистрации');
  }

  void signOut() {
    _currentUser = null;
    _apiService.setToken('');
  }
}
