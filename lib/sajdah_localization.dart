import 'package:flutter/material.dart';
import 'sajdah_storage.dart';

class SajdahLocalization extends ChangeNotifier {
  static final SajdahLocalization _instance = SajdahLocalization._internal();
  factory SajdahLocalization() => _instance;
  SajdahLocalization._internal();

  String _currentLocale = 'ru';
  String get currentLocale => _currentLocale;

  void init(String systemLanguageCode) {
    String? savedLang = SajdahStorage().getLanguage();
    if (savedLang != null) {
      _currentLocale = savedLang;
    } else {
      if (_localizedValues.containsKey(systemLanguageCode)) {
        _currentLocale = systemLanguageCode;
      } else {
        _currentLocale = 'en';
      }
      SajdahStorage().saveLanguage(_currentLocale);
    }
  }

  Future<void> setLanguage(String languageCode) async {
    if (_localizedValues.containsKey(languageCode) && _currentLocale != languageCode) {
      _currentLocale = languageCode;
      await SajdahStorage().saveLanguage(languageCode);
      notifyListeners();
    }
  }

  static const Map<String, Map<String, String>> _localizedValues = {
    'ru': {
      'rakats': 'РАКААТЫ',
      'too_dark': 'Слишком темно. Используйте кнопку "+1"',
      'all_good': 'Всё нормально, можете молиться',
      'no_front_camera': 'Фронтальная камера не найдена, используйте кнопку "+1"',
      'setting_up_camera': 'Подождите, настраиваем камеру',
      'settings_title': 'НАСТРОЙКИ',
      'setting_debug': 'Режим отладки',
      'setting_vibration': 'Вибрация при суджуде',
    },
    'en': {
      'rakats': 'RAKATS',
      'too_dark': 'Too dark. Use the "+1" button',
      'all_good': 'Everything is fine, you can pray',
      'no_front_camera': 'Front camera not found, use the "+1" button',
      'setting_up_camera': 'Just a moment, setting up the camera',
      'settings_title': 'SETTINGS',
      'setting_debug': 'Debug Mode',
      'setting_vibration': 'Vibration on Sajdah',
    },
    'ar': {
      'rakats': 'الركعات',
      'too_dark': 'مظلم جداً. استخدم زر "+1"',
      'all_good': 'كل شيء جيد، يمكنك الصلاة',
      'no_front_camera': 'الكاميرا الأمامية غير موجودة، استخدم زر "+1"',
      'setting_up_camera': 'انتظر، يتم إعداد الكاميرا',
      'settings_title': 'الإعدادات',
      'setting_debug': 'وضع التصحيح',
      'setting_vibration': 'الاهتزاز عند السجود',
    },
  };

  String translate(String key) {
    return _localizedValues[_currentLocale]?[key] ?? _localizedValues['en']?[key] ?? key;
  }
}