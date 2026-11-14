"""Jonli yangilanishlar (WebSocket) / живые обновления (WebSocket).

Bitta server nusxasi — ulanishlar xotirada. Hodisa faqat kanal a’zolariga yuboriladi.
Один экземпляр сервера — соединения в памяти. Событие отправляется только участникам канала.
"""
import asyncio
import json
import threading

_lock = threading.Lock()
_conns = {}  # user_id -> set[(websocket, loop)]


def add(uid, ws, loop):
    with _lock:
        _conns.setdefault(uid, set()).add((ws, loop))


def remove(uid, ws, loop):
    with _lock:
        s = _conns.get(uid)
        if s:
            s.discard((ws, loop))
            if not s:
                _conns.pop(uid, None)


def online(uid):
    with _lock:
        return uid in _conns


def send(user_ids, event):
    """Istalgan oqimdan chaqirish mumkin / можно вызывать из любого потока."""
    text = json.dumps(event, ensure_ascii=False)
    with _lock:
        targets = [(ws, loop) for u in set(user_ids) for (ws, loop) in _conns.get(u, ())]
    for ws, loop in targets:
        try:
            asyncio.run_coroutine_threadsafe(ws.send_text(text), loop)
        except Exception:
            pass
