#!/bin/bash
# Verifies that every animation frame exists and can be loaded before building.
set -u
cd "$(dirname "$0")"

base_frames=(
  back belly blink crouch front groom hang1 hang2 happywalk jump land lie loaf
  loafclosed lookup peek peekeyes peektilt play run0 run1 run2 run3 sit sitt1
  sitt2 sitt3 sleep stand startle stretch tilt walk0 walk1 walk2 walk3 wash yawn
)
siamese_extra_frames=(croucht1 croucht2 croucht3)
failed=0

dimensions() {
  local path="$1"
  local width height
  width="$(sips -g pixelWidth "$path" 2>/dev/null | awk '/pixelWidth:/ { print $2 }')"
  height="$(sips -g pixelHeight "$path" 2>/dev/null | awk '/pixelHeight:/ { print $2 }')"
  printf '%sx%s' "$width" "$height"
}

validate_file() {
  local path="$1"
  local properties
  if [ ! -f "$path" ]; then
    echo "❌ Missing sprite: $path"
    failed=1
    return
  fi
  properties="$(sips -g format -g pixelWidth -g pixelHeight -g hasAlpha "$path" 2>/dev/null || true)"
  if ! grep -q 'format: png' <<<"$properties"; then
    echo "❌ Not a readable PNG: $path"
    failed=1
  fi
  if ! grep -q 'hasAlpha: yes' <<<"$properties"; then
    echo "❌ Sprite has no alpha channel: $path"
    failed=1
  fi
  if grep -Eq 'pixel(Width|Height): 0' <<<"$properties"; then
    echo "❌ Sprite has an empty canvas: $path"
    failed=1
  fi
}

for breed in ragdoll norwegian siamese; do
  for frame in "${base_frames[@]}"; do
    validate_file "sprites/$breed/$frame.png"
  done
done
for frame in "${siamese_extra_frames[@]}"; do
  validate_file "sprites/siamese/$frame.png"
done

# Norwegian Forest sprites share the Ragdoll anchor table in Mochi.swift, so
# their canvases must remain exactly the same size frame by frame.
for frame in "${base_frames[@]}"; do
  ragdoll_size="$(dimensions "sprites/ragdoll/$frame.png")"
  norwegian_size="$(dimensions "sprites/norwegian/$frame.png")"
  if [ "$ragdoll_size" != "$norwegian_size" ]; then
    echo "❌ Canvas mismatch for $frame: ragdoll=$ragdoll_size norwegian=$norwegian_size"
    failed=1
  fi
done

if [ "$failed" -ne 0 ]; then
  exit 1
fi

echo "✅ Validated 117 transparent PNG sprites across 3 breeds"
