#!/usr/bin/env python3
"""clawd 프레임 → Cody 프레임 생성 (리컬러 + 구름 머리 변환).

v3 (2026-06-13, Boss 2차 피드백): 기준 모양 = 집 위젯 Cody — 전체 키가 Clawd와 같아야 한다.
  - v1: 머리를 깎아 키는 맞췄지만 팔·눈을 안 내려 몸통만 낮아 보였고, 공 접촉 프레임에서
    윗단 run이 공에 쪼개져 깎이지 않은 잔재가 돌출 픽셀로 남았다.
  - v2: 봉우리를 실루엣 위에 얹어 상대 위치는 맞췄지만 키가 1도트 커졌다(Boss: "키가 커졌어").
  - v3 = 깎기(봉우리 자리 제외, 키 보존) + 모든 윗단 run 깎기(잔재 차단) + 눈 1도트 내림
    (봉우리 밑 컬럼 포함) + 떠 있는 팔·주둥이 블록 1도트 내림. Sprites.swift 공식 레이아웃
    (front(): 머리 t=1, 눈 er=2, 팔 ar=3 — 전부 Clawd보다 1도트 아래, 다리·키는 동일)과 일치.

변환 규칙 (fine px, DOT=4):
  1) 리컬러 coral→indigo. 눈/공(흑백)은 색 불변.
  2) 눈 내리기(깎기보다 먼저!) — 표면 2도트 안의 눈을 1도트 아래로, 자리는 indigo 백필.
     머리 꼭대기 줄에 박힌 눈(헤딩 프레임)까지 포함 — 깎기 후에 처리하면 공중에 뜬 검정
     픽셀로 남는다(프레임 45 실측). 눈 판별 = 흰색과 안 닿고 + 둘레 과반이 몸색. 공의 검정
     무늬는 회전 위상에 따라 흰색과 분리될 수 있지만 둘레가 투명/흰색이라 갈린다(79프레임
     실측: 눈 100% vs 무늬 0%). 내린 자리가 공(흰색/검정 테두리)과 맞닿으면 눈이 공에
     들러붙어 보이므로 그 프레임은 이동 보류 — 한두 프레임 눈이 1도트 높게 남는 쪽이 덜 틀리다.
  3) 머리 윗단 후보 = indigo top이 전역 최고점+1도트 이내인 모든 컬럼(run 전부, 쪼개진 조각 포함).
     최장 run의 12.5~37.5% / 62.5~87.5% 구간 = 봉우리 — 그 컬럼만 남기고 위 1도트 깎기.
     봉우리 윗면은 구간 최빈 top으로 평탄화(위는 깎고 아래는 투명일 때만 채움) — 머리가 기운
     프레임에서 캡 경계가 구간을 지나가며 만드는 1px 반-그리드 스파이크 제거.
  4) 떠 있는 블록(비후보 컬럼, 높이 ≤3도트, 바닥이 지면보다 2도트 이상 위) = 팔/주둥이 → 1도트 아래로.
  5) 공 픽셀(흰색 + 흰색에 닿는 검정)은 읽지도 쓰지도 않음.

clawd_*.png를 읽어 cody_*.png를 새로 쓰므로 멱등 — 재실행 안전.

usage: python3 codyfy.py <dir>   # dir 안의 clawd_*.png → cody_*.png
"""
import glob, os, sys
from collections import deque
from PIL import Image

DOT = 4  # fine px per art dot (build_v4.py 출력 기준)
CORAL = (0xD9, 0x77, 0x57)
INDIGO = (0x64, 0x70, 0xF3)
BUMP_ZONES = ((0.125, 0.375), (0.625, 0.875))  # Sprites.swift front() Cell(3,0,2,1)+Cell(7,0,2,1)

def black_components(p, W, H):
    """검정 픽셀 연결요소 목록과, 흰색(공)에 닿는 요소 표시."""
    seen = set(); comps = []
    for sy in range(H):
        for sx in range(W):
            if (sx, sy) in seen or p[sx, sy][3] != 255 or p[sx, sy][:3] != (0, 0, 0):
                continue
            comp = []; touches_white = False
            q = deque([(sx, sy)]); seen.add((sx, sy))
            while q:
                x, y = q.popleft(); comp.append((x, y))
                for dx, dy in ((1,0),(-1,0),(0,1),(0,-1)):
                    nx, ny = x+dx, y+dy
                    if not (0 <= nx < W and 0 <= ny < H): continue
                    c = p[nx, ny]
                    if c[3] == 255 and c[:3] == (255, 255, 255): touches_white = True
                    if (nx, ny) not in seen and c[3] == 255 and c[:3] == (0, 0, 0):
                        seen.add((nx, ny)); q.append((nx, ny))
            comps.append((comp, touches_white))
    return comps

def codyfy(src, dst):
    im = Image.open(src).convert("RGBA")
    W, H = im.size
    p = im.load()
    # 1) 리컬러
    for y in range(H):
        for x in range(W):
            if p[x, y][3] == 255 and p[x, y][:3] == CORAL:
                p[x, y] = INDIGO + (255,)
    ind = lambda x, y: p[x, y][3] == 255 and p[x, y][:3] == INDIGO
    white = lambda x, y: 0 <= x < W and 0 <= y < H and p[x, y][3] == 255 and p[x, y][:3] == (255, 255, 255)

    # 2) 눈 내리기 — 깎기 *전*, 단단한 원본 얼굴 위에서. (깎기 후에 하면 머리 꼭대기 줄에
    #    박힌 눈(헤딩 프레임)이 공중에 뜬 검정 픽셀로 남는다 — v3 검증에서 실측, 프레임 45.)
    comps = black_components(p, W, H)
    ball_black = {q for comp, tw in comps if tw for q in comp}   # 흰색에 닿는 검정 = 공
    otops = {}   # 컬럼별 캐릭터 표면(indigo 또는 눈 검정, 공 제외)
    for x in range(W):
        for y in range(H):
            if ind(x, y) or (p[x, y][3] == 255 and p[x, y][:3] == (0, 0, 0) and (x, y) not in ball_black):
                otops[x] = y; break
    if not otops:
        im.save(dst); return "no body"
    gminO = min(otops.values())
    candO = {x for x, t in otops.items() if t <= gminO + DOT}
    eyes_moved = eyes_held = 0
    for comp, touches_white in comps:
        if touches_white: continue   # 공의 검정 — 불가침
        cs = set(comp)
        per_ind = per_tot = 0
        for x, y in comp:
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                if (x + dx, y + dy) in cs: continue
                per_tot += 1
                if 0 <= x + dx < W and 0 <= y + dy < H and ind(x + dx, y + dy): per_ind += 1
        if per_ind * 2 < per_tot: continue   # 둘레 과반이 몸색이 아님 = 공 무늬 — 불가침
        cxs = {x for x, _ in comp}
        if not cxs <= candO: continue
        ctop = min(y for _, y in comp)
        oref = min(otops[x] for x in cxs)
        if not (oref <= ctop < oref + 2 * DOT): continue   # 표면 2도트 안의 눈만 (꼭대기 눈 포함)
        dest = [(x, y + DOT) for x, y in comp]
        if not all(y < H and (ind(x, y) or (x, y) in cs) for x, y in dest): continue
        if any(white(x + dx, y + dy) or (x + dx, y + dy) in ball_black
               for x, y in dest for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
            eyes_held += 1           # 내리면 공(흰색/검정 테두리)과 맞닿음 — 이 프레임은 보류
            continue
        for x, y in comp: p[x, y] = INDIGO + (255,)
        for x, y in dest: p[x, y] = (0, 0, 0, 255)
        eyes_moved += 1

    # 3) 머리 윗단 분석 — 눈 이동 후의 순수 indigo 프로파일 기준
    tops = {}
    gbot = 0
    for x in range(W):
        for y in range(H):
            if ind(x, y):
                if x not in tops: tops[x] = y
                gbot = max(gbot, y)
    gmin = min(tops.values())
    cand = sorted(x for x, t in tops.items() if t <= gmin + DOT)
    runs, cur = [], [cand[0]]
    for x in cand[1:]:
        if x == cur[-1] + 1: cur.append(x)
        else: runs.append(cur); cur = [x]
    runs.append(cur)
    run0 = max(runs, key=len)
    c0, w = run0[0], len(run0)
    if w < DOT * 3:
        im.save(dst); return "skip(narrow head)"
    zone_cols = set()
    for fa, fb in BUMP_ZONES:
        zone_cols.update(range(c0 + int(fa * w), c0 + int(fb * w) + 1))
    # 3a) 깎기 — 후보 전 컬럼(쪼개진 run 포함), 봉우리 컬럼 제외. indigo만 지움(눈·공 불가침)
    for x in cand:
        if x in zone_cols: continue
        for y in range(tops[x], min(tops[x] + DOT, H)):
            if ind(x, y): p[x, y] = (0, 0, 0, 0)
    # 3b) 봉우리 평탄화 — 구간별 최빈 top 레벨로 윗면 정렬 (1px 스파이크 제거)
    for fa, fb in BUMP_ZONES:
        cols = [x for x in range(c0 + int(fa * w), c0 + int(fb * w) + 1) if x in tops]
        if not cols: continue
        lv = max(set(tops[x] for x in cols), key=lambda t: sum(1 for x in cols if tops[x] == t))
        for x in cols:
            for y in range(min(tops[x], lv), lv):  # 최빈보다 높은 캡 — 깎기
                if ind(x, y): p[x, y] = (0, 0, 0, 0)
            ct = next((y for y in range(lv, H) if p[x, y][3] != 0), None)
            if ct is not None and ct > lv and ind(x, ct):  # lv까지 투명 틈 — indigo 지지면 위로만 채움
                for y in range(lv, ct):
                    p[x, y] = INDIGO + (255,)
    # 4) 팔·주둥이 내리기 — 비후보 컬럼의 떠 있는 indigo 세그먼트
    moved_cols = 0
    for x in range(W):
        if x in set(cand) or x not in tops: continue
        segs, y = [], 0
        while y < H:
            if ind(x, y):
                y0 = y
                while y < H and ind(x, y): y += 1
                segs.append((y0, y))  # [y0, y)
            else:
                y += 1
        for y0, y1 in segs:
            if y1 - y0 > 3 * DOT: continue          # 몸통 윤곽 — 불가침
            if y1 > gbot - 2 * DOT: continue        # 지면 근처(다리 등) — 불가침
            if any(p[x, yy][3] != 0 for yy in range(y1, min(y1 + DOT, H))): continue
            for yy in range(y1 - 1, y0 - 1, -1):    # 아래부터 1도트 평행이동
                p[x, yy + DOT] = p[x, yy]
            for yy in range(y0, min(y0 + DOT, y1)):
                p[x, yy] = (0, 0, 0, 0)
            moved_cols += 1
    im.save(dst)
    return (f"ok(head {c0}-{run0[-1]}, runs {len(runs)}, eyes {eyes_moved}+{eyes_held}hold, "
            f"arm cols {moved_cols})")

if __name__ == "__main__":
    d = sys.argv[1]
    srcs = sorted(glob.glob(f"{d}/clawd_*.png"))
    if not srcs:
        sys.exit(f"no clawd_*.png in {d}")
    for f in srcs:
        dst = os.path.join(d, os.path.basename(f).replace("clawd_", "cody_", 1))
        print(os.path.basename(dst), codyfy(f, dst))
