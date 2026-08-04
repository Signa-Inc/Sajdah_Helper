// Web-реализация детекции лица через face-api.js (TinyFaceDetector).
// Используется ТОЛЬКО для iOS Web ветки (SajdahConfig.isiOSWeb()).
// Android-логика (AndroidFrameAnalyzer, CameraController) этот файл не затрагивает.

import 'dart:js_interop';

@JS('sajdahInitFace')
external JSPromise<JSAny?> _sajdahInitFace();

@JS('sajdahStartCamera')
external JSPromise<JSBoolean> _sajdahStartCamera();

@JS('sajdahStopCamera')
external void _sajdahStopCamera();

@JS('sajdahDetectFaceScore')
external JSPromise<JSNumber> _sajdahDetectFaceScore();

/// Загружает модель TinyFaceDetector (веса с CDN).
/// Вызывать один раз при старте iOS Web ветки.
Future<void> initFaceDetectionImpl() async {
  try {
    await _sajdahInitFace().toDart;
  } catch (e) {
    // Модель не загрузилась (нет сети / CDN недоступен) —
    // detectFaceScoreImpl будет возвращать -1, экран уйдёт в isInitializing = false
    // без краша, просто без автосчёта.
  }
}

/// Поднимает getUserMedia (front camera) и скрытый <video> элемент в JS.
/// Возвращает true, если камера успешно стартовала.
Future<bool> startFaceCameraImpl() async {
  try {
    final result = await _sajdahStartCamera().toDart;
    return result.toDart;
  } catch (e) {
    return false;
  }
}

/// Останавливает getUserMedia стрим и убирает video элемент.
/// ОБЯЗАТЕЛЬНО вызывать в dispose(), иначе камера останется активной у пользователя.
void stopFaceCameraImpl() {
  try {
    _sajdahStopCamera();
  } catch (e) {
    // no-op
  }
}

/// Возвращает score детекции лица (0..1) на текущем кадре видео,
/// либо -1.0, если лицо не найдено / модель ещё не готова.
Future<double> detectFaceScoreImpl() async {
  try {
    final result = await _sajdahDetectFaceScore().toDart;
    return result.toDartDouble;
  } catch (e) {
    return -1.0;
  }
}

@JS('sajdahDebugInfo')
external JSPromise<JSString> _sajdahDebugInfo();

/// Возвращает строку с диагностикой: готова ли модель, жив ли видеопоток,
/// его readyState/размеры. Используется только в debug-режиме.
Future<String> debugInfoImpl() async {
  try {
    final result = await _sajdahDebugInfo().toDart;
    return result.toDart;
  } catch (e) {
    return 'debugInfo error: $e';
  }
}
