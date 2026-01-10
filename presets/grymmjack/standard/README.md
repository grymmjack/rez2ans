# grymmjack's rez2ans presets - submission #1

> All the presets I have created making these 2 videos:

## ▶️ [REZ2ANS BETA](https://www.youtube.com/watch?v=dv9uiXLxr24&t=3040s&pp=0gcJCU0KAYcqIYzv)

## ▶️ [REZ2ANS BETA Part 2](https://www.youtube.com/watch?v=LWhCjbwhoIw&t=388s)

## Small scale guidance

> TLDR: Use 80px width, any height, indexed [CGA](./color-graphics-adapter.hex) palette, PNG format.

**To make small scale, you're going to forego shading in favor of accuracy.**

The preset I created is here:
[0 - img2ans(1px = 1block - 80 cols = 80px).ini](./0%20-%20img2ans%20%281px%20%3D%201block%20-%2080%20cols%20%3D%2080px%29.ini)

Since rez2ans does not crop, and the selection tool is imprecise, for best results you must prepare your source image ahead of time in a pixel editor.

In rez2ans you will use hires plain mode, and a 1:1 px to column/row approach.

### rez2Ans Setup

- `Image Adjustments` tab parameters to use
  - `WinX` = `1`
  - `WinY` = `1`
  - `Aspect` = `0.50` (do not use 0.55)
- Key `Conversion Settings` tab parameters to use
  - Style = `plain`
  - Mode = `hires`

### Small scale conversion tips

- If you are using Gen AI make sure you use "pixel art style", "small icon size", and be explicit about the dimensions
- Use pixel art that is converted already to CGA palette (16 colors) palette here: [./color-graphics-adapter.hex](color-graphics-adapter.hex)
- Before you even open rez2ans, get your pixel art to look good at 80 pixels width, because rez2ans uses 80 columns width. (this may change in future)
- If you can convert your pixel art to CGA ahead of time, do it, it will make it the most predictable outcome
- If your subject matter needs more blank area in the conversion, make it in the pixel art.

### Free pixel art editors

Any of these are fine, honestly anything that can save as a PNG in indexed palette mode is fine.

- GIMP (FOSS photoshop - takes some tweaking though)[https://www.gimp.org]
- Libre Sprite [free ASEPrite - like](https://libresprite.github.io/#!/)
- Grafx2 (harder / deeper learning curve, totally worth learning though) [deluxe paint - like](http://grafx2.chez.com/)
- PyDPainter (free deluxe paint clone written in python) [fantastic supports anim brushes](https://pydpainter.org/)
- DPaint.js (javascript web based deluxe paint - like) [link here](https://www.stef.be/dpaint/)
- Pixelorama (FOSS and fantastic) [homepage](https://pixelorama.org/)

### Pixel art sizes for small scale
- 80px wide
- 25px tall = full screen
- 50px tall = full screen 8px
- But any width will work, the most important is 80px wide

## Examples:

### `55 - The Crow.ini`
![The Crow](./example-the_crow.png)

### `44 - Ghostbusters.ini`
![Ghostbusters](./example-ghostbusters.png)

### `33 - Dungeon Degenerates.ini`
![Goblinko Fishman](./example-goblinko-fishman.png)

### `35 - Dungeon Degenerates 3.ini`
![Goblinko Skull Candle](./example-goblinko-skull-candle.png)

### `31 - Small Renderer.ini` (i think)
![Haunted House](./example-haunted-house.png)

### `18 - Egypt B.ini`
![King Tut](./example-king-tut.png)

### `43 - LOTROrcs.ini`
![LOTR Orcs](./example-lotr-orcs.png)

### `65 - Mind Flayer.ini`
![Mind Flayer](./example-mindflayer.png)

### `40 - Return of the Living Dead.ini`
![Return of the Living Dead](./example-return-of-the-living-dead.png)
