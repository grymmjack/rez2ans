unit ansi_export_opts;

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

type
  // Row separator used when writing ANSI files.
  // NOTE:
  //   - Windows tools typically expect CRLF.
  //   - Unix tools (Linux/macOS) typically expect LF (avoids stray ^M).
  // Some retro ANSI viewers/editors treat CR as "newline" by itself.
  TAnsiLineEnding = (aleCR, aleCRLF, aleLF);

  // Options for Save-to-ANSI (BBS/CP437) export.
  TAnsiExportOptions = record
    // Compatibility / formatting
    TrimTrailingSpaces: Boolean;   // remove trailing default cells per line
    ClearScreenHome: Boolean;      // emit ESC[2J ESC[H at file start
    LineEnding: TAnsiLineEnding;   // row separator (CR/CRLF/LF)

    // SAUCE metadata
    AddSauce: Boolean;
    SauceTitle: AnsiString;
    SauceAuthor: AnsiString;
    SauceGroup: AnsiString;
    AddSourceComment: Boolean;     // write COMNT line: SOURCE: <file>
    IceFlag: Boolean;              // SAUCE ICE flag bit0

    // Convenience
    CopySourceImage: Boolean;      // copy <out>_source.<ext> beside .ans
  end;

procedure SetAnsiExportDefaults(const OutName, SourceImagePath: string;
  var Opt: TAnsiExportOptions);

implementation

procedure SetAnsiExportDefaults(const OutName, SourceImagePath: string;
  var Opt: TAnsiExportOptions);
var
  baseTitle: string;
begin
  FillChar(Opt, SizeOf(Opt), 0);

  Opt.TrimTrailingSpaces := True;
  Opt.ClearScreenHome := True;

  // Default EOL:
  // - Windows: CRLF
  // - Linux/macOS: LF (avoids stray ^M in unix tools)
{$IFDEF WINDOWS}
  Opt.LineEnding := aleCRLF;
{$ELSE}
  Opt.LineEnding := aleLF;
{$ENDIF}

  Opt.AddSauce := True;
  baseTitle := ChangeFileExt(ExtractFileName(OutName), '');
  if baseTitle = '' then baseTitle := 'ANSI';
  Opt.SauceTitle := AnsiString(baseTitle);
  Opt.SauceAuthor := 'rez2ansi';
  Opt.SauceGroup := 'BlockZ';
  Opt.AddSourceComment := True;

  // Default ICE flag should track the render option usually,
  // but if caller doesn't know, default to True for BBS usage.
  Opt.IceFlag := True;

  Opt.CopySourceImage := (SourceImagePath <> '') and FileExists(SourceImagePath);
end;

end.
