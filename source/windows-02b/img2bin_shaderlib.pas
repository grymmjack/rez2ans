unit img2bin_shaderlib;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson, jsonparser,
  img2bin_types, img2bin_patchlib,
  img2bin_tronicshade;

type
  TColorPair = packed record
    FG: Byte;
    BG: Byte;
  end;

  TColorPairArray = array of TColorPair;

  // Swatch-based shader library.
  // A "swatch" is a small 3x3 training block imported from BIN/ANSI.
  // Swatches are capped (default 2000 per profile). Newer swatches overwrite older ones.
  TSwatch = packed record
    FG: Byte;
    BG: Byte;
    GlyphBits: array[0..31] of Byte; // 256-bit bitset: which glyphs appeared in the 3x3 block
    Sig: QWord;                      // signature of GlyphBits for fast matching
    Stamp: Int64;                    // recency counter (monotonic)
  end;

  TSwatchArray = array of TSwatch;

  // Derived lookup tables for fast conversion (keeps existing converter API).
  TShaderLibrary = record
    Loaded: Boolean;
    FileName: string;
    MaxRowsRead: Integer;
    RowsInFile: Integer;

    // Swatches (training examples)
    MaxSwatches: Integer;
    StampCounter: Int64;
    Swatches: TSwatchArray;

    // Derived: for each glyph byte, a list of FG/BG pairs that appeared recently with that glyph.
    PairsByGlyph: array[0..255] of TColorPairArray;
    // Derived: all unique pairs found.
    AllPairs: TColorPairArray;

    UniquePairs: Integer;
    UniqueGlyphPairs: Integer;
  end;

  TShaderParams = record
    // Heuristic weights inspired by common ANSI shading practices.
    // 0.0 disables the feature; 1.0 is a strong bias.
    BlockStrength: Double;   // prefer keeping BG close to a "base" color (block-in pass)
    EdgeKeep: Double;        // prefer solid glyph coverage on high-contrast cells (keep outlines crisp)
    VerticalSmear: Double;   // encourage FG/BG continuity vertically (classic "chain" feel)
  end;

  TShaderProfile = record
    Name: string;
    Lib: TShaderLibrary;
    Params: TShaderParams;
  end;

procedure ShaderClear;            // clears ACTIVE profile
procedure ShaderClearAll;         // clears ALL profiles (in-memory)
function ShaderIsLoaded: Boolean; // ACTIVE profile has any data
function ShaderSummary: string;

procedure ShaderFillProfileNames(AItems: TStrings);
procedure ShaderSetActiveProfile(const Name: string);
function ShaderActiveProfileName: string;

procedure ShaderGetActiveParams(out P: TShaderParams);

// Save / reload helpers for UI buttons.
// These operate on the ACTIVE profile (ShaderActiveProfileName).
procedure ShaderSaveActiveProfile;
procedure ShaderReloadActiveProfile;

// Import a BIN and MERGE it into the active profile; when Append=False it resets active first.
// After import, the profile is automatically saved to disk as JSON (next to the exe).
function ShaderImportBINToActive(const FN: string; const MaxRows: Integer = 500; const Append: Boolean = True;
  const LearnShadeOnly: Boolean = True): Boolean;

// Import ANSI text (.ANS/.ANSI) and merge its final screen cells into the active shader profile.
// Supports basic ANSI SGR colors + cursor movement. Intended for ANSI art exported from editors (TheDraw, etc.).
function ShaderImportANSIToActive(const FN: string; const MaxRows: Integer = 500; const Append: Boolean = True;
  const TreatBlinkAsBrightBG: Boolean = True; const LearnShadeOnly: Boolean = True): Boolean;

// Returns a *reference* to internal arrays (do NOT modify).
procedure ShaderGetPairsForGlyph(ch: Byte; out Pairs: TColorPairArray);
procedure ShaderGetAllPairs(out Pairs: TColorPairArray);

implementation

// Forward declarations
function ShaderDir: string; forward;
procedure LibClear(var Lib: TShaderLibrary); forward;




type
  PShaderLibrary = ^TShaderLibrary;

const
  BIN_COLS = 80;

  PROFILE_COUNT = 4;
  DEFAULT_PROFILE_NAMES: array[0..PROFILE_COUNT-1] of string =
    ('realstyle', 'toon', 'death', 'ascii');

  DEFAULT_PROFILE_PARAMS: array[0..PROFILE_COUNT-1] of TShaderParams = (
    // realstyle: light bias toward base BG + crisp edges, but allow gradients
    (BlockStrength: 0.35; EdgeKeep: 0.55; VerticalSmear: 0.20),
    // toon: strong base colors + very crisp edges (less noisy shading)
    (BlockStrength: 0.75; EdgeKeep: 0.90; VerticalSmear: 0.10),
    // death: allow more vertical "chain" style and rougher shading
    (BlockStrength: 0.45; EdgeKeep: 0.40; VerticalSmear: 0.55),
    // ascii: keep edges readable; moderate base color bias
    (BlockStrength: 0.55; EdgeKeep: 0.80; VerticalSmear: 0.20)
  );

  // Training block size (requested rewrite): 3x3
  BLOCK_W = 3;
  BLOCK_H = 3;
  DEFAULT_MAX_SWATCHES = 2500;

var
  GProfiles: array of TShaderProfile;
  GActive: Integer = 0;

procedure AddProfile(const AName: string; const AParams: TShaderParams);
var
  n: Integer;
begin
  n := Length(GProfiles);
  SetLength(GProfiles, n + 1);
  GProfiles[n].Name := LowerCase(Trim(AName));
  LibClear(GProfiles[n].Lib);
  GProfiles[n].Params := AParams;
end;

procedure ScanProfilesFromDisk;
var
  sr: TSearchRec;
  base, nm: string;
  i: Integer;
begin
  base := ShaderDir;
  if FindFirst(base + '*.json', faAnyFile, sr) = 0 then
  try
    repeat
      if (sr.Attr and faDirectory) <> 0 then Continue;
      nm := ChangeFileExt(sr.Name, '');
      // ignore empty names
      if Trim(nm) = '' then Continue;
      // already exists?
      for i := 0 to High(GProfiles) do
        if LowerCase(GProfiles[i].Name) = LowerCase(nm) then
        begin
          nm := '';
          Break;
        end;
      if nm <> '' then
        AddProfile(nm, DEFAULT_PROFILE_PARAMS[0]);
    until FindNext(sr) <> 0;
  finally
    FindClose(sr);
  end;
end;

function ShouldLearnGlyph(const ProfileName: string; const Ch: Byte; const LearnShadeOnly: Boolean): Boolean;
const
  // A conservative ASCII "ramp" set often used for shading.
  ASCII_RAMP: AnsiString = ' .,:;''"`-_=+*/\\|^~#%@$&()[]{}<>!?';
begin
  if not LearnShadeOnly then Exit(Ch >= 32);

  // Always allow space.
  if Ch = 32 then Exit(True);

  // Block / shade / half-block characters (CP437) commonly used for ANSI shading.
  case Ch of
    176, 177, 178, 219, 220, 223:
      Exit(LowerCase(ProfileName) <> 'ascii');
  end;

  // ASCII ramp chars.
  if (Ch >= 32) and (Ch <= 126) then
    Exit(Pos(AnsiChar(Ch), ASCII_RAMP) > 0);

  // Otherwise, ignore (prevents text/box UI characters from polluting the shader library).
  Result := False;
end;

// --- small helpers ----------------------------------------------------------

function PairExists(const arr: TColorPairArray; fg, bg: Byte): Boolean;
var
  i: Integer;
begin
  for i := 0 to High(arr) do
    if (arr[i].FG = fg) and (arr[i].BG = bg) then Exit(True);
  Exit(False);
end;

function AddUniquePair(var arr: TColorPairArray; fg, bg: Byte): Boolean;
var
  n: Integer;
begin
  if PairExists(arr, fg, bg) then Exit(False);
  n := Length(arr);
  SetLength(arr, n + 1);
  arr[n].FG := fg;
  arr[n].BG := bg;
  Exit(True);
end;

procedure ClearBits(var Bits: array of Byte);
var
  i: Integer;
begin
  for i := Low(Bits) to High(Bits) do Bits[i] := 0;
end;

procedure SetBit(var Bits: array of Byte; const Idx: Integer);
var
  b, m: Integer;
begin
  if (Idx < 0) or (Idx > 255) then Exit;
  b := Idx shr 3;
  m := 1 shl (Idx and 7);
  Bits[b] := Bits[b] or Byte(m);
end;

function TestBit(const Bits: array of Byte; const Idx: Integer): Boolean;
var
  b, m: Integer;
begin
  if (Idx < 0) or (Idx > 255) then Exit(False);
  b := Idx shr 3;
  m := 1 shl (Idx and 7);
  Result := (Bits[b] and Byte(m)) <> 0;
end;

function BitsEqual(const A, B: array of Byte): Boolean;
var
  i: Integer;
begin
  for i := 0 to 31 do
    if A[i] <> B[i] then Exit(False);
  Result := True;
end;

function SigFNV1a64(const Bits: array of Byte): QWord;
var
  i: Integer;
  h: QWord;
begin
  h := QWord($CBF29CE484222325);
  for i := 0 to 31 do
  begin
    h := h xor Bits[i];
    h := h * QWord($100000001B3);
  end;
  Result := h;
end;

function HexNibble(const c: Char): Integer;
begin
  case c of
    '0'..'9': Result := Ord(c) - Ord('0');
    'a'..'f': Result := Ord(c) - Ord('a') + 10;
    'A'..'F': Result := Ord(c) - Ord('A') + 10;
  else
    Result := -1;
  end;
end;

function BytesToHex(const Bits: array of Byte): string;
const
  D: PChar = '0123456789ABCDEF';
var
  i: Integer;
begin
  SetLength(Result, Length(Bits) * 2);
  for i := 0 to High(Bits) do
  begin
    Result[i*2 + 1] := D[(Bits[i] shr 4) and $0F];
    Result[i*2 + 2] := D[Bits[i] and $0F];
  end;
end;

function HexToBits(const S: string; out Bits: array of Byte): Boolean;
var
  i, hi, lo: Integer;
begin
  Result := False;
  if Length(S) < 64 then Exit(False);
  for i := 0 to 31 do
  begin
    hi := HexNibble(S[i*2 + 1]);
    lo := HexNibble(S[i*2 + 2]);
    if (hi < 0) or (lo < 0) then Exit(False);
    Bits[i] := Byte((hi shl 4) or lo);
  end;
  Result := True;
end;

// --- library core -----------------------------------------------------------

procedure LibClear(var Lib: TShaderLibrary);
var
  i: Integer;
begin
  Lib.Loaded := False;
  Lib.FileName := '';
  Lib.MaxRowsRead := 0;
  Lib.RowsInFile := 0;

  Lib.MaxSwatches := DEFAULT_MAX_SWATCHES;
  Lib.StampCounter := 0;
  SetLength(Lib.Swatches, 0);

  for i := 0 to 255 do
    SetLength(Lib.PairsByGlyph[i], 0);
  SetLength(Lib.AllPairs, 0);
  Lib.UniquePairs := 0;
  Lib.UniqueGlyphPairs := 0;
end;

function ShaderDir: string;
begin
  // Cross-platform folder for named shader / TronicShade style profiles.
  {$IFDEF Windows}
  // Portable: keep styles next to the executable on Windows.
  Result := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + 'styles' + PathDelim;
  {$ELSE}
  // Use per-user config dir on Unix-like systems to avoid permission issues when installed system-wide.
  Result := IncludeTrailingPathDelimiter(GetAppConfigDir(False)) + 'styles' + PathDelim;
  {$ENDIF}

  // Ensure the directory exists. If creation fails, fall back to a temp folder.
  if not ForceDirectories(Result) then
  begin
    Result := IncludeTrailingPathDelimiter(GetTempDir) + 'img2bin' + PathDelim + 'styles' + PathDelim;
    ForceDirectories(Result);
  end;
end;


function ProfileFileName(const ProfileName: string): string;
begin
  Result := ShaderDir + LowerCase(Trim(ProfileName)) + '.json';
end;

function ActiveLibPtr: PShaderLibrary;
begin
  if (GActive < 0) or (GActive >= Length(GProfiles)) then
    Exit(nil);
  Result := @GProfiles[GActive].Lib;
end;

function FindSwatchIndex(const Lib: TShaderLibrary; const FG, BG: Byte; const Sig: QWord;
  const Bits: array of Byte): Integer;
var
  i: Integer;
begin
  for i := 0 to High(Lib.Swatches) do
  begin
    if (Lib.Swatches[i].FG = FG) and (Lib.Swatches[i].BG = BG) and (Lib.Swatches[i].Sig = Sig) then
    begin
      if BitsEqual(Lib.Swatches[i].GlyphBits, Bits) then
        Exit(i);
    end;
  end;
  Exit(-1);
end;

function FindOldestIndex(const Lib: TShaderLibrary): Integer;
var
  i: Integer;
  bestStamp: Int64;
begin
  if Length(Lib.Swatches) = 0 then Exit(-1);
  Result := 0;
  bestStamp := Lib.Swatches[0].Stamp;
  for i := 1 to High(Lib.Swatches) do
    if Lib.Swatches[i].Stamp < bestStamp then
    begin
      bestStamp := Lib.Swatches[i].Stamp;
      Result := i;
    end;
end;

procedure AddOrReplaceSwatch(var Lib: TShaderLibrary; const FG, BG: Byte; const Bits: array of Byte);
var
  sig: QWord;
  idx: Integer;
  s: TSwatch;
begin
  sig := SigFNV1a64(Bits);
  idx := FindSwatchIndex(Lib, FG, BG, sig, Bits);

  Inc(Lib.StampCounter);

  if idx >= 0 then
  begin
    Lib.Swatches[idx].Stamp := Lib.StampCounter;
    // keep newest bits (same key)
    Move(Bits[0], Lib.Swatches[idx].GlyphBits[0], 32);
    Exit;
  end;

  s.FG := FG;
  s.BG := BG;
  Move(Bits[0], s.GlyphBits[0], 32);
  s.Sig := sig;
  s.Stamp := Lib.StampCounter;

  if Length(Lib.Swatches) < Lib.MaxSwatches then
  begin
    SetLength(Lib.Swatches, Length(Lib.Swatches) + 1);
    Lib.Swatches[High(Lib.Swatches)] := s;
  end
  else
  begin
    idx := FindOldestIndex(Lib);
    if idx < 0 then Exit;
    Lib.Swatches[idx] := s;
  end;
end;

procedure SortIndicesByStampDesc(const Lib: TShaderLibrary; var Idx: array of Integer);

  procedure QuickSort(L, R: Integer);
  var
    i, j, p, t: Integer;
    pivot: Int64;
  begin
    i := L;
    j := R;
    p := Idx[(L + R) div 2];
    pivot := Lib.Swatches[p].Stamp;

    repeat
      while Lib.Swatches[Idx[i]].Stamp > pivot do Inc(i);
      while Lib.Swatches[Idx[j]].Stamp < pivot do Dec(j);

      if i <= j then
      begin
        t := Idx[i]; Idx[i] := Idx[j]; Idx[j] := t;
        Inc(i); Dec(j);
      end;
    until i > j;

    if L < j then QuickSort(L, j);
    if i < R then QuickSort(i, R);
  end;

begin
  if Length(Idx) <= 1 then Exit;
  QuickSort(0, High(Idx));
end;

procedure RebuildDerivedPairs(var Lib: TShaderLibrary);
var
  i, g: Integer;
  idxs: array of Integer;
  s: TSwatch;
begin
  for g := 0 to 255 do
    SetLength(Lib.PairsByGlyph[g], 0);
  SetLength(Lib.AllPairs, 0);

  if Length(Lib.Swatches) = 0 then
  begin
    Lib.UniquePairs := 0;
    Lib.UniqueGlyphPairs := 0;
    Lib.Loaded := False;
    Exit;
  end;

  SetLength(idxs, Length(Lib.Swatches));
  for i := 0 to High(idxs) do idxs[i] := i;
  SortIndicesByStampDesc(Lib, idxs);

  // Add pairs in recency order (newest first)
  for i := 0 to High(idxs) do
  begin
    s := Lib.Swatches[idxs[i]];
    AddUniquePair(Lib.AllPairs, s.FG, s.BG);

    for g := 0 to 255 do
      if TestBit(s.GlyphBits, g) then
        AddUniquePair(Lib.PairsByGlyph[g], s.FG, s.BG);
  end;

  Lib.UniquePairs := Length(Lib.AllPairs);
  Lib.UniqueGlyphPairs := 0;
  for g := 0 to 255 do
    Inc(Lib.UniqueGlyphPairs, Length(Lib.PairsByGlyph[g]));

  Lib.Loaded := (Lib.UniquePairs > 0) or (Lib.UniqueGlyphPairs > 0);
end;

procedure SaveProfileToDisk(const ProfileIdx: Integer);
var
  fn: string;
  root: TJSONObject;
  paramsObj: TJSONObject;
  swArr: TJSONArray;
  swObj: TJSONObject;
  i: Integer;
  sl: TStringList;
  lib: ^TShaderLibrary;
begin
  if (ProfileIdx < 0) or (ProfileIdx >= Length(GProfiles)) then Exit;
  fn := ProfileFileName(GProfiles[ProfileIdx].Name);

  lib := @GProfiles[ProfileIdx].Lib;

  root := TJSONObject.Create;
  try
    root.Add('version', 2);
    root.Add('profile', GProfiles[ProfileIdx].Name);
    root.Add('blockW', BLOCK_W);
    root.Add('blockH', BLOCK_H);
    root.Add('maxSwatches', lib^.MaxSwatches);

    paramsObj := TJSONObject.Create;
    paramsObj.Add('blockStrength', GProfiles[ProfileIdx].Params.BlockStrength);
    paramsObj.Add('edgeKeep', GProfiles[ProfileIdx].Params.EdgeKeep);
    paramsObj.Add('verticalSmear', GProfiles[ProfileIdx].Params.VerticalSmear);
    root.Add('params', paramsObj);

    swArr := TJSONArray.Create;
    for i := 0 to High(lib^.Swatches) do
    begin
      swObj := TJSONObject.Create;
      swObj.Add('fg', Integer(lib^.Swatches[i].FG));
      swObj.Add('bg', Integer(lib^.Swatches[i].BG));
      swObj.Add('bits', BytesToHex(lib^.Swatches[i].GlyphBits));
      swObj.Add('stamp', lib^.Swatches[i].Stamp);
      swArr.Add(swObj);
    end;
    root.Add('swatches', swArr);

    // Saving next to the executable can fail (permissions, read-only media, etc.).
    // Never crash the GUI on save; best-effort only.
    sl := TStringList.Create;
    try
      sl.Text := root.FormatJSON([], 2);
      try
        sl.SaveToFile(fn);
      except
        // ignore write failures; profile remains in memory
      end;
    finally
      sl.Free;
    end;
  finally
    root.Free;
  end;
end;

function LoadProfileFromDisk(const ProfileIdx: Integer): Boolean;
var
  fn: string;
  sl: TStringList;
  json: TJSONData;
  root: TJSONObject;
  paramsObj: TJSONObject;
  swArr: TJSONArray;
  i, fg, bg: Integer;
  stamp: Int64;
  bitsHex: string;
  bits: array[0..31] of Byte;
  lib: ^TShaderLibrary;
  tmp: array of TSwatch;
  idxs: array of Integer;
  keepN: Integer;

  procedure SortTmpByStampDesc;
    procedure QS(L, R: Integer);
    var
      ii, jj, p, t: Integer;
      pivot: Int64;
    begin
      ii := L; jj := R;
      p := idxs[(L + R) div 2];
      pivot := tmp[p].Stamp;
      repeat
        while tmp[idxs[ii]].Stamp > pivot do Inc(ii);
        while tmp[idxs[jj]].Stamp < pivot do Dec(jj);
        if ii <= jj then
        begin
          t := idxs[ii]; idxs[ii] := idxs[jj]; idxs[jj] := t;
          Inc(ii); Dec(jj);
        end;
      until ii > jj;
      if L < jj then QS(L, jj);
      if ii < R then QS(ii, R);
    end;
  begin
    if Length(idxs) <= 1 then Exit;
    QS(0, High(idxs));
  end;

begin
  Result := False;
  if (ProfileIdx < 0) or (ProfileIdx >= Length(GProfiles)) then Exit;

  fn := ProfileFileName(GProfiles[ProfileIdx].Name);
  if not FileExists(fn) then Exit(False);

  lib := @GProfiles[ProfileIdx].Lib;
  LibClear(lib^);
  lib^.FileName := fn;

  sl := TStringList.Create;
  try
    sl.LoadFromFile(fn);
    json := GetJSON(sl.Text);
    try
      if (json = nil) or not (json is TJSONObject) then Exit(False);
      root := TJSONObject(json);

      // Params
      paramsObj := root.FindPath('params') as TJSONObject;
      if paramsObj <> nil then
      begin
        if paramsObj.Find('blockStrength') <> nil then
          GProfiles[ProfileIdx].Params.BlockStrength := paramsObj.Get('blockStrength', GProfiles[ProfileIdx].Params.BlockStrength);
        if paramsObj.Find('edgeKeep') <> nil then
          GProfiles[ProfileIdx].Params.EdgeKeep := paramsObj.Get('edgeKeep', GProfiles[ProfileIdx].Params.EdgeKeep);
        if paramsObj.Find('verticalSmear') <> nil then
          GProfiles[ProfileIdx].Params.VerticalSmear := paramsObj.Get('verticalSmear', GProfiles[ProfileIdx].Params.VerticalSmear);
      end;

      if root.Find('maxSwatches') <> nil then
        lib^.MaxSwatches := root.Get('maxSwatches', DEFAULT_MAX_SWATCHES)
      else
        lib^.MaxSwatches := DEFAULT_MAX_SWATCHES;

      swArr := root.FindPath('swatches') as TJSONArray;
      if swArr = nil then Exit(False);

      SetLength(tmp, swArr.Count);
      for i := 0 to swArr.Count - 1 do
      begin
        fg := (swArr.Objects[i]).Get('fg', 7);
        bg := (swArr.Objects[i]).Get('bg', 0);
        bitsHex := (swArr.Objects[i]).Get('bits', '');
        stamp := (swArr.Objects[i]).Get('stamp', Int64(0));

        if (fg < 0) or (fg > 15) or (bg < 0) or (bg > 15) then Continue;
        ClearBits(bits);
        if (bitsHex <> '') and (not HexToBits(bitsHex, bits)) then Continue;

        tmp[i].FG := Byte(fg);
        tmp[i].BG := Byte(bg);
        Move(bits[0], tmp[i].GlyphBits[0], 32);
        tmp[i].Sig := SigFNV1a64(tmp[i].GlyphBits);
        tmp[i].Stamp := stamp;
      end;

      // Keep newest MaxSwatches if file has more.
      SetLength(idxs, Length(tmp));
      for i := 0 to High(idxs) do idxs[i] := i;
      SortTmpByStampDesc;

      keepN := Length(tmp);
      if keepN > lib^.MaxSwatches then keepN := lib^.MaxSwatches;

      SetLength(lib^.Swatches, 0);
      lib^.StampCounter := 0;
      for i := 0 to keepN - 1 do
      begin
        // skip uninitialized (stamp=0 and bits empty) records
        if (tmp[idxs[i]].Stamp = 0) and (tmp[idxs[i]].Sig = 0) then Continue;
        SetLength(lib^.Swatches, Length(lib^.Swatches) + 1);
        lib^.Swatches[High(lib^.Swatches)] := tmp[idxs[i]];
        if tmp[idxs[i]].Stamp > lib^.StampCounter then lib^.StampCounter := tmp[idxs[i]].Stamp;
      end;

      RebuildDerivedPairs(lib^);
      Result := True;
    finally
      json.Free;
    end;
  finally
    sl.Free;
  end;
end;

procedure EnsureProfiles;
var
  i, oldLen: Integer;
begin
  // Initialize defaults once.
  if Length(GProfiles) = 0 then
  begin
    SetLength(GProfiles, 0);
    for i := 0 to PROFILE_COUNT - 1 do
      AddProfile(DEFAULT_PROFILE_NAMES[i], DEFAULT_PROFILE_PARAMS[i]);
    GActive := 0;
  end;

  // Pull in any *.json profiles found in the styles directory.
  oldLen := Length(GProfiles);
  ScanProfilesFromDisk;

  // Best-effort load profiles from disk if files exist (including newly discovered ones).
  for i := 0 to High(GProfiles) do
  begin
    // Load only if not already loaded.
    if not GProfiles[i].Lib.Loaded then
      LoadProfileFromDisk(i);
  end;

  // Clamp active.
  if (GActive < 0) or (GActive > High(GProfiles)) then
    GActive := 0;
end;

function GetProfileIndexByName(const Name: string): Integer;
var
  i: Integer;
  n: string;
begin
  EnsureProfiles;
  n := LowerCase(Trim(Name));
  for i := 0 to High(GProfiles) do
    if LowerCase(GProfiles[i].Name) = n then Exit(i);
  Exit(-1);
end;

procedure ShaderClearAll;
var
  i: Integer;
begin
  EnsureProfiles;
  for i := 0 to High(GProfiles) do
    LibClear(GProfiles[i].Lib);
  // TronicShade is stored/loaded alongside shader profiles; clear it as well.
  TronicShadeClear;
end;

procedure ShaderClear;
var
  lib: PShaderLibrary;
begin
  EnsureProfiles;
  lib := ActiveLibPtr;
  if lib = nil then Exit;
  LibClear(lib^);
  // Also clear TronicShade model associated with the active profile.
  TronicShadeClear;
end;

procedure ShaderFillProfileNames(AItems: TStrings);
var
  i: Integer;
begin
  EnsureProfiles;
  if AItems = nil then Exit;
  AItems.BeginUpdate;
  try
    AItems.Clear;
    for i := 0 to High(GProfiles) do
      AItems.Add(GProfiles[i].Name);
  finally
    AItems.EndUpdate;
  end;
end;

procedure ShaderSetActiveProfile(const Name: string);
var
  idx: Integer;
  nm: string;
begin
  EnsureProfiles;
  nm := LowerCase(Trim(Name));
  if nm = '' then nm := 'default';
  idx := GetProfileIndexByName(nm);
  if idx < 0 then
  begin
    // New user-named profile.
    AddProfile(nm, DEFAULT_PROFILE_PARAMS[0]);
    idx := High(GProfiles);
  end;
  GActive := idx;
  if not GProfiles[idx].Lib.Loaded then
    LoadProfileFromDisk(idx);
end;

function ShaderActiveProfileName: string;
begin
  EnsureProfiles;
  if (GActive < 0) or (GActive >= Length(GProfiles)) then Exit('default');
  Result := GProfiles[GActive].Name;
end;

procedure ShaderGetActiveParams(out P: TShaderParams);
begin
  EnsureProfiles;
  if (GActive < 0) or (GActive >= Length(GProfiles)) then
    P := DEFAULT_PROFILE_PARAMS[0]
  else
    P := GProfiles[GActive].Params;
end;

procedure ShaderSaveActiveProfile;
begin
  EnsureProfiles;
  if (GActive < 0) or (GActive >= Length(GProfiles)) then Exit;
  // Always persist current active to disk so named profiles can be managed explicitly.
  SaveProfileToDisk(GActive);
end;

procedure ShaderReloadActiveProfile;
begin
  EnsureProfiles;
  if (GActive < 0) or (GActive >= Length(GProfiles)) then Exit;
  // Discard current in-memory lib content and reload from JSON if present.
  LibClear(GProfiles[GActive].Lib);
  GProfiles[GActive].Lib.Loaded := False;
  LoadProfileFromDisk(GActive);
end;

function ShaderIsLoaded: Boolean;
var
  lib: PShaderLibrary;
begin
  EnsureProfiles;
  lib := ActiveLibPtr;
  if lib = nil then Exit(False);
  Result := lib^.Loaded and ((lib^.UniquePairs > 0) or (lib^.UniqueGlyphPairs > 0));
end;

function ShaderSummary: string;
var
  lib: PShaderLibrary;
begin
  EnsureProfiles;
  lib := ActiveLibPtr;
  if (lib = nil) or not lib^.Loaded then
    Exit(Format('Shader (%s): (none)', [ShaderActiveProfileName]));
  Result := Format('Shader (%s): swatches=%d pairs=%d glyphPairs=%d  file=%s',
    [ShaderActiveProfileName, Length(lib^.Swatches), lib^.UniquePairs, lib^.UniqueGlyphPairs, ExtractFileName(lib^.FileName)]);
end;

procedure ShaderGetPairsForGlyph(ch: Byte; out Pairs: TColorPairArray);
var
  lib: PShaderLibrary;
begin
  EnsureProfiles;
  lib := ActiveLibPtr;
  if lib = nil then
    SetLength(Pairs, 0)
  else
    Pairs := lib^.PairsByGlyph[ch];
end;

procedure ShaderGetAllPairs(out Pairs: TColorPairArray);
var
  lib: PShaderLibrary;
begin
  EnsureProfiles;
  lib := ActiveLibPtr;
  if lib = nil then
    SetLength(Pairs, 0)
  else
    Pairs := lib^.AllPairs;
end;

// --- import helpers ---------------------------------------------------------

procedure HarvestBlocksFromGrid(const ProfileName: string; var Lib: TShaderLibrary;
  const Grid: TCellArray; const Rows: Integer; const Append: Boolean; const LearnShadeOnly: Boolean);
var
  maxRead: Integer;
  by, bx: Integer;
  y0, x0: Integer;
  cx, cy: Integer;
  idx: Integer;
  ch, attr: Byte;
  fg, bg: Byte;
  // Count FG/BG pairs inside the block (dominant pair)
  pairCount: array[0..15,0..15] of Integer;
  bestFG, bestBG: Byte;
  bestCnt: Integer;
  bits: array[0..31] of Byte;
  any: Boolean;
begin
  if not Append then
    LibClear(Lib);

  maxRead := Rows;
  if maxRead < BLOCK_H then Exit;
  // Align down to block height
  maxRead := (maxRead div BLOCK_H) * BLOCK_H;

  for by := 0 to (maxRead div BLOCK_H) - 1 do
  begin
    y0 := by * BLOCK_H;
    for bx := 0 to (BIN_COLS div BLOCK_W) - 1 do
    begin
      x0 := bx * BLOCK_W;

      // reset
      for fg := 0 to 15 do
        for bg := 0 to 15 do
          pairCount[fg,bg] := 0;

      ClearBits(bits);
      any := False;

      // gather 3x3
      for cy := 0 to BLOCK_H - 1 do
      begin
        for cx := 0 to BLOCK_W - 1 do
        begin
          idx := (y0 + cy) * BIN_COLS + (x0 + cx);
          ch := Grid[idx].Ch;
          attr := Grid[idx].Attr;

          // Skip control chars / garbage
          if ch < 32 then Continue;
          if not ShouldLearnGlyph(ProfileName, ch, LearnShadeOnly) then Continue;

          fg := attr and $0F;
          bg := (attr shr 4) and $0F;

          Inc(pairCount[fg,bg]);
          SetBit(bits, ch);
          any := True;
        end;
      end;

      if not any then Continue;

      // dominant fg/bg
      bestCnt := -1;
      bestFG := 7;
      bestBG := 0;
      for fg := 0 to 15 do
        for bg := 0 to 15 do
          if pairCount[fg,bg] > bestCnt then
          begin
            bestCnt := pairCount[fg,bg];
            bestFG := Byte(fg);
            bestBG := Byte(bg);
          end;

      // add swatch
      AddOrReplaceSwatch(Lib, bestFG, bestBG, bits);
    end;
  end;

  RebuildDerivedPairs(Lib);
  Lib.Loaded := True;
end;

// --- ANSI import ------------------------------------------------------------

function ShaderImportANSIToActive(const FN: string; const MaxRows: Integer; const Append: Boolean;
  const TreatBlinkAsBrightBG: Boolean; const LearnShadeOnly: Boolean): Boolean;
type
  TAnsiState = record
    FGBase: Byte;   // 0..7
    BGBase: Byte;   // 0..7
    Bold: Boolean;  // bright FG
    Blink: Boolean; // used as bright BG when TreatBlinkAsBrightBG=True (iCE)
    BGBright: Boolean; // explicit bright BG (100..107)
  end;

  TCursorSave = record
    X, Y: Integer;
    Valid: Boolean;
  end;

  TInts = array of Integer;

  function MakeAttr(const St: TAnsiState): Byte;
  var
    fg, bg: Integer;
    bgHi: Boolean;
  begin
    fg := St.FGBase;
    if St.Bold then fg := fg + 8;
    bg := St.BGBase;
    bgHi := St.BGBright or (St.Blink and TreatBlinkAsBrightBG);
    if bgHi then bg := bg + 8;
    if fg < 0 then fg := 0 else if fg > 15 then fg := 15;
    if bg < 0 then bg := 0 else if bg > 15 then bg := 15;
    Result := Byte((bg shl 4) or fg);
  end;

  procedure ResetState(var St: TAnsiState);
  begin
    St.FGBase := 7;
    St.BGBase := 0;
    St.Bold := False;
    St.Blink := False;
    St.BGBright := False;
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

  procedure GridFill(var Grid: TCellArray; const Attr: Byte);
  var
    i: Integer;
  begin
    for i := 0 to High(Grid) do
    begin
      Grid[i].Ch := 32;
      Grid[i].Attr := Attr;
    end;
  end;

  procedure ClearLine(var Grid: TCellArray; const Y, X0, X1: Integer; const Attr: Byte);
  var
    x: Integer;
    idx: Integer;
  begin
    if (Y < 0) or (Y >= MaxRows) then Exit;
    for x := X0 to X1 do
    begin
      if (x < 0) or (x >= BIN_COLS) then Continue;
      idx := Y * BIN_COLS + x;
      Grid[idx].Ch := 32;
      Grid[idx].Attr := Attr;
    end;
  end;

  procedure ClearScreenFrom(var Grid: TCellArray; const X, Y: Integer; const Mode: Integer; const Attr: Byte);
  var
    yy, xx: Integer;
  begin
    // Mode: 0 = cursor->end, 1 = start->cursor, 2 = all
    if Mode = 2 then
    begin
      GridFill(Grid, Attr);
      Exit;
    end;

    if Mode = 0 then
    begin
      for yy := Y to MaxRows - 1 do
      begin
        for xx := 0 to BIN_COLS - 1 do
        begin
          if (yy = Y) and (xx < X) then Continue;
          Grid[yy * BIN_COLS + xx].Ch := 32;
          Grid[yy * BIN_COLS + xx].Attr := Attr;
        end;
      end;
    end
    else if Mode = 1 then
    begin
      for yy := 0 to Y do
      begin
        for xx := 0 to BIN_COLS - 1 do
        begin
          if (yy = Y) and (xx > X) then Continue;
          Grid[yy * BIN_COLS + xx].Ch := 32;
          Grid[yy * BIN_COLS + xx].Attr := Attr;
        end;
      end;
    end;
  end;

var
  fs: TFileStream;
  buf: TBytes;
  i: Int64;
  b: Byte;
  grid: TCellArray;
  st: TAnsiState;
  save: TCursorSave;
  x, y: Integer;
  maxY: Integer;
  lib: PShaderLibrary;

  finalCh: Char;
  params: TInts;

  procedure AddParam(var Arr: TInts; v: Integer);
  var n: Integer;
  begin
    n := Length(Arr);
    SetLength(Arr, n+1);
    Arr[n] := v;
  end;

  procedure ParseCSI(var Pos: Int64; out FinalCh: Char; out P: TInts);
  var
    cur: Integer;
    haveNum: Boolean;
    c: Byte;
  begin
    SetLength(P, 0);
    cur := 0;
    haveNum := False;
    FinalCh := #0;

    while Pos < Length(buf) do
    begin
      c := buf[Pos];
      // end of CSI when we hit a final byte in 0x40..0x7E
      if (c >= $40) and (c <= $7E) then
      begin
        if (Length(P) = 0) and (not haveNum) then
          AddParam(P, 0)
        else if haveNum then
          AddParam(P, cur);

        FinalCh := Char(c);
        Exit;
      end;

      if (c >= Ord('0')) and (c <= Ord('9')) then
      begin
        cur := cur * 10 + Integer(c - Ord('0'));
        haveNum := True;
      end
      else if c = Ord(';') then
      begin
        if haveNum then
          AddParam(P, cur)
        else
          AddParam(P, 0);
        cur := 0;
        haveNum := False;
      end
      else
      begin
        // ignore other chars like '?'
      end;

      Inc(Pos);
    end;
  end;

  procedure PutChar(const C: Byte);
  var
    idx: Integer;
  begin
    if (y < 0) or (y >= MaxRows) then Exit;
    if (x < 0) then x := 0;
    if (x >= BIN_COLS) then
    begin
      x := 0;
      Inc(y);
      if y >= MaxRows then Exit;
    end;

    idx := y * BIN_COLS + x;
    grid[idx].Ch := C;
    grid[idx].Attr := MakeAttr(st);

    Inc(x);
    if x >= BIN_COLS then
    begin
      x := 0;
      Inc(y);
    end;

    if y > maxY then maxY := y;
  end;

begin
  Result := False;
  EnsureProfiles;

  if not FileExists(FN) then Exit(False);

  lib := ActiveLibPtr;
  if lib = nil then Exit(False);

  fs := TFileStream.Create(FN, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(buf, fs.Size);
    if fs.Size > 0 then
      fs.ReadBuffer(buf[0], fs.Size);

    ResetState(st);
    save.Valid := False;
    x := 0; y := 0;
    maxY := 0;

    SetLength(grid, BIN_COLS * MaxRows);
    GridFill(grid, MakeAttr(st));

    i := 0;
    while i < Length(buf) do
    begin
      b := buf[i];

      // ESC sequences
      if b = $1B then
      begin
        if (i + 1) < Length(buf) then
        begin
          Inc(i);
          b := buf[i];

          if b = Ord('[') then
          begin
            // CSI sequence
            Inc(i);
            ParseCSI(i, finalCh, params);
            // ParseCSI returns with i at final byte position
            if (i >= Length(buf)) or (finalCh = #0) then Break;
            case finalCh of
              'm': ApplySGR(st, params);
              'H','f':
                begin
                  // CUP row;col (1-based)
                  if Length(params) >= 1 then y := params[0] - 1 else y := 0;
                  if Length(params) >= 2 then x := params[1] - 1 else x := 0;
                  if x < 0 then x := 0 else if x >= BIN_COLS then x := BIN_COLS-1;
                  if y < 0 then y := 0 else if y >= MaxRows then y := MaxRows-1;
                end;
              'A': begin
                     if Length(params) >= 1 then y := y - params[0] else Dec(y);
                     if y < 0 then y := 0;
                   end;
              'B': begin
                     if Length(params) >= 1 then y := y + params[0] else Inc(y);
                     if y >= MaxRows then y := MaxRows-1;
                   end;
              'C': begin
                     if Length(params) >= 1 then x := x + params[0] else Inc(x);
                     if x >= BIN_COLS then x := BIN_COLS-1;
                   end;
              'D': begin
                     if Length(params) >= 1 then x := x - params[0] else Dec(x);
                     if x < 0 then x := 0;
                   end;
              'G': begin
                     // CHA set column (1-based)
                     if Length(params) >= 1 then x := params[0] - 1 else x := 0;
                     if x < 0 then x := 0 else if x >= BIN_COLS then x := BIN_COLS-1;
                   end;
              'J': begin
                     if Length(params) >= 1 then ClearScreenFrom(grid, x, y, params[0], MakeAttr(st))
                     else ClearScreenFrom(grid, x, y, 0, MakeAttr(st));
                   end;
              'K': begin
                     // EL erase in line
                     if Length(params) = 0 then
                       ClearLine(grid, y, x, BIN_COLS-1, MakeAttr(st))
                     else case params[0] of
                       0: ClearLine(grid, y, x, BIN_COLS-1, MakeAttr(st));
                       1: ClearLine(grid, y, 0, x, MakeAttr(st));
                       2: ClearLine(grid, y, 0, BIN_COLS-1, MakeAttr(st));
                     end;
                   end;
              's': begin save.X := x; save.Y := y; save.Valid := True; end;
              'u': if save.Valid then begin x := save.X; y := save.Y; end;
            end;

            Inc(i); // move past final char
            Continue;
          end
          else if b = Ord('7') then
          begin
            save.X := x; save.Y := y; save.Valid := True;
            Inc(i);
            Continue;
          end
          else if b = Ord('8') then
          begin
            if save.Valid then begin x := save.X; y := save.Y; end;
            Inc(i);
            Continue;
          end;
        end;

        Inc(i);
        Continue;
      end;

      // Newlines / controls
      if b = 13 then
      begin
        x := 0;
        Inc(i);
        Continue;
      end
      else if b = 10 then
      begin
        x := 0;
        Inc(y);
        if y >= MaxRows then Break;
        if y > maxY then maxY := y;
        Inc(i);
        Continue;
      end
      else if b = 9 then
      begin
        x := (x + 8) and (not 7);
        if x >= BIN_COLS then x := BIN_COLS - 1;
        Inc(i);
        Continue;
      end
      else if b < 32 then
      begin
        Inc(i);
        Continue;
      end;

      PutChar(b);
      Inc(i);

      if y >= MaxRows then Break;
    end;

    if maxY >= MaxRows then maxY := MaxRows - 1;

    // Harvest 3x3 blocks from the final grid
    // PatchStyle learning: keep a patchbook from imported files
    if not Append then PatchLibClear;
    PatchLibLearnFromCells(grid, BIN_COLS, maxY + 1);
    // If we're learning "shade only", also restrict PatchStyle patches to blocks/shades.
    if LearnShadeOnly then
      PatchLibFilterBlocksOnly;

    // TronicShade learning (multi-scale probabilistic style)
    // When LearnShadeOnly is requested, strip letters/numbers/etc. and learn only
    // shading glyphs (space/blocks/halves) for Tronicshade styles.
    if not Append then TronicShadeClear;
    if LearnShadeOnly then
      TronicShadeLearnFromCellsShadeOnly(grid, BIN_COLS, maxY + 1)
    else
      TronicShadeLearnFromCells(grid, BIN_COLS, maxY + 1);

    HarvestBlocksFromGrid(ShaderActiveProfileName, lib^, grid, maxY + 1, Append, LearnShadeOnly);

    lib^.FileName := FN;
    lib^.RowsInFile := maxY + 1;
    lib^.MaxRowsRead := maxY + 1;

    SaveProfileToDisk(GActive);
    Result := True;
  finally
    fs.Free;
  end;
end;

// --- BIN import -------------------------------------------------------------

function ShaderImportBINToActive(const FN: string; const MaxRows: Integer; const Append: Boolean;
  const LearnShadeOnly: Boolean): Boolean;
var
  fs: TFileStream;
  cells: Int64;
  rows: Integer;
  maxRead: Integer;
  x, y: Integer;
  idx: Int64;
  grid: TCellArray;
  lib: PShaderLibrary;
begin
  Result := False;
  EnsureProfiles;

  if not FileExists(FN) then Exit(False);

  lib := ActiveLibPtr;
  if lib = nil then Exit(False);

  fs := TFileStream.Create(FN, fmOpenRead or fmShareDenyWrite);
  try
    if (fs.Size mod 2) <> 0 then Exit(False);
    cells := fs.Size div 2;
    if (cells mod BIN_COLS) <> 0 then Exit(False);

    rows := cells div BIN_COLS;
    if rows < 1 then Exit(False);

    maxRead := rows;
    if maxRead > MaxRows then maxRead := MaxRows;

    // Load the region into a grid
    SetLength(grid, BIN_COLS * maxRead);
    for y := 0 to maxRead - 1 do
      for x := 0 to BIN_COLS - 1 do
      begin
        idx := (Int64(y) * BIN_COLS + Int64(x)) * 2;
        fs.Position := idx;
        fs.ReadBuffer(grid[y * BIN_COLS + x].Ch, 1);
        fs.ReadBuffer(grid[y * BIN_COLS + x].Attr, 1);
      end;

    // PatchStyle learning: keep a patchbook from imported files
    if not Append then PatchLibClear;
    PatchLibLearnFromCells(grid, BIN_COLS, maxRead);
    // If we're learning "shade only", also restrict PatchStyle patches to blocks/shades.
    if LearnShadeOnly then
      PatchLibFilterBlocksOnly;

    HarvestBlocksFromGrid(ShaderActiveProfileName, lib^, grid, maxRead, Append, LearnShadeOnly);

    lib^.FileName := FN;
    lib^.RowsInFile := rows;
    lib^.MaxRowsRead := maxRead;

    SaveProfileToDisk(GActive);
    Result := True;
  finally
    fs.Free;
  end;
end;

initialization
  EnsureProfiles;

end.
