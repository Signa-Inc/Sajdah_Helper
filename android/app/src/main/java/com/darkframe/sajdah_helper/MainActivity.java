package com.darkframe.sajdah_helper;

import android.app.NotificationManager;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
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
                            notificationManager.setInterruptionFilter(3); // Включаем полную тишину (INTERRUPT_FILTER_NONE)
                            result.success(true);
                            break;

                        case "inactivateDnd":
                            notificationManager.setInterruptionFilter(1); // Включаем всё звуки (INTERRUPT_FILTER_ALL)
                            result.success(true);
                            break;

                        case "restoreDnd":
                            if (isStateSaved) {
                                notificationManager.setInterruptionFilter(initialDndState); // Возвращаем то, что сохранили
                            }
                            result.success(true);
                            break;

                        case "resetSession":
                            // Полностью сбрасываем флаг сессии при уничтожении экрана молитвы
                            isStateSaved = false;
                            result.success(true);
                            break;

                        default:
                            result.notImplemented();
                            break;
                    }
                });
    }
}