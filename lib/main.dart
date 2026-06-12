import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:vibration/vibration.dart';
import 'dart:async';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter/services.dart';
import 'sajdah_localization.dart';
import 'sajdah_storage.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

class SajdahConfig {
  static const int pixelStep = 15;
  static const int sensitivityThreshold = 35;
  static const double detectionThreshold = 0.85;
  static const double resetThreshold = 0.25;
  static const int framesToConfirm = 3;
  static const int cooldownVibrationSeconds = 2;
  static const double minBrightessThreshold = 100.0;
  static const int frameThrottleMs = 50;
}

late List<CameraDescription> _cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  await SajdahStorage().init();

  final String systemLang = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
  SajdahLocalization().init(systemLang);

  _cameras = await availableCameras();
  runApp(const SajdahApp());
}

class SajdahApp extends StatefulWidget {
  const SajdahApp({super.key});

  static void restartApp(BuildContext context) {
    context.findAncestorStateOfType<_SajdahAppState>()?.restart();
  }

  @override
  State<SajdahApp> createState() => _SajdahAppState();
}

class _SajdahAppState extends State<SajdahApp> {
  Key _key = UniqueKey();

  void restart() {
    setState(() {
      _key = UniqueKey();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: SajdahLocalization(),
      builder: (context, _) {
        final currentLang = SajdahLocalization().currentLocale;

        return KeyedSubtree(
          key: _key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData.dark().copyWith(
              scaffoldBackgroundColor: Colors.black,
            ),

            // --- ДОБАВЛЯЕМ ЭТИ ТРИ СТРОКИ ---
            locale: Locale(currentLang), // Указывает Flutter текущий язык
            supportedLocales: const [Locale('ru'), Locale('en'), Locale('ar')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            // ---------------------------------

            home: const SajdahScreen(),
          ),
        );
      },
    );
  }
}

class SajdahScreen extends StatefulWidget {
  const SajdahScreen({super.key});
  @override
  State<SajdahScreen> createState() => _SajdahScreenState();
}

class _SajdahScreenState extends State<SajdahScreen> with WidgetsBindingObserver {
  CameraController? controller;
  double rakatCount = 0;

  List<int>? baselineFrame;
  bool isSajdaDetected = false;
  DateTime? lastSajdaTime;
  int confirmCount = 0;

  double currentBrightness = 0.0;
  double changePercentage = 0;

  bool showCameraPreview = false;
  bool isFrontCameraFinded = true;

  // Состояния настроек
  bool isDebugMode = false;
  bool isSettingsOpen = false;

  DateTime? _lastFrameTime;

  bool isInitializing = true;
  bool showStatusMessage = false;
  String statusMessageText = "";
  Color statusMessageColor = Colors.yellow;
  double statusMessageFontSize = 18;

  bool hasCheckedInitialBrightness = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();

    // Загружаем сохраненный режим отладки из памяти
    isDebugMode = SajdahStorage().getDebugMode();

    initCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (controller == null || !controller!.value.isInitialized || isSettingsOpen) return;

    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      controller?.stopImageStream();
    } else if (state == AppLifecycleState.resumed) {
      if (isFrontCameraFinded && !controller!.value.isStreamingImages) {
        controller?.startImageStream(analyzeFrame);
      }
    }
  }

  Future<void> initCamera() async {
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

      if (controller!.value.isInitialized) {
        await controller!.setFocusMode(FocusMode.locked);
        await controller!.setExposureMode(ExposureMode.locked);
        await controller!.lockCaptureOrientation(DeviceOrientation.portraitUp);
      }

      // Запускаем стрим только если панель настроек закрыта
      if (!isSettingsOpen) {
        controller!.startImageStream(analyzeFrame);
      }
    } catch (e) {
      debugPrint("Ошибка камеры: $e");
      setState(() {
        isInitializing = false;
      });
    }

    if (mounted) setState(() {});
  }

  // Метод переключения панели настроек с остановкой/запуском камеры
  void toggleSettings() async {
    setState(() {
      isSettingsOpen = !isSettingsOpen;
    });

    if (isSettingsOpen) {
      // Засыпаем: останавливаем камеру и убираем превью дебага
      if (controller != null && controller!.value.isStreamingImages) {
        await controller?.stopImageStream();
      }
    } else {
      // Просыпаемся: если фронталка на месте, заводим стрим заново
      if (isFrontCameraFinded && controller != null && controller!.value.isInitialized) {
        if (!controller!.value.isStreamingImages) {
          baselineFrame = null; // Сбрасываем базовый кадр для адаптации к возможно новому освещению
          controller!.startImageStream(analyzeFrame);
        }
      }
    }
  }

  void analyzeFrame(CameraImage image) {
    if(!isFrontCameraFinded || isSettingsOpen) return;

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

    double avgBrightness = 0;
    if (!hasCheckedInitialBrightness || isDebugMode) {
      double totalBrightness = 0;
      int checkStep = 50;
      int count = 0;
      for (int i = 0; i < bytes.length; i += checkStep) {
        totalBrightness += bytes[i];
        count++;
      }
      avgBrightness = count > 0 ? totalBrightness / count : 0;
    }

    if (!hasCheckedInitialBrightness) {
      hasCheckedInitialBrightness = true;
      isInitializing = false;
      showStatusMessage = true;

      if (avgBrightness <= SajdahConfig.minBrightessThreshold) {
        statusMessageText = SajdahLocalization().translate('too_dark');
        statusMessageColor = Colors.redAccent;
        statusMessageFontSize = 23;
      } else {
        statusMessageText = SajdahLocalization().translate('all_good');
        statusMessageColor = Colors.greenAccent;
        statusMessageFontSize = 23;
      }

      Timer(const Duration(seconds: 5), () {
        if (mounted) {
          setState(() {
            showStatusMessage = false;
          });
        }
      });
    }

    if (baselineFrame == null) {
      baselineFrame = List<int>.from(bytes);
      if (mounted) {
        setState(() {
          currentBrightness = avgBrightness;
        });
      }
      return;
    }

    int changedPixels = 0;
    int totalChecked = 0;

    final int sensorOrientation = controller?.description.sensorOrientation ?? 270;

    int startX = 0;
    int endX = width;
    int startY = 0;
    int endY = height;

    if (sensorOrientation == 270) {
      startX = width ~/ 2;
      endX = width;
    } else if (sensorOrientation == 90) {
      startX = 0;
      endX = width ~/ 2;
    } else {
      startY = 0;
      endY = height ~/ 2;
    }

    for (int y = startY; y < endY; y += SajdahConfig.pixelStep) {
      for (int x = startX; x < endX; x += SajdahConfig.pixelStep) {

        int index = (y * bytesPerRow) + x;

        if (index < bytes.length && index < baselineFrame!.length) {
          totalChecked++;

          final int diff = (bytes[index] - baselineFrame![index]).abs();

          if (diff > SajdahConfig.sensitivityThreshold) {
            changedPixels++;
          }
        }
      }
    }

    final double computedPercentage = totalChecked > 0 ? (changedPixels / totalChecked) : 0;
    changePercentage = computedPercentage;
    currentBrightness = avgBrightness;

    if (mounted && isDebugMode) {
      setState(() {});
    }

    if (changePercentage > SajdahConfig.detectionThreshold) {
      confirmCount++;
      if (confirmCount >= SajdahConfig.framesToConfirm && !isSajdaDetected) {
        processSajda();
        isSajdaDetected = true;
      }
    } else if (changePercentage < SajdahConfig.resetThreshold) {
      confirmCount = 0;
      isSajdaDetected = false;
    }
  }

  void processSajda() {
    final now = DateTime.now();
    if (lastSajdaTime != null &&
        now.difference(lastSajdaTime!).inSeconds < SajdahConfig.cooldownVibrationSeconds) {
      return;
    }

    lastSajdaTime = now;

    // Проверяем настройку вибрации перед запуском мотора
    if (SajdahStorage().getVibrationEnabled()) {
      Vibration.vibrate(duration: 100);
    }

    setState(() {
      rakatCount += 0.5;
    });
  }

  void resetAll() {
    SajdahApp.restartApp(context);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller?.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Stack(
        children: [
          // Главный экран приложения
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

                _buildStatLabel(SajdahLocalization().translate('rakats'), Colors.white38, 35),

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

                IconButton(
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

                const SizedBox(height: 10),

                if (!isFrontCameraFinded)
                  _buildWarningCard(SajdahLocalization().translate('no_front_camera')),

                if (isDebugMode) ...[
                  const SizedBox(height: 20),
                  _buildDebugText("Яркость: ${currentBrightness.toStringAsFixed(1)}"),
                  const SizedBox(height: 5),
                  _buildDebugText("Несовпадение: ${(changePercentage * 100).toStringAsFixed(2)}%"),
                ],

                const Spacer(flex: 2),

                const SizedBox(height: 130),
              ],
            ),
          ),

          // КНОПКА НАСТРОЕК (В верхнем левом углу)
          PositionedDirectional(
            top: 45,
            start: 20, // Вместо left: 20
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
                SajdahLocalization().translate('setting_up_camera'),
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
                    color: statusMessageColor.withOpacity(0.8),
                    fontSize: statusMessageFontSize,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.3
                ),
              ),
            ),

          // ПАНЕЛЬ НАСТРОЕК СВЕРХУ (Оверлей)
          if (isSettingsOpen) _buildSettingsOverlay(size),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: isSettingsOpen ? null : _buildManualButton(),
    );
  }

  // --- Виджет Оверлея Настроек ---
  Widget _buildSettingsOverlay(Size size) {
    final localization = SajdahLocalization();
    final currentLang = localization.currentLocale;

    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.95),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 45),
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
                  // Убрали const, так как .withOpacity вычисляется в рантайме
                  icon: Icon(Icons.close_rounded, color: Colors.white.withOpacity(0.5), size: 30),
                  onPressed: toggleSettings,
                ),
              ],
            ),
            const SizedBox(height: 40),

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
            const Divider(color: Colors.white10, height: 30),

            _buildSettingRow(
              title: localization.translate('setting_vibration'),
              value: SajdahStorage().getVibrationEnabled(),
              onChanged: (val) async {
                await SajdahStorage().saveVibrationEnabled(val);
                setState(() {});
              },
            ),
            const Divider(color: Colors.white10, height: 40),

            Row(
              children: [
                _buildLangButton(label: "Рус", isActive: currentLang == 'ru', onTap: () => localization.setLanguage('ru')),
                const SizedBox(width: 12),
                _buildLangButton(label: "Eng", isActive: currentLang == 'en', onTap: () => localization.setLanguage('en')),
                const SizedBox(width: 12),
                _buildLangButton(label: "العربية", isActive: currentLang == 'ar', onTap: () => localization.setLanguage('ar')),
              ],
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
          inactiveThumbColor: Colors.white.withOpacity(0.2), // Исправлено здесь
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
              color: isActive ? Colors.white.withOpacity(0.8) : Colors.white30, // Исправлено здесь
              fontSize: 16,
              fontWeight: isActive ? FontWeight.w400 : FontWeight.w300,
            ),
          ),
        ),
      ),
    );
  }

  // --- Вспомогательные Stealth-виджеты ---

  Widget _buildStatLabel(String text, Color color, double size) => Text(
    text,
    style: TextStyle(
      fontSize: size,
      color: color,
      fontWeight: FontWeight.w400,
      letterSpacing: 4.0,
    ),
  );

  Widget _buildStatValue(String text, double size) => Text(
    text,
    style: TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w100,
      color: Colors.white70,
    ),
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
            child: Text(
              text,
              style: const TextStyle(color: Colors.white38, fontSize: 12, height: 1.2),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildManualButton() => GestureDetector(
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
      child: const Text(
        '+1',
        style: TextStyle(color: Colors.white38, fontSize: 35),
      ),
    ),
  );
}