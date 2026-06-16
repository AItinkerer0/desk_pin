# DeskPin 🦀☁️

> **macOS 전용** · Apple Silicon · macOS 26+ · Xcode 불필요(`swiftc`만으로 빌드)

macOS 데스크탑에 상주하는 픽셀 캐릭터 위젯. Claude Code의 마스코트 **Clawd**(테라코타 게)와 Codex의 짝꿍 **Cody**(인디고 구름)가 바탕화면 위, 모든 창 아래에서 살아간다. 클릭하면 해당 앱이 실행된다.

## 위젯

- **Clawd 집 / Cody 집** — 작은 집 디오라마 안에서 생활 사이클을 돈다: 마당에서 쉬다 → 책상으로 출근 → 타자 → 꾸벅 졸기 → 침대로 → 취침(zzz) → 기상. 단계 길이는 랜덤이라 두 캐릭터의 하루가 서로 어긋난다.
- **Clawd 탐정** — 돋보기 수색 모션 루프.
- **Clawd 저글링** — 공놀이 모션 (무손실 벡터 기반).
- **Clawd 모션 8종** (기본 숨김, 우클릭 메뉴로 켜기) — 춤 · 게걸음 · 점프 · 엿보기 · 레이싱 · 손흔들기 · 항해 · 작업(노트북).

> 모션 스프라이트는 Anthropic 에셋을 로컬에서 변환해 생성하며 저장소에 포함되지 않는다(`.gitignore`). 빌드 시 본인 환경에서 생성·번들된다. Clawd 원본 디자인 © Anthropic.

## 조작

| 동작 | 결과 |
|---|---|
| 좌클릭 | 연결된 앱 실행 (Claude / Codex) |
| 드래그 | 이동 (위치 자동 저장) |
| 가장자리 드래그 | 크기 조절 (정사각, 최소 32px) |
| 우클릭 / ⌃클릭 | 메뉴: 숨기기 · 크기 초기화 · 위젯 토글 · 애니메이션 · 로그인 자동 시작 · 종료 |
| 메뉴바 픽셀 게 아이콘 | 같은 메뉴 (노치에 가려질 수 있음 — 우클릭이 더 확실) |

## 빌드

Xcode 불필요 — Command Line Tools의 swiftc만으로 빌드된다 (macOS 26+).

```sh
./build.sh   # 종료 → 삭제 → 컴파일·번들 조립 → ad-hoc 서명 → /Applications/DeskPin.app
open -a DeskPin
```

## 구조

```
Sources/          앱 본체 (AppKit, ~700줄)
  Sprites.swift     셀 기반 씬·캐릭터 렌더 (방·생활 사이클 포즈)
  Widget.swift      위젯 창·입력(클릭/드래그/리사이즈)·모션 루프 렌더
  AppDelegate.swift 창 관리·메뉴바·로그인 자동 시작·절전 가드
  Config.swift      ~/Library/Application Support/DeskPin/config.json 영속
tools/            모션 추출 파이프라인 (swiftc 단일 파일들)
  extract_frames.swift  mov/gif → 프레임 PNG
  key_motion.swift      공식 무손실 에셋 → 키잉·크롭·인디고 리컬러
  make_sprites.swift    화면 녹화 → 격자 양자화 재건축 (위상 보정·눈 정규화·투톤)
docs/DESIGN.md    설계·적대 리뷰·실측 기록 전체
assets/           스프라이트·참조 프레임 — Anthropic 추출물이라 gitignore (도구로 재생성)
```

## 기술 메모 (macOS 26.4 실측)

- 창은 `NSPanel [.borderless, .nonactivatingPanel]`, 레벨 `desktopIconWindow+1` — 바탕화면 아이콘 위·모든 창 아래에서 클릭 수신 확인.
- 투명 영역 클릭은 `ignoresMouseEvents = false` 명시(tri-state)로 해결 — 알파 백킹은 0.01에서도 회색 상자로 비침.
- 로그인 자동 시작은 `SMAppService` — ad-hoc 서명에서도 동작 확인 (LaunchAgent 폴백 내장).
- 개인 로컬 전용: ad-hoc 서명이라 다른 맥으로 옮기면 Gatekeeper에 차단된다.

---
Boss와 Claude가 2026-06-12~13 밤샘으로 만듦. Clawd 원본 디자인 © Anthropic.
