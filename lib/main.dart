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
import 'package:image/image.dart' as img;

// ============================================================================
// АРХИТЕКТУРА: ПАТТЕРН СТРАТЕГИЯ ДЛЯ АНАЛИЗА КАДРОВ
// ============================================================================

/// Результат анализа кадра, передаваемый обратно в экран
class AnalysisResult {
  final double computedPercentage;
  final double avgBrightness;

  AnalysisResult({required this.computedPercentage, required this.avgBrightness});
}

/// Абстрактный класс стратегии анализа кадров
abstract class SajdahFrameAnalyzer {
  Uint8List? baselineFrame;

  /// Метод сброса базового кадра при перезапуске
  void resetBaseline() {
    baselineFrame = null;
  }

  /// Абстрактный метод для обработки кадра
  AnalysisResult analyze({
    required Uint8List currentBytes,
    required int width,
    required int height,
    required int bytesPerRow,
    required int sensorOrientation,
    required bool isDebugMode,
  });
}

/// СТРАТЕГИЯ ДЛЯ ANDROID: Оригинальный алгоритм без изменений
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

// ПРАВКА: Удален неиспользуемый класс IosPwaFrameAnalyzer, так как на iOS PWA
// анализ кадров отключен и метод детекции переведен в режим заглушки.

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
  static bool isiOSWeb() => kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  static bool isAndroidWeb() => kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static bool isWindows() => defaultTargetPlatform == TargetPlatform.windows;
  static bool isMacOS() => defaultTargetPlatform == TargetPlatform.macOS;
  static bool isLinux() => defaultTargetPlatform == TargetPlatform.linux;
  static bool isWeb() => kIsWeb;

  static bool shouldShowStub() => isAndroidWeb() || isWindows() || isMacOS() || isLinux();
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

  // Инициализация списка камер убрана отсюда, чтобы не триггерить её на заглушках и до проверки девайса

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
        } else if (_showOnboarding) {
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

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 500),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.05), width: 1),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.02),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                  ),
                  child: Icon(
                    isAndroid ? Icons.phone_android_rounded : Icons.laptop_chromebook_rounded,
                    size: 48,
                    color: const Color(0xFFBB86FC),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  "Sajdah Helper",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  isAndroid
                      ? "Полноценная работа приложения в мобильном браузере Android не поддерживается из-за ограничений веб-камеры. Пожалуйста, установите наше приложение для лучшего опыта."
                      : "Этот проект разработан только для mobile устройств.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 15,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 32),
                if (isAndroid) ...[
                  _buildButton(
                    label: "Скачать из RuStore",
                    icon: Icons.download_rounded,
                    color: const Color(0xFFBB86FC),
                    textColor: Colors.black,
                    onTap: () => _openUrl("https://www.rustore.ru/catalog/app/com.darkframe.sajdah_helper"),
                  ),
                  const SizedBox(height: 12),
                  _buildButton(
                    label: "Скачать APK напрямую",
                    icon: Icons.android_rounded,
                    color: Colors.white.withOpacity(0.05),
                    textColor: Colors.white,
                    borderColor: Colors.white.withOpacity(0.2),
                    onTap: () => _openUrl("https://github.com/Signa-Inc/"),
                  ),
                ] else ...[
                  _buildButton(
                    label: "Перейти на главную сайта",
                    icon: Icons.language_rounded,
                    color: const Color(0xFFBB86FC),
                    textColor: Colors.black,
                    onTap: () => _openUrl("https://github.com/Signa-Inc/"),
                  ),
                ],
                const SizedBox(height: 32),
                const Divider(color: Colors.white10),
                const SizedBox(height: 8),
                Text(
                  'Dark Frame',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.25),
                    fontSize: 13,
                    fontWeight: FontWeight.w300,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildButton({
    required String label,
    required IconData icon,
    required Color color,
    required Color textColor,
    Color? borderColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        height: 52,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          border: borderColor != null ? Border.all(color: borderColor, width: 1) : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: textColor, size: 20),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                color: textColor,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
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
      // Эти шаги добавятся в любом случае в конец списка
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

  // ПРАВКА: Удалены неиспользуемые переменные таймера веба (_frameTimer и _isProcessingWebFrame),
  // провоцировавшие нагрев и лаги на iOS PWA.

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

    // ПРАВКА: В силу того, что iOS PWA переведен на заглушку, используем стандартный
    // AndroidFrameAnalyzer для нативного бэкенда, убирая мертвый код.
    _frameAnalyzer = AndroidFrameAnalyzer();

    isDebugMode = SajdahStorage().getDebugMode();

    // Инициализация камеры теперь сама подтянет список камер после всех проверок
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

    if (controller == null || !controller!.value.isInitialized || isSettingsOpen) return;

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
    // Если это iOS PWA, то камера нам вообще не нужна, так как анализ отключен
    if (SajdahConfig.isiOSWeb()) {
      setState(() {
        isInitializing = false;
      });
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
        // ПРАВКА: Изъят тяжелый таймер цикличного вызова takePicture для Web.
        // Нативные платформы по-прежнему запускают оптимизированный image stream.
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
      // ПРАВКА: Убран блок остановки таймера веба за ненадобностью.
      if (!SajdahConfig.isWeb()) {
        if (controller != null && controller!.value.isStreamingImages) {
          await controller?.stopImageStream();
        }
      }
    } else {
      if (isFrontCameraFinded && controller != null && controller!.value.isInitialized) {
        // ПРАВКА: Исключен блок инициализации таймера веба, стрим запускается только на нативе.
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller?.dispose();
    _executeDndCommand('restoreDnd');
    _executeDndCommand('resetSession');
    _brightnessNotifier.dispose();
    _changePercentageNotifier.dispose();
    // ПРАВКА: Убрана очистка несуществующего веб-таймера.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final localization = SajdahLocalization();

    return Scaffold(
      body: Stack(
        children: [
          if (showCameraPreview && controller != null && controller!.value.isInitialized)
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
                if (!isFrontCameraFinded)
                  _buildWarningCard(localization.translate('no_front_camera')),

                if (isDebugMode && !SajdahConfig.isiOSWeb())
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

          if (isInitializing)
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
              value: SajdahStorage().getVibrationEnabled(),
              onChanged: (val) async {
                await SajdahStorage().saveVibrationEnabled(val);
                setState(() {});
              },
            ),
            const Divider(color: Colors.white10, height: 25),

            _buildSettingRow(
              title: localization.translate('setting_dnd'),
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
                  final Uri url = Uri.parse('https://github.com/Signa-Inc/');
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
                        'Dark Frame',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.25),
                          fontSize: 13,
                          fontWeight: FontWeight.w300,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '1.0.0',
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

  Widget _buildSettingRow({required String title, required bool value, required ValueChanged<bool> onChanged}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: const TextStyle(color: Colors.white60, fontSize: 18, fontWeight: FontWeight.w300)),
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