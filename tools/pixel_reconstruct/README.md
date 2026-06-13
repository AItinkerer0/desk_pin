# pixel_reconstruct — 녹화 영상 → 도트복원 스프라이트 파이프라인 (2026-06-13)

Claude 앱 Clawd 모션 녹화(.mov)에서 진짜 픽셀 그리드를 복원해 desk_pin 모션 루프용
PNG 시퀀스를 만든다. 기존 tools/make_sprites.swift(원본 픽셀 보존 키잉)와 달리
논리 그리드 스냅 + 4색 양자화로 녹화 블러를 제거한다 — juggle 79프레임이 이 산출물.

## 사용법

```bash
# 1) 영상 → 전 프레임 PNG (VFR 대응: 파일명에 PTS 포함)
swift extract_frames.swift <video.mov> /tmp/clawd_motion/frames

# 2) 복원 빌드 — /tmp/clawd_motion/v4/ 에 clawd_soccer_NN.png + cody_soccer_NN.png 생성
python3 build_v4.py

# 3) cody 생성 — clawd_*.png를 읽어 cody_*.png를 새로 쓴다(리컬러+머리 위 봉우리 2개).
#    v2(2026-06-13)부터 멱등 — 깎기 없음, 재실행 안전
python3 codyfy.py <스프라이트 폴더>
```

## 새 모션에 맞춰 조정할 상수 (build_v4.py 상단)

- `CROP` — 캐릭터+공 포함 crop (px, 녹화 좌표). 영상마다 재측정 필요
- `S` — 반-그리드 도트 크기 (juggle 녹화는 3.65px; 몸통 도트는 그 2배)
- `IDLE_END / REAPPEAR / CONTENT_END` — 타임라인 절단점 (캐릭터 사라지는 구간 제거)
- `BALL_R` — 공 반경. 공 없는 모션이면 ball 패스는 자동으로 안 탄다 (흰 픽셀 클러스터 미검출)

핵심 트릭: ① 몸통은 반-그리드 스냅+팔레트 양자화, ② 공은 프레임별 흰색 중심 추적 후
disc prior로 흑/백 이진 재양자화(회전 보존), ③ 몸 안에 갇힌 투명 구멍(눈·입)은 검정 채움
(원본 앱에선 배경 비침이라 투명 위젯에 그대로 두면 바탕화면이 비친다), ④ 10fps 균일 리샘플.
