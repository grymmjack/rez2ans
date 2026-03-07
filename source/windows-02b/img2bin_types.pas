unit img2bin_types;

{$mode objfpc}{$H+}

interface

uses
  Math, Types, FPImage;

type
  // Palette profiles supported by the converter.
  // NOTE: Different terminals/viewers use different base RGB values.
  // If your reds/blues look "off", try switching the palette profile.
  TPaletteKind = (pkVGA, pkWin, pkGray);

  // Palette distance metric used when choosing the "nearest" palette color.
  // NOTE: New metrics are appended to preserve older INI index values.
  TColorMetric = (
    cmRGB,          // naive sRGB Euclidean
    cmRedmean,      // weighted RG...B (good perceptual compromise)
    cmYCbCr,        // luma/chroma space with optional per-channel weights
    // --- added metrics (slower, higher quality) ---
    cmLinearRGB,    // Euclidean in linear RGB (gamma-corrected)
    cmXYZ,          // Euclidean in CIE XYZ (D65)
    cmLab76,        // CIE Lab ΔE76
    cmLab94,        // CIE Lab ΔE94 (graphic arts)
    cmLab2000,      // CIEDE2000
    cmOKLab,        // OKLab distance
    cmOKLCH,        // OKLCH (with hue wrap)
    cmHSVAdaptive   // HSV with saturation-adaptive hue weighting
  );

  // Dithering modes applied during quantization.
  TDitherMode = (dmNone, dmFS, dmAtkinson, dmJJN, dmStucki, dmSierraLite, dmBayer4);

  // TronicShade-specific diffusion models (used only when Mode=rmTronicShade).
  // NOTE: Kept separate from TDitherMode to avoid changing legacy INI indices.
  TTronicDiffusionModel = (
    tdmOff,
    tdmOrderedBayer4,
    tdmOrderedBayer8,
    tdmFloydSteinberg,
    tdmJJN,
    tdmAtkinson,
    tdmSierraLite
  );

  // Cell-level diffusion models (operates on the 80xN cell grid).
  // This is distinct from TDitherMode (pixel/quantizer dithering).
  // NOTE: Ordering mirrors TTronicDiffusionModel to make mapping trivial.
  TCellDiffusionModel = (
    cdmOff,
    cdmOrderedBayer4,
    cdmOrderedBayer8,
    cdmFloydSteinberg,
    cdmJJN,
    cdmAtkinson,
    cdmSierraLite
  );

  // TronicShade-specific color matching metric.
  // NOTE: LumaOnly is intentionally first and is not the same as cmYCbCr.
  TTronicColorMetric = (
    tcmLumaOnly,
    tcmRGB,
    tcmRedmean,
    tcmYCbCr,
    tcmHSVAdaptive
  );

  // Rendering modes for 80-column cells.
  // rmCartoon: prefers half/side blocks on color transitions for smoother edges.
  // rmColorBook: flat fills + black outlines ("coloring book" look).
  TRenderMode = (rmHires, rmShades, rmHybrid, rmCartoon, rmColorBook, rmGlyphFit, rmAutoShader, rmTronicShade);

  // ANSIrez-style post-quantization filters (applied on the quantized 16-color grid).
  // NOTE: These are inspired by ANSIrez's 2x2/4x4 filters, but adapted to img2bin's
  // 2x2-subpixel internal grid.
  TAnsiRezFilter = (afNone, afMedian, afBlend, afBrite, af4x4);

  // Optional debug report for TronicShade rendering (filled by converter when requested).
  TTronicRenderReport = record
    Cols: Integer;
    Rows: Integer;
    CellsTotal: Integer;
    CellsChanged: Integer;
    CellsLockedColors: Integer;
    CellsWithStylePrior: Integer;
    CellsWithEdgeForce: Integer;

    SumBestErr: Int64;
    MinBestErr: Int64;
    MaxBestErr: Int64;
    SumMatchPct: Int64;

    SumToneErrAbs: Int64;
    SumToneErrSigned: Int64;
  end;

  PTronicRenderReport = ^TTronicRenderReport;

  // Character set used by GlyphFit mode.
  // Blocks: only block/shade characters.
  // Shading: blocks + punctuation gradient.
  // Lines: adds CP437 line/box drawing characters (good for rounded/outlined shapes).
  // Full: allows all printable CP437 (can look great, but may introduce symbols).
  // ASCII: printable 7-bit ASCII only (32..126).
  // Glyph candidate sets (order must match UI dropdown indices).
  // gsAnsiBlocks: CP437 shade blocks + solid + top/bottom half blocks (no left/right side halves).
  // gsAnsiBlocksPixel: same glyph set as gsAnsiBlocks, but tuned for pixel art
  // (ramp shades are treated as last-resort and BG is stabilized against neighbors).
  // GlyphSet UI order MUST match mainform.pas CbGlyphSet.Items
  TGlyphSetKind = (gsBlocks, gsShading, gsAnsiBlocks, gsAnsiBlocksPixel, gsLines, gsFull, gsAscii , gsTronic);

  // Optional restriction of glyph candidates to a gradient/ramp.
  // gmOff   : use GlyphSet normally (legacy behavior)
  // gmFixed : restrict glyph candidates to the chosen GradientSet
  // gmAuto  : pick a gradient per-cell (blocks for flat areas, ASCII for detail)
  TGradientMode = (gmOff, gmFixed, gmAuto);

  // Progress callback for long-running conversions.
  // Percent is 0..100. Msg can be '' for simple percent updates.
  TProgressProc = procedure(Percent: Integer; const Msg: string) of object;

  TRGB = record
    R, G, B: Byte;
  end;

  TRGBArray = array of TRGB;

// Optional "color hint" mapping used to bias palette selection.
// Src is the sampled/average source color, TargetIdx is the preferred
// ANSI palette index (0..15), and Strength is how strongly to bias.
TColorHint = record
  Src: TRGB;
  TargetIdx: Byte;   // 0..15
  Strength: Integer; // 0..50000 typical (higher = stronger bias)
end;

TColorHintArray = array of TColorHint;

  // One BIN cell (character + attribute byte).
  TCell = packed record
    Ch: Byte;    // CP437 character byte
    Attr: Byte;  // (BG shl 4) or FG, each 0..15 (iCE allows BG 0..15)
  end;

  TCellArray = array of TCell;

  // Main conversion settings.
  TConvertOptions = record
    Aspect: Double;
    Palette: TPaletteKind;      // e.g. 0.55
    PaletteMatch: Boolean;      // pre-match colors to palette inside sampling window
    PreMatchHexFile: string;   // optional .hex palette file for pre-match (empty = built-in)
    PreMatchPalette: TRGBArray; // optional loaded palette (2..256); if set, used for pre-match mapping
    // Ordered dither strength for custom pre-match palettes (Bayer 4x4).
    // 0 disables ordered dithering for the custom palette; 100 is strongest.
    PreMatchBayerStrength: Integer;
    ColorMetric: TColorMetric;  // how to choose nearest palette color
    // Perceptual color matching strength, in percent (50..200 typical).
    // Higher values emphasize chroma differences more (helps saturated reds/blues).
    ColorMatchPct: Integer;

    // Fine-tuning for cmYCbCr metric (percent, 50..300 typical).
    // YWeight emphasizes brightness matching.
    // CbWeight emphasizes blue/yellow chroma matching.
    // CrWeight emphasizes red/cyan chroma matching.
    YWeightPct: Integer;
    CbWeightPct: Integer;
    CrWeightPct: Integer;

// Optional user-provided color hints (sampled from the loaded image).
// These bias NearestAnsi16 so intended hues (e.g. pastel pink) don't drift
// to gray/white when the palette is limited.
HintTolerance: Integer;   // 0..255 typical (higher = wider influence)
ColorHints: TColorHintArray;

// If True, use the sampled hints to build a temporary per-image palette by
// overriding the base 16-color palette entries for any hinted ANSI indexes.
// This is often more stable than distance-biasing (no negative distances).
UseHintPalette: Boolean;

    // If True, apply user color hints as a final post-pass on the finished
    // 80xN cell grid. This can "snap" near-misses (e.g. pastel pink drifting
    // toward white) back to the intended ANSI index.
    HintPostFix: Boolean;

    // 0..100. If a cell's sampled average color matches a hint color by at
    // least this percent, the cell's FG/BG is adjusted toward the hint.
    // Typical: 85..95.
    HintPostFixPct: Integer;


    // If True, gently re-fit hinted palette entries after each AutoShader/GlyphFit refinement pass.
    // Only hinted ANSI indexes are adjusted (others remain standard VGA/Win palette).
    RefitHintedPaletteEachPass: Boolean;

    ForcedRows: Integer;        // <=0 means auto

    WinX: Integer;              // sample window width in pixels
    WinY: Integer;              // sample window height in pixels

    UseCrop: Boolean;
    Crop: TRect;                // in source image pixels

    Ice: Boolean;               // iCE colors (BG 0..15)
    Dither: TDitherMode;
    DitherStrength: Double;     // 0..3 typical

    // Cell-level diffusion (operates on the 80xN cell grid decisions).
    // This is independent of TDitherMode (pixel/quantizer dithering).
    CellDiffusionModel: TCellDiffusionModel;
    CellDiffusionAmount: Integer; // 0..100
    // Extra luma-fit penalty (0..100). If diffusion is enabled and this is 0,
    // the converter uses a gentle default internally.
    CellToneCorrection: Integer;
    Mode: TRenderMode;          // hires/shades/hybrid

    Gamma: Double;
    Contrast: Double;
    Saturation: Double;
    Brightness: Double; // overall brightness multiplier (1.0 = unchanged)

    // ANSIrez mode: apply an additional palette-grid filter after quantization.
    // This helps reduce speckle and can thicken thin lines, at the cost of some detail.
    AnsiRezMode: Boolean;
    AnsiRezFilter: TAnsiRezFilter;

    // GlyphFit mode options
    GlyphSet: TGlyphSetKind;
    TronicGlyphSet: TGlyphSetKind; // glyph set used only in Tronicshade mode
    GlyphSmooth: Double; // 0..1, small neighbor-bias to reduce noise

    // Optional gradient restriction for glyph selection (GlyphFit/AutoShader paths).
    GradientMode: TGradientMode;
    GradientSet: Integer; // 0..GRADIENT_COUNT-1 (see img2bin_gradients)

    // Shade-blend weight (0..1). When >0, shading glyphs (░▒▓) may be scored
    // using a perceptual "blended" target color rather than strict per-pixel
    // error. This effectively extends the usable "palette" by leveraging
    // FG/BG micro-dither via shade blocks.
    ShadeBlend: Double;


    // Glyph bias weights (100 = neutral). Values >100 prefer the glyph; <100 discourage.
    // Up/Down blocks affect ▀/▄ selection; ShadeBlocks affects ░▒▓ texture glyphs.
    BlockUpWeight: Integer;    // 0..200 (default 100)
    BlockDownWeight: Integer;  // 0..200 (default 100)
    ShadeBlockWeight: Integer; // 0..200 (default 100)

    // Use shader BIN (AutoShader) color pairs if a shader has been loaded.
    UseShaderLib: Boolean;

    // When UseShaderLib is enabled, restrict AutoShader/GlyphFit candidates to
    // glyph + FG/BG combinations that actually appeared in the loaded shader
    // profile. This improves style consistency and avoids "random" glyphs
    // that never occur in your shader training art.
    ShaderStrictGlyphMatch: Boolean;


    // Number of refinement passes for Shade/AutoShader/GlyphFit (>=1).
    AutoShaderPasses: Integer;

    // If >0, when the best per-cell match falls BELOW this percent,
    // block/shade color refinement may use a 3x3 neighborhood average color.
    AutoShader3x3BelowPct: Integer; // 0..100, 0 = off

    // If >0, prefer shade/block glyphs (░▒▓█) when their match percent is >= this value.
    AutoShaderBlocksOnlyPct: Integer; // 0..100, 0 = off
    // DOSBox viewer-model matching.
    // When enabled, GlyphFit/AutoShader scoring compares tiles after a small
    // horizontal blur in linear-light. This matches how DOSBox output scaling
    // makes ░▒▓ blends and block edges appear on screen.
    DosBoxModel: Boolean;

    // Two-cluster FG/BG guess (experimental).
    // When enabled, GlyphFit/AutoShader/TronicShade will also evaluate a per-cell
    // 2-color clustering guess (FG/BG + glyph mask alignment) as an alternative
    // to per-glyph on/off averages.
    TwoClusterGuess: Boolean;
    // 0..200. Higher = stronger preference for glyph masks that match the two clusters.
    TwoClusterStrength: Integer;



    // PatchStyle AutoShader (learned patches from imported ANSI/BIN)
    PatchStyleEnabled: Boolean;
    PatchUse10: Boolean;
    PatchUse5: Boolean;
    PatchUse3: Boolean;
    PatchLoops: Integer;        // number of 10->5->3 cycles (1..8)
    PatchMinMatchPct: Integer;  // 0..100 (signature match threshold)
    PatchApplyMode: Byte;       // 0=full (glyph+colors), 1=glyph-only

    // TronicShade mode controls (rmTronicShade)
    // TronicCharStrength: 0..200 (100 = default strength)
    // TronicLumaOnly: when True, candidate scoring is luma-driven (hue differences matter less)
    TronicCharStrength: Integer;
    TronicLumaOnly: Boolean;
    // TronicToneCorrection: 0..100, extra luma-fit penalty (helps overall brightness/tone)
    TronicToneCorrection: Integer;

    // TronicAutoShader: build a smoothed tone target field using overlapping windows.
    // Defaults to 10x10 windows stepping by 5 cells.
    TronicAutoShaderEnabled: Boolean;
    TronicWindowSize: Integer; // 6..20 typical (default 10)
    TronicWindowStep: Integer; // 1..10 typical (default 5)

    // Tronic diffusion + color metric
    TronicDiffusionModel: TTronicDiffusionModel;
    TronicDiffusionAmount: Integer; // 0..100
    TronicColorMetric: TTronicColorMetric;
    // TronicApplyMode: 0=full (glyph+colors), 1=glyph-only (keep existing colors)
    TronicApplyMode: Byte;


    // Tronic edge shading (post-process + scoring gate)
    TronicEdgeShadeEnabled: Boolean;
    // Edge sample size for mix ratio (2..4)
    TronicEdgeSampleSize: Integer;
    // Edge block threshold: 0..50. Half-blocks are allowed only for very clean edges.
    // Higher values => fewer half-blocks, more shade ramps.
    TronicBlockThreshold: Integer;
    // Shade weight: 0..200. Higher values => stronger preference for ░▒▓ texture on edges.
    TronicShadeWeight: Integer;
    // If True, corners/junctions (multi-direction edges) always use shade ramps (░▒▓) instead of half-blocks.
    TronicCornersShadesOnly: Boolean;

    // Optional UI progress reporting (assigned by GUI).
    OnProgress: TProgressProc;
    // Optional cancel flag (set by GUI). If assigned and True, conversion should stop.
    CancelFlag: PBoolean;

    // Optional debug output (GUI can pass a pointer to collect stats in TronicShade mode).
    TronicReport: PTronicRenderReport;

    // Export-only high-quality mode selector.
    // 0 = off (use normal conversion settings)
    // 1..N = enable heavier export pipeline in the GUI (mainform.pas)
    HQMode: Integer;

    // HQ supersampling factor for building the 8x16 cell sample tile.
    // 1 = classic center-sample per output pixel (fast)
    // 2 = 2x2 supersample per output pixel (slow, higher quality)
    // 3 = 3x3 supersample per output pixel (very slow)
    HQSuperSample: Integer;

    // HQ unsharp/micro-contrast amount applied to the 8x16 target tile (0..1 typical).
    // 0 disables. Values around 0.10..0.20 usually sharpen details without strong halos.
    HQSharpAmount: Double;
  end;

const
  // BIN files are 80 columns wide.
  COLS = 80;

  // CP437 block/shade helpers (used internally + by preview glyph mapping).
  CH_FULL  = 219; // █
  CH_LOW   = 220; // ▄
  CH_LEFT  = 221; // ▌
  CH_RIGHT = 222; // ▐
  CH_UP    = 223; // ▀

  // Compatibility aliases used by some render paths.
  // (Historically these were named CH_HALF*; keep them for older code.)
  CH_HALFDN    = CH_LOW;
  CH_HALFLEFT  = CH_LEFT;
  CH_HALFRIGHT = CH_RIGHT;
  CH_HALFUP    = CH_UP;

  CH_SPACE = 32;  // ' '
  CH_LIGHT = 176; // ░
  CH_MED   = 177; // ▒
  CH_DARK  = 178; // ▓

  // Prefer half/side blocks when contrast is high (hybrid mode).
  HIRES_CONTRAST_TH = 8000;

function RGB(R, G, B: Byte): TRGB; inline;
function ClampByte(v: Integer): Byte;
procedure SwapInt(var a, b: Integer); inline;

function FPColorToRGB(const C: TFPColor): TRGB; inline;

function NormalizeRectLocal(const R: TRect): TRect; inline;
function ClampRectToImage(const R: TRect; W, H: Integer): TRect;

implementation

procedure SwapInt(var a, b: Integer); inline;
var t: Integer;
begin
  t := a; a := b; b := t;
end;

function RGB(r, g, b: Byte): TRGB; inline;
begin
  Result.R := r; Result.G := g; Result.B := b;
end;

function ClampByte(v: Integer): Byte;
begin
  if v < 0 then Exit(0);
  if v > 255 then Exit(255);
  Result := Byte(v);
end;

function FPColorToRGB(const C: TFPColor): TRGB; inline;
begin
  Result.R := C.red   shr 8;
  Result.G := C.green shr 8;
  Result.B := C.blue  shr 8;
end;

function NormalizeRectLocal(const R: TRect): TRect; inline;
begin
  Result := R;
  if Result.Left > Result.Right then SwapInt(Result.Left, Result.Right);
  if Result.Top > Result.Bottom then SwapInt(Result.Top, Result.Bottom);
end;

function ClampRectToImage(const R: TRect; W, H: Integer): TRect;
begin
  Result := NormalizeRectLocal(R);
  if Result.Left < 0 then Result.Left := 0;
  if Result.Top < 0 then Result.Top := 0;
  if Result.Right > W then Result.Right := W;
  if Result.Bottom > H then Result.Bottom := H;
  if Result.Right <= Result.Left then Result.Right := Min(W, Result.Left + 1);
  if Result.Bottom <= Result.Top then Result.Bottom := Min(H, Result.Top + 1);
end;


end.