import 'package:flutter/material.dart';
import 'sajdah_storage.dart';

class SajdahLocalization extends ChangeNotifier {
  static final SajdahLocalization _instance = SajdahLocalization._internal();
  factory SajdahLocalization() => _instance;
  SajdahLocalization._internal();

  String _currentLocale = 'ru';
  String get currentLocale => _currentLocale;

  void init(String systemLanguageCode) {
    if (!SajdahStorage().isFirstLaunch()) {
      _currentLocale = SajdahStorage().getLanguage() ?? 'en';
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
      'setting_dnd': 'Режим "Не беспокоить"',
      'replay_tutorial': 'Пройти обучение заново',
      'debug_brightness': 'Яркость: ',
      'debug_mismatch': 'Несовпадение: ',
      'onboarding_text_phoneOnFloor': 'Добро пожаловать! Положите телефон на пол перед ковриком (местом земного поклона) экраном вверх, примерно на уровне груди.\n\nУ вас есть время, пока на экране горит жёлтый текст, чтобы принять исходное положение. Если вы успели занять его и загорелся зелёный текст, то можете начинать молиться.',
      'onboarding_text_cameraDetection': 'Фронтальная камера будет автоматически фиксировать каждый поклон (суджуд), когда вы приближаетесь к экрану.',
      'onboarding_text_toDarkInRoom': 'Если в комнате слишком темно, автоподсчёт может работать некорректно (приложение предупредит вас). В этом случае используйте кнопку «+1» внизу экрана.',
      'onboarding_text_warning': 'Внимание! Данное приложение создано для помощи в молитве и не гарантирует безошибочный учёт поклонов. Нажимая «Далее», вы соглашаетесь с тем, что самостоятельно несёте всю ответственность за правильность выполнения молитвы и возможные пропущенные суджуды.',
      'onboarding_text_theEnd': 'Вы всегда можете заново пройти это обучение или изменить другие параметры в настройках приложения. Приятного использования!',
      'next_button': 'Далее',
      'start_button': 'Начать',
      'seconds_short': 'сек',
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
      'setting_dnd': 'Do Not Disturb Mode',
      'replay_tutorial': 'Restart Tutorial',
      'debug_brightness': 'Brightness: ',
      'debug_mismatch': 'Mismatch: ',
      'onboarding_text_phoneOnFloor': 'Welcome! Place your phone on the floor in front of the prayer mat (the place of prostration) screen up, approximately at chest level.\n\nWhile the yellow text is displayed on the screen, you have time to take your starting position. If you have successfully taken it and the text turns green, you can begin your prayer.',
      'onboarding_text_cameraDetection': 'The front camera will automatically detect each prostration (sajdah) as you move closer to the screen.',
      'onboarding_text_toDarkInRoom': 'If the room is too dark, the auto-count might work incorrectly (the app will notify you). In this case, use the manual "+1" button.',
      'onboarding_text_warning': 'Attention! This application is created to assist with prayer and does not guarantee error-free prostration counting. By tapping "Next", you agree that you solely bear full responsibility for the correctness of your prayer and any potentially missed sajdahs.',
      'onboarding_text_theEnd': 'You can restart this tutorial at any time or change other preferences in the application settings. Have a blessed prayer!',
      'next_button': 'Next',
      'start_button': 'Start',
      'seconds_short': 'sec',
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
      'setting_dnd': 'وضع عدم الإزعاج',
      'replay_tutorial': 'إعادة الدليل التعليمий',
      'debug_brightness': 'السطوع: ',
      'debug_mismatch': 'عدم التطابق: ',
      'onboarding_text_phoneOnFloor': 'مرحباً بك! ضع الهاتف على الأرض أمام سجادة الصلاة (موضع السجود) والشاشة متجهة لأعلى، على مستوى الصدر تقريباً.\n\nلديك الوقت لاتخاذ الوضعية البدئية طالما أن النص الأصفر يضيء على الشاشة. إذا تمكنت من اتخاذها وتحول النص إلى اللون الأخضر، فيمكنك البدء في الصلاة.',
      'onboarding_text_cameraDetection': 'ستقوم الكاميرا الأمامية بتلقائية باحتساب كل سجدة عند اقترابك من الشاشة.',
      'onboarding_text_toDarkInRoom': 'إذا كانت الإضاءة خافتة جداً، قد لا يعمل الحساب التلقائي بشكل صحيح (سيقوم التطبيق بتنبيهك). في هذه الحالة، استخدم زر "+1" اليدوي.',
      'onboarding_text_warning': 'تنبيه! تم تصميم هذا التطبيق للمساعدة في الصلاة ولا يضمن احتساباً خالياً من الأخطاء للسجدات. بالضغط على «التالي»، فإنك توافق на تحمل المسؤولية الكاملة عن صحة صلاتك وعن أي سجدات فائتة محتملة.',
      'onboarding_text_theEnd': 'يمكنك دائماً إعادة تشغيل هذا التعليمي أو تغيير الإعدادات الأخرى من قائمة الإعدادات. نرجو لك صلاة مقبولة!',
      'next_button': 'التالي',
      'start_button': 'ابدأ',
      'seconds_short': 'ثانية',
    },
  };

  String translate(String key) {
    return _localizedValues[_currentLocale]?[key] ?? _localizedValues['en']?[key] ?? key;
  }
}