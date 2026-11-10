#!/usr/bin/env python3
# Generates a stylized puppet skin texture using the local ComfyUI API.
#
# Usage:
#   python3 scripts/generate_puppet_texture.py --output ~/Desktop/puppet_skin.png
#   python3 scripts/generate_puppet_texture.py --output ~/Desktop/puppet_skin.png \
#       --prompt "front-facing stylized puppet face texture, cyberpunk style"
#
# Requires ComfyUI to be running locally (default http://127.0.0.1:8188) and a
# checkpoint configured in Workflows/puppet_skin_texture.json.

import argparse
import json
import os
import random
import sys
import time
import urllib.parse
import urllib.request
import uuid


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate a puppet skin texture via ComfyUI")
    parser.add_argument("--output", required=True, help="Path to write the generated PNG")
    parser.add_argument("--prompt", default=None, help="Override the positive prompt")
    parser.add_argument("--seed", type=int, default=None, help="Seed for the KSampler (random if omitted)")
    parser.add_argument("--server", default="127.0.0.1:8188", help="ComfyUI server address")
    parser.add_argument("--timeout", type=int, default=600, help="Maximum seconds to wait for generation")
    args = parser.parse_args()

    workflow_path = os.path.join(os.path.dirname(__file__), "..", "Workflows", "puppet_skin_texture.json")
    with open(workflow_path, "r", encoding="utf-8") as f:
        prompt = json.load(f)

    if args.prompt:
        prompt["2"]["inputs"]["text"] = args.prompt
    if args.seed is None:
        args.seed = random.randint(0, 0xFFFFFFFF)
    prompt["5"]["inputs"]["seed"] = args.seed

    prompt_id = str(uuid.uuid4())
    queue_prompt(args.server, prompt, prompt_id)
    print(f"Queued prompt {prompt_id} with seed {args.seed}")

    image_data = poll_for_image(args.server, prompt_id, args.timeout)
    if image_data is None:
        print("Timed out waiting for image output", file=sys.stderr)
        return 1

    output_path = os.path.abspath(args.output)
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, "wb") as f:
        f.write(image_data)
    print(f"Saved puppet texture to {output_path}")
    return 0


def queue_prompt(server: str, prompt: dict, prompt_id: str) -> None:
    payload = {"prompt": prompt, "client_id": str(uuid.uuid4()), "prompt_id": prompt_id}
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        f"http://{server}/prompt",
        data=data,
        headers={"Content-Type": "application/json"},
    )
    urllib.request.urlopen(req).read()


def poll_for_image(server: str, prompt_id: str, timeout: int) -> bytes | None:
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with urllib.request.urlopen(f"http://{server}/history/{prompt_id}") as response:
                history = json.loads(response.read())
        except urllib.error.HTTPError:
            history = {}

        entry = history.get(prompt_id, {})
        outputs = entry.get("outputs", {})
        for node_id in outputs:
            node_output = outputs[node_id]
            if "images" in node_output and node_output["images"]:
                image = node_output["images"][0]
                params = urllib.parse.urlencode({
                    "filename": image["filename"],
                    "subfolder": image["subfolder"],
                    "type": image["type"],
                })
                with urllib.request.urlopen(f"http://{server}/view?{params}") as response:
                    return response.read()

        # Wait a little before polling again so we do not hammer the server.
        time.sleep(0.5)

    return None


if __name__ == "__main__":
    sys.exit(main())
