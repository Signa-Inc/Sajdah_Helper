// Тот же паттерн conditional-import, что уже используется в pwa_helper.dart:
// на вебе подключается sajdah_face_web.dart (JS-interop),
// на остальных платформах — sajdah_face_stub.dart (no-op).

import 'sajdah_face_stub.dart'
    if (dart.library.js_interop) 'sajdah_face_web.dart';

Future<void> initFaceDetection() => initFaceDetectionImpl();

Future<bool> startFaceCamera() => startFaceCameraImpl();

void stopFaceCamera() => stopFaceCameraImpl();

Future<double> detectFaceScore() => detectFaceScoreImpl();
