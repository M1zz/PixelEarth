# Pixel Earth — 빛을 담은 병 (macOS)

**별을 잃은 행성 나엘. 하늘의 마지막 빛을 병에 담아 들고, 땅속으로 내려가, 그 빛을 키워 하늘을 되찾는 게임.**

나엘에는 해가 없습니다. 하늘을 밝히는 빛안개는 땅 밑 깊은 곳의 심장에서 빛기둥을 타고 올라옵니다. 세계관은 `docs/STORY.md` 0절에 있습니다.
Swift + SpriteKit, 외부 의존성 0, 전부 무료 도구로 빌드됩니다.

## 이야기와 구조

- **1막 하강** — 조용한 오후, 마지막 안개지기인 할머니가 병을 건넨다. 빛안개가 거꾸로 땅속으로 빨려 들어가고 발밑이 갈라진다. 갱도를 따라 내려가면 뒤가 무너진다.
- **2막 정착** — 5층 균열의 숲(빛기둥의 금 사이로 빛이 샌다). 제단 세 개에 붉은·초록·푸른 빛풀을 심어 캠프를 깨운다. 아래로 내려가 포자와 광석을 병에 넣어 빛의 색을 키운다.
- **3막 되찾기** — 9층 '빛의 심장'은 흰빛(세 색 모두)에만 응답한다. 빛을 위로 돌려보내면 무너진 암석이 부서지고, 올라갈수록 하늘이 밝아진다.

### 빛의 색 = 세계를 읽는 렌즈
| 색 | 만드는 법 | 여는 것 |
|---|---|---|
| 붉은빛 | 붉은 포자(6층) + 철 | 돌 속 **숨은 광맥**이 비침, 용암 가장자리 |
| 초록빛 | 초록 포자(지상·옛 통로·캠프) + 금 | **덩굴**(초록 포자+나무) 제작, 식물 |
| 푸른빛 | 푸른 포자(7층) + 다이아 + 물 | **물의 장막**(7층) 통과 |
| 보랏빛 | 빨강 + 파랑 | **유령 돌** 통과 — 봉인된 보물방 |
| 흰빛 | 셋 다 | 심장이 응답. 단, 모든 생물이 모여든다 |

8층부터는 횃불이 꺼집니다. 병의 빛만 남습니다.

## 실행 (Xcode)

1. Xcode에서 `PixelEarth.xcodeproj`를 엽니다.
2. 스킴 `PixelEarth`, 대상 `My Mac` 선택 후 ⌘R.

소스 파일을 추가하거나 지웠다면 `xcodegen generate`로 프로젝트를 다시 만듭니다. 프로젝트 설정의 원본은 `project.yml`입니다.

> 성능: Debug 구성에도 `-O`가 걸려 있어 60fps가 나옵니다. 더 빠르게 하려면 Product ▸ Scheme ▸ Edit Scheme ▸ Run ▸ Build Configuration = Release.

## 실행 (터미널) / .app 번들 만들기

```bash
swift run -c release            # 바로 실행
./Tools/make_app.sh             # build/PixelEarth.app 생성 (더블클릭 실행 가능)
```

## 조작

| 동작 | 키 |
|---|---|
| 이동 / 점프 | A D / Space |
| 위아래 겨누기 · 덩굴 오르내리기 · 발판 내려가기 | W / S |
| 공격 · 캐기 · 사용 · 상자 · 왕좌 · 대화 | K (길게 누르면 계속) |
| 블록 설치 · 제단에 빛풀 심기 | L |
| 핫바 선택 | 1~9 |
| 제작 / 가방 / 병 / 왕좌 현황 | E / I / J / R |
| 손에 든 것 버리기 / 병에 넣기 | Q / F |
| 수비 중 포탑 / 방벽 | B / V |
| 창과 메뉴에서 옮기기 / 고르기 | W A S D / K, Return, Space |
| 지도 확대 | M |
| 메뉴(저장) | ESC |

화면에도 키가 안내됩니다. 오른쪽 버튼에 키가 함께 표시되고, 핫바 위 줄은 손에 든 물건과 커서 아래 대상에 맞는 행동을 보여 줍니다. 금색으로 깜빡이는 안내는 지금 필요한 행동입니다. 규칙은 `KeyHints.swift`에 있습니다.

마우스도 그대로 쓸 수 있습니다. 키는 물리 위치로 읽으므로 한글 입력 상태에서도 동작합니다.

## 갈림길과 곁굴

5~9층 왕좌 방 옆 통로 끝에 갈림길이 있습니다. 앞에서 K를 누르면 돌아서서 화면과 직각으로 뻗은 곁굴로 들어가고, 곁굴의 갈림길에서 다시 K를 누르면 나옵니다. 곁굴은 세계 양쪽 가장자리에 기반암으로 닫힌 띠로 만들어져 있어 조명, 저장, 그리기가 그대로 동작합니다. 위치와 내용은 `Junction.swift`, 처음 들어갈 때의 문장은 `passage.<층>.*` 키입니다.

## 첫 오후 (튜토리얼)

새 게임은 할머니가 병을 건네는 장면에서 시작합니다. 병 들여다보기, 걷기, 점프, 나무 베기, 판자, 작업대, 나무 검, 슬라임, 병에 넣기까지 9단계를 안내하고, 끝나면 3분의 자유 시간 뒤에 재난이 옵니다. 재난 전 지상에는 자연 스폰이 없고 밤도 오지 않습니다. T로 건너뛸 수 있습니다. 조절값은 `Tutorial.swift`, 문구는 `Localizable.xcstrings`(한국어, 영어)에 있습니다.

## 층의 왕좌와 수비

5~9층마다 왕좌와 주인이 있습니다. 주인을 쓰러뜨리고 그 층의 빛을 지닌 채 왕좌에서 K를 누르면 다음 주인이 됩니다. 주인이 되면 공물을 얻고, 침략이 오면 포탑과 방벽으로 왕좌를 지키는 디펜스 전투를 합니다. 지면 도전자가 더 강한 다음 대 주인이 됩니다. 규칙은 `Reign.swift`, 난이도 수치는 `Defense.swift`의 `DefenseDesign`에 있습니다.

각 층의 첫 주인에게는 세상이 아는 소문과 실제 사연이 있습니다. 층마다 더할 중간 보스와 재앙 뒤 위에서 일어난 일은 `docs/STORY.md`에 설계되어 있습니다. 층에 처음 내려가면 소문을 듣고, 주인을 쓰러뜨리면 왕좌 기록(R → 이야기)에 진실이 남습니다. 문구는 `Localizable.xcstrings`의 `lord.<층>.*` 키입니다.

## 소개 문구

스토어 소개 문구 초안은 `docs/store_description.txt`(한국어, 영어, 평문)에 있습니다. 다른 게임과 비교하는 표현은 쓰지 않습니다.

## 진행

나무 → 판자 → **작업대** → 나무 곡괭이 → 돌 → 돌 곡괭이 → 철(주괴 제련) → 금 → 다이아 → 갑옷
석탄이 모자라면 작업대에서 원목 2개로 석탄 1개를 만들 수 있습니다. 첫 보스는 5층의 주인입니다. **빛 조각**(다이아 1 + 빛수정 3, 상자와 9층 공물)은 빛의 그릇을 20 늘립니다. 지하 깊은 곳엔 용암, 보물상자, 빛버섯.

밤의 지상에는 **빛굶주린 자**가 나옵니다. 사람보다 가까운 횃불을 먼저 쫓아가 삼키므로, 횃불을 미끼로 따돌릴 수 있습니다.

## 에셋 교체

게임 그래픽은 원본 시트(`~/Downloads/game_pixel_assets`)를 `Tools/import_assets.py`로 변환한 결과입니다.
원본은 체커무늬가 그림에 박힌 불투명 PNG라서 그대로 넣을 수 없고, 스크립트가 배경 제거, 축소, 아래 레이아웃으로 재배치를 합니다.

```bash
python3 Tools/import_assets.py          # Pillow 필요. Resources의 PNG를 덮어씁니다
```

원본에 없는 선인장, 코인, `glow.png`, `pixel.png`는 `Tools/placeholder_assets/`의 기존 그래픽을 씁니다.
배경음악 `music.caf`는 `Tools/gen_music.py`가 합성한 64초 무한 반복 곡입니다(`python3 Tools/gen_music.py <폴더>` 뒤 `afconvert -f caff -d ima4 <폴더>/music.wav Sources/PixelEarth/Resources/music.caf`). 소리 켬/끔을 따릅니다.
앱 아이콘은 `Tools/icon_art.png` 그림을 `python3 Tools/make_icon.py`가 macOS 규격의 둥근 모양으로 만듭니다.

빛 조각 아이콘(`items.png` 50번 칸)과 빛의 그릇 게이지(`vessel.png`)는 `Tools/gen_original_art.py`가 직접 그립니다.
왕좌지기(`king.png`, 72×66 ×5 숨쉬기), 빛굶주린 자(`zombie.png`, 26×28 ×6: 걷기 4, 횃불 삼키기 2), 갈림길(`tiles.png` 46행: 0~1열 아래, 2~3열 위), 포탑(`turret.png`, 16×24 ×3), 곁굴 그림(`decor.png`, `bed.png`), 앱 아이콘은 두 번째 묶음 `Tools/source_art/bundle`을 `Tools/import_bundle.py`가 변환합니다. 묶음의 `keeper.png`와 `passage_tiles.png`는 이름이 서로 바뀌어 있어 스크립트가 내용대로 씁니다.
`import_assets.py`는 마지막에 두 스크립트를 차례로 부릅니다. 앱 아이콘은 `App/Assets.xcassets`에 있습니다.
`Tools/gen_assets.py`를 실행하면 Resources가 이전 플레이스홀더로 돌아가니 주의하세요.

- `tiles.png` — 512×752. 행 = 타일 ID(0~46), 16px 타일. 31 붕괴암석, 32 빛수정, 33~35 포자(빨/파/초), 39 제단(4프레임), 40 심장, 41~43 빛풀, 44 덩굴, 45 왕좌, 46 갈림길(직접 그림).
  오토타일(흙·돌·광석 등)은 열 = `mask*2 + variant` (mask 비트: 1=위 노출, 2=오른쪽, 4=아래, 8=왼쪽).
  특수 타일(횃불·물·용암·문·상자·꽃·발판·등불)은 열 = 프레임.
- `walls.png` — 배경 벽 4종 × 4변형.
- `player.png` — 20×32 프레임 9개(idle, walk×6, jump, fall) × 4줄(기본/철/금/다이아 갑옷). 앞팔은 `arm.png`(6×12, 갑옷별 4프레임)로 따로 그려 도구를 휘두릅니다. 원본은 `Tools/source_art/player_sprite_sheet.png`로, 4줄에 몸 8포즈와 팔 1개씩(걷기 5프레임, 게임은 6프레임이라 하나를 반복)입니다.
- `slimes.png`(24×16 ×2프레임 ×3색), `zombie.png`(빛굶주린 자, 20×28 ×4), `bat.png`(24×14 ×2), `king.png`(왕좌지기, 72×66 ×2, 층 색으로 물듦)
- `items.png` — 16×16 아이콘, 인덱스 = 아이템 ID − 100.
- `mountains0/1.png`, `clouds.png`, `stars.png` — 패럴랙스 배경.
- `jar.png`(36×40 ×3단계), `bug.png`(4×4 ×2), `core.png`(48×48 ×2)
- 효과음은 `Tools/gen_sounds.py`로 합성한 WAV.

## 구조

```
Sources/PixelEarth/
  main.swift          AppKit 부트스트랩(창 + SKView)
  Tiles.swift         타일/아이템/레시피 데이터
  World.swift         시드 기반 월드 생성(바이옴·동굴·광맥·용암·상자·식생), 오토타일 마스크
  Lighting.swift      RGB 3채널 BFS 조명
  Entities.swift      플레이어/적/드롭/화살, 공용 물리
  Game.swift          시뮬레이션 전체(입력→채굴/설치/전투/스폰/드롭/저장 타이머) — SpriteKit 의존 없음
  Assets.swift        스프라이트시트 로딩·슬라이싱, 효과음
  ChunkRenderer.swift 32×32 타일 청크를 CGContext로 베이크해 SKSpriteNode 텍스처로
  GameScene.swift     카메라, 패럴랙스 하늘, 엔티티 노드 동기화, 조명 멀티플라이 오버레이, 입력
  HUD.swift           하트/핫바/미니맵/시계/보스바, 제작·가방 패널, 메뉴
  Jar.swift           병 — 들어간 것 → 빛의 색, 단계, 반응
  Tutorial.swift      첫 오후의 단계, 자유 시간, 목표 안내
  Aim.swift           키보드 겨누기
  Reign.swift         층의 왕좌, 주인 계승, 침략
  Defense.swift       수비 전투와 난이도 표
  Story.swift         막 전환, 층 메시지, 제단, 심장, 결말 선택
  Save.swift          ~/Library/Application Support/PixelEarth/world1.save (JSON)
```

Game.swift가 SpriteKit을 모르기 때문에, 나중에 iOS로 갈 때는 GameScene/HUD의 입력 부분만 터치용으로 바꾸면 됩니다.
