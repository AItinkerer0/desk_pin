# DeskPin 🦀☁️

> **macOS 전용** · Apple Silicon 대상 · `LSMinimumSystemVersion` **26.0+** · Xcode 없이 Command Line Tools `swiftc`로 빌드

macOS 데스크탑에 상주하는 **픽셀 캐릭터 위젯(런처)** 앱. Claude Code 마스코트 **Clawd**(테라코타 게)와 Codex 짝꿍 **Cody**(인디고 구름)가 바탕화면 위·일반 창 아래에서 움직인다. 좌클릭하면 연결된 앱(`Claude.app` / `Codex.app`)을 연다. **게임이 아니라 데스크탑 위젯**이다.

## Status

- **Last reviewed:** 2026-07-17 (base `9448f05`)
- **Maturity:** 로컬 ad-hoc 서명 앱. 공증·외부 배포·자동 업데이트 없음. 이 README 작성 시 빌드·실행하지 않았다.
- **License:** 저장소에 라이선스 파일 없음 — 재사용 조건은 현재 명시되지 않음. Clawd 원본 디자인 © Anthropic.

## 위젯 (소스 `Config.swift` 기본·마이그레이션 목록)

생활 사이클 집 (셀 드로잉, `WidgetKind.clawd` / `.codex`):

- **Clawd 집 (`claude`)** · **Cody 집 (`codex`)** — 작은 방 디오라마. 단계(소스 `LifePhase`): 마당 대기(`idle`) → 책상 출근(`walkToDesk`) → 타자(`work`) → 꾸벅(`doze`) → 침대 퇴근(`walkToBed`) → 취침(`sleep`) → 기상 복귀(`walkBack`) → 다시 대기. 단계 길이는 랜덤이라 두 캐릭터 타이밍이 어긋난다. (`play` 공차기 단계는 타입으로 존재하나 기본 루프는 대기→출근 경로.)

스프라이트 루프 (번들 PNG; 저장소에는 에셋 미포함):

- **Clawd 탐정 (`detective`)** — 돋보기 수색 루프 (`detectiveLoop`)
- **Clawd 저글링 (`juggle`)** · **Cody 저글링 (`cody_juggle`)** — 공놀이/저글링 프레임 루프 (`clawdLoop` / `codexLoop`; UI 라벨은 “저글링”)
- **Clawd 모션 8종** (기본 `visible: false`, 메뉴로 켜기) — 춤 · 게걸음 · 점프 · 엿보기 · 레이싱 · 손흔들기 · 항해 · 작업(노트북)
  ids: `dancing` `crabwalk` `jumping` `lurking` `racingcar` `waving` `sailing` `laptop`

> 모션 스프라이트는 Anthropic 계열 에셋을 로컬에서 변환해 생성하며 **git에 포함되지 않는다** (`.gitignore`의 `assets/`). 빌드 시 본인 환경에서 생성·번들한다.

## 조작

| 동작 | 결과 |
|---|---|
| 좌클릭 | 연결된 앱 실행 (Claude / Codex 경로·bundle id) |
| 드래그 | 이동 (위치 자동 저장) |
| 가장자리 드래그 | 크기 조절 (정사각, 최소 32px) |
| 우클릭 / ⌃클릭 | 메뉴: 숨기기 · 크기 초기화 · 위젯 토글 · 애니메이션 · 로그인 자동 시작 · 종료 |
| 메뉴바 픽셀 게 아이콘 | 같은 계열 메뉴 (노치에 가려질 수 있음 — 우클릭이 더 확실) |

## 빌드

Xcode 불필요 — Command Line Tools의 `swiftc`로 빌드 (`resources/Info.plist` 최소 OS 26.0). **에셋 PNG가 없으면** 루프 위젯 프레임이 비거나 폴백될 수 있다(`build.sh`는 `assets/sprites/*/*.png` 복사를 시도하고 실패해도 계속).

```sh
./build.sh   # 종료 → 삭제 → swiftc Sources/*.swift → 번들 조립 → ad-hoc 서명 → /Applications/DeskPin.app
open -a DeskPin
```

(`build.sh` / `docs/DESIGN.md`에 적힌 절차. 이 리프레시에서는 **실행하지 않음**.)

## 구조

```
Sources/                 앱 본체 (AppKit, 현재 ~1202 LOC 합산)
  main.swift               엔트리
  Sprites.swift            셀 씬·캐릭터·WidgetKind / LifePhase
  Widget.swift             위젯 창·입력·모션 루프 렌더·앱 실행
  AppDelegate.swift        창 관리·메뉴바·로그인 자동 시작·절전 가드
  Config.swift             ~/Library/Application Support/DeskPin/config.json
resources/Info.plist     번들 메타 (LSUIElement, LSMinimumSystemVersion 26.0)
build.sh                 로컬 설치 스크립트
tools/                   모션 추출·키잉·스프라이트·pixel_reconstruct 등
docs/DESIGN.md           설계·적대 리뷰·실측 기록
spike/                   초기 창 스파이크
assets/                  스프라이트·참조 — gitignore (도구로 재생성)
```

## 저장 · 네트워크 · 안전

- **저장:** `~/Library/Application Support/DeskPin/config.json` (위젯 위치·크기·가시성·모션·로그인 설정). 디버그 로그 경로 코드상 `/tmp/deskpin.log`.
- **네트워크:** 위젯 동작에 원격 API 호출 없음. 클릭 시 로컬 앱 실행만.
- **서명:** ad-hoc (`codesign --sign -`). 다른 Mac으로 옮기면 Gatekeeper에 막힐 수 있음. 공증 없음.
- **개인 로컬 전용** 전제.

## 기술 메모 (설계 문서·코드 주석 기준; 이번 세션 재실측 없음)

- 창: `NSPanel` `[.borderless, .nonactivatingPanel]`, 레벨 `desktopIconWindow+1`.
- 투명 히트: `backgroundColor = .clear`, `ignoresMouseEvents = false` 명시.
- 로그인 자동 시작: `SMAppService` 우선, LaunchAgent 폴백 코드 존재.
- 전력: 창이 가려지면 틱 스킵(`occlusionState`).

---
Boss와 Claude가 2026-06-12~13 중심으로 만듦(이후 모션 위젯 확장 커밋 포함). Clawd 원본 디자인 © Anthropic.
