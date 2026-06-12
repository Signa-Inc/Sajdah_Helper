import 'package:shared_preferences/shared_preferences.dart';

class SajdahStorage {
  static final SajdahStorage _instance = SajdahStorage._internal();
  factory SajdahStorage() => _instance;
  SajdahStorage._internal();

  late SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // --- ЯЗЫК ---
  String? getLanguage() => _prefs.getString('language_code');
  Future<void> saveLanguage(String langCode) async => await _prefs.setString('language_code', langCode);

  // --- РЕЖИМ ОТЛАДКИ (По умолчанию: false) ---
  bool getDebugMode() => _prefs.getBool('debug_mode') ?? false;
  Future<void> saveDebugMode(bool value) async => await _prefs.setBool('debug_mode', value);

  // --- ВИБРАЦИЯ (По умолчанию: true) ---
  bool getVibrationEnabled() => _prefs.getBool('vibration_enabled') ?? true;
  Future<void> saveVibrationEnabled(bool value) async => await _prefs.setBool('vibration_enabled', value);
}