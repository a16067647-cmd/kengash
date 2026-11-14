/// Ilova sozlamalari / настройки приложения.
library;

const String kAppName = 'Kengash';

/// Server manzili. Yig‘ishda o‘zgartirish mumkin: --dart-define=SERVER=https://...
/// Адрес сервера. Можно изменить при сборке: --dart-define=SERVER=https://...
const String kServerUrl = String.fromEnvironment('SERVER', defaultValue: 'https://kengash-api.onrender.com');

/// Ochiq sayt (huquqiy sahifalar) / публичный сайт (правовые страницы).
const String kWebUrl = 'https://a16067647-cmd.github.io/kengash/';

/// Jonli fon (IDROK Motion Lab) umumiy kaliti / общий переключатель живого фона.
const bool kMotionLab = true;

/// Aloqa / контакты.
const String kContactTelegram = 'behruz_sk';
const String kContactEmail = 'behryzmamajon@gmail.com';
