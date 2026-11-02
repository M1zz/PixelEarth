# 에셋 요청 목록

받은 파일은 `~/Downloads/pixel_earth_assets/`에 아래 파일 이름으로 넣어 주세요. 게임에 넣는 변환은 코드 쪽에서 합니다.

## 모든 그림에 공통으로 붙일 문장

```
pixel art, crisp hard pixels, no anti-aliasing, no blur, 1px dark outline, limited palette,
side view facing right, frames aligned on an exact grid with equal spacing,
transparent background (PNG alpha) — if transparency is not possible use a flat solid #FF00FF magenta background,
no checkerboard pattern, no ground shadow, no text, no watermark, no signature
```

- 투명 배경이 가장 중요합니다. 체커무늬가 그려진 배경은 지우기 어렵습니다. 투명이 안 되면 단색 마젠타(#FF00FF) 배경이 가장 좋습니다.
- 크기는 게임 픽셀의 정확한 배수(예: 8배)로 받으면 축소할 때 픽셀이 뭉개지지 않습니다.

## 0순위 — 새 세계 '나엘'의 겉모습

**받은 상태 (11월 2일)**: 별하늘, 물렁이, 날개막, 지형 두 겹은 `Tools/source_art/nael`로 넣었습니다(`Tools/import_nael.py`). 다섯 어른, 식생의 나뭇잎, 그림 하늘, 앱 아이콘은 그림체가 지금 게임(왕좌지기, 주인공)보다 단순해서 다시 받아야 합니다. 다시 받을 때는 `Sources/PixelEarth/Resources/king.png`를 참고 그림으로 함께 주세요.

세계관이 별을 잃은 행성 나엘로 바뀌었습니다(`docs/STORY.md` 0절). 해가 없고, 하늘은 땅 밑 심장에서 올라온 청록·보랏빛 **빛안개**입니다.
하늘색과 해 없애기는 코드로 이미 바꿨고, 아래 그림이 오면 지상이 지구처럼 보이지 않게 됩니다. 크기는 지금 파일과 같아서 받으면 이름 그대로 바꿔 끼우면 됩니다.

모든 그림에 위 공통 문장과 함께 이 문장도 붙여 주세요.

```
alien rogue planet with no sun, the sky lit from below by drifting teal and violet aurora mist,
muted cold palette with teal, violet and pale gold accents, nothing that looks like Earth
```

### N1. ~~빛안개 커튼 — `clouds.png`~~ 필요 없음: 하늘을 셰이더로 직접 그립니다 (`GameScene.skyShader`)
192×32px, 64×32 조각 3개 가로 한 줄. 하늘에 천천히 흘러가며 겹쳐 보입니다. 거의 흰색으로 그리면 코드에서 밝기를 조절합니다.

```
3 separate floating wisps of glowing aurora mist for a 2D pixel art sky, each 64x32 pixels in one row,
soft vertical curtain shapes with wavy hanging edges, pale near-white with faint teal tint,
semi-transparent dithered edges made of hard pixels, no clouds, no fluffy cumulus shapes.
```

### N2. 먼 지형 두 겹 — `mountains0.png`, `mountains1.png`
각 512×160px, 좌우가 이음새 없이 이어져야 합니다. 0번은 먼 겹(높고 흐릿), 1번은 가까운 겹(낮고 진함). 한 가지 회청색으로만 그리면 코드가 낮밤에 맞춰 물들입니다.

```
Seamless horizontally tiling background silhouette layer for a 2D pixel art side-scroller, 512x160 pixels,
an alien horizon: tall leaning spires of crystal rock, broken arches, and thin mesas,
a few faint glowing cracks in the rock, single flat grey-blue colour with one lighter shade for edges,
transparent sky above, bottom edge fully filled.
Make two versions: (A) distant layer, taller and sparser spires; (B) near layer, lower rolling crystal ridges.
```

### N3. 별하늘 — `stars.png`
256×128px, 이어 붙일 수 있게. 빛안개가 어두워지는 밤에 보입니다.

```
Seamless tiling night sky of a starless-sun rogue planet, 256x128 pixel art,
dense field of tiny cold white and blue stars of 1-2 pixels, a faint band of distant galaxy,
very dark navy background, no moon, no planets.
```

### N4. 지상 식생 — `surface_tiles.png`
16×16px 타일 6개 가로 한 줄. 순서대로: 풀 덮인 흙 윗면, 흙, 나무 줄기, 나뭇잎 덩어리, 나뭇잎 가장자리, 작은 꽃. 받으면 `tiles.png` 해당 칸에 옮기는 변환은 코드 쪽에서 합니다.

```
A row of 6 tiles for a 2D pixel art alien planet, each 16x16 pixels, seamless where they repeat:
1) dark violet soil topped with short teal glowing moss, 2) plain dark violet-brown soil,
3) a pale bone-white tree trunk with faint glowing veins, 4) a dense clump of drooping teal-blue leaves with tiny glowing tips,
5) the edge of that leaf clump fading out, 6) a small alien flower with a pale gold glowing bulb.
```

### N5. 물렁이 (지상의 작은 적) — `slimes.png`
144×16px, 24×16 프레임 6개: 색 3가지 × 2프레임(제자리, 눌림). 지금은 슬라임 그림입니다.

```
Sprite sheet of a small alien blob creature for a 2D pixel art game, 6 frames of 24x16 pixels in one row:
3 colour variants (teal, violet, pale gold), each with 2 frames (resting, squashed mid-hop).
A translucent jelly body with a glowing core seed inside and three tiny feeler stalks on top, no face.
```

### N6. 날개막 (동굴의 날짐승) — `bat.png`
48×14px, 24×14 프레임 2개(날개 위, 날개 아래). 지금은 박쥐 그림입니다.

```
Sprite sheet of a small alien cave flier for a 2D pixel art game, 2 frames of 24x14 pixels in one row
(wings up, wings down). A thin translucent membrane like a manta ray with a single glowing pale eye in the middle,
dark violet body, faint teal glow along the wing edges, no feathers, no bat ears.
```

### N7. 앱 아이콘 다시 — `app_icon.png`
1024×1024px, 글자 없이. 지금 아이콘은 지구 동굴 느낌이라 나엘에 맞춥니다.

```
App icon, pixel art style, 1024x1024. A small glass jar held up on the dark surface of an alien planet,
a handful of teal and violet aurora mist breathing inside the jar, above it a dark sky where the aurora is being
pulled down into a glowing crack in the ground, strong silhouette readable at small sizes, no text, no border.
```

### N8. 그림 하늘 천장 다시 — `painted_sky.png`
64×48px 1장(지금 `decor.png`의 그림 하늘 자리와 같은 크기), 좌우 이음새 없이. 9층 아이들이 천장에 칠한 '하늘'입니다. 나엘의 하늘은 빛안개라 파란 하늘과 구름이면 안 됩니다.

```
A ceiling painting for a 2D underground pixel art game, 64x48 pixels, seamless horizontally,
a child's naive painting of teal and violet aurora curtains made with coloured stone dust on dark rock,
uneven brush strokes, one curtain fold still wet and shiny, a tiny handprint at the bottom edge, no clouds, no blue sky.
```

### 층의 어른 다섯 (N9~N13)
> **바뀜**: 어른들이 사람이 아닌 생명(서랍달팽이, 여섯팔두더지, 물집게, 큰눈원숭이, 까치)이 되었습니다. 캐릭터 그림은 `docs/CHARACTERS.md`의 프롬프트를 쓰고, 아래 프롬프트는 쓰지 않습니다.

지금은 다섯 층 주인이 모두 같은 왕좌지기 그림에 색만 입혀 씁니다. 동화의 어른마다 얼굴이 따로 있어야 합니다(`docs/STORY.md` 2절).
모두 같은 규격으로 받습니다. 게임 크기 72×66px, **5프레임 가로 한 줄**(제자리에서 천천히 숨쉬기), 오른쪽을 봅니다. 8배면 프레임당 576×528.
아래 문장을 다섯 장 모두에 붙여 주세요.

```
storybook fairy-tale mood, a lonely gentle grown-up, not a monster, sad rather than scary,
large readable silhouette, 5 frames in one row of a slow idle breathing loop, each frame 72x66 pixels, facing right
```

**N9. 내일을 지키는 사람 (5층, 초록)** — `lord5.png`
```
A thin old gardener in a long moss-green coat standing beside a tall wooden cabinet with dozens of tiny drawers,
holding a small seed pouch close to the chest, a pocket watch on a chain, tiny sprouts at the feet, soft green glow.
```

**N10. 쉬지 않는 사람 (6층, 붉은)** — `lord6.png`
```
A stooped miner with sleeves rolled up, a pickaxe raised mid-swing, a lamp helmet, sweat drops,
a half-carved wingless bird of red stone tied to the belt, warm red glow from cracks in the rock behind.
```

**N11. 벽을 세운 사람 (7층, 푸른)** — `lord7.png`
```
A tall woman in a blue shawl standing inside a rising wall of water, one hand raised to hold the water up,
the other hand holding two small teacups, a bundle of dried herbs at her waist, calm sad eyes, cool blue glow.
```

**N12. 눈을 감은 사람 (8층, 보랏빛)** — `lord8.png`
```
A gaunt figure in a dark violet market-keeper's coat, eyes peacefully closed, one hand cupped behind an ear as if listening,
an extinguished lantern hanging from the other hand, a thin wisp of smoke, very dim violet rim light.
```

**N13. 하늘을 가진 사람 (9층, 흰)** — `lord9.png`
```
A small round man in a too-large white and gold coat sitting on a stack of ledgers like a throne,
a huge leather ledger open on his lap, a ring of heavy keys at his belt, behind him a vault door with pale light leaking through the seams.
```

## 받은 것 (적용 끝)

아래 1~6은 두 번째 묶음으로 받아 게임에 넣었습니다. 7번 이후는 아직 필요합니다.

### 1순위

### 1. 왕좌지기 (층의 주인) — `keeper.png`
게임 크기 72×66px, 4프레임 가로 한 줄(8배면 프레임당 576×528). 가면, 망토 어깨, 가슴의 빛은 거의 흰색으로 그려야 게임에서 층마다 다른 색으로 물듭니다.

```
Sprite sheet of a hulking hooded "throne keeper" boss for a 2D underground fantasy game.
A heavy dark grey cloak shaped like a bell, a pale cracked porcelain mask with two narrow eye slits,
a pale stone mantle across the shoulders, both hands holding a glowing white diamond-shaped light against the chest,
a tall staff with an unlit iron cage lantern.
4 frames in one row: standing still, crouching before a leap, mid-air with the cloak flaring out, landing impact.
Mask, mantle and the held light in pale near-white tones; everything else muted greys.
Each frame 72x66 pixels.
```

### 2. 빛굶주린 자 (밤의 적) — `starved.png`
게임 크기 20×28px, 6프레임 가로 한 줄.

```
Sprite sheet of a "light-starved" night wanderer for a 2D pixel art game.
A gaunt hunched figure in torn dark rags, pale grey-blue skin, long thin arms,
head pushed forward with two small glowing pale-yellow eyes, carrying an empty rusted lantern cage.
6 frames in one row: 4-frame walk cycle, then 2 frames crouching and swallowing a torch flame
with cupped hands at the mouth and orange glow on the face.
Each frame 20x28 pixels.
```

### 3. 갈림길 타일 — `junction.png`
게임 크기 16×32px(2칸 높이), 2프레임 가로 한 줄.

```
Tile of a narrow passage opening in an underground brick wall for a 2D pixel art game.
A tall dark vertical slit framed by worn carved stone blocks, faint cold blue air drifting out of the darkness,
2 animation frames in one row where the drifting air moves slightly.
Each frame 16x32 pixels, front view, edges blend with dark stone brick.
```

### 4. 포탑 (왕좌 수비) — `turret.png`
게임 크기 16×24px, 3프레임 가로 한 줄. 지금은 활 아이콘을 대신 쓰고 있습니다.

```
Sprite sheet of a small defensive "lantern turret" for a 2D pixel art tower defense scene.
A squat carved stone pedestal topped by an iron lantern with a lens that shoots bolts of light.
3 frames in one row: idle with a soft glow, charging with a brighter glow, firing with a bright flash from the lens.
Each frame 16x24 pixels.
```

### 2순위

### 5. 곁굴 장식 타일 — `passage_tiles.png`
16×16px 타일 7개 가로 한 줄. 순서대로: 이름이 새겨진 벽 A, 이름이 새겨진 벽 B, 손톱 자국 세 줄이 난 벽, 마른 약초 묶음, 침상 왼쪽, 침상 오른쪽, 푸른 돌가루로 칠한 천장(이어 붙여도 이음새가 없게).

```
A row of 7 tiles for a 2D underground pixel art game, each 16x16 pixels, in this order:
1-2) dark stone wall carved with rows of tiny names (two variants that tile seamlessly side by side),
3) stone wall with three claw scratch marks, the first deep, the second shallow, the last barely visible,
4) a bundle of dried herbs hanging on a string,
5-6) a small wooden cot with a thin blanket, left half and right half,
7) a ceiling painted with a naive blue sky and white clouds in stone dust, seamless horizontally.
```

### 6. 앱 아이콘 — `app_icon.png`
1024×1024px, 글자 없이.

```
App icon, pixel art style, 1024x1024. A small glass jar held up in a dark underground cave,
a warm golden light breathing inside the jar, faint coloured motes of red, green and blue light around it,
dark blue stone background, strong silhouette readable at small sizes, no text, no border.
```

## 3순위 (생존 시스템을 만들 때)

### 7. 생존 아이템 아이콘 — `survival_items.png`
16×16px 아이콘 5개 가로 한 줄: 빛열매, 구운 빛버섯, 맑은 물이 든 유리병, 빛 잔해(쓰러진 자리에 남는 빛 덩어리), 다 탄 횃불.

```
A row of 5 item icons for a 2D pixel art game, each 16x16 pixels:
1) a glowing pale gold berry cluster, 2) a roasted cyan glowing mushroom on a stick,
3) a small glass bottle of clear water with a cork, 4) a soft glowing heap of light fragments,
5) a burnt-out torch with grey ash at the tip.
```

### 8. 캠프 침상 — `bed.png`
32×16px(2칸 너비) 1장.

```
A simple wooden bed for an underground camp in a 2D pixel art game, side view, 32x16 pixels,
straw mattress, patched wool blanket, a small lantern hook on the headboard.
```

## 선택

### 9. 주인공 걷기 보강 — `player_walk6.png`
지금 시트는 걷기가 5프레임이라 한 장을 반복합니다. 같은 주인공으로 걷기 6프레임을 4줄(기본, 철, 금, 다이아 갑옷)로, 프레임당 20×32px 격자에 정확히 맞춰 주면 됩니다.
