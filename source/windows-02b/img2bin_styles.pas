unit img2bin_styles;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Types,
  img2bin_types;

procedure ApplyStyle(const style: string; out Opt: TConvertOptions);

implementation

procedure ApplyStyle(const style: string; out Opt: TConvertOptions);
var s: string;
begin
  Opt.Aspect := 0.55;
  Opt.Palette := pkVGA;
  Opt.PaletteMatch := True;
  Opt.ColorMetric := cmRedmean;
  Opt.ColorMatchPct := 130;
  Opt.ForcedRows := -1;
  Opt.WinX := 4;
  Opt.WinY := 4;

  Opt.UseCrop := False;
  Opt.Crop := Rect(0,0,0,0);

  Opt.Mode := rmHybrid;
  Opt.Ice := True;
  Opt.Dither := dmFS;
  Opt.DitherStrength := 1.0;

  // Cell-level diffusion (disabled by default; enable explicitly).
  Opt.CellDiffusionModel := cdmOff;
  Opt.CellDiffusionAmount := 35;
  Opt.CellToneCorrection := 0;

  Opt.Gamma := 1.00;
  Opt.Contrast := 1.10;
  Opt.Saturation := 1.05;

  Opt.Brightness := 1.00;
  Opt.AnsiRezMode := False;
  Opt.AnsiRezFilter := afMedian;

  Opt.GlyphSet := gsLines;
  Opt.GlyphSmooth := 0.15;
  Opt.ShadeBlend := 0.65;

  // Color hints (optional, provided by GUI). By default, if hints exist,
  // use them to override palette entries for more stable matching.
  Opt.HintTolerance := 50;
  SetLength(Opt.ColorHints, 0);
  Opt.UseHintPalette := True;

  // By default, if hints exist, also apply a final "snap" pass.
  Opt.HintPostFix := True;
  Opt.HintPostFixPct := 90;


  // Optional: gently refit hinted palette entries over multiple passes.
  Opt.RefitHintedPaletteEachPass := True;

  Opt.AutoShaderPasses := 4;
  // AutoShader defaults
  Opt.UseShaderLib := False;
  // When a shader profile is used, match strictly to glyph+color combos that
  // appear in that profile. This makes output look more like the imported art.
  Opt.ShaderStrictGlyphMatch := True;
  // Match what you'll actually see in DOSBox terminals.
  Opt.DosBoxModel := True;

  // TronicShade defaults
  Opt.TronicCharStrength := 100;
  // Legacy checkbox kept for backward compatibility; color metric below is the real switch.
  Opt.TronicLumaOnly := True;
  Opt.TronicToneCorrection := 20;

  // AutoShader-style tone target field (10x10 blocks, stride 5)
  Opt.TronicAutoShaderEnabled := True;
  Opt.TronicWindowSize := 10;
  Opt.TronicWindowStep := 5;

  // Diffusion + color metric
  Opt.TronicDiffusionModel := tdmOrderedBayer4;
  Opt.TronicDiffusionAmount := 20;
  Opt.TronicColorMetric := tcmLumaOnly;

  // Export-only HQ mode (handled by GUI export pipeline).
  Opt.HQMode := 0;

  s := LowerCase(style);
  if s = 'acid' then
  begin
    Opt.Ice := True;
    Opt.Dither := dmFS;
  Opt.DitherStrength := 1.0;
    Opt.Gamma := 0.95;
    Opt.Contrast := 1.25;
    Opt.Saturation := 1.20;
  end
  else if s = 'plain' then
  begin
    Opt.Ice := False;
    Opt.Dither := dmNone;
  Opt.DitherStrength := 0.0;
    Opt.Gamma := 1.00;
    Opt.Contrast := 1.00;
    Opt.Saturation := 1.00;
  end;

  // HQ export preset: keep UI-configurable ANSI tab settings (shadeblend, glyph smooth,
  // diffusion, etc.) but enable a heavier conversion pipeline during export.
  if (s = 'hqmode') or (s = 'hq') then
  begin
    // User asked for HQMode=2.
    Opt.HQMode := 2;
  end;

  // Mode-like styles (convenience)
  if s = 'cartoon' then
  begin
    Opt.Mode := rmCartoon;
    Opt.Ice := True;
    Opt.Dither := dmFS;
    Opt.DitherStrength := 0.9;
    Opt.Contrast := 1.10;
    Opt.Saturation := 1.15;
  end
  else if (s = 'colorbook') or (s = 'coloringbook') then
  begin
    Opt.Mode := rmColorBook;
    // Dither tends to create speckle edges; keep it off by default for clean regions.
    Opt.Dither := dmNone;
    Opt.DitherStrength := 0.0;
    Opt.Contrast := 1.15;
    Opt.Brightness := 1.00;
    Opt.Saturation := 1.05;
  end;


  if s = 'glyphfit' then
  begin
    Opt.Mode := rmGlyphFit;
    Opt.Dither := dmNone;
    Opt.DitherStrength := 0.0;
    Opt.Contrast := 1.12;
    Opt.Saturation := 1.05;
    Opt.GlyphSet := gsLines;
    Opt.GlyphSmooth := 0.15;
    Opt.ShadeBlend := 0.65;
  end;

  // ANSIrez-inspired preset: palette-matched, no dithering, with a 2x2 smoothing pass.
  if (s = 'ansirez') or (s = 'ansi-rez') then
  begin
    Opt.AnsiRezMode := True;
    Opt.AnsiRezFilter := afMedian;
    Opt.PaletteMatch := True;
    Opt.Dither := dmNone;
    Opt.DitherStrength := 0.0;
    // Keep the user's chosen Mode/Ice; just give a good default look.
    Opt.Contrast := 1.15;
    Opt.Saturation := 1.00;
    Opt.WinX := 3;
    Opt.WinY := 3;
  end;
end;


end.
