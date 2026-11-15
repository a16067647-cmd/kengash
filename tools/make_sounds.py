"""Kengash uchun original tovushlar (sintez) / оригинальные звуки Kengash (синтез)."""
import sys, wave
import numpy as np

SR = 32000
OUT = sys.argv[1]
rng = np.random.default_rng(7)


def t(sec):
    return np.arange(int(SR * sec)) / SR


def save(name, x, peak=0.7):
    x = x / (np.max(np.abs(x)) + 1e-9) * peak
    fade = min(len(x), int(SR * 0.01))
    x[-fade:] *= np.linspace(1, 0, fade)
    pcm = (x * 32767).astype(np.int16)
    with wave.open(f"{OUT}/{name}.wav", "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())


def room(x, wet=0.22):
    """Yengil xona aksi (bir nechta kechikish) / лёгкая «комната» (несколько задержек)."""
    y = x.copy()
    for d, g in [(0.031, 0.5), (0.047, 0.4), (0.071, 0.3), (0.113, 0.22), (0.167, 0.15)]:
        n = int(SR * d)
        z = np.zeros_like(x); z[n:] = x[:-n] * g
        y += z * wet * 2
    return y


def glass(f, dur=1.3, bright=1.0):
    """Shisha qo‘ng‘iroqcha: noharmonik obertonlar, tez hujum, sekin so‘nish / стеклянный колокольчик."""
    tt = t(dur)
    partials = [(1.0, 1.0, 1.5), (2.756, 0.42 * bright, 0.75), (5.404, 0.2 * bright, 0.4), (8.933, 0.08 * bright, 0.22)]
    x = np.zeros_like(tt)
    for mult, amp, dec in partials:
        for det in (-0.6, 0.6):  # yengil «chorus» / лёгкий хорус
            x += amp * 0.5 * np.sin(2 * np.pi * (f * mult + det) * tt) * np.exp(-tt / dec)
    att = np.minimum(1, tt / 0.004)
    return room(x * att)


notes = [1046.5, 1174.7, 1318.5, 1568.0, 1760.0, 2093.0, 2349.3, 2637.0]  # C6 pentatonik ko‘tariluvchi
for i, f in enumerate(notes):
    save(f"chime{i}", glass(f, 1.2, bright=0.9), peak=0.55)

# Yakuniy akkord: C-E-G-B-D arpedjio + iliq past ohang / финальный аккорд + тёплый низ
dur = 2.6
tt = t(dur)
x = np.zeros_like(tt)
for k, f in enumerate([523.25, 659.25, 783.99, 987.77, 1174.66, 1567.98]):
    g = glass(f, dur - k * 0.06, bright=0.7)
    s = int(SR * k * 0.06)
    x[s:s + len(g)] += g[: len(x) - s] * (0.9 - k * 0.08)
pad = 0.35 * np.sin(2 * np.pi * 130.81 * tt) * np.minimum(1, tt / 0.25) * np.exp(-tt / 1.1)
pad += 0.18 * np.sin(2 * np.pi * 261.63 * tt) * np.minimum(1, tt / 0.3) * np.exp(-tt / 1.0)
save("intro_chord", x + pad, peak=0.6)

# Muvaffaqiyat: ikki nota yuqoriga / успех: две ноты вверх
a, b = glass(1567.98, 0.9), glass(2093.0, 0.9)
x = np.zeros(int(SR * 1.0)); x[: len(a)] += a; s = int(SR * 0.085); x[s:s + len(b)] += b[: len(x) - s] * 0.9
save("success", x, peak=0.5)

# Bosish: qisqa raqamli «tik» / нажатие: короткий цифровой «тик»
tt = t(0.035)
x = np.sin(2 * np.pi * 2200 * tt) * np.exp(-tt / 0.006) + 0.25 * rng.standard_normal(len(tt)) * np.exp(-tt / 0.002)
save("tap", x, peak=0.35)

# Yuborish: yuqoriga ko‘tariluvchi yumshoq «vush» / отправка: мягкий восходящий «вжух»
dur = 0.32; tt = t(dur)
f = 520 * (1700 / 520) ** (tt / dur)  # eksponensial ko‘tarilish
ph = 2 * np.pi * np.cumsum(f) / SR
env = np.minimum(1, tt / 0.012) * np.exp(-tt / 0.11)
tone = (np.sin(ph) + 0.3 * np.sin(2 * ph)) * env
noise = rng.standard_normal(len(tt))
noise = np.diff(noise, prepend=0)  # baland chastotali shitirlash / высокочастотный шорох
noise *= np.exp(-((tt - 0.07) / 0.05) ** 2) * 0.18
save("send", room(tone + noise, 0.12), peak=0.45)

# Qabul: yumshoq «pop» (pastga tushuvchi ikki tomchi) / приём: мягкий «поп»
dur = 0.22; tt = t(dur)
def drop(f0, f1, at, ln):
    x = np.zeros_like(tt); s = int(SR * at); tl = tt[: int(SR * ln)]
    f = f0 + (f1 - f0) * (tl / ln)
    seg = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.minimum(1, tl / 0.003) * np.exp(-tl / 0.045)
    x[s:s + len(seg)] += seg[: len(x) - s]
    return x
save("receive", room(drop(1100, 760, 0, 0.12) + 0.7 * drop(1480, 1180, 0.07, 0.12), 0.1), peak=0.45)
print("ok")
