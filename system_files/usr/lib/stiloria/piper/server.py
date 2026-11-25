#!/usr/bin/python3
"""Piper text-to-speech for Achilles, on the CPU, with voices of your own.

piper-tts.service runs this with the Python environment that
`stiloria-models install piper` creates (piper-tts, onnxruntime and numpy).

    GET  /health             200 "ok" once the default voice is loaded, 503 before
    POST /speak?voice=NAME   raw UTF-8 text in, mono 16-bit WAV out at the voice's
                             rate. NAME is a voice's file name without .onnx; without
                             it, en_US-mira-medium if it is there, else the first voice.

It listens on 127.0.0.1 only. A voice is a Piper ONNX model and its
.onnx.json, trained or downloaded, which nobody installs for you: put them in
~/.local/share/piper-voices. Each loads the first time it is asked for, the
last few used stay loaded, and one whose files change is loaded again. Its
playback settings (noise, rhythm and speed) come from its .onnx.json. Each
line of text is read as its own utterance, as the piper command does.
"""

import argparse
import io
import json
import os
import re
import sys
import threading
import time
import urllib.parse
import wave
from collections import OrderedDict
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

# onnxruntime from PyPI reports usage to Microsoft over HTTPS (seen from 1.31
# on Linux) unless this is set before it is imported.
os.environ["ORT_DISABLE_TELEMETRY"] = "1"

import onnxruntime  # noqa: E402
from piper import PiperConfig, PiperVoice  # noqa: E402

MAX_TEXT_BYTES = 64000
DEFAULT_VOICE = "en_US-mira-medium"
LOADED_VOICES = 3  # each holds its model in memory, about 100 MB
# A voice name goes into a file path: no slashes, no leading dot.
NAME = re.compile(r"[A-Za-z0-9_-][A-Za-z0-9_.-]*")


def load(model, threads):
    """The voice, its session limited to `threads` CPU threads (PiperVoice.load
    takes no session options)."""
    with open(f"{model}.json", encoding="utf-8") as config:
        config = PiperConfig.from_dict(json.load(config))
    options = onnxruntime.SessionOptions()
    options.intra_op_num_threads = threads
    options.inter_op_num_threads = 1
    session = onnxruntime.InferenceSession(str(model), sess_options=options, providers=["CPUExecutionProvider"])
    return PiperVoice(session=session, config=config)


class Voices:
    """The voices in a folder, loaded on first use and kept for the last few."""

    def __init__(self, folder, threads):
        self.folder = folder
        self.threads = threads
        self.loaded = OrderedDict()  # name: (files' change times, PiperVoice)

    def names(self):
        return sorted(
            model.name[: -len(".onnx")]
            for model in self.folder.glob("*.onnx")
            if NAME.fullmatch(model.name[: -len(".onnx")]) and Path(f"{model}.json").is_file()
        )

    def default(self):
        names = self.names()
        if not names:
            raise ValueError(f"no voices in {self.folder}")
        return DEFAULT_VOICE if DEFAULT_VOICE in names else names[0]

    def get(self, name):
        if not NAME.fullmatch(name) or name not in self.names():
            raise ValueError(f"no voice {name} in {self.folder}")
        model = self.folder / f"{name}.onnx"
        changed = (model.stat().st_mtime_ns, Path(f"{model}.json").stat().st_mtime_ns)
        if name in self.loaded and self.loaded[name][0] == changed:
            self.loaded.move_to_end(name)
        else:
            started = time.monotonic()
            self.loaded[name] = (changed, load(model, self.threads))
            self.loaded.move_to_end(name)
            print(f"piper-tts: loaded {name} in {time.monotonic() - started:.1f} s", flush=True)
            while len(self.loaded) > LOADED_VOICES:
                self.loaded.popitem(last=False)
        return self.loaded[name][1]


def speak(voice, text):
    buffer = io.BytesIO()
    frames = 0
    with wave.open(buffer, "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(voice.config.sample_rate)
        for line in text.splitlines():
            if line.strip():
                for chunk in voice.synthesize(line.strip()):
                    out.writeframes(chunk.audio_int16_bytes)
                    frames += len(chunk.audio_int16_bytes) // 2
    if not frames:
        raise ValueError("nothing to say")
    return buffer.getvalue(), frames / voice.config.sample_rate


class Handler(BaseHTTPRequestHandler):
    server_version = "stiloria-piper/2"
    voices = None  # set once the default voice is loaded
    lock = threading.Lock()  # one synthesis (or load) at a time

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
        if Handler.voices is None:
            return self.reply(503, b"loading")
        self.reply(200, b"ok")

    def do_POST(self):
        url = urllib.parse.urlparse(self.path)
        if url.path != "/speak":
            return self.reply(404, b"not found")
        if Handler.voices is None:
            return self.reply(503, b"loading")
        try:
            length = int(self.headers.get("Content-Length", 0))
        except ValueError:
            length = 0
        if not 0 < length <= MAX_TEXT_BYTES:
            return self.reply(400, b"send 1 to 64000 bytes of text")
        text = self.rfile.read(length).decode("utf-8", errors="replace").strip()
        name = urllib.parse.parse_qs(url.query).get("voice", [""])[0]
        started = time.monotonic()
        try:
            with Handler.lock:
                name = name or Handler.voices.default()
                audio, seconds = speak(Handler.voices.get(name), text)
        except ValueError as error:
            return self.reply(400, str(error).encode())
        except Exception as error:  # noqa: BLE001 - report it and keep serving
            print(f"piper-tts: synthesis failed: {error}", file=sys.stderr, flush=True)
            return self.reply(500, b"synthesis failed")
        print(
            f"piper-tts: {len(text)} characters as {name}: {seconds:.1f} s of speech "
            f"in {time.monotonic() - started:.2f} s",
            flush=True,
        )
        self.reply(200, audio, "audio/wav")


def main():
    data = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share")
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--port", type=int, default=17835)
    parser.add_argument("--voices", type=Path, default=data / "piper-voices", help="folder of .onnx voices")
    # A quarter of the CPU's threads, 2 to 8, as for Kokoro: a short reply
    # takes a fraction of a second, and most of the CPU stays with whatever
    # game is running.
    threads = min(8, max(2, (os.cpu_count() or 8) // 4))
    parser.add_argument("--threads", type=int, default=threads, help=f"CPU threads to use (default {threads})")
    args = parser.parse_args()

    # Listen first, so /health can answer 503 while the default voice loads.
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    print(f"piper-tts: voices in {args.voices}, listening on 127.0.0.1:{args.port}", flush=True)
    voices = Voices(args.voices, args.threads)
    voices.get(voices.default())
    Handler.voices = voices
    print("piper-tts: ready", flush=True)
    threading.Event().wait()


if __name__ == "__main__":
    main()
