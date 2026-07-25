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
      'all_good': 'Всё в порядке, можете начинать молиться',
      'no_front_camera': 'Фронтальная камера не найдена, используйте кнопку "+1"',
      'setting_up_camera': 'Подождите, идёт настройка камеры...',
      'settings_title': 'НАСТРОЙКИ',
      'setting_debug': 'Режим отладки',
      'setting_debug_desc': 'Отображает отладочную информацию о яркости и проценте изменения кадра с камеры для проверки работы алгоритма',
      'setting_vibration': 'Вибрация при суджуде',
      'setting_vibration_desc': 'Устройство кратко вибрирует при каждом успешно зафиксированном земном поклоне',
      'setting_dnd': 'Режим "Не беспокоить"',
      'setting_dnd_desc': 'Автоматически отключает звук уведомлений и звонков во время совершения молитвы, чтобы вас ничего не отвлекало',
      'setting_camera': 'Автоматический подсчёт',
      'setting_camera_desc': 'Использует фронтальную камеру для автофиксации поклонов. При отключении подсчёт осуществляется только вручную кнопкой «+1»',
      'replay_tutorial': 'Пройти обучение заново',
      'debug_brightness': 'Яркость: ',
      'debug_mismatch': 'Несовпадение: ',
      'onboarding_text_phoneOnFloor': 'Добро пожаловать! Положите телефон на пол перед ковриком (местом земного поклона) экраном вверх, примерно на уровне груди.\n\nУ вас есть время, пока на экране горит жёлтый текст, чтобы принять исходное положение. Если вы успели занять его и загорелся зелёный текст, то можете начинать молиться.',
      'onboarding_text_cameraDetection': 'Фронтальная камера будет автоматически фиксировать каждый земной поклон (суджуд), когда вы приближаетесь к экрану.',
      'onboarding_text_toDarkInRoom': 'Если в комнате слишком темно, автоподсчёт может работать некорректно (приложение предупредит вас об этом). В этом случае используйте кнопку «+1» внизу экрана.',
      'onboarding_text_toDarkInRoom_ios_pwa': 'Добро пожаловать!\n\nДля подсчёта ракаатов используйте кнопку «+1» внизу экрана.\n\nАвтоматический подсчёт пока недоступен для вашего типа устройства, но мы уже работаем над этим.',
      'onboarding_text_warning': 'Внимание!\n\nЕсли вы заметили, что в строке «Несовпадение» значение превышает 10, когда вы находитесь в выпрямленном положении, это означает, что произошёл сбой алгоритма. В таком случае следует нажать кнопку «Перезапустить» - она находится под счётчиком ракаатов.\n\nДанное приложение создано для помощи в молитве и не гарантирует абсолютно безошибочный учёт поклонов. Нажимая «Далее», вы соглашаетесь с тем, что самостоятельно несёте полную ответственность за правильность выполнения молитвы и возможные пропущенные суджуды.',
      'onboarding_text_theEnd': 'Вы всегда можете заново пройти это обучение или изменить другие параметры в настройках приложения.\n\nПриятного использования!',
      'next_button': 'Далее',
      'start_button': 'Начать',
      'seconds_short': 'сек',
    },
    'en': {
      'rakats': 'RAKAATS',
      'too_dark': 'Too dark. Use the "+1" button',
      'all_good': 'Everything is ready, you can start praying',
      'no_front_camera': 'Front camera not found, use the "+1" button',
      'setting_up_camera': 'Please wait, setting up the camera...',
      'settings_title': 'SETTINGS',
      'setting_debug': 'Debug mode',
      'setting_debug_desc': 'Displays debug info about brightness and frame change percentage to check algorithm performance',
      'setting_vibration': 'Vibration on Sujud',
      'setting_vibration_desc': 'The device vibrates briefly for every successfully detected prostration',
      'setting_dnd': 'Do Not Disturb mode',
      'setting_dnd_desc': 'Automatically mutes notification sounds and calls during prayer so nothing distracts you',
      'setting_camera': 'Auto-counting',
      'setting_camera_desc': 'Uses the front camera to automatically detect prostrations. When disabled, counting is done manually using the "+1" button',
      'replay_tutorial': 'Replay tutorial',
      'debug_brightness': 'Brightness: ',
      'debug_mismatch': 'Mismatch: ',
      'onboarding_text_phoneOnFloor': 'Welcome! Place your phone on the floor in front of your prayer mat (the place of prostration) screen facing up, roughly at chest level.\n\nYou have time to take your starting position while the yellow text is on the screen. Once you are in position and the text turns green, you can start praying.',
      'onboarding_text_cameraDetection': 'The front camera will automatically detect each prostration (sujud) as you move closer to the screen.',
      'onboarding_text_toDarkInRoom': 'If the room is too dark, auto-counting may not work correctly (the app will warn you). In this case, use the "+1" button at the bottom of the screen.',
      'onboarding_text_toDarkInRoom_ios_pwa': 'Welcome!\n\nTo count rakaats, use the "+1" button at the bottom of the screen.\n\nAuto-counting is not yet available for your device type, but we are working on it.',
      'onboarding_text_warning': 'Warning!\n\nIf you notice the "Mismatch" value exceeds 10 while you are standing upright, the algorithm has encountered an error. In this case, press "Restart" — it is located under the rakaat counter.\n\nThis app is created to assist in prayer and does not guarantee completely error-free counting. By tapping "Next", you agree that you carry full personal responsibility for the correctness of your prayer and any missed sujuds.',
      'onboarding_text_theEnd': 'You can always replay this tutorial or adjust parameters in the app settings.\n\nEnjoy using the app!',
      'next_button': 'Next',
      'start_button': 'Start',
      'seconds_short': 'sec',
    },
    'ar': {
      'rakats': 'الركعات',
      'too_dark': 'المكان مظلم جداً. استخدم الزر "+1"',
      'all_good': 'كل شيء جاهز، يمكنك البدء في الصلاة',
      'no_front_camera': 'لم يتم العثور على الكاميرا الأمامية، استخدم الزر "+1"',
      'setting_up_camera': 'يرجى الانتظار، جاري إعداد الكاميرا...',
      'settings_title': 'الإعدادات',
      'setting_debug': 'وضع التصحيح',
      'setting_debug_desc': 'يعرض معلومات التصحيح الخاصة بالسطوع ونسبة تغير إطار الكاميرا للتحقق من عمل الخوارزمية',
      'setting_vibration': 'الاهتزاز عند السجود',
      'setting_vibration_desc': 'يهتز الجهاز لفترة قصيرة مع كل سجدة يتم تسجيلها بنجاح',
      'setting_dnd': 'وضع "عدم الإزعاج"',
      'setting_dnd_desc': 'يقوم بكتم صوت الإشعارات والمكالمات تلقائياً أثناء الصلاة لمنع أي إزعاج',
      'setting_camera': 'العد التلقائي',
      'setting_camera_desc': 'يستخدم الكاميرا الأمامية لتسجيل السجدات تلقائياً. عند إيقاف تشغيله، يتم العد يدوياً فقط باستخدام الزر "+1"',
      'replay_tutorial': 'إعادة الشرح',
      'debug_brightness': 'السطوع: ',
      'debug_mismatch': 'عدم التطابق: ',
      'onboarding_text_phoneOnFloor': 'مرحباً بك! ضع الهاتف على الأرض أمام سجادة الصلاة (موضع السجود) والشاشة للأعلى، على مستوى الصدر تقريباً.\n\nلديك وقت لاتخاذ الوضعية الأساسية أثناء ظهور النص باللون الأصفر على الشاشة. وبمجرد اتخاذك للوضعية وظهور النص باللون الأخضر، يمكنك البدء في الصلاة.',
      'onboarding_text_cameraDetection': 'ستقوم الكاميرا الأمامية بتسجيل كل سجدة (سجود) تلقائياً عندما تقترب من الشاشة.',
      'onboarding_text_toDarkInRoom': 'إذا كانت الغرفة مظلمة جداً، فقد لا يعمل العد التلقائي بشكل صحيح (سينبهك التطبيق بذلك). في هذه الحالة، استخدم الزر "+1" أسفل الشاشة.',
      'onboarding_text_toDarkInRoom_ios_pwa': 'مرحباً بك!\n\nلحساب الركعات، استخدم الزر "+1" أسفل الشاشة.\n\nالعد التلقائي غير متاح بعد لنوع جهازك، ولكننا نعمل على ذلك حالياً.',
      'onboarding_text_warning': 'تنبيه!\n\nإذا لاحظت أن قيمة "عدم التطابق" تتجاوز 10 أثناء وقوفك في وضع الاعتدال، فهذا يعني حدوث خطأ في الخوارزمية. في هذه الحالة، اضغط على زر "إعادة التشغيل" — الموجود أسفل عداد الركعات.\n\nتم تصميم هذا التطبيق للمساعدة في الصلاة ولا يضمن دقة خالية من الأخطاء بنسبة 100%. بالضغط على "التالي"، فإنك توافق على أنك تتحمل المسؤولية الكاملة عن صحة صلاتك وعن أي سجدات قد تُنسى.',
      'onboarding_text_theEnd': 'يمكنك دائماً إعادة الشرح أو تعديل الإعدادات من قائمة إعدادات التطبيق.\n\nاستخداماً ممتعاً!',
      'next_button': 'التالي',
      'start_button': 'ابدأ',
      'seconds_short': 'ثانية',
    },
  };

  String translate(String key) {
    return _localizedValues[_currentLocale]?[key] ?? _localizedValues['en']?[key] ?? key;
  }
}