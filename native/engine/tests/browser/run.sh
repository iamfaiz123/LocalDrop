#!/usr/bin/env bash
# End-to-end test of the bundled browser client against a real engine.
# Requires: cargo, node + playwright (with Chromium), python3 + Pillow, ffmpeg.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
engine="$here/../.."
work="$(mktemp -d)"
trap 'kill "${pid:-0}" 2>/dev/null || true; rm -rf "$work"' EXIT

node "$here/sha256_check.js" "$engine/web/app.js"
cargo build --quiet --manifest-path "$engine/Cargo.toml" --bin localdrop-server
python3 - "$work" <<'PY'
import random, sys
from PIL import Image
for i in range(4):
    im = Image.new('RGB', (1600, 1200))
    for x in range(0, 1600, 40):
        for y in range(0, 1200, 40):
            im.paste((random.randint(0, 255), random.randint(0, 255), random.randint(0, 255)), (x, y, x + 40, y + 40))
    im.save(f'{sys.argv[1]}/photo{i}.jpg', quality=92)
PY
ffmpeg -loglevel error -y -f lavfi -i testsrc=duration=3:size=640x360:rate=25 -pix_fmt yuv420p "$work/clip.mp4"

port=18080
"$engine/target/debug/localdrop-server" --name "Manali Trip 2026" --host Aarav --port $port --data "$work/data" >"$work/server.log" 2>&1 &
pid=$!
for _ in $(seq 50); do grep -q "PIN" "$work/server.log" && break; sleep 0.1; done
pin="$(grep 'PIN' "$work/server.log" | awk '{print $3}')"
node "$here/web_e2e.js" "http://127.0.0.1:$port" "$pin" "$work"
(cd "$work" && mkdir ex && cd ex && unzip -q ../export.zip && for f in *; do cmp "$f" "../$f"; done)
echo "Browser E2E passed (ZIP contents are byte-identical to the originals)."
