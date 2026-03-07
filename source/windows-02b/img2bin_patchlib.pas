unit img2bin_patchlib;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  img2bin_types, img2bin_palette, img2bin_dosfont;

type
  TPatchApplyMode = (pamFull, pamGlyphOnly);

  // A learned style patch in cell-space.
  TPatch = packed record
    Size: Byte; // 10,5,3
    Sig: array[0..15] of Byte; // 4x4 luma signature (0..255)
    Cells: array of TCell; // Size*Size, row-major
  end;

  TPatchArray = array of TPatch;

procedure PatchLibClear;
procedure PatchLibLearnFromCells(const Cells: TCellArray; W, H: Integer; const MaxPatchesPerSize: Integer = 6000);
function PatchLibHasAny: Boolean;

function PatchLibSaveToFile(const FN: string): Boolean;
function PatchLibLoadFromFile(const FN: string): Boolean;

// Keep only block/shade glyphs in the patchbook (space, ░▒▓█).
// This is useful when you want PatchStyle to act as a ramp/shading guide only,
// without importing punctuation/texture glyphs from the style reference.
procedure PatchLibFilterBlocksOnly;

// Apply multi-scale patches onto an existing screen of cells.
// Cells must be width W and height H.
// Patch sizes enabled via Use10/Use5/Use3; Loops repeats the 10->5->3 cycle.
procedure PatchStyleApply(var Cells: TCellArray; W, H: Integer;
  Use10, Use5, Use3: Boolean; Loops: Integer; MinMatchPct: Integer;
  ApplyMode: TPatchApplyMode);

implementation

var
  GPatches10: TPatchArray = nil;
  GPatches5: TPatchArray = nil;
  GPatches3: TPatchArray = nil;

function ClampI(v, lo, hi: Integer): Integer; inline;
begin
  if v < lo then Exit(lo);
  if v > hi then Exit(hi);
  Result := v;
end;

function RGBLuma(const c: TRGB): Integer; inline;
begin
  // 0..255 approx.
  Result := (c.R * 77 + c.G * 150 + c.B * 29) shr 8;
end;

function CellFG(const C: TCell): Byte; inline;
begin
  Result := C.Attr and $0F;
end;

function CellBG(const C: TCell): Byte; inline;
begin
  Result := (C.Attr shr 4) and $0F;
end;

function GlyphOnCount(ch: Byte): Integer; inline;
var
  y: Integer;
  row: Byte;
begin
  Result := 0;
  for y := 0 to 15 do
  begin
    row := DOSFontModernDOS8x16[ch, y];
    // count bits (8 bits)
    Result += ((row shr 0) and 1) + ((row shr 1) and 1) + ((row shr 2) and 1) + ((row shr 3) and 1) +
              ((row shr 4) and 1) + ((row shr 5) and 1) + ((row shr 6) and 1) + ((row shr 7) and 1);
  end;
end;

function CellApproxLuma(const C: TCell; PalKind: TPaletteKind): Integer; inline;
var
  fg, bg: TRGB;
  fgL, bgL: Integer;
  onCnt: Integer;
begin
  fg := Palette16(PalKind, CellFG(C));
  bg := Palette16(PalKind, CellBG(C));
  fgL := RGBLuma(fg);
  bgL := RGBLuma(bg);
  onCnt := GlyphOnCount(C.Ch); // 0..128
  Result := (fgL * onCnt + bgL * (128 - onCnt)) div 128;
end;

procedure PatchSigFromCells(const Cells: TCellArray; W, H: Integer; x0, y0, size: Integer; out Sig: array of Byte);
var
  bx, by, i, x, y: Integer;
  sum, cnt: Integer;
  cx0, cy0, cx1, cy1: Integer;
  palKind: TPaletteKind;
begin
  palKind := pkVGA;
  i := 0;
  for by := 0 to 3 do
    for bx := 0 to 3 do
    begin
      cx0 := x0 + (bx * size) div 4;
      cx1 := x0 + ((bx + 1) * size) div 4 - 1;
      cy0 := y0 + (by * size) div 4;
      cy1 := y0 + ((by + 1) * size) div 4 - 1;
      cx0 := ClampI(cx0, 0, W-1);
      cx1 := ClampI(cx1, 0, W-1);
      cy0 := ClampI(cy0, 0, H-1);
      cy1 := ClampI(cy1, 0, H-1);

      sum := 0;
      cnt := 0;
      for y := cy0 to cy1 do
        for x := cx0 to cx1 do
        begin
          sum += CellApproxLuma(Cells[y * W + x], palKind);
          Inc(cnt);
        end;

      if cnt = 0 then Sig[i] := 0
      else Sig[i] := Byte(ClampI(sum div cnt, 0, 255));
      Inc(i);
    end;
end;

function SigDist(const A, B: array of Byte): Integer; inline;
var
  i, d: Integer;
begin
  Result := 0;
  for i := 0 to 15 do
  begin
    d := Integer(A[i]) - Integer(B[i]);
    if d < 0 then d := -d;
    Result += d;
  end;
end;

function DistToPct(dist: Integer): Integer; inline;
var
  maxd: Integer;
begin
  maxd := 255 * 16;
  Result := 100 - (dist * 100) div maxd;
  if Result < 0 then Result := 0;
  if Result > 100 then Result := 100;
end;

procedure PatchLibClear;
begin
  SetLength(GPatches10, 0);
  SetLength(GPatches5, 0);
  SetLength(GPatches3, 0);
end;

function PatchLibHasAny: Boolean;
begin
  Result := (Length(GPatches10) > 0) or (Length(GPatches5) > 0) or (Length(GPatches3) > 0);
end;

function IsBlockShadeChar(ch: Byte): Boolean; inline;
begin
  // CP437: ░=176, ▒=177, ▓=178, █=219
  Result := (ch = 32) or (ch = 176) or (ch = 177) or (ch = 178) or (ch = 219);
end;

procedure FilterArrBlocksOnly(var Arr: TPatchArray);
var
  outArr: TPatchArray;
  i, j, outN: Integer;
  ok: Boolean;
begin
  outN := 0;
  SetLength(outArr, Length(Arr));
  for i := 0 to High(Arr) do
  begin
    ok := True;
    for j := 0 to High(Arr[i].Cells) do
      if not IsBlockShadeChar(Arr[i].Cells[j].Ch) then
      begin
        ok := False;
        Break;
      end;
    if ok then
    begin
      outArr[outN] := Arr[i];
      Inc(outN);
    end;
  end;
  SetLength(outArr, outN);
  Arr := outArr;
end;

procedure PatchLibFilterBlocksOnly;
begin
  FilterArrBlocksOnly(GPatches10);
  FilterArrBlocksOnly(GPatches5);
  FilterArrBlocksOnly(GPatches3);
end;

procedure LearnSize(var Arr: TPatchArray; const Cells: TCellArray; W, H, size, MaxP: Integer);
var
  x, y, stride, i, idx: Integer;
  p: TPatch;
  sig: array[0..15] of Byte;
begin
  stride := size div 2;
  if stride < 1 then stride := 1;

  y := 0;
  while y + size <= H do
  begin
    x := 0;
    while x + size <= W do
    begin
      if Length(Arr) >= MaxP then Exit;

      PatchSigFromCells(Cells, W, H, x, y, size, sig);

      p.Size := Byte(size);
      for i := 0 to 15 do p.Sig[i] := sig[i];

      SetLength(p.Cells, size * size);
      for idx := 0 to size * size - 1 do
        p.Cells[idx] := Cells[(y + (idx div size)) * W + (x + (idx mod size))];

      SetLength(Arr, Length(Arr) + 1);
      Arr[High(Arr)] := p;

      Inc(x, stride);
    end;
    Inc(y, stride);
  end;
end;

procedure PatchLibLearnFromCells(const Cells: TCellArray; W, H: Integer; const MaxPatchesPerSize: Integer);
begin
  if (W <= 0) or (H <= 0) then Exit;
  if Length(Cells) < W * H then Exit;

  LearnSize(GPatches10, Cells, W, H, 10, MaxPatchesPerSize);
  LearnSize(GPatches5, Cells, W, H, 5, MaxPatchesPerSize);
  LearnSize(GPatches3, Cells, W, H, 3, MaxPatchesPerSize);
end;

function PatchLibSaveToFile(const FN: string): Boolean;
var
  fs: TFileStream;

  procedure WriteArr(const A: TPatchArray);
  var
    n, i, j: Integer;
    sz: Byte;
    cellCount: Integer;
  begin
    n := Length(A);
    fs.WriteBuffer(n, SizeOf(n));
    for i := 0 to n - 1 do
    begin
      sz := A[i].Size;
      fs.WriteBuffer(sz, SizeOf(sz));
      fs.WriteBuffer(A[i].Sig[0], 16);
      cellCount := Length(A[i].Cells);
      fs.WriteBuffer(cellCount, SizeOf(cellCount));
      for j := 0 to cellCount - 1 do
        fs.WriteBuffer(A[i].Cells[j], SizeOf(TCell));
    end;
  end;

var
  magic: array[0..3] of AnsiChar;
  ver: Integer;
begin
  Result := False;
  try
    fs := TFileStream.Create(FN, fmCreate);
    try
      magic[0] := 'P'; magic[1] := 'C'; magic[2] := 'H'; magic[3] := '1';
      fs.WriteBuffer(magic, 4);
      ver := 1;
      fs.WriteBuffer(ver, SizeOf(ver));
      WriteArr(GPatches10);
      WriteArr(GPatches5);
      WriteArr(GPatches3);
      Result := True;
    finally
      fs.Free;
    end;
  except
    Result := False;
  end;
end;

function PatchLibLoadFromFile(const FN: string): Boolean;
var
  fs: TFileStream;

  function ReadArr: TPatchArray;
  var
    n, i, j: Integer;
    sz: Byte;
    cellCount: Integer;
    p: TPatch;
  begin
    Result := nil;
    fs.ReadBuffer(n, SizeOf(n));
    if n < 0 then n := 0;
    SetLength(Result, n);
    for i := 0 to n - 1 do
    begin
      fs.ReadBuffer(sz, SizeOf(sz));
      p.Size := sz;
      fs.ReadBuffer(p.Sig[0], 16);
      fs.ReadBuffer(cellCount, SizeOf(cellCount));
      if cellCount < 0 then cellCount := 0;
      SetLength(p.Cells, cellCount);
      for j := 0 to cellCount - 1 do
        fs.ReadBuffer(p.Cells[j], SizeOf(TCell));
      Result[i] := p;
    end;
  end;

var
  magic: array[0..3] of AnsiChar;
  ver: Integer;
begin
  Result := False;
  try
    fs := TFileStream.Create(FN, fmOpenRead or fmShareDenyWrite);
    try
      fs.ReadBuffer(magic, 4);
      if (magic[0] <> 'P') or (magic[1] <> 'C') or (magic[2] <> 'H') then Exit(False);
      fs.ReadBuffer(ver, SizeOf(ver));
      PatchLibClear;
      GPatches10 := ReadArr;
      GPatches5 := ReadArr;
      GPatches3 := ReadArr;
      Result := True;
    finally
      fs.Free;
    end;
  except
    Result := False;
  end;
end;

procedure PickBestPatch(const Arr: TPatchArray; const wantSig: array of Byte; out bestIdx: Integer; out bestPct: Integer);
var
  i, d, bestD: Integer;
begin
  bestIdx := -1;
  bestPct := 0;
  bestD := MaxInt;
  for i := 0 to High(Arr) do
  begin
    d := SigDist(wantSig, Arr[i].Sig);
    if d < bestD then
    begin
      bestD := d;
      bestIdx := i;
    end;
  end;
  if bestIdx >= 0 then
    bestPct := DistToPct(bestD);
end;

procedure ApplyPatchAt(var Cells: TCellArray; W, H, x0, y0: Integer; const P: TPatch; ApplyMode: TPatchApplyMode);
var
  px, py, idx, dstIdx: Integer;
  srcCell: TCell;
begin
  for py := 0 to P.Size - 1 do
    for px := 0 to P.Size - 1 do
    begin
      if (x0 + px < 0) or (x0 + px >= W) or (y0 + py < 0) or (y0 + py >= H) then Continue;
      idx := py * P.Size + px;
      dstIdx := (y0 + py) * W + (x0 + px);
      srcCell := P.Cells[idx];
      if ApplyMode = pamGlyphOnly then
        Cells[dstIdx].Ch := srcCell.Ch
      else
        Cells[dstIdx] := srcCell;
    end;
end;

procedure PatchStyleApply(var Cells: TCellArray; W, H: Integer;
  Use10, Use5, Use3: Boolean; Loops: Integer; MinMatchPct: Integer;
  ApplyMode: TPatchApplyMode);
const
  SIZES: array[0..2] of Integer = (10, 5, 3);
var
  loop, si, size, x, y: Integer;
  sig: array[0..15] of Byte;
  bestIdx, bestPct: Integer;
  arr: TPatchArray;
  stride: Integer;
begin
  if not PatchLibHasAny then Exit;
  if (W <= 0) or (H <= 0) then Exit;
  if Length(Cells) < W * H then Exit;

  Loops := ClampI(Loops, 1, 8);
  MinMatchPct := ClampI(MinMatchPct, 0, 100);

  for loop := 1 to Loops do
  begin
    for si := 0 to 2 do
    begin
      size := SIZES[si];
      if (size = 10) and (not Use10) then Continue;
      if (size = 5) and (not Use5) then Continue;
      if (size = 3) and (not Use3) then Continue;

      if size = 10 then arr := GPatches10 else
      if size = 5 then arr := GPatches5 else
        arr := GPatches3;

      if Length(arr) = 0 then Continue;

      // non-overlapping block placement (stable + fast)
      stride := size;

      y := 0;
      while (y + size) <= H do
      begin
        x := 0;
        while (x + size) <= W do
        begin
          PatchSigFromCells(Cells, W, H, x, y, size, sig);
          PickBestPatch(arr, sig, bestIdx, bestPct);
          if (bestIdx >= 0) and (bestPct >= MinMatchPct) then
            ApplyPatchAt(Cells, W, H, x, y, arr[bestIdx], ApplyMode);
          Inc(x, stride);
        end;
        Inc(y, stride);
      end;
    end;
  end;
end;

end.
