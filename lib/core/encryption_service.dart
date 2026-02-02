import 'package:encrypt/encrypt.dart';

class EncryptionService {
  // ВНИМАНИЕ: В реальном приложении ключ должен быть уникальным для каждого чата.
  // Сейчас мы используем фиксированный ключ для тестирования.
  static final _key = Key.fromUtf8('my_32_char_very_secret_key_12345');
  
  // Используем фиксированный IV (Initialization Vector) для того, чтобы 
  // зашифрованное сообщение можно было расшифровать на другом устройстве.
  // В идеале IV должен передаваться вместе с сообщением.
  static final _iv = IV.fromUtf8('fixed_16_char_iv'); 
  
  static final _encrypter = Encrypter(AES(_key, mode: AESMode.cbc));

  static String encrypt(String text) {
    try {
      return _encrypter.encrypt(text, iv: _iv).base64;
    } catch (e) {
      return text;
    }
  }

  static String decrypt(String encryptedBase64) {
    if (encryptedBase64.isEmpty) return '';
    try {
      return _encrypter.decrypt(Encrypted.fromBase64(encryptedBase64), iv: _iv);
    } catch (e) {
      // Если это не зашифрованная строка или ошибка ключа, возвращаем как есть
      return encryptedBase64;
    }
  }
}
