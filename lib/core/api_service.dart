import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class ApiService {
  static const String baseUrl = 'http://83.166.246.225:3000';
  String? _token;

  String? get token => _token;

  void setToken(String token) => _token = token;

  Future<Map<String, dynamic>> sendOtp(String phoneNumber) async {
    try {
      print('ApiService: Sending OTP to $phoneNumber...');
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/send-otp'),
        body: jsonEncode({'phoneNumber': phoneNumber}),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));
      print('ApiService: Response status: ${response.statusCode}');
      print('ApiService: Response body: ${response.body}');
      return jsonDecode(response.body);
    } catch (e) {
      print('ApiService: Error sending OTP: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> verifyOtp(String phoneNumber, String code, {String? displayName}) async {
    try {
      print('ApiService: Verifying OTP for $phoneNumber...');
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
      if (data['success'] == true) {
        _token = data['token'];
      }
      return data;
    } catch (e) {
      print('ApiService: Error verifying OTP: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> loginEmail(String email, String password) async {
    try {
      print('ApiService: Logging in with $email...');
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/email-login'),
        body: jsonEncode({'email': email, 'password': password}),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));
      final data = jsonDecode(response.body);
      print('ApiService: Login response: $data');
      if (data['success'] == true && data['token'] != null) {
        _token = data['token'];
        print('ApiService: Token saved to _token: $_token');
      }
      return data;
    } catch (e) {
      print('ApiService: Login error: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> registerEmail(String email, String password, String displayName) async {
    try {
      print('ApiService: Registering with $email...');
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/email-register'),
        body: jsonEncode({
          'email': email, 
          'password': password, 
          'displayName': displayName
        }),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));
      final data = jsonDecode(response.body);
      print('ApiService: Register response: $data');
      if (data['success'] == true && data['token'] != null) {
        _token = data['token'];
        print('ApiService: Token saved to _token: $_token');
      }
      return data;
    } catch (e) {
      print('ApiService: Register error: $e');
      return {'success': false, 'message': e.toString()};
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
}
