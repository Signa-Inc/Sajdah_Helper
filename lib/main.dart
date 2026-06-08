import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:vibration/vibration.dart';
import 'dart:async';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter/services.dart';

// --- КОНФИГ ---
class SajdahConfig {
  static const int pixelStep = 15;                      // Шаг проверки пикселей (чем больше, тем быстрее, но хуже точность)
  static const int sensitivityThreshold = 35;           // Насколько сильно должен измениться цвет пикселя (0-255)
  static const double detectionThreshold = 0.85;        // % изменений для фиксации суджуда
  static const double resetThreshold = 0.25;            // % изменений для сброса состояния (поднялся)
  static const int framesToConfirm = 3;                 // Сколько кадров подряд нужно для детекции
  static const int cooldownVibrationSeconds = 2;        // Защита от дребезга (пауза между суджудами)
  static const double minBrightessThreshold = 100.0;    // Порог "слишком темно"
}

late List<CameraDescription> _cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky); // Убираем статус-бар

  // Жестко фиксируем ориентацию самого приложения в портрет
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  _cameras = await availableCameras();
  runApp(const SajdahApp());
}

class SajdahApp extends StatelessWidget {
  const SajdahApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark().copyWith(
      scaffoldBackgroundColor: Colors.black, // Гарантируем глубокий черный фон
    ),
    home: const SajdahScreen(),
  );
}

class SajdahScreen extends StatefulWidget {
  const SajdahScreen({super.key});
  @override
  State<SajdahScreen> createState() => _SajdahScreenState();
}

class _SajdahScreenState extends State<SajdahScreen> {
  CameraController? controller;
  double rakatCount = 0;

  List<int>? baselineFrame;
  bool isSajdaDetected = false;
  DateTime? lastSajdaTime;
  int confirmCount = 0;

  double currentBrightness = 0.0;
  double changePercentage = 0;

  // Флаг видимости камеры в UI
  bool showCameraPreview = false;

  bool isFrontCameraFinded = true;

  bool isDebugMode = false;

  // --- ПЕРЕМЕННЫЕ ДЛЯ ТАСКОВ С ТЕМНОТОЙ ---
  bool showDarkWarning = false;               // Показывается ли сейчас предупреждение
  bool hasCheckedInitialBrightness = false;   // Была ли уже сделана стартовая проверка

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable(); // Экрану запрещено гаснуть
    initCamera();
  }

  Future<void> initCamera() async {
    if (_cameras.isEmpty) {
      debugPrint("Камеры не найдены на устройстве");
      return;
    }

    // Ищем фронтальную камеру по её типу направления линзы
    CameraDescription selectedCamera = _cameras.firstWhere(
          (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () {
        isFrontCameraFinded = false; // Фронталка НЕ найдена, меняем флаг на false
        return _cameras.first;       // Возвращаем первую доступную камеру как запасной вариант
      },
    );

    controller = CameraController(selectedCamera, ResolutionPreset.low, enableAudio: false);

    try {
      await controller!.initialize();

      if (controller!.value.isInitialized) {
        await controller!.setFocusMode(FocusMode.locked);
        await controller!.setExposureMode(ExposureMode.locked);
        await controller!.lockCaptureOrientation(DeviceOrientation.portraitUp);
      }

      controller!.startImageStream(analyzeFrame);
    } catch (e) {
      debugPrint("Ошибка камеры: $e");
    }

    if (mounted) setState(() {});
  }

  void analyzeFrame(CameraImage image) {
    if(!isFrontCameraFinded) return;

    final bytes = image.planes[0].bytes;
    final int width = image.width;
    final int height = image.height;
    final int bytesPerRow = image.planes[0].bytesPerRow;

    // 1. Считаем общую яркость
    double totalBrightness = 0;
    int checkStep = 50;
    int count = 0;
    for (int i = 0; i < bytes.length; i += checkStep) {
      totalBrightness += bytes[i];
      count++;
    }
    double avgBrightness = count > 0 ? totalBrightness / count : 0;

    // СТАРТОВАЯ ПРОВЕРКА ЯРКОСТИ (Выполняется 1 раз за запуск)
    if (!hasCheckedInitialBrightness) {
      hasCheckedInitialBrightness = true;
      if (avgBrightness <= SajdahConfig.minBrightessThreshold) {
        showDarkWarning = true;
        // Таймер авто-скрытия плашки ровно через 10 секунд
        Timer(const Duration(seconds: 10), () {
          if (mounted) {
            setState(() {
              showDarkWarning = false;
            });
          }
        });
      }
    }

    // 2. Инициализируем базовый кадр
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

    // 3. АВТООПРЕДЕЛЕНИЕ ГЕОМЕТРИИ (ВЕРХ ТЕЛЕФОНА)
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

    // 4. Сканируем только вычисленную область
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

    if (mounted) {
      setState(() {
        currentBrightness = avgBrightness;
        changePercentage = totalChecked > 0 ? (changedPixels / totalChecked) : 0;
      });
    }

    // 5. Логика детекции суджуда
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
    Vibration.vibrate(duration: 100);

    setState(() {
      rakatCount += 0.5;
    });
  }

  Future<void> resetAll() async {
    setState(() {
      rakatCount = 0;
      baselineFrame = null;
      confirmCount = 0;
    });

    if (controller != null && controller!.value.isInitialized) {
      await controller!.setExposureMode(ExposureMode.auto);
      await Future.delayed(const Duration(milliseconds: 500));
      await controller!.setExposureMode(ExposureMode.locked);
    }
  }

  @override
  void dispose() {
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
          // 1. ЗАДНИЙ ФОН: Камера (если включена)
          if (showCameraPreview && controller != null && controller!.value.isInitialized)
            SizedBox(
              width: size.width,
              height: size.height,
              child: AspectRatio(
                aspectRatio: controller!.value.aspectRatio,
                child: CameraPreview(controller!),
              ),
            ),

          // 2. СЛОЙ UI: глубокое затемнение поверх превью для максимальной скрытности
          if (showCameraPreview)
            Container(color: Colors.black.withOpacity(0.75)),

          // 3. КОНТЕНТ UI
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 3), // Центрируем контент более плавно

                _buildStatLabel("РАКААТЫ", Colors.white24, 20),

                const SizedBox(height: 5),

                // Нажатие на цифру ракаатов тоже переключает камеру в дебаге
                GestureDetector(
                  onTap: isDebugMode
                      ? () => setState(() => showCameraPreview = !showCameraPreview)
                      : null,
                  child: _buildStatValue(
                      rakatCount % 1 == 0 ? rakatCount.toInt().toString() : rakatCount.toString(),
                      110
                  ),
                ),

                // Минималистичная контурная кнопка сброса (не отвлекает)
                IconButton(
                  onPressed: resetAll,
                  icon: const Icon(Icons.refresh_rounded),
                  color: Colors.white30,
                  iconSize: 22,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.01),
                    padding: const EdgeInsets.all(14),
                    side: BorderSide(color: Colors.white.withOpacity(0.04), width: 1),
                  ),
                ),

                const SizedBox(height: 10),

                // Премиальные мягкие плашки предупреждений цвета затухающего янтаря
                if (showDarkWarning)
                  _buildWarningCard("Слишком темно. Камера может не работать. Используйте кнопку '+1'"),

                if (!isFrontCameraFinded)
                  _buildWarningCard("Фронтальная камера не найдена, используйте кнопку '+1'"),

                if (isDebugMode) ...[
                  const SizedBox(height: 20),
                  _buildDebugText("Яркость: ${currentBrightness.toStringAsFixed(1)}"),
                  const SizedBox(height: 5),
                  _buildDebugText("Несовпадение: ${(changePercentage * 100).toStringAsFixed(2)}%"),
                ],

                const Spacer(flex: 2),

                const SizedBox(height: 130), // Фиксированный задел под нижнюю матовую кнопку
              ],
            ),
          ),

          // Иконка жука (приглушена, чтобы не светиться в углу)
          Positioned(
            top: 45,
            right: 20,
            child: IconButton(
              icon: Icon(
                isDebugMode ? Icons.bug_report : Icons.bug_report_outlined,
                color: isDebugMode ? Colors.orangeAccent.withOpacity(0.6) : Colors.white12,
                size: 24,
              ),
              onPressed: () {
                setState(() {
                  isDebugMode = !isDebugMode;
                  if (!isDebugMode) {
                    showCameraPreview = false;
                  }
                });
              },
            ),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _buildManualButton(),
    );
  }

  // --- Новые благородные Stealth-виджеты ---

  Widget _buildStatLabel(String text, Color color, double size) => Text(
    text,
    style: TextStyle(
      fontSize: size,
      color: color,
      fontWeight: FontWeight.w400,
      letterSpacing: 4.0, // Красивый благородный разбег букв
    ),
  );

  Widget _buildStatValue(String text, double size) => Text(
    text,
    style: TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w100, // Элегантный тонкий стиль
      color: Colors.white70, // Приглушили, чтобы не слепило
    ),
  );

  Widget _buildDebugText(String text) => Text(
    text,
    style: const TextStyle(color: Colors.white30, fontSize: 13, fontFamily: 'monospace'),
  );

  // Мягкое полупрозрачное уведомление
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
      height: 130, // Сделали чуть компактнее по высоте
      alignment: Alignment.center,
      margin: const EdgeInsets.symmetric(horizontal: 8), // Красивые отступы от краев корпуса
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.01), // Почти полностью растворяется на черном экране
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
      ),
      child: const Text(
        '+1',
        style: TextStyle(color: Colors.white38, fontSize: 20/*, fontWeight: FontWeight.w300*/),
      ),
    ),
  );
}