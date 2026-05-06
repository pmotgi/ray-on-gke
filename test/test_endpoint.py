"""Smoke test: hits /v1/models and runs a few /v1/chat/completions calls.

Usage:
  python test/test_endpoint.py --base-url http://localhost:8000
  python test/test_endpoint.py --base-url http://<EXT_IP>:8000 --stream

Requires only `requests` (already in any standard Python install or `pip install requests`).
"""
from __future__ import annotations

import argparse
import json
import sys
import time

import requests


PROMPTS = [
    "Explain Ray on GKE in two sentences.",
    "Write a Python function that returns the n-th Fibonacci number.",
    "What is the difference between LoRA and full fine-tuning?",
    "Translate to French: 'The model serves traffic on Ray Serve.'",
]


def list_models(base_url: str) -> None:
    r = requests.get(f"{base_url}/v1/models", timeout=30)
    r.raise_for_status()
    data = r.json()
    print("=== /v1/models ===")
    print(json.dumps(data, indent=2))
    print()


def chat_one(base_url: str, model: str, prompt: str, stream: bool, max_tokens: int) -> None:
    body = {
        "model": model,
        "messages": [
            {"role": "user", "content": prompt},
        ],
        "max_tokens": max_tokens,
        "temperature": 0.7,
        "stream": stream,
    }

    print(f"--- prompt: {prompt!r}")
    t0 = time.perf_counter()

    if stream:
        with requests.post(
            f"{base_url}/v1/chat/completions",
            json=body, stream=True, timeout=120,
        ) as r:
            r.raise_for_status()
            ttft: float | None = None
            content_chunks: list[str] = []
            for line in r.iter_lines():
                if not line:
                    continue
                if line.startswith(b"data: "):
                    payload = line[len(b"data: "):]
                    if payload == b"[DONE]":
                        break
                    try:
                        ev = json.loads(payload)
                    except json.JSONDecodeError:
                        continue
                    delta = ev["choices"][0].get("delta", {}).get("content", "") or ""
                    if delta:
                        if ttft is None:
                            ttft = time.perf_counter() - t0
                        content_chunks.append(delta)
            total = time.perf_counter() - t0
            text = "".join(content_chunks)
            print(f"    TTFT: {ttft:.3f}s   total: {total:.3f}s   tokens-ish: {len(text.split())}")
            print(f"    response: {text[:240]}{'…' if len(text) > 240 else ''}")
    else:
        r = requests.post(
            f"{base_url}/v1/chat/completions", json=body, timeout=120,
        )
        r.raise_for_status()
        data = r.json()
        elapsed = time.perf_counter() - t0
        msg = data["choices"][0]["message"]["content"]
        usage = data.get("usage", {})
        print(
            f"    elapsed: {elapsed:.3f}s   "
            f"prompt_tokens: {usage.get('prompt_tokens')}   "
            f"completion_tokens: {usage.get('completion_tokens')}"
        )
        print(f"    response: {msg[:240]}{'…' if len(msg) > 240 else ''}")
    print()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--base-url", required=True, help="e.g. http://localhost:8000")
    ap.add_argument("--model", default="gemma-3-1b-dolly")
    ap.add_argument("--max-tokens", type=int, default=128)
    ap.add_argument("--stream", action="store_true")
    args = ap.parse_args()

    list_models(args.base_url)

    for p in PROMPTS:
        chat_one(args.base_url, args.model, p, args.stream, args.max_tokens)

    print("=== all probes finished ===")
    return 0


if __name__ == "__main__":
    sys.exit(main())
