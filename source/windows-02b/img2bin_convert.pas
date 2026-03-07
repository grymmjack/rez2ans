unit img2bin_convert;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Types, FPImage,
  img2bin_types, img2bin_patchlib, img2bin_gradients, img2bin_colorbook;



procedure ConvertImageToCells(
  const Img: TFPCustomImage;
  const Opt: TConvertOptions;
  out OutRows: Integer;
  out Cells: TCellArray
);

implementation
uses
  img2bin_palette,
  img2bin_dosfont,
  img2bin_shaderlib,
  img2bin_tronicshade;


// Map a sampled/preview RGB through the pre-match palette stage.
// If Opt.PreMatchPalette is loaded (2..256 colors), it is used; otherwise
// the selected ANSI16 palette (Opt.Palette) is used.
function PreMatchMapColor(const cIn: TRGB; const Opt: TConvertOptions; ix, iy: Integer): TRGB; inline;
const
  // 4x4 Bayer matrix (0..15). Standard ordering.
  Bayer4: array[0..3,0..3] of Byte = (
    ( 0,  8,  2, 10),
    (12,  4, 14,  6),
    ( 3, 11,  1,  9),
    (15,  7, 13,  5)
  );
var
  i: Integer;
  v: Integer;
  delta: Integer;
  amp: Double;
  sPct: Integer;
begin
  Result := cIn;
  if not Opt.PaletteMatch then Exit;

  // Ordered (Bayer 4x4) dither for CUSTOM pre-match palettes only.
  // This improves perceived gradients when remapping PNG colors to small palettes.
  if (Length(Opt.PreMatchPalette) >= 2) then
  begin
    // User-controlled strength (0..100). 0 disables ordered dithering.
    sPct := EnsureRange(Opt.PreMatchBayerStrength, 0, 100);
    if sPct > 0 then
    begin
      // Map to a practical +/- brightness bump (0..96 typical)
      amp := (sPct / 100.0) * 96.0;
      v := Bayer4[iy and 3, ix and 3]; // 0..15
      delta := Round(((v - 7.5) / 16.0) * amp); // roughly +/- (amp/2)
      Result.R := ClampByte(Integer(Result.R) + delta);
      Result.G := ClampByte(Integer(Result.G) + delta);
      Result.B := ClampByte(Integer(Result.B) + delta);
    end;
  end;

  if Length(Opt.PreMatchPalette) >= 2 then
  begin
    i := NearestInRGBPalette(Result, Opt.PreMatchPalette);
    if (i >= 0) and (i < Length(Opt.PreMatchPalette)) then
      Result := Opt.PreMatchPalette[i];
  end
  else
  begin
    i := NearestAnsi16(Result, Opt.Palette);
    Result := Palette16(Opt.Palette, i);
  end;
end;





type
  // Fixed-size helper used by two-cluster FG/BG guessing.
  TByte128 = array[0..127] of Byte;

// TronicShade post-pass edge texturing (character-only, operates on the final cells)
procedure TronicPostEdgeShade(var Cells: TCellArray; cols, rows: Integer; const Opt: TConvertOptions);
var
  x, y, idx, nidx: Integer;
  bg0, bgN: Byte;
  fg0, fgN, bestOther: Byte;
  d, bestD: Integer;
  edgeCount: Integer;
  mixApprox: Integer;
  effT: Integer;
  forceShade: Boolean;
  ch: Byte;
begin
  if not Opt.TronicEdgeShadeEnabled then Exit;
  // Post-pass: convert remaining half-block boundaries into shade texture.
  for y := 0 to rows-1 do
  begin
    for x := 0 to cols-1 do
    begin
      idx := y*cols + x;
      fg0 := Cells[idx].Attr and $0F;
      bg0 := (Cells[idx].Attr shr 4) and $0F;
      if not Opt.Ice then bg0 := bg0 and $07;
      bestOther := bg0; bestD := 0; edgeCount := 0;
      // left
      if x > 0 then
      begin
        nidx := idx - 1;
        fgN := Cells[nidx].Attr and $0F;
        bgN := (Cells[nidx].Attr shr 4) and $0F; if not Opt.Ice then bgN := bgN and $07;
        if (bgN <> bg0) or (fgN <> fg0) then
        begin
          Inc(edgeCount);
          // Prefer the most contrasting *palette index* change (FG or BG), not strict RGB matching.
          if bgN <> bg0 then
          begin
            d := PalDist2(Palette16(Opt.Palette, bg0), Palette16(Opt.Palette, bgN));
            if d > bestD then begin bestD := d; bestOther := bgN; end;
          end;
          if fgN <> fg0 then
          begin
            d := PalDist2(Palette16(Opt.Palette, fg0), Palette16(Opt.Palette, fgN));
            if d > bestD then begin bestD := d; bestOther := fgN; end;
          end;
        end;
      end;
      // right
      if x < cols-1 then
      begin
        nidx := idx + 1;
        fgN := Cells[nidx].Attr and $0F;
        bgN := (Cells[nidx].Attr shr 4) and $0F; if not Opt.Ice then bgN := bgN and $07;
        if (bgN <> bg0) or (fgN <> fg0) then
        begin
          Inc(edgeCount);
          if bgN <> bg0 then
          begin
            d := PalDist2(Palette16(Opt.Palette, bg0), Palette16(Opt.Palette, bgN));
            if d > bestD then begin bestD := d; bestOther := bgN; end;
          end;
          if fgN <> fg0 then
          begin
            d := PalDist2(Palette16(Opt.Palette, fg0), Palette16(Opt.Palette, fgN));
            if d > bestD then begin bestD := d; bestOther := fgN; end;
          end;
        end;
      end;
      // up
      if y > 0 then
      begin
        nidx := idx - cols;
        fgN := Cells[nidx].Attr and $0F;
        bgN := (Cells[nidx].Attr shr 4) and $0F; if not Opt.Ice then bgN := bgN and $07;
        if (bgN <> bg0) or (fgN <> fg0) then
        begin
          Inc(edgeCount);
          if bgN <> bg0 then
          begin
            d := PalDist2(Palette16(Opt.Palette, bg0), Palette16(Opt.Palette, bgN));
            if d > bestD then begin bestD := d; bestOther := bgN; end;
          end;
          if fgN <> fg0 then
          begin
            d := PalDist2(Palette16(Opt.Palette, fg0), Palette16(Opt.Palette, fgN));
            if d > bestD then begin bestD := d; bestOther := fgN; end;
          end;
        end;
      end;
      // down
      if y < rows-1 then
      begin
        nidx := idx + cols;
        fgN := Cells[nidx].Attr and $0F;
        bgN := (Cells[nidx].Attr shr 4) and $0F; if not Opt.Ice then bgN := bgN and $07;
        if (bgN <> bg0) or (fgN <> fg0) then
        begin
          Inc(edgeCount);
          if bgN <> bg0 then
          begin
            d := PalDist2(Palette16(Opt.Palette, bg0), Palette16(Opt.Palette, bgN));
            if d > bestD then begin bestD := d; bestOther := bgN; end;
          end;
          if fgN <> fg0 then
          begin
            d := PalDist2(Palette16(Opt.Palette, fg0), Palette16(Opt.Palette, fgN));
            if d > bestD then begin bestD := d; bestOther := fgN; end;
          end;
        end;
      end;

      if edgeCount > 0 then
      begin
        // If we still ended up with a splitter, force a shade glyph instead.
        
// Decide whether to replace half-blocks with shade ramps (░▒▓).
// We approximate "mix ratio" using how many neighbor directions differ in color.
case edgeCount of
  0, 1: mixApprox := 0;
  2: mixApprox := 50;
  3: mixApprox := 75;
else
  mixApprox := 100;
end;

effT := Opt.TronicBlockThreshold;
// ShadeWeight slightly increases the tendency to shade (0..200 => +0..10).
effT := effT + (Opt.TronicShadeWeight div 20);
if effT > 50 then effT := 50;

forceShade := False;
if Opt.TronicCornersShadesOnly and (edgeCount >= 3) then
  forceShade := True
else if (mixApprox > effT) and (mixApprox < (100 - effT)) then
  forceShade := True;

case Cells[idx].Ch of
          CH_HALFUP, CH_HALFDN, CH_HALFLEFT, CH_HALFRIGHT:
          begin
            if not forceShade then
            begin
              // keep original half-block
            end
            else
            begin
            // Choose a shade glyph based on the approximate mix, with ShadeWeight bias.
            if mixApprox < 34 then ch := CH_LIGHT
            else if mixApprox < 67 then ch := CH_MED
            else ch := CH_DARK;

            // ShadeWeight bias (-2..+2): higher => darker, lower => lighter.
            d := (Opt.TronicShadeWeight - 100) div 50;
            if d < -2 then d := -2 else if d > 2 then d := 2;
            case ch of
              CH_LIGHT:
                if d >= 1 then ch := CH_MED;
              CH_MED:
                if d <= -1 then ch := CH_LIGHT
                else if d >= 1 then ch := CH_DARK;
              CH_DARK:
                if d <= -1 then ch := CH_MED;
            end;

            Cells[idx].Ch := ch;
            // Keep the current FG and use the most contrasting neighbor palette index
            // as the other color. (This responds to *overall* color changes, FG or BG.)
            if (not Opt.Ice) and (bestOther > 7) then
              // In 8-bg ANSI, only BG is limited; keep BG and move the contrasting color to FG.
              Cells[idx].Attr := AttrByte(bestOther, bg0, Opt.Ice)
            else
              Cells[idx].Attr := AttrByte(fg0, bestOther, Opt.Ice);
            end;
          end;
        end;
      end;
    end;
  end;
end;


// Forward declarations (FPC requires routines to be declared before first use)
function TransformRGB(c: TRGB; Gamma, Contrast, Saturation, Brightness: Double): TRGB; forward;
function AvgRGBWindowCenteredMapped(
  const Img: TFPCustomImage;
  sx, sy, gridW, gridH: Integer;
  winX, winY: Integer;
  const SrcRect: TRect
): TRGB; forward;

// --- Hint post-pass ---------------------------------------------------------

function RGBDist2(const a, b: TRGB): Int64; inline;
var dr, dg, db: Int64;
begin
  dr := Int64(a.R) - Int64(b.R);
  dg := Int64(a.G) - Int64(b.G);
  db := Int64(a.B) - Int64(b.B);
  Result := dr*dr + dg*dg + db*db;
end;

procedure ApplyHintsPostFix(
  const Img: TFPCustomImage;
  const SrcRect: TRect;
  const rows: Integer;
  const Opt: TConvertOptions;
  var Cells: TCellArray
);
var
  x, y, idx: Integer;
  cCell, cHint: TRGB;
  iHint: Integer;
  bestPct, pct: Integer;
  bestIdx: Integer;
  d2: Int64;
  tol2: Int64;
  fg, bg: Integer;
  dFG, dBG: Int64;
begin
  if (rows <= 0) or (Length(Cells) = 0) then Exit;
  if not Opt.HintPostFix then Exit;
  if Length(Opt.ColorHints) = 0 then Exit;

  // Scale percent-match against tolerance.
  // Treat tolerance as a per-channel radius; max squared distance is 3*t^2.
  if Opt.HintTolerance <= 0 then Exit;
  tol2 := Int64(Opt.HintTolerance) * Int64(Opt.HintTolerance) * 3;
  if tol2 <= 0 then tol2 := 1;

  for y := 0 to rows - 1 do
    for x := 0 to COLS - 1 do
    begin
      idx := y * COLS + x;
      if (idx < 0) or (idx > High(Cells)) then Continue;

      // Sample the *source* average color for this cell (same spatial basis
      // as the solver), then apply the same pre-processing transforms.
      cCell := AvgRGBWindowCenteredMapped(Img, x, y, COLS, rows, Opt.WinX, Opt.WinY, SrcRect);
      cCell := TransformRGB(cCell, Opt.Gamma, Opt.Contrast, Opt.Saturation, Opt.Brightness);

      bestPct := -1;
      bestIdx := -1;

      for iHint := 0 to High(Opt.ColorHints) do
      begin
        cHint := TransformRGB(Opt.ColorHints[iHint].Src, Opt.Gamma, Opt.Contrast, Opt.Saturation, Opt.Brightness);
        d2 := RGBDist2(cCell, cHint);
        pct := 100 - Integer((d2 * 100) div tol2);
        if pct > bestPct then
        begin
          bestPct := pct;
          bestIdx := Opt.ColorHints[iHint].TargetIdx;
        end;
      end;

      if (bestIdx < 0) or (bestIdx > 15) then Continue;
      if bestPct < EnsureRange(Opt.HintPostFixPct, 0, 100) then Continue;

      // Decide whether FG or BG should be snapped.
      fg := Cells[idx].Attr and $0F;
      bg := (Cells[idx].Attr shr 4) and $0F;

      // If not iCE, BG is limited to 0..7.
      if (not Opt.Ice) and (bestIdx > 7) then
      begin
        fg := bestIdx;
      end
      else
      begin
        // Choose the component (FG/BG) that is closer to the target ANSI entry.
        cHint := Palette16(Opt.Palette, bestIdx);
        dFG := RGBDist2(Palette16(Opt.Palette, fg), cHint);
        dBG := RGBDist2(Palette16(Opt.Palette, bg), cHint);
        if dBG < dFG then
          bg := bestIdx
        else
          fg := bestIdx;
      end;

      Cells[idx].Attr := Byte(((bg and $0F) shl 4) or (fg and $0F));
    end;
end;

type
  TByteArray = array of Byte;
  TBool256 = array[0..255] of Boolean;

  // Linear-light RGB (0..1) used by the DOSBox viewer-model matcher.
  TLRGB = record
    R, G, B: Double;
  end;

  TLRGBTile = array[0..127] of TLRGB;
  TPalLin = array[0..15] of TLRGB;

  TGlyphInfo = record
    Ch: Byte;
    Rows: array[0..15] of Byte;
    OnCount: Integer;
  end;

  TGlyphInfoArray = array of TGlyphInfo;

var
  GGlyphCache: array[TGlyphSetKind] of TGlyphInfoArray;
  GGlyphCacheInit: array[TGlyphSetKind] of Boolean;

  // sRGB(0..255) -> linear(0..1) LUT (gamma 2.2). Used when Opt.DosBoxModel is on.
  GLin22: array[0..255] of Double;
  GLin22Init: Boolean = False;

const
  // Subpixel width for 80 columns (2 subpixels per column).
  SUBW = COLS * 2;

function AttrByte(FG, BG: Byte; Ice: Boolean): Byte; inline;
begin
  if not Ice then BG := BG and $07;
  Result := ((BG and $0F) shl 4) or (FG and $0F);
end;

function Blend(const fg, bg: TRGB; alpha: Double): TRGB; inline;
var r,g,b: Double;
begin
  r := alpha*fg.R + (1.0-alpha)*bg.R;
  g := alpha*fg.G + (1.0-alpha)*bg.G;
  b := alpha*fg.B + (1.0-alpha)*bg.B;
  Result.R := ClampByte(Round(r));
  Result.G := ClampByte(Round(g));
  Result.B := ClampByte(Round(b));
end;

function ToLin(v: Byte): Double; inline;
begin
  // Approx sRGB -> linear
  Result := Power(v / 255.0, 2.2);
end;

function ToSRGB(x: Double): Byte; inline;
begin
  if x < 0 then x := 0;
  if x > 1 then x := 1;
  // Approx linear -> sRGB
  Result := ClampByte(Round(Power(x, 1.0 / 2.2) * 255.0));
end;

function BlendLinear(const fg, bg: TRGB; alpha: Double): TRGB; inline;
var r,g,b: Double;
begin
  r := alpha*ToLin(fg.R) + (1.0-alpha)*ToLin(bg.R);
  g := alpha*ToLin(fg.G) + (1.0-alpha)*ToLin(bg.G);
  b := alpha*ToLin(fg.B) + (1.0-alpha)*ToLin(bg.B);
  Result.R := ToSRGB(r);
  Result.G := ToSRGB(g);
  Result.B := ToSRGB(b);
end;


// --- Linear-light helpers (TronicShade quality) ---------------------------

// Forward declaration (used by helpers below).
procedure EnsureLin22; forward;
function LumaLin255(const c: TRGB): Integer; inline;
var
  r, g, b, y: Double;
begin
  // Rec.709 luma in *linear* light, mapped to 0..255.
  EnsureLin22;
  r := GLin22[c.R];
  g := GLin22[c.G];
  b := GLin22[c.B];
  y := 0.2126*r + 0.7152*g + 0.0722*b;
  Result := EnsureRange(Round(y * 255.0), 0, 255);
end;

function DistLin22_2(const a, b: TRGB): Integer; inline;
var
  dr, dg, db: Double;
begin
  // Squared distance in linear sRGB (gamma~2.2), scaled up.
  EnsureLin22;
  dr := GLin22[a.R] - GLin22[b.R];
  dg := GLin22[a.G] - GLin22[b.G];
  db := GLin22[a.B] - GLin22[b.B];
  Result := Round((dr*dr + dg*dg + db*db) * 1000000.0);
end;

// --- DOSBox viewer-model matcher ------------------------------------------

procedure EnsureLin22; inline;
var i: Integer;
begin
  if GLin22Init then Exit;
  for i := 0 to 255 do
    GLin22[i] := Power(i / 255.0, 2.2);
  GLin22Init := True;
end;

function RGBToLin22(const c: TRGB): TLRGB; inline;
begin
  EnsureLin22;
  Result.R := GLin22[c.R];
  Result.G := GLin22[c.G];
  Result.B := GLin22[c.B];
end;

procedure BuildTileVM_HBlur(const samples: array of TRGB; out dst: TLRGBTile);
var
  lin: TLRGBTile;
  idx, py, px: Integer;
  lidx, ridx: Integer;
begin
  // 1) sRGB -> linear
  for idx := 0 to 127 do
    lin[idx] := RGBToLin22(samples[idx]);

  // 2) 1px horizontal blur (clamped edges). Kernel [1 2 1]/4.
  for py := 0 to 15 do
    for px := 0 to 7 do
    begin
      idx := py*8 + px;
      lidx := py*8 + IfThen(px>0, px-1, px);
      ridx := py*8 + IfThen(px<7, px+1, px);
      dst[idx].R := (lin[lidx].R + 2.0*lin[idx].R + lin[ridx].R) * 0.25;
      dst[idx].G := (lin[lidx].G + 2.0*lin[idx].G + lin[ridx].G) * 0.25;
      dst[idx].B := (lin[lidx].B + 2.0*lin[idx].B + lin[ridx].B) * 0.25;
    end;
end;

function TileErrVM_HBlur(const g: TGlyphInfo; fgIdx, bgIdx: Byte; const palLin: TPalLin; const srcVM: TLRGBTile): Int64;
var
  px, py: Integer;
  row: Byte;
  idx: Integer;
  b0, bL, bR: Boolean;
  c, l, r: TLRGB;
  br1, bg, bb: Double;
  dr, dg, db: Double;
  e: Double;
begin
  e := 0.0;
  for py := 0 to 15 do
  begin
    row := g.Rows[py];
    for px := 0 to 7 do
    begin
      idx := py*8 + px;

      b0 := (row and (1 shl (7-px))) <> 0;
      if b0 then c := palLin[fgIdx] else c := palLin[bgIdx];

      if px = 0 then l := c
      else
      begin
        bL := (row and (1 shl (7-(px-1)))) <> 0;
        if bL then l := palLin[fgIdx] else l := palLin[bgIdx];
      end;

      if px = 7 then r := c
      else
      begin
        bR := (row and (1 shl (7-(px+1)))) <> 0;
        if bR then r := palLin[fgIdx] else r := palLin[bgIdx];
      end;

      br1 := (l.R + 2.0*c.R + r.R) * 0.25;
      bg := (l.G + 2.0*c.G + r.G) * 0.25;
      bb := (l.B + 2.0*c.B + r.B) * 0.25;

      dr := srcVM[idx].R - br1;
      dg := srcVM[idx].G - bg;
      db := srcVM[idx].B - bb;
      e := e + dr*dr + dg*dg + db*db;
    end;
  end;
  Result := Round(e * 1000000.0);
end;

// --- Color refinement (AutoSwatch++) ---------------------------------------
//
// After a glyph has been chosen (shape match), refine FG/BG colors while
// keeping the glyph locked. This improves hue accuracy (especially skin,
// reds/blues) without changing the shapes you like.
//
// We evaluate a compact candidate set:
//   * pairs learned from the shader library for this glyph (if enabled)
//   * top-N nearest palette colors for the glyph's "on" and "off" pixel averages
//   * a 2nd pass exploring palette-neighbors around the current best pair
//
// Scoring uses the same tile matcher as the main loop:
//   * DOSBox model: rendered tile with horizontal blur in linear-light
//   * otherwise: per-pixel PalDist2 with optional ShadeBlend + BlockStrength bias

type
  TByteDyn = array of Byte;

function TopNPaletteIdx(const target: TRGB; N, MaxIdx: Integer; const pal: array of TRGB): TByteDyn;
var
  i, j, bestI: Integer;
  used: array[0..15] of Boolean;
  bestD, d: Integer;
begin
  Result := nil;
  if N < 1 then N := 1;
  if N > (MaxIdx + 1) then N := MaxIdx + 1;
  SetLength(Result, 0);
  FillChar(used, SizeOf(used), 0);
  for j := 0 to N - 1 do
  begin
    bestI := -1;
    bestD := High(Integer);
    for i := 0 to MaxIdx do
    begin
      if used[i] then Continue;
      d := PalDist2Hinted(target, pal[i], i);
      if d < bestD then
      begin
        bestD := d;
        bestI := i;
      end;
    end;
    if bestI < 0 then Break;
    used[bestI] := True;
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := Byte(bestI);
  end;
end;

function NeighborPaletteIdx(const idx: Byte; N, MaxIdx: Integer; const pal: array of TRGB): TByteDyn;
begin
  Result := TopNPaletteIdx(pal[idx], N, MaxIdx, pal);
end;

// --- TronicShade hook (style priors) ---------------------------------------

var
  gTronicEnabled: Boolean = False;
  gTronicKey3, gTronicKey5, gTronicKey10: Integer;
  gTronicHasLeft, gTronicHasTop: Boolean;
  gTronicLeftAttr, gTronicTopAttr: Byte;
  gTronicTargetY: Integer;
  // When true, this cell sits on a palette/color edge (left/right/up/down).
  // Tronicshade can then force shade/half-block texture to smooth ANSI block transitions.
  gTronicEdge: Boolean;
  gTronicEdgeFG, gTronicEdgeBG: Byte; // preferred boundary colors (palette indexes)
  gTronicEdgeDir: Byte; // 0=none,1=left,2=right,3=up,4=down
  gTronicEdgeCount: Byte; // number of differing neighbors (L/R/U/D)
  gTronicEdgeMixPct: Byte; // 0..100: how mixed the two edge colors are inside this cell

const
  TRONIC_ERR_SCALE = 9000; // scales log-prob bonus into the pixel-error space

const
  TRONIC_SCALE = 9000.0; // converts log-prob bonus into error units (tunable)

function PairErrLockedGlyph(const g: TGlyphInfo; fgIdx, bgIdx: Byte;
  const pal: array of TRGB; const palLin: TPalLin; const srcVM: TLRGBTile;
  useVM: Boolean; const Opt: TConvertOptions; const avgAll: TRGB; baseBG: Byte;
  const shaderParams: TShaderParams; const samples: array of TRGB): Int64;
var
  px, py: Integer;
  row: Byte;
  bitOn: Boolean;
  w, alpha: Double;
  blendCol: TRGB;
  baseErr, baseAbs, maxBias, bias: Int64;

  function RGBLuma(const c: TRGB): Integer; inline;
  begin
    Result := (77*Integer(c.R) + 150*Integer(c.G) + 29*Integer(c.B)) shr 8;
  end;

  function LumaDist2(const a, b: TRGB): Integer; inline;
  var
    da: Integer;
  begin
    da := RGBLuma(a) - RGBLuma(b);
    Result := da * da;
  end;

  function SampleDist2(const a: TRGB; const palCol: TRGB; palIdx: Integer): Integer; inline;
  begin
    // In TronicShade mode we optionally score primarily by luma so glyph/structure
    // can win even when hues differ ("chars match" even if colors don't).
    if (Opt.Mode = rmTronicShade) and ((Opt.TronicColorMetric = tcmLumaOnly) or Opt.TronicLumaOnly) then
      Result := PalLumaDist2Hinted(a, palCol, palIdx)
    else
      Result := PalDist2Hinted(a, palCol, palIdx);
  end;
begin
  if useVM then
    Result := TileErrVM_HBlur(g, fgIdx, bgIdx, palLin, srcVM)
  else
  begin
    Result := 0;
    for py := 0 to 15 do
    begin
      row := g.Rows[py];
      for px := 0 to 7 do
      begin
        bitOn := (row and (1 shl (7-px))) <> 0;
        if bitOn then
          Inc(Result, SampleDist2(samples[py*8 + px], pal[fgIdx], fgIdx))
        else
          Inc(Result, SampleDist2(samples[py*8 + px], pal[bgIdx], bgIdx));
      end;
    end;

    // Shade-blend perceptual assist for ░▒▓ when not using the VM tile matcher
    if (Opt.ShadeBlend > 0) and ((g.Ch = CH_LIGHT) or (g.Ch = CH_MED) or (g.Ch = CH_DARK)) and
       (g.OnCount > 0) and (g.OnCount < 128) then
    begin
      w := Opt.ShadeBlend;
      // Use nominal coverage for shade blocks; ANSI artists rely on these being ~25/50/75%.
      case g.Ch of
        CH_LIGHT: alpha := 0.25;
        CH_MED:   alpha := 0.50;
        CH_DARK:  alpha := 0.75;
      else
        alpha := g.OnCount / 128.0;
      end;
      blendCol := BlendLinear(pal[fgIdx], pal[bgIdx], alpha);
      Result := Round((1.0 - w) * Result + w * (Int64(128) * PalDist2(avgAll, blendCol)));
    end;
  end;

  // Block-in bias: keep background close to the base cell color (helps outlines)
  if shaderParams.BlockStrength > 0 then
    Inc(Result, Round(shaderParams.BlockStrength * 16.0 * PalDist2(pal[bgIdx], pal[baseBG])));

  // Tone correction (luma-fit) penalty
  // Helps overall brightness/tone even when hues differ.
  // - In TronicShade, controlled by TronicToneCorrection / TronicDiffusionModel.
  // - In regular modes, controlled by CellToneCorrection / CellDiffusionModel.
  if (Opt.Mode = rmTronicShade) and ((Opt.TronicToneCorrection > 0) or
     (Opt.TronicDiffusionModel in [tdmFloydSteinberg, tdmJJN, tdmAtkinson, tdmSierraLite])) then
  begin
    // If diffusion is enabled but ToneCorrection is 0, use a gentle default.
    w := Opt.TronicToneCorrection / 100.0;
    if (w <= 0) and (Opt.TronicDiffusionModel in [tdmFloydSteinberg, tdmJJN, tdmAtkinson, tdmSierraLite]) then w := 0.35;
    if w > 0 then
    begin
      case g.Ch of
        CH_LIGHT: alpha := 0.25;
        CH_MED:   alpha := 0.50;
        CH_DARK:  alpha := 0.75;
      else
        alpha := g.OnCount / 128.0;
      end;
            // candidate blended luma
      px := (77*Integer(pal[fgIdx].R) + 150*Integer(pal[fgIdx].G) + 29*Integer(pal[fgIdx].B)) shr 8;
      py := (77*Integer(pal[bgIdx].R) + 150*Integer(pal[bgIdx].G) + 29*Integer(pal[bgIdx].B)) shr 8;
      // blend
      row := EnsureRange(Round(alpha * px + (1.0 - alpha) * py), 0, 255);
      // penalty scales into the same space as pixel-error sums
      Inc(Result, Round((24.0 * w) * Sqr(gTronicTargetY - Integer(row))));
    end;
  end
  else if (Opt.Mode <> rmTronicShade) and ((Opt.CellToneCorrection > 0) or
     (Opt.CellDiffusionModel in [cdmFloydSteinberg, cdmJJN, cdmAtkinson, cdmSierraLite])) then
  begin
    w := Opt.CellToneCorrection / 100.0;
    if (w <= 0) and (Opt.CellDiffusionModel in [cdmFloydSteinberg, cdmJJN, cdmAtkinson, cdmSierraLite]) then w := 0.35;
    if w > 0 then
    begin
      case g.Ch of

        CH_LIGHT: alpha := 0.25;

        CH_MED:   alpha := 0.50;

        CH_DARK:  alpha := 0.75;

      else

        alpha := g.OnCount / 128.0;

      end;
      px := (77*Integer(pal[fgIdx].R) + 150*Integer(pal[fgIdx].G) + 29*Integer(pal[fgIdx].B)) shr 8;
      py := (77*Integer(pal[bgIdx].R) + 150*Integer(pal[bgIdx].G) + 29*Integer(pal[bgIdx].B)) shr 8;
      row := EnsureRange(Round(alpha * px + (1.0 - alpha) * py), 0, 255);
      Inc(Result, Round((24.0 * w) * Sqr(gTronicTargetY - Integer(row))));
    end;
  end;

  // ---------------------------------------------------------------------
  // Tronicshade edge texture force (ANSI block transitions)
  // If this cell lies on a palette edge (L/R/U/D color change), strongly
  // prefer shade blocks / half blocks and encourage the two boundary colors.
  if (Opt.Mode = rmTronicShade) and Opt.TronicEdgeShadeEnabled and gTronicEdge then
  begin
    // Prefer the two edge colors (either order). BG is usually 0..7 in ANSI.
    if not (((fgIdx = gTronicEdgeFG) and (bgIdx = gTronicEdgeBG)) or
            ((fgIdx = gTronicEdgeBG) and (bgIdx = gTronicEdgeFG))) then
      Inc(Result, 2500);

    // Force use of shading/block glyphs at edges.
    // IMPORTANT: prefer ░▒▓ (shade texture) over half-block splitters.
    // Half-blocks are still useful for clean 1-direction boundaries, but
    // shades should dominate (ANSI "ramped" edges).
    case g.Ch of
      // shades: VERY strong preference at color edges.
      // We want ANSI-style "texture ramps" (░▒▓) to dominate over splitters.
      CH_LIGHT, CH_MED, CH_DARK:
        Dec(Result, 12000 + 1500 * Integer(gTronicEdgeCount));

      // full block is allowed but usually too harsh for transitions.
      CH_FULL:
        Dec(Result, 3500);

      // half blocks: only use when it's a clean single-direction boundary.
      // Otherwise, actively discourage them so shades show up.
      CH_HALFUP, CH_HALFDN, CH_HALFLEFT, CH_HALFRIGHT:
        begin
          // If the edge is internally mixed, strongly prefer texture shades over splitters.
          if gTronicEdgeMixPct >= 40 then
          begin
            Inc(Result, 8500 + 50 * Integer(gTronicEdgeMixPct));
          end
          else if (gTronicEdgeCount = 1) then
          begin
            // Clean split: allow, with a mild directional preference.
            if ((gTronicEdgeDir = 1) and (g.Ch = CH_HALFLEFT)) or
               ((gTronicEdgeDir = 2) and (g.Ch = CH_HALFRIGHT)) or
               ((gTronicEdgeDir = 3) and (g.Ch = CH_HALFUP)) or
               ((gTronicEdgeDir = 4) and (g.Ch = CH_HALFDN)) then
              Dec(Result, 450)
            else
              Inc(Result, 600);
          end
          else
          begin
            // Busy / corner edge: push HARD away from splitters.
            Inc(Result, 5200 + 800 * Integer(gTronicEdgeCount));
          end;
        end;
    else
      // Anything else: strongly discouraged at color edges.
      Inc(Result, 9000);
    end;
  end;

  // TronicShade style prior (optional)
  if gTronicEnabled and (Opt.Mode = rmTronicShade) and TronicShadeHasAny then
  begin
    // A negative log-prob bonus; more likely stylistic choices get less penalty.
    // Scale factor chosen to be a gentle bias relative to typical RGBDist2 sums.
    Result := Result - Round((TRONIC_ERR_SCALE * (Opt.TronicCharStrength / 100.0)) * TronicShadeBonus(gTronicKey3, gTronicKey5, gTronicKey10,
      g.Ch, fgIdx, bgIdx, gTronicLeftAttr, gTronicTopAttr, gTronicHasLeft, gTronicHasTop, pal));
  end;
  // User-configurable glyph biases (100=neutral)
// These let you push the converter toward (or away from) certain block glyphs.
//
// Stabilizer: the bias is clamped to a fraction of the current base error so it
// only breaks ties / near-ties instead of overpowering true pixel matching.
baseErr := Result;
bias := 0;

if Opt.ShadeBlockWeight <> 100 then
  case g.Ch of
    CH_LIGHT, CH_MED, CH_DARK: Inc(bias, Int64(100 - Opt.ShadeBlockWeight) * 120);
  end;

if (Opt.BlockUpWeight <> 100) and (g.Ch = CH_HALFUP) then
  Inc(bias, Int64(100 - Opt.BlockUpWeight) * 80);

if (Opt.BlockDownWeight <> 100) and (g.Ch = CH_HALFDN) then
  Inc(bias, Int64(100 - Opt.BlockDownWeight) * 80);

// clamp bias to keep it "stable" across images/palettes
baseAbs := baseErr;
if baseAbs < 0 then baseAbs := -baseAbs;
maxBias := baseAbs div 3;  // ~33% of base error
if maxBias < 1200 then maxBias := 1200;
if maxBias > 20000 then maxBias := 20000;

if bias > maxBias then bias := maxBias else
if bias < -maxBias then bias := -maxBias;

Result := baseErr + bias;

end;

procedure RefinePairLockedGlyph(const g: TGlyphInfo; const samples: array of TRGB;
  const pal: array of TRGB; const palLin: TPalLin; const srcVM: TLRGBTile;
  useVM: Boolean; const Opt: TConvertOptions; const shaderParams: TShaderParams;
  const avgAll: TRGB; baseBG: Byte; var fg, bg: Byte);
const
  TOPN = 6;          // palette candidates from averages
  TOPN2 = 6;         // palette neighbors around current best
  MAX_SHADER = 300;  // cap shader candidates to keep it snappy
var
  avgOn, avgOff: TRGB;
  onR, onG, onB: Int64;
  offR, offG, offB: Int64;
  denomOn, denomOff: Integer;
  px, py: Integer;
  row: Byte;
  bitOn: Boolean;
  fgList, bgList: TByteDyn;
  fgN, bgN: Integer;
  bestE, e: Int64;
  candUsed: array[0..15,0..15] of Boolean;
  fi, bi: Integer;
  maxBG: Integer;
  // shader candidates
  shaderPairs: TColorPairArray;
  spi: Integer;
  // second pass neighbor lists
  fg2, bg2: TByteDyn;
begin
  // compute per-glyph on/off averages
  onR := 0; onG := 0; onB := 0;
  offR := 0; offG := 0; offB := 0;
  for py := 0 to 15 do
  begin
    row := g.Rows[py];
    for px := 0 to 7 do
    begin
      bitOn := (row and (1 shl (7-px))) <> 0;
      if bitOn then
      begin
        Inc(onR, samples[py*8 + px].R);
        Inc(onG, samples[py*8 + px].G);
        Inc(onB, samples[py*8 + px].B);
      end
      else
      begin
        Inc(offR, samples[py*8 + px].R);
        Inc(offG, samples[py*8 + px].G);
        Inc(offB, samples[py*8 + px].B);
      end;
    end;
  end;

  denomOn := g.OnCount;
  denomOff := 128 - g.OnCount;
  if denomOn < 1 then denomOn := 1;
  if denomOff < 1 then denomOff := 1;

  avgOn.R := ClampByte(Round(onR / denomOn));
  avgOn.G := ClampByte(Round(onG / denomOn));
  avgOn.B := ClampByte(Round(onB / denomOn));

  avgOff.R := ClampByte(Round(offR / denomOff));
  avgOff.G := ClampByte(Round(offG / denomOff));
  avgOff.B := ClampByte(Round(offB / denomOff));

  maxBG := 15;
  if not Opt.Ice then maxBG := 7;

  fgList := TopNPaletteIdx(avgOn, TOPN, 15, pal);
  bgList := TopNPaletteIdx(avgOff, TOPN, maxBG, pal);

  FillChar(candUsed, SizeOf(candUsed), 0);

  bestE := PairErrLockedGlyph(g, fg, bg, pal, palLin, srcVM, useVM, Opt, avgAll, baseBG, shaderParams, samples);

  // 1) shader library candidates for this glyph
	if Opt.UseShaderLib and ShaderIsLoaded then
	begin
	  // If strict shader matching is enabled, ONLY allow glyph+color pairs that
	  // actually appeared in the imported shader art. This turns the shader
	  // library into a rendered candidate set (glyph+FG/BG), which tends to look
	  // far more "stylistically consistent".
	  ShaderGetPairsForGlyph(g.Ch, shaderPairs);
	  if Length(shaderPairs) = 0 then
	  begin
	    // In strict mode, no pairs for this glyph means: simply skip shader-lib
	    // candidates (do NOT abort the whole routine).
	    if not Opt.ShaderStrictGlyphMatch then
	      ShaderGetAllPairs(shaderPairs);
	  end;

    if Length(shaderPairs) > 0 then
    begin
      // cap to MAX_SHADER by scanning in order (newest swatches tend to be earlier already)
      for spi := 0 to High(shaderPairs) do
      begin
        if spi >= MAX_SHADER then Break;
        if shaderPairs[spi].FG > 15 then Continue;
        if shaderPairs[spi].BG > maxBG then Continue;
        if candUsed[shaderPairs[spi].FG][shaderPairs[spi].BG] then Continue;
        candUsed[shaderPairs[spi].FG][shaderPairs[spi].BG] := True;

        e := PairErrLockedGlyph(g, shaderPairs[spi].FG, shaderPairs[spi].BG, pal, palLin, srcVM, useVM, Opt, avgAll, baseBG, shaderParams, samples);
        if e < bestE then
        begin
          bestE := e;
          fg := shaderPairs[spi].FG;
          bg := shaderPairs[spi].BG;
        end;
      end;
    end;
  end;

  // 2) cross-product of top palette matches for on/off averages
  for fi := 0 to High(fgList) do
    for bi := 0 to High(bgList) do
    begin
      if candUsed[fgList[fi]][bgList[bi]] then Continue;
      candUsed[fgList[fi]][bgList[bi]] := True;

      e := PairErrLockedGlyph(g, fgList[fi], bgList[bi], pal, palLin, srcVM, useVM, Opt, avgAll, baseBG, shaderParams, samples);
      if e < bestE then
      begin
        bestE := e;
        fg := fgList[fi];
        bg := bgList[bi];
      end;
    end;

  // 3) 2nd pass: explore palette-neighbors around the current best (small hue shifts)
  fg2 := NeighborPaletteIdx(fg, TOPN2, 15, pal);
  bg2 := NeighborPaletteIdx(bg, TOPN2, maxBG, pal);

  for fi := 0 to High(fg2) do
    for bi := 0 to High(bg2) do
    begin
      if candUsed[fg2[fi]][bg2[bi]] then Continue;
      candUsed[fg2[fi]][bg2[bi]] := True;

      e := PairErrLockedGlyph(g, fg2[fi], bg2[bi], pal, palLin, srcVM, useVM, Opt, avgAll, baseBG, shaderParams, samples);
      if e < bestE then
      begin
        bestE := e;
        fg := fg2[fi];
        bg := bg2[bi];
      end;
    end;
end;

function Mix2(const a, b: TRGB): TRGB; inline;
begin
  Result.R := Byte((Integer(a.R) + Integer(b.R)) div 2);
  Result.G := Byte((Integer(a.G) + Integer(b.G)) div 2);
  Result.B := Byte((Integer(a.B) + Integer(b.B)) div 2);
end;

function Mix4(const a, b, c, d: TRGB): TRGB; inline;
begin
  Result.R := Byte((Integer(a.R)+Integer(b.R)+Integer(c.R)+Integer(d.R)) div 4);
  Result.G := Byte((Integer(a.G)+Integer(b.G)+Integer(c.G)+Integer(d.G)) div 4);
  Result.B := Byte((Integer(a.B)+Integer(b.B)+Integer(c.B)+Integer(d.B)) div 4);
end;

function ApplyGammaByte(v: Byte; Gamma: Double): Byte; inline;
var x: Double;
begin
  if (Gamma <= 0) or (Abs(Gamma - 1.0) < 1e-9) then Exit(v);
  x := v / 255.0;
  x := Power(x, 1.0 / Gamma);
  Result := ClampByte(Round(x * 255.0));
end;

function ApplyContrastByte(v: Byte; Contrast: Double): Byte; inline;
var x: Double;
begin
  if Abs(Contrast - 1.0) < 1e-9 then Exit(v);
  x := (v - 128.0) * Contrast + 128.0;
  Result := ClampByte(Round(x));
end;

function TransformRGB(c: TRGB; Gamma, Contrast, Saturation, Brightness: Double): TRGB;
var
  gray: Double;
  r,g,b: Double;
begin
  // Basic tone mapping
  Result.R := ApplyContrastByte(ApplyGammaByte(c.R, Gamma), Contrast);
  Result.G := ApplyContrastByte(ApplyGammaByte(c.G, Gamma), Contrast);
  Result.B := ApplyContrastByte(ApplyGammaByte(c.B, Gamma), Contrast);

  // Saturation
  if Abs(Saturation - 1.0) >= 1e-9 then
  begin
    gray := (Result.R + Result.G + Result.B) / 3.0;
    r := gray + (Result.R - gray) * Saturation;
    g := gray + (Result.G - gray) * Saturation;
    b := gray + (Result.B - gray) * Saturation;

    Result.R := ClampByte(Round(r));
    Result.G := ClampByte(Round(g));
    Result.B := ClampByte(Round(b));
  end;

  // Brightness (simple multiplier, like ANSIrez-style "boost all")
  if Abs(Brightness - 1.0) >= 1e-9 then
  begin
    Result.R := ClampByte(Round(Result.R * Brightness));
    Result.G := ClampByte(Round(Result.G * Brightness));
    Result.B := ClampByte(Round(Result.B * Brightness));
  end;
end;

procedure InitGlyphCache(kind: TGlyphSetKind);
const
  SHADING_ASCII = ' .,:;i1tfLCG08@#%$';
  EXTRA_ASCII = '/\|_-()[]{}<>+*=';
var
  seen: array[0..255] of Boolean;
  chars: array of Byte;
  i, y, x: Integer;
  ch: Byte;
  row: Byte;
  info: TGlyphInfo;

  procedure AddByte(b: Byte);
  var n: Integer;
  begin
    if seen[b] then Exit;
    seen[b] := True;
    n := Length(chars);
    SetLength(chars, n+1);
    chars[n] := b;
  end;

begin
  if GGlyphCacheInit[kind] then Exit;
  FillChar(seen, SizeOf(seen), 0);
  SetLength(chars, 0);

  // Always include space
  AddByte(CH_SPACE);



if kind = gsAscii then
begin
  // Printable 7-bit ASCII only (32..126); space already included above.
  for ch := 33 to 126 do
    AddByte(ch);
end
else
begin
  // Blocks + shades
  AddByte(CH_LIGHT);
  AddByte(CH_MED);
  AddByte(CH_DARK);
  AddByte(CH_FULL);
  AddByte(CH_LOW);
  AddByte(CH_UP);
  // Side half-blocks:
  // - Always include for Tronicshade-specific glyph set (gsTronic).
  // - Exclude for the ANSI Blocks modes (harder to match; can reduce stability).
  if (kind = gsTronic) or (not (kind in [gsAnsiBlocks, gsAnsiBlocksPixel])) then
  begin
    AddByte(CH_LEFT);
    AddByte(CH_RIGHT);
  end else
  begin
    AddByte(CH_LEFT);
    AddByte(CH_RIGHT);
  end;
  AddByte(254); // ■ (dense fill)

  if (kind in [gsShading, gsLines, gsFull]) and (kind <> gsTronic) then
  begin
    for i := 1 to Length(SHADING_ASCII) do
      AddByte(Ord(SHADING_ASCII[i]));
    AddByte(Ord('`'));
    AddByte(Ord(''''));
  end;

  if (kind in [gsLines, gsFull]) and (kind <> gsTronic) then
  begin
    for i := 1 to Length(EXTRA_ASCII) do
      AddByte(Ord(EXTRA_ASCII[i]));
    for ch := 179 to 218 do
      AddByte(ch);
  end;

  if kind = gsFull then
  begin
    for ch := 33 to 255 do
      if ch <> 127 then
        AddByte(ch);
  end;
  end;

  SetLength(GGlyphCache[kind], Length(chars));
  for i := 0 to High(chars) do
  begin
    ch := chars[i];
    info.Ch := ch;
    info.OnCount := 0;
    for y := 0 to 15 do
    begin
      row := DOSFontModernDOS8x16[ch, y];
      info.Rows[y] := row;
      for x := 0 to 7 do
        if (row and (1 shl (7-x))) <> 0 then
          Inc(info.OnCount);
    end;
    GGlyphCache[kind][i] := info;
  end;

  GGlyphCacheInit[kind] := True;
end;

function FilterGlyphsByAllowed(const Base: TGlyphInfoArray; const Allowed: TBool256): TGlyphInfoArray;
var
  i, n: Integer;
begin
  SetLength(Result, 0);
  if Length(Base) = 0 then Exit;
  // First count
  n := 0;
  for i := 0 to High(Base) do
    if Allowed[Base[i].Ch] then
      Inc(n);
  SetLength(Result, n);
  n := 0;
  for i := 0 to High(Base) do
    if Allowed[Base[i].Ch] then
    begin
      Result[n] := Base[i];
      Inc(n);
    end;
end;

function SampleRGBBilinear(const Img: TFPCustomImage; const SrcR: TRect; fx, fy: Double): TRGB;
var
  x0, y0, x1, y1: Integer;
  tx, ty: Double;
  c00, c10, c01, c11: TRGB;
  w00, w10, w01, w11: Double;
  r, g, b: Double;
  sx, sy: Double;
begin
  // fx,fy are in 0..1 relative to SrcR
  sx := SrcR.Left + fx * (SrcR.Right - SrcR.Left - 1);
  sy := SrcR.Top + fy * (SrcR.Bottom - SrcR.Top - 1);

  x0 := Floor(sx); y0 := Floor(sy);
  tx := sx - x0;
  ty := sy - y0;

  x1 := x0 + 1; y1 := y0 + 1;
  if x0 < SrcR.Left then x0 := SrcR.Left;
  if y0 < SrcR.Top then y0 := SrcR.Top;
  if x1 >= SrcR.Right then x1 := SrcR.Right - 1;
  if y1 >= SrcR.Bottom then y1 := SrcR.Bottom - 1;

  c00 := FPColorToRGB(Img.Colors[x0, y0]);
  c10 := FPColorToRGB(Img.Colors[x1, y0]);
  c01 := FPColorToRGB(Img.Colors[x0, y1]);
  c11 := FPColorToRGB(Img.Colors[x1, y1]);

  w00 := (1-tx) * (1-ty);
  w10 := tx * (1-ty);
  w01 := (1-tx) * ty;
  w11 := tx * ty;

  r := c00.R*w00 + c10.R*w10 + c01.R*w01 + c11.R*w11;
  g := c00.G*w00 + c10.G*w10 + c01.G*w01 + c11.G*w11;
  b := c00.B*w00 + c10.B*w10 + c01.B*w01 + c11.B*w11;

  Result.R := ClampByte(Round(r));
  Result.G := ClampByte(Round(g));
  Result.B := ClampByte(Round(b));
end;


function SampleRGBBilinearHQ(const Img: TFPCustomImage; const SrcR: TRect; fx, fy: Double): TRGB;
var
  x0, y0, x1, y1: Integer;
  tx, ty: Double;
  c00, c10, c01, c11: TFPColor;
  w00, w10, w01, w11: Double;
  rP, gP, bP, aP: Double;
  sx, sy: Double;

  function Chan8(const v16: Word): Byte; inline;
  begin
    Result := Byte(v16 shr 8);
  end;

  procedure AddWeightedPremul(const c: TFPColor; w: Double);
  var
    a: Double;
    rL, gL, bL: Double;
    rb, gb, bb: Byte;
  begin
    // Alpha in 0..1
    a := Chan8(c.alpha) / 255.0;
    rb := Chan8(c.red);
    gb := Chan8(c.green);
    bb := Chan8(c.blue);

    // Convert to linear light (gamma 2.2 approximation), then premultiply.
    rL := ToLin(rb) * a;
    gL := ToLin(gb) * a;
    bL := ToLin(bb) * a;

    rP := rP + rL * w;
    gP := gP + gL * w;
    bP := bP + bL * w;
    aP := aP + a * w;
  end;

var
  rL, gL, bL: Double;
begin
  // HQ bilinear sampler:
  // - blends in linear-light (approx gamma 2.2)
  // - respects alpha (premultiplied) and composites transparency to black
  sx := SrcR.Left + fx * (SrcR.Right - SrcR.Left - 1);
  sy := SrcR.Top + fy * (SrcR.Bottom - SrcR.Top - 1);

  x0 := Floor(sx); y0 := Floor(sy);
  tx := sx - x0;
  ty := sy - y0;

  x1 := x0 + 1; y1 := y0 + 1;
  if x0 < SrcR.Left then x0 := SrcR.Left;
  if y0 < SrcR.Top then y0 := SrcR.Top;
  if x1 >= SrcR.Right then x1 := SrcR.Right - 1;
  if y1 >= SrcR.Bottom then y1 := SrcR.Bottom - 1;

  c00 := Img.Colors[x0, y0];
  c10 := Img.Colors[x1, y0];
  c01 := Img.Colors[x0, y1];
  c11 := Img.Colors[x1, y1];

  w00 := (1-tx) * (1-ty);
  w10 := tx * (1-ty);
  w01 := (1-tx) * ty;
  w11 := tx * ty;

  rP := 0; gP := 0; bP := 0; aP := 0;
  AddWeightedPremul(c00, w00);
  AddWeightedPremul(c10, w10);
  AddWeightedPremul(c01, w01);
  AddWeightedPremul(c11, w11);

  if aP <= 0.000001 then
  begin
    Result.R := 0; Result.G := 0; Result.B := 0;
    Exit;
  end;

  // Unpremultiply back to linear RGB.
  rL := rP / aP;
  gL := gP / aP;
  bL := bP / aP;

  Result.R := ToSRGB(rL);
  Result.G := ToSRGB(gL);
  Result.B := ToSRGB(bL);
end;

function SampleRGBSuper(const Img: TFPCustomImage; const SrcR: TRect;
  fx, fy, pxW, pxH: Double; const SS: Integer; const UseHQ: Boolean): TRGB;
var
  i, j, n: Integer;
  ox, oy: Double;
  c: TRGB;
  rL, gL, bL: Double;
  sumR, sumG, sumB: Double;
  fx2, fy2: Double;
  s: Integer;
begin
  s := SS;
  if s < 1 then s := 1;
  if s = 1 then
  begin
    if UseHQ then Result := SampleRGBBilinearHQ(Img, SrcR, fx, fy)
    else Result := SampleRGBBilinear(Img, SrcR, fx, fy);
    Exit;
  end;

  sumR := 0; sumG := 0; sumB := 0;
  n := 0;
  for j := 0 to s-1 do
    for i := 0 to s-1 do
    begin
      // Uniform grid inside this output pixel footprint.
      ox := (((i + 0.5) / s) - 0.5) * pxW;
      oy := (((j + 0.5) / s) - 0.5) * pxH;
      fx2 := fx + ox;
      fy2 := fy + oy;
      if fx2 < 0 then fx2 := 0 else if fx2 > 1 then fx2 := 1;
      if fy2 < 0 then fy2 := 0 else if fy2 > 1 then fy2 := 1;
      if UseHQ then c := SampleRGBBilinearHQ(Img, SrcR, fx2, fy2)
      else c := SampleRGBBilinear(Img, SrcR, fx2, fy2);
      // Accumulate in linear-light (same 2.2 approximation as HQ sampler).
      rL := ToLin(c.R);
      gL := ToLin(c.G);
      bL := ToLin(c.B);
      sumR := sumR + rL;
      sumG := sumG + gL;
      sumB := sumB + bL;
      Inc(n);
    end;

  if n <= 0 then
  begin
    Result.R := 0; Result.G := 0; Result.B := 0;
    Exit;
  end;

  sumR := sumR / n;
  sumG := sumG / n;
  sumB := sumB / n;

  Result.R := ToSRGB(sumR);
  Result.G := ToSRGB(sumG);
  Result.B := ToSRGB(sumB);
end;


// --- HQ micro-contrast / unsharp on the 8x16 target tile -------------------
// Runs only when HQSharpAmount > 0 (typically in HQMode>=2).
// Uses a small 3x3 Gaussian-ish blur (separable [1 2 1]/4) in linear-light,
// then applies an unsharp mask: out = in + a*(in - blur).
procedure ApplyHQUnsharp(var samples: array of TRGB; const Amt: Double);
var
  a: Double;
  linR, linG, linB: array[0..127] of Double;
  tmpR, tmpG, tmpB: array[0..127] of Double;
  blrR, blrG, blrB: array[0..127] of Double;
  idx, px, py: Integer;
  lidx, ridx, uidx, didx: Integer;
  r, g, b: Double;
begin
  a := Amt;
  if a <= 0 then Exit;
  if a > 1 then a := 1;

  // 1) sRGB -> linear
  for idx := 0 to 127 do
  begin
    linR[idx] := ToLin(samples[idx].R);
    linG[idx] := ToLin(samples[idx].G);
    linB[idx] := ToLin(samples[idx].B);
  end;

  // 2) Horizontal blur [1 2 1]/4 (clamped)
  for py := 0 to 15 do
    for px := 0 to 7 do
    begin
      idx := py*8 + px;
      lidx := py*8 + (px-1); if px = 0 then lidx := idx;
      ridx := py*8 + (px+1); if px = 7 then ridx := idx;

      tmpR[idx] := (linR[lidx] + 2.0*linR[idx] + linR[ridx]) * 0.25;
      tmpG[idx] := (linG[lidx] + 2.0*linG[idx] + linG[ridx]) * 0.25;
      tmpB[idx] := (linB[lidx] + 2.0*linB[idx] + linB[ridx]) * 0.25;
    end;

  // 3) Vertical blur [1 2 1]/4 (clamped)
  for py := 0 to 15 do
    for px := 0 to 7 do
    begin
      idx := py*8 + px;
      uidx := (py-1)*8 + px; if py = 0 then uidx := idx;
      didx := (py+1)*8 + px; if py = 15 then didx := idx;

      blrR[idx] := (tmpR[uidx] + 2.0*tmpR[idx] + tmpR[didx]) * 0.25;
      blrG[idx] := (tmpG[uidx] + 2.0*tmpG[idx] + tmpG[didx]) * 0.25;
      blrB[idx] := (tmpB[uidx] + 2.0*tmpB[idx] + tmpB[didx]) * 0.25;
    end;

  // 4) Unsharp (detail boost), clamp to [0..1], then linear -> sRGB
  for idx := 0 to 127 do
  begin
    r := linR[idx] + a * (linR[idx] - blrR[idx]);
    g := linG[idx] + a * (linG[idx] - blrG[idx]);
    b := linB[idx] + a * (linB[idx] - blrB[idx]);

    if r < 0 then r := 0 else if r > 1 then r := 1;
    if g < 0 then g := 0 else if g > 1 then g := 1;
    if b < 0 then b := 0 else if b > 1 then b := 1;

    samples[idx].R := ToSRGB(r);
    samples[idx].G := ToSRGB(g);
    samples[idx].B := ToSRGB(b);
  end;
end;


procedure BuildCellsGlyphFit(
  const Img: TFPCustomImage;
  const SrcR: TRect;
  const Rows: Integer;
  const Opt: TConvertOptions;
  var Cells: TCellArray
);
var
  glyphs: TGlyphInfoArray;
  baseGlyphs: TGlyphInfoArray;
  tronicGlyphs: TGlyphInfoArray;
  gradAllowedFixed, gradAllowedBlock, gradAllowedBasic, gradAllowedSmooth: TBool256;
  gradGlyphsFixed, gradGlyphsBlock, gradGlyphsBasic, gradGlyphsSmooth: TGlyphInfoArray;
  pal: array[0..15] of TRGB;
  palLin: TPalLin;
  palYLin: array[0..15] of Double;
  samples: array[0..127] of TRGB;
  samplesOrig: array[0..127] of TRGB;
  // HQ: per-cell pixel->palette distance cache (used to try more FG/BG pairs)
  hqDist: array[0..127,0..15] of Integer;
  hqDistValid: Boolean;
  hqCandFG: array[0..15] of Byte;
  hqCandBG: array[0..15] of Byte;
  hqNFG, hqNBG: Integer;
  hqTmpB: Byte;
  hqBestD: Integer;
  hqK: Integer;
  hqUsedPair: Boolean;
  hqUsedColor: array[0..15] of Boolean;
  hqBestI: Integer;
  hqCurD: Integer;
  // Two-cluster per-cell guess (FG/BG + FG mask)
  tcFGMask: TByte128;
  tcFGGuess, tcBGGuess: Byte;
  tcPenPerPix: Integer;
  tcEnabled: Boolean;
  tcStrength: Integer;
  tcErr0, tcErr1, tcErrBest: Int64;
  tcMis0, tcMis1: Integer;
  tcFGCand, tcBGCand: Byte;

  glyphIndexByCh: array[0..255] of Integer;
  passes, passNo: Integer;
  prevCells: TCellArray;
  beta: Double;
  srcVM: TLRGBTile;
  useVM: Boolean;
  // Shader (tutorial-inspired) heuristics
  shaderParams: TShaderParams;
  baseBG: Integer;
  minY, maxY, yv: Integer;
  edgeY: Integer;
  sumY, sumY2: Int64;
  varY: Integer;
  x, y, px, py: Integer;
  g: TGlyphInfo;
  gi: Integer;
  fx, fy: Double;
  onR, onG, onB, offR, offG, offB: Integer;
  sumAllR, sumAllG, sumAllB: Int64;
  avgOn, avgOff, avgAll, c: TRGB;
  avgAll3: TRGB;
  fg, bg: Byte;
  err, bestErr: Int64;
  bestCh, bestFG, bestBG: Byte;
  bestGlyph: TGlyphInfo;
  bestBlockErr: Int64;
  bestBlockCh, bestBlockFG, bestBlockBG: Byte;
  bestBlockGlyph: TGlyphInfo;
  bestBlockWasShader: Boolean;
  matchPct, blockPct: Integer;
  baseBG3: Integer;
  bitOn: Boolean;
  row: Byte;
  leftAttr, topAttr: Byte;
  leftFG, leftBG, topFG, topBG: Byte;
  curFG, curBG: Byte;
  pen: Int64;
  cellIndex: Integer;
  denom: Integer;
  tmpIdx: Integer;
  i: Integer;
  w: Double;
  // Cell-level tone/diffusion (TronicShade and optional regular-mode diffuser)
  cellDoDiff: Boolean;
  cellDoOrdered: Boolean;
  cellModelKind: Integer;
  cellAmountPct: Integer;
  trSerpentine: Boolean;
  errRow, errNextRow, errNext2Row: array of Double;
  targetYBase, targetYAdj, prodY: Integer;
  qErr, qScaled: Double;

  // Tronic AutoShader tone target field (smoothed luma targets)
  trTargetLuma: array of Integer; // final blended tone target, len = COLS*Rows
  trBaseLuma: array of Integer;   // base (center-sampled) luma per cell
  trField10: array of Integer;
  trField5: array of Integer;
  trField3: array of Integer;
  trAccI: array of Integer;
  trWgtI: array of Integer;
  trTargetW: array of Integer;
  trWin, trStep: Integer;
  alpha: Double;
  tFG, tBG, bgIdx: Integer;
  d: Integer;
  effOld, effBest: Int64;
  errOld, errBest: Int64;
  blendCol: TRGB;
  bestBlendD: Integer;
  bestFG2, bestBG2: Byte;
  fgBlend, bgBlend: Byte;
  errPix, errMixOld, errMixBest: Int64;
  rfFGCand: array[0..3] of Byte;
  rfBGCand: array[0..3] of Byte;
  rfFGD: array[0..3] of Integer;
  rfBGD: array[0..3] of Integer;
  rfi, rfj, rfidx: Integer;
  rfMaxBG: Integer;
  rfFG2, rfBG2: Byte;
  rfBestFG3, rfBestBG3: Byte;
  rfBestE3, rfE3: Int64;
  rfW2, rfAlpha2: Double;
  rfBlend2: TRGB;
  rfSat: Integer;
  // Shader BIN support (AutoShader)
  shaderPairs: TColorPairArray;
  shaderPicked: Boolean;
  bestWasShader: Boolean;
  spi: Integer;
  bestPairErr: Int64;
  tmpErr: Int64;
  bestPairFG, bestPairBG: Byte;

  // TronicShade per-cell neighborhood context (palette-index grids)
  trGrid3: array[0..8] of Byte;
  trGrid5: array[0..24] of Byte;
  trGrid10: array[0..99] of Byte;
  // Full-cell palette sampling for TronicShade neighborhood keys
  trCellPal: array of Byte;   // representative palette index per cell (len=COLS*Rows)
  trCellHist: array of Word;  // per-cell palette histogram counts (len=COLS*Rows*16)
  trKey3, trKey5, trKey10: Integer;
  trC0, trCN: Byte;
  trBestD, trD: Integer;
  trBestIdx: Integer;
  trHadAttr: Boolean;
  trOldAttr: Byte;
  // Tronic edge mix sampling temps
  trCountA, trCountB, trTot, trMin: Integer;
  trS, trSX, trSY, trX, trY0, trIdx: Integer;
  trD0, trD1: Integer;
  trSumY: Integer;


  // Hinted-palette refit stats (optional)
  hintedIdx: array[0..15] of Boolean;
  sumHintR, sumHintG, sumHintB: array[0..15] of Int64;
  cntHint: array[0..15] of Int64;
  doRefitHintPal: Boolean;
  refitAlpha: Double;

  // Optional TronicShade render report
  rep: PTronicRenderReport;
  oldCh, oldAttr: Byte;
  toneErrI: Integer;


function IsBlockCh(ch: Byte): Boolean; inline;
begin
  Result := (ch = CH_SPACE) or (ch = CH_FULL) or (ch = CH_LIGHT) or (ch = CH_MED) or (ch = CH_DARK);
end;



function RGBLumaLocal(const c: TRGB): Integer; inline;
begin
  Result := (77*Integer(c.R) + 150*Integer(c.G) + 29*Integer(c.B)) shr 8;
end;

function Dist2RGBLocal(const a, b: TRGB): Integer; inline;
var
  dr, dg, db: Integer;
begin
  dr := Integer(a.R) - Integer(b.R);
  dg := Integer(a.G) - Integer(b.G);
  db := Integer(a.B) - Integer(b.B);
  Result := dr*dr + dg*dg + db*db;
end;

// Simple 2-means clustering on the 8x16 samples. Returns a foreground-mask
// (1 = belongs to the brighter cluster) and suggested palette indices.
procedure TwoClusterGuessCell(const S: array of TRGB; const Opt: TConvertOptions; out FGIdx, BGIdx: Byte; out FGMask: TByte128; out PenPerPix: Integer);
var
  i, it: Integer;
  c0, c1: TRGB;
  a: TByte128;
  sum0r, sum0g, sum0b, sum1r, sum1g, sum1b: Int64;
  cnt0, cnt1: Integer;
  bestLo, bestHi: Integer;
  loL, hiL: Integer;
  fgCluster: Byte;
  sep: Integer;
  fgCol, bgCol: TRGB;
  d0, d1: Integer;
  l0, l1: Integer;
  tmp: TRGB;
  tmpI: Integer;

  procedure SwapRGB(var x, y: TRGB);
  var t: TRGB;
  begin
    t := x; x := y; y := t;
  end;

begin
  // Defaults
  FGIdx := 7;
  BGIdx := 0;
  for i := 0 to 127 do FGMask[i] := 0;
  PenPerPix := 0;

  if Length(S) < 128 then Exit;

  // Init centers using darkest & brightest luma samples.
  bestLo := 0; bestHi := 0;
  loL := 1000; hiL := -1;
  for i := 0 to 127 do
  begin
    tmpI := RGBLumaLocal(S[i]);
    if tmpI < loL then begin loL := tmpI; bestLo := i; end;
    if tmpI > hiL then begin hiL := tmpI; bestHi := i; end;
  end;
  c0 := S[bestLo];
  c1 := S[bestHi];

  // If there's basically no contrast, bail.
  if Dist2RGBLocal(c0, c1) < 200 then Exit;

  // Run a few iterations.
  for it := 0 to 5 do
  begin
    sum0r := 0; sum0g := 0; sum0b := 0; cnt0 := 0;
    sum1r := 0; sum1g := 0; sum1b := 0; cnt1 := 0;
    for i := 0 to 127 do
    begin
      d0 := Dist2RGBLocal(S[i], c0);
      d1 := Dist2RGBLocal(S[i], c1);
      if d0 <= d1 then
      begin
        a[i] := 0;
        Inc(sum0r, S[i].R); Inc(sum0g, S[i].G); Inc(sum0b, S[i].B);
        Inc(cnt0);
      end
      else
      begin
        a[i] := 1;
        Inc(sum1r, S[i].R); Inc(sum1g, S[i].G); Inc(sum1b, S[i].B);
        Inc(cnt1);
      end;
    end;

    if cnt0 > 0 then
    begin
      c0.R := ClampByte(Round(sum0r / cnt0));
      c0.G := ClampByte(Round(sum0g / cnt0));
      c0.B := ClampByte(Round(sum0b / cnt0));
    end;
    if cnt1 > 0 then
    begin
      c1.R := ClampByte(Round(sum1r / cnt1));
      c1.G := ClampByte(Round(sum1g / cnt1));
      c1.B := ClampByte(Round(sum1b / cnt1));
    end;
  end;

  // Order clusters: brighter = FG.
  l0 := RGBLumaLocal(c0);
  l1 := RGBLumaLocal(c1);
  if l1 > l0 then fgCluster := 1 else fgCluster := 0;
  if fgCluster = 0 then begin fgCol := c0; bgCol := c1; end else begin fgCol := c1; bgCol := c0; end;

  // Build FG mask.
  for i := 0 to 127 do
    if a[i] = fgCluster then FGMask[i] := 1 else FGMask[i] := 0;

  // Palette indices.
  FGIdx := NearestAnsi16(fgCol, Opt.Palette) and $0F;
  BGIdx := NearestAnsi16(bgCol, Opt.Palette) and $0F;
  if not Opt.Ice then BGIdx := BGIdx and $07;

  // Mask alignment penalty per mismatched pixel, scaled by cluster separation.
  sep := Dist2RGBLocal(c0, c1);
  if sep < 800 then
    PenPerPix := 0
  else
    PenPerPix := EnsureRange(sep div 8, 150, 18000);
end;

// Linear-light variant of TwoClusterGuessCell. This is more stable for TronicShade
// shading because it respects how light actually blends.
procedure TwoClusterGuessCellLinear(const S: array of TRGB; const Opt: TConvertOptions; out FGIdx, BGIdx: Byte; out FGMask: TByte128; out PenPerPix: Integer);
var
  i, it: Integer;
  c0, c1: TRGB;
  a: TByte128;
  sum0r, sum0g, sum0b, sum1r, sum1g, sum1b: Int64;
  cnt0, cnt1: Integer;
  bestLo, bestHi: Integer;
  loL, hiL: Integer;
  fgCluster: Byte;
  sep: Integer;
  fgCol, bgCol: TRGB;
  d0, d1: Integer;
  l0, l1: Integer;
  tmpI: Integer;
begin
  FGIdx := 7;
  BGIdx := 0;
  for i := 0 to 127 do FGMask[i] := 0;
  PenPerPix := 0;
  if Length(S) < 128 then Exit;

  // Init centers using darkest & brightest *linear* luma samples.
  bestLo := 0; bestHi := 0;
  loL := 1000; hiL := -1;
  for i := 0 to 127 do
  begin
    tmpI := LumaLin255(S[i]);
    if tmpI < loL then begin loL := tmpI; bestLo := i; end;
    if tmpI > hiL then begin hiL := tmpI; bestHi := i; end;
  end;
  c0 := S[bestLo];
  c1 := S[bestHi];

  // If there's basically no contrast, bail.
  if DistLin22_2(c0, c1) < 200000 then Exit;

  // Run a few iterations in linear distance.
  for it := 0 to 5 do
  begin
    sum0r := 0; sum0g := 0; sum0b := 0; cnt0 := 0;
    sum1r := 0; sum1g := 0; sum1b := 0; cnt1 := 0;
    for i := 0 to 127 do
    begin
      d0 := DistLin22_2(S[i], c0);
      d1 := DistLin22_2(S[i], c1);
      if d0 <= d1 then
      begin
        a[i] := 0;
        Inc(sum0r, S[i].R); Inc(sum0g, S[i].G); Inc(sum0b, S[i].B);
        Inc(cnt0);
      end
      else
      begin
        a[i] := 1;
        Inc(sum1r, S[i].R); Inc(sum1g, S[i].G); Inc(sum1b, S[i].B);
        Inc(cnt1);
      end;
    end;

    if cnt0 > 0 then
    begin
      c0.R := ClampByte(Round(sum0r / cnt0));
      c0.G := ClampByte(Round(sum0g / cnt0));
      c0.B := ClampByte(Round(sum0b / cnt0));
    end;
    if cnt1 > 0 then
    begin
      c1.R := ClampByte(Round(sum1r / cnt1));
      c1.G := ClampByte(Round(sum1g / cnt1));
      c1.B := ClampByte(Round(sum1b / cnt1));
    end;
  end;

  // Order clusters: brighter = FG.
  l0 := LumaLin255(c0);
  l1 := LumaLin255(c1);
  if l1 > l0 then fgCluster := 1 else fgCluster := 0;
  if fgCluster = 0 then begin fgCol := c0; bgCol := c1; end else begin fgCol := c1; bgCol := c0; end;

  for i := 0 to 127 do
    if a[i] = fgCluster then FGMask[i] := 1 else FGMask[i] := 0;

  FGIdx := NearestAnsi16(fgCol, Opt.Palette) and $0F;
  BGIdx := NearestAnsi16(bgCol, Opt.Palette) and $0F;
  if not Opt.Ice then BGIdx := BGIdx and $07;

  // Penalty per mismatched pixel, scaled by separation (linear).
  sep := DistLin22_2(c0, c1);
  if sep < 800000 then
    PenPerPix := 0
  else
    PenPerPix := EnsureRange(sep div 8000, 150, 18000);
end;

function CellSampleDist2(const a: TRGB; const palCol: TRGB; palIdx: Integer; const Opt: TConvertOptions): Integer; inline;
begin
  if (Opt.Mode = rmTronicShade) and ((Opt.TronicColorMetric = tcmLumaOnly) or Opt.TronicLumaOnly) then
    Result := PalLumaDist2Hinted(a, palCol, palIdx)
  else
    Result := PalDist2Hinted(a, palCol, palIdx);
end;

function SamplePalAtCell(cx, cy: Integer): Byte; inline;
var
  cc: TRGB;
  fx2, fy2: Double;
  idxC: Integer;
begin
  // In TronicShade mode we precompute a representative palette index per cell
  // using a full 8x16 histogram sample. This makes neighborhood keys much more
  // stable on dither-heavy styles.
  if (Opt.Mode = rmTronicShade) and (Length(trCellPal) = COLS*Rows) then
  begin
    cx := EnsureRange(cx, 0, COLS-1);
    cy := EnsureRange(cy, 0, Rows-1);
    idxC := cy*COLS + cx;
    Exit(trCellPal[idxC] and $0F);
  end;

  cx := EnsureRange(cx, 0, COLS-1);
  cy := EnsureRange(cy, 0, Rows-1);
  fx2 := (cx*8 + 4.0) / (COLS*8.0);
  fy2 := (cy*16 + 8.0) / (Rows*16.0);
  if Opt.HQMode > 0 then
    cc := SampleRGBBilinearHQ(Img, SrcR, fx2, fy2)
  else
    cc := SampleRGBBilinear(Img, SrcR, fx2, fy2);
  cc := TransformRGB(cc, Opt.Gamma, Opt.Contrast, Opt.Saturation, Opt.Brightness);
  Result := NearestAnsi16(cc, Opt.Palette) and $0F;
  cx := EnsureRange(cx, 0, COLS-1);
  cy := EnsureRange(cy, 0, Rows-1);
  fx2 := (cx*8 + 4.0) / (COLS*8.0);
  fy2 := (cy*16 + 8.0) / (Rows*16.0);
  if Opt.HQMode > 0 then
    cc := SampleRGBBilinearHQ(Img, SrcR, fx2, fy2)
  else
    cc := SampleRGBBilinear(Img, SrcR, fx2, fy2);
  cc := TransformRGB(cc, Opt.Gamma, Opt.Contrast, Opt.Saturation, Opt.Brightness);
  Result := NearestAnsi16(cc, Opt.Palette) and $0F;
end;

type
  TIntDyn = array of Integer;

procedure BuildTronicToneField(const AWin, AStep: Integer; var OutField: TIntDyn);
var
  win, step: Integer;
  px2, py2, xx, yy: Integer;
  wi, hj: Integer;
  dist, wInt: Integer;
  sumLocal: Int64;
  meanY: Integer;
  idx2: Integer;
begin
  win := EnsureRange(AWin, 3, 20);
  step := EnsureRange(AStep, 1, 10);

  // accumulators
  SetLength(trAccI, COLS*Rows);
  SetLength(trWgtI, COLS*Rows);
  for idx2 := 0 to High(trAccI) do begin trAccI[idx2] := 0; trWgtI[idx2] := 0; end;

  for py2 := 0 to (Rows - win) div step do
  begin
    yy := py2 * step;
    for px2 := 0 to (COLS - win) div step do
    begin
      xx := px2 * step;
      sumLocal := 0;
      for wi := 0 to win-1 do
        for hj := 0 to win-1 do
          Inc(sumLocal, trBaseLuma[(yy+wi)*COLS + (xx+hj)]);
      meanY := EnsureRange(Integer(sumLocal div (Int64(win) * Int64(win))), 0, 255);

      // Splat using a simple tent weight (Manhattan distance to center).
      for wi := 0 to win-1 do
        for hj := 0 to win-1 do
        begin
          dist := Abs(hj - (win div 2)) + Abs(wi - (win div 2));
          wInt := (win div 2) + 1 - dist;
          if wInt < 1 then wInt := 1;
          idx2 := (yy+wi)*COLS + (xx+hj);
          trAccI[idx2] := trAccI[idx2] + meanY * wInt;
          trWgtI[idx2] := trWgtI[idx2] + wInt;
        end;
    end;
  end;

  SetLength(OutField, COLS*Rows);
  for idx2 := 0 to High(OutField) do
  begin
    if trWgtI[idx2] > 0 then
      OutField[idx2] := EnsureRange(trAccI[idx2] div trWgtI[idx2], 0, 255)
    else
      OutField[idx2] := EnsureRange(trBaseLuma[idx2], 0, 255);
  end;
end;

procedure FillTronicGrid(const S: Integer; const cx, cy: Integer; var OutGrid: array of Byte);
var
  r, c, i2, nx, ny: Integer;
begin
  i2 := 0;
  for r := -(S div 2) to (S div 2) do
    for c := -(S div 2) to (S div 2) do
    begin
      nx := cx + c;
      ny := cy + r;
      OutGrid[i2] := SamplePalAtCell(nx, ny);
      Inc(i2);
    end;
end;

function Bayer4Val(const x, y: Integer): Integer; inline;
const
  M: array[0..15] of Byte = (
    0, 8, 2, 10,
    12, 4, 14, 6,
    3, 11, 1, 9,
    15, 7, 13, 5
  );
begin
  Result := M[(y and 3)*4 + (x and 3)];
end;

function Bayer8Val(const x, y: Integer): Integer; inline;
const
  M: array[0..63] of Byte = (
    0, 48, 12, 60, 3, 51, 15, 63,
    32, 16, 44, 28, 35, 19, 47, 31,
    8, 56, 4, 52, 11, 59, 7, 55,
    40, 24, 36, 20, 43, 27, 39, 23,
    2, 50, 14, 62, 1, 49, 13, 61,
    34, 18, 46, 30, 33, 17, 45, 29,
    10, 58, 6, 54, 9, 57, 5, 53,
    42, 26, 38, 22, 41, 25, 37, 21
  );
begin
  Result := M[(y and 7)*8 + (x and 7)];
end;

function TronicOrderedOffset(const x, y: Integer; const Model: TTronicDiffusionModel; const AmountPct: Integer): Integer; inline;
var
  v: Integer;
  a: Double;
begin
  if AmountPct <= 0 then Exit(0);
  a := EnsureRange(AmountPct, 0, 100) / 100.0;
  case Model of
    tdmOrderedBayer8: v := Bayer8Val(x, y);
  else
    v := Bayer4Val(x, y);
  end;
  // v is 0..(n^2-1). Center around 0, scale into a modest luma offset.
  // Scale chosen to be subtle; AutoShader windowing does the heavy lifting.
  if Model = tdmOrderedBayer8 then
    Result := Round(((v - 31.5) / 64.0) * (64.0 * a))
  else
    Result := Round(((v - 7.5) / 16.0) * (64.0 * a));
end;

// Render the previous pass' cell into a 8x16 RGB tile (using current palette).
type
  // Fixed 8x16 tile used by multi-pass residual refinement.
  // NOTE: FPC/Lazarus does not allow a fixed-size "array[..] of" type directly
  // in nested procedure parameters, so we name it.
  TRGBTile128 = array[0..127] of TRGB;

procedure RenderPrevTile(const prev: TCell; out outTile: TRGBTile128);
var
  fgIdx, bgIdx: Integer;
  gidx: Integer;
  rowb: Byte;
  px, py: Integer;
  bitOn: Boolean;
begin
  fgIdx := prev.Attr and $0F;
  bgIdx := (prev.Attr shr 4) and $0F;
  gidx := glyphIndexByCh[prev.Ch];
  if gidx < 0 then
  begin
    // Unknown glyph - just fill BG.
    for py := 0 to 15 do
      for px := 0 to 7 do
        outTile[py*8 + px] := pal[bgIdx];
    Exit;
  end;

  for py := 0 to 15 do
  begin
    rowb := baseGlyphs[gidx].Rows[py];
    for px := 0 to 7 do
    begin
      bitOn := (rowb and (1 shl (7 - px))) <> 0;
      if bitOn then outTile[py*8 + px] := pal[fgIdx]
      else outTile[py*8 + px] := pal[bgIdx];
    end;
  end;
end;

// Multi-pass refinement: adjust per-pixel targets using the residual from the previous pass.
procedure ApplyResidual(const orig: TRGBTile128; const prev: TCell; var outS: TRGBTile128; const aBeta: Double);
var
  rend: array[0..127] of TRGB;
  i: Integer;
  v: Integer;
begin
  RenderPrevTile(prev, rend);
  for i := 0 to 127 do
  begin
    v := Round((1.0 + aBeta) * orig[i].R - aBeta * rend[i].R); outS[i].R := ClampByte(v);
    v := Round((1.0 + aBeta) * orig[i].G - aBeta * rend[i].G); outS[i].G := ClampByte(v);
    v := Round((1.0 + aBeta) * orig[i].B - aBeta * rend[i].B); outS[i].B := ClampByte(v);
  end;
end;

begin
  InitGlyphCache(Opt.GlyphSet);
  baseGlyphs := GGlyphCache[Opt.GlyphSet];
  glyphs := baseGlyphs;

  // Tronicshade uses its own isolated glyph candidate set (CP437 shade + blocks).
  // This prevents global glyph-set / gradient controls from interfering.
  if Opt.Mode = rmTronicShade then
  begin
    InitGlyphCache(Opt.TronicGlyphSet);
    // Use the full glyph set as the base pool for TronicShade.
    baseGlyphs := GGlyphCache[Opt.TronicGlyphSet];
    SetLength(tronicGlyphs, 0);
    for gi := 0 to High(baseGlyphs) do
    begin
      case baseGlyphs[gi].Ch of
        CH_SPACE, CH_LIGHT, CH_MED, CH_DARK, CH_FULL, CH_HALFUP, CH_HALFDN, CH_HALFLEFT, CH_HALFRIGHT:
          begin
            SetLength(tronicGlyphs, Length(tronicGlyphs)+1);
            tronicGlyphs[High(tronicGlyphs)] := baseGlyphs[gi];
          end;
      end;
    end;
    if Length(tronicGlyphs) > 0 then
      glyphs := tronicGlyphs
    else
      glyphs := baseGlyphs;
  end;

for tmpIdx := 0 to 255 do glyphIndexByCh[tmpIdx] := -1;
for gi := 0 to High(baseGlyphs) do
  glyphIndexByCh[baseGlyphs[gi].Ch] := gi;

  // Optional glyph ramp restriction (gradient sets).
  // Never apply this in Tronicshade; Tronic has its own isolated glyph set.
  if (Opt.Mode <> rmTronicShade) and (Opt.GradientMode = gmFixed) then
  begin
    FillChar(gradAllowedFixed, SizeOf(gradAllowedFixed), 0);
    GradientAllowed(EnsureRange(Opt.GradientSet, 0, GRADIENT_COUNT-1), gradAllowedFixed);
    gradGlyphsFixed := FilterGlyphsByAllowed(baseGlyphs, gradAllowedFixed);
    if Length(gradGlyphsFixed) > 0 then
      glyphs := gradGlyphsFixed;
  end
  else if (Opt.Mode <> rmTronicShade) and (Opt.GradientMode = gmAuto) then
  begin
    // Built-in auto ramps: Blocks for flat areas, Basic ASCII for moderate detail, Smooth for high detail.
    FillChar(gradAllowedBlock, SizeOf(gradAllowedBlock), 0);
    FillChar(gradAllowedBasic, SizeOf(gradAllowedBasic), 0);
    FillChar(gradAllowedSmooth, SizeOf(gradAllowedSmooth), 0);
    GradientAllowed(2, gradAllowedBlock);  // Block Shade
    GradientAllowed(0, gradAllowedBasic);  // Basic ASCII
    GradientAllowed(7, gradAllowedSmooth); // Smooth
    gradGlyphsBlock := FilterGlyphsByAllowed(baseGlyphs, gradAllowedBlock);
    gradGlyphsBasic := FilterGlyphsByAllowed(baseGlyphs, gradAllowedBasic);
    gradGlyphsSmooth := FilterGlyphsByAllowed(baseGlyphs, gradAllowedSmooth);
    if Length(gradGlyphsBlock) = 0 then gradGlyphsBlock := baseGlyphs;
    if Length(gradGlyphsBasic) = 0 then gradGlyphsBasic := baseGlyphs;
    if Length(gradGlyphsSmooth) = 0 then gradGlyphsSmooth := baseGlyphs;
  end;


  ShaderGetActiveParams(shaderParams);

  // Caller typically sizes the cell array, but this routine may be used
  // independently. Ensure we have room for COLS*Rows cells.
  if Length(Cells) <> (COLS * Rows) then
    SetLength(Cells, COLS * Rows);

  for tmpIdx := 0 to 15 do
    pal[tmpIdx] := Palette16(Opt.Palette, tmpIdx);

  // TronicShade benefits from linear-light luma for tone fitting / diffusion.
  // Build a small lookup of palette luma in linear space (0..1).
  if Opt.Mode = rmTronicShade then
  begin
    EnsureLin22;
    for tmpIdx := 0 to 15 do
      palYLin[tmpIdx] := 0.2126*GLin22[pal[tmpIdx].R] + 0.7152*GLin22[pal[tmpIdx].G] + 0.0722*GLin22[pal[tmpIdx].B];
  end;

  useVM := Opt.DosBoxModel;
  if useVM then
  begin
    EnsureLin22;
    for tmpIdx := 0 to 15 do
      palLin[tmpIdx] := RGBToLin22(pal[tmpIdx]);
  end;

  passes := Opt.AutoShaderPasses;


  if passes < 1 then passes := 1;

  // Optional TronicShade render report (final pass only)
  rep := nil;
  if (Opt.Mode = rmTronicShade) then
    rep := Opt.TronicReport;
  if Assigned(rep) then
  begin
    FillChar(rep^, SizeOf(rep^), 0);
    rep^.Cols := COLS;
    rep^.Rows := Rows;
    rep^.MinBestErr := High(Int64);
    rep^.MaxBestErr := 0;
  end;


  // Build a quick lookup of which ANSI indexes have user hints.
  for tmpIdx := 0 to 15 do hintedIdx[tmpIdx] := False;
  for i := 0 to High(Opt.ColorHints) do
  begin
    tmpIdx := EnsureRange(Integer(Opt.ColorHints[i].TargetIdx), 0, 15);
    hintedIdx[tmpIdx] := True;
  end;

  doRefitHintPal := Opt.UseHintPalette and Opt.RefitHintedPaletteEachPass and (passes > 1) and (Length(Opt.ColorHints) > 0);
  refitAlpha := 0.25; // gentle per-pass adjustment

  SetLength(prevCells, Length(Cells));

  // --- TronicShade AutoShader tone field (smoothed luma targets) ------------
  // For TronicShade we build a per-cell target luma field using overlapping
  // windows. To make 5x5 and 3x3 swatches "strong" (more shading control),
  // we use a fixed multi-scale schedule:
  //   10x10 step 5  (macro)
  //   5x5  step 2  (micro)
  //   3x3  step 1  (detail)
  // and blend the resulting tone fields.
  if Opt.Mode = rmTronicShade then
  begin
    InitGlyphCache(Opt.TronicGlyphSet);
    // Base luma per cell (center sample) — used as the source for multi-scale tone fields.
    SetLength(trBaseLuma, COLS * Rows);

    // Base per-cell palette histogram + luma (full 8x16 sample) — used as the source
    // for multi-scale tone fields and for stable TronicShade neighborhood keys.
    SetLength(trCellPal, COLS * Rows);
    SetLength(trCellHist, COLS * Rows * 16);

    for y := 0 to Rows-1 do
      for x := 0 to COLS-1 do
      begin
        cellIndex := y*COLS + x;

        // Reset histogram bins for this cell.
        for tmpIdx := 0 to 15 do
          trCellHist[cellIndex*16 + tmpIdx] := 0;

        trSumY := 0;

        // Full 8x16 sample inside the cell. This is intentionally heavy-weight:
        // TronicShade is about style fidelity, not speed.
        for trSY := 0 to 15 do
          for trSX := 0 to 7 do
          begin
            fx := (x*8 + (trSX + 0.5)) / (COLS * 8.0);
            fy := (y*16 + (trSY + 0.5)) / (Rows * 16.0);

            c := SampleRGBSuper(
                   Img, SrcR, fx, fy,
                   1.0 / (COLS * 8.0),
                   1.0 / (Rows * 16.0),
                   IfThen(Opt.HQMode > 0, Opt.HQSuperSample, 1),
                   (Opt.HQMode > 0)
                 );
            c := TransformRGB(c, Opt.Gamma, Opt.Contrast, Opt.Saturation, Opt.Brightness);

            Inc(trSumY, LumaLin255(c));

            trIdx := NearestAnsi16(c, Opt.Palette) and $0F;
            Inc(trCellHist[cellIndex*16 + trIdx]);
          end;

        trBaseLuma[cellIndex] := EnsureRange(trSumY div 128, 0, 255);

        // Representative palette index = histogram mode.
        // Tie-breaker: choose the palette index whose luma is closest to the cell mean.
        trBestIdx := 0;
        trBestD := -1;
        for tmpIdx := 0 to 15 do
        begin
          trD := trCellHist[cellIndex*16 + tmpIdx];
          if trD > trBestD then
          begin
            trBestD := trD;
            trBestIdx := tmpIdx;
          end
          else if (trD = trBestD) and (trD > 0) then
          begin
            if Abs(RGBLumaLocal(Palette16(Opt.Palette, tmpIdx)) - trBaseLuma[cellIndex]) <
               Abs(RGBLumaLocal(Palette16(Opt.Palette, trBestIdx)) - trBaseLuma[cellIndex]) then
              trBestIdx := tmpIdx;
          end;
        end;
        trCellPal[cellIndex] := Byte(trBestIdx);
      end;


    SetLength(trTargetLuma, COLS * Rows);
    if not Opt.TronicAutoShaderEnabled then
    begin
      // No smoothing: target = base.
      for i := 0 to High(trTargetLuma) do trTargetLuma[i] := trBaseLuma[i];
    end
    else
    begin
      // Fixed multi-scale schedule that makes 5x5 and 3x3 swatches strong for shading.
      BuildTronicToneField(10, 5, trField10);
      BuildTronicToneField(5,  2, trField5);
      BuildTronicToneField(3,  1, trField3);

      // Blend: bias toward 5x5 and 3x3 so they strongly affect shading.
      // (Keep 10x10 to prevent drift across large areas.)
      // These weights are intentionally "shade-forward".
      for i := 0 to High(trTargetLuma) do
        trTargetLuma[i] := EnsureRange(
          (Int64(trField10[i]) * 10 + Int64(trField5[i]) * 18 + Int64(trField3[i]) * 14) div (10 + 18 + 14),
          0, 255);
    end;
  end;



  for passNo := 1 to passes do


  begin


    // Reset hinted-palette usage stats for this pass.
    if doRefitHintPal and (passNo < passes) then
      for tmpIdx := 0 to 15 do begin sumHintR[tmpIdx] := 0; sumHintG[tmpIdx] := 0; sumHintB[tmpIdx] := 0; cntHint[tmpIdx] := 0; end;

    if passNo > 1 then prevCells := Cells;


    if passNo > 1 then beta := 0.5 / (passNo - 1) else beta := 0.0;
    // Cell-level diffusion is available in TronicShade (TronicDiffusionModel)
    // and as a regular-mode option (CellDiffusionModel).
    if Opt.Mode = rmTronicShade then
    begin
      cellModelKind := Ord(Opt.TronicDiffusionModel);
      cellAmountPct := EnsureRange(Opt.TronicDiffusionAmount, 0, 100);
    end
    else
    begin
      cellModelKind := Ord(Opt.CellDiffusionModel);
      cellAmountPct := EnsureRange(Opt.CellDiffusionAmount, 0, 100);
    end;
    cellDoDiff := (cellModelKind in [Ord(tdmFloydSteinberg), Ord(tdmJJN), Ord(tdmAtkinson), Ord(tdmSierraLite)]) and (passNo = passes) and (cellAmountPct > 0);
    cellDoOrdered := (cellModelKind in [Ord(tdmOrderedBayer4), Ord(tdmOrderedBayer8)]) and (passNo = passes) and (cellAmountPct > 0);
    trSerpentine := False; // (keep deterministic; can be added later)
    if cellDoDiff then
    begin
      SetLength(errRow, COLS);
      SetLength(errNextRow, COLS);
      SetLength(errNext2Row, COLS);
      for i := 0 to COLS-1 do begin errRow[i] := 0.0; errNextRow[i] := 0.0; errNext2Row[i] := 0.0; end;
    end;


    for y := 0 to Rows - 1 do


    begin
    if cellDoDiff and (y > 0) then
    begin
      // Advance error buffers to the next row (keep a 2-row lookahead).
      for i := 0 to COLS-1 do
      begin
        errRow[i] := errNextRow[i];
        errNextRow[i] := errNext2Row[i];
        errNext2Row[i] := 0.0;
      end;
    end;
    if Assigned(Opt.CancelFlag) and Opt.CancelFlag^ then
      raise Exception.Create('Canceled');
    if Assigned(Opt.OnProgress) then
    begin
      if y = 0 then
        Opt.OnProgress(0, 'Fitting glyphs / shading...');
      // Update percent occasionally to keep UI responsive without slowing conversion.
      if (y and 3) = 0 then
        Opt.OnProgress((y * 100) div Max(1, Rows-1), '');
    end;

    for x := 0 to COLS - 1 do
    begin
      // Sample an 8x16 grid for this cell.
      for py := 0 to 15 do
      begin
        for px := 0 to 7 do
        begin
          fx := (x*8 + (px + 0.5)) / (COLS * 8);
          fy := (y*16 + (py + 0.5)) / (Rows * 16);
          c := SampleRGBSuper(
                 Img, SrcR, fx, fy,
                 1.0 / (COLS * 8.0),
                 1.0 / (Rows * 16.0),
                 IfThen(Opt.HQMode > 0, Opt.HQSuperSample, 1),
                 (Opt.HQMode > 0)
               );
          c := TransformRGB(c, Opt.Gamma, Opt.Contrast, Opt.Saturation, Opt.Brightness);
          c := PreMatchMapColor(c, Opt, x*8 + px, y*16 + py);
          samplesOrig[py*8 + px] := c;
        end;
      end;


      if passNo = 1 then
        samples := samplesOrig
      else
        ApplyResidual(samplesOrig, prevCells[y*COLS + x], samples, beta);

      // HQ: mild unsharp on the 8x16 target tile (detail-first).
      if (Opt.HQMode >= 2) and (Opt.HQSharpAmount > 0) then
        ApplyHQUnsharp(samples, Opt.HQSharpAmount);

      // HQ: build per-pixel distance cache to all 16 palette entries (used for multi-pair search)
      hqDistValid := False;
      if (Opt.HQMode >= 2) and (not useVM) then
      begin
        for i := 0 to 15 do
        begin
          // Precompute distances for each sampled pixel to this palette entry.
          for tmpIdx := 0 to 127 do
            hqDist[tmpIdx, i] := PalDist2Hinted(samples[tmpIdx], pal[i], i);
        end;
        hqDistValid := True;
      end;

      // Average target color for the cell (used for shade-blend scoring).
      sumAllR := 0; sumAllG := 0; sumAllB := 0;
      minY := 255; maxY := 0;
      sumY := 0; sumY2 := 0;
      for i := 0 to 127 do
      begin
        Inc(sumAllR, samples[i].R);
        Inc(sumAllG, samples[i].G);
        Inc(sumAllB, samples[i].B);
        // Luma for edge/outline preservation.
        // TronicShade benefits from linear-light luma (better ramps / shading decisions).
        if Opt.Mode = rmTronicShade then
          yv := LumaLin255(samples[i])
        else
          yv := (77*Integer(samples[i].R) + 150*Integer(samples[i].G) + 29*Integer(samples[i].B)) shr 8;
        Inc(sumY, yv);
        Inc(sumY2, Int64(yv) * Int64(yv));
        if yv < minY then minY := yv;
        if yv > maxY then maxY := yv;
      end;
      avgAll.R := ClampByte(Round(sumAllR / 128));
      avgAll.G := ClampByte(Round(sumAllG / 128));
      avgAll.B := ClampByte(Round(sumAllB / 128));

      // TronicShade target luma for tone fit / diffusion
      if (Opt.Mode = rmTronicShade) and (Length(trTargetLuma) = COLS*Rows) then
        targetYBase := EnsureRange(trTargetLuma[y*COLS + x], 0, 255)
      else
        targetYBase := EnsureRange(Integer(sumY div 128), 0, 255);

      targetYAdj := targetYBase;
      if cellDoOrdered then
      begin
        // Ordered (Bayer) modulation of the tone target at cell granularity.
        if Opt.Mode = rmTronicShade then
          targetYAdj := EnsureRange(targetYAdj + TronicOrderedOffset(x, y, Opt.TronicDiffusionModel, cellAmountPct), 0, 255)
        else
          targetYAdj := EnsureRange(targetYAdj + TronicOrderedOffset(x, y, TTronicDiffusionModel(cellModelKind), cellAmountPct), 0, 255);
      end;
      if cellDoDiff then
        // Apply accumulated error to the target luma.
        targetYAdj := EnsureRange(Round(targetYAdj + errRow[x]), 0, 255);
      gTronicTargetY := targetYAdj;

      // 3x3 neighborhood average color (cheap: sample 9 cell centers). Used as a stabilizer for block/shade colors.
      if Opt.AutoShader3x3BelowPct > 0 then
      begin
        sumAllR := 0; sumAllG := 0; sumAllB := 0;
        for tmpIdx := -1 to 1 do
        begin
          for i := -1 to 1 do
          begin
            // clamp neighbor cell coords
            rfi := EnsureRange(x + i, 0, COLS - 1);
            rfj := EnsureRange(y + tmpIdx, 0, Rows - 1);
            fx := (rfi*8 + 4.0) / (COLS * 8.0);
            fy := (rfj*16 + 8.0) / (Rows * 16.0);
            c := SampleRGBSuper(
                   Img, SrcR, fx, fy,
                   1.0 / (COLS * 8.0),
                   1.0 / (Rows * 16.0),
                   IfThen(Opt.HQMode > 0, Opt.HQSuperSample, 1),
                   (Opt.HQMode > 0)
                 );
            c := TransformRGB(c, Opt.Gamma, Opt.Contrast, Opt.Saturation, Opt.Brightness);
            c := PreMatchMapColor(c, Opt, rfi*8 + 4, rfj*16 + 8);
            Inc(sumAllR, c.R);
            Inc(sumAllG, c.G);
            Inc(sumAllB, c.B);
          end;
        end;
        avgAll3.R := ClampByte(Round(sumAllR / 9));
        avgAll3.G := ClampByte(Round(sumAllG / 9));
        avgAll3.B := ClampByte(Round(sumAllB / 9));
      end
      else
        avgAll3 := avgAll;

        // Two-cluster per-cell FG/BG guess (used by GlyphFit/AutoShader/TronicShade)
      // K-means anchors help TronicShade lock onto the correct two ANSI colors
      // before shading (very good for split-tone / posterized sources).
      // In HQMode>=2 we always enable this for TronicShade, even if the checkbox is off.
      tcStrength := Opt.TwoClusterStrength;
      tcEnabled := (Opt.TwoClusterGuess and (tcStrength > 0)) or ((Opt.Mode = rmTronicShade) and (Opt.HQMode >= 2));
      if tcEnabled then
      begin
        if (Opt.Mode = rmTronicShade) and (Opt.HQMode >= 2) then
        begin
          if tcStrength <= 0 then tcStrength := 100;
          TwoClusterGuessCellLinear(samples, Opt, tcFGGuess, tcBGGuess, tcFGMask, tcPenPerPix);
        end
        else
          TwoClusterGuessCell(samples, Opt, tcFGGuess, tcBGGuess, tcFGMask, tcPenPerPix);
      end
      else
      begin
        tcFGGuess := 7; tcBGGuess := 0; tcPenPerPix := 0;
      end;


      if useVM then
        BuildTileVM_HBlur(samples, srcVM);

      // Base background color for block-in style (avg cell color)
      baseBG := NearestAnsi16(avgAll, Opt.Palette);
      if not Opt.Ice then baseBG := baseBG and $07;
      edgeY := maxY - minY;

      // Cheap texture estimate used for auto gradient choice
      // varY ~= E[Y^2] - (E[Y])^2
      varY := Integer((sumY2 div 128) - Int64((sumY div 128) * (sumY div 128)));
      if varY < 0 then varY := 0;

      if Opt.GradientMode = gmAuto then
      begin
        // Flat -> blocks, moderate -> basic ASCII, textured -> smooth.
        if (edgeY <= 20) and (varY <= 80) then glyphs := gradGlyphsBlock
        else if (edgeY <= 45) and (varY <= 500) then glyphs := gradGlyphsBasic
        else glyphs := gradGlyphsSmooth;
        if Length(glyphs) = 0 then glyphs := baseGlyphs;
      end;

      bestErr := High(Int64);
      bestBlockErr := High(Int64);
      bestBlockWasShader := False;
      bestBlockCh := CH_SPACE;
      bestBlockFG := 7;
      bestBlockBG := 0;
      if Length(glyphs) > 0 then bestBlockGlyph := glyphs[0];
      bestWasShader := False;
      bestCh := CH_SPACE;
      bestFG := 7;
      bestBG := 0;
      if Length(glyphs) > 0 then bestGlyph := glyphs[0];

      cellIndex := y * COLS + x;

      // For TronicShade report: snapshot the pre-pass cell (base pass result).
      if Assigned(rep) and (passNo = passes) then
      begin
        oldCh := Cells[cellIndex].Ch;
        oldAttr := Cells[cellIndex].Attr;
      end;

      // Preserve original colors for glyph-only mode, but don't let an uninitialized
      // cell (Attr=0) force everything to black. If Attr is zero, treat it as
      // "no colors yet" and allow a normal color search on this pass.
      trHadAttr := (Cells[cellIndex].Attr <> 0);
      trOldAttr := Cells[cellIndex].Attr;

      // TronicShade: glyph-only option (keep existing colors)
      // When enabled, restrict color search to the current cell FG/BG and only change the character.
      if (Opt.Mode = rmTronicShade) and (Opt.TronicApplyMode = 1) then
      begin
        if trHadAttr then
        begin
          curFG := trOldAttr and $0F;
          curBG := (trOldAttr shr 4) and $0F;
          if not Opt.Ice then curBG := curBG and $07;
        end
        else
        begin
          // No prior colors: let the solver pick colors for this first render.
          curFG := 255;
          curBG := 255;
        end;
      end
      else
      begin
        curFG := 255;
        curBG := 255;
      end;


      // TronicShade context for this cell (computed once per cell, reused by candidate scoring).
      // Tronicshade context is always computed in rmTronicShade so edge-texture
      // forcing works even before a library is learned.
      gTronicEnabled := (Opt.Mode = rmTronicShade);
      if gTronicEnabled then
      begin
        gTronicHasLeft := (x > 0);
        gTronicHasTop := (y > 0);
        if gTronicHasLeft then gTronicLeftAttr := Cells[cellIndex - 1].Attr else gTronicLeftAttr := 0;
        if gTronicHasTop then gTronicTopAttr := Cells[cellIndex - COLS].Attr else gTronicTopAttr := 0;

        // Sample palette indices at neighbor cell centers for 3x3/5x5/10x10 neighborhoods.
        FillTronicGrid(3, x, y, trGrid3);
        FillTronicGrid(5, x, y, trGrid5);
        FillTronicGrid(10, x, y, trGrid10);
        if TronicShadeHasAny then
        begin
          trKey3 := TronicShadeKeyFromPalGrid(3, trGrid3, pal);
          trKey5 := TronicShadeKeyFromPalGrid(5, trGrid5, pal);
          trKey10 := TronicShadeKeyFromPalGrid(10, trGrid10, pal);
          gTronicKey3 := trKey3;
          gTronicKey5 := trKey5;
          gTronicKey10 := trKey10;
        end
        else
        begin
          gTronicKey3 := 0; gTronicKey5 := 0; gTronicKey10 := 0;
        end;

        // --- Edge detection (palette transitions) ------------------------
        // Detect hard palette/color boundaries (L/R/U/D) and force shade/half-block
        // texture there so ANSI block art gets proper "ramped" edges.
        gTronicEdge := False;
        gTronicEdgeDir := 0;
        gTronicEdgeMixPct := 0;
        gTronicEdgeCount := 0;
        gTronicEdgeFG := trGrid3[4];
        gTronicEdgeBG := trGrid3[4];
        // Choose the strongest differing neighbor by palette distance.
        // trGrid3 indices: [0..8] row-major, center=4, up=1, left=3, right=5, down=7.
        begin
          trC0 := trGrid3[4];
          trBestD := 0; trBestIdx := -1;
          // left
          trCN := trGrid3[3];
          if trCN <> trC0 then begin Inc(gTronicEdgeCount); trD := PalDist2(pal[trC0], pal[trCN]); if trD > trBestD then begin trBestD := trD; trBestIdx := 1; gTronicEdgeBG := trCN; end; end;
          // right
          trCN := trGrid3[5];
          if trCN <> trC0 then begin Inc(gTronicEdgeCount); trD := PalDist2(pal[trC0], pal[trCN]); if trD > trBestD then begin trBestD := trD; trBestIdx := 2; gTronicEdgeBG := trCN; end; end;
          // up
          trCN := trGrid3[1];
          if trCN <> trC0 then begin Inc(gTronicEdgeCount); trD := PalDist2(pal[trC0], pal[trCN]); if trD > trBestD then begin trBestD := trD; trBestIdx := 3; gTronicEdgeBG := trCN; end; end;
          // down
          trCN := trGrid3[7];
          if trCN <> trC0 then begin Inc(gTronicEdgeCount); trD := PalDist2(pal[trC0], pal[trCN]); if trD > trBestD then begin trBestD := trD; trBestIdx := 4; gTronicEdgeBG := trCN; end; end;

          if (trBestIdx <> -1) and Opt.TronicEdgeShadeEnabled then
          begin
            gTronicEdge := True;
            gTronicEdgeDir := Byte(trBestIdx);

            // Estimate how mixed the two boundary colors are INSIDE this cell.
            // 0 = solid (one color), 100 = very mixed (50/50).
            gTronicEdgeMixPct := 0;
            begin
              trCountA := 0; trCountB := 0;
              // HQ: sample the *coverage field* directly from the source (not from the 8x16 tile indices)
              // so boundaries are measured smoothly and deterministically.
              trS := EnsureRange(Opt.TronicEdgeSampleSize, 2, 6);
              for trSY := 0 to trS-1 do
                for trSX := 0 to trS-1 do
                begin
                  fx := (x*8 + (trSX + 0.5) * (8.0 / trS)) / (COLS * 8.0);
                  fy := (y*16 + (trSY + 0.5) * (16.0 / trS)) / (Rows * 16.0);
                  c := SampleRGBSuper(
                         Img, SrcR, fx, fy,
                         1.0 / (COLS * 8.0),
                         1.0 / (Rows * 16.0),
                         IfThen(Opt.HQMode > 0, Opt.HQSuperSample, 1),
                         (Opt.HQMode > 0)
                       );
                  c := TransformRGB(c, Opt.Gamma, Opt.Contrast, Opt.Saturation, Opt.Brightness);
                  c := PreMatchMapColor(c, Opt, x*8 + 4, y*16 + 8);

                  // Compare in linear-light distance for more accurate mixture estimation.
                  trD0 := DistLin22_2(c, pal[trC0]);
                  trD1 := DistLin22_2(c, pal[gTronicEdgeBG]);
                  if trD1 < trD0 then Inc(trCountB) else Inc(trCountA);
                end;
              trTot := trCountA + trCountB;
              if trTot > 0 then
              begin
                if trCountA < trCountB then trMin := trCountA else trMin := trCountB;
                gTronicEdgeMixPct := EnsureRange(Round(200.0 * trMin / trTot), 0, 100);
              end;
            end;

            // Keep BG in classic ANSI range unless iCE is enabled globally.
            if not Opt.Ice then gTronicEdgeBG := gTronicEdgeBG and $07;
          end;
        end;
      end
      else
      begin
        gTronicHasLeft := False; gTronicHasTop := False;
        gTronicLeftAttr := 0; gTronicTopAttr := 0;
        gTronicKey3 := 0; gTronicKey5 := 0; gTronicKey10 := 0;
        gTronicEdge := False;
        gTronicEdgeDir := 0;
        gTronicEdgeCount := 0;
        gTronicEdgeFG := 0;
        gTronicEdgeBG := 0;
      end;

      for gi := 0 to High(glyphs) do
      begin
        g := glyphs[gi];

        // coverage ratio of the glyph (0..1), used by shade-blend + edge keep
        alpha := 0.0;
        if (g.OnCount > 0) and (g.OnCount < 128) then
          alpha := g.OnCount / 128.0;

        onR := 0; onG := 0; onB := 0;
        offR := 0; offG := 0; offB := 0;

        for py := 0 to 15 do
        begin
          row := g.Rows[py];
          for px := 0 to 7 do
          begin
            bitOn := (row and (1 shl (7-px))) <> 0;
            c := samples[py*8 + px];
            if bitOn then
            begin
              Inc(onR, c.R); Inc(onG, c.G); Inc(onB, c.B);
            end
            else
            begin
              Inc(offR, c.R); Inc(offG, c.G); Inc(offB, c.B);
            end;
          end;
        end;

        if g.OnCount > 0 then
        begin
          avgOn.R := ClampByte(Round(onR / g.OnCount));
          avgOn.G := ClampByte(Round(onG / g.OnCount));
          avgOn.B := ClampByte(Round(onB / g.OnCount));
          fg := NearestAnsi16(avgOn, Opt.Palette);
        end
        else
          fg := 0;

        if g.OnCount < 128 then
        begin
          denom := 128 - g.OnCount;
          if denom < 1 then denom := 1;
          avgOff.R := ClampByte(Round(offR / denom));
          avgOff.G := ClampByte(Round(offG / denom));
          avgOff.B := ClampByte(Round(offB / denom));
          bg := NearestAnsi16(avgOff, Opt.Palette);
        end
        else
          bg := 0;

        if not Opt.Ice then
          bg := bg and $07;

        shaderPicked := False;

        if Opt.UseShaderLib and ShaderIsLoaded then
        begin
          // If strict shader matching is enabled, ONLY allow glyph+color pairs that
          // actually appeared in the imported shader art.
          ShaderGetPairsForGlyph(g.Ch, shaderPairs);
          if Length(shaderPairs) = 0 then
          begin
            if Opt.ShaderStrictGlyphMatch then
              Continue // skip this glyph entirely
            else
              ShaderGetAllPairs(shaderPairs);
          end;

          if Length(shaderPairs) > 0 then
          begin
            bestPairErr := High(Int64);
            bestPairFG := fg;
            bestPairBG := bg;

            w := Opt.ShadeBlend;

            for spi := 0 to High(shaderPairs) do
            begin
              tFG := shaderPairs[spi].FG;
              tBG := shaderPairs[spi].BG;
              if not Opt.Ice then tBG := tBG and $07;

              // TronicShade glyph-only: restrict colors to the existing cell's FG/BG.
              if (Opt.Mode = rmTronicShade) and (Opt.TronicApplyMode = 1) and (curFG <> 255) then
              begin
                if (tFG <> curFG) or (tBG <> curBG) then
                  Continue;
              end;

              if useVM then
                tmpErr := TileErrVM_HBlur(g, Byte(tFG), Byte(tBG), palLin, srcVM)
              else
              begin
                tmpErr := 0;
                for py := 0 to 15 do
                begin
                  row := g.Rows[py];
                  for px := 0 to 7 do
                  begin
                    bitOn := (row and (1 shl (7-px))) <> 0;
                    c := samples[py*8 + px];
                    if bitOn then
                      Inc(tmpErr, PalDist2Hinted(c, pal[tFG], tFG))
                    else
                      Inc(tmpErr, PalDist2Hinted(c, pal[tBG], tBG));
                  end;
                end;
              end;

              if (not useVM) and (w > 0) and (alpha > 0) and (alpha < 1) then
              begin
                blendCol := BlendLinear(pal[tFG], pal[tBG], alpha);
                if Opt.Mode = rmTronicShade then
                  effOld := Int64(128) * DistLin22_2(avgAll, blendCol)
                else
                  effOld := Int64(128) * PalDist2(avgAll, blendCol);
                tmpErr := Round((1.0 - w) * tmpErr + w * effOld);
              end;

              // "Block-in then shade" bias: keep background close to the base cell color.
              if shaderParams.BlockStrength > 0 then
                Inc(tmpErr, Round(shaderParams.BlockStrength * 16.0 * PalDist2(pal[tBG], pal[baseBG])));

              if tmpErr < bestPairErr then
              begin
                bestPairErr := tmpErr;
                bestPairFG := Byte(tFG);
                bestPairBG := Byte(tBG);
              end;
            end;

            fg := bestPairFG;
            bg := bestPairBG;
            err := bestPairErr;
            shaderPicked := True;
          end;
        end;

        if not shaderPicked then
        begin
          if useVM then
            err := TileErrVM_HBlur(g, fg, bg, palLin, srcVM)
          else
          begin
            err := 0;
            for py := 0 to 15 do
            begin
              row := g.Rows[py];
              for px := 0 to 7 do
              begin
                bitOn := (row and (1 shl (7-px))) <> 0;
                c := samples[py*8 + px];
                if bitOn then
                  Inc(err, PalDist2Hinted(c, pal[fg], fg))
                else
                  Inc(err, PalDist2Hinted(c, pal[bg], bg));
              end;
            end;
          end;

          // Evaluate two-cluster guess (cell-level FG/BG + mask alignment), as an alternative to per-glyph averages.
          // Only applied when we are not in shader-picked mode (shader may restrict pairs).
          if tcEnabled and (tcPenPerPix > 0) then
          begin
            tcErr0 := 0; tcErr1 := 0; tcMis0 := 0;
            for py := 0 to 15 do
            begin
              row := g.Rows[py];
              for px := 0 to 7 do
              begin
                bitOn := (row and (1 shl (7-px))) <> 0;
                c := samples[py*8 + px];
                if bitOn then
                begin
                  Inc(tcErr0, CellSampleDist2(c, pal[tcFGGuess], tcFGGuess, Opt));
                  Inc(tcErr1, CellSampleDist2(c, pal[tcBGGuess], tcBGGuess, Opt));
                  if tcFGMask[py*8 + px] = 0 then Inc(tcMis0);
                end
                else
                begin
                  Inc(tcErr0, CellSampleDist2(c, pal[tcBGGuess], tcBGGuess, Opt));
                  Inc(tcErr1, CellSampleDist2(c, pal[tcFGGuess], tcFGGuess, Opt));
                  if tcFGMask[py*8 + px] <> 0 then Inc(tcMis0);
                end;
              end;
            end;
            tcMis1 := 128 - tcMis0;

            // Disallow swapped orientation if BG would exceed 7 when iCE is off.
            if (not Opt.Ice) and (tcFGGuess >= 8) then
              tcErr1 := High(Int64) div 4;

            // Strength scale: 100 = as computed, >100 increases mask alignment importance.
            tcErr0 := tcErr0 + (Int64(tcPenPerPix) * Int64(tcMis0) * Int64(tcStrength)) div 100;
            tcErr1 := tcErr1 + (Int64(tcPenPerPix) * Int64(tcMis1) * Int64(tcStrength)) div 100;

            if tcErr0 <= tcErr1 then
            begin
              tcErrBest := tcErr0;
              tcFGCand := tcFGGuess;
              tcBGCand := tcBGGuess;
            end
            else
            begin
              tcErrBest := tcErr1;
              tcFGCand := tcBGGuess;
              tcBGCand := tcFGGuess;
              if not Opt.Ice then tcBGCand := tcBGCand and $07;
            end;

            if tcErrBest < err then
            begin
              err := tcErrBest;
              fg := tcFGCand;
              bg := tcBGCand;
            end;
          end;

          // TronicShade HQ: also try the k-means palette anchors *without*
          // mask-alignment penalty. This makes shading much better on
          // posterized / 16-color sources where the correct answer is
          // "these two colors" and the glyph mask should adapt.
          if (Opt.Mode = rmTronicShade) and (Opt.HQMode >= 2) and tcEnabled then
          begin
            // try normal orientation
            tmpErr := 0;
            if useVM then
              tmpErr := TileErrVM_HBlur(g, tcFGGuess, tcBGGuess, palLin, srcVM)
            else if hqDistValid then
            begin
              tmpErr := 0;
              for i := 0 to 127 do
                if (g.Rows[i div 8] and (1 shl (7-(i mod 8)))) <> 0 then
                  Inc(tmpErr, hqDist[i, tcFGGuess])
                else
                  Inc(tmpErr, hqDist[i, tcBGGuess]);
            end
            else
            begin
              tmpErr := 0;
              for py := 0 to 15 do
              begin
                row := g.Rows[py];
                for px := 0 to 7 do
                begin
                  bitOn := (row and (1 shl (7-px))) <> 0;
                  c := samples[py*8 + px];
                  if bitOn then
                    Inc(tmpErr, CellSampleDist2(c, pal[tcFGGuess], tcFGGuess, Opt))
                  else
                    Inc(tmpErr, CellSampleDist2(c, pal[tcBGGuess], tcBGGuess, Opt));
                end;
              end;
            end;
            if tmpErr < err then
            begin
              err := tmpErr;
              fg := tcFGGuess;
              bg := tcBGGuess;
            end;

            // try swapped orientation (rarely better if the shade glyph is inverted)
            if Opt.Ice or (tcBGGuess <= 7) then
            begin
              tmpErr := 0;
              if useVM then
                tmpErr := TileErrVM_HBlur(g, tcBGGuess, tcFGGuess, palLin, srcVM)
              else if hqDistValid then
              begin
                tmpErr := 0;
                for i := 0 to 127 do
                  if (g.Rows[i div 8] and (1 shl (7-(i mod 8)))) <> 0 then
                    Inc(tmpErr, hqDist[i, tcBGGuess])
                  else
                    Inc(tmpErr, hqDist[i, tcFGGuess]);
              end
              else
              begin
                tmpErr := 0;
                for py := 0 to 15 do
                begin
                  row := g.Rows[py];
                  for px := 0 to 7 do
                  begin
                    bitOn := (row and (1 shl (7-px))) <> 0;
                    c := samples[py*8 + px];
                    if bitOn then
                      Inc(tmpErr, CellSampleDist2(c, pal[tcBGGuess], tcBGGuess, Opt))
                    else
                      Inc(tmpErr, CellSampleDist2(c, pal[tcFGGuess], tcFGGuess, Opt));
                  end;
                end;
              end;
              if tmpErr < err then
              begin
                err := tmpErr;
                fg := tcBGGuess;
                bg := tcFGGuess;
                if not Opt.Ice then bg := bg and $07;
              end;
            end;
          end;

          // HQ micro-palette per glyph (very slow, but high quality):
          // pick a small set of palette colors that best match the cell, then try all fg/bg pairs from that set.
          if (Opt.HQMode >= 2) and (not useVM) and hqDistValid and (not ((Opt.Mode = rmTronicShade) and (Opt.TronicApplyMode = 1) and (curFG <> 255))) then
          begin
            FillChar(hqUsedColor, SizeOf(hqUsedColor), 0);
            hqNFG := 0;

            // Seed with current choices and two-cluster guesses.
            hqCandFG[hqNFG] := fg; Inc(hqNFG);
            hqCandFG[hqNFG] := bg; Inc(hqNFG);
            if tcEnabled then
            begin
              if hqNFG <= High(hqCandFG) then begin hqCandFG[hqNFG] := tcFGGuess; Inc(hqNFG); end;
              if hqNFG <= High(hqCandFG) then begin hqCandFG[hqNFG] := tcBGGuess; Inc(hqNFG); end;
            end;

            // Mark used
            for i := 0 to hqNFG-1 do
              if hqCandFG[i] <= 15 then
                hqUsedColor[hqCandFG[i]] := True;

            // Add candidate palette colors for this cell.
            //
            // In rmTronicShade we prefer using the colors that are actually
            // present in the cell (via the full 8x16 histogram sample). This
            // produces much more faithful ANSI-style blending on dither-heavy
            // art (PabloDraw / scene ANSI).
            if (Opt.Mode = rmTronicShade) and (Length(trCellHist) = COLS*Rows*16) then
            begin
              // Add up to 6 most frequent palette colors in this cell.
              for hqK := 1 to 6 do
              begin
                hqBestD := -1;  // best count
                hqBestI := -1;
                for i := 0 to 15 do
                  if not hqUsedColor[i] then
                  begin
                    hqCurD := trCellHist[cellIndex*16 + i];
                    if hqCurD > hqBestD then
                    begin
                      hqBestD := hqCurD;
                      hqBestI := i;
                    end;
                  end;

                // Stop once remaining colors have zero presence.
                if (hqBestI < 0) or (hqBestD <= 0) then Break;

                hqUsedColor[hqBestI] := True;
                if hqNFG <= High(hqCandFG) then begin hqCandFG[hqNFG] := Byte(hqBestI); Inc(hqNFG); end;
              end;

              // Also seed with neighbor colors to encourage ANSI-like coherence.
              if x > 0 then
              begin
                leftAttr := Cells[cellIndex - 1].Attr;
                leftFG := leftAttr and $0F;
                leftBG := (leftAttr shr 4) and $0F;
                if not Opt.Ice then leftBG := leftBG and $07;
                if not hqUsedColor[leftFG] then begin hqUsedColor[leftFG] := True; if hqNFG <= High(hqCandFG) then begin hqCandFG[hqNFG] := Byte(leftFG); Inc(hqNFG); end; end;
                if not hqUsedColor[leftBG] then begin hqUsedColor[leftBG] := True; if hqNFG <= High(hqCandFG) then begin hqCandFG[hqNFG] := Byte(leftBG); Inc(hqNFG); end; end;
              end;
              if y > 0 then
              begin
                topAttr := Cells[cellIndex - COLS].Attr;
                topFG := topAttr and $0F;
                topBG := (topAttr shr 4) and $0F;
                if not Opt.Ice then topBG := topBG and $07;
                if not hqUsedColor[topFG] then begin hqUsedColor[topFG] := True; if hqNFG <= High(hqCandFG) then begin hqCandFG[hqNFG] := Byte(topFG); Inc(hqNFG); end; end;
                if not hqUsedColor[topBG] then begin hqUsedColor[topBG] := True; if hqNFG <= High(hqCandFG) then begin hqCandFG[hqNFG] := Byte(topBG); Inc(hqNFG); end; end;
              end;

              // Ensure extreme anchors are available (helps many styles).
              if not hqUsedColor[0] then begin hqUsedColor[0] := True; if hqNFG <= High(hqCandFG) then begin hqCandFG[hqNFG] := 0; Inc(hqNFG); end; end;
              if not hqUsedColor[15] then begin hqUsedColor[15] := True; if hqNFG <= High(hqCandFG) then begin hqCandFG[hqNFG] := 15; Inc(hqNFG); end; end;
            end
            else
            begin
              // Fallback: add up to 4 best colors by summed distance across the cell.
              for hqK := 1 to 4 do
              begin
                hqBestD := High(Integer);
                hqBestI := -1;
                for i := 0 to 15 do
                  if not hqUsedColor[i] then
                  begin
                    hqCurD := 0;
                    for tmpIdx := 0 to 127 do
                      Inc(hqCurD, hqDist[tmpIdx, i]);
                    if hqCurD < hqBestD then
                    begin
                      hqBestD := hqCurD;
                      hqBestI := i;
                    end;
                  end;
                if hqBestI >= 0 then
                begin
                  hqUsedColor[hqBestI] := True;
                  if hqNFG <= High(hqCandFG) then begin hqCandFG[hqNFG] := Byte(hqBestI); Inc(hqNFG); end;
                end;
              end;
            end;

            bestPairErr := err;
            bestPairFG := fg;
            bestPairBG := bg;

            for tFG := 0 to hqNFG-1 do
              for tBG := 0 to hqNFG-1 do
              begin
                rfFG2 := hqCandFG[tFG];
                rfBG2 := hqCandFG[tBG];
                if (rfFG2 > 15) or (rfBG2 > 15) then Continue;
                if rfFG2 = rfBG2 then Continue;
                if (not Opt.Ice) and (rfBG2 >= 8) then Continue;

                tmpErr := 0;
                for py := 0 to 15 do
                begin
                  row := g.Rows[py];
                  for px := 0 to 7 do
                  begin
                    bitOn := (row and (1 shl (7-px))) <> 0;
                    tmpIdx := py*8 + px;
                    if bitOn then
                      Inc(tmpErr, hqDist[tmpIdx, rfFG2])
                    else
                      Inc(tmpErr, hqDist[tmpIdx, rfBG2]);
                  end;
                end;

                if tmpErr < bestPairErr then
                begin
                  bestPairErr := tmpErr;
                  bestPairFG := rfFG2;
                  bestPairBG := rfBG2;
                end;
              end;

            if bestPairErr < err then
            begin
              err := bestPairErr;
              fg := bestPairFG;
              bg := bestPairBG;
            end;
          end;
        // Optional shade-blend scoring: for the shade glyphs (░▒▓), allow
        // fg/bg pairs that approximate an intermediate color via perceptual
        // blending, rather than only strict per-pixel matching. This is the
        // main "colors are slightly off" fix.
        if (not useVM) and (not shaderPicked) and (Opt.ShadeBlend > 0) and
           ((g.Ch = CH_LIGHT) or (g.Ch = CH_MED) or (g.Ch = CH_DARK)) and
           (g.OnCount > 0) and (g.OnCount < 128) then
        begin
          w := Opt.ShadeBlend;
          case g.Ch of
            CH_LIGHT: alpha := 0.25;
            CH_MED:   alpha := 0.50;
            CH_DARK:  alpha := 0.75;
          else
            alpha := g.OnCount / 128.0;
          end;
// Effective/blended error for the current fg/bg choice
          blendCol := BlendLinear(pal[fg], pal[bg], alpha);
          if Opt.Mode = rmTronicShade then
            effOld := Int64(128) * DistLin22_2(avgAll, blendCol)
          else
            effOld := Int64(128) * PalDist2(avgAll, blendCol);

          // Find the fg/bg pair that best matches the blended target
          bestBlendD := High(Integer);
          bestFG2 := fg;
          bestBG2 := bg;
          for tFG := 0 to 15 do
            for tBG := 0 to 15 do
            begin
              bgIdx := tBG;
              if not Opt.Ice then bgIdx := bgIdx and $07;
              blendCol := BlendLinear(pal[tFG], pal[bgIdx], alpha);
              d := PalDist2(avgAll, blendCol);

              // When iCE is OFF, backgrounds are limited (0..7). Prefer using
              // bright foreground colors (9..15) so the image doesn't look dull.
              // This is a gentle tie-breaker / bias, not a hard rule.
              if (not Opt.Ice) and (tFG >= 9) and (tFG <= 15) then
              begin
                if d > 96 then Dec(d, 96) else d := 0;
              end;

              if d < bestBlendD then
              begin
                bestBlendD := d;
                bestFG2 := Byte(tFG);
                bestBG2 := Byte(bgIdx);
              end;
            end;
          effBest := Int64(128) * bestBlendD;

          // Blend strict pixel error with blended-color error.
          errOld := Round((1.0 - w) * err + w * effOld);
          errBest := Round((1.0 - w) * err + w * effBest);

          if errBest < errOld then
          begin
            fg := bestFG2;
            bg := bestBG2;
            err := errBest;
          end
          else
            err := errOld;
        end;


        // Edge keep: prefer solid-ish glyph coverage on high-contrast cells (crisper outlines)
        if (shaderParams.EdgeKeep > 0) and (edgeY > 40) and (alpha > 0) and (alpha < 1) then
          Inc(err, Round(shaderParams.EdgeKeep * (edgeY - 40) * 4500.0 * (alpha * (1.0 - alpha))));

        // Vertical smear: extra bias toward matching the cell above (classic "chain" feel)
        if (shaderParams.VerticalSmear > 0) and (y > 0) then
        begin
          topAttr := Cells[cellIndex - COLS].Attr;
          topFG := topAttr and $0F;
          topBG := (topAttr shr 4) and $0F;
          if not Opt.Ice then topBG := topBG and $07;
          pen := 0;
          if fg <> topFG then Inc(pen);
          if bg <> topBG then Inc(pen);
          if pen > 0 then
            Inc(err, Round(shaderParams.VerticalSmear * 30000.0) * pen);
        end;

        if Opt.GlyphSmooth > 0 then
        begin
          pen := 0;
          if x > 0 then
          begin
            leftAttr := Cells[cellIndex - 1].Attr;
            leftFG := leftAttr and $0F;
            leftBG := (leftAttr shr 4) and $0F;
            if not Opt.Ice then leftBG := leftBG and $07;
            if fg <> leftFG then Inc(pen);
            if bg <> leftBG then Inc(pen);
          end;
          if y > 0 then
          begin
            topAttr := Cells[cellIndex - COLS].Attr;
            topFG := topAttr and $0F;
            topBG := (topAttr shr 4) and $0F;
            if not Opt.Ice then topBG := topBG and $07;
            if fg <> topFG then Inc(pen);
            if bg <> topBG then Inc(pen);
          end;
          if pen > 0 then
            Inc(err, Round(Opt.GlyphSmooth * 50000.0) * pen);
        end;

        // When iCE is OFF, backgrounds are limited (0..7). Prefer using bright
        // foreground colors (9..15) a bit more across the whole image.
        if (not Opt.Ice) and (fg >= 9) and (fg <= 15) then
        begin
          if err > 12000 then Dec(err, 12000) else err := 0;
        end;

        if err < bestErr then
        begin
          bestErr := err;
          bestWasShader := shaderPicked;
          bestCh := g.Ch;
          bestFG := fg;
          bestBG := bg;
          bestGlyph := g;
        end;

        // Track best block/shade glyph separately so we can optionally prefer ░▒▓█ when it matches well.
        if IsBlockCh(g.Ch) and (err < bestBlockErr) then
        begin
          bestBlockErr := err;
          bestBlockWasShader := shaderPicked;
          bestBlockCh := g.Ch;
          bestBlockFG := fg;
          bestBlockBG := bg;
          bestBlockGlyph := g;

        end;
      end;


      // Optional: prefer block/shade glyphs (░▒▓█) when they match well enough.
      matchPct := 0;
      blockPct := 0;
      // Approx worst-case: 128 pixels * max RGB^2 distance (3*255^2)
      if bestErr < High(Int64) then
        matchPct := EnsureRange(Round(100.0 * (1.0 - (bestErr / (128.0 * 195075.0)))), 0, 100);
      if bestBlockErr < High(Int64) then
        blockPct := EnsureRange(Round(100.0 * (1.0 - (bestBlockErr / (128.0 * 195075.0)))), 0, 100);

      if (Opt.AutoShaderBlocksOnlyPct > 0) and (blockPct >= Opt.AutoShaderBlocksOnlyPct) then
      begin
        // Refine colors for the best block glyph too (AutoSwatch++)
        RefinePairLockedGlyph(bestBlockGlyph, samples, pal, palLin, srcVM, useVM, Opt, shaderParams, avgAll, baseBG, bestBlockFG, bestBlockBG);

        // If the match is poor, stabilize block colors using a 3x3 neighborhood average.
        if (Opt.AutoShader3x3BelowPct > 0) and (matchPct < Opt.AutoShader3x3BelowPct) then
        begin
          baseBG3 := NearestAnsi16(avgAll3, Opt.Palette);
          if not Opt.Ice then baseBG3 := baseBG3 and $07;
          RefinePairLockedGlyph(bestBlockGlyph, samples, pal, palLin, srcVM, useVM, Opt, shaderParams, avgAll3, baseBG3, bestBlockFG, bestBlockBG);
        end;

        // Replace the chosen cell with the block/shade version.
        bestWasShader := bestBlockWasShader;
        bestCh := bestBlockCh;
        bestFG := bestBlockFG;
        bestBG := bestBlockBG;
        bestGlyph := bestBlockGlyph;
      end;

      if (Opt.Mode = rmTronicShade) and (Opt.TronicApplyMode = 1) and (curFG <> 255) then
      begin
        // Glyph-only: keep current colors
        Cells[cellIndex].Ch := bestCh;
        // Keep Attr as-is
        bestFG := curFG;
        bestBG := curBG;
      end
      else
      begin
        // Refine FG/BG for the chosen glyph (AutoSwatch++)
        RefinePairLockedGlyph(bestGlyph, samples, pal, palLin, srcVM, useVM, Opt, shaderParams, avgAll, baseBG, bestFG, bestBG);
        Cells[cellIndex].Ch := bestCh;
        Cells[cellIndex].Attr := AttrByte(bestFG, bestBG, Opt.Ice);
      end;

      // Fill TronicShade render report for the final pass.
      if Assigned(rep) and (passNo = passes) then
      begin
        Inc(rep^.CellsTotal);
        if (oldCh <> Cells[cellIndex].Ch) or (oldAttr <> Cells[cellIndex].Attr) then
          Inc(rep^.CellsChanged);
        if (Opt.Mode = rmTronicShade) and (Opt.TronicApplyMode = 1) and trHadAttr then
          Inc(rep^.CellsLockedColors);
        if TronicShadeHasAny then
          Inc(rep^.CellsWithStylePrior);
        if gTronicEdge then
          Inc(rep^.CellsWithEdgeForce);

        rep^.SumBestErr := rep^.SumBestErr + bestErr;
        if bestErr < rep^.MinBestErr then rep^.MinBestErr := bestErr;
        if bestErr > rep^.MaxBestErr then rep^.MaxBestErr := bestErr;
        rep^.SumMatchPct := rep^.SumMatchPct + matchPct;

        // Tone error (target luma vs produced luma for the chosen glyph+colors)
        w := bestGlyph.OnCount / 128.0;
        if Opt.Mode = rmTronicShade then
          prodY := EnsureRange(Round(255.0 * (w * palYLin[bestFG] + (1.0 - w) * palYLin[bestBG])), 0, 255)
        else
          prodY := EnsureRange(Round(w * ((77*Integer(pal[bestFG].R) + 150*Integer(pal[bestFG].G) + 29*Integer(pal[bestFG].B)) shr 8)
                                     + (1.0 - w) * ((77*Integer(pal[bestBG].R) + 150*Integer(pal[bestBG].G) + 29*Integer(pal[bestBG].B)) shr 8)), 0, 255);
        toneErrI := gTronicTargetY - prodY;
        rep^.SumToneErrSigned := rep^.SumToneErrSigned + toneErrI;
        rep^.SumToneErrAbs := rep^.SumToneErrAbs + Abs(toneErrI);
      end;

      // TronicShade: optional cell-level luma error diffusion (various kernels)
      if cellDoDiff then
      begin
        // Produced luma from the chosen glyph+colors (coverage-weighted blend).
        w := bestGlyph.OnCount / 128.0;
        if Opt.Mode = rmTronicShade then
          prodY := EnsureRange(Round(255.0 * (w * palYLin[bestFG] + (1.0 - w) * palYLin[bestBG])), 0, 255)
        else
          prodY := EnsureRange(Round(w * ((77*Integer(pal[bestFG].R) + 150*Integer(pal[bestFG].G) + 29*Integer(pal[bestFG].B)) shr 8)
                                     + (1.0 - w) * ((77*Integer(pal[bestBG].R) + 150*Integer(pal[bestBG].G) + 29*Integer(pal[bestBG].B)) shr 8)), 0, 255);
        qErr := (gTronicTargetY - prodY);
        qScaled := qErr * (cellAmountPct / 100.0);

        // Helper: add weighted error to row buffers (bounds-checked)
        // dx is relative column offset; dy is 0 (same row) or 1/2 (future rows)
        // num/den is the kernel weight.
        // NOTE: We only store forward errors (no feedback into already-processed cells).
        // (Nested proc would be cleaner, but keep it inline for FPC speed.)

        case TTronicDiffusionModel(cellModelKind) of
          tdmSierraLite:
            begin
              // Sierra Lite (1D-ish):
              //   * 2/4 to x+1
              // 1/4 to next row x-1, 1/4 to next row x
              if x < COLS-1 then errRow[x+1] := errRow[x+1] + qScaled * (2.0/4.0);
              if y < Rows-1 then
              begin
                if x > 0 then errNextRow[x-1] := errNextRow[x-1] + qScaled * (1.0/4.0);
                errNextRow[x] := errNextRow[x] + qScaled * (1.0/4.0);
              end;
            end;

          tdmAtkinson:
            begin
              // Atkinson (sum = 6/8):
              // * 1/8 to x+1, x+2
              // 1/8 to next row x-1, x, x+1
              // 1/8 to row+2 x
              if x < COLS-1 then errRow[x+1] := errRow[x+1] + qScaled * (1.0/8.0);
              if x < COLS-2 then errRow[x+2] := errRow[x+2] + qScaled * (1.0/8.0);
              if y < Rows-1 then
              begin
                if x > 0 then errNextRow[x-1] := errNextRow[x-1] + qScaled * (1.0/8.0);
                errNextRow[x] := errNextRow[x] + qScaled * (1.0/8.0);
                if x < COLS-1 then errNextRow[x+1] := errNextRow[x+1] + qScaled * (1.0/8.0);
              end;
              // Row+2 x
              if y < Rows-2 then
                errNext2Row[x] := errNext2Row[x] + qScaled * (1.0/8.0);
            end;

          tdmJJN:
            begin
              // Jarvis-Judice-Ninke (48 denom)
              // same row: x+1 7/48, x+2 5/48
              if x < COLS-1 then errRow[x+1] := errRow[x+1] + qScaled * (7.0/48.0);
              if x < COLS-2 then errRow[x+2] := errRow[x+2] + qScaled * (5.0/48.0);
              if y < Rows-1 then
              begin
                if x > 1 then errNextRow[x-2] := errNextRow[x-2] + qScaled * (3.0/48.0);
                if x > 0 then errNextRow[x-1] := errNextRow[x-1] + qScaled * (5.0/48.0);
                errNextRow[x] := errNextRow[x] + qScaled * (7.0/48.0);
                if x < COLS-1 then errNextRow[x+1] := errNextRow[x+1] + qScaled * (5.0/48.0);
                if x < COLS-2 then errNextRow[x+2] := errNextRow[x+2] + qScaled * (3.0/48.0);
              end;
              // Row+2
              if y < Rows-2 then
              begin
                if x > 1 then errNext2Row[x-2] := errNext2Row[x-2] + qScaled * (1.0/48.0);
                if x > 0 then errNext2Row[x-1] := errNext2Row[x-1] + qScaled * (3.0/48.0);
                errNext2Row[x] := errNext2Row[x] + qScaled * (5.0/48.0);
                if x < COLS-1 then errNext2Row[x+1] := errNext2Row[x+1] + qScaled * (3.0/48.0);
                if x < COLS-2 then errNext2Row[x+2] := errNext2Row[x+2] + qScaled * (1.0/48.0);
              end;
            end;

        else
          begin
            // Default: Floyd–Steinberg
            if x < COLS-1 then errRow[x+1] := errRow[x+1] + qScaled * (7.0/16.0);
            if y < Rows-1 then
            begin
              if x > 0 then errNextRow[x-1] := errNextRow[x-1] + qScaled * (3.0/16.0);
              errNextRow[x] := errNextRow[x] + qScaled * (5.0/16.0);
              if x < COLS-1 then errNextRow[x+1] := errNextRow[x+1] + qScaled * (1.0/16.0);
            end;
          end;
        end;
      end;

      // Accumulate original-color samples for any hinted ANSI indexes actually used.
      // This is used to gently re-fit ONLY those palette entries between passes.
      if doRefitHintPal and (passNo < passes) then
      begin
        for py := 0 to 15 do
        begin
          row := bestGlyph.Rows[py];
          for px := 0 to 7 do
          begin
            bitOn := (row and (1 shl (7 - px))) <> 0;
            tmpIdx := bestFG; if not bitOn then tmpIdx := bestBG;
            if hintedIdx[tmpIdx] then
            begin
              Inc(sumHintR[tmpIdx], samplesOrig[py*8 + px].R);
              Inc(sumHintG[tmpIdx], samplesOrig[py*8 + px].G);
              Inc(sumHintB[tmpIdx], samplesOrig[py*8 + px].B);
              Inc(cntHint[tmpIdx]);
            end;
          end;
        end;
      end;
    end;
  end;

  // After finishing a pass, gently re-fit ONLY hinted palette entries toward
  // the colors the solver actually used in this pass. This improves convergence
  // without drifting the rest of the palette.
  if doRefitHintPal and (passNo < passes) then
  begin
    for tmpIdx := 0 to 15 do
    begin
      if (not hintedIdx[tmpIdx]) or (cntHint[tmpIdx] <= 0) then Continue;
      c.R := ClampByte(Round(sumHintR[tmpIdx] / cntHint[tmpIdx]));
      c.G := ClampByte(Round(sumHintG[tmpIdx] / cntHint[tmpIdx]));
      c.B := ClampByte(Round(sumHintB[tmpIdx] / cntHint[tmpIdx]));
      // Lerp current override toward the used average.
      blendCol := Palette16(Opt.Palette, tmpIdx);
      blendCol.R := ClampByte(Round((1.0 - refitAlpha) * blendCol.R + refitAlpha * c.R));
      blendCol.G := ClampByte(Round((1.0 - refitAlpha) * blendCol.G + refitAlpha * c.G));
      blendCol.B := ClampByte(Round((1.0 - refitAlpha) * blendCol.B + refitAlpha * c.B));
      SetHintPaletteOverride(tmpIdx, blendCol);
    end;
    // Rebuild local palette arrays for the next pass.
    for tmpIdx := 0 to 15 do pal[tmpIdx] := Palette16(Opt.Palette, tmpIdx);
    if useVM then
      for tmpIdx := 0 to 15 do palLin[tmpIdx] := RGBToLin22(pal[tmpIdx]);
  end;

  end;

end;


end;

function AvgRGBWindowCenteredMapped(
  const Img: TFPCustomImage;
  sx, sy, gridW, gridH: Integer;
  winX, winY: Integer;
  const SrcRect: TRect
): TRGB;
var
  crop: TRect;
  cropW, cropH: Integer;
  cx, cy: Integer;
  x0,x1,y0,y1: Integer;
  x,y: Integer;
  sumR,sumG,sumB: Int64;
  cnt: Int64;
  c: TRGB;
  halfX, halfY: Integer;
begin
  crop := SrcRect;
  cropW := crop.Right - crop.Left;
  cropH := crop.Bottom - crop.Top;
  if cropW < 1 then cropW := 1;
  if cropH < 1 then cropH := 1;

  cx := crop.Left + ((2*sx + 1) * cropW) div (2*gridW);
  cy := crop.Top  + ((2*sy + 1) * cropH) div (2*gridH);

  if winX < 1 then winX := 1;
  if winY < 1 then winY := 1;
  halfX := winX div 2;
  halfY := winY div 2;

  x0 := cx - halfX;
  y0 := cy - halfY;
  x1 := x0 + winX;
  y1 := y0 + winY;

  if x0 < crop.Left then x0 := crop.Left;
  if y0 < crop.Top then y0 := crop.Top;
  if x1 > crop.Right then x1 := crop.Right;
  if y1 > crop.Bottom then y1 := crop.Bottom;

  sumR := 0; sumG := 0; sumB := 0; cnt := 0;
  for y := y0 to y1 - 1 do
    for x := x0 to x1 - 1 do
    begin
      c := FPColorToRGB(Img.Colors[x, y]);
      Inc(sumR, c.R); Inc(sumG, c.G); Inc(sumB, c.B);
      Inc(cnt);
    end;

  if cnt = 0 then Exit(RGB(0,0,0));
  Result.R := Byte(sumR div cnt);
  Result.G := Byte(sumG div cnt);
  Result.B := Byte(sumB div cnt);
end;

function AvgRGBWindowCenteredMappedPalFit(
  const Img: TFPCustomImage;
  sx, sy, gridW, gridH: Integer;
  winX, winY: Integer;
  const SrcRect: TRect;
  const Opt: TConvertOptions;
  Gamma, Contrast, Saturation, Brightness: Double
): TRGB;
var
  crop: TRect;
  cx, cy: Integer;
  x0,x1,y0,y1: Integer;
  x,y: Integer;
  sumR,sumG,sumB: Int64;
  cnt: Int64;
  c: TRGB;
begin
  crop := SrcRect;
  if (crop.Right <= crop.Left) or (crop.Bottom <= crop.Top) then
    crop := Rect(0, 0, Img.Width, Img.Height);

  // Map subpixel grid coord -> image coord (center)
  cx := crop.Left + Round((sx + 0.5) * (crop.Right - crop.Left) / gridW);
  cy := crop.Top  + Round((sy + 0.5) * (crop.Bottom - crop.Top) / gridH);

  x0 := cx - (winX div 2);
  y0 := cy - (winY div 2);
  x1 := x0 + winX;
  y1 := y0 + winY;

  if x0 < crop.Left then x0 := crop.Left;
  if y0 < crop.Top then y0 := crop.Top;
  if x1 > crop.Right then x1 := crop.Right;
  if y1 > crop.Bottom then y1 := crop.Bottom;

  sumR := 0; sumG := 0; sumB := 0; cnt := 0;
  for y := y0 to y1 - 1 do
    for x := x0 to x1 - 1 do
    begin
      c := FPColorToRGB(Img.Colors[x, y]);
      c := TransformRGB(c, Gamma, Contrast, Saturation, Brightness);
      c := PreMatchMapColor(c, Opt, x, y);
      Inc(sumR, c.R); Inc(sumG, c.G); Inc(sumB, c.B);
      Inc(cnt);
    end;

  if cnt = 0 then Exit(RGB(0,0,0));
  Result.R := ClampByte(Integer(sumR div cnt));
  Result.G := ClampByte(Integer(sumG div cnt));
  Result.B := ClampByte(Integer(sumB div cnt));
end;

procedure QuantizeSubpixels(
  const Img: TFPCustomImage;
  subH: Integer;
  winX, winY: Integer;
  const SrcRect: TRect;
  Dither: TDitherMode;
  Strength: Double;
  Pal: TPaletteKind;
  PalMatch: Boolean;
  Gamma, Contrast, Saturation, Brightness: Double;
  const Opt: TConvertOptions;
  BasePct, SpanPct: Integer;
  var idx: array of Byte
);
type
  TDoubleArray = array of Double;
var
  x, y: Integer;
  ci: Integer;
  pad: Integer;
  maxDY: Integer;
  useErr: Boolean;

  err0R, err0G, err0B: TDoubleArray;
  err1R, err1G, err1B: TDoubleArray;
  err2R, err2G, err2B: TDoubleArray;
  tmp: TDoubleArray;

  inC, outC: TRGB;
  rr, gg, bb: Double;
  eR, eG, eB: Double;

  function ClampD(v: Double): Double; inline;
  begin
    if v < 0 then Exit(0);
    if v > 255 then Exit(255);
    Result := v;
  end;

  procedure AddErr(var arr: TDoubleArray; pos: Integer; v: Double); inline;
  begin
    if (pos >= 0) and (pos < Length(arr)) then
      arr[pos] := arr[pos] + v;
  end;

  procedure ClearArray(var a: TDoubleArray); inline;
  var i: Integer;
  begin
    for i := 0 to High(a) do a[i] := 0;
  end;

  function Bayer4Delta(ax, ay: Integer): Double; inline;
  const
    M: array[0..3,0..3] of Integer = (
      ( 0,  8,  2, 10),
      (12,  4, 14,  6),
      ( 3, 11,  1,  9),
      (15,  7, 13,  5)
    );
  var v: Integer;
  begin
    v := M[ay and 3][ax and 3]; // 0..15
    // scale to [-0.5 .. +0.5]
    Result := ((v + 0.5) / 16.0) - 0.5;
  end;

begin
  // Error diffusion needs padding for -2..+2 taps
  pad := 2;

  useErr := Dither in [dmFS, dmAtkinson, dmJJN, dmStucki, dmSierraLite];

  if Strength < 0 then Strength := 0;
  if Strength > 3.0 then Strength := 3.0;


  // max rows ahead needed
  case Dither of
    dmAtkinson, dmJJN, dmStucki: maxDY := 2;
  else
    if useErr then maxDY := 1 else maxDY := 0;
  end;

  SetLength(err0R, SUBW + pad*2); SetLength(err0G, SUBW + pad*2); SetLength(err0B, SUBW + pad*2);
  SetLength(err1R, SUBW + pad*2); SetLength(err1G, SUBW + pad*2); SetLength(err1B, SUBW + pad*2);
  ClearArray(err0R); ClearArray(err0G); ClearArray(err0B);
  ClearArray(err1R); ClearArray(err1G); ClearArray(err1B);

  if maxDY = 2 then
  begin
    SetLength(err2R, SUBW + pad*2); SetLength(err2G, SUBW + pad*2); SetLength(err2B, SUBW + pad*2);
    ClearArray(err2R); ClearArray(err2G); ClearArray(err2B);
  end;

  for y := 0 to subH - 1 do
  begin
    if Assigned(Opt.CancelFlag) and Opt.CancelFlag^ then
      raise Exception.Create('Canceled');
    if Assigned(Opt.OnProgress) and ((y and 3) = 0) then
      Opt.OnProgress(BasePct + (y * SpanPct) div Max(1, subH-1), '');
    for x := 0 to SUBW - 1 do
    begin
      if PalMatch then
        inC := AvgRGBWindowCenteredMappedPalFit(Img, x, y, SUBW, subH, winX, winY, SrcRect, Opt, Gamma, Contrast, Saturation, Brightness)
      else
      begin
        inC := AvgRGBWindowCenteredMapped(Img, x, y, SUBW, subH, winX, winY, SrcRect);
        inC := TransformRGB(inC, Gamma, Contrast, Saturation, Brightness);
      end;
// Ordered dithering (simple Bayer 4x4)
      if Dither = dmBayer4 then
      begin
        rr := ClampD(inC.R + Bayer4Delta(x, y) * 32.0 * Strength);
        gg := ClampD(inC.G + Bayer4Delta(x, y) * 32.0 * Strength);
        bb := ClampD(inC.B + Bayer4Delta(x, y) * 32.0 * Strength);
        inC.R := ClampByte(Round(rr));
        inC.G := ClampByte(Round(gg));
        inC.B := ClampByte(Round(bb));
      end
      else if useErr then
      begin
        rr := ClampD(inC.R + err0R[x + pad]);
        gg := ClampD(inC.G + err0G[x + pad]);
        bb := ClampD(inC.B + err0B[x + pad]);
        inC.R := ClampByte(Round(rr));
        inC.G := ClampByte(Round(gg));
        inC.B := ClampByte(Round(bb));
      end;

      ci := NearestAnsi16(inC, Pal);
      idx[y*SUBW + x] := Byte(ci);

      if useErr then
      begin
        outC := Palette16(Pal, ci);
        eR := (Integer(inC.R) - Integer(outC.R)) * Strength;
        eG := (Integer(inC.G) - Integer(outC.G)) * Strength;
        eB := (Integer(inC.B) - Integer(outC.B)) * Strength;

        case Dither of
          dmFS:
            begin
              // (x+1,0) 7/16
              AddErr(err0R, x + pad + 1, eR * 7.0/16.0);
              AddErr(err0G, x + pad + 1, eG * 7.0/16.0);
              AddErr(err0B, x + pad + 1, eB * 7.0/16.0);

              // next row: (-1,1) 3/16, (0,1) 5/16, (1,1) 1/16
              AddErr(err1R, x + pad - 1, eR * 3.0/16.0);
              AddErr(err1G, x + pad - 1, eG * 3.0/16.0);
              AddErr(err1B, x + pad - 1, eB * 3.0/16.0);

              AddErr(err1R, x + pad + 0, eR * 5.0/16.0);
              AddErr(err1G, x + pad + 0, eG * 5.0/16.0);
              AddErr(err1B, x + pad + 0, eB * 5.0/16.0);

              AddErr(err1R, x + pad + 1, eR * 1.0/16.0);
              AddErr(err1G, x + pad + 1, eG * 1.0/16.0);
              AddErr(err1B, x + pad + 1, eB * 1.0/16.0);
            end;

          dmAtkinson:
            begin
              // 1/8 to 6 neighbors
              AddErr(err0R, x + pad + 1, eR * 1.0/8.0);
              AddErr(err0G, x + pad + 1, eG * 1.0/8.0);
              AddErr(err0B, x + pad + 1, eB * 1.0/8.0);

              AddErr(err0R, x + pad + 2, eR * 1.0/8.0);
              AddErr(err0G, x + pad + 2, eG * 1.0/8.0);
              AddErr(err0B, x + pad + 2, eB * 1.0/8.0);

              AddErr(err1R, x + pad - 1, eR * 1.0/8.0);
              AddErr(err1G, x + pad - 1, eG * 1.0/8.0);
              AddErr(err1B, x + pad - 1, eB * 1.0/8.0);

              AddErr(err1R, x + pad + 0, eR * 1.0/8.0);
              AddErr(err1G, x + pad + 0, eG * 1.0/8.0);
              AddErr(err1B, x + pad + 0, eB * 1.0/8.0);

              AddErr(err1R, x + pad + 1, eR * 1.0/8.0);
              AddErr(err1G, x + pad + 1, eG * 1.0/8.0);
              AddErr(err1B, x + pad + 1, eB * 1.0/8.0);

              AddErr(err2R, x + pad + 0, eR * 1.0/8.0);
              AddErr(err2G, x + pad + 0, eG * 1.0/8.0);
              AddErr(err2B, x + pad + 0, eB * 1.0/8.0);
            end;

          dmJJN:
            begin
              // Jarvis-Judice-Ninke, denom 48
              AddErr(err0R, x + pad + 1, eR * 7.0/48.0);
              AddErr(err0G, x + pad + 1, eG * 7.0/48.0);
              AddErr(err0B, x + pad + 1, eB * 7.0/48.0);

              AddErr(err0R, x + pad + 2, eR * 5.0/48.0);
              AddErr(err0G, x + pad + 2, eG * 5.0/48.0);
              AddErr(err0B, x + pad + 2, eB * 5.0/48.0);

              // row +1: -2..+2 (3,5,7,5,3)
              AddErr(err1R, x + pad - 2, eR * 3.0/48.0);
              AddErr(err1G, x + pad - 2, eG * 3.0/48.0);
              AddErr(err1B, x + pad - 2, eB * 3.0/48.0);

              AddErr(err1R, x + pad - 1, eR * 5.0/48.0);
              AddErr(err1G, x + pad - 1, eG * 5.0/48.0);
              AddErr(err1B, x + pad - 1, eB * 5.0/48.0);

              AddErr(err1R, x + pad + 0, eR * 7.0/48.0);
              AddErr(err1G, x + pad + 0, eG * 7.0/48.0);
              AddErr(err1B, x + pad + 0, eB * 7.0/48.0);

              AddErr(err1R, x + pad + 1, eR * 5.0/48.0);
              AddErr(err1G, x + pad + 1, eG * 5.0/48.0);
              AddErr(err1B, x + pad + 1, eB * 5.0/48.0);

              AddErr(err1R, x + pad + 2, eR * 3.0/48.0);
              AddErr(err1G, x + pad + 2, eG * 3.0/48.0);
              AddErr(err1B, x + pad + 2, eB * 3.0/48.0);

              // row +2: -2..+2 (1,3,5,3,1)
              AddErr(err2R, x + pad - 2, eR * 1.0/48.0);
              AddErr(err2G, x + pad - 2, eG * 1.0/48.0);
              AddErr(err2B, x + pad - 2, eB * 1.0/48.0);

              AddErr(err2R, x + pad - 1, eR * 3.0/48.0);
              AddErr(err2G, x + pad - 1, eG * 3.0/48.0);
              AddErr(err2B, x + pad - 1, eB * 3.0/48.0);

              AddErr(err2R, x + pad + 0, eR * 5.0/48.0);
              AddErr(err2G, x + pad + 0, eG * 5.0/48.0);
              AddErr(err2B, x + pad + 0, eB * 5.0/48.0);

              AddErr(err2R, x + pad + 1, eR * 3.0/48.0);
              AddErr(err2G, x + pad + 1, eG * 3.0/48.0);
              AddErr(err2B, x + pad + 1, eB * 3.0/48.0);

              AddErr(err2R, x + pad + 2, eR * 1.0/48.0);
              AddErr(err2G, x + pad + 2, eG * 1.0/48.0);
              AddErr(err2B, x + pad + 2, eB * 1.0/48.0);
            end;

          dmStucki:
            begin
              // Stucki, denom 42 (8,4) and (2,4,8,4,2) and (1,2,4,2,1)
              AddErr(err0R, x + pad + 1, eR * 8.0/42.0);
              AddErr(err0G, x + pad + 1, eG * 8.0/42.0);
              AddErr(err0B, x + pad + 1, eB * 8.0/42.0);

              AddErr(err0R, x + pad + 2, eR * 4.0/42.0);
              AddErr(err0G, x + pad + 2, eG * 4.0/42.0);
              AddErr(err0B, x + pad + 2, eB * 4.0/42.0);

              AddErr(err1R, x + pad - 2, eR * 2.0/42.0);
              AddErr(err1G, x + pad - 2, eG * 2.0/42.0);
              AddErr(err1B, x + pad - 2, eB * 2.0/42.0);

              AddErr(err1R, x + pad - 1, eR * 4.0/42.0);
              AddErr(err1G, x + pad - 1, eG * 4.0/42.0);
              AddErr(err1B, x + pad - 1, eB * 4.0/42.0);

              AddErr(err1R, x + pad + 0, eR * 8.0/42.0);
              AddErr(err1G, x + pad + 0, eG * 8.0/42.0);
              AddErr(err1B, x + pad + 0, eB * 8.0/42.0);

              AddErr(err1R, x + pad + 1, eR * 4.0/42.0);
              AddErr(err1G, x + pad + 1, eG * 4.0/42.0);
              AddErr(err1B, x + pad + 1, eB * 4.0/42.0);

              AddErr(err1R, x + pad + 2, eR * 2.0/42.0);
              AddErr(err1G, x + pad + 2, eG * 2.0/42.0);
              AddErr(err1B, x + pad + 2, eB * 2.0/42.0);

              AddErr(err2R, x + pad - 2, eR * 1.0/42.0);
              AddErr(err2G, x + pad - 2, eG * 1.0/42.0);
              AddErr(err2B, x + pad - 2, eB * 1.0/42.0);

              AddErr(err2R, x + pad - 1, eR * 2.0/42.0);
              AddErr(err2G, x + pad - 1, eG * 2.0/42.0);
              AddErr(err2B, x + pad - 1, eB * 2.0/42.0);

              AddErr(err2R, x + pad + 0, eR * 4.0/42.0);
              AddErr(err2G, x + pad + 0, eG * 4.0/42.0);
              AddErr(err2B, x + pad + 0, eB * 4.0/42.0);

              AddErr(err2R, x + pad + 1, eR * 2.0/42.0);
              AddErr(err2G, x + pad + 1, eG * 2.0/42.0);
              AddErr(err2B, x + pad + 1, eB * 2.0/42.0);

              AddErr(err2R, x + pad + 2, eR * 1.0/42.0);
              AddErr(err2G, x + pad + 2, eG * 1.0/42.0);
              AddErr(err2B, x + pad + 2, eB * 1.0/42.0);
            end;

          dmSierraLite:
            begin
              // Sierra Lite, denom 4: (x+1,0)*2, (-1,1)*1, (0,1)*1
              AddErr(err0R, x + pad + 1, eR * 2.0/4.0);
              AddErr(err0G, x + pad + 1, eG * 2.0/4.0);
              AddErr(err0B, x + pad + 1, eB * 2.0/4.0);

              AddErr(err1R, x + pad - 1, eR * 1.0/4.0);
              AddErr(err1G, x + pad - 1, eG * 1.0/4.0);
              AddErr(err1B, x + pad - 1, eB * 1.0/4.0);

              AddErr(err1R, x + pad + 0, eR * 1.0/4.0);
              AddErr(err1G, x + pad + 0, eG * 1.0/4.0);
              AddErr(err1B, x + pad + 0, eB * 1.0/4.0);
            end;
        end;
      end;
    end;

    // advance diffusion rows
    if useErr then
    begin
      if maxDY = 1 then
      begin
        // err0 <- err1 ; clear err1
        tmp := err0R; err0R := err1R; err1R := tmp; ClearArray(err1R);
        tmp := err0G; err0G := err1G; err1G := tmp; ClearArray(err1G);
        tmp := err0B; err0B := err1B; err1B := tmp; ClearArray(err1B);
      end
      else
      begin
        // err0 <- err1 ; err1 <- err2 ; clear err2
        tmp := err0R; err0R := err1R; err1R := err2R; err2R := tmp; ClearArray(err2R);
        tmp := err0G; err0G := err1G; err1G := err2G; err2G := tmp; ClearArray(err2G);
        tmp := err0B; err0B := err1B; err1B := err2B; err2B := tmp; ClearArray(err2B);
      end;
    end;
  end;
end;

function Luma(const c: TRGB): Integer; inline;
begin
  // Rec.601 luma approximation.
  Result := (Integer(c.R) * 299 + Integer(c.G) * 587 + Integer(c.B) * 114) div 1000;
end;

function MajorityOrAvgNearest(
  a, b, c, d: Byte;
  Pal: TPaletteKind
): Byte; inline;
var
  ca, cb, cc, cd: TRGB;
  sumR, sumG, sumB: Integer;
  avg: TRGB;
begin
  // Fast majority vote.
  if (a = b) or (a = c) or (a = d) then Exit(a);
  if (b = c) or (b = d) then Exit(b);
  if (c = d) then Exit(c);

  // No majority: pick the nearest palette color to the average.
  ca := Palette16(Pal, a);
  cb := Palette16(Pal, b);
  cc := Palette16(Pal, c);
  cd := Palette16(Pal, d);
  sumR := Integer(ca.R) + Integer(cb.R) + Integer(cc.R) + Integer(cd.R);
  sumG := Integer(ca.G) + Integer(cb.G) + Integer(cc.G) + Integer(cd.G);
  sumB := Integer(ca.B) + Integer(cb.B) + Integer(cc.B) + Integer(cd.B);
  avg.R := ClampByte(sumR div 4);
  avg.G := ClampByte(sumG div 4);
  avg.B := ClampByte(sumB div 4);
  Result := Byte(NearestAnsi16(avg, Pal));
end;

function AvgNearest(
  a, b, c, d: Byte;
  Pal: TPaletteKind
): Byte; inline;
var
  ca, cb, cc, cd: TRGB;
  sumR, sumG, sumB: Integer;
  avg: TRGB;
begin
  ca := Palette16(Pal, a);
  cb := Palette16(Pal, b);
  cc := Palette16(Pal, c);
  cd := Palette16(Pal, d);
  sumR := Integer(ca.R) + Integer(cb.R) + Integer(cc.R) + Integer(cd.R);
  sumG := Integer(ca.G) + Integer(cb.G) + Integer(cc.G) + Integer(cd.G);
  sumB := Integer(ca.B) + Integer(cb.B) + Integer(cc.B) + Integer(cd.B);
  avg.R := ClampByte(sumR div 4);
  avg.G := ClampByte(sumG div 4);
  avg.B := ClampByte(sumB div 4);
  Result := Byte(NearestAnsi16(avg, Pal));
end;

function BritePick(
  a, b, c, d: Byte;
  Pal: TPaletteKind
): Byte; inline;
var
  ca, cb, cc, cd: TRGB;
  la, lb, lc, ld: Integer;
begin
  ca := Palette16(Pal, a);
  cb := Palette16(Pal, b);
  cc := Palette16(Pal, c);
  cd := Palette16(Pal, d);
  la := Luma(ca);
  lb := Luma(cb);
  lc := Luma(cc);
  ld := Luma(cd);
  Result := a;
  if lb > la then begin la := lb; Result := b; end;
  if lc > la then begin la := lc; Result := c; end;
  if ld > la then begin la := ld; Result := d; end;
end;

procedure ApplyAnsiRezFilterParity2(
  var idx: array of Byte;
  W, H: Integer;
  Filter: TAnsiRezFilter;
  Pal: TPaletteKind
);
var
  src: TByteArray;
  x, y: Integer;
  x0, x1, y0, y1: Integer;
  a, b, c, d: Byte;
  outv: Byte;
begin
  if (Filter = afNone) or (W <= 0) or (H <= 0) then Exit;

  // Copy so the filter is stable (read old, write new).
  SetLength(src, Length(idx));
  if Length(src) <> Length(idx) then Exit;
  Move(idx[0], src[0], Length(idx));

  for y := 0 to H - 1 do
  begin
    // Keep parity plane; use ±2 sampling so we don't mix subpixel quadrants.
    if y >= 2 then y0 := y - 2 else y0 := y;
    if y + 2 < H then y1 := y + 2 else y1 := y;
    for x := 0 to W - 1 do
    begin
      if x >= 2 then x0 := x - 2 else x0 := x;
      if x + 2 < W then x1 := x + 2 else x1 := x;

      a := src[y0*W + x0];
      b := src[y0*W + x1];
      c := src[y1*W + x0];
      d := src[y1*W + x1];

      case Filter of
        afMedian: outv := MajorityOrAvgNearest(a, b, c, d, Pal);
        afBlend:  outv := AvgNearest(a, b, c, d, Pal);
        afBrite:  outv := BritePick(a, b, c, d, Pal);
      else
        outv := src[y*W + x];
      end;
      idx[y*W + x] := outv;
    end;
  end;
end;

procedure ApplyAnsiRezFilter4x4(
  var idx: array of Byte;
  W, H: Integer;
  Pal: TPaletteKind
);
var
  xParity, yParity: Integer;
  x, y: Integer;
  a, b, c, d: Byte;
  outv: Byte;
  x1, y1: Integer;
begin
  // "Fat pixel" look: operate on 2x2 character-cell neighborhoods, but keep quadrant parity.
  for yParity := 0 to 1 do
    for xParity := 0 to 1 do
    begin
      y := yParity;
      while y < H do
      begin
        x := xParity;
        while x < W do
        begin
          x1 := x + 2; if x1 >= W then x1 := x;
          y1 := y + 2; if y1 >= H then y1 := y;

          a := idx[y*W + x];
          b := idx[y*W + x1];
          c := idx[y1*W + x];
          d := idx[y1*W + x1];

          outv := MajorityOrAvgNearest(a, b, c, d, Pal);
          idx[y*W + x] := outv;
          idx[y*W + x1] := outv;
          idx[y1*W + x] := outv;
          idx[y1*W + x1] := outv;

          Inc(x, 4);
        end;
        Inc(y, 4);
      end;
    end;
end;

function ErrFull(const tl,tr,bl,br, p: TRGB): Int64; inline;
begin
  Result := Int64(Dist2(tl,p)) + Dist2(tr,p) + Dist2(bl,p) + Dist2(br,p);
end;

function ErrTB(const tl,tr,bl,br, topP, botP: TRGB): Int64; inline;
begin
  Result := Int64(Dist2(tl,topP)) + Dist2(tr,topP) + Dist2(bl,botP) + Dist2(br,botP);
end;

function ErrLR(const tl,tr,bl,br, leftP, rightP: TRGB): Int64; inline;
begin
  Result := Int64(Dist2(tl,leftP)) + Dist2(bl,leftP) + Dist2(tr,rightP) + Dist2(br,rightP);
end;

function ErrMix4(const tl,tr,bl,br, mixP: TRGB): Int64; inline;
begin
  Result := Int64(Dist2(tl,mixP)) + Dist2(tr,mixP) + Dist2(bl,mixP) + Dist2(br,mixP);
end;

procedure PickShadeCell(
  const tl,tr,bl,br: TRGB;
  Pal: TPaletteKind;
  Ice: Boolean;
  AllowSideBlocks: Boolean;
  var bestCh: Byte; var bestFG, bestBG: Byte; var bestE: Int64
);
const
  // For blended shade chars: 0%..100% foreground coverage
  Alphas: array[0..4] of Double = (0.00, 0.25, 0.50, 0.75, 1.00);
  ShadeChars:  array[0..4] of Byte   = (CH_SPACE, CH_LIGHT, CH_MED, CH_DARK, CH_FULL);
var
  fgI, bgI, jj: Integer;
  mixP: TRGB;
  target: TRGB;
  e: Int64;
  maxBG: Integer;

  function NearestIndexMax(const c: TRGB; maxI: Integer): Integer; inline;
  var
    i, bestI, bestD, d: Integer;
    p: TRGB;
  begin
    bestI := 0;
    bestD := MaxInt;
    for i := 0 to maxI do
    begin
      p := Palette16(Pal, i);
      d := PalDist2(c, p);
      if d < bestD then begin bestD := d; bestI := i; end;
    end;
    Result := bestI;
  end;

  procedure ConsiderHalfBlock(const ch: Byte; const fgC, bgC: TRGB;
                             fgOnTL, fgOnTR, fgOnBL, fgOnBR: Boolean);
  var
    fgi2, bgi2: Integer;
    pFG, pBG: TRGB;
    ee: Int64;
  begin
    // Foreground can always be 0..15, background may be limited by iCE
    fgi2 := NearestAnsi16(fgC, Pal);
    bgi2 := NearestIndexMax(bgC, maxBG);
    pFG := Palette16(Pal, fgi2);
    pBG := Palette16(Pal, bgi2);

    ee := 0;
    if fgOnTL then ee := ee + Dist2(tl, pFG) else ee := ee + Dist2(tl, pBG);
    if fgOnTR then ee := ee + Dist2(tr, pFG) else ee := ee + Dist2(tr, pBG);
    if fgOnBL then ee := ee + Dist2(bl, pFG) else ee := ee + Dist2(bl, pBG);
    if fgOnBR then ee := ee + Dist2(br, pFG) else ee := ee + Dist2(br, pBG);

    if ee < bestE then
    begin
      bestE := ee;
      bestCh := ch;
      bestFG := Byte(fgi2);
      bestBG := Byte(bgi2);
    end;
  end;

var
  topAvg, botAvg, leftAvg, rightAvg: TRGB;
begin
  bestE := High(Int64);

  if Ice then maxBG := 15 else maxBG := 7;

  target := Mix4(tl,tr,bl,br);

  // 1) Blended shade blocks: match the average color of the 2x2 block using shade coverage FG/BG mix by coverage percentage
  for bgI := 0 to maxBG do
    for fgI := 0 to 15 do
      for jj := 0 to 4 do
      begin
        mixP := Blend(Palette16(Pal, fgI), Palette16(Pal, bgI), Alphas[jj]);
        e := Int64(Dist2(target, mixP)) * 4;

        // When iCE is OFF, backgrounds are limited (0..7). Prefer using bright
        // foreground colors (9..15) a bit more across the whole image.
        //
        // Extra: even if the chosen glyph is a space (0% FG coverage), carry a
        // bright foreground attribute when possible. This helps workflows that
        // later treat "no background"/transparent output as "use FG".
        if (fgI >= 9) and (fgI <= 15) then
        begin
          if not Ice then
          begin
            // Base bias
            if e > 12000 then Dec(e, 12000) else e := 0;
            // Stronger bias when the glyph would be space
            if jj = 0 then
            begin
              if e > 18000 then Dec(e, 18000) else e := 0;
            end;
          end
          else
          begin
            // With iCE on, keep it subtle (still useful for style)
            if jj = 0 then
              if e > 3000 then Dec(e, 3000) else e := 0;
          end;
        end;

        if e < bestE then
        begin
          bestE := e;
          bestCh := ShadeChars[jj];
          bestFG := Byte(fgI);
          bestBG := Byte(bgI);
        end;
      end;

  // 2) Half and side blocks: match what the glyph actually shows in the cell.
  //    These are effectively 50% coverage, but directional (top/bottom/left/right).
  topAvg   := Mix2(tl, tr);
  botAvg   := Mix2(bl, br);
  leftAvg  := Mix2(tl, bl);
  rightAvg := Mix2(tr, br);

  // ▀ : foreground on top half
  ConsiderHalfBlock(CH_UP,    topAvg,  botAvg,  True, True, False, False);
  // ▄ : foreground on bottom half
  ConsiderHalfBlock(CH_LOW,   botAvg,  topAvg,  False, False, True, True);
  if AllowSideBlocks then
  begin
    // ▌ : foreground on left half
    ConsiderHalfBlock(CH_LEFT,  leftAvg, rightAvg, True, False, True, False);
    // ▐ : foreground on right half
    ConsiderHalfBlock(CH_RIGHT, rightAvg, leftAvg, False, True, False, True);
  end;

  // Stabilize unused attribute for fully covered chars
  if bestCh = CH_FULL then bestBG := 0;
  // Do not force FG=0 for spaces; keep the chosen FG attribute so downstream
  // exporters can optionally interpret "no background" as using FG.
end;

procedure BuildCellsFromSubpixels(
  const idx: array of Byte;
  rows: Integer;
  Ice: Boolean;
  Mode: TRenderMode;
  Pal: TPaletteKind;
  const Opt: TConvertOptions;
  BasePct, SpanPct: Integer;
  var cells: array of TCell
);
var
  x, y: Integer;
  tlI,trI,blI,brI: Integer;
  tl,tr,bl,br: TRGB;

  topAvg, botAvg, leftAvg, rightAvg, fullAvg: TRGB;
  topI, botI, leftI, rightI, fullI: Integer;
  eFull, eUp, eLow, eLeft, eRight: Int64;
  pFull, pTop, pBot, pLeft, pRight, pTopBG, pBotBG, pLeftBG, pRightBG: TRGB;

  bestE: Int64;
  bestCh: Byte;
  bestFG, bestBG: Byte;
  contrastMax: Integer;
      contrastTmp: Integer;
  // Keep the best non-shade (hires/half) candidate so we can apply
  // ANSI Blocks Pixel-art preferences when comparing against shade candidates.
  hiresE: Int64;
  hiresCh: Byte;
  hiresFG, hiresBG: Byte;

  shadeCh: Byte;
  shadeFG, shadeBG: Byte;
  shadeE: Int64;

  cellHasColorChange: Boolean;

  function BgOfAttr(a: Byte): Byte; inline;
  begin
    Result := (a shr 4) and $0F;
  end;

  function IsRampShade(ch: Byte): Boolean; inline;
  begin
    // Only the dither ramp; space/full are handled separately.
    Result := (ch = CH_LIGHT) or (ch = CH_MED) or (ch = CH_DARK);
  end;

  function NeighborPenalty(const candBG: Byte; cx, cy: Integer): Int64; inline;
  const
    // Tuned for pixel-art: discourage background "sparkle".
    BG_PENALTY = 12000;
  var
    p: Int64;
    leftBG, upBG: Byte;
  begin
    if Opt.GlyphSet <> gsAnsiBlocksPixel then Exit(0);
    p := 0;
    if (cx > 0) then
    begin
      leftBG := BgOfAttr(cells[cy*COLS + (cx-1)].Attr);
      if candBG <> leftBG then Inc(p, BG_PENALTY);
    end;
    if (cy > 0) then
    begin
      upBG := BgOfAttr(cells[(cy-1)*COLS + cx].Attr);
      if candBG <> upBG then Inc(p, BG_PENALTY);
    end;
    Result := p;
  end;


  function IdxAt(sx, sy: Integer): Integer; inline;
  begin
    Result := idx[sy*SUBW + sx];
  end;

  procedure ConsiderHires;
  var
    cTB, cLR: Integer;
        topBGI, botBGI, leftBGI, rightBGI, fullBGI: Integer;
bestHalfE: Int64;
    bestHalfCh: Byte;
    bestHalfFG, bestHalfBG: Byte;
  begin
    topAvg   := Mix2(tl, tr);
    botAvg   := Mix2(bl, br);
    leftAvg  := Mix2(tl, bl);
    rightAvg := Mix2(tr, br);
    fullAvg  := Mix4(tl, tr, bl, br);

    topI   := NearestAnsi16(topAvg, Pal);
    botI   := NearestAnsi16(botAvg, Pal);
    leftI  := NearestAnsi16(leftAvg, Pal);
    rightI := NearestAnsi16(rightAvg, Pal);
    fullI  := NearestAnsi16(fullAvg, Pal);

    
    topBGI := topI; botBGI := botI; leftBGI := leftI; rightBGI := rightI; fullBGI := fullI;
    if not Ice then
    begin
      topBGI := topBGI and $07;
      botBGI := botBGI and $07;
      leftBGI := leftBGI and $07;
      rightBGI := rightBGI and $07;
      fullBGI := fullBGI and $07;
    end;

pTop   := Palette16(Pal, topI);
    pBot   := Palette16(Pal, botI);
    pLeft  := Palette16(Pal, leftI);
    pRight := Palette16(Pal, rightI);
    pFull  := Palette16(Pal, fullI);

    // If iCE colors are OFF, BG is limited to 0..7 in BIN/ANSI.
    // Compute errors using the *actual* BG color we'll be able to encode.
    if Ice then
    begin
      pTopBG   := pTop;
      pBotBG   := pBot;
      pLeftBG  := pLeft;
      pRightBG := pRight;
    end
    else
    begin
      pTopBG   := Palette16(Pal, topBGI);
      pBotBG   := Palette16(Pal, botBGI);
      pLeftBG  := Palette16(Pal, leftBGI);
      pRightBG := Palette16(Pal, rightBGI);
    end;

    eFull  := ErrFull(tl,tr,bl,br, pFull);
    eUp    := ErrTB(tl,tr,bl,br, pTop,  pBotBG);
    eLow   := ErrTB(tl,tr,bl,br, pBot,  pTopBG);
    eLeft  := ErrLR(tl,tr,bl,br, pLeft, pRightBG);
    eRight := ErrLR(tl,tr,bl,br, pRight, pLeftBG);
    // ANSI Blocks modes intentionally exclude side half-blocks (▌▐) for stability.
    if Opt.GlyphSet in [gsAnsiBlocks, gsAnsiBlocksPixel] then
    begin
      eLeft := High(Int64);
      eRight := High(Int64);
    end;
// Default: strict best-fit
    bestE := eFull; bestCh := CH_FULL; bestFG := Byte(fullI); bestBG := Byte(fullBGI);

    // Cartoon mode: prefer half/side blocks on strong transitions even if they're slightly worse
    if Mode = rmCartoon then
    begin
      // Measure transition strength based on quantized palette colors
      cTB := Dist2(pTop, pBot);
      cLR := Dist2(pLeft, pRight);

      bestHalfE := High(Int64);
      bestHalfCh := CH_FULL;
      bestHalfFG := Byte(fullI);
      bestHalfBG := Byte(fullBGI);

      // Only consider directional blocks if they actually represent a change
      if (topI <> botI) and (cTB >= 2500) then
      begin
        if eUp < bestHalfE then begin bestHalfE := eUp; bestHalfCh := CH_UP;  bestHalfFG := Byte(topI); bestHalfBG := Byte(botBGI); end;
        if eLow < bestHalfE then begin bestHalfE := eLow; bestHalfCh := CH_LOW; bestHalfFG := Byte(botI); bestHalfBG := Byte(topBGI); end;
      end;
      if (not (Opt.GlyphSet in [gsAnsiBlocks, gsAnsiBlocksPixel])) and (leftI <> rightI) and (cLR >= 2500) then
      begin
        if eLeft < bestHalfE then begin bestHalfE := eLeft; bestHalfCh := CH_LEFT;  bestHalfFG := Byte(leftI); bestHalfBG := Byte(rightBGI); end;
        if eRight < bestHalfE then begin bestHalfE := eRight; bestHalfCh := CH_RIGHT; bestHalfFG := Byte(rightI); bestHalfBG := Byte(leftBGI); end;
      end;

      // Allow half/side blocks if within 30% of the full-block error
      // (this intentionally chooses "smoother" structure over perfect color match)
      if (bestHalfE <> High(Int64)) and (bestHalfE * 10 <= eFull * 13) then
      begin
        bestE := bestHalfE;
        bestCh := bestHalfCh;
        bestFG := bestHalfFG;
        bestBG := bestHalfBG;
      end
      else
      begin
        // Still allow strict improvements
        if eUp < bestE then begin bestE := eUp; bestCh := CH_UP; bestFG := Byte(topI); bestBG := Byte(botBGI); end;
        if eLow < bestE then begin bestE := eLow; bestCh := CH_LOW; bestFG := Byte(botI); bestBG := Byte(topBGI); end;
        if not (Opt.GlyphSet in [gsAnsiBlocks, gsAnsiBlocksPixel]) then
        begin
          if eLeft < bestE then begin bestE := eLeft; bestCh := CH_LEFT; bestFG := Byte(leftI); bestBG := Byte(rightBGI); end;
          if eRight < bestE then begin bestE := eRight; bestCh := CH_RIGHT; bestFG := Byte(rightI); bestBG := Byte(leftBGI); end;
        end;
      end;
    end
    else
    begin
      if eUp < bestE then begin bestE := eUp; bestCh := CH_UP; bestFG := Byte(topI); bestBG := Byte(botBGI); end;
      if eLow < bestE then begin bestE := eLow; bestCh := CH_LOW; bestFG := Byte(botI); bestBG := Byte(topBGI); end;
      if not (Opt.GlyphSet in [gsAnsiBlocks, gsAnsiBlocksPixel]) then
      begin
        if eLeft < bestE then begin bestE := eLeft; bestCh := CH_LEFT; bestFG := Byte(leftI); bestBG := Byte(rightBGI); end;
        if eRight < bestE then begin bestE := eRight; bestCh := CH_RIGHT; bestFG := Byte(rightI); bestBG := Byte(leftBGI); end;
      end;
    end;
  end;

begin
  // Special mode: flat fills + black outlines
  if Mode = rmColorBook then
  begin
    BuildCellsColorBook(idx, rows, Ice, Pal, cells);
    Exit;
  end;

  for y := 0 to rows - 1 do
  begin
    if Assigned(Opt.CancelFlag) and Opt.CancelFlag^ then
      raise Exception.Create('Canceled');
    if Assigned(Opt.OnProgress) and ((y and 3) = 0) then
      Opt.OnProgress(BasePct + (y * SpanPct) div Max(1, rows-1), '');

    for x := 0 to COLS - 1 do
    begin
      tlI := IdxAt(2*x,   2*y);
      trI := IdxAt(2*x+1, 2*y);
      blI := IdxAt(2*x,   2*y+1);
      brI := IdxAt(2*x+1, 2*y+1);

      tl := Palette16(Pal, tlI);
      tr := Palette16(Pal, trI);
      bl := Palette16(Pal, blI);
      br := Palette16(Pal, brI);

      // ANSI Blocks Pixel tuning hint: detect whether this cell is a genuine
      // color transition (multiple palette indices). For pixel art we keep flat
      // areas clean (avoid unnecessary ░▒▓), but we allow richer dithering on
      // transitions to improve shading between colors.
      cellHasColorChange := (tlI <> trI) or (tlI <> blI) or (tlI <> brI);

      if (Mode = rmHires) or (Mode = rmHybrid) or (Mode = rmCartoon) then
        ConsiderHires
      else
        bestE := High(Int64);

      // Snapshot the best non-shade candidate (hires/half blocks) so we can
      // apply pixel-art preferences when considering shade cells.
      hiresE := bestE;
      hiresCh := bestCh;
      hiresFG := bestFG;
      hiresBG := bestBG;

      if (Mode = rmShades) or (Mode = rmHybrid) or (Mode = rmCartoon) then
      begin
        PickShadeCell(tl,tr,bl,br, Pal, Ice,
          (not (Opt.GlyphSet in [gsAnsiBlocks, gsAnsiBlocksPixel])),
          shadeCh, shadeFG, shadeBG, shadeE);

        // Pixel-art tuning for ANSI Blocks:
        //  - In flat areas: prefer solid/half blocks over ramp shades (░▒▓)
        //    unless they are *significantly* better.
        //  - On color transitions: allow richer dithering between colors, and
        //    give ramp shades a small bias so ramps appear more often.
        if (Opt.GlyphSet = gsAnsiBlocksPixel) and IsRampShade(shadeCh) and (hiresE <> High(Int64)) then
        begin
          if not cellHasColorChange then
          begin
            // Flat-ish region: require at least 15% improvement.
            if shadeE * 100 >= hiresE * 85 then
              shadeE := High(Int64);
          end
          else
          begin
            // Transition region: keep shade candidates, but discard if they're
            // wildly worse than the best non-shade option.
            if shadeE * 100 >= hiresE * 120 then
              shadeE := High(Int64)
            else
              // Small preference for ramp shades on transitions (ANSI-art rich).
              shadeE := (shadeE * 90) div 100; // ~10% bonus (richer transitions)
          end;
        end;

        // Neighbor-aware stabilization (pixel-art): discourage background sparkle.
        // On transitions, reduce the penalty so ramps are not suppressed.
        if Opt.GlyphSet = gsAnsiBlocksPixel then
        begin
          if hiresE <> High(Int64) then
            hiresE := hiresE + (NeighborPenalty(hiresBG, x, y) div (1 + Ord(cellHasColorChange)));
          if shadeE <> High(Int64) then
            shadeE := shadeE + (NeighborPenalty(shadeBG, x, y) div (1 + Ord(cellHasColorChange)));
        end;

        if (Mode = rmHybrid) or (Mode = rmCartoon) then
        begin
          contrastMax := Dist2(pTop, pBot);
          contrastTmp := Dist2(pLeft, pRight);
          if contrastTmp > contrastMax then contrastMax := contrastTmp;
          if contrastMax >= HIRES_CONTRAST_TH then
          begin
            // In cartoon mode we strongly prefer half/side blocks on transitions,
            // so penalize shade cells more than hybrid.
            if Mode = rmCartoon then
              shadeE := shadeE + Int64(contrastMax) * 4
            else
              shadeE := shadeE + contrastMax;
          end;
        end;
        // Choose between the best non-shade candidate and the (possibly
        // penalized/gated) shade candidate.
        bestE := hiresE;
        bestCh := hiresCh;
        bestFG := hiresFG;
        bestBG := hiresBG;

        if shadeE < bestE then
        begin
          bestE := shadeE;
          bestCh := shadeCh;
          bestFG := shadeFG;
          bestBG := shadeBG;
        end;
      end;

      cells[y*COLS + x].Ch := bestCh;
      cells[y*COLS + x].Attr := AttrByte(bestFG, bestBG, Ice);
    end;
  end;
end;


procedure HQRefineCellsDetail(
  const Img: TFPCustomImage;
  const SrcR: TRect;
  const Rows: Integer;
  const Opt: TConvertOptions;
  var Cells: TCellArray
);
const
  HQ_PASSES = 2;
  // Allow a tiny error increase only if it noticeably reduces BG seams (detail-preserving).
  HQ_ERR_TOL_PCT = 0.3; // 0.3%
var
  pass, x, y, idx: Integer;
  srcCells, dstCells: TCellArray;
  pal: array[0..15] of TRGB;
  samples: array[0..127] of TRGB;
  px, py: Integer;
  fx, fy: Double;
  c: TRGB;

  ch: Byte;
  fg, bg: Byte;
  bgMax: Byte;

  // Glyph rows for the chosen character
  row: Byte;
  bitOn: Boolean;

  // Candidate BG list
  candBG: array[0..7] of Byte;
  nCand, iCand: Integer;

  leftBG, topBG, rightBG, botBG, mostBG: Byte;
  cntBG: array[0..15] of Integer;
  i: Integer;
  bestCnt: Integer;

  curErr, candErr, bestErr: Int64;
  curSeams, candSeams, bestSeams: Integer;
  tolMul: Double;

  function CellErrFor(const gCh, gFG, gBG: Byte): Int64;
  var
    e: Int64;
    pxi, pyi, tidx: Integer;
    rr: Byte;
    onBit: Boolean;
  begin
    e := 0;
    for pyi := 0 to 15 do
    begin
      rr := DOSFontModernDOS8x16[gCh, pyi];
      for pxi := 0 to 7 do
      begin
        onBit := (rr and (1 shl (7-pxi))) <> 0;
        tidx := pyi*8 + pxi;
        if onBit then
          Inc(e, PalDist2Hinted(samples[tidx], pal[gFG], gFG))
        else
          Inc(e, PalDist2Hinted(samples[tidx], pal[gBG], gBG));
      end;
    end;
    Result := e;
  end;

  function BGSeamsForCell(const cx, cy: Integer; const gBG: Byte; const refCells: TCellArray): Integer;
  var
    nBG: Byte;
    n: Integer;
    a: Byte;
  begin
    n := 0;
    // left
    if cx > 0 then
    begin
      a := refCells[cy*COLS + (cx-1)].Attr;
      nBG := (a shr 4) and $0F; if not Opt.Ice then nBG := nBG and $07;
      if nBG <> gBG then Inc(n);
    end;
    // right
    if cx < COLS-1 then
    begin
      a := refCells[cy*COLS + (cx+1)].Attr;
      nBG := (a shr 4) and $0F; if not Opt.Ice then nBG := nBG and $07;
      if nBG <> gBG then Inc(n);
    end;
    // up
    if cy > 0 then
    begin
      a := refCells[(cy-1)*COLS + cx].Attr;
      nBG := (a shr 4) and $0F; if not Opt.Ice then nBG := nBG and $07;
      if nBG <> gBG then Inc(n);
    end;
    // down
    if cy < Rows-1 then
    begin
      a := refCells[(cy+1)*COLS + cx].Attr;
      nBG := (a shr 4) and $0F; if not Opt.Ice then nBG := nBG and $07;
      if nBG <> gBG then Inc(n);
    end;
    Result := n;
  end;

  procedure AddCandBG(v: Byte);
  var j: Integer;
  begin
    if not Opt.Ice then v := v and $07;
    for j := 0 to nCand-1 do
      if candBG[j] = v then Exit;
    if nCand <= High(candBG) then
    begin
      candBG[nCand] := v;
      Inc(nCand);
    end;
  end;

begin
  if (Rows <= 0) or (Length(Cells) <> COLS*Rows) then Exit;
  if (Opt.Mode = rmTronicShade) and (Opt.TronicApplyMode = 1) then Exit; // glyph-only lock: don't touch colors
  if Opt.HQMode < 2 then Exit;

  // Palette
  for i := 0 to 15 do pal[i] := Palette16(Opt.Palette, i);

  SetLength(srcCells, Length(Cells));
  SetLength(dstCells, Length(Cells));
  srcCells := Cells;

  tolMul := 1.0 + (HQ_ERR_TOL_PCT / 100.0);

  for pass := 1 to HQ_PASSES do
  begin
    dstCells := srcCells;

    for y := 0 to Rows-1 do
      for x := 0 to COLS-1 do
      begin
        idx := y*COLS + x;

        ch := srcCells[idx].Ch;
        fg := srcCells[idx].Attr and $0F;
        bg := (srcCells[idx].Attr shr 4) and $0F;
        if not Opt.Ice then bg := bg and $07;

        // sample this cell again (HQ sampling)
        for py := 0 to 15 do
          for px := 0 to 7 do
          begin
            fx := (x*8 + (px + 0.5)) / (COLS * 8);
            fy := (y*16 + (py + 0.5)) / (Rows * 16);
            c := SampleRGBSuper(
                   Img, SrcR, fx, fy,
                   1.0 / (COLS * 8.0),
                   1.0 / (Rows * 16.0),
                   IfThen(Opt.HQMode > 0, Opt.HQSuperSample, 1),
                   (Opt.HQMode > 0)
                 );
            c := TransformRGB(c, Opt.Gamma, Opt.Contrast, Opt.Saturation, Opt.Brightness);
            c := PreMatchMapColor(c, Opt, x*8 + px, y*16 + py);
            samples[py*8 + px] := c;
          end;

        if (Opt.HQMode >= 2) and (Opt.HQSharpAmount > 0) then
          ApplyHQUnsharp(samples, Opt.HQSharpAmount);

        curErr := CellErrFor(ch, fg, bg);
        curSeams := BGSeamsForCell(x, y, bg, srcCells);

        // build BG candidates from neighbors (detail-preserving: keep glyph + FG fixed)
        nCand := 0;
        AddCandBG(bg);

        leftBG := bg; topBG := bg; rightBG := bg; botBG := bg;
        if x > 0 then
        begin
          leftBG := (srcCells[idx-1].Attr shr 4) and $0F;
          if not Opt.Ice then leftBG := leftBG and $07;
          AddCandBG(leftBG);
        end;
        if x < COLS-1 then
        begin
          rightBG := (srcCells[idx+1].Attr shr 4) and $0F;
          if not Opt.Ice then rightBG := rightBG and $07;
          AddCandBG(rightBG);
        end;
        if y > 0 then
        begin
          topBG := (srcCells[idx-COLS].Attr shr 4) and $0F;
          if not Opt.Ice then topBG := topBG and $07;
          AddCandBG(topBG);
        end;
        if y < Rows-1 then
        begin
          botBG := (srcCells[idx+COLS].Attr shr 4) and $0F;
          if not Opt.Ice then botBG := botBG and $07;
          AddCandBG(botBG);
        end;

        // most common neighbor BG (often reduces flicker without changing detail)
        for i := 0 to 15 do cntBG[i] := 0;
        if x > 0 then Inc(cntBG[leftBG]);
        if x < COLS-1 then Inc(cntBG[rightBG]);
        if y > 0 then Inc(cntBG[topBG]);
        if y < Rows-1 then Inc(cntBG[botBG]);
        mostBG := bg; bestCnt := -1;
        for i := 0 to 15 do
          if cntBG[i] > bestCnt then begin bestCnt := cntBG[i]; mostBG := Byte(i); end;
        AddCandBG(mostBG);

        bestErr := curErr;
        bestSeams := curSeams;
        bgMax := bg;

        for iCand := 0 to nCand-1 do
        begin
          bgMax := candBG[iCand];
          candErr := CellErrFor(ch, fg, bgMax);
          candSeams := BGSeamsForCell(x, y, bgMax, srcCells);

          // Prefer strictly better error. Otherwise allow a tiny error increase only if seams improve.
          if (candErr < bestErr) or
             ((candErr <= Round(curErr * tolMul)) and (candSeams + 1 <= curSeams) and (candErr < bestErr + 2500)) then
          begin
            bestErr := candErr;
            bestSeams := candSeams;
            bg := bgMax;
          end;
        end;

        dstCells[idx].Attr := AttrByte(fg, bg, Opt.Ice);
      end;

    // next pass
    srcCells := dstCells;
  end;

  Cells := srcCells;
end;


procedure ConvertImageToCells(
  const Img: TFPCustomImage;
  const Opt: TConvertOptions;
  out OutRows: Integer;
  out Cells: TCellArray
);
var
  rows, subH: Integer;
  idx: TByteArray;
  winX, winY: Integer;
  srcR: TRect;
  srcW, srcH: Integer;
  BaseOpt: TConvertOptions;
begin
  // Use the selected palette metric when picking nearest palette colors.
  // In TronicShade mode, allow an override (Color metric dropdown) so users can
  // experiment without affecting the global converter defaults.
  if Opt.Mode = rmTronicShade then
  begin
    InitGlyphCache(Opt.TronicGlyphSet);
    case Opt.TronicColorMetric of
      tcmRGB:         SetPaletteMetric(cmRGB, Opt.PaletteMatch, Opt.ColorMatchPct,
                        Opt.YWeightPct, Opt.CbWeightPct, Opt.CrWeightPct);
      tcmRedmean:     SetPaletteMetric(cmRedmean, Opt.PaletteMatch, Opt.ColorMatchPct,
                        Opt.YWeightPct, Opt.CbWeightPct, Opt.CrWeightPct);
      tcmYCbCr:       SetPaletteMetric(cmYCbCr, Opt.PaletteMatch, Opt.ColorMatchPct,
                        Opt.YWeightPct, Opt.CbWeightPct, Opt.CrWeightPct);
      tcmHSVAdaptive: SetPaletteMetric(cmHSVAdaptive, Opt.PaletteMatch, Opt.ColorMatchPct,
                        Opt.YWeightPct, Opt.CbWeightPct, Opt.CrWeightPct);
    else
      // Luma-only matching is handled inside glyph scoring (doesn't use PalDist2).
      SetPaletteMetric(Opt.ColorMetric, Opt.PaletteMatch, Opt.ColorMatchPct,
        Opt.YWeightPct, Opt.CbWeightPct, Opt.CrWeightPct);
    end;
  end
  else
    SetPaletteMetric(Opt.ColorMetric, Opt.PaletteMatch, Opt.ColorMatchPct,
      Opt.YWeightPct, Opt.CbWeightPct, Opt.CrWeightPct);

  SetColorHints(Opt.ColorHints, Opt.HintTolerance);
  SetHintPaletteMode(Opt.UseHintPalette);

  if (Img.Width <= 0) or (Img.Height <= 0) then
    raise Exception.Create('Invalid image dimensions.');

  if Opt.UseCrop then
    srcR := ClampRectToImage(Opt.Crop, Img.Width, Img.Height)
  else
    srcR := Rect(0, 0, Img.Width, Img.Height);

  srcW := srcR.Right - srcR.Left;
  srcH := srcR.Bottom - srcR.Top;

  if Opt.ForcedRows > 0 then
    rows := Opt.ForcedRows
  else
  begin
    rows := Round((srcH / Max(1, srcW)) * COLS * Opt.Aspect);
    if rows < 1 then rows := 1;
  end;

  winX := Opt.WinX; if winX < 1 then winX := 1;
  winY := Opt.WinY; if winY < 1 then winY := 1;

  SetLength(Cells, COLS * rows);

  if (Opt.Mode = rmGlyphFit) or (Opt.Mode = rmAutoShader) or (Opt.Mode = rmTronicShade) then
  begin
    // TronicShade is meant to be a *style/texture pass* on top of a normal
    // palette conversion. If we go straight into rmTronicShade, many images can
    // look "unchanged" (especially in Glyph-only mode) because there is no
    // established base color field to work from.
    //
    // So: in rmTronicShade we run a fast base glyph-fit pass first to establish
    // initial FG/BG + chars, then run the TronicShade pass which can lock colors
    // (glyph-only) and apply the learned style / edge texturing.
    if (Opt.Mode = rmTronicShade) then
    begin
      if Assigned(Opt.OnProgress) then
        Opt.OnProgress(0, 'Preparing base palette pass (TronicShade)...');
      BaseOpt := Opt;
      BaseOpt.Mode := rmGlyphFit;
      // Use the global glyph set for the base pass; TronicShade will use its
      // own TronicGlyphSet in the second pass.
      BuildCellsGlyphFit(Img, srcR, rows, BaseOpt, Cells);

      if Assigned(Opt.OnProgress) then
        Opt.OnProgress(55, 'Applying TronicShade texture/style pass...');
      BuildCellsGlyphFit(Img, srcR, rows, Opt, Cells);

      // Optional: extra character-only edge texture on the resulting ANSI grid.
      // This is intentionally AFTER pair matching, so it can push any remaining
      // splitters (half blocks) towards shade textures at palette boundaries.
      if Opt.TronicEdgeShadeEnabled then
        TronicPostEdgeShade(Cells, COLS, rows, Opt);

      if Assigned(Opt.OnProgress) then
        Opt.OnProgress(100, 'Done.');
    end
    else
    begin
      if Assigned(Opt.OnProgress) then
        Opt.OnProgress(0, 'Preparing glyph fit / autoshader...');
      BuildCellsGlyphFit(Img, srcR, rows, Opt, Cells);
      if Assigned(Opt.OnProgress) then
        Opt.OnProgress(100, 'Done.');
    end;
  
  // Optional PatchStyle pass (style transfer using learned patches)
  if Opt.PatchStyleEnabled and PatchLibHasAny then
    PatchStyleApply(Cells, COLS, rows,
      Opt.PatchUse10, Opt.PatchUse5, Opt.PatchUse3,
      Opt.PatchLoops, Opt.PatchMinMatchPct,
      TPatchApplyMode(Opt.PatchApplyMode));

  // HQ: detail-preserving refinement sweep to reduce background flicker/seams.
  if (Opt.HQMode >= 2) and (Opt.Mode <> rmTronicShade) then
  begin
    if Assigned(Opt.OnProgress) then
      Opt.OnProgress(97, 'HQ refine sweep (detail)...');
    HQRefineCellsDetail(Img, srcR, rows, Opt, Cells);
  end;

  OutRows := rows;
    Exit;
  end;

  subH := rows * 2;

  SetLength(idx, SUBW * subH);

  if Assigned(Opt.OnProgress) then
    Opt.OnProgress(0, 'Sampling & quantizing colors...');

  // ANSIrez mode is intended to behave more like classic ANSI converters:
  // palette-matched sampling, no dithering (less speckle), plus an optional
  // post-quantization smoothing pass.
  if Opt.AnsiRezMode then
    QuantizeSubpixels(Img, subH, winX, winY, srcR, dmNone, 0.0, Opt.Palette, True, Opt.Gamma, Opt.Contrast, Opt.Saturation, Opt.Brightness, Opt, 0, 75, idx)
  else
    QuantizeSubpixels(Img, subH, winX, winY, srcR, Opt.Dither, Opt.DitherStrength, Opt.Palette, Opt.PaletteMatch, Opt.Gamma, Opt.Contrast, Opt.Saturation, Opt.Brightness, Opt, 0, 75, idx);

  if Opt.AnsiRezMode then
  begin
    if Assigned(Opt.OnProgress) then
      Opt.OnProgress(78, 'Applying ANSIrez smoothing filter...');
    if Opt.AnsiRezFilter = af4x4 then
      ApplyAnsiRezFilter4x4(idx, SUBW, subH, Opt.Palette)
    else
      ApplyAnsiRezFilterParity2(idx, SUBW, subH, Opt.AnsiRezFilter, Opt.Palette);
  end;

  if Assigned(Opt.OnProgress) then
    Opt.OnProgress(85, 'Building output cells...');
  BuildCellsFromSubpixels(idx, rows, Opt.Ice, Opt.Mode, Opt.Palette, Opt, 85, 15, Cells);

  if Assigned(Opt.OnProgress) then
    Opt.OnProgress(100, 'Done.');


  // Optional PatchStyle pass (style transfer using learned patches)
  if Opt.PatchStyleEnabled and PatchLibHasAny then
    PatchStyleApply(Cells, COLS, rows,
      Opt.PatchUse10, Opt.PatchUse5, Opt.PatchUse3,
      Opt.PatchLoops, Opt.PatchMinMatchPct,
      TPatchApplyMode(Opt.PatchApplyMode));

  // Optional final hint post-pass: snap near-miss colors to the hinted ANSI index.
  ApplyHintsPostFix(Img, srcR, rows, Opt, Cells);

  OutRows := rows;
end;


end.
