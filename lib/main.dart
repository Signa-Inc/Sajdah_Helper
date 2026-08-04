import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:vibration/vibration.dart';
import 'dart:async';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter/services.dart';
import 'sajdah_localization.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'sajdah_storage.dart';
import 'package:video_player/video_player.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart';
import 'pwa_helper.dart';
import 'package:universal_html/html.dart' as html;
import 'sajdah_face_helper.dart';

class AnalysisResult {
  final double computedPercentage;
  final double avgBrightness;

  AnalysisResult({required this.computedPercentage, required this.avgBrightness});
}

abstract class SajdahFrameAnalyzer {
  Uint8List? baselineFrame;

  void resetBaseline() {
    baselineFrame = null;
  }

  AnalysisResult analyze({
    required Uint8List currentBytes,
    required int width,
    required int height,
    required int bytesPerRow,
    required int sensorOrientation,
    required bool isDebugMode,
  });
}

class AndroidFrameAnalyzer extends SajdahFrameAnalyzer {
  @override
  AnalysisResult analyze({
    required Uint8List currentBytes,
    required int width,
    required int height,
    required int bytesPerRow,
    required int sensorOrientation,
    required bool isDebugMode,
  }) {
    double avgBrightness = 0;

    double totalBrightness = 0;
    int checkStep = 50;
    int count = 0;
    for (int i = 0; i < currentBytes.length; i += checkStep) {
      totalBrightness += currentBytes[i];
      count++;
    }
    avgBrightness = count > 0 ? totalBrightness / count : 0;

    if (baselineFrame == null) {
      baselineFrame = Uint8List.fromList(currentBytes);
      return AnalysisResult(computedPercentage: 0.0, avgBrightness: avgBrightness);
    }

    int changedPixels = 0;
    int totalChecked = 0;

    int startX = 0;
    int endX = width;
    int startY = 0;
    int endY = height;

    if (sensorOrientation == 270) {
      startX = width >> 1;
      endX = width;
    } else if (sensorOrientation == 90) {
      startX = 0;
      endX = width >> 1;
    } else {
      startY = 0;
      endY = height >> 1;
    }

    for (int y = startY; y < endY; y += SajdahConfig.pixelStep) {
      int rowOffset = y * bytesPerRow;
      for (int x = startX; x < endX; x += SajdahConfig.pixelStep) {
        int index = rowOffset + x;
        if (index < currentBytes.length && index < baselineFrame!.length) {
          totalChecked++;
          final int diff = (currentBytes[index] - baselineFrame![index]).abs();
          changedPixels += (diff > SajdahConfig.sensitivityThreshold) ? 1 : 0;
        }
      }
    }

    final double computedPercentage = totalChecked > 0 ? (changedPixels / totalChecked) : 0;
    return AnalysisResult(computedPercentage: computedPercentage, avgBrightness: avgBrightness);
  }
}

class IosWebFrameAnalyzer extends SajdahFrameAnalyzer {
  @override
  AnalysisResult analyze({
    required Uint8List currentBytes,
    required int width,
    required int height,
    required int bytesPerRow,
    required int sensorOrientation,
    required bool isDebugMode,
  }) {
    // Не используется: iOS Web ветка вызывает analyzeFaceScore() напрямую (async),
    // этот метод оставлен для совместимости с абстрактным классом.
    return AnalysisResult(computedPercentage: 0.0, avgBrightness: 0.0);
  }

  /// score > 0.4 обычно значит лицо распознано; -1 значит лицо не найдено
  AnalysisResult fromFaceScore(double score) {
    // Лицо не найдено => считаем что произошло "закрытие камеры" => высокий процент = суджуд
    final double computedPercentage = score < 0 ? 1.0 : 0.0;
    return AnalysisResult(computedPercentage: computedPercentage, avgBrightness: 128.0);
  }
}

// ============================================================================
// КОНФИГУРАЦИЯ И НАСТРОЙКИ ПРИЛОЖЕНИЯ
// ============================================================================

class SajdahConfig {
  static const int pixelStep = 15;
  static const int sensitivityThreshold = 35;
  static const double detectionThreshold = 0.85;
  static const double resetThreshold = 0.25;
  static const int framesToConfirm = 3;
  static const int cooldownVibrationSeconds = 2;
  static const double minBrightnessThreshold = 100.0;
  static const int frameThrottleMs = 50;
  static const int stableFramesToUpdateBaseline = 8;

  static bool isWeb() => kIsWeb;
  static bool isiOSWeb() => kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  static bool isAndroidWeb() => kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static bool isPC() => defaultTargetPlatform != TargetPlatform.iOS && defaultTargetPlatform != TargetPlatform.android;

  static bool isPwa() {
    if (!kIsWeb) return false;
    return isPwaStandalone();
  }

  static bool shouldShowStub() => isAndroidWeb() || isPC();
}

late List<CameraDescription> _cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!SajdahConfig.isWeb()) {
    try {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    } catch (e) {
      debugPrint("Ошибка SystemChrome (нативная платформа): $e");
    }
  }

  await SajdahStorage().init();

  final String systemLang = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
  SajdahLocalization().init(systemLang);

  runApp(const SajdahApp());
}

class SajdahApp extends StatefulWidget {
  const SajdahApp({super.key});

  static void restartApp(BuildContext context) {
    context.findAncestorStateOfType<_SajdahAppState>()?.restart();
  }

  static void showTutorial(BuildContext context) {
    context.findAncestorStateOfType<_SajdahAppState>()?.openTutorialDynamically();
  }

  @override
  State<SajdahApp> createState() => _SajdahAppState();
}

class _SajdahAppState extends State<SajdahApp> {
  Key _key = UniqueKey();
  bool _showOnboarding = SajdahStorage().isFirstLaunch();

  @override
  void initState() {
    super.initState();
    try {
      WakelockPlus.enable();
    } catch (e) {
      debugPrint("Wakelock enable error: $e");
    }
  }

  @override
  void dispose() {
    try {
      WakelockPlus.disable();
    } catch (e) {
      debugPrint("Wakelock disable error: $e");
    }
    super.dispose();
  }

  void restart() {
    setState(() {
      _key = UniqueKey();
      _showOnboarding = SajdahStorage().isFirstLaunch();
    });
  }

  void openTutorialDynamically() {
    setState(() {
      _showOnboarding = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: SajdahLocalization(),
      builder: (context, _) {
        final currentLang = SajdahLocalization().currentLocale;

        Widget homeScreen;
        if (SajdahConfig.shouldShowStub()) {
          homeScreen = const SajdahWebStubScreen();
        }
        else if (SajdahConfig.isiOSWeb() && !SajdahConfig.isPwa()) {
          homeScreen = const SajdahIosWebPromptScreen();
        }
        else if (_showOnboarding) {
          homeScreen = SajdahOnboardingScreen(
            onCompleted: () {
              setState(() {
                _showOnboarding = false;
              });
            },
          );
        } else {
          homeScreen = const SajdahScreen();
        }

        return KeyedSubtree(
          key: _key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData.dark().copyWith(
              scaffoldBackgroundColor: Colors.black,
            ),
            locale: Locale(currentLang),
            supportedLocales: const [Locale('ru'), Locale('en'), Locale('ar')],
            localizationsDelegates: [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            home: homeScreen,
          ),
        );
      },
    );
  }
}

// ============================================================================
// МОДЕЛЬ И СЧИТЫВАТЕЛЬ СТИЛЕЙ ИЗ index.html
// ============================================================================
class IndexTheme {
  final Color bgColor;
  final Color surfaceCard;
  final Color borderColor;
  final Color primaryColor;
  final Color accentColor;
  final Color textMain;
  final Color textSecondary;

  const IndexTheme({
    this.bgColor = const Color(0xFF0B0F19),
    this.surfaceCard = const Color(0xFF131C2E),
    this.borderColor = const Color(0x14FFFFFF),
    this.primaryColor = const Color(0xFF38BDF8),
    this.accentColor = const Color(0xFF6366F1),
    this.textMain = const Color(0xFFF8FAFC),
    this.textSecondary = const Color(0xFF94A3B8),
  });

  factory IndexTheme.fromCssOrDefaults() {
    if (!kIsWeb) return const IndexTheme();

    try {
      final rootElement = html.document.documentElement;

      final style = rootElement?.getComputedStyle();

      Color parseColor(String varName, Color fallback) {
        if (style == null) return fallback;
        final rawVal = style.getPropertyValue(varName).trim();

        if (rawVal.startsWith('#')) {
          final hex = rawVal.replaceFirst('#', '');
          if (hex.length == 6) {
            return Color(int.parse('FF$hex', radix: 16));
          }
        }
        return fallback;
      }

      return IndexTheme(
        bgColor: parseColor('--bg-color', const Color(0xFF0B0F19)),
        surfaceCard: parseColor('--surface-card', const Color(0xFF131C2E)),
        borderColor: parseColor('--border-color', const Color(0x14FFFFFF)),
        primaryColor: parseColor('--primary-color', const Color(0xFF38BDF8)),
        accentColor: parseColor('--accent-color', const Color(0xFF6366F1)),
        textMain: parseColor('--text-main', const Color(0xFFF8FAFC)),
        textSecondary: parseColor('--text-secondary', const Color(0xFF94A3B8)),
      );
    } catch (_) {
      return const IndexTheme();
    }
  }
}

// ============================================================================
// ЭКРАН-ЗАГЛУШКА ДЛЯ ДЕСКТОПА И ANDROID WEB
// ============================================================================
class SajdahWebStubScreen extends StatelessWidget {
  const SajdahWebStubScreen({super.key});

  Future<void> _openUrl(String urlString) async {
    final Uri url = Uri.parse(urlString);
    try {
      await launchUrl(url, mode: LaunchMode.platformDefault);
    } catch (e) {
      debugPrint("Не удалось открыть ссылку: $urlString");
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isAndroid = SajdahConfig.isAndroidWeb();
    final IndexTheme theme = IndexTheme.fromCssOrDefaults();

    return Scaffold(
      backgroundColor: theme.bgColor,
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.6, -0.8),
                  radius: 0.9,
                  colors: [
                    theme.accentColor.withOpacity(0.12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.6, 0.6),
                  radius: 0.9,
                  colors: [
                    theme.primaryColor.withOpacity(0.10),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildBrandLogo(theme),
                  const SizedBox(height: 32),

                  Container(
                    constraints: const BoxConstraints(maxWidth: 480),
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: theme.surfaceCard,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: theme.borderColor, width: 1),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.4),
                          blurRadius: 32,
                          offset: const Offset(0, 12),
                        ),
                        BoxShadow(
                          color: theme.primaryColor.withOpacity(0.15),
                          blurRadius: 20,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: theme.primaryColor.withOpacity(0.08),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: theme.primaryColor.withOpacity(0.25),
                            ),
                          ),
                          child: Icon(
                            isAndroid ? Icons.phone_android_rounded : Icons.laptop_chromebook_rounded,
                            size: 44,
                            color: theme.primaryColor,
                          ),
                        ),
                        const SizedBox(height: 20),

                        Text(
                          "Sajdah Helper",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: theme.textMain,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            fontFamily: 'Plus Jakarta Sans',
                          ),
                        ),
                        const SizedBox(height: 14),

                        Text(
                          isAndroid
                              ? "Для наиболее точной работы алгоритмов и полной стабильности рекомендуем использовать нативное приложение."
                              : "Приложение спроектировано и оптимизировано исключительно для мобильных устройств.",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: theme.textSecondary,
                            fontSize: 14,
                            height: 1.6,
                            fontFamily: 'Plus Jakarta Sans',
                          ),
                        ),
                        const SizedBox(height: 28),

                        if (isAndroid) ...[
                          _buildPrimaryButton(
                            label: "Установить с RuStore",
                            icon: Icons.download_rounded,
                            theme: theme,
                            onTap: () => _openUrl("https://www.rustore.ru/catalog/app/com.darkframe.sajdah_helper"),
                          ),
                          const SizedBox(height: 12),
                          _buildSecondaryButton(
                            label: "Загрузить с GitHub",
                            icon: Icons.android_rounded,
                            theme: theme,
                            onTap: () => _openUrl("https://github.com/Signa-Inc/Sajdah_Helper/releases"),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),
                  Text(
                    '© 2026 SignaInc',
                    style: TextStyle(
                      color: theme.textSecondary.withOpacity(0.6),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      fontFamily: 'Plus Jakarta Sans',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBrandLogo(IndexTheme theme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          "Signa",
          style: TextStyle(
            color: theme.textMain,
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            fontFamily: 'Plus Jakarta Sans',
          ),
        ),
        ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: [theme.primaryColor, theme.accentColor],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(bounds),
          child: const Text(
            "Inc",
            style: TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              fontFamily: 'Plus Jakarta Sans',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPrimaryButton({
    required String label,
    required IconData icon,
    required IndexTheme theme,
    required VoidCallback onTap,
  }) {
    return Container(
      width: double.infinity,
      height: 50,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0284C7), Color(0xFF6366F1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: theme.primaryColor.withOpacity(0.30),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Plus Jakarta Sans',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSecondaryButton({
    required String label,
    required IconData icon,
    required IndexTheme theme,
    required VoidCallback onTap,
  }) {
    return Container(
      width: double.infinity,
      height: 50,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.borderColor, width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: theme.textMain, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: theme.textMain,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Plus Jakarta Sans',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// ЭКРАН-ИНСТРУКЦИЯ ДЛЯ iOS: УСТАНОВКА PWA
// ============================================================================
class SajdahIosWebPromptScreen extends StatelessWidget {
  const SajdahIosWebPromptScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 450),
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.05), width: 1),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.ios_share_rounded,
                      size: 40,
                      color: Colors.blueAccent,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    "Добавьте на экран «Домой»",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "Для удобного использования Sajdah Helper и стабильной работы в полноэкранном режиме сохраните веб-версию на рабочий стол.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 15,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 32),
                  _buildStep(
                    number: "1",
                    text: "Нажмите иконку «Поделиться» в нижней панели браузера Safari.",
                  ),
                  const SizedBox(height: 14),
                  _buildStep(
                    number: "2",
                    text: "Прокрутите меню вниз и выберите пункт «На экран „Домой“».",
                  ),
                  const SizedBox(height: 14),
                  _buildStep(
                    number: "3",
                    text: "Нажмите «Добавить» в верхнем углу, затем откройте иконку с рабочего стола.",
                  ),
                  const SizedBox(height: 24),
                  const Divider(color: Colors.white10),
                  const SizedBox(height: 12),
                  Text(
                    'Приложение будет запускаться на весь экран, без элементов браузера, чтобы вас ничего не отвлекало.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.4),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep({required String number, required String text}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: Colors.white12,
            shape: BoxShape.circle,
          ),
          child: Text(
            number,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 14, height: 1.4),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// ВИДЖЕТ ИНСТРУКЦИИ (ONBOARDING)
// ============================================================================
class SajdahOnboardingScreen extends StatefulWidget {
  final VoidCallback onCompleted;

  const SajdahOnboardingScreen({super.key, required this.onCompleted});

  @override
  State<SajdahOnboardingScreen> createState() => _SajdahOnboardingScreenState();
}

class _SajdahOnboardingScreenState extends State<SajdahOnboardingScreen> {
  int _currentStepIndex = 0;
  VideoPlayerController? _videoController;
  Timer? _countdownTimer;
  int _secondsRemaining = 0;
  bool _isButtonEnabled = false;

  late final List<Map<String, dynamic>> _steps;

  @override
  void initState() {
    super.initState();

    _steps = [
      if (SajdahConfig.isiOSWeb())
        {
          'textKey': 'onboarding_text_toDarkInRoom_ios_pwa',
          'video': 'assets/videos/video_toDarkInRoom.mp4',
          'duration': 6,
        }
      else ...[
        {
          'textKey': 'onboarding_text_phoneOnFloor',
          'video': 'assets/videos/video_phoneOnFloor.mp4',
          'duration': 5,
        },
        {
          'textKey': 'onboarding_text_cameraDetection',
          'video': 'assets/videos/video_cameraDetection.mp4',
          'duration': 6,
        },
        {
          'textKey': 'onboarding_text_toDarkInRoom',
          'video': 'assets/videos/video_toDarkInRoom.mp4',
          'duration': 6,
        },
      ],
      {
        'textKey': 'onboarding_text_warning',
        'video': 'assets/videos/video_warning.mp4',
        'duration': 10,
      },
      {
        'textKey': 'onboarding_text_theEnd',
        'video': 'assets/videos/video_theEnd.mp4',
        'duration': 5,
      },
    ];

    _initStep();
  }

  void _initStep() async {
    _countdownTimer?.cancel();

    final oldController = _videoController;
    _videoController = null;

    if (mounted) {
      setState(() {});
    }

    if (oldController != null) {
      await oldController.dispose();
    }

    final currentStep = _steps[_currentStepIndex];

    _secondsRemaining = (currentStep['duration'] as num).round();
    _isButtonEnabled = _secondsRemaining <= 0;

    final newController = VideoPlayerController.asset(currentStep['video']);

    try {
      await newController.initialize();
      await newController.setLooping(true);
      await newController.setVolume(0.0);
      await newController.play();

      if (mounted) {
        setState(() {
          _videoController = newController;
        });
      } else {
        await newController.dispose();
      }
    } catch (e) {
      debugPrint("Ошибка загрузки видео инструкции: $e");
      if (mounted) {
        setState(() {
          _videoController = null;
        });
      }
    }

    if (_secondsRemaining > 0) {
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) return;
        setState(() {
          if (_secondsRemaining > 1) {
            _secondsRemaining--;
          } else {
            _secondsRemaining = 0;
            _isButtonEnabled = true;
            _countdownTimer?.cancel();
          }
        });
      });
    }
  }

  void _nextStep() async {
    if (!_isButtonEnabled) return;

    if (_currentStepIndex < _steps.length - 1) {
      setState(() {
        _currentStepIndex++;
      });
      _initStep();
    } else {
      _countdownTimer?.cancel();
      if (_videoController != null) {
        await _videoController!.dispose();
      }
      if (SajdahStorage().isFirstLaunch()) {
        await SajdahStorage().setFirstLaunchCompleted();
      }
      widget.onCompleted();
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localization = SajdahLocalization();
    final currentStep = _steps[_currentStepIndex];
    final isLastStep = _currentStepIndex == _steps.length - 1;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 10),
              Text(
                localization.translate(currentStep['textKey']),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 18,
                  fontWeight: FontWeight.w300,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 35),
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
                ),
                clipBehavior: Clip.antiAlias,
                child: _videoController != null && _videoController!.value.isInitialized
                    ? AspectRatio(
                  aspectRatio: _videoController!.value.aspectRatio,
                  child: VideoPlayer(_videoController!),
                )
                    : const AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Center(
                    child: CircularProgressIndicator(color: Colors.white24),
                  ),
                ),
              ),
              const SizedBox(height: 45),
              GestureDetector(
                onTap: _isButtonEnabled ? _nextStep : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: double.infinity,
                  height: 55,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _isButtonEnabled
                        ? Colors.white.withOpacity(0.08)
                        : Colors.white.withOpacity(0.02),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _isButtonEnabled
                          ? Colors.white.withOpacity(0.3)
                          : Colors.white.withOpacity(0.05),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    _isButtonEnabled
                        ? (isLastStep
                        ? localization.translate('start_button')
                        : localization.translate('next_button'))
                        : "${localization.translate('next_button')} ($_secondsRemaining ${localization.translate('seconds_short')})",
                    style: TextStyle(
                      color: _isButtonEnabled ? Colors.white : Colors.white30,
                      fontSize: 16,
                      fontWeight: _isButtonEnabled ? FontWeight.w500 : FontWeight.w300,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// ГЛАВНЫЙ ЭКРАН ПРИЛОЖЕНИЯ (SAJDAH SCREEN)
// ============================================================================
class SajdahScreen extends StatefulWidget {
  const SajdahScreen({super.key});
  @override
  State<SajdahScreen> createState() => _SajdahScreenState();
}

class _SajdahScreenState extends State<SajdahScreen> with WidgetsBindingObserver {
  bool _isDndNativeActive = false;

  CameraController? controller;
  double rakatCount = 0;

  late final SajdahFrameAnalyzer _frameAnalyzer;

  Uint8List? get baselineFrame => _frameAnalyzer.baselineFrame;
  set baselineFrame(Uint8List? value) => _frameAnalyzer.baselineFrame = value;

  bool isSajdaDetected = false;
  DateTime? lastSajdaTime;
  int confirmCount = 0;

  final ValueNotifier<double> _brightnessNotifier = ValueNotifier(0.0);
  final ValueNotifier<double> _changePercentageNotifier = ValueNotifier(0.0);

  bool showCameraPreview = false;
  bool isFrontCameraFinded = true;

  bool isDebugMode = true;
  bool isSettingsOpen = false;

  DateTime? _lastFrameTime;

  bool isInitializing = true;
  int _warmupFrames = 0;
  bool showStatusMessage = false;
  String statusMessageText = "";
  Color statusMessageColor = Colors.yellow;

  bool hasCheckedInitialBrightness = false;

  int _stableFrameCount = 0;
  double _lastRakatCountAtBaselineUpdate = 0;
  bool _baselineUpdatePending = false;

  static const platform = MethodChannel('com.darkframe.sajdah_helper/dnd');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    try {
      WakelockPlus.enable();
    } catch (e) {
      debugPrint("Wakelock enable error: $e");
    }

    _frameAnalyzer = SajdahConfig.isiOSWeb() ? IosWebFrameAnalyzer() : AndroidFrameAnalyzer();

if (SajdahConfig.isiOSWeb()) {
  _initIosWebFaceLoop();
}

    isDebugMode = SajdahStorage().getDebugMode();

    initCamera();

    if (!SajdahConfig.isWeb()) {
      _executeDndCommand('saveInitialState').then((_) {
        _isDndNativeActive = SajdahStorage().getDndEnabled();
        _executeDndCommand(_isDndNativeActive ? 'activateDnd' : 'inactivateDnd');
      });
    } else {
      isInitializing = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final dndEnabled = SajdahStorage().getDndEnabled();

    if (state == AppLifecycleState.resumed) {
      try {
        WakelockPlus.enable();
      } catch (e) {
        debugPrint("Wakelock enable error: $e");
      }

      if (dndEnabled && !_isDndNativeActive) {
        _executeDndCommand('activateDnd');
        _isDndNativeActive = true;
      }
    }
    else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {

      if (dndEnabled && _isDndNativeActive) {
        _executeDndCommand('restoreDnd');
        _isDndNativeActive = false;
      }
    }

    if (controller == null || !controller!.value.isInitialized || isSettingsOpen || !SajdahStorage().getCameraEnabled()) return;

    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      controller?.stopImageStream();
    } else if (state == AppLifecycleState.resumed) {
      if (isFrontCameraFinded && !controller!.value.isStreamingImages) {
        controller?.startImageStream(analyzeFrame);
      }
    }
  }

  Future<void> _executeDndCommand(String command) async {
    if (SajdahConfig.isWeb()) return;

    try {
      await platform.invokeMethod(command);
    } on PlatformException catch (e) {
      debugPrint("Ошибка DND при команде $command: ${e.message}");
    } catch (e) {
      debugPrint("Ошибка DND (MethodChannel) при команде $command: $e");
    }
  }

  Future<void> initCamera() async {
    if (SajdahConfig.isiOSWeb()) {
      // iOS Web использует отдельный getUserMedia + face-api.js вместо пакета camera
      return;
    }

    if (!SajdahStorage().getCameraEnabled()) {
      if (mounted) {
        setState(() {
          isInitializing = false;
        });
      }
      return;
    }

    try {
      _cameras = await availableCameras();
    } catch (e) {
      debugPrint("Ошибка получения списка камер: $e");
      _cameras = <CameraDescription>[];
    }

    if (_cameras.isEmpty) {
      debugPrint("Камеры не найдены на устройстве");
      setState(() {
        isInitializing = false;
      });
      return;
    }

    CameraDescription selectedCamera = _cameras.firstWhere(
          (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () {
        isFrontCameraFinded = false;
        return _cameras.first;
      },
    );

    if (!isFrontCameraFinded) {
      setState(() {
        isInitializing = false;
      });
      return;
    }

    controller = CameraController(selectedCamera, ResolutionPreset.low, enableAudio: false);

    try {
      await controller!.initialize();

      if (!isSettingsOpen && controller!.value.isInitialized) {
        if (!SajdahConfig.isWeb()) {
          try {
            _warmupFrames = 30;
            await controller!.startImageStream(analyzeFrame);

            await Future.delayed(const Duration(milliseconds: 500));

            if (controller!.value.isInitialized && !isSettingsOpen) {
              await controller!.setFocusMode(FocusMode.locked);
              await controller!.setExposureMode(ExposureMode.locked);
              await controller!.lockCaptureOrientation(DeviceOrientation.portraitUp);
            }
          } catch (e) {
            debugPrint("Ошибка настройки нативного стрима камеры: $e");
          }
        }
      }
    } catch (e) {
      debugPrint("Ошибка камеры: $e");
      if (mounted) {
        setState(() {
          isInitializing = false;
        });
      }
    }

    if (mounted) setState(() {});
  }

  void toggleSettings() async {
    setState(() {
      isSettingsOpen = !isSettingsOpen;
    });

    if (isSettingsOpen) {
      if (!SajdahConfig.isWeb() && SajdahStorage().getCameraEnabled()) {
        if (controller != null && controller!.value.isStreamingImages) {
          await controller?.stopImageStream();
        }
      }
    } else {
      if (SajdahStorage().getCameraEnabled() && isFrontCameraFinded && controller != null && controller!.value.isInitialized) {
        if (!SajdahConfig.isWeb()) {
          if (!controller!.value.isStreamingImages) {
            _frameAnalyzer.resetBaseline();
            _warmupFrames = 20;
            try {
              await controller!.startImageStream(analyzeFrame);

              await Future.delayed(const Duration(milliseconds: 500));
              if (controller!.value.isInitialized && !isSettingsOpen) {
                await controller!.setFocusMode(FocusMode.locked);
                await controller!.setExposureMode(ExposureMode.locked);
              }
            } catch (e) {
              debugPrint("Ошибка перезапуска нативного стрима камеры: $e");
            }
          }
        }
      }
    }
  }

  void analyzeFrame(CameraImage image) {
    if(!isFrontCameraFinded || isSettingsOpen) return;
    if (_warmupFrames > 0) {
      _warmupFrames--;
      return;
    }

    final now = DateTime.now();
    if (_lastFrameTime != null &&
        now.difference(_lastFrameTime!).inMilliseconds < SajdahConfig.frameThrottleMs) {
      return;
    }
    _lastFrameTime = now;

    final bytes = image.planes[0].bytes;
    final int width = image.width;
    final int height = image.height;
    final int bytesPerRow = image.planes[0].bytesPerRow;

    final sensorOrientation = controller?.description.sensorOrientation ?? 270;
    final result = _frameAnalyzer.analyze(
      currentBytes: bytes,
      width: width,
      height: height,
      bytesPerRow: bytesPerRow,
      sensorOrientation: sensorOrientation,
      isDebugMode: isDebugMode,
    );

    if (!hasCheckedInitialBrightness) {
      hasCheckedInitialBrightness = true;
      isInitializing = false;
      showStatusMessage = true;

      setState(() {
        if (result.avgBrightness <= SajdahConfig.minBrightnessThreshold) {
          statusMessageText = SajdahLocalization().translate('too_dark');
          statusMessageColor = Colors.redAccent;
        } else {
          statusMessageText = SajdahLocalization().translate('all_good');
          statusMessageColor = Colors.greenAccent;
        }
      });

      Timer(const Duration(seconds: 5), () {
        if (mounted) {
          setState(() { showStatusMessage = false; });
        }
      });
    }

    _changePercentageNotifier.value = result.computedPercentage;
    _brightnessNotifier.value = result.avgBrightness;

    if (result.computedPercentage > SajdahConfig.detectionThreshold) {
      confirmCount++;
      if (confirmCount >= SajdahConfig.framesToConfirm && !isSajdaDetected) {
        processSajda();
        isSajdaDetected = true;
      }
    } else if (result.computedPercentage < SajdahConfig.resetThreshold) {
      confirmCount = 0;
      isSajdaDetected = false;

      if (rakatCount > _lastRakatCountAtBaselineUpdate) {
        _baselineUpdatePending = true;
      }

      if (_baselineUpdatePending) {
        _stableFrameCount++;
        if (_stableFrameCount >= SajdahConfig.stableFramesToUpdateBaseline) {
          baselineFrame = Uint8List.fromList(bytes);
          _lastRakatCountAtBaselineUpdate = rakatCount;
          _baselineUpdatePending = false;
          _stableFrameCount = 0;
        }
      } else {
        _stableFrameCount = 0;
      }
    }
  }

  void analyzeWebFrame(Uint8List jpegBytes) {
    return;
  }

  Future<void> _initIosWebFaceLoop() async {
    await initFaceDetection();
    final started = await startFaceCamera();

    if (!started) {
      if (mounted) setState(() { isInitializing = false; });
      return;
    }

    if (mounted) setState(() { isInitializing = false; });

    final analyzer = _frameAnalyzer as IosWebFrameAnalyzer;

    Timer.periodic(const Duration(milliseconds: 200), (timer) async {
      if (!mounted) {
        timer.cancel();
        stopFaceCamera();
        return;
      }
      if (isSettingsOpen) return;

      final score = await detectFaceScore();
      final result = analyzer.fromFaceScore(score);

      _changePercentageNotifier.value = result.computedPercentage;
      _brightnessNotifier.value = result.avgBrightness;

      if (result.computedPercentage > SajdahConfig.detectionThreshold) {
        confirmCount++;
        if (confirmCount >= SajdahConfig.framesToConfirm && !isSajdaDetected) {
          processSajda();
          isSajdaDetected = true;
        }
      } else {
        confirmCount = 0;
        isSajdaDetected = false;
      }
    });
  }

  void processSajda() async {
    final now = DateTime.now();
    if (lastSajdaTime != null &&
        now.difference(lastSajdaTime!).inSeconds < SajdahConfig.cooldownVibrationSeconds) {
      return;
    }

    lastSajdaTime = now;

    if (SajdahStorage().getVibrationEnabled() && !SajdahConfig.isWeb()) {
      if (_isDndNativeActive) {
        await _executeDndCommand('vibrateWithDndBypassInsideNative');
      } else {
        try {
          Vibration.vibrate(duration: 100);
        } catch (e) {
          debugPrint("Ошибка вибрации: $e");
        }
      }
    }

    if (mounted) {
      setState(() {
        rakatCount += 0.5;
      });
    }
  }

  void resetAll() async {
    if (_isDndNativeActive) {
      _isDndNativeActive = false;
      await _executeDndCommand('restoreDnd');
    }

    if (mounted) {
      SajdahApp.restartApp(context);
    }
  }

  void _showSettingInfo(String title, String description) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  description,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller?.dispose();
    _executeDndCommand('restoreDnd');
    _executeDndCommand('resetSession');
    _brightnessNotifier.dispose();
    _changePercentageNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final localization = SajdahLocalization();

    return Scaffold(
      body: Stack(
        children: [
          if (showCameraPreview && SajdahStorage().getCameraEnabled() && controller != null && controller!.value.isInitialized)
            SizedBox(
              width: size.width,
              height: size.height,
              child: AspectRatio(
                aspectRatio: controller!.value.aspectRatio,
                child: CameraPreview(controller!),
              ),
            ),

          if (showCameraPreview)
            Container(color: Colors.black.withOpacity(0.75)),

          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 3),
                _buildStatLabel(localization.translate('rakats'), Colors.white38, 35),
                const SizedBox(height: 5),
                GestureDetector(
                  onTap: isDebugMode
                      ? () => setState(() => showCameraPreview = !showCameraPreview)
                      : null,
                  child: _buildStatValue(
                      rakatCount % 1 == 0 ? rakatCount.toInt().toString() : rakatCount.toString(),
                      150
                  ),
                ),
                GestureDetector(
                  onPanStart: (_) => resetAll(),
                  child: IconButton(
                    onPressed: resetAll,
                    icon: const Icon(Icons.refresh_rounded),
                    color: Colors.white30,
                    iconSize: 35,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withOpacity(0.01),
                      padding: const EdgeInsets.all(14),
                      side: BorderSide(color: Colors.white.withOpacity(0.04), width: 1),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                if (!isFrontCameraFinded && SajdahStorage().getCameraEnabled())
                  _buildWarningCard(localization.translate('no_front_camera')),

                if (isDebugMode && SajdahStorage().getCameraEnabled() && !SajdahConfig.isiOSWeb())
                  ValueListenableBuilder<double>(
                    valueListenable: _brightnessNotifier,
                    builder: (context, brightness, _) {
                      return ValueListenableBuilder<double>(
                        valueListenable: _changePercentageNotifier,
                        builder: (context, mismatch, _) {
                          return Column(
                            children: [
                              const SizedBox(height: 20),
                              _buildDebugText("${localization.translate('debug_brightness')}${brightness.toStringAsFixed(1)}"),
                              const SizedBox(height: 5),
                              _buildDebugText("${localization.translate('debug_mismatch')}${(mismatch * 100).toStringAsFixed(2)}%"),
                            ],
                          );
                        },
                      );
                    },
                  ),
                const Spacer(flex: 2),
                const SizedBox(height: 130),
              ],
            ),
          ),

          PositionedDirectional(
            top: 45,
            start: 20,
            child: IconButton(
              icon: const Icon(Icons.settings_outlined, color: Colors.white30, size: 32),
              onPressed: toggleSettings,
            ),
          ),

          if (isInitializing && SajdahStorage().getCameraEnabled())
            Positioned(
              top: 52,
              left: 80,
              right: 80,
              child: Text(
                localization.translate('setting_up_camera'),
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.yellow.withOpacity(0.7),
                    fontSize: 23,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.5
                ),
              ),
            ),

          if (showStatusMessage && !isSettingsOpen)
            Positioned(
              top: 52,
              left: 80,
              right: 80,
              child: Text(
                statusMessageText,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 23,
                    color: statusMessageColor.withOpacity(0.8),
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.3
                ),
              ),
            ),

          if (isSettingsOpen) _buildSettingsOverlay(size),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _buildManualButton(),
    );
  }

  Widget _buildSettingsOverlay(Size size) {
    final localization = SajdahLocalization();
    final currentLang = localization.currentLocale;

    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.95),
        padding: const EdgeInsets.only(left: 24, right: 24, top: 45, bottom: 25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  localization.translate('settings_title'),
                  style: const TextStyle(color: Colors.white70, fontSize: 22, fontWeight: FontWeight.w300, letterSpacing: 2),
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: Colors.white.withOpacity(0.5), size: 30),
                  onPressed: toggleSettings,
                ),
              ],
            ),
            const SizedBox(height: 30),

            _buildSettingRow(
              title: localization.translate('setting_vibration'),
              description: localization.translate('setting_vibration_desc'),
              value: SajdahStorage().getVibrationEnabled(),
              onChanged: (val) async {
                await SajdahStorage().saveVibrationEnabled(val);
                setState(() {});
              },
            ),
            const Divider(color: Colors.white10, height: 25),

            if (!SajdahConfig.isiOSWeb()) ...[
              _buildSettingRow(
                title: localization.translate('setting_camera'),
                description: localization.translate('setting_camera_desc'),
                value: SajdahStorage().getCameraEnabled(),
                onChanged: (val) async {
                  await SajdahStorage().saveCameraEnabled(val);
                  if (!val) {
                    if (controller != null) {
                      if (controller!.value.isStreamingImages) {
                        await controller?.stopImageStream();
                      }
                      await controller?.dispose();
                      controller = null;
                    }
                    setState(() {
                      isInitializing = false;
                      showStatusMessage = false;
                    });
                  } else {
                    setState(() {
                      isInitializing = true;
                    });
                    await initCamera();
                  }
                },
              ),
              const Divider(color: Colors.white10, height: 25),
            ],

            _buildSettingRow(
              title: localization.translate('setting_dnd'),
              description: localization.translate('setting_dnd_desc'),
              value: SajdahStorage().getDndEnabled(),
              onChanged: (val) async {
                await SajdahStorage().saveDndEnabled(val);
                setState(() {});

                if (val) {
                  await _executeDndCommand('saveInitialState');
                  await _executeDndCommand('activateDnd');
                  _isDndNativeActive = true;
                } else {
                  await _executeDndCommand('restoreDnd');
                  _isDndNativeActive = false;
                }
              },
            ),
            const Divider(color: Colors.white10, height: 25),

            GestureDetector(
              onTap: () {
                if (mounted) {
                  setState(() {
                    isSettingsOpen = false;
                  });
                  SajdahApp.showTutorial(context);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                color: Colors.transparent,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      localization.translate('replay_tutorial'),
                      style: const TextStyle(color: Colors.white60, fontSize: 18, fontWeight: FontWeight.w300),
                    ),
                    Icon(Icons.refresh_rounded, color: Colors.white.withOpacity(0.4), size: 24),
                  ],
                ),
              ),
            ),
            const Divider(color: Colors.white10, height: 25),

            if (!SajdahConfig.isiOSWeb()) ...[
              _buildSettingRow(
                title: localization.translate('setting_debug'),
                description: localization.translate('setting_debug_desc'),
                value: isDebugMode,
                onChanged: (val) async {
                  await SajdahStorage().saveDebugMode(val);
                  setState(() {
                    isDebugMode = val;
                    if (!isDebugMode) showCameraPreview = false;
                  });
                },
              ),
              const Divider(color: Colors.white10, height: 25),
            ],

            Row(
              children: [
                _buildLangButton(label: "Рус", isActive: currentLang == 'ru', onTap: () => localization.setLanguage('ru')),
                const SizedBox(width: 12),
                _buildLangButton(label: "Eng", isActive: currentLang == 'en', onTap: () => localization.setLanguage('en')),
                const SizedBox(width: 12),
                _buildLangButton(label: "العربية", isActive: currentLang == 'ar', onTap: () => localization.setLanguage('ar')),
              ],
            ),

            const Spacer(),
            Center(
              child: GestureDetector(
                onTap: () async {
                  final Uri url = Uri.parse('https://signainc.ru');
                  try {
                    await launchUrl(
                        url,
                        mode: SajdahConfig.isWeb() ? LaunchMode.platformDefault : LaunchMode.externalApplication
                    );
                  } catch (e) {
                    debugPrint("Не удалось открыть ссылку: $url");
                  }
                },
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'SignaInc',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.25),
                          fontSize: 13,
                          fontWeight: FontWeight.w300,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '1.0.5',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.15),
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingRow({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
    String? description,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  title,
                  style: const TextStyle(color: Colors.white60, fontSize: 18, fontWeight: FontWeight.w300),
                ),
              ),
              if (description != null) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => _showSettingInfo(title, description),
                  child: Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Icon(
                      Icons.help_outline_rounded,
                      color: Colors.white.withOpacity(0.4),
                      size: 20,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        Switch.adaptive(
          value: value,
          activeColor: Colors.greenAccent.withOpacity(0.6),
          activeTrackColor: Colors.greenAccent.withOpacity(0.2),
          inactiveThumbColor: Colors.white.withOpacity(0.2),
          inactiveTrackColor: Colors.white.withOpacity(0.05),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildLangButton({required String label, required bool isActive, required VoidCallback onTap}) {
    return Expanded(
      child: GestureDetector(
        onTap: () async {
          onTap();
          setState(() {});
        },
        child: Container(
          height: 55,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isActive ? Colors.white.withOpacity(0.05) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isActive ? Colors.white.withOpacity(0.25) : Colors.white.withOpacity(0.05),
              width: 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isActive ? Colors.white.withOpacity(0.8) : Colors.white30,
              fontSize: 16,
              fontWeight: isActive ? FontWeight.w400 : FontWeight.w300,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatLabel(String text, Color color, double size) => Text(
    text,
    style: TextStyle(fontSize: size, color: color, fontWeight: FontWeight.w400, letterSpacing: 4.0),
  );

  Widget _buildStatValue(String text, double size) => Text(
    text,
    style: TextStyle(fontSize: size, fontWeight: FontWeight.w100, color: Colors.white70),
  );

  Widget _buildDebugText(String text) => Text(
    text,
    style: const TextStyle(color: Colors.white30, fontSize: 13, fontFamily: 'monospace'),
  );

  Widget _buildWarningCard(String text) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 5),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.orangeAccent.withOpacity(0.01),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orangeAccent.withOpacity(0.06), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent.withOpacity(0.3), size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: const TextStyle(color: Colors.white38, fontSize: 12, height: 1.2)),
          ),
        ],
      ),
    ),
  );

  Widget _buildManualButton() {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 250),
      opacity: isSettingsOpen ? 0.0 : 1.0,
      child: IgnorePointer(
        ignoring: isSettingsOpen,
        child: GestureDetector(
          onTap: processSajda,
          onDoubleTap: processSajda,
          onLongPress: processSajda,
          onPanStart: (_) => processSajda(),
          child: Container(
            width: double.infinity,
            height: 130,
            alignment: Alignment.center,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.01),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
            ),
            child: const Text('+1', style: TextStyle(color: Colors.white38, fontSize: 35)),
          ),
        ),
      ),
    );
  }
}