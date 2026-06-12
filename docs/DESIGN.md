# DeskPin — 데스크탑 플로팅 런처 위젯 설계 v1

- 날짜: 2026-06-12
- 상태: **결정 확정(D1~D5) — Phase 0(spike) 진행** (2026-06-12)
- 검토: 4렌즈 적대적 검증 workflow `wf_6949bde5-870` 반영 (window-behavior / input-handling / packaging-signing / persistence-launch). wrong 판정 2건 수정, uncertain 3건은 Spike(§6)로 이관.
- 앱 이름: **DeskPin 확정** (Boss, 2026-06-12). 폴더 `desk_pin`, bundle id `local.jinwoo.deskpin`.

## 1. 요구사항 (Boss 원문 기준)

| # | 원문 | 해석 |
|---|---|---|
| R1 | "크기는 1x1부터 자유롭게 조절가능하게" | 가장자리 드래그 자유 리사이즈, 최소 32px, 정사각 고정(추천안, 결정점 D2) |
| R2 | "위젯에서 보이는건 클로드의 캐릭터 … 얘처럼"(Clawd 스크린샷) | Clawd 픽셀 캐릭터 — 공식 에셋(`assets/ref/clawd_frame.png`) 재구성 |
| R3 | "클릭하면 클로드 코드가 켜지게" | 좌클릭 1회 = `/Applications/Claude.app` 실행 |
| R4 | "코덱스는 코덱스 앱 모양" → (변경) "그림체랑 느낌이 비슷해야디" | Codex 위젯 = Clawd와 같은 골격의 픽셀 캐릭터 (시안 승인 대기, 결정점 D3) |
| R5 | 위젯 갤러리 부재 보완 (대화 합의) | 메뉴바 토글·위젯 추가·로그인 자동 시작(P2)·종료 |

## 2. 환경 (실측 2026-06-12)

- macOS 26.4 (25E246), Apple Silicon (arm64), MacBook Air
- Xcode 없음 — CLT swiftc 6.3.2 (`Target: arm64-apple-macosx26.0`)만으로 빌드 (검토 실측 confirmed)
- 대상: `/Applications/Claude.app`, `/Applications/Codex.app` (존재 실측)
- 개인 로컬 전용, ad-hoc 서명. **외부 배포 금지 전제** — zip/AirDrop 경유 시 quarantine이 붙어 차단됨 (검토 confirmed)

## 3. 아키텍처

단일 LSUIElement 앱:

```
main.swift            — top-level 부트스트랩 (NSApplication.shared + delegate + run)
AppDelegate           — 시동, config 로드, 화면 재구성·wake 노티 방어
StatusItemController  — 메뉴바 아이콘 + NSMenu (위젯 토글 체크 / 위젯 추가… / 로그인 자동 시작(P2) / 종료)
WidgetPanel (×N)      — NSPanel 서브클래스, 위젯 창 1개 = 런처 1개
WidgetView            — 이미지 표시 + 입력 처리 (클릭/드래그/리사이즈/우클릭)
ConfigStore           — ~/Library/Application Support/<AppName>/config.json
```

## 4. 핵심 기술 결정 — 검토 반영 최종안

검토 판정 표기: ✅ confirmed / 🔧 wrong→수정됨 / ⚠️ uncertain→Spike에서 실측.

- **W1. 창 종류** 🔧 — ~~NSWindow~~ → **NSPanel 서브클래스 + styleMask [.borderless, .nonactivatingPanel]**. 근거: mouse 이벤트는 key 상태와 무관하게 전달되므로 canBecomeKey=true는 불필요하고, 오히려 클릭마다 사용자 앱 포커스를 뺏는 부작용만 있음. .nonactivatingPanel이 "클릭해도 다른 앱 포커스 비탈취"의 정석. **canBecomeKey 오버라이드 금지(기본 false 유지)**, `hidesOnDeactivate = false` 필수(기본 true면 앱 비활성 시 위젯 소멸), `isReleasedWhenClosed = false` 명시(숨김 토글 크래시 방지), 표시는 `orderFrontRegardless()`.
- **W2. 투명창 구성** ✅ — isOpaque=false, backgroundColor=.clear, hasShadow=false (Übersicht/Plash와 동일 레시피).
- **W3. 히트영역** 🔧 (설계가 놓친 wrong) — non-opaque 창은 **픽셀 alpha 기반 per-pixel hit testing**: 투명 픽셀 클릭은 창을 통과해 배경화면으로 가고, Sonoma+ 기본설정 "배경화면 클릭해 데스크탑 보기"를 오발동시킴(전 창이 치워지는 최악 UX). 픽셀 캐릭터는 투명 영역이 넓어 치명적. **fix: contentView 전체에 alpha ≈0.01~0.05의 layer 배경을 깔아 사각형 전체를 히트영역화.** 비문서 우회(ignoresMouseEvents tri-state)에 의존하지 않음.
- **W4. 레벨** ⚠️ — 1차: `NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)` (아이콘 위·전 일반창 아래). z-order는 confirmed이나 **이 레벨에서의 클릭 수신 실측 선례를 못 찾음** + macOS 26.3 RC borderless 회귀(26.4 beta 재발 보고, Apple Forums 814798) 리스크. **폴백 사다리: ① desktopIcon+1 → ② normalWindow−1 (Übersicht interactive 모드의 검증된 레벨, 목표 동일 충족) → ③ Plash식 클릭 순간만 레벨 승격.** Spike S1에서 결정.
- **W5. collectionBehavior** ✅ — `[.canJoinAllSpaces, .stationary, .ignoresCycle]` (정석 조합, 문서·선례 confirmed). 기대 동작 명문화: Show Desktop 제스처에서 잔존 / **Mission Control 오버뷰 중에는 시스템 위젯처럼 일시 비표시가 정상** / fullscreen Space에서는 안 보임(의도 일치). "배경화면 클릭 reveal"·Stage Manager 거동은 문서 보장 밖 ⚠️ → Spike S2.
- **I1. 첫 클릭** ✅ — WidgetView에서 `acceptsFirstMouse(for:) = true` (비활성 상태 첫 클릭 즉시 동작).
- **I2. 클릭/드래그 구분** ✅(+수정) — mouseDown 좌표 기억, **스크린 좌표 기준** 이동량 ≤ 5px에서 mouseUp이면 클릭=실행. 초과 시 보관해 둔 mouseDown 이벤트로 **`window.performDrag(with:)`** 위임(Spaces 가장자리·지터 처리 무료). **단 performDrag는 mouseUp이 안 올 수 있음(문서 명시) → 위치 저장은 mouseUp이 아니라 `windowDidMove` delegate + debounce**(P1). 임계값은 트랙패드 실사용 후 조정 여지(4→5~8px).
- **I3. 리사이즈** ⚠️ — 우선순위 역전(검토 제안): **1차 시도 = styleMask에 .resizable 추가 + `contentAspectRatio = 1:1` + `minSize = 32×32` + canBecomeKey=false 명시** → 시스템이 가장자리 리사이즈·커서·정사각·최소크기를 전부 처리(수동 코드 0줄). 단 .resizable은 canBecomeKey 기본값을 true로 만들므로 false 오버라이드 필수, 26.x styleMask 회귀와 겹침 → Spike S3 실측. **실패 시 수동 폴백**: NSTrackingArea `[.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect]` + mouseMoved에서 `NSCursor.frameResize(position:directions:)`(macOS 15+ 공개 API) 직접 set. **`.cursorUpdate`+`.activeAlways` 조합 금지(문서상 이벤트 미발송)**, addCursorRect도 비-key borderless에서 무력 보고 있음. 밴드 폭 `max(6, size*0.15)` 또는 모서리 4곳 한정 — 최소 32px에서 클릭 타깃 잠식 방지.
- **I4. 우클릭 메뉴** ✅(+수정) — rightMouseDown 수동 처리 대신 **`view.menu` 할당**(우클릭+control-클릭 자동 커버). 항목: 이 위젯 숨기기 / 크기 초기화.
- **L1. 실행** ✅ — `NSWorkspace.shared.openApplication(at:configuration:)`, 기본값 activates=true(문서 confirmed: 실행 중이면 앞으로 가져옴) + `addsToRecentItems=false`. completionHandler error 로깅 + 실패 시 `NSRunningApplication.activate()` 폴백 1줄. config의 appPath 실패 시 **bundleIdentifier로 `urlForApplication(withBundleIdentifier:)` 재해석**(앱 이동·재설치 복구).
- **L2. 아이콘/이미지** ✅ — 기본: `NSWorkspace.shared.icon(forFile:)` — 반환 NSImage의 size가 32pt로 박혀 있어 그대로 쓰면 흐림(Forums 실사례). **fix: icon.size = 타깃 pt로 재설정 + imageScaling .scaleProportionallyUpOrDown, 흐리면 representations에서 최대 pixelsWide rep 재구성. 리사이즈 종료마다 size 갱신.** 커스텀 이미지(`imagePath`, 이번 픽셀 캐릭터): PNG를 1024px급으로 사전 렌더해 두고 표시는 동일 경로 — 픽셀 아트 보간 흐림 방지를 위해 표시 레이어에서 `magnificationFilter = nearest` 적용(축소는 무관).
- **M1. 메뉴바** ✅ — NSStatusItem(strong 참조 유지 — 지역변수면 즉시 소멸), LSUIElement=true만으로 launch 시 .accessory 실측 확인 → `setActivationPolicy` 호출 불필요.
- **M2. 위젯 추가(P2)** ✅(+수정) — NSOpenPanel 전 `NSApp.activate(ignoringOtherApps: true)` 필수(accessory 앱에서 패널이 뒤에 깔리는 표준 함정), `allowedContentTypes = [.applicationBundle]`.
- **P1. 영속** ✅ — Application Support JSON 지지(UserDefaults 대비 디버깅·diff·cfprefsd 캐시 함정 회피). 보완: **atomic write, schemaVersion 필드, corrupt 시 .bak 격리 후 기본값(크래시 금지)**, 항목에 appPath + bundleIdentifier 병행 저장. 저장 트리거: windowDidMove(debounce)·리사이즈 종료·표시 토글·추가/삭제·applicationWillTerminate. 화면 밖 좌표는 **영속값을 덮지 말고 표시만 클램프**(외장 모니터 늦은 인식 시 데이터 파괴 방지).
- **P2. 로그인 자동 시작** ⚠️ (P2 단계) — `SMAppService.mainApp.register()`의 ad-hoc 서명 동작은 **공식 보장 없음**(문서에 서명 요건 미명시). 구현 시 register() 직후 `status == .enabled` 런타임 확인 → 아니면 LaunchAgent plist 폴백(`RunAtLoad=true`, **KeepAlive 금지**(종료 시 무한 재기동), `LimitLoadToSessionType=Aqua`). **이중 등록 방지: 사용 중 메커니즘을 config에 단일 기록, 전환 시 이전 것 해제.** ad-hoc CDHash는 빌드마다 변함 → 재빌드 후 status 재확인을 빌드 체크리스트에 포함.
- **B1. 빌드** ✅ (전부 이 머신 실측) — `swiftc -O Sources/*.swift` + 수동 .app 조립 + `codesign --force --sign -` + `codesign --verify --strict`. 엔트리포인트는 **Sources/main.swift의 top-level 코드로 고정**(다른 파일에 top-level 두면 link 에러, @main은 -parse-as-library 필요 — 실측). Swift 런타임 OS 내장(otool 실측) — 동봉 불필요. quarantine 없음 실측 → Gatekeeper 비차단. **`spctl --assess`의 "rejected"는 notarization 평가일 뿐 실행과 무관 — 빌드 검증에 넣지 말 것.**
- **B2. Info.plist 최소셋** ✅ (변형 번들 실측) — 기능 필수: `CFBundleIdentifier`(reverse-DNS — 없으면 UserDefaults·SMAppService·LS 등록이 조용히 비정상, 실측 bundleId=nil), `LSUIElement=true`. 명시 권장: CFBundleExecutable, CFBundleName, CFBundlePackageType=APPL. NSHighResolutionCapable: macOS 26에서 부재여도 windowScale=2.0 실측 — 무해하므로 레거시 호환용으로 포함.
- **B3. 설치 경로 고정** ✅ — 산출물은 `/Applications/<AppName>.app` 단일 고정 경로. 빌드 스크립트 4단계: 기존 인스턴스 종료 → 기존 .app 삭제 → 조립·서명 → 검증. (여러 사본 방치 시 LS database 오염 → SMAppService error 78류 비결정 실패, Apple DTS 명시 단골 문제. 실행 중 in-place 덮어쓰기는 signature invalidation으로 Killed:9.)
- **D1. 방어 코드(MVP 포함)** — `NSApplication.didChangeScreenParametersNotification` + NSWorkspace wake 노티에서 level·collectionBehavior·frame 재설정 (Übersicht #522류 sleep 복귀 유실 대응). 숨김/표시는 `orderOut(nil)` / `orderFrontRegardless()` 쌍.

## 5. 캐릭터·이미지 파이프라인

- 원본: `assets/ref/clawd_frame.png` (Claude.app 번들 `ion-dist/images/install-hub/clawd-magnifier.gif` 첫 프레임 — 공식 에셋, 개인 로컬 사용).
- 그리드 분석(원본 실측): 셀 12×8 — 몸통 8×6(cols2-9), 눈 검정 1셀 (3,1)·(8,1), 팔 2×2 좌우(rows2-3), 다리 4개(cols 2·4·7·9, 2셀). 색: 테라코타(구현 시 원본에서 픽셀 샘플링해 확정 — 추정 #D97757 근사).
- Clawd 위젯 이미지: 같은 그리드로 SVG 재구성 → 1024px PNG 렌더(투명 배경). 원본 frame은 흰 배경이라 직접 사용 불가.
- Codex 캐릭터: **같은 골격**(몸통 8×N + 검정 눈 + 팔 + 다리 4개)에 구름 머리 변형, indigo(Codex 아이콘 색 샘플링) — 시안 Boss 승인 대기(D3).
- config: `imagePath` 옵션(없으면 NSWorkspace 앱 아이콘 폴백). PNG는 `assets/`에 보관, 앱 번들 Resources로 복사.
- **애니메이션** (추가 요구 2026-06-12 "약간의 애니메이션 … 작업하는거 같이"): 프레임 기반 스프라이트 — 모션별 프레임 시퀀스(대기[확정 2026-06-12]: 정면 팔 들썩+깜빡임+꾸벅 졸기(z) — 옆 돌아보기·케이블 변주 제외 / **작업[승인 2026-06-12]: 옆모습으로 노트북 앞 타자** — 키 타격 픽셀, 화면 코드 라인 누적, 중간에 멈춰 "…" 생각 후 재개하는 리듬)를 **런타임 셀 드로잉**(픽셀 그리드를 view draw()에서 직접 렌더)으로 재생, 2~5fps Timer(+tolerance). PNG 시퀀스 방식에서 변경(2026-06-12) — 사유: 어떤 위젯 크기에서도 또렷(해상도 독립) + 에셋 빌드 파이프라인 제거. 픽셀 그림체 보존을 위해 보간·트위닝 금지, 칸 단위 스텝만. **전력 가드(MVP 포함)**: `occlusionState`가 비가시면 일시정지, 화면 슬립 시 정지, 토글로 애니메이션 끄기 제공. 모션 레퍼런스(실측 확보 2026-06-12, `assets/ref/motion/`): ① `clawd-laptop.mov` 36프레임 분석 — 시퀀스 = 정면 대기 → 옆모습 전환(투톤 음영+주둥이) → 검은 케이블 잡아당김 → 정면 복귀. **열린 노트북 타자 장면은 이 에셋에 없음(실측)** → "작업 모션"은 자작 옆모습 타자 모션(데모 승인본) 채택 — 옆모습 포즈(투톤 음영+주둥이)는 공식 프레임 문법을 따름. **케이블 당기기 동작은 대기 모션에서 제외(Boss 결정 2026-06-12).** ② `clawd-magnifier.gif` 113프레임(돋보기 탐색 모션) 확보. 추출 도구: `tools/extract_frames.swift`(swiftc 빌드, mov/gif 지원). 모드는 결정점 D5.
- **생활 사이클 개편 (2026-06-13, Boss 재결정)**: activity-aware(D5②) 폐기 — 위젯은 데스크탑 레벨이라 앱 사용 중(=창에 가려진 시간)에는 안 보이므로 "실행 중=작업 모션"은 보이지 않는 시간에만 발동하는 모순(Boss 지적). 대체: 위젯 = 작은 방(왼쪽 침대 + 오른쪽 노트북 책상 상시 배치), 캐릭터가 **대기 → 걸어가서 타자 → 꾸벅 → 침대로 걸어가 취침(이불·숨쉬기·zzz) → 기상 복귀** 루프를 무작위 길이로 순환(위젯별 비동기). 씬 18×9.2셀, 걷기 0.45셀/박자(2프레임 다리 교차), 좌향 걷기는 스프라이트 수평 플립. NSWorkspace 앱 감지 코드 제거.

## 6. Spike — 구현 0단계 (필수 선행, ~30줄 단일 .swift)

검토 4렌즈 공통 최우선 권고. macOS 26.4 borderless 회귀 보고(Forums 814798) 때문에 문서 기반 확정이 불가능한 항목을 본 구현 전에 실측한다. 실패해도 원인 분리가 되도록 본 코드와 분리된 최소 창 1개로:

- S1 (W4): desktopIcon+1 레벨 borderless NSPanel에서 mouseDown 수신 → 실패 시 폴백 사다리 ②③ 순차 실측
- S2 (W5): ① 위젯 클릭이 "배경화면 클릭 reveal"을 트리거하지 않는지(설정 Always 상태) ② 빈 배경 클릭 reveal 발동 시 위젯 잔존 ③ Show Desktop 제스처 잔존 ④ Mission Control 진입/복귀 ⑤ Spaces 전환 ⑥ Stage Manager ON ⑦ sleep/wake 후 레벨·위치 유지
- S3 (I3): .resizable+contentAspectRatio+minSize+canBecomeKey=false 조합으로 비활성 상태 가장자리 리사이즈·커서 동작 여부
- S4 (W3): 투명 모서리 클릭이 위젯에 잡히는지(alpha 백킹 적용/미적용 A/B)
- S5 (I1): 다른 앱 활성 상태에서 첫 클릭 → 실행 + **원래 앱 키보드 포커스 유지** 확인

S1~S5 결과를 이 문서에 추가 기록 후 MVP 진행.

### Phase 0 실측 결과 (2026-06-12, macOS 26.4 실기, Boss 수동 입력 + 로그 판정)

- **S1 PASS** — desktopIcon+1(레벨 -2147483602)에서 mouseDown 수신: `mouseDown zone=CENTER at=64,82` 외 4건. 폴백 사다리 불필요.
- **S4 PASS** — alpha 0.02 백킹의 시각적 투명 영역도 클릭 수신: `mouseDown zone=EDGE_ALPHA at=133,137` 외 1건 → W3 성립.
- **C10 확인** — `rightMouseDown` 수신.
- **S3 FAIL(추정)** — 가장자리 드래그에도 windowDidResize 0건 → 비활성 borderless에서 시스템 .resizable 리사이즈 미동작으로 판정, **수동 리사이즈(I3 폴백 B) 채택**.
- **S5 미판정** — nonactivatingPanel 문서 보장 + 정황 증거(클릭 직후 채팅 입력 포커스 유지). MVP 시연 확인 항목.
- **S2** — ⑥ Stage Manager: 현 환경 OFF(defaults 키 부재)로 해당 없음. ①②④⑤⑦: 미실측(화면기록·손쉬운사용 권한 대기) → MVP 시연 확인 항목.

### Phase 1 실측 추가 (2026-06-12, Boss 육안·수동 검증)

- **W3 최종 해법 변경**: 알파 백킹(0.02 뷰 fill → 0.01 창 배경)은 macOS 26 합성에서 **회색 상자로 비침(실측)** → **backgroundColor=.clear + `ignoresMouseEvents = false` 명시(tri-state)** 채택. 비문서 동작이지만 26.4에서 투명영역 클릭 수신 실측 확인. OS 업데이트 후 회귀 시 폴백: alpha 0.005.
- 검증됨: 표시·드래그 이동·위치 영속(재시작 복원)·activity-aware(Claude/Codex 실행 중 → 작업 모드, 실행 상태 pgrep 교차확인)·우클릭 전체 제어 메뉴·투명영역 클릭 실행.
- 메뉴바 아이콘: 노치에 가려진 것으로 추정(아이콘 다수) — 우클릭 메뉴를 전체 제어 세트로 보강해 의존 제거.
- 미검증 잔여: 리사이즈 실사용감·가장자리 커서 표시(mouseMoved 불확실), Show Desktop/Mission Control 잔존, sleep/wake 복원.

### Phase 2 — 외형·행동 확정 + 마무리 (2026-06-13, Boss 피드백 반복 반영)

- **생활 사이클 v2** (모드 폐기 후): 집 디오라마 — 크림 베이지 벽(시안 B 픽), 바닥 선반, 밤하늘 창문(달+별), 액자, 러그. 지붕은 넣었다가 제거(Boss). 사이클: 대기 → (40% 확률) 공차기[걸어가서 뻥, 포물선 비행, 최대 3킥] → 출근 → 타자(생각 점) → 꾸벅(z) → 퇴근 → 침대 취침(이불 둔덕·숨쉬기·세로 감은 눈 1짝·zzz) → 복귀. 단계 길이 무작위(전체 ~40초), 위젯별 비동기.
- **비율 튜닝 이력**: 캐릭터 0.66 → 0.55 스케일(발바닥 바닥 고정), 방 18→20셀, 옆모습 눈 1×1.4 → 0.85×1.05, 생각 점 간격 비스케일 보정(선처럼 보임 픽스), 누운 덩치 보정(서 있을 때 부피 매칭), 창문을 머리 동선에서 분리.
- **로그인 자동 시작 구현·실측**: `SMAppService.mainApp.register()` — **ad-hoc 서명에서 동작 확인** (로그 `method=sma smStatus=1`, 2026-06-13). C12 uncertain 해소. LaunchAgent 폴백 코드는 보험으로 유지. 기본 ON(최초 1회), 메뉴바·우클릭 메뉴 토글. 실제 재부팅 기동은 다음 로그인에서 자연 확인.
- 상태: **v1 완성 — Boss 승인** ("맘에 들어 마무리하고 정리하고"). git: xixwxx/desk_pin (private).
- **캐릭터 작명 (2026-06-13)**: Codex 구름 크리터 = **Cody(코디)** — Clawd가 Claude의 말장난이듯 Codex의 말장난 (Boss 픽). 메뉴 라벨: "Clawd (Claude)" / "Cody (Codex)".

## 7. 구현 단계

- **Phase 0 — Spike** (§6) → 결과 기록, 레벨·리사이즈 방식 확정
- **Phase 1 — MVP**: 위젯 2개(Clawd·Codex 캐릭터), 클릭 실행, 이동(performDrag), 리사이즈, 영속, 메뉴바 토글·종료, 방어 코드(D1), 우클릭 메뉴
- **Phase 2**: 로그인 자동 시작(P2 항목), 위젯 추가 UI(M2), hover 강조, 앱 .icns
- 각 Phase 종료 시 evidence-gate rubric + 실측 체크리스트(검토 권고 I열 항목들) 보고

## 8. 리스크 등록부 (검토 채택)

1. **macOS 26.4 borderless 회귀** — 입력 경로 전체가 회귀 표면 위. 대응: Spike 선행, 레벨 폴백 사다리.
2. **투명 픽셀 클릭 통과 → reveal desktop 오발동** — 대응: W3 alpha 백킹 (Spike S4로 검증).
3. **sleep/wake·디스플레이 재구성 후 창 상태 유실** — 대응: D1 방어 코드 MVP 포함.
4. **ad-hoc 재서명 churn** — BTM 로그인 항목 stale 화. 대응: B3 고정 경로 + 재빌드 후 status 재확인. 향후 TCC 필요 기능(접근성 등) 추가 시 재논의.
5. **performDrag 후 mouseUp 미도달** — 대응: 저장을 windowDidMove delegate로.
6. **config 파손** — 대응: atomic write + .bak 격리 + 기본값 재시작.
7. **의도치 않은 실행**(이동하려다 5px 미만 릴리즈) — 대응: 임계값 실사용 튜닝 여지.

## 9. 비목표

위젯 갤러리 통합, 정보 표시(시계 등), 자동 업데이트, 외부 배포(서명/공증), 다중 디스플레이 고급 처리(좌표 클램프만), macOS 26 미만 호환.

## 10. 검토 이력

- 2026-06-12 4렌즈 적대적 검토(wf_6949bde5-870, 에이전트 4, 웹·실기 실측 포함): C1-b·C4 wrong 적발→W3·W1로 수정, C2·C3-b·C6·C12 uncertain→S1~S3·P2 런타임 분기로 이관, C13 계열 전부 이 머신 실측 confirmed. 원본 JSON: 세션 transcript `tasks/w7xyaamyh.output`.

## 11. 결정점 (Boss)

전부 확정 (Boss, 2026-06-12 "웅 해줘 ㄱㄱ" = 추천안 일괄 채택):

- **D1. 앱 이름** → **DeskPin** (폴더 `desk_pin` 유지, bundle id `local.jinwoo.deskpin`)
- **D2. 리사이즈** → **정사각 고정** (contentAspectRatio 1:1)
- **D3. Codex 캐릭터** → **구름 크리터 승인** ("저거 개마음에 든다")
- **D4. Spike** → **승인 — Phase 0 진행**
- **D5. 애니메이션 모드** → ~~② activity-aware~~ → **생활 사이클 루프로 재결정 (2026-06-13, §5)** — 모드 개념 자체를 제거
