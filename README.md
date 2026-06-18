# Prayer Assistant / Помощник намаза

<p align="center">
  <a href="#english">English Description</a> • 
  <a href="#русский">Русское описание</a>
</p>

---

## English

An innovative Android application developed with **Flutter** that helps Muslims maintain accurate counts of sujuds and rakats during prayer (Salah). Using the device's camera and advanced frame-comparison algorithms, the app tracks movement in real-time, completely hands-free.

### Key Features

* **Smart Onboarding:** Interactive introduction screens with animations guiding you on how to place the device (e.g., chest level). The navigation locks until the tutorial animation finishes.
* **Computer Vision Tracking:** Fully offline tracking based on frame geometry and pixel-change comparison. It dynamically adapts to changes in environment and lighting, remaining completely independent of clothing color.
* **Intelligent Status System:** A dynamic color-coded indicator tells you exactly when to start praying:
  * **Yellow:** Camera is initializing.
  * **Green:** Calibration successful, ready to pray.
  * **Red:** Low light or tracking issue (recommends switching to manual mode).
* **Advanced Settings:**
  * **Vibration Feedback:** Haptic confirmation when a sujud is successfully registered.
  * **Do Not Disturb Mode:** Automatically mutes all application and system-notification sounds during prayer.
  * **Reset:** Instantly restart the current session.
  * **Manual Correction (+1):** A quick-access button to manually add a sujud if the camera misses it due to poor lighting.
* **Multilingual & Full RTL Support:** Localized in **English, Russian, and Arabic**. Switching to Arabic automatically flips the entire UI layout from Right-to-Left (RTL) according to UI standards.
* **Debug Mode (Developer Tools):** Displays real-time technical telemetry (frame comparison data and pixel changes). Tapping the counter reveals a live camera feed preview over the interface.

### Tech Stack & Architecture

* **Framework:** Flutter SDK
* **Language:** Dart / Kotlin
* **Algorithm:** Frame geometry comparison and pixel-state differentials (no cloud-processing or external servers, ensuring 100% user privacy).

---

## Русский

Инновационное Android-приложение, разработанное на **Flutter**, которое помогает мусульманам безошибочно контролировать количество совершенных суджудов (земных поклонов) и ракаатов во время молитвы. Используя фронтальную камеру устройства и алгоритмы сравнения кадров, приложение отслеживает движения в реальном времени без необходимости прикасаться к экрану.

### Ключевые возможности

* **Умный онбординг:** Интерактивные приветственные экраны с анимациями, обучающие правильному расположению телефона (например, на уровне груди). Переход к следующему шагу блокируется до тех пор, пока анимация не проиграется полностью.
* **Трекинг на компьютерном зрении:** Полностью автономный алгоритм, работающий на основе сравнения геометрии кадра и изменения пикселей. Система динамически адаптируется к внешнему освещению и стабильно работает независимо от цвета одежды пользователя.
* **Интеллектуальная система статусов:** Цветовой текстовый индикатор подскажет точный момент для начала намаза:
  * **Желтый:** Идет инициализация и калибровка камеры.
  * **Зеленый:** Калибровка успешно завершена, можно приступать к молитве.
  * **Красный:** Недостаточно света или сбой трекинга (рекомендуется использовать ручную корректировку).
* **Расширенные настройки:**
  * **Виброотклик:** Тактильное подтверждение вибрацией при успешной фиксации каждого суджуда.
  * **Режим «Не беспокоить»:** Автоматическое глушение системных уведомлений и звуков приложения во время молитвы.
  * **Сброс (Reset):** Мгновенный перезапуск текущей сессии намаза.
  * **Ручная корректировка (+1):** Кнопка быстрого добавления суджуда вручную, если алгоритм пропустил поклон из-за плохих условий съемки.
* **Локализация и поддержка RTL:** Интерфейс переведен на **русский, английский и арабский** языки. При выборе арабского весь интерфейс автоматически зеркалится справа налево (RTL) по всем канонам.
* **Режим разработчика (Debug Mode):** Выводит техническую телеметрию (изменение геометрии и пикселей кадра). Нажатие на счетчик открывает прямой поток с камеры поверх интерфейса для проверки работы алгоритма.

### Технологический стек

* **Фреймворк:** Flutter SDK
* **Язык программирования:** Dart / Kotlin
* **Логика работы:** Сравнение геометрии кадров и дифференциация пиксельных состояний (все вычисления происходят локально на устройстве, обеспечивая 100% конфиденциальность).
