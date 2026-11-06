#!/usr/bin/python3
"""Piper text-to-speech for Achilles, on the CPU, with a voice of your own.

piper-tts.service runs this with the Python environment that
`stiloria-models install piper` creates (piper-tts, onnxruntime and numpy).

    GET  /health   200 "ok" once the voice is loaded, 503 before
    POST /speak    raw UTF-8 text in, mono 16-bit WAV out at the voice's rate

It listens on 127.0.0.1 only. The voice is a Piper ONNX model and its
.onnx.json, which nobody downloads: you put them in
~/.local/share/piper-voices yourself (en_US-mira-medium by default). Its
playback settings (noise, rhythm and speed) come from the .onnx.json. Each
line of text is read as its own utterance, as the piper command does.
"""

import argparse
import io
import json
import os
import sys
import threading
import time
import wave
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

# onnxruntime from PyPI reports usage to Microsoft over HTTPS (seen from 1.31
# on Linux) unless this is set before it is imported.
os.environ["ORT_DISABLE_TELEMETRY"] = "1"

import onnxruntime  # noqa: E402
from piper import PiperConfig, PiperVoice  # noqa: E402

MAX_TEXT_BYTES = 64000


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
    server_version = "stiloria-piper/1"
    voice = None  # set once the voice is loaded
    lock = threading.Lock()  # one synthesis at a time

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
        if Handler.voice is None:
            return self.reply(503, b"loading")
        self.reply(200, b"ok")

    def do_POST(self):
        if self.path.split("?")[0] != "/speak":
            return self.reply(404, b"not found")
        if Handler.voice is None:
            return self.reply(503, b"loading")
        try:
            length = int(self.headers.get("Content-Length", 0))
        except ValueError:
            length = 0
        if not 0 < length <= MAX_TEXT_BYTES:
            return self.reply(400, b"send 1 to 64000 bytes of text")
        text = self.rfile.read(length).decode("utf-8", errors="replace").strip()
        started = time.monotonic()
        try:
            with Handler.lock:
                audio, seconds = speak(Handler.voice, text)
        except ValueError as error:
            return self.reply(400, str(error).encode())
        except Exception as error:  # noqa: BLE001 - report it and keep serving
            print(f"piper-tts: synthesis failed: {error}", file=sys.stderr, flush=True)
            return self.reply(500, b"synthesis failed")
        print(
            f"piper-tts: {len(text)} characters: {seconds:.1f} s of speech in {time.monotonic() - started:.2f} s",
            flush=True,
        )
        self.reply(200, audio, "audio/wav")


def main():
    data = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share")
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--port", type=int, default=17835)
    parser.add_argument("--voice", type=Path, default=data / "piper-voices/en_US-mira-medium.onnx")
    # A quarter of the CPU's threads, 2 to 8, as for Kokoro: a short reply
    # takes a fraction of a second, and most of the CPU stays with whatever
    # game is running.
    threads = min(8, max(2, (os.cpu_count() or 8) // 4))
    parser.add_argument("--threads", type=int, default=threads, help=f"CPU threads to use (default {threads})")
    args = parser.parse_args()

    # Listen first, so /health can answer 503 while the voice loads.
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    print(f"piper-tts: loading {args.voice.name}, listening on 127.0.0.1:{args.port}", flush=True)
    started = time.monotonic()
    Handler.voice = load(args.voice, args.threads)
    print(f"piper-tts: ready in {time.monotonic() - started:.1f} s", flush=True)
    threading.Event().wait()


if __name__ == "__main__":
    main()
