# Mone App — техкарты и документы

Программа для хранения и просмотра техкарт и документов кафе.

## Скачать

| Устройство | Файл |
|---|---|
| Windows | [Mone-App-Windows.zip](https://github.com/alinaibragimovna120-byte/mone-desktop-app/releases/latest/download/Mone-App-Windows.zip) |
| Android | [Mone-App-Android.apk](https://github.com/alinaibragimovna120-byte/mone-desktop-app/releases/latest/download/Mone-App-Android.apk) |
| macOS | [Mone-App-macOS.zip](https://github.com/alinaibragimovna120-byte/mone-desktop-app/releases/latest/download/Mone-App-macOS.zip) |
| Linux | [Mone-App-Linux.tar.gz](https://github.com/alinaibragimovna120-byte/mone-desktop-app/releases/latest/download/Mone-App-Linux.tar.gz) |
| iPhone / iPad | [Mone-App-iOS-unsigned.ipa](https://github.com/alinaibragimovna120-byte/mone-desktop-app/releases/latest/download/Mone-App-iOS-unsigned.ipa) (без подписи Apple) |

### iPhone / iPad без компьютера и App Store

Откройте в **Safari** на iPhone: <https://alinaibragimovna120-byte.github.io/mone-desktop-app/>

Чтобы приложение было на экране как обычное: кнопка «Поделиться» → «На экран „Домой“».
Оно откроется во весь экран, без адресной строки. Файлы хранятся на самом телефоне,
в данных Safari; если очистить историю и данные сайтов, они удалятся.

Веб-версия обновляется сама при каждой отправке изменений в `main`.

Все версии: [страница Releases](https://github.com/alinaibragimovna120-byte/mone-desktop-app/releases).
Новая сборка выкладывается автоматически при отправке метки версии: `git tag v1.0.1 && git push origin v1.0.1`.

## Возможности

- Добавление любых файлов: кнопка «Добавить файл», перетаскивание мышкой, Ctrl+V (на компьютере).
- Карточки с превью: первая страница PDF, начало таблицы Excel, текст Word, картинки.
- Просмотр прямо в программе: PDF, Word (.docx), Excel (.xlsx, .csv), PowerPoint (.pptx), RTF, TXT, картинки.
- Исправление текста в Word и ячеек в Excel с сохранением оформления; кнопка «Вернуть исходный».
- Своя картинка для карточки, переименование, поиск.
- Интерфейс подстраивается под любой экран: телефон, планшет, ноутбук, большой монитор.

## Платформы

| Платформа | Сборка |
|---|---|
| Windows | `flutter build windows` |
| Android | `flutter build apk` |
| iPhone / iPad | `flutter build ios` (только на Mac с Xcode) |
| macOS | `flutter build macos` (только на Mac) |
| Linux | `flutter build linux` (только на Linux) |
| Браузер / iPhone (PWA) | `flutter build web` |

## Разработка

```
flutter pub get
flutter run        # запуск
flutter test       # проверки, включая раскладку на разных размерах экрана
```
