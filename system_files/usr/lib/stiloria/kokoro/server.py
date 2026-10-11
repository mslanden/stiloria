#!/usr/bin/python3
"""Kokoro text-to-speech for Achilles, on the CPU.

kokoro-tts.service runs this with the Python environment that
`stiloria-models install tts` creates (onnxruntime and numpy only).

    GET  /health            200 "ok" once the model is loaded, 503 before
    POST /speak?voice=NAME  raw UTF-8 text in, 24 kHz mono 16-bit WAV out.
                            The default voice is af_heart; "af_heart,af_bella"
                            blends voices.

It listens on 127.0.0.1 only. Text becomes phonemes with the system's
espeak-ng, the way Kokoro's own JavaScript port does it, and the Kokoro-82M
v1.0 ONNX export turns the phonemes into audio with onnxruntime on the CPU,
so the GPU stays free for games and the language models.
"""

import argparse
import ctypes
import io
import json
import os
import re
import sys
import threading
import time
import urllib.parse
import wave
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

# onnxruntime from PyPI reports usage to Microsoft over HTTPS (seen from 1.31
# on Linux) unless this is set before it is imported.
os.environ["ORT_DISABLE_TELEMETRY"] = "1"

import numpy as np  # noqa: E402
import onnxruntime  # noqa: E402

onnxruntime.disable_telemetry_events()

SAMPLE_RATE = 24000
DEFAULT_VOICE = "af_heart"
MAX_TOKENS = 510  # the model's context, less the padding token at each end
MAX_TEXT_BYTES = 64_000

# A Kokoro voice name starts with its language; these are espeak-ng's voices
# for them ("en" is British English).
LANGUAGES = {"a": "en-us", "b": "en", "e": "es", "f": "fr", "h": "hi", "i": "it", "p": "pt-br"}

# espeak-ng drops punctuation, but Kokoro pauses and intones by it, so text is
# phonemized between runs of these marks and the marks are put back.
PUNCTUATION = ';:,.!?¡¿—…"«»“”(){}[]'
PUNCTUATION_RUN = re.compile(rf"(\s*[{re.escape(PUNCTUATION)}]+\s*)+")

CURRENCIES = {"$": ("dollar", "dollars", "cent", "cents"), "£": ("pound", "pounds", "penny", "pence")}


class Espeak:
    """espeak-ng's text-to-IPA function. It keeps global state: hold a lock."""

    def __init__(self):
        lib = ctypes.CDLL("libespeak-ng.so.1")
        lib.espeak_Initialize.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_char_p, ctypes.c_int]
        lib.espeak_SetVoiceByName.argtypes = [ctypes.c_char_p]
        lib.espeak_TextToPhonemes.argtypes = [ctypes.POINTER(ctypes.c_char_p), ctypes.c_int, ctypes.c_int]
        lib.espeak_TextToPhonemes.restype = ctypes.c_char_p
        # Synchronous output: espeak-ng never opens an audio device.
        if lib.espeak_Initialize(2, 0, None, 0) <= 0:
            raise RuntimeError("espeak-ng failed to initialize")
        self.lib = lib
        self.language = None

    def __call__(self, text, language):
        if not text.strip():
            return ""
        if language != self.language:
            if self.lib.espeak_SetVoiceByName(language.encode()) != 0:
                raise ValueError(f"espeak-ng has no voice {language}")
            self.language = language
        pointer = ctypes.c_char_p(text.encode())
        clauses = []
        # Each call converts one clause and advances the pointer, NULL at the end.
        while pointer.value is not None:
            clause = self.lib.espeak_TextToPhonemes(ctypes.byref(pointer), 1, 0x02)  # UTF-8 in, IPA out
            if clause:
                clauses.append(clause.decode())
        # Drop the "(fr)" markers espeak-ng puts around words in another language.
        return re.sub(r"\([a-z-]+\)", "", " ".join(clauses)).strip()


def _money(match):
    one, many, cent, cents = CURRENCIES[match[1]]
    whole, fraction = int(match[2]), int(match[3])
    words = f"{whole} {one if whole == 1 else many}"
    return words + (f" and {fraction} {cent if fraction == 1 else cents}" if fraction else "")


def _time(match):
    hour, minute = match[1], int(match[2])
    if minute == 0:
        return f"{hour} o'clock"
    return f"{hour} oh {minute}" if minute < 10 else f"{hour} {minute}"


def normalize(text):
    """Spell out what espeak-ng would misread once punctuation is split off."""
    text = text.replace("‘", "'").replace("’", "'").replace("«", "“").replace("»", "”")
    text = re.sub(r"[^\S\n]+", " ", text)
    text = re.sub(r"\b(Dr|Mr|Mrs|Ms)\.(?= [A-Z])", r"\1", text)  # no full stop after a title
    text = re.sub(r"\be\.g\.", "for example", text)
    text = re.sub(r"\bi\.e\.", "that is", text)
    text = re.sub(r"(?<=\d),(?=\d{3}\b)", "", text)  # 1,000
    text = re.sub(r"([$£])(\d+)\.(\d\d)\b", _money, text)  # $4.99
    text = re.sub(r"(?<![\d:])\b(\d{1,2}):([0-5]\d)\b(?!:)", _time, text)  # 9:30
    text = re.sub(r"(\d*)\.(\d+)", lambda m: f"{m[1] or 'zero'} point {' '.join(m[2])}", text)  # 3.14
    text = re.sub(r"(?<=\d)-(?=\d)", " to ", text)  # 3-5
    return text.strip()


def phonemize(espeak, text, language):
    pieces, start = [], 0
    for mark in PUNCTUATION_RUN.finditer(text):
        pieces += [espeak(text[start : mark.start()], language), mark.group()]
        start = mark.end()
    pieces.append(espeak(text[start:], language))
    phonemes = "".join(pieces)
    if language.startswith("en"):
        # The fixes Kokoro's own JavaScript port applies to espeak-ng's English.
        phonemes = phonemes.replace("kəkˈoːɹoʊ", "kˈoʊkəɹoʊ").replace("kəkˈɔːɹəʊ", "kˈəʊkəɹəʊ")
        phonemes = phonemes.replace("ʲ", "j").replace("r", "ɹ").replace("x", "k").replace("ɬ", "l")
        phonemes = re.sub(r"(?<=[a-zɹː])(?=hˈʌndɹɪd)", " ", phonemes)
        phonemes = re.sub(r' z(?=[;:,.!?¡¿—…"«»“” ]|$)', "z", phonemes)
        if language == "en-us":
            phonemes = re.sub(r"(?<=nˈaɪn)ti(?!ː)", "di", phonemes)
    return " ".join(phonemes.split())


def batches(phonemes):
    """Split into pieces the model takes in one pass: at a sentence end if
    possible, then at a clause mark, then between words."""
    while len(phonemes) > MAX_TOKENS:
        window = phonemes[:MAX_TOKENS]
        for marks in (".!?…", ",;:—", " "):
            cut = max(window.rfind(mark) for mark in marks)
            if cut > 0:
                break
        else:
            cut = MAX_TOKENS - 1
        yield window[: cut + 1].strip()
        phonemes = phonemes[cut + 1 :].strip()
    if phonemes:
        yield phonemes


class Kokoro:
    def __init__(self, models, threads):
        options = onnxruntime.SessionOptions()
        options.intra_op_num_threads = threads
        options.inter_op_num_threads = 1
        # Without onnxruntime's memory arena, memory a long text needed is
        # given back afterwards instead of being held while the server idles.
        options.enable_cpu_mem_arena = False
        self.session = onnxruntime.InferenceSession(
            str(models / "kokoro-v1.0.onnx"), options, providers=["CPUExecutionProvider"]
        )
        # The export carries Kokoro's config, phoneme vocabulary included.
        config = json.loads(self.session.get_modelmeta().custom_metadata_map["kokoro_config"])
        self.vocab = config["vocab"]
        with np.load(models / "voices-v1.0.bin") as voices:
            self.voices = {name: voices[name] for name in voices.files}
        self.espeak = Espeak()
        self.lock = threading.Lock()
        self.speak("Ready.", DEFAULT_VOICE)  # the first run is slow: get it over with now

    def style(self, voice):
        names = [name.strip() for name in voice.split(",") if name.strip()]
        unknown = [name for name in names if name not in self.voices]
        if not names or unknown:
            raise ValueError(f"unknown voice {voice!r}")
        language = LANGUAGES.get(names[0][0])
        if not language:
            raise ValueError(f"voice {names[0]} needs a language this server doesn't support")
        return np.mean([self.voices[name] for name in names], axis=0, dtype=np.float32), language

    def speak(self, text, voice):
        """Return 16-bit samples of `text` spoken by `voice`."""
        style, language = self.style(voice)
        with self.lock:
            phonemes = phonemize(self.espeak, normalize(text), language)
            parts = []
            for piece in batches("".join(p for p in phonemes if p in self.vocab)):
                tokens = [self.vocab[p] for p in piece]
                (audio,) = self.session.run(
                    ["waveform"],
                    {
                        "input_ids": np.array([[0, *tokens, 0]], dtype=np.int64),
                        # Each voice has a style for every input length.
                        "style": style[len(tokens) - 1],
                        "speed": np.array([1.0], dtype=np.float32),
                    },
                )
                parts.append(audio)
        if not parts:
            raise ValueError("nothing to say")
        return (np.clip(np.concatenate(parts), -1.0, 1.0) * 32767).astype("<i2")


def wav(samples):
    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(SAMPLE_RATE)
        out.writeframes(samples.tobytes())
    return buffer.getvalue()


class Handler(BaseHTTPRequestHandler):
    server_version = "stiloria-kokoro/1"
    kokoro = None  # set once the model is loaded

    def log_message(self, *args):  # requests are logged below, without their text
        pass

    def reply(self, status, body, content_type="text/plain; charset=utf-8"):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path != "/health":
            return self.reply(404, b"not found")
        if Handler.kokoro is None:
            return self.reply(503, b"loading")
        self.reply(200, b"ok")

    def do_POST(self):
        url = urllib.parse.urlparse(self.path)
        if url.path != "/speak":
            return self.reply(404, b"not found")
        if Handler.kokoro is None:
            return self.reply(503, b"loading")
        voice = urllib.parse.parse_qs(url.query).get("voice", [DEFAULT_VOICE])[0]
        try:
            length = int(self.headers.get("Content-Length", 0))
        except ValueError:
            length = 0
        if not 0 < length <= MAX_TEXT_BYTES:
            return self.reply(400, b"send 1 to 64000 bytes of text")
        text = self.rfile.read(length).decode("utf-8", errors="replace").strip()
        started = time.monotonic()
        try:
            samples = Handler.kokoro.speak(text, voice)
        except ValueError as error:
            return self.reply(400, str(error).encode())
        except Exception as error:  # noqa: BLE001 - report it and keep serving
            print(f"kokoro-tts: synthesis failed: {error}", file=sys.stderr, flush=True)
            return self.reply(500, b"synthesis failed")
        print(
            f"kokoro-tts: {len(text)} characters as {voice}: {len(samples) / SAMPLE_RATE:.1f} s of speech "
            f"in {time.monotonic() - started:.2f} s",
            flush=True,
        )
        self.reply(200, wav(samples), "audio/wav")


def main():
    data = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share")
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--port", type=int, default=17833)
    parser.add_argument("--models", type=Path, default=data / "stiloria/models")
    # A quarter of the CPU's threads, 2 to 8: a short reply takes a fraction
    # of a second, and most of the CPU stays with whatever game is running.
    threads = min(8, max(2, (os.cpu_count() or 8) // 4))
    parser.add_argument("--threads", type=int, default=threads, help=f"CPU threads to use (default {threads})")
    args = parser.parse_args()

    # Listen first, so /health can answer 503 while the model loads.
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    print(f"kokoro-tts: loading the model, listening on 127.0.0.1:{args.port}", flush=True)
    started = time.monotonic()
    Handler.kokoro = Kokoro(args.models, args.threads)
    print(f"kokoro-tts: ready in {time.monotonic() - started:.1f} s", flush=True)
    threading.Event().wait()


if __name__ == "__main__":
    main()
