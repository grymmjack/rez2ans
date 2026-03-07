unit img2bin_tronicshade;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  img2bin_types;

// TronicShade: learns multi-scale style probabilities from ANSI/BIN example screens
// and exposes a light-weight scoring bias (priors) for the converter.

type
  TTronicPolarity = (tpDarkInk, tpLightInk, tpNeutral);

  // Report returned by TronicShadeImportANSIEx for UI/debugging.
  TTronicImportReport = record
    FileName: string;
    Width: Integer;
    HeightUsed: Integer;
    TotalCells: Integer;
    ShadeCells: Integer;
    // Glyph category counts (useful for style presets)
    CountSpace: Integer;
    CountFull: Integer;      // █
    CountShade25: Integer;   // ░
    CountShade50: Integer;   // ▒
    CountShade75: Integer;   // ▓
    CountHalfUp: Integer;    // ▀
    CountHalfDown: Integer;  // ▄
    CountHalfLeft: Integer;  // ▌
    CountHalfRight: Integer; // ▐
    Weight: Integer;
    Passes: Integer;
    MirrorH: Boolean;
    DedupeCap: Integer;
    // Neighborhood stats (shade-only learner)
    Tried3, Tried5, Tried10: Integer;
    Added3, Added5, Added10: Integer;
    Blocked3, Blocked5, Blocked10: Integer;
  end;


// Retro stylizer applied *after* a normal Hybrid render.
// This keeps Hybrid behavior intact while giving a controlled "Tronic" look.
TTronicRetroStyle = (trsNeutral, trsBlocky, trsCgaCrunch, trsGrainy, trsScanline);

// Optional pass kind for multi-pass stylizing. The stylizer is per-cell,
// so "direction" is expressed via a coordinate transform used by the
// deterministic hash (and scanline row parity).
TTronicRetroPass = (trpLeftToRight, trpTopToBottom, trpBottomToTop, trpRightToLeft);

// Apply a post-process pass to an 80xN cell grid.
// - Style selects the remapping behavior.
// - Texture is 0..100 and controls how aggressively the style is applied.
procedure TronicRetroStylizeCells(var Cells: TCellArray; W, H: Integer; Style: TTronicRetroStyle; Texture: Integer);

// Same as TronicRetroStylizeCells, but with an explicit scope toggle.
// - IncludeBlocks = False: only ░▒▓ (176/177/178) are remapped.
// - IncludeBlocks = True : ░▒▓█ (including 219) are remapped.
procedure TronicRetroStylizeCellsEx(var Cells: TCellArray; W, H: Integer; Style: TTronicRetroStyle; Texture: Integer;
  const IncludeBlocks: Boolean);

// Multi-pass-friendly variant that applies a coordinate transform based on Pass.
procedure TronicRetroStylizeCellsPassEx(var Cells: TCellArray; W, H: Integer; Style: TTronicRetroStyle; Texture: Integer;
  const IncludeBlocks: Boolean; const Pass: TTronicRetroPass);

procedure TronicShadeClear;
function TronicShadeHasAny: Boolean;

// Save/Load TronicShade priors to a JSON file (independent from shader profiles).
procedure TronicShadeSaveToFile(const FN: string);
function TronicShadeLoadFromFile(const FN: string): Boolean;
function IsShadeGlyph(const ch: Byte): Boolean; inline;
// Return the total learned patch-counts by neighborhood scale.
// These are useful for showing "library size" in the UI.
procedure TronicShadeGetScaleTotals(out Tot3, Tot5, Tot10: Integer);

// Import an ANSI file directly into the Tronicshade library.
// This is independent from the ShaderLab/AutoShader libraries.
// NOTE: We intentionally learn *shade-only* glyphs (no letters/digits/punct).
// Import an ANSI file and learn Tronicshade patterns.
// NOTE: Tronicshade ANSI imports are append-only by design.
function TronicShadeImportANSI(const FN: string; const MaxRows: Integer = 500; const Append: Boolean = True;
  const Weight: Integer = 1; const MirrorH: Boolean = False; const Passes: Integer = 1; const TreatBlinkAsBrightBG: Boolean = True): Boolean;

// Same as TronicShadeImportANSI, but also returns a debug report.
// NOTE: FreePascal requires default parameters to be trailing; therefore the "Ex" form
// does not use defaults (callers should pass explicit values).
function TronicShadeImportANSIEx(const FN: string; const MaxRows: Integer; const Append: Boolean;
  const Weight: Integer; const MirrorH: Boolean; const Passes: Integer; const DedupeCap: Integer; const TreatBlinkAsBrightBG: Boolean;
  out Report: TTronicImportReport): Boolean;

// Learn priors but ignore non-shading glyphs (letters/digits/etc.).
// This is intended for building Tronicshade styles that only contain shading.
procedure TronicShadeLearnFromCellsShadeOnly(const Cells: TCellArray; W, H: Integer; const DedupeCap: Integer = 4;
  const Weight: Integer = 1);

// Same as TronicShadeLearnFromCellsShadeOnly but returns counts for debugging/UI.
procedure TronicShadeLearnFromCellsShadeOnlyEx(const Cells: TCellArray; W, H: Integer; const DedupeCap: Integer;
  const Weight: Integer; var Tried3, Tried5, Tried10: Integer; var Added3, Added5, Added10: Integer; var Blocked3, Blocked5, Blocked10: Integer);

// Learn style priors from a finished ANSI screen (Cells with width W and height H).
// DedupeCap controls how many times the same structural patch signature may be counted per key.
procedure TronicShadeLearnFromCells(const Cells: TCellArray; W, H: Integer; const DedupeCap: Integer = 4;
  const Weight: Integer = 1);

// Compute a style bonus (in log-prob space) for a candidate at (x,y).
// key3/key5/key10 are precomputed TronicShade key indices for the current source neighborhood.
// Candidate glyph + colors are provided so polarity and BG-keep can be biased.
function TronicShadeBonus(const key3, key5, key10: Integer; const Ch, FG, BG: Byte;
  const LeftAttr, TopAttr: Byte; const HasLeft, HasTop: Boolean;
  const Pal: array of TRGB): Double;

// Helper to compute key index from a neighborhood summarized as palette-index samples.
// The neighborhood is given as an array of palette indices (0..15), row-major, with width S and height S.
function TronicShadeKeyFromPalGrid(const S: Integer; const PalIdx: array of Byte; const Pal: array of TRGB): Integer;

implementation

uses
  fpjson, jsonparser,
  img2bin_palette;


procedure FreeDedupe; forward;
type
  TAnsiState = record
    FGBase: Byte;   // 0..7
    BGBase: Byte;   // 0..7
    Bold: Boolean;  // bright FG
    Blink: Boolean; // used as bright BG (iCE-like)
    BGBright: Boolean; // explicit bright BG (100..107)
  end;

  TCursorSave = record
    X, Y: Integer;
    Valid: Boolean;
  end;

  TInts = array of Integer;

// small helpers (kept here so the ANSI importer compiles as a standalone unit)
function ClampI(v, lo, hi: Integer): Integer; inline;
begin
  if v < lo then Exit(lo);
  if v > hi then Exit(hi);
  Result := v;
end;

procedure ResetState(var St: TAnsiState); inline;
begin
  St.FGBase := 7;
  St.BGBase := 0;
  St.Bold := False;
  St.Blink := False;
  St.BGBright := False;
end;

function ParseParams(const s: string): TInts;
var
  i, v: Integer;
  cur: string;
  arr: TInts;
  function Flush: Boolean;
  begin
    if cur = '' then Exit(False);
    v := StrToIntDef(cur, 0);
    SetLength(arr, Length(arr)+1);
    arr[High(arr)] := v;
    cur := '';
    Exit(True);
  end;
begin
  SetLength(arr, 0);
  cur := '';
  // accept "1;32;40" etc.
  for i := 1 to Length(s) do
  begin
    if s[i] in ['0'..'9','-','+'] then
      cur := cur + s[i]
    else if s[i] = ';' then
      Flush;
  end;
  Flush;
  Result := arr;
end;

procedure ApplySGR(var St: TAnsiState; const Params: TInts);
var
  i, c: Integer;
begin
  if Length(Params) = 0 then
  begin
    ResetState(St);
    Exit;
  end;

  for i := 0 to High(Params) do
  begin
    c := Params[i];
    case c of
      0: ResetState(St);
      1: St.Bold := True;
      22: St.Bold := False;
      5: St.Blink := True;
      25: St.Blink := False;
      30..37: St.FGBase := Byte(c - 30);
      39: begin St.FGBase := 7; St.Bold := False; end;
      40..47: begin St.BGBase := Byte(c - 40); St.BGBright := False; end;
      49: begin St.BGBase := 0; St.BGBright := False; end;
      90..97: begin St.FGBase := Byte(c - 90); St.Bold := True; end;
      100..107: begin St.BGBase := Byte(c - 100); St.BGBright := True; end;
    end;
  end;
end;


function MakeAttr(const St: TAnsiState; const TreatBlinkAsBrightBG: Boolean): Byte; inline;
var
  fg, bg: Integer;
  bgHi: Boolean;
begin
  fg := St.FGBase;
  if St.Bold then fg := fg + 8;
  bg := St.BGBase;
  // For Tronic import we treat blink as bright BG (iCE-like) to maximize shading patterns.
  bgHi := St.BGBright or (St.Blink and TreatBlinkAsBrightBG);
  if bgHi then bg := bg + 8;
  if fg < 0 then fg := 0 else if fg > 15 then fg := 15;
  if bg < 0 then bg := 0 else if bg > 15 then bg := 15;
  Result := Byte((bg shl 4) or fg);
end;

function TronicShadeImportANSI(const FN: string; const MaxRows: Integer; const Append: Boolean;
  const Weight: Integer; const MirrorH: Boolean; const Passes: Integer; const TreatBlinkAsBrightBG: Boolean): Boolean;
var
  rep: TTronicImportReport;
begin
  // Backwards-compatible wrapper: ignore the report.
  Result := TronicShadeImportANSIEx(FN, MaxRows, Append, Weight, MirrorH, Passes, 4, TreatBlinkAsBrightBG, rep);
end;

function TronicShadeImportANSIEx(const FN: string; const MaxRows: Integer; const Append: Boolean;
  const Weight: Integer; const MirrorH: Boolean; const Passes: Integer; const DedupeCap: Integer; const TreatBlinkAsBrightBG: Boolean;
  out Report: TTronicImportReport): Boolean;
var
  data: RawByteString;
  fs: TFileStream;
  i, n: Integer;
  ch: Byte;
  shadeSeen: Integer;
  cSpace, cFull, c25, c50, c75, cHalfU, cHalfD, cHalfL, cHalfR: Integer;
  St: TAnsiState;
  Cur: TCursorSave;
  grid: TCellArray;
  gridMir: TCellArray;
  W, H: Integer;
  x, y, maxY: Integer;
  passNo, passMax: Integer;
  esc: Boolean;
  csi: Boolean;
  seq: string;
  finalCh: Char;
  params: TInts;

  // Per-pass learn stats (summed into Report)
  tTried3, tTried5, tTried10: Integer;
  tAdded3, tAdded5, tAdded10: Integer;
  tBlocked3, tBlocked5, tBlocked10: Integer;

  // Decode a very small subset of UTF-8 that commonly appears in "ANSI" files
  // saved by modern editors (Unicode block elements). We map those Unicode
  // codepoints into their CP437 single-byte equivalents so shade-only learning
  // works on both CP437 and UTF-8 inputs.
  function NextTextByte(var idx: Integer): Byte;
  var
    b0, b1, b2: Byte;
  begin
    // idx is 1-based into RawByteString
    b0 := Byte(data[idx]);

    // Fast path: plain ASCII
    if b0 < $80 then
    begin
      Inc(idx);
      Exit(b0);
    end;

    // CP437-first: the overwhelming majority of ANSI art is single-byte DOS.
    // Only decode UTF-8 when we *recognize* the common block-element sequence
    // (E2 96 xx = U+2580..U+259F and friends).
    if (b0 = $E2) and (idx + 2 <= n) then
    begin
      b1 := Byte(data[idx+1]);
      b2 := Byte(data[idx+2]);

      // U+25xx block elements are encoded as E2 96 xx
      if (b1 = $96) then
      begin
        // consume 3 bytes
        Inc(idx, 3);
        // Map common shade/block Unicode characters to CP437 bytes.
        // Known encodings:
        //   ░ U+2591 = E2 96 91
        //   ▒ U+2592 = E2 96 92
        //   ▓ U+2593 = E2 96 93
        //   █ U+2588 = E2 96 88
        //   ▄ U+2584 = E2 96 84
        //   ▀ U+2580 = E2 96 80
        case b2 of
          $91: Exit(176); // ░
          $92: Exit(177); // ▒
          $93: Exit(178); // ▓
          $88: Exit(219); // █
          $84: Exit(220); // ▄
          $80: Exit(223); // ▀
          $8C: Exit(221); // ▌
          $90: Exit(222); // ▐
        else
          // Unknown unicode block: treat as space so we don't poison the grid.
          Exit(32);
        end;
      end;
    end;

    // Default: treat as raw CP437 byte.
    Inc(idx);
    Exit(b0);
  end;

  // Map any printable glyph into one of the Tronicshade shade glyphs.
  // This lets Tronicshade be trained from ANSI art that uses "ASCII shading"
  // (.,:;-=+*#@) or letters/digits instead of CP437 block elements.
  function MapAnyToShade(const b: Byte): Byte; inline;
  begin
    if IsShadeGlyph(b) then Exit(b);
    // Common light marks
    case b of
      32, Ord('.'), Ord('`'), Ord('\'): Exit(32);
      Ord(','), Ord(':'), Ord(';'): Exit(176);
      Ord('-'), Ord('_'), Ord('~'), Ord('+'), Ord('='): Exit(177);
      Ord('*'), Ord('#'), Ord('%'), Ord('&'), Ord('@'): Exit(178);
    end;
    // Letters/digits and everything else -> medium shade.
    Exit(177);
  end;

  procedure EnsureGrid;
  var
    idx: Integer;
  begin
    if Length(grid) = W * H then Exit;
    SetLength(grid, W * H);
    for idx := 0 to High(grid) do
    begin
      grid[idx].Ch := 32;
      grid[idx].Attr := MakeAttr(St, TreatBlinkAsBrightBG);
    end;
  end;

  procedure PutCell(const ax, ay: Integer; const aCh: Byte; const aAttr: Byte);
  var
    idx: Integer;
  begin
    if (ax < 0) or (ax >= W) or (ay < 0) or (ay >= H) then Exit;
    idx := ay * W + ax;
    grid[idx].Ch := aCh;
    grid[idx].Attr := aAttr;
    if ay > maxY then maxY := ay;
    // Count categories for style analysis
    case aCh of
      32: Inc(cSpace);
      219: Inc(cFull);
      176: Inc(c25);
      177: Inc(c50);
      178: Inc(c75);
      223: Inc(cHalfU);
      220: Inc(cHalfD);
      221: Inc(cHalfL);
      222: Inc(cHalfR);
    end;
    if IsShadeGlyph(aCh) then Inc(shadeSeen);
  end;

  procedure ClearLine(const ay, x0, x1: Integer; const aAttr: Byte);
  var
    ax: Integer;
  begin
    if (ay < 0) or (ay >= H) then Exit;
    for ax := ClampI(x0, 0, W-1) to ClampI(x1, 0, W-1) do
      PutCell(ax, ay, 32, aAttr);
  end;

  procedure ClearFromCursorToEnd;
  var
    ay: Integer;
  begin
    ClearLine(y, x, W-1, MakeAttr(St, TreatBlinkAsBrightBG));
    for ay := y+1 to H-1 do
      ClearLine(ay, 0, W-1, MakeAttr(St, TreatBlinkAsBrightBG));
  end;

  procedure ApplyCSI(const sSeq: string; out fCh: Char);
  var
    body: string;
    p1, p2: Integer;
  begin
    if sSeq = '' then begin fCh := #0; Exit; end;
    fCh := sSeq[Length(sSeq)];
    body := Copy(sSeq, 1, Length(sSeq)-1);
    params := ParseParams(body);
    case fCh of
      'm': ApplySGR(St, params);
      'H', 'f':
        begin
          p1 := 1; p2 := 1;
          if Length(params) >= 1 then p1 := params[0];
          if Length(params) >= 2 then p2 := params[1];
          y := ClampI(p1-1, 0, H-1);
          x := ClampI(p2-1, 0, W-1);
        end;
      'A': begin p1 := 1; if Length(params) >= 1 then p1 := params[0]; y := ClampI(y - p1, 0, H-1); end;
      'B': begin p1 := 1; if Length(params) >= 1 then p1 := params[0]; y := ClampI(y + p1, 0, H-1); end;
      'C': begin p1 := 1; if Length(params) >= 1 then p1 := params[0]; x := ClampI(x + p1, 0, W-1); end;
      'D': begin p1 := 1; if Length(params) >= 1 then p1 := params[0]; x := ClampI(x - p1, 0, W-1); end;
      'J':
        begin
          p1 := 0; if Length(params) >= 1 then p1 := params[0];
          case p1 of
            0: ClearFromCursorToEnd;
            2: begin ClearLine(0, 0, W-1, MakeAttr(St, TreatBlinkAsBrightBG)); for p2 := 1 to H-1 do ClearLine(p2, 0, W-1, MakeAttr(St, TreatBlinkAsBrightBG)); x := 0; y := 0; end;
          end;
        end;
      'K':
        begin
          p1 := 0; if Length(params) >= 1 then p1 := params[0];
          case p1 of
            0: ClearLine(y, x, W-1, MakeAttr(St, TreatBlinkAsBrightBG));
            1: ClearLine(y, 0, x, MakeAttr(St, TreatBlinkAsBrightBG));
            2: ClearLine(y, 0, W-1, MakeAttr(St, TreatBlinkAsBrightBG));
          end;
        end;
      's': begin Cur.X := x; Cur.Y := y; Cur.Valid := True; end;
      'u': if Cur.Valid then begin x := Cur.X; y := Cur.Y; end;
    end;
  end;

begin
  Result := False;
  if not FileExists(FN) then Exit(False);
  FillChar(Report, SizeOf(Report), 0);
  Report.FileName := FN;
  Report.Weight := Weight;
  Report.Passes := Passes;
  Report.MirrorH := MirrorH;
  Report.DedupeCap := DedupeCap;
  // Append-only: never clear the existing Tronicshade library on ANSI import.
  // (The Append parameter is kept for API compatibility.)

  W := 80;
  H := MaxRows;
  if H < 1 then H := 1;

  ResetState(St);
  Cur.Valid := False;
  x := 0; y := 0; maxY := 0;
  shadeSeen := 0;
  cSpace := 0; cFull := 0; c25 := 0; c50 := 0; c75 := 0;
  cHalfU := 0; cHalfD := 0; cHalfL := 0; cHalfR := 0;
  EnsureGrid;

  fs := TFileStream.Create(FN, fmOpenRead or fmShareDenyNone);
  try
    SetLength(data, fs.Size);
    if fs.Size > 0 then fs.ReadBuffer(Pointer(data)^, fs.Size);
  finally
    fs.Free;
  end;

  esc := False;
  csi := False;
  seq := '';
  n := Length(data);
  i := 1;
  while i <= n do
  begin
    ch := NextTextByte(i);

    if esc then
    begin
      if not csi then
      begin
        if ch = Ord('[') then
        begin
          csi := True;
          seq := '';
        end
        else
        begin
          // non-CSI escape, ignore
          esc := False;
        end;
        Continue;
      end
      else
      begin
        // CSI: read until final byte in @A-Z[\]^_`a-z{|}~
        seq := seq + Chr(ch);
        if (ch >= 64) and (ch <= 126) then
        begin
          ApplyCSI(seq, finalCh);
          esc := False;
          csi := False;
          seq := '';
        end;
        Continue;
      end;
    end;

    case ch of
      27: begin esc := True; csi := False; seq := ''; Continue; end; // ESC
      13: begin x := 0; Continue; end; // CR
      10: begin if y < H-1 then Inc(y); Continue; end; // LF
      8:  begin if x > 0 then Dec(x); Continue; end; // BS
    end;

    if ch >= 32 then
    begin
      // Force glyphs into shade-only domain for Tronicshade training.
      //
      // Many CP437 ANSI artworks "draw" solid areas using a SPACE character
      // with a non-black background color. If we naively keep it as SPACE,
      // the shade-only learner often sees nothing worth learning.
      //
      // So: if the glyph is SPACE and the background color is non-zero,
      // treat it as a solid block for training purposes.
      if (ch = 32) and ((MakeAttr(St, TreatBlinkAsBrightBG) shr 4) <> 0) then
        ch := 219; // █ (CP437)
      ch := MapAnyToShade(ch);
      PutCell(x, y, ch, MakeAttr(St, TreatBlinkAsBrightBG));
      Inc(x);
      if x >= W then
      begin
        x := 0;
        if y < H-1 then Inc(y);
      end;
    end;
  end;

  // --- basic report fields ------------------------------------------------
  FillChar(Report, SizeOf(Report), 0);
  Report.FileName := FN;
  Report.Width := W;
  Report.Weight := Weight;
  Report.Passes := Passes;
  Report.MirrorH := MirrorH;
  Report.DedupeCap := DedupeCap;

  // learn shade-only from used rows
  if maxY < 0 then maxY := 0;
  if maxY >= H then maxY := H-1;
    // Trim grid to used rows so learner's (W*H) sanity check passes.
  SetLength(grid, W * (maxY+1));
  Report.HeightUsed := maxY + 1;
  Report.TotalCells := W * (maxY + 1);
  Report.ShadeCells := shadeSeen;
  Report.CountSpace := cSpace;
  Report.CountFull := cFull;
  Report.CountShade25 := c25;
  Report.CountShade50 := c50;
  Report.CountShade75 := c75;
  Report.CountHalfUp := cHalfU;
  Report.CountHalfDown := cHalfD;
  Report.CountHalfLeft := cHalfL;
  Report.CountHalfRight := cHalfR;
  // Multi-pass learning: repeat the learn step Passes times. Between passes we reset
  // the per-key dedupe lists so the same structural patches can be counted again.
  // Effective strength = Weight * Passes (and *2 if mirror is enabled).
  passMax := Passes;
  if passMax < 1 then passMax := 1;
  if passMax > 999 then passMax := 999;
  for passNo := 1 to passMax do
  begin
    // Count patches for the original orientation.
    TronicShadeLearnFromCellsShadeOnlyEx(grid, W, maxY+1, DedupeCap, Weight,
      Report.Tried3, Report.Tried5, Report.Tried10,
      Report.Added3, Report.Added5, Report.Added10,
      Report.Blocked3, Report.Blocked5, Report.Blocked10);

    // Optional augmentation: learn a horizontally mirrored version as well.
    // This improves generalization for directional patterns.
    if MirrorH then
    begin
      if Length(gridMir) <> Length(grid) then SetLength(gridMir, Length(grid));
      // Mirror each row: (x,y) -> (W-1-x,y)
      for y := 0 to maxY do
        for x := 0 to W-1 do
          gridMir[y*W + (W-1-x)] := grid[y*W + x];
      // Count patches for the mirrored orientation.
      TronicShadeLearnFromCellsShadeOnlyEx(gridMir, W, maxY+1, DedupeCap, Weight,
        Report.Tried3, Report.Tried5, Report.Tried10,
        Report.Added3, Report.Added5, Report.Added10,
        Report.Blocked3, Report.Blocked5, Report.Blocked10);
    end;

    // Reset dedupe between passes so repeated training actually strengthens counts.
    if passNo < passMax then
      FreeDedupe;
  end;

  // Return True as long as we successfully read & parsed the file.
  // The library may still remain empty if the ANSI had no usable content,
  // but that's not a fatal error for "append" workflows.
  Result := True;
end;

const
  // Key dimensions
  SCALE_COUNT = 3; // 3,5,10
  CDOM_COUNT = 3;  // 1,2,3+
  FLAT_COUNT = 2;
  TRANS_COUNT = 2;
  EDGE_COUNT = 2;
  BUSY_COUNT = 3; // calm/med/busy
  KEY_COUNT = SCALE_COUNT * CDOM_COUNT * FLAT_COUNT * TRANS_COUNT * EDGE_COUNT * EDGE_COUNT * BUSY_COUNT; // 432

  GLYPH_COUNT = 9;
  POL_COUNT = 3;

type
  TKeyGlyphCounts = array[0..KEY_COUNT-1, 0..GLYPH_COUNT-1] of Cardinal;
  TKeyTotals = array[0..KEY_COUNT-1] of Cardinal;
  TKeyPolCounts = array[0..KEY_COUNT-1, 0..POL_COUNT-1] of Cardinal;
  TKeyKeepBGCounts = array[0..KEY_COUNT-1, 0..1] of Cardinal;

  // Learned FG/BG pair preferences (16x16) per key.
  // This is what makes ANSI shading feel "painted": artists keep pairs stable
  // and vary glyph coverage (░▒▓▀▄▌▐) to blend.
  TKeyPairCounts = array[0..KEY_COUNT-1, 0..15, 0..15] of Cardinal;

  // small fixed-size signature for dedupe (structure-first)
  TPatchSig = QWord;

var
  GGlyph: TKeyGlyphCounts;
  GTotGlyph: TKeyTotals;
  GPol: TKeyPolCounts;
  GTotPol: TKeyTotals;
  GKeepBG: TKeyKeepBGCounts;
  GTotKeepBG: TKeyTotals;
  GPair: TKeyPairCounts;
  GTotPair: TKeyTotals;
  GHasAny: Boolean = False;

  // Dedupe map: Key -> signature -> count
  // We keep it light: one TStringList per key, storing "sig=count" as hex.
  GDedupe: array[0..KEY_COUNT-1] of TStringList;

function IsShadeGlyph(const ch: Byte): Boolean; inline;
begin
  case ch of
    32, 219, 178, 177, 176, 223, 220, 221, 222: Result := True;
  else
    Result := False;
  end;
end;

procedure TronicShadeSaveToFile(const FN: string);
var
  root: TJSONObject;
  arr, arr2: TJSONArray;
  k, g: Integer;
  fs: TFileStream;
  s: String;
begin
  root := TJSONObject.Create;
  try
    root.Add('ver', 2);
    root.Add('hasAny', GHasAny);

    // Glyph counts: [KEY][GLYPH]
    arr := TJSONArray.Create;
    for k := 0 to KEY_COUNT-1 do
    begin
      arr2 := TJSONArray.Create;
      for g := 0 to GLYPH_COUNT-1 do
        arr2.Add(Int64(GGlyph[k][g]));
      arr.Add(arr2);
    end;
    root.Add('glyph', arr);

    arr := TJSONArray.Create;
    for k := 0 to KEY_COUNT-1 do arr.Add(Int64(GTotGlyph[k]));
    root.Add('totGlyph', arr);

    // Polarity counts: [KEY][POL]
    arr := TJSONArray.Create;
    for k := 0 to KEY_COUNT-1 do
    begin
      arr2 := TJSONArray.Create;
      for g := 0 to POL_COUNT-1 do
        arr2.Add(Int64(GPol[k][g]));
      arr.Add(arr2);
    end;
    root.Add('pol', arr);

    arr := TJSONArray.Create;
    for k := 0 to KEY_COUNT-1 do arr.Add(Int64(GTotPol[k]));
    root.Add('totPol', arr);

    // KeepBG counts: [KEY][2]
    arr := TJSONArray.Create;
    for k := 0 to KEY_COUNT-1 do
    begin
      arr2 := TJSONArray.Create;
      arr2.Add(Int64(GKeepBG[k][0]));
      arr2.Add(Int64(GKeepBG[k][1]));
      arr.Add(arr2);
    end;
    root.Add('keepBG', arr);

    arr := TJSONArray.Create;
    for k := 0 to KEY_COUNT-1 do arr.Add(Int64(GTotKeepBG[k]));
    root.Add('totKeepBG', arr);

    // FG/BG pair counts: [KEY][16][16]
    arr := TJSONArray.Create;
    for k := 0 to KEY_COUNT-1 do
    begin
      arr2 := TJSONArray.Create;
      // store as flat 256 list to keep JSON smaller (fg*16+bg)
      for g := 0 to 255 do
        arr2.Add(Int64(GPair[k][g div 16][g mod 16]));
      arr.Add(arr2);
    end;
    root.Add('pair', arr);

    arr := TJSONArray.Create;
    for k := 0 to KEY_COUNT-1 do arr.Add(Int64(GTotPair[k]));
    root.Add('totPair', arr);

    ForceDirectories(ExtractFileDir(FN));
    s := root.AsJSON;
    fs := TFileStream.Create(FN, fmCreate);
    try
      fs.WriteBuffer(Pointer(s)^, Length(s));
    finally
      fs.Free;
    end;
  finally
    root.Free;
  end;
end;

function TronicShadeLoadFromFile(const FN: string): Boolean;
var
  json: TJSONData;
  root: TJSONObject;
  arr, arr2: TJSONArray;
  k, g: Integer;
  fs: TFileStream;
  s: String;
begin
  Result := False;
  if not FileExists(FN) then Exit(False);

  fs := TFileStream.Create(FN, fmOpenRead or fmShareDenyNone);
  try
    SetLength(s, fs.Size);
    if fs.Size > 0 then
      fs.ReadBuffer(Pointer(s)^, Length(s));
  finally
    fs.Free;
  end;

  json := GetJSON(s);
  try
    if (json = nil) or (json.JSONType <> jtObject) then Exit(False);
    root := TJSONObject(json);

    TronicShadeClear;

    GHasAny := root.Get('hasAny', False);

    arr := root.Arrays['glyph'];
    if (arr <> nil) and (arr.Count = KEY_COUNT) then
      for k := 0 to KEY_COUNT-1 do
      begin
        arr2 := arr.Arrays[k];
        if (arr2 <> nil) then
          for g := 0 to GLYPH_COUNT-1 do
            if g < arr2.Count then
              GGlyph[k][g] := Cardinal(arr2.Integers[g]);
      end;

arr := root.Arrays['totGlyph'];
    if (arr <> nil) and (arr.Count = KEY_COUNT) then
      for k := 0 to KEY_COUNT-1 do
        GTotGlyph[k] := Cardinal(arr.Integers[k]);

    arr := root.Arrays['pol'];
    if (arr <> nil) and (arr.Count = KEY_COUNT) then
      for k := 0 to KEY_COUNT-1 do
      begin
        arr2 := arr.Arrays[k];
        if (arr2 <> nil) and (arr2.Count = POL_COUNT) then
          for g := 0 to POL_COUNT-1 do
            GPol[k][g] := Cardinal(arr2.Integers[g]);
      end;

    arr := root.Arrays['totPol'];
    if (arr <> nil) and (arr.Count = KEY_COUNT) then
      for k := 0 to KEY_COUNT-1 do
        GTotPol[k] := Cardinal(arr.Integers[k]);

    arr := root.Arrays['keepBG'];
    if (arr <> nil) and (arr.Count = KEY_COUNT) then
      for k := 0 to KEY_COUNT-1 do
      begin
        arr2 := arr.Arrays[k];
        if (arr2 <> nil) and (arr2.Count >= 2) then
        begin
          GKeepBG[k][0] := Cardinal(arr2.Integers[0]);
          GKeepBG[k][1] := Cardinal(arr2.Integers[1]);
        end;
      end;

    arr := root.Arrays['totKeepBG'];
    if (arr <> nil) and (arr.Count = KEY_COUNT) then
      for k := 0 to KEY_COUNT-1 do
        GTotKeepBG[k] := Cardinal(arr.Integers[k]);

    // FG/BG pair counts (optional; ver>=2)
    arr := root.Arrays['pair'];
    if (arr <> nil) and (arr.Count = KEY_COUNT) then
      for k := 0 to KEY_COUNT-1 do
      begin
        arr2 := arr.Arrays[k];
        if (arr2 <> nil) and (arr2.Count >= 256) then
          for g := 0 to 255 do
            GPair[k][g div 16][g mod 16] := Cardinal(arr2.Integers[g]);
      end;

    arr := root.Arrays['totPair'];
    if (arr <> nil) and (arr.Count = KEY_COUNT) then
      for k := 0 to KEY_COUNT-1 do
        GTotPair[k] := Cardinal(arr.Integers[k]);


    // If file says hasAny=false but data exists, recompute quickly.
    if not GHasAny then
      for k := 0 to KEY_COUNT-1 do
        if GTotGlyph[k] > 0 then begin GHasAny := True; Break; end;

    Result := True;
  finally
    json.Free;
  end;
end;

procedure TronicShadeGetScaleTotals(out Tot3, Tot5, Tot10: Integer);
const
  SCALE_STRIDE = CDOM_COUNT * FLAT_COUNT * TRANS_COUNT * EDGE_COUNT * EDGE_COUNT * BUSY_COUNT;
var
  k, s: Integer;
begin
  Tot3 := 0; Tot5 := 0; Tot10 := 0;
  for k := 0 to KEY_COUNT-1 do
  begin
    s := k div SCALE_STRIDE;
    case s of
      0: Inc(Tot3, GTotGlyph[k]);
      1: Inc(Tot5, GTotGlyph[k]);
    else
      Inc(Tot10, GTotGlyph[k]);
    end;
  end;
end;


function RGBLuma(const c: TRGB): Integer; inline;
begin
  Result := (77*Integer(c.R) + 150*Integer(c.G) + 29*Integer(c.B)) shr 8;
end;

function GlyphClassIndex(ch: Byte): Integer; inline;
begin
  // order must match GLYPH_COUNT and TronicShadeBonus
  case ch of
    32:  Result := 0; // space
    219: Result := 1; // █
    178: Result := 2; // ▓
    177: Result := 3; // ▒
    176: Result := 4; // ░
    223: Result := 5; // ▀
    220: Result := 6; // ▄
    221: Result := 7; // ▌
    222: Result := 8; // ▐
  else
    // fallback: treat as "solid" bucket
    Result := 1;
  end;
end;

function ScaleIndexFromSize(S: Integer): Integer; inline;
begin
  if S <= 3 then Exit(0);
  if S <= 5 then Exit(1);
  Result := 2;
end;

function KeyIndex(const ScaleIdx, Cdom, Flat, Trans, EdgeTB, EdgeLR, Busy: Integer): Integer; inline;
var
  idx: Integer;
begin
  idx := ScaleIdx;
  idx := idx * CDOM_COUNT + Cdom;
  idx := idx * FLAT_COUNT + Flat;
  idx := idx * TRANS_COUNT + Trans;
  idx := idx * EDGE_COUNT + EdgeTB;
  idx := idx * EDGE_COUNT + EdgeLR;
  idx := idx * BUSY_COUNT + Busy;
  Result := idx;
end;

function SigFNV1a64(const data: array of Byte): QWord;
var
  i: Integer;
  h: QWord;
begin
  h := QWord($CBF29CE484222325);
  for i := Low(data) to High(data) do
  begin
    h := h xor data[i];
    h := h * QWord($100000001B3);
  end;
  Result := h;
end;

function DominantColorBucket(const hist: array of Integer): Integer;
var
  nonzero, i: Integer;
begin
  nonzero := 0;
  for i := Low(hist) to High(hist) do
    if hist[i] > 0 then Inc(nonzero);
  if nonzero <= 1 then Exit(0); // 1
  if nonzero = 2 then Exit(1);  // 2
  Result := 2;                 // 3+
end;

function BusyBucket(changes: Integer; S: Integer): Integer;
var
  maxc: Integer;
  pct: Integer;
begin
  // changes across grid edges, normalize to 0..100
  maxc := (S*(S-1)) * 2;
  if maxc <= 0 then Exit(0);
  pct := (changes * 100) div maxc;
  if pct < 18 then Exit(0);
  if pct < 45 then Exit(1);
  Result := 2;
end;

function TronicPolarityFromColors(const FG, BG: Byte; const Pal: array of TRGB): Integer;
var
  lf, lb: Integer;
begin
  lf := RGBLuma(Pal[FG]);
  lb := RGBLuma(Pal[BG]);
  if Abs(lf - lb) < 16 then Exit(Ord(tpNeutral));
  if lf < lb then Exit(Ord(tpDarkInk)) else Exit(Ord(tpLightInk));
end;

function TronicShadeKeyFromPalGrid(const S: Integer; const PalIdx: array of Byte; const Pal: array of TRGB): Integer;
var
  hist: array[0..15] of Integer;
  i, x, y: Integer;
  cdom, flat, trans, edgeTB, edgeLR, busy: Integer;
  topL, botL, leftL, rightL: Int64;
  topN, botN, leftN, rightN: Integer;
  changes: Integer;
  a, b: Byte;
  best1, best2: Integer;
  sumL, sumL2: Int64;
  n: Integer;
  meanL: Double;
  varL: Double;
  scaleIdx: Integer;
begin
  if Length(PalIdx) <> (S*S) then Exit(0);
  FillChar(hist, SizeOf(hist), 0);
  sumL := 0; sumL2 := 0;
  for i := 0 to S*S-1 do
  begin
    Inc(hist[PalIdx[i] and $0F]);
    n := RGBLuma(Pal[PalIdx[i] and $0F]);
    sumL += n;
    sumL2 += Int64(n) * Int64(n);
  end;

  cdom := DominantColorBucket(hist);

  // top/bottom and left/right luma differences
  topL := 0; botL := 0; leftL := 0; rightL := 0;
  topN := 0; botN := 0; leftN := 0; rightN := 0;
  for y := 0 to S-1 do
    for x := 0 to S-1 do
    begin
      n := RGBLuma(Pal[PalIdx[y*S + x] and $0F]);
      if y < (S div 2) then begin topL += n; Inc(topN); end
      else begin botL += n; Inc(botN); end;
      if x < (S div 2) then begin leftL += n; Inc(leftN); end
      else begin rightL += n; Inc(rightN); end;
    end;

  if topN > 0 then topL := topL div topN;
  if botN > 0 then botL := botL div botN;
  if leftN > 0 then leftL := leftL div leftN;
  if rightN > 0 then rightL := rightL div rightN;

  edgeTB := Ord(Abs(Integer(topL) - Integer(botL)) >= 20);
  edgeLR := Ord(Abs(Integer(leftL) - Integer(rightL)) >= 20);

  // adjacency changes
  changes := 0;
  for y := 0 to S-1 do
    for x := 0 to S-1 do
    begin
      a := PalIdx[y*S + x] and $0F;
      if x+1 < S then begin b := PalIdx[y*S + (x+1)] and $0F; if a <> b then Inc(changes); end;
      if y+1 < S then begin b := PalIdx[(y+1)*S + x] and $0F; if a <> b then Inc(changes); end;
    end;
  busy := BusyBucket(changes, S);

  // flatness from luma variance + dominant colors
  if (S*S) > 0 then
  begin
    meanL := sumL / (S*S);
    varL := (sumL2 / (S*S)) - (meanL * meanL);
  end
  else
    varL := 0;
  flat := Ord((cdom = 0) and (varL < 80.0) and (busy = 0));

  // transition: two strong colors + not flat
  best1 := 0; best2 := 0;
  for i := 0 to 15 do
  begin
    if hist[i] > best1 then
    begin
      best2 := best1;
      best1 := hist[i];
    end
    else if hist[i] > best2 then
      best2 := hist[i];
  end;
  trans := Ord((cdom >= 1) and (best2 > 0) and (best2 * 100 div (S*S) >= 18) and (flat = 0));

  scaleIdx := ScaleIndexFromSize(S);
  Result := KeyIndex(scaleIdx, cdom, flat, trans, edgeTB, edgeLR, busy);
end;

procedure EnsureDedupe;
var
  i: Integer;
begin
  for i := 0 to KEY_COUNT-1 do
    if GDedupe[i] = nil then
    begin
      GDedupe[i] := TStringList.Create;
      GDedupe[i].Sorted := True;
      GDedupe[i].Duplicates := dupIgnore;
    end;
end;

procedure FreeDedupe;
var
  i: Integer;
begin
  for i := 0 to KEY_COUNT-1 do
    FreeAndNil(GDedupe[i]);
end;

procedure TronicShadeClear;
begin
  FillChar(GGlyph, SizeOf(GGlyph), 0);
  FillChar(GTotGlyph, SizeOf(GTotGlyph), 0);
  FillChar(GPol, SizeOf(GPol), 0);
  FillChar(GTotPol, SizeOf(GTotPol), 0);
  FillChar(GKeepBG, SizeOf(GKeepBG), 0);
  FillChar(GTotKeepBG, SizeOf(GTotKeepBG), 0);
  FillChar(GPair, SizeOf(GPair), 0);
  FillChar(GTotPair, SizeOf(GTotPair), 0);
  FreeDedupe;
  GHasAny := False;
end;

function TronicShadeHasAny: Boolean;
begin
  Result := GHasAny;
end;

function CellFG(const C: TCell): Byte; inline;
begin
  Result := C.Attr and $0F;
end;

function CellBG(const C: TCell): Byte; inline;
begin
  Result := (C.Attr shr 4) and $0F;
end;

function CellApproxPalIdx(const C: TCell; const Pal: array of TRGB): Byte;
var
  fg, bg: TRGB;
  lf, lb: Integer;
begin
  // Use the dominant background color for style context; for solid blocks use FG.
  if (C.Ch = 219) or (C.Ch = 223) or (C.Ch = 220) then
    Exit(CellFG(C));
  // Shade blocks are a mix; choose whichever is closer to mid-luma of the mix.
  fg := Pal[CellFG(C)];
  bg := Pal[CellBG(C)];
  lf := RGBLuma(fg);
  lb := RGBLuma(bg);
  if lf > lb then Result := CellFG(C) else Result := CellBG(C);
end;

procedure ExtractNeighborhoodPal(const Cells: TCellArray; W, H, cx, cy, S: Integer; out OutIdx: array of Byte; const Pal: array of TRGB);
var
  r, c, x, y, i: Integer;
begin
  i := 0;
  for r := -(S div 2) to (S div 2) do
    for c := -(S div 2) to (S div 2) do
    begin
      x := ClampI(cx + c, 0, W-1);
      y := ClampI(cy + r, 0, H-1);
      OutIdx[i] := CellApproxPalIdx(Cells[y*W + x], Pal) and $0F;
      Inc(i);
    end;
end;

function PatchSigFromPalGrid(const S: Integer; const PalIdx: array of Byte): TPatchSig;
var
  tmp: array of Byte;
  i: Integer;
begin
  // Canonicalize: map most common color to 0, second to 1, others to 2.
  SetLength(tmp, S*S);
  for i := 0 to S*S-1 do tmp[i] := PalIdx[i] and $0F;
  Result := SigFNV1a64(tmp);
end;

function DedupeAllow(const Key: Integer; const Sig: TPatchSig; const Cap: Integer): Boolean;
var
  sl: TStringList;
  k: String;
  idx: Integer;
  cnt: PtrInt;
begin
  EnsureDedupe;
  sl := GDedupe[Key];
  k := IntToHex(Sig, 16);

  // NOTE: TStringList in Sorted mode does not allow modifying name/value pairs
  // (it raises EStringListError: "Operation not allowed on sorted list").
  // We keep the list Sorted for fast lookup, store the signature as the string,
  // and store the per-signature count in Objects[] (safe to mutate).
  if not sl.Find(k, idx) then
  begin
    sl.AddObject(k, TObject(PtrInt(1)));
    Exit(True);
  end;

  cnt := PtrInt(sl.Objects[idx]);
  if cnt >= Cap then Exit(False);
  sl.Objects[idx] := TObject(cnt + 1);
  Result := True;
end;

procedure BumpCounts(const Key: Integer; const Ch, FG, BG: Byte; const KeepBG: Boolean;
  const Pal: array of TRGB; const Weight: Integer);
var
  gi: Integer;
  pi: Integer;
  w: Cardinal;
begin
  // Weight is a user-facing "training passes" knob (implemented as count weight).
  // Keep it sane so styles don't overflow counters.
  if Weight <= 1 then w := 1 else if Weight > 1000 then w := 1000 else w := Cardinal(Weight);
  gi := ClampI(GlyphClassIndex(Ch), 0, GLYPH_COUNT-1);
  Inc(GGlyph[Key][gi], w);
  Inc(GTotGlyph[Key], w);

  // polarity only matters for shades/halves
  if (Ch = 176) or (Ch = 177) or (Ch = 178) or (Ch = 223) or (Ch = 220) or (Ch = 221) or (Ch = 222) then
  begin
    pi := TronicPolarityFromColors(FG and $0F, BG and $0F, Pal);
    Inc(GPol[Key][ClampI(pi, 0, POL_COUNT-1)], w);
    Inc(GTotPol[Key], w);
  end;

  if KeepBG then Inc(GKeepBG[Key][1], w) else Inc(GKeepBG[Key][0], w);
  Inc(GTotKeepBG[Key], w);

  GHasAny := True;
end;

procedure BumpCountsShadeOnly(const Key: Integer; const Ch, FG, BG: Byte; const KeepBG: Boolean;
  const Pal: array of TRGB; const Weight: Integer);
begin
  // Strip letters/numbers/punctuation/etc. When building Tronicshade styles, we only
  // learn from shading glyphs (spaces/blocks/halves).
  if not IsShadeGlyph(Ch) then Exit;
  BumpCounts(Key, Ch, FG, BG, KeepBG, Pal, Weight);
end;

procedure TronicShadeLearnFromCellsShadeOnlyEx(const Cells: TCellArray; W, H: Integer;
  const DedupeCap: Integer; const Weight: Integer;
  var Tried3, Tried5, Tried10: Integer; var Added3, Added5, Added10: Integer; var Blocked3, Blocked5, Blocked10: Integer);
const
  SIZES: array[0..2] of Integer = (3, 5, 10);
var
  x, y, si, S: Integer;
  grid: array of Byte;
  key: Integer;
  sig: TPatchSig;
  c: TCell;
  hasL, hasT: Boolean;
  leftAttr, topAttr: Byte;
  keepBG: Boolean;
  pal: array[0..15] of TRGB;
  i: Integer;
  blocked: Boolean;
begin
  if (W <= 0) or (H <= 0) or (Length(Cells) <> W*H) then Exit;

  for i := 0 to 15 do pal[i] := Palette16(pkVGA, i);

  for y := 0 to H-1 do
    for x := 0 to W-1 do
    begin
      c := Cells[y*W + x];
      if not IsShadeGlyph(c.Ch) then Continue;

      hasL := x > 0;
      hasT := y > 0;
      if hasL then leftAttr := Cells[y*W + (x-1)].Attr else leftAttr := 0;
      if hasT then topAttr := Cells[(y-1)*W + x].Attr else topAttr := 0;
      keepBG := False;
      if hasL and (((leftAttr shr 4) and $0F) = CellBG(c)) then keepBG := True;
      if hasT and (((topAttr shr 4) and $0F) = CellBG(c)) then keepBG := True;

      for si := 0 to 2 do
      begin
        S := SIZES[si];
        SetLength(grid, S*S);
        ExtractNeighborhoodPal(Cells, W, H, x, y, S, grid, pal);
        key := TronicShadeKeyFromPalGrid(S, grid, pal);
        sig := PatchSigFromPalGrid(S, grid);

        blocked := not DedupeAllow(key, sig, DedupeCap);
        case S of
          3: begin Inc(Tried3); if blocked then Inc(Blocked3) else Inc(Added3); end;
          5: begin Inc(Tried5); if blocked then Inc(Blocked5) else Inc(Added5); end;
          10: begin Inc(Tried10); if blocked then Inc(Blocked10) else Inc(Added10); end;
        end;
        if blocked then Continue;
        BumpCountsShadeOnly(key, c.Ch, CellFG(c), CellBG(c), keepBG, pal, Weight);
      end;
    end;
end;

procedure TronicShadeLearnFromCellsShadeOnly(const Cells: TCellArray; W, H: Integer;
  const DedupeCap: Integer; const Weight: Integer);
var
  tT3, tT5, tT10: Integer;
  tA3, tA5, tA10: Integer;
  tB3, tB5, tB10: Integer;
begin
  // Wrapper for backwards compatibility.
  tT3 := 0; tT5 := 0; tT10 := 0;
  tA3 := 0; tA5 := 0; tA10 := 0;
  tB3 := 0; tB5 := 0; tB10 := 0;
  TronicShadeLearnFromCellsShadeOnlyEx(Cells, W, H, DedupeCap, Weight,
    tT3, tT5, tT10,
    tA3, tA5, tA10,
    tB3, tB5, tB10);
end;

procedure TronicShadeLearnFromCells(const Cells: TCellArray; W, H: Integer;
  const DedupeCap: Integer; const Weight: Integer);
const
  SIZES: array[0..2] of Integer = (3, 5, 10);
var
  x, y, si, S: Integer;
  grid: array of Byte;
  key: Integer;
  sig: TPatchSig;
  c: TCell;
  hasL, hasT: Boolean;
  leftAttr, topAttr: Byte;
  keepBG: Boolean;
  pal: array[0..15] of TRGB;
  i: Integer;
begin
  if (W <= 0) or (H <= 0) or (Length(Cells) <> W*H) then Exit;

  // Learn against VGA palette (style references are typically VGA/ANSI).
  for i := 0 to 15 do pal[i] := Palette16(pkVGA, i);

  for y := 0 to H-1 do
    for x := 0 to W-1 do
    begin
      c := Cells[y*W + x];
      hasL := x > 0;
      hasT := y > 0;
      if hasL then leftAttr := Cells[y*W + (x-1)].Attr else leftAttr := 0;
      if hasT then topAttr := Cells[(y-1)*W + x].Attr else topAttr := 0;
      keepBG := False;
      if hasL and (((leftAttr shr 4) and $0F) = CellBG(c)) then keepBG := True;
      if hasT and (((topAttr shr 4) and $0F) = CellBG(c)) then keepBG := True;

      for si := 0 to 2 do
      begin
        S := SIZES[si];
        SetLength(grid, S*S);
        ExtractNeighborhoodPal(Cells, W, H, x, y, S, grid, pal);
        key := TronicShadeKeyFromPalGrid(S, grid, pal);
        sig := PatchSigFromPalGrid(S, grid);
        if not DedupeAllow(key, sig, DedupeCap) then Continue;
        BumpCounts(key, c.Ch, CellFG(c), CellBG(c), keepBG, pal, Weight);
      end;
    end;
end;

function SmoothedProb(const Count, Total, K: Cardinal): Double; inline;
begin
  // Laplace smoothing
  Result := (Count + 1.0) / (Total + K);
end;

function LogP(const p: Double): Double; inline;
begin
  if p <= 1e-9 then Exit(Ln(1e-9));
  Result := Ln(p);
end;

function TronicShadeBonusForKey(const Key: Integer; const Ch, FG, BG: Byte; const KeepBG: Boolean; const Pal: array of TRGB): Double;
var
  gi: Integer;
  p: Double;
  pol: Integer;
begin
  Result := 0.0;
  gi := ClampI(GlyphClassIndex(Ch), 0, GLYPH_COUNT-1);
  p := SmoothedProb(GGlyph[Key][gi], GTotGlyph[Key], GLYPH_COUNT);
  Result += 1.0 * LogP(p);

  if (Ch = 176) or (Ch = 177) or (Ch = 178) or (Ch = 223) or (Ch = 220) or (Ch = 221) or (Ch = 222) then
  begin
    pol := TronicPolarityFromColors(FG and $0F, BG and $0F, Pal);
    p := SmoothedProb(GPol[Key][ClampI(pol,0,POL_COUNT-1)], GTotPol[Key], POL_COUNT);
    Result += 0.6 * LogP(p);
  end;

  if KeepBG then
    p := SmoothedProb(GKeepBG[Key][1], GTotKeepBG[Key], 2)
  else
    p := SmoothedProb(GKeepBG[Key][0], GTotKeepBG[Key], 2);
  Result += 0.5 * LogP(p);

  // FG/BG pair preference (learned from ANSI art)
  // Encourages stable two-color ramps where glyph choice (░▒▓▀▄▌▐) does the blending.
  if IsShadeGlyph(Ch) and (GTotPair[Key] > 0) then
  begin
    p := SmoothedProb(GPair[Key][FG and $0F][BG and $0F], GTotPair[Key], 256);
    Result += 0.35 * LogP(p);
  end;
end;

function TronicShadeBonus(const key3, key5, key10: Integer; const Ch, FG, BG: Byte;
  const LeftAttr, TopAttr: Byte; const HasLeft, HasTop: Boolean;
  const Pal: array of TRGB): Double;
var
  keepBG: Boolean;
  bg1: Byte;
begin
  if not GHasAny then Exit(0.0);
  bg1 := BG and $0F;
  keepBG := False;
  if HasLeft and (((LeftAttr shr 4) and $0F) = bg1) then keepBG := True;
  if HasTop and (((TopAttr shr 4) and $0F) = bg1) then keepBG := True;

  Result := 0.0;
  // scale weights: 3x3=1.0, 5x5=1.3, 10x10=0.7
  Result += 1.0 * TronicShadeBonusForKey(key3, Ch, FG, BG1, keepBG, Pal);
  Result += 1.3 * TronicShadeBonusForKey(key5, Ch, FG, BG1, keepBG, Pal);
  Result += 0.7 * TronicShadeBonusForKey(key10, Ch, FG, BG1, keepBG, Pal);

  // transition richness: if any key indicates transition, boost shade chars slightly
  if (Ch = 176) or (Ch = 177) or (Ch = 178) then
  begin
    // key encoding: trans bit is the 3rd from the end of KeyIndex packing; we can re-derive cheaply
    // but simplest: apply mild global bonus; transition detection already reflected in learned P.
    Result += 0.12;
  end;
end;


function ShadeIndex(const ch: Byte): Integer; inline;
begin
  case ch of
    176: Result := 0; // ░
    177: Result := 1; // ▒
    178: Result := 2; // ▓
    219: Result := 3; // █
  else
    Result := -1;
  end;
end;

function ShadeIndexEx(const ch: Byte; const IncludeBlocks: Boolean): Integer; inline;
begin
  case ch of
    176: Result := 0; // ░
    177: Result := 1; // ▒
    178: Result := 2; // ▓
    219: if IncludeBlocks then Result := 3 else Result := -1; // █ (optional)
  else
    Result := -1;
  end;
end;

function ShadeCharFromIndex(const idx: Integer): Byte; inline;
begin
  case idx of
    0: Result := 176; // ░
    1: Result := 177; // ▒
    2: Result := 178; // ▓
  else
    Result := 219; // █
  end;
end;

procedure TronicRetroStylizeCells(var Cells: TCellArray; W, H: Integer; Style: TTronicRetroStyle; Texture: Integer);
begin
  // Preserve prior behavior (included █) for existing callers.
  TronicRetroStylizeCellsEx(Cells, W, H, Style, Texture, True);
end;

procedure TronicRetroStylizeCellsPassEx(var Cells: TCellArray; W, H: Integer; Style: TTronicRetroStyle; Texture: Integer;
  const IncludeBlocks: Boolean; const Pass: TTronicRetroPass);
var
  x, y, i: Integer;
  idx, n: Integer;
  fg, bg: Integer;
  seed: Cardinal;
  tx, ty: Integer;
  x0, x1, xs: Integer;
  y0, y1, ys: Integer;
begin
  if (Style = trsNeutral) then Exit;
  if Texture <= 0 then Exit;
  if (W <= 0) or (H <= 0) then Exit;
  if Length(Cells) < W * H then Exit;

  Texture := ClampI(Texture, 0, 100);

  // Select a scan order that matches the named pass direction.
  case Pass of
    trpRightToLeft:
      begin x0 := W-1; x1 := 0; xs := -1; y0 := 0; y1 := H-1; ys := 1; end;
    trpBottomToTop:
      begin x0 := 0; x1 := W-1; xs := 1; y0 := H-1; y1 := 0; ys := -1; end;
  else // LeftToRight / TopToBottom
    begin x0 := 0; x1 := W-1; xs := 1; y0 := 0; y1 := H-1; ys := 1; end;
  end;

  y := y0;
  while True do
  begin
    x := x0;
    while True do
    begin
      i := y * W + x;
      idx := ShadeIndexEx(Cells[i].Ch, IncludeBlocks);
      if idx >= 0 then
      begin
        fg := Cells[i].Attr and $0F;
        bg := (Cells[i].Attr shr 4) and $0F;

        // Coordinate transform to vary the deterministic hash between passes.
        case Pass of
          trpRightToLeft: begin tx := (W-1) - x; ty := y; end;
          trpBottomToTop: begin tx := x; ty := (H-1) - y; end;
        else
          begin tx := x; ty := y; end;
        end;

        // Deterministic per-cell hash (no global RNG).
        seed := Cardinal(tx) * 73856093;
        seed := seed xor (Cardinal(ty) * 19349663);
        seed := seed xor (Cardinal(fg) * 83492791);
        seed := seed xor (Cardinal(bg) * 2654435761);
        seed := seed * 1664525 + 1013904223;

        // Chance gate based on Texture (0..100)
        n := Integer(seed mod 100);
        if n < Texture then
        begin
          case Style of
            trsGrainy:
              begin
                if (seed and 1) = 0 then Dec(idx) else Inc(idx);
              end;

            trsScanline:
              begin
                // Alternate rows push shade density up/down.
                if (ty and 1) = 0 then Dec(idx) else Inc(idx);
                // Extra grain at higher texture.
                if (Texture >= 60) and ((seed and 2) = 0) then
                  if (seed and 1) = 0 then Dec(idx) else Inc(idx);
              end;

            trsBlocky:
              begin
                // Bias toward fuller blocks as texture increases.
                if Texture >= 50 then Inc(idx);
                if (seed and 1) = 0 then Inc(idx);
              end;

            trsCgaCrunch:
              begin
                // High-contrast remap into extremes.
                if (seed and 1) = 0 then idx := 0 else idx := 3;
              end;
          else
            ;
          end;

          if idx < 0 then idx := 0;
          if idx > 3 then idx := 3;
          Cells[i].Ch := ShadeCharFromIndex(idx);
        end;
      end;

      if x = x1 then Break;
      x := x + xs;
    end;

    if y = y1 then Break;
    y := y + ys;
  end;
end;

procedure TronicRetroStylizeCellsEx(var Cells: TCellArray; W, H: Integer; Style: TTronicRetroStyle; Texture: Integer;
  const IncludeBlocks: Boolean);
begin
  // Default single-pass behavior (top-to-bottom).
  TronicRetroStylizeCellsPassEx(Cells, W, H, Style, Texture, IncludeBlocks, trpTopToBottom);
end;

initialization
  // no-op

finalization
  FreeDedupe;


end.
