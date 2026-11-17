"""Android va iOS papkalarini yaratadi va sozlaydi / создаёт и настраивает папки Android и iOS.

    cd app && python3 tool/setup_platforms.py

Qayta ishga tushirish xavfsiz / повторный запуск безопасен.
"""
import os
import re
import shutil
import subprocess
from pathlib import Path

APP = Path(__file__).resolve().parent.parent
NAME = "Kengash"
NT = os.name == "nt"


def sh(*cmd):
    print("→", " ".join(cmd), flush=True)
    subprocess.run(list(cmd), cwd=APP, check=True, shell=NT)


def android():
    m = APP / "android/app/src/main/AndroidManifest.xml"
    s = m.read_text(encoding="utf-8")
    s = re.sub(r'android:label="[^"]*"', f'android:label="{NAME}"', s)
    for perm in ("INTERNET", "RECORD_AUDIO"):
        if f"android.permission.{perm}" not in s:
            s = s.replace("<application", f'<uses-permission android:name="android.permission.{perm}"/>\n    <application', 1)
    # url_launcher: Telegram (https) va qo‘ng‘iroq (tel) havolalari / ссылки https и tel
    if "<queries>" not in s:
        s = s.replace("</manifest>", """    <queries>
        <intent><action android:name="android.intent.action.VIEW"/><data android:scheme="https"/></intent>
        <intent><action android:name="android.intent.action.DIAL"/><data android:scheme="tel"/></intent>
    </queries>
</manifest>""")
    elif "android:scheme=\"https\"" not in s:
        s = s.replace("<queries>", """<queries>
        <intent><action android:name="android.intent.action.VIEW"/><data android:scheme="https"/></intent>
        <intent><action android:name="android.intent.action.DIAL"/><data android:scheme="tel"/></intent>""", 1)
    m.write_text(s, encoding="utf-8")


def android_signing():
    """Doimiy imzo: android/key.properties bo‘lsa (CI uni GitHub secret dan yozadi) — release kalit, bo‘lmasa debug.
    Har yangilanish bir xil kalit bilan imzolanadi — telefonda eski ilova ustiga o‘rnatiladi.
    Постоянная подпись: если есть android/key.properties (CI пишет его из секрета) — релизный ключ, иначе debug.
    Все обновления подписаны одним ключом — ставятся поверх старой версии."""
    g = APP / "android/app/build.gradle.kts"
    if not g.exists():
        return
    s = g.read_text(encoding="utf-8")
    if "keystoreProperties" in s:
        return
    s = "import java.io.FileInputStream\nimport java.util.Properties\n\n" + s
    s = s.replace("\nandroid {", """
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {""", 1)
    s = s.replace("    buildTypes {", """    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {""", 1)
    s = s.replace('signingConfig = signingConfigs.getByName("debug")',
                  'signingConfig = signingConfigs.getByName(if (keystorePropertiesFile.exists()) "release" else "debug")', 1)
    g.write_text(s, encoding="utf-8")


def ios():
    p = APP / "ios/Runner/Info.plist"
    s = p.read_text(encoding="utf-8")
    s = re.sub(r"(<key>CFBundleDisplayName</key>\s*<string>)[^<]*", rf"\g<1>{NAME}", s)
    extra = {
        "NSPhotoLibraryUsageDescription": "Profil surati va kanalga rasm yuborish uchun / Для фото профиля и отправки в канал",
        "NSCameraUsageDescription": "Surat, video va QR davomat uchun / Для фото, видео и QR-посещаемости",
        "NSMicrophoneUsageDescription": "Ovozli xabar uchun / Для голосовых сообщений",
        "LSApplicationQueriesSchemes": None,
    }
    add = ""
    for k, v in extra.items():
        if f"<key>{k}</key>" in s:
            continue
        if v is None:
            add += f"\t<key>{k}</key>\n\t<array>\n\t\t<string>https</string>\n\t\t<string>tg</string>\n\t\t<string>tel</string>\n\t</array>\n"
        else:
            add += f"\t<key>{k}</key>\n\t<string>{v}</string>\n"
    s = s.replace("</dict>\n</plist>", add + "</dict>\n</plist>")
    p.write_text(s, encoding="utf-8")


if __name__ == "__main__":
    flutter = shutil.which("flutter") or "flutter"
    sh(flutter, "create", "--platforms=android,ios", "--org", "uz.kengash", "--project-name", "kengash", ".")
    # `flutter create` namuna testini qo‘shadi (MyApp hisoblagich) — u bizga tegishli emas.
    # `flutter create` добавляет пример теста (счётчик MyApp) — он не наш.
    sample = APP / "test/widget_test.dart"
    if sample.exists() and "MyApp" in sample.read_text(encoding="utf-8"):
        sample.unlink()
    android()
    android_signing()
    ios()
    sh(flutter, "pub", "get")
    sh(shutil.which("dart") or "dart", "run", "flutter_launcher_icons")
    print("✓ tayyor / готово")
