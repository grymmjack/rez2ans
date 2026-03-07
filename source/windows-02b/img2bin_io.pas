unit img2bin_io;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  FPImage, FPReadPNG, FPReadJPEG, FPReadBMP,
  img2bin_types, ansi_export_opts;

function LoadAnyImage(const FN: string): TFPMemoryImage;
function LoadHexPalette(const FN: string; out Pal: TRGBArray): Boolean;
procedure SaveBIN(const OutName: string; const Cells: TCellArray);

// Writes an ANSI (CP437) file with minimized SGR sequences.
// Optional features are controlled by Opt:
// - TrimTrailingSpaces, ClearScreenHome
// - SAUCE record + optional COMNT SOURCE line
// - Optional copy of original source image beside the .ans
procedure SaveANSIEx(const OutName: string; const Cells: TCellArray;
  const Opt: TAnsiExportOptions; const SourceImagePath: string = '');

// Backwards-compatible API used elsewhere in the project.
// Ice controls the SAUCE iCE flag (bit0) and legacy blink/bright-bg expectations.
procedure SaveANSI(const OutName: string; const Cells: TCellArray; Ice: Boolean;
  const SourceImagePath: string = '');

implementation

function LoadAnyImage(const FN: string): TFPMemoryImage;
var
  ext: string;
  rPNG: TFPReaderPNG;
  rJPG: TFPReaderJPEG;
  rBMP: TFPReaderBMP;
begin
  if (FN = '') or (not FileExists(FN)) then
    raise Exception.CreateFmt('File not found: %s', [FN]);

  Result := TFPMemoryImage.Create(0, 0);
  ext := LowerCase(ExtractFileExt(FN));

  try
    if ext = '.png' then
    begin
      rPNG := TFPReaderPNG.Create;
      try
        Result.LoadFromFile(FN, rPNG);
      finally
        rPNG.Free;
      end;
      Exit;
    end;

    if ext = '.bmp' then
    begin
      rBMP := TFPReaderBMP.Create;
      try
        Result.LoadFromFile(FN, rBMP);
      finally
        rBMP.Free;
      end;
      Exit;
    end;

    if (ext = '.jpg') or (ext = '.jpeg') then
    begin
      rJPG := TFPReaderJPEG.Create;
      try
        Result.LoadFromFile(FN, rJPG);
      finally
        rJPG.Free;
      end;
      Exit;
    end;

    // Fallback: try JPEG first, then PNG. Cleanly handle failures without leaking Result.
    rJPG := TFPReaderJPEG.Create;
    try
      try
        Result.LoadFromFile(FN, rJPG);
        Exit;
      except
        // swallow and try PNG next
      end;
    finally
      rJPG.Free;
    end;

    rPNG := TFPReaderPNG.Create;
    try
      Result.LoadFromFile(FN, rPNG);
    finally
      rPNG.Free;
    end;

  except
    on E: Exception do
    begin
      Result.Free;
      raise Exception.CreateFmt('Failed to load image "%s": %s', [FN, E.Message]);
    end;
  end;
end;

function LoadHexPalette(const FN: string; out Pal: TRGBArray): Boolean;
var
  sl: TStringList;
  i: Integer;
  s: string;
  v: Int64;
  c: TRGB;
begin
  Result := False;
  SetLength(Pal, 0);
  if (FN = '') or (not FileExists(FN)) then Exit;

  sl := TStringList.Create;
  try
    sl.LoadFromFile(FN);
    for i := 0 to sl.Count - 1 do
    begin
      s := Trim(sl[i]);
      if s = '' then Continue;

      // Allow comments
      if (Length(s) >= 1) and (s[1] in [';','/']) then Continue;
      if (Length(s) >= 2) and (s[1] = '/') and (s[2] = '/') then Continue;

      // Allow leading '#'
      if (Length(s) >= 1) and (s[1] = '#') then
        Delete(s, 1, 1);

      if Length(s) <> 6 then Continue;

      try
        v := StrToInt64('$' + s);
      except
        Continue;
      end;

      c.R := Byte((v shr 16) and $FF);
      c.G := Byte((v shr 8) and $FF);
      c.B := Byte(v and $FF);

      SetLength(Pal, Length(Pal) + 1);
      Pal[High(Pal)] := c;
      if Length(Pal) >= 256 then Break;
    end;
  finally
    sl.Free;
  end;

  // Enforce 2..256
  if Length(Pal) < 2 then
  begin
    SetLength(Pal, 0);
    Exit(False);
  end;

  Result := True;
end;


procedure SaveBIN(const OutName: string; const Cells: TCellArray);
var
  fs: TFileStream;
begin
  fs := TFileStream.Create(OutName, fmCreate);
  try
    if Length(Cells) > 0 then
      fs.WriteBuffer(Cells[0], Length(Cells) * SizeOf(TCell));
  finally
    fs.Free;
  end;
end;

procedure SaveANSIEx(const OutName: string; const Cells: TCellArray; const Opt: TAnsiExportOptions;
  const SourceImagePath: string = '');
type
  TSauceRec = packed record
    ID: array[0..6] of AnsiChar;        // 'SAUCE00'
    Title: array[0..34] of AnsiChar;
    Author: array[0..19] of AnsiChar;
    Group: array[0..19] of AnsiChar;
    Date: array[0..7] of AnsiChar;      // YYYYMMDD
    FileSize: LongWord;
    DataType: Byte;                    // 1 = Character
    FileType: Byte;                    // 1 = ANSI
    TInfo1: Word;                      // cols
    TInfo2: Word;                      // rows
    TInfo3: Word;
    TInfo4: Word;
    TComments: Byte;                   // number of 64-byte comment lines
    TFlags: Byte;
    TInfoS: array[0..21] of AnsiChar;
  end;

  procedure FillFixed(var dst; dstLen: Integer; const s: AnsiString);
  var
    p: PAnsiChar;
    i, n: Integer;
  begin
    FillChar(dst, dstLen, Ord(' '));
    if s = '' then Exit;
    p := PAnsiChar(s);
    n := Length(s);
    if n > dstLen then n := dstLen;
    for i := 0 to n-1 do
      PAnsiChar(@dst)[i] := p[i];
  end;

  procedure WriteBytes(ms: TStream; const buf; len: Integer);
  begin
    if len > 0 then
      ms.WriteBuffer(buf, len);
  end;

  procedure WriteAnsiStr(ms: TStream; const s: AnsiString);
  begin
    if s <> '' then
      WriteBytes(ms, PAnsiChar(s)^, Length(s));
  end;

  procedure WriteEOL(ms: TStream; le: TAnsiLineEnding);
  const
    CR_: Byte = 13;
    LF_: Byte = 10;
    CRLF: array[0..1] of Byte = (13, 10);
  begin
    case le of
      aleCR:   WriteBytes(ms, CR_, 1);
      aleLF:   WriteBytes(ms, LF_, 1);
    else
      WriteBytes(ms, CRLF, 2);
    end;
  end;

  function Clamp01To7(v: Integer): Integer; inline;
  begin
    Result := v and 7;
  end;

  procedure WriteSGR(ms: TStream; const Codes: array of Integer);
  var
    s: AnsiString;
    i: Integer;
  begin
    if Length(Codes) = 0 then Exit;
    s := #27'[';
    for i := 0 to High(Codes) do
    begin
      if i > 0 then s := s + ';';
      s := s + AnsiString(IntToStr(Codes[i]));
    end;
    s := s + 'm';
    WriteAnsiStr(ms, s);
  end;

  procedure CopyFileSimple(const Src, Dst: string);
  var
    fsIn, fsOut: TFileStream;
  begin
    if (Src = '') or (Dst = '') then Exit;
    if not FileExists(Src) then Exit;
    if SameFileName(Src, Dst) then Exit;
    fsIn := TFileStream.Create(Src, fmOpenRead or fmShareDenyNone);
    try
      fsOut := TFileStream.Create(Dst, fmCreate);
      try
        fsOut.CopyFrom(fsIn, 0);
      finally
        fsOut.Free;
      end;
    finally
      fsIn.Free;
    end;
  end;

var
  ms: TMemoryStream;
  rows, r, c, idx: Integer;
  lastCol: Integer;
  curAttr: Integer;
  fgRaw, bgRaw: Integer;
  fgBase, bgBase: Integer;
  wantBold, wantBlink: Boolean;
  wantFGCode, wantBGCode: Integer;
  wantAttr: Integer;
  ch: Byte;
  sauce: TSauceRec;
  baseTitle: string;
  commentLine: AnsiString;
  commentCount: Byte;
  fileSizeBeforeMeta: LongWord;
  dstImg: string;
  outDir: string;
const
  // VGA (DOS) attribute color order is BGR (1=blue, 4=red), while ANSI SGR
  // base colors are ordered as: 0=black,1=red,2=green,3=yellow,4=blue,5=magenta,6=cyan,7=white.
  // Map VGA 0..7 -> SGR 0..7 so exported .ANS matches ANSI art editors/viewers.
  VGA_TO_SGR: array[0..7] of Byte = (0, 4, 2, 6, 1, 5, 3, 7);
begin
  if Length(Cells) = 0 then Exit;
  rows := Length(Cells) div COLS;
  if rows <= 0 then Exit;

  ms := TMemoryStream.Create;
  try
    // Reset attributes (most compatible).
    WriteSGR(ms, [0]);
    if Opt.ClearScreenHome then
      WriteAnsiStr(ms, #27'[2J'#27'[H');
    curAttr := -1;
    for r := 0 to rows-1 do
    begin
      if Opt.TrimTrailingSpaces then
      begin
              // Trim trailing "default" area, but keep colored spaces.
              lastCol := -1;
              for c := COLS-1 downto 0 do
              begin
                idx := r*COLS + c;
                if idx > High(Cells) then Continue;
                ch := Cells[idx].Ch;
                if (ch < 32) or (ch = 127) then ch := 32;
                if (ch <> 32) or ((Cells[idx].Attr and $0F) <> 7) or (((Cells[idx].Attr shr 4) and $0F) <> 0) then
                begin
                  lastCol := c;
                  Break;
                end;
      end;
      end
      else
        lastCol := COLS-1;

      if lastCol < 0 then
      begin
        // Empty line
        WriteSGR(ms, [0]);
        curAttr := -1;
        WriteEOL(ms, Opt.LineEnding);
        Continue;
      end;

      for c := 0 to lastCol do
      begin
        idx := r*COLS + c;
        if idx > High(Cells) then Break;
        fgRaw := Cells[idx].Attr and $0F;
        bgRaw := (Cells[idx].Attr shr 4) and $0F;

        // Compatibility-first 16-color ANSI (PabloDraw/Moebius style):
        // - Base colors use 30..37 / 40..47
        // - Bright foreground uses "bold" (SGR 1) instead of 90..97
        // - Bright background uses "blink" (SGR 5) + 40..47 when ICE is enabled.
        //   If ICE is disabled, bright backgrounds are downgraded to 0..7.

        // Derive effective BG and style flags.
        wantBold := (fgRaw >= 8);
        wantBlink := (bgRaw >= 8) and Opt.IceFlag;

        if fgRaw >= 8 then
          fgBase := fgRaw - 8
        else
          fgBase := fgRaw;

        if bgRaw >= 8 then
        begin
          if Opt.IceFlag then
            bgBase := bgRaw - 8
          else
            bgBase := bgRaw - 8; // downgrade, but keep base hue
        end
        else
          bgBase := bgRaw;

        // If ICE is off, ensure bgBase is 0..7 and don't blink.
        if (not Opt.IceFlag) then
        begin
          wantBlink := False;
          if bgBase > 7 then bgBase := bgBase and 7;
        end;

        wantFGCode := 30 + VGA_TO_SGR[fgBase];
        wantBGCode := 40 + VGA_TO_SGR[bgBase];

        // Include style flags in the change-detection key.
        wantAttr := (Ord(wantBlink) shl 9) or (Ord(wantBold) shl 8) or (bgBase shl 4) or fgBase;
        if wantAttr <> curAttr then
        begin
          if wantBold and wantBlink then
            WriteSGR(ms, [0, 1, 5, wantFGCode, wantBGCode])
          else if wantBold then
            WriteSGR(ms, [0, 1, wantFGCode, wantBGCode])
          else if wantBlink then
            WriteSGR(ms, [0, 5, wantFGCode, wantBGCode])
          else
            WriteSGR(ms, [0, wantFGCode, wantBGCode]);
          curAttr := wantAttr;
        end;

        // Emit character byte (CP437).
        ch := Cells[idx].Ch;
        if (ch < 32) or (ch = 127) then ch := 32;
        WriteBytes(ms, ch, 1);
      end;
      WriteSGR(ms, [0]);
      curAttr := -1;
      WriteEOL(ms, Opt.LineEnding);
    end;

    // Reset at end.
    WriteSGR(ms, [0]);
    if Opt.AddSauce then
    begin
      // --- SAUCE ---
      fileSizeBeforeMeta := ms.Size;
      FillChar(sauce, SizeOf(sauce), 0);
      sauce.ID[0] := 'S'; sauce.ID[1] := 'A'; sauce.ID[2] := 'U'; sauce.ID[3] := 'C';
      sauce.ID[4] := 'E'; sauce.ID[5] := '0'; sauce.ID[6] := '0';

      baseTitle := ChangeFileExt(ExtractFileName(OutName), '');
      if baseTitle = '' then baseTitle := 'ANSI';

      if Opt.SauceTitle <> '' then
        FillFixed(sauce.Title, SizeOf(sauce.Title), Opt.SauceTitle)
      else
        FillFixed(sauce.Title, SizeOf(sauce.Title), AnsiString(baseTitle));

      if Opt.SauceAuthor <> '' then
        FillFixed(sauce.Author, SizeOf(sauce.Author), Opt.SauceAuthor)
      else
        FillFixed(sauce.Author, SizeOf(sauce.Author), 'img2bin_gui');

      if Opt.SauceGroup <> '' then
        FillFixed(sauce.Group, SizeOf(sauce.Group), Opt.SauceGroup)
      else
        FillFixed(sauce.Group, SizeOf(sauce.Group), 'Tronic');

      FillFixed(sauce.Date, SizeOf(sauce.Date), AnsiString(FormatDateTime('yyyymmdd', Date)));
      sauce.FileSize := fileSizeBeforeMeta;
      sauce.DataType := 1;
      sauce.FileType := 1;
      sauce.TInfo1 := Word(COLS);
      sauce.TInfo2 := Word(rows);
      sauce.TInfo3 := 0;
      sauce.TInfo4 := 0;
      // SAUCE TFlags bit0 is commonly used to indicate ICE colors.
      sauce.TFlags := Ord(Opt.IceFlag);

      commentCount := 0;
      commentLine := '';
      if Opt.AddSourceComment and (SourceImagePath <> '') and FileExists(SourceImagePath) then
      begin
        commentLine := 'SOURCE: ' + AnsiString(ExtractFileName(SourceImagePath));
        commentCount := 1;
      end;
      sauce.TComments := commentCount;

      if commentCount > 0 then
      begin
        WriteAnsiStr(ms, 'COMNT');
        // 64-byte, space padded line
        if Length(commentLine) > 64 then
          commentLine := Copy(commentLine, 1, 64);
        while Length(commentLine) < 64 do
          commentLine := commentLine + ' ';
        WriteAnsiStr(ms, commentLine);
      end;

      WriteBytes(ms, sauce, SizeOf(sauce));
    end;

    ms.SaveToFile(OutName);
  finally
    ms.Free;
  end;

  // Copy source image into the same output folder (handy for sharing / SAUCE-aware tooling).
  // IMPORTANT: If the file already exists, overwrite it (don't create numbered duplicates).
  if Opt.CopySourceImage and (SourceImagePath <> '') and FileExists(SourceImagePath) then
  begin
    outDir := ExtractFileDir(OutName);
    dstImg := IncludeTrailingPathDelimiter(outDir) + ExtractFileName(SourceImagePath);
    try
      CopyFileSimple(SourceImagePath, dstImg);
    except
      // non-fatal
    end;
  end;
end;




procedure SaveANSI(const OutName: string; const Cells: TCellArray; Ice: Boolean;
  const SourceImagePath: string = '');
var
  o: TAnsiExportOptions;
begin
  SetAnsiExportDefaults(OutName, SourceImagePath, o);
  o.IceFlag := Ice;
  // Keep existing behavior: if a source exists, default to copying it.
  o.CopySourceImage := (SourceImagePath <> '') and FileExists(SourceImagePath);
  SaveANSIEx(OutName, Cells, o, SourceImagePath);
end;


end.
