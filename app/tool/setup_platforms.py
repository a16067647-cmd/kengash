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
    if "android.permission.INTERNET" not in s:
        s = s.replace("<application", '<uses-permission android:name="android.permission.INTERNET"/>\n    <application', 1)
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


def ios():
    p = APP / "ios/Runner/Info.plist"
    s = p.read_text(encoding="utf-8")
    s = re.sub(r"(<key>CFBundleDisplayName</key>\s*<string>)[^<]*", rf"\g<1>{NAME}", s)
    extra = {
        "NSPhotoLibraryUsageDescription": "Profil surati uchun / Для фото профиля",
        "NSCameraUsageDescription": "Profil surati uchun / Для фото профиля",
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
    ios()
    sh(flutter, "pub", "get")
    sh(shutil.which("dart") or "dart", "run", "flutter_launcher_icons")
    print("✓ tayyor / готово")
