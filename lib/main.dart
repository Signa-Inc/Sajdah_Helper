import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:vibration/vibration.dart';
import 'dart:async';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter/services.dart';

// --- КОНФИГ ---
class SajdahConfig {
  static const int pixelStep = 15;                      // Шаг проверки пикселей
  static const int sensitivityThreshold = 35;           // Насколько сильно должен измениться цвет пикселя
  static const double detectionThreshold = 0.85;        // % изменений для фиксации суджуда
  static const double resetThreshold = 0.25;            // % изменений для сброса состояния (поднялся)
  static const int framesToConfirm = 3;                 // Сколько кадров подряд нужно для детекции
  static const int cooldownVibrationSeconds = 2;        // Защита от дребезга (пауза между суджудами)
  //static const double minBrightessThreshold = 80.0;     // Порог "слишком темно"
}

late List<CameraDescription> _cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);   // Убираем статус-бар и панель навигации
  _cameras = await availableCameras();
  runApp(const SajdahApp());
}

class SajdahApp extends StatelessWidget {
  const SajdahApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: ThemeData.dark(),
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
  int rakatCount = 0;
  int sajdahInCurrentRakat = 0;

  List<int>? baselineFrame;
  bool isSajdaDetected = false;
  DateTime? lastSajdaTime;
  int confirmCount = 0;

  double currentBrightness = 0.0;
  double changePercentage = 0;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable(); // Экрану запрещено гаснуть
    initCamera();
  }

  Future<void> initCamera() async {
    // Выбираем фронталку (обычно индекс 1)
    controller = CameraController(_cameras[1], ResolutionPreset.low, enableAudio: false);
    await controller!.initialize();

    if (controller!.value.isInitialized) {
      await controller!.setFocusMode(FocusMode.locked);
      await controller!.setExposureMode(ExposureMode.locked);
    }

    controller!.startImageStream(analyzeFrame);
    if (mounted) setState(() {});
  }

  void analyzeFrame(CameraImage image) {
    final bytes = image.planes[0].bytes;

    double totalBrightness = 0;
    int checkStep = 50;
    int count = 0;

    for (int i = 0; i < bytes.length; i += checkStep) {
      totalBrightness += bytes[i];
      count++;
    }

    double avgBrightness = totalBrightness / count;

    final int halfSize = bytes.length ~/ 2;

    if (baselineFrame == null) {
      baselineFrame = List<int>.from(bytes.take(halfSize));
      return;
    }

    int changedPixels = 0;
    int totalChecked = 0;

    for (int i = 0; i < halfSize; i += SajdahConfig.pixelStep) {
      totalChecked++;
      final int diff = (bytes[i] - baselineFrame![i]).abs();
      if (diff > SajdahConfig.sensitivityThreshold) {
        changedPixels++;
      }
    }

    if (mounted) {
      setState(() {
        currentBrightness = avgBrightness;
        changePercentage = changedPixels / totalChecked;
      });
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
    Vibration.vibrate(duration: 100);

    setState(() {
      sajdahInCurrentRakat++;
      if (sajdahInCurrentRakat == 2) {
        rakatCount++;
        sajdahInCurrentRakat = 0;
      }
    });
  }

  Future<void> resetAll() async {
    setState(() {
      rakatCount = 0;
      sajdahInCurrentRakat = 0;
      baselineFrame = null;
      confirmCount = 0;
    });

    await controller!.setExposureMode(ExposureMode.auto);
    await Future.delayed(const Duration(milliseconds: 500));
    //await controller!.setExposureOffset(await controller!.getMaxExposureOffset());
    //await Future.delayed(const Duration(milliseconds: 500));
    await controller!.setExposureMode(ExposureMode.locked);
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildStatLabel("РАКААТЫ", Colors.grey, 24),
            _buildStatValue("$rakatCount", 120),
            const SizedBox(height: 20),
            _buildStatLabel("Поклоны: $sajdahInCurrentRakat / 2", Colors.white, 20),
            const SizedBox(height: 30),
            Text(
              "Яркость: ${currentBrightness.toStringAsFixed(1)}",
              style: TextStyle(
                color: Colors.white54,
                fontSize: 16,
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(height: 30),
            Text(
              "Несовпадение: ${(changePercentage * 100).toStringAsFixed(2)}%",
              style: TextStyle(
                color: Colors.white54,
                fontSize: 16,
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(height: 50),
            ElevatedButton(
              onPressed: resetAll,
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15)),
              child: const Text("СБРОС"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatLabel(String text, Color color, double size) =>
      Text(text, style: TextStyle(fontSize: size, color: color));

  Widget _buildStatValue(String text, double size) =>
      Text(text, style: TextStyle(fontSize: size, fontWeight: FontWeight.bold));
}