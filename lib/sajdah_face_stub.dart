// Заглушка для всех платформ, где нет dart.library.js_interop
// (Android native, iOS native, десктоп). Ничего не делает.

Future<void> initFaceDetectionImpl() async {}

Future<bool> startFaceCameraImpl() async => false;

void stopFaceCameraImpl() {}

Future<double> detectFaceScoreImpl() async => -1.0;
