#!/usr/bin/env python3
"""claude.ai Clawd 모션 → desk_pin PNG 스프라이트 시퀀스 변환.

소스 두 종류:
- Lottie(.json): assets/external/clawd_lottie/ 의 원본(코드 인라인 추출분).
  먼저 lottie_convert.py 로 투명 GIF 래스터화 후 처리.
- GIF: claude.ai/images/clawd/{core,persona}/ 에서 받은 투명 GIF는 바로 처리.

처리: 전 프레임 alpha union bbox 크롭 → LANCZOS 리사이즈(긴 변 TARGET) →
      assets/sprites/{motion}/clawd_{motion}_NN.png 로 저장.
desk_pin 위젯은 kind=.clawdLoop + config motion 필드로 이 PNG 시퀀스를 루프 렌더한다.

실행: tools/lottie-venv/bin/python tools/lottie_to_sprites.py
이후 ./build.sh 로 번들 반영.
"""
import os
import subprocess
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VENV_BIN = os.path.join(ROOT, "tools", "lottie-venv", "bin")
SPRITES = os.path.join(ROOT, "assets", "sprites")
TARGET = 480  # 긴 변 px (위젯은 더 작게 렌더 — 해상도 여유분)


def lottie_to_gif(json_path: str, gif_path: str) -> None:
    subprocess.run([os.path.join(VENV_BIN, "lottie_convert.py"), json_path, gif_path],
                   check=True, capture_output=True)


def gif_to_sprites(motion: str, gif_path: str) -> int:
    im = Image.open(gif_path)
    n = getattr(im, "n_frames", 1)
    bbox = None
    for i in range(n):
        im.seek(i)
        bb = im.convert("RGBA").split()[3].getbbox()  # alpha 채널만으로 캐릭터 영역
        if bb:
            bbox = bb if bbox is None else (
                min(bbox[0], bb[0]), min(bbox[1], bb[1]),
                max(bbox[2], bb[2]), max(bbox[3], bb[3]))
    outdir = os.path.join(SPRITES, motion)
    os.makedirs(outdir, exist_ok=True)
    for old in os.listdir(outdir):  # 같은 모션 기존 프레임만 교체 (cody_* 등 보존)
        if old.startswith(f"clawd_{motion}_") and old.endswith(".png"):
            os.remove(os.path.join(outdir, old))
    for i in range(n):
        im.seek(i)
        f = im.convert("RGBA").crop(bbox)
        f.thumbnail((TARGET, TARGET), Image.LANCZOS)
        f.save(os.path.join(outdir, f"clawd_{motion}_{i:02d}.png"))
    return n


if __name__ == "__main__":
    # Lottie 원본 → sprite (juggle 은 Soccer 무손실 교체)
    lottie_dir = os.path.join(ROOT, "assets", "external", "clawd_lottie")
    for name, motion in [("Clawd-Soccer", "juggle"), ("Clawd-Laptop", "laptop")]:
        jp = os.path.join(lottie_dir, name + ".json")
        if os.path.exists(jp):
            gp = f"/tmp/{name}.gif"
            lottie_to_gif(jp, gp)
            print(f"{motion:10s} {gif_to_sprites(motion, gp):3d} frames (Lottie {name})")
            os.remove(gp)
    print("완료 → ./build.sh 로 번들 반영")
