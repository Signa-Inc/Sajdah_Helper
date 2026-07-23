import 'dart:js_interop';

@JS('isSamplePwaStandalone')
external JSBoolean get isSamplePwaStandaloneJS;

bool get isPwaStandaloneImpl {
  try {
    return isSamplePwaStandaloneJS.toDart;
  } catch (_) {
    return false;
  }
}