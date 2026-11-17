"""Kengash uchun original tovushlar (sintez, faqat numpy) / оригинальные звуки Kengash (синтез, только numpy).

Ishlatish / запуск:  python3 tools/make_sounds.py app/assets/sounds

Ovozlar «akustik» bo‘lishi uchun asboblar modellari: marimba (yog‘och), selesta (shisha qo‘ng‘iroqcha),
yumshoq pianino akkordi, pad; hammasi tabiiy xona aksi (konvolyutsion reverb) bilan.
Чтобы звучало «акустически»: модели маримбы, челесты, мягкого фортепиано и пэда + свёрточный ревербератор.

intro.wav — ochilish animatsiyasi bilan bir xil vaqtda: 8 nota nuqtalar qo‘nganda (1.066 s + i·0.182 s)
va akkord belgi tugaganda (3.042 s). Animatsiya o‘zgarsa — INTRO_* ni ham o‘zgartiring.
intro.wav совпадает с анимацией: 8 нот при посадке точек и аккорд при готовом знаке.
"""
import sys
import wave

import numpy as np

SR = 44100
OUT = sys.argv[1] if len(sys.argv) > 1 else "."
rng = np.random.default_rng(11)

INTRO_FIRST, INTRO_STEP, INTRO_CHORD, INTRO_LEN = 1.066, 0.182, 3.042, 5.0


def t(sec):
    return np.arange(int(SR * sec)) / SR


def hz(note):
    """'A4' → 440 Hz; '#' qo‘llanadi / поддерживает '#'."""
    names = {"C": -9, "D": -7, "E": -5, "F": -4, "G": -2, "A": 0, "B": 2}
    n = names[note[0]] + (1 if note[1] == "#" else 0)
    octave = int(note[-1])
    return 440.0 * 2 ** ((n + (octave - 4) * 12) / 12)


def lowpass(x, cutoff, order=2):
    """FFT orqali yumshoq past chastota filtri / мягкий ФНЧ через FFT."""
    n = len(x)
    f = np.fft.rfftfreq(n, 1 / SR)
    spec = np.fft.rfft(x) / (1 + (f / cutoff) ** (2 * order)) ** 0.5
    return np.fft.irfft(spec, n)


def highpass(x, cutoff):
    n = len(x)
    f = np.fft.rfftfreq(n, 1 / SR)
    spec = np.fft.rfft(x) * (1 - 1 / (1 + (f / cutoff) ** 4) ** 0.5)
    return np.fft.irfft(spec, n)


def env(tt, attack, decay):
    """Silliq hujum (yarim kosinus) + eksponensial so‘nish / плавная атака + экспоненциальный спад."""
    a = np.clip(tt / max(attack, 1e-4), 0, 1)
    return (0.5 - 0.5 * np.cos(np.pi * a)) * np.exp(-np.maximum(tt - attack, 0) / decay)


def place(buf, x, at, gain=1.0):
    i = int(at * SR)
    end = min(len(buf), i + len(x))
    buf[i:end] += x[: end - i] * gain


# ------------------------------------------------------------------ asboblar / инструменты
def marimba(f, dur=1.0, soft=1.0):
    """Yog‘och: asosiy + 3.93× va 9.2× obertonlar, yumshoq tayoqcha / дерево: обертоны 3.93× и 9.2×."""
    tt = t(dur)
    dec = 0.55 * (440 / f) ** 0.35
    x = np.sin(2 * np.pi * f * tt) * env(tt, 0.002, dec)
    x += 0.22 * soft * np.sin(2 * np.pi * f * 3.93 * tt) * env(tt, 0.001, dec * 0.28)
    x += 0.05 * soft * np.sin(2 * np.pi * f * 9.2 * tt) * env(tt, 0.001, dec * 0.1)
    thump = lowpass(rng.standard_normal(len(tt)) * env(tt, 0.0005, 0.004), 1800) * 0.12
    return x + thump


def celesta(f, dur=2.2, bright=1.0):
    """Shisha qo‘ng‘iroqcha (deyarli garmonik — shirin) / челеста (почти гармоническая — сладкая)."""
    tt = t(dur)
    x = np.zeros_like(tt)
    for mult, amp, dec in [(1.0, 1.0, 1.4), (2.0, 0.32 * bright, 0.7), (3.0, 0.1 * bright, 0.4),
                           (4.07, 0.06 * bright, 0.25), (6.2, 0.025 * bright, 0.12)]:
        for det in (-0.35, 0.35):  # yengil tebranish / лёгкое биение
            x += 0.5 * amp * np.sin(2 * np.pi * (f * mult + det) * tt) * env(tt, 0.003, dec)
    return x


def piano(f, dur=3.0):
    """Yumshoq «pianino» (filtrli garmonikalar) / мягкое «фортепиано» (фильтрованные гармоники)."""
    tt = t(dur)
    x = np.zeros_like(tt)
    for n in range(1, 10):
        amp = 1 / n ** 1.6
        dec = 2.2 / n ** 0.7
        inharm = n * (1 + 0.0004 * n * n)
        x += amp * np.sin(2 * np.pi * f * inharm * tt + rng.uniform(0, 6.28)) * env(tt, 0.006, dec)
    return lowpass(x, 3200)


def pad(freqs, dur, attack=1.2, release=1.0):
    """Iliq pad: bir oz farqli sozlangan arra to‘lqinlar, yumshoq filtr / тёплый пэд."""
    tt = t(dur)
    x = np.zeros_like(tt)
    for f in freqs:
        for det in (-0.12, 0.0, 0.12):
            ff = f * 2 ** (det / 12)
            ph = rng.uniform(0, 6.28)
            for n in range(1, 14):
                x += np.sin(2 * np.pi * ff * n * tt + ph * n) / n
    x = lowpass(x, 1100, order=1)
    a = np.clip(tt / attack, 0, 1) ** 2
    r = np.clip((dur - tt) / release, 0, 1)
    return x * a * r


def reverb(x, seconds=1.6, wet=0.25, tone=5000):
    """Konvolyutsion reverb (stereo): erta aks-sadolar + quyuqlashib so‘nuvchi «dum» / свёрточный ревербератор."""
    n = int(SR * seconds)
    tt = np.arange(n) / SR
    out = []
    for ch in range(2):
        ir = rng.standard_normal(n) * np.exp(-tt / (seconds / 6.9))
        ir = lowpass(ir, tone)
        for d, g in [(0.011, 0.6), (0.019, 0.45), (0.029, 0.35), (0.043, 0.3)]:
            ir[int(SR * (d + 0.003 * ch))] += g
        ir[:int(SR * 0.008)] *= np.linspace(0, 1, int(SR * 0.008))
        ir /= np.sqrt(np.sum(ir ** 2))
        m = len(x) + n
        y = np.fft.irfft(np.fft.rfft(x, m) * np.fft.rfft(ir, m), m)
        out.append(y)
    dry = np.pad(x, (0, n))
    return np.stack([dry * (1 - wet) + out[0] * wet * 3, dry * (1 - wet) + out[1] * wet * 3])


# ------------------------------------------------------------------ saqlash / сохранение
def save(name, x, peak=0.8):
    """16-bit WAV; oxiri silliq; jimlik kesiladi / конец плавный; тишина обрезается."""
    x = np.atleast_2d(x)
    level = np.max(np.abs(x), axis=0)
    last = np.nonzero(level > 0.004 * level.max())[0]  # −48 dB dan past — kesiladi
    x = x[:, : (last[-1] + 1 if len(last) else x.shape[1])]
    x = x / (np.max(np.abs(x)) + 1e-9) * peak
    fade = min(x.shape[1], int(SR * 0.02))
    x[:, -fade:] *= np.linspace(1, 0, fade)
    pcm = (x.T * 32767).astype(np.int16)
    with wave.open(f"{OUT}/{name}.wav", "wb") as w:
        w.setnchannels(x.shape[0]); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())
    print(f"{name}.wav  {x.shape[1] / SR:.2f}s  {x.shape[0]}ch")


# ------------------------------------------------------------------ tovushlar / звуки
def tap():
    """Juda qisqa yumshoq «tok» (telefon klaviaturasidek) / короткий мягкий «ток», как клавиатура телефона."""
    tt = t(0.045)
    body = np.sin(2 * np.pi * 1450 * tt) * env(tt, 0.0004, 0.0045) * 0.6
    low = np.sin(2 * np.pi * 210 * tt) * env(tt, 0.0008, 0.009) * 0.5
    click = highpass(lowpass(rng.standard_normal(len(tt)), 6000), 1200) * env(tt, 0.0002, 0.0012) * 0.5
    return lowpass(body + low + click, 7000)


def send():
    """Havoli «vush»: shovqin chastotasi ko‘tariladi + oxirida nozik yaltirash / воздушный «вжух» + блик."""
    dur = 0.34
    n = int(SR * dur)
    noise = rng.standard_normal(n)
    hop, win = 128, 1024
    out = np.zeros(n + win)
    w = np.hanning(win)
    freqs = np.fft.rfftfreq(win, 1 / SR)
    for i in range(0, n - win, hop):
        p = i / (n - win)
        centre = 450 * (4200 / 450) ** (p ** 0.8)
        width = centre * 0.55
        shape = np.exp(-0.5 * ((freqs - centre) / width) ** 2)
        frame = np.fft.irfft(np.fft.rfft(noise[i:i + win] * w) * shape, win)
        out[i:i + win] += frame * w * np.sin(np.pi * p) ** 1.5
    x = out[:n]
    x /= np.max(np.abs(x)) + 1e-9
    tt = t(dur)
    glint = np.sin(2 * np.pi * 2637 * tt) * env(np.maximum(tt - 0.2, 0), 0.004, 0.05) * (tt > 0.2) * 0.18
    return reverb(x * 0.8 + glint, seconds=0.6, wet=0.12, tone=7000)


def receive():
    """Ikki nozik shisha nota (pastdan yuqoriga) / две тонкие стеклянные ноты."""
    x = np.zeros(int(SR * 0.9))
    place(x, celesta(hz("C#6"), 0.8, bright=0.6), 0.0, 0.8)
    place(x, celesta(hz("E6"), 0.8, bright=0.6), 0.075, 1.0)
    tt = t(0.9)
    x *= np.exp(-tt / 0.28)
    return reverb(lowpass(x, 6500), seconds=0.9, wet=0.18)


def success():
    """Iliq marimba arpedjiosi A–C#–E + selesta yaltirashi / тёплое арпеджио маримбы + блеск челесты."""
    x = np.zeros(int(SR * 1.6))
    for i, nn in enumerate(["A4", "C#5", "E5"]):
        place(x, marimba(hz(nn), 1.2), i * 0.07, 0.9)
    place(x, celesta(hz("A5"), 1.4, bright=0.5), 0.2, 0.32)
    return reverb(lowpass(x, 6000), seconds=1.4, wet=0.22)


def intro():
    """Ochilish: yumshoq pad + 8 selesta notasi (nuqtalar) + iliq akkord (belgi) / интро: пэд + 8 нот + аккорд."""
    x = np.zeros(int(SR * INTRO_LEN))
    # pad: belgi yig‘ilayotganda sekin kuchayadi / пэд нарастает, пока собирается знак
    place(x, pad([hz("A2"), hz("E3"), hz("A3"), hz("C#4")], INTRO_CHORD + 0.4, attack=2.2, release=0.6), 0.25, 0.045)
    notes = ["A4", "B4", "C#5", "E5", "F#5", "A5", "B5", "C#6"]
    for i, nn in enumerate(notes):
        place(x, celesta(hz(nn), 1.6, bright=0.8), INTRO_FIRST + i * INTRO_STEP, 0.42 + 0.04 * i)
    # akkord: Amaj9 (A2 E3 A3 C#4 G#4 B4 E5) — sekin «arpedjio» bilan / аккорд с лёгким арпеджио
    for i, nn in enumerate(["A2", "E3", "A3", "C#4", "G#4", "B4", "E5"]):
        place(x, piano(hz(nn), INTRO_LEN - INTRO_CHORD), INTRO_CHORD + i * 0.012, 0.55 if i > 1 else 0.7)
    place(x, celesta(hz("A6"), 1.8, bright=0.4), INTRO_CHORD + 0.05, 0.16)
    tt = t(INTRO_LEN)
    tail = np.clip((INTRO_LEN - tt) / 1.0, 0, 1)
    return reverb(lowpass(x * tail, 7000), seconds=2.4, wet=0.3)


if __name__ == "__main__":
    save("tap", tap(), peak=0.6)
    save("send", send(), peak=0.7)
    save("receive", receive(), peak=0.7)
    save("success", success(), peak=0.75)
    save("intro", intro(), peak=0.8)
    # intro — siqilgan AAC (tez yuklanadi) / сжатый AAC (быстро грузится)
    import os
    import subprocess
    src = f"{OUT}/intro.wav"
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", src, "-c:a", "aac", "-b:a", "128k",
                    "-movflags", "+faststart", f"{OUT}/intro.m4a"], check=True)
    os.remove(src)
    print("intro.m4a", os.path.getsize(f"{OUT}/intro.m4a") // 1024, "KB")
