package com.darkframe.sajdah_helper;

import android.app.NotificationManager;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.os.VibrationEffect;
import android.os.Vibrator;
import android.provider.Settings;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterActivity {
    private static final String CHANNEL = "com.darkframe.sajdah_helper/dnd";

    // Переменные сессии
    private int initialDndState = 1;
    private boolean isStateSaved = false;

    @Override
    public void configureFlutterEngine(FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);

        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL)
                .setMethodCallHandler((call, result) -> {
                    NotificationManager notificationManager = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);

                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M || notificationManager == null) {
                        result.success(false);
                        return;
                    }

                    // Проверяем системное разрешение на управление режимом "Не беспокоить"
                    if (!notificationManager.isNotificationPolicyAccessGranted()) {
                        Intent intent = new Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS);
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                        startActivity(intent);
                        result.error("PERMISSION_DENIED", "Режиму DND требуется разрешение", null);
                        return;
                    }

                    // Разделяем логику на атомарные методы
                    switch (call.method) {
                        case "saveInitialState":
                            // Запоминаем состояние ОДИН раз за сессию, чтобы случайно не перезаписать его тишиной
                            if (!isStateSaved) {
                                initialDndState = notificationManager.getCurrentInterruptionFilter();
                                isStateSaved = true;
                            }
                            result.success(true);
                            break;

                        case "activateDnd":
                            // ЗАЩИТА: Если состояние еще не сохранено (например, при возврате из бэкграунда),
                            // делаем слепок прямо сейчас, ПЕРЕД тем как включить тишину.
                            if (!isStateSaved) {
                                initialDndState = notificationManager.getCurrentInterruptionFilter();
                                isStateSaved = true;
                            }
                            notificationManager.setInterruptionFilter(3); // Включаем полную тишину
                            result.success(true);
                            break;

                        case "inactivateDnd":
                            notificationManager.setInterruptionFilter(1); // Включаем все звуки (INTERRUPT_FILTER_ALL)
                            result.success(true);
                            break;

                        case "restoreDnd":
                            if (isStateSaved) {
                                notificationManager.setInterruptionFilter(initialDndState);
                                isStateSaved = false; // Сбрасываем флаг сессии
                            }
                            result.success(true);
                            break;

                        case "resetSession":
                            // Полностью сбрасываем флаг сессии при уничтожении экрана молитвы
                            isStateSaved = false;
                            result.success(true);
                            break;

                        case "vibrateWithDndBypassInsideNative":
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && notificationManager != null) {
                                // 1. Запоминаем текущий фильтр (на случай, если там не 3, а что-то другое)
                                int currentFilter = notificationManager.getCurrentInterruptionFilter();

                                // 2. Мгновенно открываем шлюз для звуков/вибрации (INTERRUPT_FILTER_ALL)
                                notificationManager.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_ALL);

                                // 3. Запускаем вибрацию стандартным способом
                                Vibrator v = (Vibrator) getApplicationContext().getSystemService(Context.VIBRATOR_SERVICE);
                                if (v != null && v.hasVibrator()) {
                                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                        v.vibrate(VibrationEffect.createOneShot(100, VibrationEffect.DEFAULT_AMPLITUDE));
                                    } else {
                                        v.vibrate(100);
                                    }
                                }

                                // 4. Возвращаем DND обратно без каких-либо задержек
                                notificationManager.setInterruptionFilter(currentFilter);

                                result.success(true);
                            } else {
                                result.success(false);
                            }
                            break;

                        default:
                            result.notImplemented();
                            break;
                    }
                });
    }

    @Override
    protected void onDestroy() {
        restoreDndNative();
        super.onDestroy();
    }

    @Override
    protected void onStop() {
        restoreDndNative();
        super.onStop();
    }
    private void restoreDndNative() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && isStateSaved) {
            NotificationManager notificationManager = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
            if (notificationManager != null && notificationManager.isNotificationPolicyAccessGranted()) {
                notificationManager.setInterruptionFilter(initialDndState);
                isStateSaved = false; // Очищаем сессию
            }
        }
    }
}