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

  // --- РЕЖИМ ОТЛАДКИ (По умолчанию: true) ---
  bool getDebugMode() => _prefs.getBool('debug_mode') ?? true;
  Future<void> saveDebugMode(bool value) async => await _prefs.setBool('debug_mode', value);

  // --- ВИБРАЦИЯ (По умолчанию: true) ---
  bool getVibrationEnabled() => _prefs.getBool('vibration_enabled') ?? true;
  Future<void> saveVibrationEnabled(bool value) async => await _prefs.setBool('vibration_enabled', value);

  // --- РЕЖИМ "НЕ БЕСПОКОИТЬ" (По умолчанию: true) ---
  bool getDndEnabled() => _prefs.getBool('dnd_enabled') ?? true;
  Future<void> saveDndEnabled(bool value) async => await _prefs.setBool('dnd_enabled', value);

  // --- ПЕРВЫЙ ЗАПУСК / ИНСТРУКЦИЯ ---
  bool isFirstLaunch() => _prefs.getBool('is_first_launch') ?? true;
  Future<void> setFirstLaunchCompleted() async => await _prefs.setBool('is_first_launch', false);

  // --- ИСПОЛЬЗОВАНИЕ КАМЕРЫ (По умолчанию: true) ---
  bool getCameraEnabled() => _prefs.getBool('camera_enabled') ?? true;
  Future<void> saveCameraEnabled(bool value) async => await _prefs.setBool('camera_enabled', value);
}