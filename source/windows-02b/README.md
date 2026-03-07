# img2bin_gui (Lazarus / FreePascal)

GUI tool to convert PNG/JPG into TheDraw/PabloDraw `.BIN` (80xN) using CP437 blocks/shades.

## Files
- `img2bin_gui.lpr`   (project source)
- `mainform.pas`      (UI: open image, drag-select crop box, render, save BIN)
- `img2bin_core.pas`  (public API facade)
- `img2bin_types.pas` (types + constants)
- `img2bin_palette.pas` (palette + distance metrics)
- `img2bin_convert.pas` (conversion engine)
- `img2bin_io.pas`    (image/BIN I/O)
- `img2bin_styles.pas` (style presets)
- `img2bin_cp437.pas` (CP437 preview glyph mapping)

## Build (Windows / Lazarus)
1. Open Lazarus
2. `File -> Open...` and open `img2bin_gui.lpr`
3. Lazarus may ask to "Create project / rebuild" — say yes.
4. Build & Run.

## Using crop selection
- Open an image
- Drag a rectangle on the left preview
- Keep "Render selection only" checked
- Click Render
- Save `.BIN` and open in PabloDraw (80 columns, height = rows)

Tip: best starting settings:
- Style: `acid`
- Mode: `hybrid`
- Dither: `fs`
- Window: 4 x 4

## AutoShader + DOSBox model

AutoShader is the "reverse ANSI" trick: it uses *real ANSI art* you import (BIN/ANS) as a training hint for
which **FG/BG pairs** look good for each glyph.

Workflow:
1. Go to **Ansi Art** tab.
2. Pick a **Shader style**: `realstyle`, `toon`, `death`, `ascii`.
3. Click **Import shader (BIN/ANS)...** and import one or more reference files.
   - Keep **Learn shading glyphs only** enabled (recommended) so normal text/box UI characters don't pollute the shader.
4. Enable **Use shader BIN**.
5. Enable **DOSBox model** (recommended for DOSBox output / how ANSI editors look).
6. Set Mode = `autoshader` (or `glyphfit` if you want glyph matching without shader ramps).

The imported shader data is saved as JSON in a `shaders` folder next to the EXE, so it grows over time.

Each profile JSON also contains a small `params` section (blockStrength / edgeKeep / verticalSmear). If you want to push a style harder,
you can edit those numbers and re-run.

During Render/Convert, a small progress popup appears with a progress bar and a log so it doesn't feel frozen.


## New UI
- Palette: vga16 / gray16
- CellW(px): fixed preview cell width (height is 2x), preview scrolls instead of scaling.


## Dither modes
- none
- fs (Floyd–Steinberg)
- atkinson
- jjn (Jarvis–Judice–Ninke)
- stucki
- sierra-lite
- bayer4 (ordered 4x4)


## Dither strength
- 0.0 disables dithering even if a dither mode is selected.
- 1.0 is normal.
- Up to 3.0 increases the effect (can get noisy).

## Look presets
- realistic: balanced photo look
- cartoon: higher contrast + saturation
- lineart: high contrast + low saturation (edgey)


## ANSIrez Mode
- Open the **ANSIrez Mode** tab.
- Enable **ANSIrez mode** to run a post-quantization 2x2/4x4 smoothing pass (classic ANSIrez-style cleanup).
- Pick a filter: **median**, **blend**, **brite**, or **4x4**.
- Use **Brightness/Gamma/Contrast/Saturation** to tweak the palette matching.

Typical starting points:
- Brightness: 0.90–1.10
- Gamma: 0.95–1.05
- Contrast: 1.10–1.25
- Saturation: 0.90–1.10
