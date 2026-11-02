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

## 1순위

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

## 2순위

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
