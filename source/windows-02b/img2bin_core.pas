unit img2bin_core;

{$mode objfpc}{$H+}

interface

uses
  FPImage, Types,
  img2bin_types;

type
  // Keep the original API surface for the GUI.
  TPaletteKind = img2bin_types.TPaletteKind;
  TColorMetric = img2bin_types.TColorMetric;
  TDitherMode  = img2bin_types.TDitherMode;
  TRenderMode  = img2bin_types.TRenderMode;

  TRGB = img2bin_types.TRGB;
  TCell = img2bin_types.TCell;
  TCellArray = img2bin_types.TCellArray;
  TConvertOptions = img2bin_types.TConvertOptions;

const
  COLS = img2bin_types.COLS;

procedure ApplyStyle(const style: string; out Opt: TConvertOptions);
function LoadAnyImage(const FN: string): TFPMemoryImage;

procedure ConvertImageToCells(
  const Img: TFPCustomImage;
  const Opt: TConvertOptions;
  out OutRows: Integer;
  out Cells: TCellArray
);

procedure SaveBIN(const OutName: string; const Cells: TCellArray);
procedure SaveANSI(const OutName: string; const Cells: TCellArray; Ice: Boolean;
  const SourceImagePath: string = '');

function VGA16(i: Integer): TRGB;
function Palette16(Pal: TPaletteKind; i: Integer): TRGB;
function CP437Glyph(b: Byte): UnicodeString;

implementation

uses
  img2bin_styles,
  img2bin_io,
  img2bin_convert,
  img2bin_palette,
  img2bin_cp437;

procedure ApplyStyle(const style: string; out Opt: TConvertOptions);
begin
  img2bin_styles.ApplyStyle(style, Opt);
end;

function LoadAnyImage(const FN: string): TFPMemoryImage;
begin
  Result := img2bin_io.LoadAnyImage(FN);
end;

procedure ConvertImageToCells(
  const Img: TFPCustomImage;
  const Opt: TConvertOptions;
  out OutRows: Integer;
  out Cells: TCellArray
);
begin
  img2bin_convert.ConvertImageToCells(Img, Opt, OutRows, Cells);
end;

procedure SaveBIN(const OutName: string; const Cells: TCellArray);
begin
  img2bin_io.SaveBIN(OutName, Cells);
end;

procedure SaveANSI(const OutName: string; const Cells: TCellArray; Ice: Boolean;
  const SourceImagePath: string = '');
begin
  img2bin_io.SaveANSI(OutName, Cells, Ice, SourceImagePath);
end;

function VGA16(i: Integer): TRGB;
begin
  Result := img2bin_palette.VGA16(i);
end;

function Palette16(Pal: TPaletteKind; i: Integer): TRGB;
begin
  Result := img2bin_palette.Palette16(Pal, i);
end;

function CP437Glyph(b: Byte): UnicodeString;
begin
  Result := img2bin_cp437.CP437Glyph(b);
end;

end.
