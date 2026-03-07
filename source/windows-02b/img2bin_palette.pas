unit img2bin_palette;

{$mode objfpc}{$H+}

interface

uses
  Math,
  img2bin_types;

// Set the palette distance metric used by PalDist2/NearestAnsi16.
// ColorMatchPct (50..200 typical) increases emphasis on chroma differences.
// Y/Cb/Cr weights (percent, 50..300 typical) allow fine-tuning of the
// cmYCbCr metric. Call once per conversion (ConvertImageToCells calls this internally).
procedure SetPaletteMetric(Metric: TColorMetric; UseChromaBias: Boolean;
  ColorMatchPct: Integer; YWeightPct: Integer; CbWeightPct: Integer; CrWeightPct: Integer);

procedure SetColorHints(const Hints: TColorHintArray; HintTolerance: Integer);
// If enabled, hints are used to override palette RGB entries (per-image palette)
// rather than biasing the distance metric. This is more stable and avoids
// over-biasing artifacts.
procedure SetHintPaletteMode(UseHintPalette: Boolean);


// Directly override a specific ANSI palette entry while hint-palette mode is enabled.
// Used for gentle per-pass palette refitting.
procedure SetHintPaletteOverride(const Idx: Integer; const C: TRGB);
function Dist2(const a, b: TRGB): Integer; inline;
function DistRedmean2(const a, b: TRGB): Integer; inline;
function DistYCbCr2(const a, b: TRGB): Integer; inline;
function SatAmount(const c: TRGB): Integer; inline;
function PalDist2(const a: TRGB; const b: TRGB): Integer; inline;

function PalDist2Hinted(const c, p: TRGB; pIdx: Integer): Integer; inline;


function PalLumaDist2Hinted(const c, p: TRGB; pIdx: Integer): Integer; inline;
function VGA16(i: Integer): TRGB;
function Win16(i: Integer): TRGB;
function Palette16(Pal: TPaletteKind; i: Integer): TRGB;




function NearestAnsi16(const c: TRGB; Pal: TPaletteKind): Integer;

// Find the nearest color index in an arbitrary RGB palette (2..256 typical).
// Uses the currently selected palette metric (SetPaletteMetric) via PalDist2.
function NearestInRGBPalette(const c: TRGB; const Pal: array of TRGB): Integer;


implementation

var
  // Global palette distance metric used by palette lookup functions.
  // Set via SetPaletteMetric, called at the start of ConvertImageToCells.
  GColorMetric: TColorMetric = cmRedmean;
  GChromaBias: Boolean = False;
  // Scale factor for chroma terms in cmYCbCr metric, fixed-point 8.8 (256=1.0).
  GChromaScaleX256: Integer = 256;

  // Per-channel weights for cmYCbCr metric, fixed-point 8.8 (256=1.0).
  // These are applied before the chromaScale boost.
  GYWeightX256: Integer = 256;
  GCbWeightX256: Integer = 256;
  GCrWeightX256: Integer = 256;

// Optional per-image color hints (set by GUI).
GHints: TColorHintArray;
GHintTol2: Integer = 0; // squared tolerance in RGB-ish space

// If True, use hints to override palette RGB entries (per-image palette).
GUseHintPalette: Boolean = False;
GPalOverride: array[0..15] of TRGB;
GPalOverrideSet: array[0..15] of Boolean;


procedure SetPaletteMetric(Metric: TColorMetric; UseChromaBias: Boolean;
  ColorMatchPct: Integer; YWeightPct: Integer; CbWeightPct: Integer; CrWeightPct: Integer);
begin
  GColorMetric := Metric;
  GChromaBias := UseChromaBias;
  if ColorMatchPct < 10 then ColorMatchPct := 10;
  if ColorMatchPct > 400 then ColorMatchPct := 400;
  GChromaScaleX256 := Round(ColorMatchPct * 256.0 / 100.0);

  // Clamp and store Y/Cb/Cr weights. Defaults are 100%.
  if YWeightPct <= 0 then YWeightPct := 100;
  if CbWeightPct <= 0 then CbWeightPct := 100;
  if CrWeightPct <= 0 then CrWeightPct := 100;
  if YWeightPct < 10 then YWeightPct := 10;
  if YWeightPct > 500 then YWeightPct := 500;
  if CbWeightPct < 10 then CbWeightPct := 10;
  if CbWeightPct > 500 then CbWeightPct := 500;
  if CrWeightPct < 10 then CrWeightPct := 10;
  if CrWeightPct > 500 then CrWeightPct := 500;
  GYWeightX256  := Round(YWeightPct  * 256.0 / 100.0);
  GCbWeightX256 := Round(CbWeightPct * 256.0 / 100.0);
  GCrWeightX256 := Round(CrWeightPct * 256.0 / 100.0);
end;



function PalLumaDist2Hinted(const c, p: TRGB; pIdx: Integer): Integer; inline;
var
  j: Integer;
  d, dh, w: Integer;

  function RGBLuma(const cc: TRGB): Integer; inline;
  begin
    Result := (77*Integer(cc.R) + 150*Integer(cc.G) + 29*Integer(cc.B)) shr 8;
  end;

  function LumaDist2(const a, b: TRGB): Integer; inline;
  var
    da: Integer;
  begin
    da := RGBLuma(a) - RGBLuma(b);
    Result := da * da;
  end;

begin
  d := LumaDist2(c, p);

  // Apply user-provided color hints (same semantics as PalDist2Hinted),
  // but on luma-only scoring for TronicShade.
  if (not GUseHintPalette) and (GHintTol2 > 0) and (Length(GHints) > 0) then
  begin
    for j := 0 to High(GHints) do
    begin
      dh := Dist2(c, GHints[j].Src);
      if dh < GHintTol2 then
      begin
        w := ((GHintTol2 - dh) * GHints[j].Strength) div GHintTol2;
        if pIdx = GHints[j].TargetIdx then
          d := d - w;
      end;
    end;
    if d < 0 then d := 0;
  end;

  Result := d;
end;

procedure SetColorHints(const Hints: TColorHintArray; HintTolerance: Integer);
var
  i: Integer;
  sumR, sumG, sumB, sumW: array[0..15] of Int64;
  idx: Integer;
  w: Int64;
begin
  // Copy hints so callers can reuse their arrays safely.
  SetLength(GHints, Length(Hints));
  for i := 0 to High(Hints) do
    GHints[i] := Hints[i];

  // Build per-index palette overrides from the hints. We compute a weighted
  // average of all sampled colors for each target index (weights = Strength).
  for idx := 0 to 15 do
  begin
    sumR[idx] := 0; sumG[idx] := 0; sumB[idx] := 0; sumW[idx] := 0;
    GPalOverrideSet[idx] := False;
  end;
  for i := 0 to High(GHints) do
  begin
    idx := EnsureRange(Integer(GHints[i].TargetIdx), 0, 15);
    w := GHints[i].Strength;
    if w <= 0 then w := 1;
    sumR[idx] := sumR[idx] + Int64(GHints[i].Src.R) * w;
    sumG[idx] := sumG[idx] + Int64(GHints[i].Src.G) * w;
    sumB[idx] := sumB[idx] + Int64(GHints[i].Src.B) * w;
    sumW[idx] := sumW[idx] + w;
    GPalOverrideSet[idx] := True;
  end;
  for idx := 0 to 15 do
  begin
    if (sumW[idx] > 0) and GPalOverrideSet[idx] then
    begin
      GPalOverride[idx].R := ClampByte(Round(sumR[idx] / sumW[idx]));
      GPalOverride[idx].G := ClampByte(Round(sumG[idx] / sumW[idx]));
      GPalOverride[idx].B := ClampByte(Round(sumB[idx] / sumW[idx]));
    end;
  end;

  // HintTolerance is expressed in 0..255-ish units.
  if HintTolerance < 0 then HintTolerance := 0;
  if HintTolerance > 255 then HintTolerance := 255;

  // Use Dist2-style scale (sum of squared deltas). A tolerance of 0 disables hints.
  if HintTolerance = 0 then
    GHintTol2 := 0
  else
    GHintTol2 := HintTolerance * HintTolerance * 3;
end;

procedure SetHintPaletteMode(UseHintPalette: Boolean);
begin
  GUseHintPalette := UseHintPalette;
end;




procedure SetHintPaletteOverride(const Idx: Integer; const C: TRGB);
var i: Integer;
begin
  i := Idx;
  if i < 0 then i := 0 else if i > 15 then i := 15;
  GPalOverride[i] := C;
  GPalOverrideSet[i] := True;
end;
function Win16(i: Integer): TRGB;
begin
  // Windows console / common "ANSI" 16-color palette (darker low colors).
  // Useful when output is viewed in modern terminals that default to this.
  case i of
    0:  Result := RGB(0,   0,   0);
    1:  Result := RGB(0,   0,   128);
    2:  Result := RGB(0,   128, 0);
    3:  Result := RGB(0,   128, 128);
    4:  Result := RGB(128, 0,   0);
    5:  Result := RGB(128, 0,   128);
    6:  Result := RGB(128, 128, 0);
    7:  Result := RGB(192, 192, 192);
    8:  Result := RGB(128, 128, 128);
    9:  Result := RGB(0,   0,   255);
    10: Result := RGB(0,   255, 0);
    11: Result := RGB(0,   255, 255);
    12: Result := RGB(255, 0,   0);
    13: Result := RGB(255, 0,   255);
    14: Result := RGB(255, 255, 0);
  else
    Result := RGB(255, 255, 255);
  end;
end;

function Dist2(const a, b: TRGB): Integer; inline;
var dr,dg,db: Integer;
begin
  dr := Integer(a.R) - Integer(b.R);
  dg := Integer(a.G) - Integer(b.G);
  db := Integer(a.B) - Integer(b.B);
  Result := dr*dr + dg*dg + db*db;
end;

{
var
  // Global palette distance metric used by palette lookup functions.
  // Set at the start of ConvertImageToCells from Opt.ColorMetric.
  GColorMetric: TColorMetric = cmRedmean;
  GChromaBias: Boolean = False;
}
function DistRedmean2(const a, b: TRGB): Integer; inline;
var dr,dg,db: Integer; rm: Integer;
begin
  dr := Integer(a.R) - Integer(b.R);
  dg := Integer(a.G) - Integer(b.G);
  db := Integer(a.B) - Integer(b.B);
  rm := (Integer(a.R) + Integer(b.R)) div 2;
  // Redmean weighted distance (approx perceptual). Uses integer math.
  Result :=
    (((512 + rm) * (dr*dr)) shr 8) +
    (4 * (dg*dg)) +
    (((767 - rm) * (db*db)) shr 8);
end;

function DistYCbCr2(const a, b: TRGB): Integer; inline;
var
  ya,yb,cba,cbb,cra,crb: Integer;
  dy,dcb,dcr: Integer;
  sat: Integer;
  chromaScaleX256: Integer;
  yTerm: Int64;
  cbTerm: Int64;
  crTerm: Int64;
begin
  // Integer YCbCr-ish transform (BT.601-ish, scaled by 256 and shifted).
  // We weight chroma more for saturated colors so reds/blues don't drift toward
  // browns/yellows just because luma is close.
  ya  := (77*Integer(a.R) + 150*Integer(a.G) + 29*Integer(a.B)) shr 8;
  yb  := (77*Integer(b.R) + 150*Integer(b.G) + 29*Integer(b.B)) shr 8;

  cba := (-43*Integer(a.R) - 85*Integer(a.G) + 128*Integer(a.B)) shr 8;
  cbb := (-43*Integer(b.R) - 85*Integer(b.G) + 128*Integer(b.B)) shr 8;

  cra := (128*Integer(a.R) - 107*Integer(a.G) - 21*Integer(a.B)) shr 8;
  crb := (128*Integer(b.R) - 107*Integer(b.G) - 21*Integer(b.B)) shr 8;

  dy  := ya - yb;
  dcb := cba - cbb;
  dcr := cra - crb;

  // Saturation of the desired color (a). 0..255
  sat := SatAmount(a);

  // Base chroma scale comes from ColorMatchPct (GChromaScaleX256).
  // Boost chroma further based on saturation to preserve hue on vivid colors.
  // chromaScaleX256 ~= GChromaScale * (1.0 + 2.0*sat/255)
  chromaScaleX256 := (GChromaScaleX256 * (256 + (sat * 2))) shr 8;

  // Less emphasis on luma, more on chroma (especially with chromaScale boost).
  // Apply per-channel weights so users can bias matching toward reds (Cr) or
  // blues (Cb), and adjust how strongly luma (Y) steers the decision.
  yTerm  := (Int64(2) * dy * dy * GYWeightX256) shr 8;
  cbTerm := (Int64(dcb) * dcb * GCbWeightX256) shr 8;
  crTerm := (Int64(dcr) * dcr * GCrWeightX256) shr 8;
  Result := Integer(yTerm + (((cbTerm + crTerm) * chromaScaleX256) shr 8));
end;

function SatAmount(const c: TRGB): Integer; inline;
var
  mn, mx: Integer;
begin
  mn := c.R; if c.G < mn then mn := c.G; if c.B < mn then mn := c.B;
  mx := c.R; if c.G > mx then mx := c.G; if c.B > mx then mx := c.B;
  Result := mx - mn;
end;

// ---
// Higher-quality (slower) color metrics
// ---

type
  TXYZ = record X, Y, Z: Double; end;
  TLab = record L, a, b: Double; end;
  TOKLab = record L, a, b: Double; end;

var
  GLinLUT: array[0..255] of Double;

procedure InitLinLUT;
var
  i: Integer;
  c: Double;
begin
  for i := 0 to 255 do
  begin
    c := i / 255.0;
    if c <= 0.04045 then
      GLinLUT[i] := c / 12.92
    else
      GLinLUT[i] := Power((c + 0.055) / 1.055, 2.4);
  end;
end;

function RGBToXYZ(const c: TRGB): TXYZ; inline;
var
  r, g, b: Double;
begin
  // sRGB (D65) -> linear -> XYZ
  r := GLinLUT[c.R];
  g := GLinLUT[c.G];
  b := GLinLUT[c.B];
  Result.X := 0.4124564*r + 0.3575761*g + 0.1804375*b;
  Result.Y := 0.2126729*r + 0.7151522*g + 0.0721750*b;
  Result.Z := 0.0193339*r + 0.1191920*g + 0.9503041*b;
end;

function XYZf(t: Double): Double; inline;
const
  e = 216.0/24389.0; // (6/29)^3
  k = 24389.0/27.0;  // (29/3)^3
begin
  if t > e then
    Result := Power(t, 1.0/3.0)
  else
    Result := (k*t + 16.0) / 116.0;
end;

function RGBToLab(const c: TRGB): TLab; inline;
var
  xyz: TXYZ;
  fx, fy, fz: Double;
begin
  xyz := RGBToXYZ(c);
  // D65 reference white
  fx := XYZf(xyz.X / 0.95047);
  fy := XYZf(xyz.Y / 1.00000);
  fz := XYZf(xyz.Z / 1.08883);
  Result.L := 116.0*fy - 16.0;
  Result.a := 500.0*(fx - fy);
  Result.b := 200.0*(fy - fz);
end;

function RGBToOKLab(const c: TRGB): TOKLab; inline;
var
  r, g, b: Double;
  l, m, s: Double;
  l_, m_, s_: Double;
begin
  // Linear sRGB
  r := GLinLUT[c.R];
  g := GLinLUT[c.G];
  b := GLinLUT[c.B];

  // sRGB -> LMS
  l := 0.4122214708*r + 0.5363325363*g + 0.0514459929*b;
  m := 0.2119034982*r + 0.6806995451*g + 0.1073969566*b;
  s := 0.0883024619*r + 0.2817188376*g + 0.6299787005*b;

  // Nonlinearity
  l_ := Power(l, 1.0/3.0);
  m_ := Power(m, 1.0/3.0);
  s_ := Power(s, 1.0/3.0);

  // LMS -> OKLab
  Result.L := 0.2104542553*l_ + 0.7936177850*m_ - 0.0040720468*s_;
  Result.a := 1.9779984951*l_ - 2.4285922050*m_ + 0.4505937099*s_;
  Result.b := 0.0259040371*l_ + 0.7827717662*m_ - 0.8086757660*s_;
end;

function HueDiffRad(a, b: Double): Double; inline;
var
  d: Double;
begin
  d := a - b;
  while d > Pi do d := d - 2*Pi;
  while d < -Pi do d := d + 2*Pi;
  Result := d;
end;

function DistLinearRGB2(const a, b: TRGB): Integer; inline;
var
  dr, dg, db: Double;
begin
  dr := GLinLUT[a.R] - GLinLUT[b.R];
  dg := GLinLUT[a.G] - GLinLUT[b.G];
  db := GLinLUT[a.B] - GLinLUT[b.B];
  Result := Round((dr*dr + dg*dg + db*db) * 1000000.0);
end;

function DistXYZ2(const a, b: TRGB): Integer; inline;
var
  ax, bx: TXYZ;
  dx, dy, dz: Double;
begin
  ax := RGBToXYZ(a);
  bx := RGBToXYZ(b);
  dx := ax.X - bx.X;
  dy := ax.Y - bx.Y;
  dz := ax.Z - bx.Z;
  Result := Round((dx*dx + dy*dy + dz*dz) * 1000000.0);
end;

function DistLab76_2(const a, b: TRGB): Integer; inline;
var
  la, lb: TLab;
  dl, da, dbv: Double;
begin
  la := RGBToLab(a);
  lb := RGBToLab(b);
  dl := la.L - lb.L;
  da := la.a - lb.a;
  dbv := la.b - lb.b;
  Result := Round((dl*dl + da*da + dbv*dbv) * 1000.0);
end;

function DistLab94_2(const a, b: TRGB): Integer; inline;
const
  kL = 1.0;
  kC = 1.0;
  kH = 1.0;
  K1 = 0.045;
  K2 = 0.015;
var
  la, lb: TLab;
  dL, C1, C2, dC, da, dbv, dH2: Double;
  SL, SC, SH, tL, tC, tH: Double;
begin
  // ΔE94 (graphic arts). Return squared for monotonic comparison.
  // See: CIE94 formula.
  la := RGBToLab(a);
  lb := RGBToLab(b);
  dL := la.L - lb.L;
  C1 := Hypot(la.a, la.b);
  C2 := Hypot(lb.a, lb.b);
  dC := C1 - C2;
  da := la.a - lb.a;
  dbv := la.b - lb.b;
  dH2 := da*da + dbv*dbv - dC*dC;
  if dH2 < 0 then dH2 := 0;
  SL := 1.0;
  SC := 1.0 + K1*C1;
  SH := 1.0 + K2*C1;
  tL := dL/(kL*SL);
  tC := dC/(kC*SC);
  tH := Sqrt(dH2)/(kH*SH);
  Result := Round((tL*tL + tC*tC + tH*tH) * 100000.0);
end;

function DegToRad(d: Double): Double; inline;
begin
  Result := d * Pi / 180.0;
end;

function RadToDeg(r: Double): Double; inline;
begin
  Result := r * 180.0 / Pi;
end;

function DistLab2000_2(const a, b: TRGB): Integer; inline;
// CIEDE2000. Returns squared distance scaled.
// Implementation follows Sharma et al. reference algorithm.
var
  la, lb: TLab;
  L1, a1, b1, L2, a2, b2: Double;
  avgLp, C1, C2, avgC, G: Double;
  a1p, a2p, C1p, C2p, avgCp: Double;
  h1p, h2p, avghp: Double;
  dLp, dCp, dhp: Double;
  T, SL, SC, SH, RT: Double;
  dTheta, RC: Double;
  dhAbs, dhTmp: Double;
  dE: Double;
begin
  la := RGBToLab(a);
  lb := RGBToLab(b);
  L1 := la.L; a1 := la.a; b1 := la.b;
  L2 := lb.L; a2 := lb.a; b2 := lb.b;

  avgLp := (L1 + L2) * 0.5;
  C1 := Hypot(a1, b1);
  C2 := Hypot(a2, b2);
  avgC := (C1 + C2) * 0.5;

  G := 0.5 * (1.0 - Sqrt(Power(avgC, 7.0) / (Power(avgC, 7.0) + Power(25.0, 7.0))));
  a1p := (1.0 + G) * a1;
  a2p := (1.0 + G) * a2;
  C1p := Hypot(a1p, b1);
  C2p := Hypot(a2p, b2);
  avgCp := (C1p + C2p) * 0.5;

  h1p := 0.0;
  if (C1p > 1e-12) then
  begin
    h1p := ArcTan2(b1, a1p);
    if h1p < 0 then h1p := h1p + 2*Pi;
  end;

  h2p := 0.0;
  if (C2p > 1e-12) then
  begin
    h2p := ArcTan2(b2, a2p);
    if h2p < 0 then h2p := h2p + 2*Pi;
  end;

  // Average hue (with wrap)
  if (C1p*C2p < 1e-12) then
    avghp := h1p + h2p
  else
  begin
    dhAbs := Abs(h1p - h2p);
    if dhAbs <= Pi then
      avghp := (h1p + h2p) * 0.5
    else
    begin
      if (h1p + h2p) < 2*Pi then
        avghp := (h1p + h2p + 2*Pi) * 0.5
      else
        avghp := (h1p + h2p - 2*Pi) * 0.5;
    end;
  end;

  dLp := L2 - L1;
  dCp := C2p - C1p;

  // Hue difference (wrapped)
  if (C1p*C2p < 1e-12) then
    dhp := 0.0
  else
  begin
    dhTmp := h2p - h1p;
    if dhTmp > Pi then dhTmp := dhTmp - 2*Pi;
    if dhTmp < -Pi then dhTmp := dhTmp + 2*Pi;
    dhp := dhTmp;
  end;
  dHp := 2.0 * Sqrt(C1p*C2p) * Sin(dhp * 0.5);

  T := 1.0
    - 0.17 * Cos(avghp - DegToRad(30.0))
    + 0.24 * Cos(2.0*avghp)
    + 0.32 * Cos(3.0*avghp + DegToRad(6.0))
    - 0.20 * Cos(4.0*avghp - DegToRad(63.0));

  SL := 1.0 + (0.015 * Power(avgLp - 50.0, 2.0)) / Sqrt(20.0 + Power(avgLp - 50.0, 2.0));
  SC := 1.0 + 0.045 * avgCp;
  SH := 1.0 + 0.015 * avgCp * T;

  dTheta := DegToRad(30.0) * Exp(-Power((RadToDeg(avghp) - 275.0) / 25.0, 2.0));
  RC := 2.0 * Sqrt(Power(avgCp, 7.0) / (Power(avgCp, 7.0) + Power(25.0, 7.0)));
  RT := -Sin(2.0*dTheta) * RC;

  // kL=kC=kH=1
  dE := Power(dLp/SL, 2.0) + Power(dCp/SC, 2.0) + Power(dHp/SH, 2.0) + RT*(dCp/SC)*(dHp/SH);
  if dE < 0 then dE := 0;
  Result := Round(dE * 100000.0);
end;

function DistOKLab2(const a, b: TRGB): Integer; inline;
var
  oa, ob: TOKLab;
  dl, da, dbv: Double;
begin
  oa := RGBToOKLab(a);
  ob := RGBToOKLab(b);
  dl := oa.L - ob.L;
  da := oa.a - ob.a;
  dbv := oa.b - ob.b;
  Result := Round((dl*dl + da*da + dbv*dbv) * 1000000.0);
end;

function DistOKLCH2(const a, b: TRGB): Integer; inline;
var
  oa, ob: TOKLab;
  C1, C2, h1, h2: Double;
  dL, dC, dh: Double;
  wH: Double;
begin
  oa := RGBToOKLab(a);
  ob := RGBToOKLab(b);
  C1 := Hypot(oa.a, oa.b);
  C2 := Hypot(ob.a, ob.b);
  h1 := ArcTan2(oa.b, oa.a);
  h2 := ArcTan2(ob.b, ob.a);
  dL := oa.L - ob.L;
  dC := C1 - C2;
  dh := HueDiffRad(h1, h2);
  // Hue weight increases with chroma
  wH := 1.0 + 2.0*Min(C1, C2);
  Result := Round((dL*dL + dC*dC + (wH*dh)*(wH*dh)) * 1000000.0);
end;

procedure RGBToHSV(const c: TRGB; out H, S, V: Double); inline;
var
  r, g, b, mx, mn, d: Double;
begin
  r := c.R / 255.0;
  g := c.G / 255.0;
  b := c.B / 255.0;
  mx := Max(r, Max(g, b));
  mn := Min(r, Min(g, b));
  d := mx - mn;
  V := mx;
  if mx <= 1e-12 then
    S := 0.0
  else
    S := d / mx;

  if d <= 1e-12 then
    H := 0.0
  else if mx = r then
    H := (g - b) / d
  else if mx = g then
    H := 2.0 + (b - r) / d
  else
    H := 4.0 + (r - g) / d;

  H := H * (Pi/3.0); // 60 deg in rad
  if H < 0 then H := H + 2*Pi;
end;

function DistHSVAdaptive2(const a, b: TRGB): Integer; inline;
var
  H1, S1, V1, H2, S2, V2: Double;
  dH, dS, dV, wH: Double;
begin
  RGBToHSV(a, H1, S1, V1);
  RGBToHSV(b, H2, S2, V2);
  dH := HueDiffRad(H1, H2);
  dS := S1 - S2;
  dV := V1 - V2;
  // Hue matters mostly when saturation is present
  wH := 0.25 + 4.0 * Min(S1, S2);
  Result := Round((dV*dV*1.0 + dS*dS*0.5 + (wH*dH)*(wH*dH)) * 1000000.0);
end;

function PalDist2(const a: TRGB; const b: TRGB): Integer; inline;
var
  d, sa, sb, pen: Integer;
begin
  case GColorMetric of
    cmRGB:        d := Dist2(a, b);
    cmRedmean:    d := DistRedmean2(a, b);
    cmYCbCr:      d := DistYCbCr2(a, b);
    cmLinearRGB:  d := DistLinearRGB2(a, b);
    cmXYZ:        d := DistXYZ2(a, b);
    cmLab76:      d := DistLab76_2(a, b);
    cmLab94:      d := DistLab94_2(a, b);
    cmLab2000:    d := DistLab2000_2(a, b);
    cmOKLab:      d := DistOKLab2(a, b);
    cmOKLCH:      d := DistOKLCH2(a, b);
    cmHSVAdaptive:d := DistHSVAdaptive2(a, b);
  else
    d := DistRedmean2(a, b);
  end;

  // If the desired color has chroma, avoid snapping to grays unless they are truly close.
  if GChromaBias then
  begin
    sa := SatAmount(a);
    sb := SatAmount(b);
    if (sa > 18) and (sb < 10) then
    begin
      pen := 10 - sb;
      d := d + pen * pen * 200;
    end;
  end;

  Result := d;
end;


// Legacy helper (currently unused by the converter, kept for experimentation)
function LumaByte(const c: TRGB): Byte; inline;
begin
  Result := ClampByte((299*Integer(c.R) + 587*Integer(c.G) + 114*Integer(c.B)) div 1000);
end;

function VGA16(i: Integer): TRGB;
begin
  case i of
    0:  Result := RGB(0,   0,   0);
    1:  Result := RGB(0,   0,   170);
    2:  Result := RGB(0,   170, 0);
    3:  Result := RGB(0,   170, 170);
    4:  Result := RGB(170, 0,   0);
    5:  Result := RGB(170, 0,   170);
    6:  Result := RGB(170, 85,  0);
    7:  Result := RGB(170, 170, 170);
    8:  Result := RGB(85,  85,  85);
    9:  Result := RGB(85,  85,  255);
    10: Result := RGB(85,  255, 85);
    11: Result := RGB(85,  255, 255);
    12: Result := RGB(255, 85,  85);
    13: Result := RGB(255, 85,  255);
    14: Result := RGB(255, 255, 85);
  else
    Result := RGB(255, 255, 255);
  end;
end;

function Palette16(Pal: TPaletteKind; i: Integer): TRGB;
var v: Integer;
begin
  // Per-image palette overrides derived from user hints.
  if GUseHintPalette then
  begin
    if i < 0 then i := 0 else if i > 15 then i := 15;
    if GPalOverrideSet[i] then
      Exit(GPalOverride[i]);
  end;

  case Pal of
    pkWin: Result := Win16(i);
    pkGray:
      begin
        // 16 grays, 0..255
        if i < 0 then i := 0 else if i > 15 then i := 15;
        v := Round(i * 255.0 / 15.0);
        Result := RGB(v, v, v);
      end;
  else
    Result := VGA16(i);
  end;
end;

function PalDist2Hinted(const c, p: TRGB; pIdx: Integer): Integer; inline;
var
  j: Integer;
  d, dh, w: Integer;
begin
  d := PalDist2(c, p);

  // Apply user-provided color hints (if any) when scoring against a specific
  // palette index. This is used by GlyphFit/AutoShader error scoring so that
  // "taught" hues (e.g. pastel pink) aren't punished into white/gray.
  if (not GUseHintPalette) and (GHintTol2 > 0) and (Length(GHints) > 0) then
  begin
    for j := 0 to High(GHints) do
    begin
      dh := Dist2(c, GHints[j].Src);
      if dh < GHintTol2 then
      begin
        w := ((GHintTol2 - dh) * GHints[j].Strength) div GHintTol2;
        // Only *boost* hinted target colors. Do not penalize non-hinted
        // candidates; hints should only help the colors the user taught.
        if pIdx = GHints[j].TargetIdx then
          d := d - w;
      end;
    end;
    if d < 0 then d := 0;
  end;

  Result := d;
end;


function NearestAnsi16(const c: TRGB; Pal: TPaletteKind): Integer;
var
  i, j, bestI, bestD, d: Integer;
  p: TRGB;
  dh, w: Integer;
begin
  bestI := 0;
  bestD := MaxInt;
  for i := 0 to 15 do
  begin
    p := Palette16(Pal, i);
    d := PalDist2(c, p);

    // Apply user-provided color hints (if any).
    // If the desired color is close to a hinted sample, we bias toward the
    // hinted TargetIdx so intented hues (like pastel pink) don't wash out.
    if (not GUseHintPalette) and (GHintTol2 > 0) and (Length(GHints) > 0) then
    begin
      for j := 0 to High(GHints) do
      begin
        dh := Dist2(c, GHints[j].Src);
        if dh < GHintTol2 then
        begin
          // Weight falls off linearly with distance to the hint.
          w := ((GHintTol2 - dh) * GHints[j].Strength) div GHintTol2;
          // Only boost the hinted target index.
          if i = GHints[j].TargetIdx then
            d := d - w;
        end;
      end;
      if d < 0 then d := 0;
    end;

    if d < bestD then begin bestD := d; bestI := i; end;
  end;
  Result := bestI;
end;

function NearestInRGBPalette(const c: TRGB; const Pal: array of TRGB): Integer;
var
  i: Integer;
  bestI: Integer;
  bestD, d: Integer;
begin
  if Length(Pal) <= 0 then Exit(0);
  bestI := 0;
  bestD := High(Integer);
  for i := 0 to High(Pal) do
  begin
    d := PalDist2(c, Pal[i]);
    if d < bestD then
    begin
      bestD := d;
      bestI := i;
      if bestD = 0 then Break;
    end;
  end;
  Result := bestI;
end;


initialization
  InitLinLUT;

end.
