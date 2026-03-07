unit mainform;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, IniFiles, Math, Types,
  Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls, Spin, ComCtrls,
  LCLType,
  FPImage,
  fpjson, jsonparser,
  ansi_export_dialog, ansi_export_opts,
  img2bin_core, img2bin_types, img2bin_dosfont, img2bin_shaderlib,
  img2bin_tronicshade,
  img2bin_io,
  img2bin_patchlib, img2bin_palette, img2bin_gradients;

type
  // 8x16 tile samples (row-major 8*16 = 128)
  TRGBTile128 = array[0..127] of TRGB;

  TRampPair = record
    FG: Byte;
    BG: Byte;
  end;
  TRampPairArray = array of TRampPair;

  TMainForm = class(TForm)
  private
        FShownAbout: Boolean;
        FShowTronicReportAfterRender: Boolean;
    FTronicRetroPassCount: Integer; // 1 = normal, 4 = Extreme preset multi-pass

    // Optional custom palette used only for the pre-match stage (loaded from .hex).
    FPreMatchPalFile: string;
    FPreMatchPalette: TRGBArray;

    // Factory defaults snapshot (captured once after UI creation)
    FDefaultPresetIni: TStringList;

OpenDlg: TOpenDialog;
    SaveDlg: TSaveDialog;
    PresetOpenDlg: TOpenDialog;
    PresetSaveDlg: TSaveDialog;
    FontDlg: TFontDialog;
    PreMatchPalOpenDlg: TOpenDialog;

    // Bottom status bar (hotkeys reference)
    StatusBar: TStatusBar;

    // Auto-preview rendering (debounced) so the output updates when settings change.
    FUIReady: Boolean;
    FPreviewTimer: TTimer;
    FPreviewBusy: Boolean;
    FPreviewPending: Boolean;

    BtnOpen, BtnRender, BtnSave, BtnClearSel, BtnFont, BtnLoadPreset, BtnSavePreset: TButton;
    LblFont: TLabel;
    CbStyle, CbMode, CbDither, CbPalette, CbLook, CbMetric: TComboBox;
    CbGlyphSet: TComboBox;
    CbGradMode: TComboBox;
    CbGradSet: TComboBox;
    // Cell-level diffusion (regular modes)
    LblCellDiff: TLabel;
    CbCellDiffModel: TComboBox;
    SeCellDiffAmt: TSpinEdit;
    SeCellTone: TSpinEdit;

    ChkIce, ChkUseSel, ChkPalMatch: TCheckBox;
    LblPreMatchPal: TLabel;
    EdPreMatchPal: TEdit;
    BtnPreMatchPalBrowse: TButton;
    BtnPreMatchPalClear: TButton;
    LblPreMatchBayer: TLabel;
    TbPreMatchBayer: TTrackBar;
    // Global glyph bias weights (100=neutral)
    SeBlockUpWeight: TSpinEdit;
    SeBlockDownWeight: TSpinEdit;
    SeShadeBlockWeight: TSpinEdit;
    ChkBiosPreview: TCheckBox;
    ChkAnsiRez: TCheckBox;
    LblAnsiRezFilter: TLabel;
    CbAnsiRezFilter: TComboBox;
    LblGradMode: TLabel;
    LblGradSet: TLabel;

    // AutoShader (shader BIN / profiles)
    ShaderOpenDlg: TOpenDialog;
    ShaderProfileOpenDlg: TOpenDialog;
    ShaderProfileSaveDlg: TSaveDialog;
    LblShaderProfile: TLabel;
    CbShaderProfile: TComboBox;
    ChkUseShader: TCheckBox;
    ChkDosBoxModel: TCheckBox;
    ChkLearnShadeOnly: TCheckBox;
    BtnLoadShader: TButton;
    BtnShaderLoad: TButton;
    BtnShaderSave: TButton;
    BtnShaderNew: TButton;
    SeShaderRows: TSpinEdit;
    SeShaderPasses: TSpinEdit;
    SeShader3x3Pct: TSpinEdit;
    SeShaderBlocksPct: TSpinEdit;
    LblShaderInfo: TLabel;

    // PatchStyle (learned patchbook) controls
    PatchOpenDlg: TOpenDialog;
    PatchSaveDlg: TSaveDialog;
    ChkPatchStyle: TCheckBox;
    ChkPatch10: TCheckBox;
    ChkPatch5: TCheckBox;
    ChkPatch3: TCheckBox;
    SePatchLoops: TSpinEdit;
    SePatchMinMatch: TSpinEdit;
    RgPatchMode: TRadioGroup;
    BtnPatchLoad: TButton;
    BtnPatchSave: TButton;
    BtnPatchClear: TButton;
    ChkPatchBlocksOnly: TCheckBox;
    LblPatchInfo: TLabel;

    // Tronicshade controls (dedicated tab)
    BtnRenderTronic: TButton;
    CbTronicPreset : TComboBox;
    CbTronicRetroStyle: TComboBox;
    TbTronicRetroTexture: TTrackBar;
    LblTronicRetroTexture: TLabel;
    ChkTronicRetroBlocks: TCheckBox;
    BtnTronicLoad: TButton;
    BtnTronicSave: TButton;
    BtnTronicLoadANSI: TButton;
    SeTronicImportWeight: TSpinEdit;
    LblTronicImportWeight: TLabel;
    SeTronicImportPasses: TSpinEdit;
    LblTronicImportPasses: TLabel;
    ChkTronicImportMirrorH: TCheckBox;
    SeTronicStrength: TSpinEdit;
    // Legacy checkbox (maps to color metric = Luma only). Kept so old INI/settings don't break.
    ChkTronicLumaOnly: TCheckBox;
    SeTronicTone: TSpinEdit;
    ChkTronicAutoShader: TCheckBox;
    SeTronicWin: TSpinEdit;
    SeTronicStep: TSpinEdit;
    CbTronicDiffModel: TComboBox;
    SeTronicDiffAmt: TSpinEdit;
    CbTronicColorMetric: TComboBox;
    CbTronicGlyphSet: TComboBox; // glyph set used only for Tronicshade
    LblTronicStrength: TLabel;
    LblTronicTone: TLabel;
    LblTronicFile: TLabel;
    LblTronicLib: TLabel;
    LblTronicTip: TLabel;
    ChkTronicGlyphOnly: TCheckBox;

    ChkTronicEdgeShade: TCheckBox;
    TbTronicBlockThreshold: TTrackBar;
    LblTronicBlockThresholdVal: TLabel;
    TbTronicShadeWeight: TTrackBar;
    LblTronicShadeWeightVal: TLabel;
    ChkTronicCornersShadesOnly: TCheckBox;
    CbTronicEdgeSample: TComboBox;
    FTronicStyleFile: string;


    // AnsiLab (build/load style presets from ANSI art)
    TabAnsiLab: TTabSheet;
    AnsiLabScroll: TScrollBox;
    EdAnsiLabName: TEdit;
    BtnAnsiLabBuild: TButton;
    BtnAnsiLabLoadPreset: TButton;
    BtnAnsiLabApplyPreset: TButton;
    ChkAnsiLabTreatBlinkAsIce: TCheckBox;
    ChkAnsiLabMirrorH: TCheckBox;
    ChkAnsiLabLearnShadeOnly: TCheckBox;
    SeAnsiLabMaxRows: TSpinEdit;
    SeAnsiLabPasses: TSpinEdit;
    SeAnsiLabWeight: TSpinEdit;
    SeAnsiLabDedupeCap: TSpinEdit;
    MemoAnsiLab: TMemo;
    FLastAnsiLabPreset: string;


    // Progress UI (popup with progress bar + log memo)
    ProgForm: TForm;
    ProgBar: TProgressBar;
    ProgMemo: TMemo;
    ProgCancelBtn: TButton;
    ProgCancel: Boolean;
    ProgLastPct: Integer;
    ProgLastMsg: string;


    ProgLastPumpTick: QWord;
    FShaderFile: string;

    SeRows: TSpinEdit;
    SeCellW: TSpinEdit;
    SeWinX, SeWinY: TSpinEdit;

    FeAspect, FeGamma, FeContrast, FeSaturation, FeBrightness, FeDitherStrength: TFloatSpinEdit;
    FeGlyphSmooth: TFloatSpinEdit;
    FeShadeBlend: TFloatSpinEdit;

    SeColorMatch: TSpinEdit;

    // Fine color-matching tweak spinedits (YCbCr weights)
    LblYCbCrWeights: TLabel;
    SeYWeight, SeCbWeight, SeCrWeight: TSpinEdit;

    SrcBox: TPaintBox;
    OutScroll: TScrollBox;
    OutBox: TPaintBox;


    ScrollConvert: TScrollBox;
    ScrollHints: TScrollBox;
    LblStyle, LblMode, LblDither, LblPalette, LblLook, LblMetric: TLabel;
    LblGlyphSet, LblGlyphSmooth, LblShadeBlend, LblColorMatch: TLabel;
    LblRows, LblWinX, LblWinY, LblAspect, LblBrightness, LblGamma, LblContrast, LblSaturation, LblDitherStr, LblCellW: TLabel;
    LblInfo, LblSel: TLabel;
    Split: TSplitter;
    PanelLeft, PanelRight: TPanel;
    BtnPreReset: TButton;
    BtnPreGray: TButton;
    BtnPreSharpen: TButton;
    BtnPreBlur: TButton;
    BtnPreEdge: TButton;
    BtnPrePosterize: TButton;
    BtnPreConPlus: TButton;
    BtnPreConMinus: TButton;

    // Color hints (manual palette bias from sampled areas)
    CbHintColor: TComboBox;
    ChkHintUsePalette: TCheckBox;
    ChkRefitHintPalette: TCheckBox;
    SeHintStrength: TSpinEdit;
    SeHintTol: TSpinEdit;
	SeHintPickRadius: TSpinEdit;

    // Post-pass hint "snap" (applied after rendering)
    ChkHintPostFix: TCheckBox;
    SeHintPostPct: TSpinEdit;
    BtnAddHintFromSel: TButton;
	BtnPickHintDropper: TButton;
    BtnClearHints: TButton;
    MemoHints: TMemo;
    PbHintPalette: TPaintBox;
	LblHintPick: TLabel;

    // Shader Lab / Atlas (visualize shader ramps and FG/BG combos)
    AtlasTop: TPanel;
    AtlasScroll: TScrollBox;
    AtlasBox: TPaintBox;
    CbAtlasMode: TComboBox;
    ChkAtlasIce: TCheckBox;
    ChkAtlasShowGrid: TCheckBox;
    BtnAtlasRefresh: TButton;
    LblAtlas: TLabel;


    // Ramp builder + Tile explorer (Shader Lab)
    LabSplit: TSplitter;
    LabRight: TPanel;
    LabPages: TPageControl;
    TabRamp: TTabSheet;
    TabTile: TTabSheet;

    // Ramp Builder UI
    LblRamp: TLabel;
    LbRamp: TListBox;
    BtnRampClear: TButton;
    BtnRampRemove: TButton;

    // Tile Explorer UI
    LblTile: TLabel;
    LblTileHint: TLabel;
    SeTileX: TSpinEdit;
    SeTileY: TSpinEdit;
    ChkTile3x3: TCheckBox;
    BtnTileEval: TButton;
    PbTilePrev: TPaintBox;
    LbTileRes: TListBox;

    FAtlasBmp: TBitmap;
    FAtlasMode: Integer;



    FRampPairs: TRampPairArray;
    FSelCellX: Integer;
    FSelCellY: Integer;

    FCellSample: TFPMemoryImage;
    FCellSampleValid: Boolean;
    FTilePrevBmp: TBitmap;

	FPickHintMode: Boolean;

    FColorHints: TColorHintArray;

    FOrigImg: TFPMemoryImage;

    FFileName: string;
    FImg: TFPMemoryImage;
    FCells: TCellArray;
    FRows: Integer;

    FHasSel: Boolean;
    FSel: TRect;
    FDragging: Boolean;
    FDragStart: TPoint;
    FSrcBmp: TBitmap;
    FPreviewFont: TFont;

    procedure SetupUI;
    procedure CopyFPImage(const Src: TFPMemoryImage; Dest: TFPMemoryImage);
    procedure UpdateSrcPreviewFromFP;
    procedure ApplyPreFilter(AFilter: Integer);
    procedure DoPreFilter(Sender: TObject);
    procedure AboutOnce(Data: PtrInt);
    procedure UpdateInfo;

    procedure UpdateTronicInfo;
    procedure StartProgressUI(const Title: string);
    procedure EndProgressUI;
    procedure ProgressUpdate(Percent: Integer; const Msg: string);
    procedure ProgCancelClick(Sender: TObject);

    // Auto-preview rendering (silent, debounced)
    procedure SetupAutoPreview;
    procedure RequestPreviewRender;
    procedure PreviewTimerTick(Sender: TObject);

    // Common render core used by both the manual Render button and auto-preview.
    procedure RenderCore(const ShowProgress: Boolean; const AllowTronicReport: Boolean);

    procedure DoOpen(Sender: TObject);
    procedure DoRender(Sender: TObject);
    procedure DoSave(Sender: TObject);
    procedure DoClearSel(Sender: TObject);

    procedure SrcPaint(Sender: TObject);
    procedure SrcMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure SrcMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure SrcMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);

    procedure OutPaint(Sender: TObject);

    procedure LookChanged(Sender: TObject);
    procedure AnyOptionChanged(Sender: TObject);
    procedure BtnPreMatchPalBrowseClick(Sender: TObject);
    procedure BtnPreMatchPalClearClick(Sender: TObject);
    procedure EdPreMatchPalEditingDone(Sender: TObject);
    procedure UpdatePreMatchPaletteCache;
    procedure BtnLoadShaderClick(Sender: TObject);
    procedure BtnShaderLoadClick(Sender: TObject);
    procedure BtnShaderSaveClick(Sender: TObject);
    procedure BtnShaderNewClick(Sender: TObject);
    procedure BtnPatchLoadClick(Sender: TObject);
    procedure BtnPatchSaveClick(Sender: TObject);
    procedure BtnPatchClearClick(Sender: TObject);
    procedure BtnRenderTronicClick(Sender: TObject);
    procedure TronicRetroTextureChanged(Sender: TObject);
    procedure TronicPresetChanged(Sender: TObject);
    procedure BtnTronicLoadClick(Sender: TObject);
    procedure BtnTronicSaveClick(Sender: TObject);
    procedure BtnTronicLoadANSIClick(Sender: TObject);
    procedure BtnAnsiLabBuildClick(Sender: TObject);
    procedure BtnAnsiLabLoadPresetClick(Sender: TObject);
    procedure BtnAnsiLabApplyPresetClick(Sender: TObject);

    procedure AnsiLabLog(const S: string);
    procedure ShaderProfileChanged(Sender: TObject);
    procedure UpdateOutScroll;
    procedure DoPickFont(Sender: TObject);
    procedure DoToggleBiosPreview(Sender: TObject);
    procedure DoLoadPreset(Sender: TObject);
    procedure DoSavePreset(Sender: TObject);

    // Preset helpers (also used to snapshot factory defaults)
    procedure SavePresetToIni(ini: TCustomIniFile);
    procedure LoadPresetFromIni(ini: TCustomIniFile);
    procedure CaptureFactoryDefaults;
    procedure ResetAllSettingsToFactoryDefaults;
    procedure SavePresetToFile(const FN: string);

    procedure LoadPresetFromFile(const FN: string);

    procedure ApplyTronicPreset(idx: Integer);
    function GetOptions: TConvertOptions;

    function ColorFromRGB(const c: TRGB): TColor;
    function GetImageDrawRect: TRect;
    function ViewToImagePoint(const P: TPoint): TPoint;
    function ImageToViewRect(const R: TRect): TRect;
    function NormalizeRectLocal(const R: TRect): TRect;
    function AvgColorInRect(const Img: TFPCustomImage; const R: TRect): TRGB;
    procedure UpdateHintsUI;
    procedure UpdateGradientUI;
    procedure HintPalettePaint(Sender: TObject);
    procedure HintPaletteMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure DoAddHintFromSel(Sender: TObject);
	procedure DoTogglePickHintDropper(Sender: TObject);
	procedure AddHintFromPoint(const PImg: TPoint);
    procedure DoClearHints(Sender: TObject);

    // Shader Lab / Atlas
    procedure AtlasOptionsChanged(Sender: TObject);
    procedure AtlasPaint(Sender: TObject);
    procedure BuildAtlas;


    procedure AtlasMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure OutMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);

    procedure RampClearClick(Sender: TObject);
    procedure RampRemoveClick(Sender: TObject);
    procedure UpdateRampListUI;
    procedure AddRampPair(FG, BG: Byte);
    function AtlasHitTest(X, Y: Integer; out FG, BG: Integer): Boolean;

    procedure TileEvalClick(Sender: TObject);
    procedure TilePrevPaint(Sender: TObject);
    procedure EnsureCellSample;
    procedure ExtractTileSamples(CellX, CellY: Integer; Use3x3: Boolean; out aTile: TRGBTile128);
    function TileMatchPct(const a, b: TRGBTile128): Integer;
    procedure RenderGlyphTile(ch: Byte; fgIdx, bgIdx: Byte; out aTile: TRGBTile128);

    // Global hotkeys
    procedure MainFormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);

  public
    constructor Create(TheOwner: TComponent); override;
    destructor Destroy; override;
  end;

var
  MainFrm: TMainForm;

implementation

// Cross-platform output/config folders.
//
// Windows: keep everything alongside the executable in ./output
// Linux/macOS: use per-user config dir to avoid permission issues when installed system-wide.
function GetBaseOutputDir: string;
begin
  {$IFDEF Windows}
  Result := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + 'output' + PathDelim;
  {$ELSE}
  Result := IncludeTrailingPathDelimiter(GetAppConfigDir(False)) + 'output' + PathDelim;
  {$ENDIF}
  ForceDirectories(Result);
end;

function GetExportsDir: string;
begin
  // User-facing exports (.bin/.ans/.ansi) should go directly under ./output
  // rather than a subfolder.
  Result := GetBaseOutputDir;
end;

function GetStylesDir: string;
begin
  // ShaderLab “style profiles” live here.
  Result := GetBaseOutputDir + 'styles' + PathDelim;
  ForceDirectories(Result);
end;

function GetShadersDir: string;
begin
  // Blockshaders + Tronicshade files can live together.
  Result := GetBaseOutputDir + 'blockshaders' + PathDelim;
  ForceDirectories(Result);
end;

function GetPalettesDir: string;
begin
  Result := GetBaseOutputDir + 'palettes' + PathDelim;
  ForceDirectories(Result);
end;

function GetPresetsDir: string;
begin
  Result := GetBaseOutputDir + 'presets' + PathDelim;
  ForceDirectories(Result);
end;

procedure EnsureAppDirs;
begin
  // Force create all output subdirs up-front.
  GetBaseOutputDir;
  // Exports use the base output folder; we still create other subfolders.
  GetStylesDir;
  GetShadersDir;
  GetPalettesDir;
  GetPresetsDir;
end;


function TMainForm.ColorFromRGB(const c: TRGB): TColor;
begin
  Result := RGBToColor(c.R, c.G, c.B);
end;

procedure TMainForm.UpdateGradientUI;
var
  modeIdx: Integer;
begin
  if not Assigned(CbGradMode) or not Assigned(CbGradSet) or not Assigned(LblGradSet) then Exit;
  modeIdx := CbGradMode.ItemIndex;
  // Only "fixed" needs the set picker
  CbGradSet.Enabled := (modeIdx = 1);
  LblGradSet.Enabled := (modeIdx = 1);
end;

constructor TMainForm.Create(TheOwner: TComponent);
begin
  inherited Create(TheOwner);

  // Ensure our output folders exist on both Windows and Linux/macOS.
  EnsureAppDirs;

  Caption := 'rez2ans (80xN) - Crop + ANSI Preview';
  Width := 1200;
  Height := 760;

  FImg := nil;
  FRows := 0;
  FHasSel := False;
  FDragging := False;
	FPickHintMode := False;

  FShaderFile := '';
  FTronicRetroPassCount := 1;

  FDefaultPresetIni := nil;

  // Prevent option-change events from triggering auto-preview while we build the UI.
  FUIReady := False;
  FPreviewTimer := nil;
  FPreviewBusy := False;
  FPreviewPending := False;

  FSrcBmp := TBitmap.Create;
  FAtlasBmp := TBitmap.Create;
  FCellSample := nil;
  FCellSampleValid := False;
  FSelCellX := 0;
  FSelCellY := 0;
  SetLength(FRampPairs, 0);
  FAtlasMode := 0;
  FPreviewFont := TFont.Create;
  FPreviewFont.Name := 'Consolas';
  FPreviewFont.Style := [];
  FPreviewFont.Size := 10;

  FontDlg := TFontDialog.Create(Self);
  PresetOpenDlg := TOpenDialog.Create(Self);
  PresetOpenDlg.Filter := 'Preset (*.ini)|*.ini|All files|*.*';
  PresetOpenDlg.InitialDir := GetPresetsDir;
  PresetSaveDlg := TSaveDialog.Create(Self);
  PresetSaveDlg.Filter := 'Preset (*.ini)|*.ini|All files|*.*';
  PresetSaveDlg.InitialDir := GetPresetsDir;

  // Global hotkeys
  KeyPreview := True;
  OnKeyDown := @MainFormKeyDown;

  SetupUI;
  // Auto-preview (live re-render on every knob tweak) is intentionally disabled.
  // It was convenient, but too heavy for real-world use. Preview rendering is
  // now user-driven (F12 / Render button).
  FUIReady := True;
  UpdateInfo;
  UpdateHintsUI;

  // Snapshot the factory defaults once, so Alt+R can restore a true "clean slate"
  // without hardcoding every control's initial values.
  CaptureFactoryDefaults;

  // Show a simple About popup once on startup
  Application.QueueAsyncCall(@AboutOnce, 0);

end;

procedure TMainForm.MainFormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  // Hotkeys
  //   Alt+S = Save (ANSI/BIN)
  //   Alt+R = Reset ALL settings to factory defaults
  //   F12   = Render current mode (regular / tronicshade)
  //   F11   = Render Tronicshade (legacy)

  // Alt combos
  if (ssAlt in Shift) then
  begin
    case UpCase(Chr(Key)) of
      'S':
        begin
          DoSave(nil);
          Key := 0;
          Exit;
        end;
      'R':
        begin
          ResetAllSettingsToFactoryDefaults;
          Key := 0;
          Exit;
        end;
    end;
  end;

  // Function keys
  case Key of
    VK_F12:
      begin
        // Render "current mode": if the mode is tronicshade, use the tronic renderer.
        if Assigned(CbMode) and (CbMode.Items.IndexOf('tronicshade') >= 0) and
           (CbMode.ItemIndex = CbMode.Items.IndexOf('tronicshade')) then
        begin
          if Assigned(BtnRenderTronic) then BtnRenderTronic.Click
          else if Assigned(BtnRender) then BtnRender.Click;
        end
        else
        begin
          if Assigned(BtnRender) then BtnRender.Click;
        end;
        Key := 0;
      end;
    VK_F11:
      begin
        if Assigned(BtnRenderTronic) then BtnRenderTronic.Click;
        Key := 0;
      end;
  end;
end;

procedure TMainForm.AboutOnce(Data: PtrInt);
begin
  if FShownAbout then Exit;
 MessageDlg(
    'AnsiRezX',
    'Warning: using this software means you''re basically a test guinea pig 🐭.' + LineEnding +
    'No guarantees, no promises, and definitely no tears when it crashes 🔥.' + LineEnding +
    'rez2ans v .02  Beta (c) Creators Of Intense Art Software, where the only thing' + LineEnding +
    'we''re guaranteeing is a wild ride 😅.' + LineEnding + LineEnding +
    'Contact Sudden Death at' + LineEnding +
    'suddendeath@email.com or join our Discord https://diiscord.gg/jsncAM87',
    mtInformation,
    [mbOK],
    0
  );
end;


destructor TMainForm.Destroy;
begin
  if Assigned(FImg) then FImg.Free;
  if Assigned(FOrigImg) then FOrigImg.Free;
  FSrcBmp.Free;
  if Assigned(FAtlasBmp) then FAtlasBmp.Free;
  if Assigned(FPreviewFont) then FPreviewFont.Free;
  if Assigned(FCellSample) then FCellSample.Free;
  if Assigned(FTilePrevBmp) then FTilePrevBmp.Free;
  if Assigned(FDefaultPresetIni) then FDefaultPresetIni.Free;
  inherited Destroy;
end;

procedure TMainForm.SetupUI;
var
  PageControl: TPageControl;
  TabFile, TabAdjust, TabConvert, TabHints, TabAnsiRez, TabAnsiArt, TabTronic, TabCleanup, TabFilters: TTabSheet;
  FlowButtons, FlowPreRender: TFlowPanel;
  AnsiArtScroll: TScrollBox;
  Lbl: TLabel;
  SB: TScrollBox;
  GB: TGroupBox;
  PTop, PAction, PBody, PLeft, PRight, PRow, Cell: TPanel;
  CellA, CellB, CellC: TPanel;
  GBTrain, GBMatch, GBDiff, GBOpts, GBEdge: TGroupBox;
  SplitTronic: TSplitter;
  // NOTE: We avoid Delphi's TGridPanel (not present in many Lazarus installs).
  // "3-up" layouts are built from nested panels.
  FlowTmp: TFlowPanel;
  Y: Integer;
  TrNeedLeft, TrNeedRight, TrNeedBody, TrNeedTop: Integer;

  procedure Make3CellRow(AParent: TWinControl; AHeight: Integer; W0, W1: Integer;
    out C0, C1, C2: TPanel);
  var
    Row: TPanel;
  begin
    Row := TPanel.Create(TabTronic);
    Row.Parent := AParent;
    Row.Align := alTop;
    Row.Height := AHeight;
    Row.BevelOuter := bvNone;
    Row.BorderSpacing.Left := 8;
    Row.BorderSpacing.Right := 8;
    Row.BorderSpacing.Bottom := 6;

    C0 := TPanel.Create(TabTronic);
    C0.Parent := Row;
    C0.Align := alLeft;
    C0.Width := W0;
    C0.BevelOuter := bvNone;
    C0.BorderSpacing.Right := 8;

    C1 := TPanel.Create(TabTronic);
    C1.Parent := Row;
    C1.Align := alLeft;
    C1.Width := W1;
    C1.BevelOuter := bvNone;
    C1.BorderSpacing.Right := 8;

    C2 := TPanel.Create(TabTronic);
    C2.Parent := Row;
    C2.Align := alClient;
    C2.BevelOuter := bvNone;
  end;

  procedure Make3CheckRow(AParent: TWinControl; AHeight: Integer; W0, W1: Integer;
    out C0, C1, C2: TPanel);
  begin
    // Same as Make3CellRow, but a little tighter for checkboxes.
    Make3CellRow(AParent, AHeight, W0, W1, C0, C1, C2);
    C0.BorderSpacing.Right := 6;
    C1.BorderSpacing.Right := 6;
  end;
begin
  OpenDlg := TOpenDialog.Create(Self);
  PreMatchPalOpenDlg := TOpenDialog.Create(Self);
  PreMatchPalOpenDlg.Filter := 'Hex palette (*.hex)|*.hex|All files|*.*';
  PreMatchPalOpenDlg.InitialDir := GetPalettesDir;
  OpenDlg.Filter := 'Images (*.png;*.jpg;*.jpeg;*.bmp)|*.png;*.jpg;*.jpeg;*.bmp|All files|*.*';
  ShaderOpenDlg := TOpenDialog.Create(Self);
  ShaderOpenDlg.Options := ShaderOpenDlg.Options + [ofAllowMultiSelect];
  ShaderOpenDlg.InitialDir := GetExportsDir;
  // Named profile manager dialogs (JSON under the styles folder).
  ShaderProfileOpenDlg := TOpenDialog.Create(Self);
  ShaderProfileOpenDlg.Filter := 'Style profiles (*.json)|*.json|All files|*.*';
  ShaderProfileOpenDlg.Options := ShaderProfileOpenDlg.Options - [ofAllowMultiSelect];
  ShaderProfileOpenDlg.InitialDir := GetStylesDir;

  ShaderProfileSaveDlg := TSaveDialog.Create(Self);
  ShaderProfileSaveDlg.Filter := 'Style profiles (*.json)|*.json|All files|*.*';
  ShaderProfileSaveDlg.FilterIndex := 1;
  ShaderProfileSaveDlg.InitialDir := GetStylesDir;
  PatchOpenDlg := TOpenDialog.Create(Self);
  PatchOpenDlg.Filter := 'Patch library (*.pch)|*.pch|All files|*.*';
  PatchOpenDlg.InitialDir := GetShadersDir;
  PatchSaveDlg := TSaveDialog.Create(Self);
  PatchSaveDlg.Filter := 'Patch library (*.pch)|*.pch|All files|*.*';
  PatchSaveDlg.InitialDir := GetShadersDir;

  ShaderOpenDlg.Filter := 'Shader files (*.bin;*.ans;*.ansi)|*.bin;*.ans;*.ansi|TheDraw BIN (*.bin)|*.bin|ANSI (*.ans;*.ansi)|*.ans;*.ansi|All files|*.*';


  SaveDlg := TSaveDialog.Create(Self);
  SaveDlg.Filter := 'ANSI (*.ans;*.ansi)|*.ans;*.ansi|TheDraw BIN (*.bin)|*.bin|All files|*.*';
  SaveDlg.FilterIndex := 1;
  SaveDlg.InitialDir := GetExportsDir;

  PresetOpenDlg.InitialDir := GetPresetsDir;
  PresetSaveDlg.InitialDir := GetPresetsDir;

  { Main PageControl for tabs }
  PageControl := TPageControl.Create(Self);
  PageControl.Parent := Self;
  PageControl.Align := alTop;
  PageControl.Height := 200;

  { === TAB 1: FILE OPERATIONS === }
  TabFile := TTabSheet.Create(PageControl);
  TabFile.Caption := 'File && Render';
  TabFile.PageControl := PageControl;

  FlowButtons := TFlowPanel.Create(TabFile);
  FlowButtons.Parent := TabFile;
  FlowButtons.SetBounds(8, 8, 900, 40);
  FlowButtons.AutoWrap := False;
  FlowButtons.BevelOuter := bvNone;

  BtnOpen := TButton.Create(Self);
  BtnOpen.Parent := FlowButtons;
  BtnOpen.Caption := 'Open Image...';
  BtnOpen.AutoSize := True;
  BtnOpen.BorderSpacing.Around := 4;
  BtnOpen.OnClick := @DoOpen;

  BtnRender := TButton.Create(Self);
  BtnRender.Parent := FlowButtons;
  BtnRender.Caption := 'Render Preview';
  BtnRender.AutoSize := True;
  BtnRender.BorderSpacing.Around := 4;
  BtnRender.OnClick := @DoRender;

  BtnSave := TButton.Create(Self);
  BtnSave.Parent := FlowButtons;
  BtnSave.Caption := 'Save...';
  BtnSave.AutoSize := True;
  BtnSave.BorderSpacing.Around := 4;
  BtnSave.OnClick := @DoSave;

  BtnClearSel := TButton.Create(Self);
  BtnClearSel.Parent := FlowButtons;
  BtnClearSel.Caption := 'Clear Selection';
  BtnClearSel.AutoSize := True;
  BtnClearSel.BorderSpacing.Around := 4;
  BtnClearSel.OnClick := @DoClearSel;

  BtnFont := TButton.Create(Self);
  BtnFont.Parent := FlowButtons;
  BtnFont.Caption := 'Preview Font...';
  BtnFont.AutoSize := True;
  BtnFont.BorderSpacing.Around := 4;
  BtnFont.BorderSpacing.Left := 12;
  BtnFont.OnClick := @DoPickFont;

  LblFont := TLabel.Create(Self);
  LblFont.Parent := FlowButtons;
  LblFont.AutoSize := True;
  LblFont.BorderSpacing.Around := 8;
  LblFont.Caption := 'Font: ' + FPreviewFont.Name;

  ChkBiosPreview := TCheckBox.Create(Self);
  ChkBiosPreview.Parent := FlowButtons;
  ChkBiosPreview.Caption := 'BIOS preview';
  ChkBiosPreview.AutoSize := True;
  ChkBiosPreview.BorderSpacing.Around := 8;
  ChkBiosPreview.Checked := True;
  ChkBiosPreview.OnChange := @DoToggleBiosPreview;
  DoToggleBiosPreview(nil);

  BtnLoadPreset := TButton.Create(Self);
  BtnLoadPreset.Parent := FlowButtons;
  BtnLoadPreset.Caption := 'Load Preset...';
  BtnLoadPreset.AutoSize := True;
  BtnLoadPreset.BorderSpacing.Around := 4;
  BtnLoadPreset.BorderSpacing.Left := 12;
  BtnLoadPreset.OnClick := @DoLoadPreset;

  BtnSavePreset := TButton.Create(Self);
  BtnSavePreset.Parent := FlowButtons;
  BtnSavePreset.Caption := 'Save Preset...';
  BtnSavePreset.AutoSize := True;
  BtnSavePreset.BorderSpacing.Around := 4;
  BtnSavePreset.OnClick := @DoSavePreset;

  // Checkboxes
  ChkUseSel := TCheckBox.Create(Self);
  ChkUseSel.Parent := TabFile;
  ChkUseSel.SetBounds(12, 56, 200, 22);
  ChkUseSel.Caption := 'Render selection only';
  ChkUseSel.Checked := True;

  // Rows control
  LblRows := TLabel.Create(Self);
  LblRows.Parent := TabFile;
  LblRows.SetBounds(12, 88, 100, 18);
  LblRows.Caption := 'Rows (0=auto)';

  SeRows := TSpinEdit.Create(Self);
  SeRows.Parent := TabFile;
  SeRows.SetBounds(12, 108, 100, 24);
  SeRows.MinValue := 0;
  SeRows.MaxValue := 5000;
  SeRows.Value := 0;

  LblCellW := TLabel.Create(Self);
  LblCellW.Parent := TabFile;
  LblCellW.SetBounds(130, 88, 100, 18);
  LblCellW.Caption := 'CellW (pixels)';

  SeCellW := TSpinEdit.Create(Self);
  SeCellW.Parent := TabFile;
  SeCellW.SetBounds(130, 108, 100, 24);
  SeCellW.MinValue := 4;
  SeCellW.MaxValue := 32;
  SeCellW.Value := 8;

  // Info labels
  LblInfo := TLabel.Create(Self);
  LblInfo.Parent := TabFile;
  LblInfo.SetBounds(12, 142, 700, 18);
  LblInfo.Caption := '';

  LblSel := TLabel.Create(Self);
  LblSel.Parent := TabFile;
  LblSel.SetBounds(12, 160, 700, 18);
  LblSel.Caption := '';

  { === TAB 2: IMAGE ADJUSTMENTS === }
  TabAdjust := TTabSheet.Create(PageControl);
  TabAdjust.Caption := 'Image Adjustments';
  TabAdjust.PageControl := PageControl;

  Y := 12;

  // WinX and WinY
  LblWinX := TLabel.Create(Self);
  LblWinX.Parent := TabAdjust;
  LblWinX.SetBounds(12, Y, 80, 18);
  LblWinX.Caption := 'WinX';

  SeWinX := TSpinEdit.Create(Self);
  SeWinX.Parent := TabAdjust;
  SeWinX.SetBounds(12, Y + 20, 80, 24);
  SeWinX.MinValue := 1;
  SeWinX.MaxValue := 128;
  SeWinX.Value := 4;

  LblWinY := TLabel.Create(Self);
  LblWinY.Parent := TabAdjust;
  LblWinY.SetBounds(110, Y, 80, 18);
  LblWinY.Caption := 'WinY';

  SeWinY := TSpinEdit.Create(Self);
  SeWinY.Parent := TabAdjust;
  SeWinY.SetBounds(110, Y + 20, 80, 24);
  SeWinY.MinValue := 1;
  SeWinY.MaxValue := 128;
  SeWinY.Value := 4;

  LblAspect := TLabel.Create(Self);
  LblAspect.Parent := TabAdjust;
  LblAspect.SetBounds(210, Y, 100, 18);
  LblAspect.Caption := 'Aspect';

  FeAspect := TFloatSpinEdit.Create(Self);
  FeAspect.Parent := TabAdjust;
  FeAspect.SetBounds(210, Y + 20, 100, 24);
  FeAspect.MinValue := 0.10;
  FeAspect.MaxValue := 1.50;
  FeAspect.Increment := 0.01;
  FeAspect.Value := 0.55;

  LblGamma := TLabel.Create(Self);
  LblGamma.Parent := TabAdjust;
  LblGamma.SetBounds(330, Y, 100, 18);
  LblGamma.Caption := 'Gamma';

  FeGamma := TFloatSpinEdit.Create(Self);
  FeGamma.Parent := TabAdjust;
  FeGamma.SetBounds(330, Y + 20, 100, 24);
  FeGamma.MinValue := 0.10;
  FeGamma.MaxValue := 3.00;
  FeGamma.Increment := 0.05;
  FeGamma.Value := 1.00;

  LblContrast := TLabel.Create(Self);
  LblContrast.Parent := TabAdjust;
  LblContrast.SetBounds(450, Y, 100, 18);
  LblContrast.Caption := 'Contrast';

  FeContrast := TFloatSpinEdit.Create(Self);
  FeContrast.Parent := TabAdjust;
  FeContrast.SetBounds(450, Y + 20, 100, 24);
  FeContrast.MinValue := 0.10;
  FeContrast.MaxValue := 3.00;
  FeContrast.Increment := 0.05;
  FeContrast.Value := 1.10;

  Y := 70;

  LblSaturation := TLabel.Create(Self);
  LblSaturation.Parent := TabAdjust;
  LblSaturation.SetBounds(12, Y, 100, 18);
  LblSaturation.Caption := 'Saturation';

  FeSaturation := TFloatSpinEdit.Create(Self);
  FeSaturation.Parent := TabAdjust;
  FeSaturation.SetBounds(12, Y + 20, 100, 24);
  FeSaturation.MinValue := 0.00;
  FeSaturation.MaxValue := 3.00;
  FeSaturation.Increment := 0.05;
  FeSaturation.Value := 1.05;

  LblDitherStr := TLabel.Create(Self);
  LblDitherStr.Parent := TabAdjust;
  LblDitherStr.SetBounds(130, Y, 120, 18);
  LblDitherStr.Caption := 'Dither Strength';

  FeDitherStrength := TFloatSpinEdit.Create(Self);
  FeDitherStrength.Parent := TabAdjust;
  FeDitherStrength.SetBounds(130, Y + 20, 120, 24);
  FeDitherStrength.MinValue := 0.0;
  FeDitherStrength.MaxValue := 3.0;
  FeDitherStrength.Increment := 0.05;
  FeDitherStrength.Value := 1.00;

  // Brightness (moved from ANSIrez tab into Image Adjustments)
  LblBrightness := TLabel.Create(Self);
  LblBrightness.Parent := TabAdjust;
  LblBrightness.SetBounds(260, Y, 120, 18);
  LblBrightness.Caption := 'Brightness';

  FeBrightness := TFloatSpinEdit.Create(Self);
  FeBrightness.Parent := TabAdjust;
  FeBrightness.SetBounds(260, Y + 20, 120, 24);
  FeBrightness.MinValue := 0.10;
  FeBrightness.MaxValue := 3.00;
  FeBrightness.Increment := 0.05;
  FeBrightness.Value := 1.00;


  

  // Hook adjust controls
  FeGamma.OnChange := @AnyOptionChanged;
  FeContrast.OnChange := @AnyOptionChanged;
  FeSaturation.OnChange := @AnyOptionChanged;
  FeBrightness.OnChange := @AnyOptionChanged;
  FeDitherStrength.OnChange := @AnyOptionChanged;

{ === TAB 3: CONVERSION SETTINGS === }
  TabConvert := TTabSheet.Create(PageControl);
  TabConvert.Caption := 'Conversion Settings';
  TabConvert.PageControl := PageControl;

	  // Make Conversion Settings tab scrollable (small windows / HiDPI)
	  // This also prevents controls like the custom-palette Bayer slider from being clipped.
	  ScrollConvert := TScrollBox.Create(Self);
	  ScrollConvert.Parent := TabConvert;
	  ScrollConvert.Align := alClient;
	  ScrollConvert.BorderStyle := bsNone;
	  ScrollConvert.VertScrollBar.Tracking := True;
	  ScrollConvert.HorzScrollBar.Tracking := True;

  Y := 12;

  // Style
  LblStyle := TLabel.Create(Self);
  LblStyle.Parent := ScrollConvert;
  LblStyle.SetBounds(12, Y, 120, 18);
  LblStyle.Caption := 'Style';

  CbStyle := TComboBox.Create(Self);
  CbStyle.Parent := ScrollConvert;
  CbStyle.SetBounds(12, Y + 20, 120, 24);
  CbStyle.Style := csDropDownList;
  CbStyle.Items.Add('ice');
  CbStyle.Items.Add('acid');
  CbStyle.Items.Add('plain');
  CbStyle.Items.Add('cartoon');
  CbStyle.Items.Add('colorbook');
  CbStyle.Items.Add('glyphfit');
  // Export-only high quality conversion preset (slow, better matching).
  CbStyle.Items.Add('hqmode');
  CbStyle.ItemIndex := 0;
  // Style changes should update the output preview.
  CbStyle.OnChange := @AnyOptionChanged;
  CbStyle.OnSelect := @AnyOptionChanged;

  // Mode
  LblMode := TLabel.Create(Self);
  LblMode.Parent := ScrollConvert;
  LblMode.SetBounds(150, Y, 120, 18);
  LblMode.Caption := 'Mode';

  CbMode := TComboBox.Create(Self);
  CbMode.Parent := ScrollConvert;
  CbMode.SetBounds(150, Y + 20, 120, 24);
  CbMode.Style := csDropDownList;
  CbMode.Items.Add('hybrid');
  CbMode.Items.Add('hires');
  CbMode.Items.Add('shades');
  CbMode.Items.Add('cartoon');
  CbMode.Items.Add('colorbook');
  CbMode.Items.Add('glyphfit');
  CbMode.Items.Add('autoshader');
  CbMode.Items.Add('tronicshade');
  CbMode.ItemIndex := 0;
  // Mode changes should update the output preview.
  CbMode.OnChange := @AnyOptionChanged;
  CbMode.OnSelect := @AnyOptionChanged;

  // Dither
  LblDither := TLabel.Create(Self);
  LblDither.Parent := ScrollConvert;
  LblDither.SetBounds(290, Y, 120, 18);
  LblDither.Caption := 'Dither';

  CbDither := TComboBox.Create(Self);
  CbDither.Parent := ScrollConvert;
  CbDither.SetBounds(290, Y + 20, 120, 24);
  CbDither.Style := csDropDownList;
  CbDither.Items.Add('fs');
  CbDither.Items.Add('atkinson');
  CbDither.Items.Add('jjn');
  CbDither.Items.Add('stucki');
  CbDither.Items.Add('sierra-lite');
  CbDither.Items.Add('bayer4');
  CbDither.Items.Add('none');
  CbDither.ItemIndex := 0;
  CbDither.OnChange := @AnyOptionChanged;
  CbDither.OnSelect := @AnyOptionChanged;
  // Dither changes should update the output preview.

  // Palette
  LblPalette := TLabel.Create(Self);
  LblPalette.Parent := ScrollConvert;
  LblPalette.SetBounds(430, Y, 120, 18);
  LblPalette.Caption := 'Palette';

  CbPalette := TComboBox.Create(Self);
  CbPalette.Parent := ScrollConvert;
  CbPalette.SetBounds(430, Y + 20, 120, 24);
  CbPalette.Style := csDropDownList;
  CbPalette.Items.Add('vga16');
  CbPalette.Items.Add('win16');
  CbPalette.Items.Add('gray16');
  CbPalette.ItemIndex := 0;
  CbPalette.OnChange := @AnyOptionChanged;
  CbPalette.OnSelect := @AnyOptionChanged;

  // ---------------------------------------------------------------------
  // Cell-level diffusion (regular modes)
  // This is separate from the pixel/quantizer dither dropdown.
  LblCellDiff := TLabel.Create(Self);
  LblCellDiff.Parent := ScrollConvert;
  LblCellDiff.SetBounds(590, Y, 220, 18);
  LblCellDiff.Caption := 'Cell diffusion (grid)';

  CbCellDiffModel := TComboBox.Create(Self);
  CbCellDiffModel.Parent := ScrollConvert;
  CbCellDiffModel.SetBounds(590, Y + 20, 190, 24);
  CbCellDiffModel.Style := csDropDownList;
  CbCellDiffModel.Items.Add('off');
  CbCellDiffModel.Items.Add('ordered (bayer 4x4)');
  CbCellDiffModel.Items.Add('ordered (bayer 8x8)');
  CbCellDiffModel.Items.Add('floyd–steinberg');
  CbCellDiffModel.Items.Add('jarvis–judice–ninke');
  CbCellDiffModel.Items.Add('atkinson');
  CbCellDiffModel.Items.Add('sierra lite');
  CbCellDiffModel.ItemIndex := 0;
  CbCellDiffModel.OnChange := @AnyOptionChanged;
  CbCellDiffModel.OnSelect := @AnyOptionChanged;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := ScrollConvert;
  Lbl.SetBounds(790, Y, 80, 18);
  Lbl.Caption := 'Amt';

  SeCellDiffAmt := TSpinEdit.Create(Self);
  SeCellDiffAmt.Parent := ScrollConvert;
  SeCellDiffAmt.SetBounds(790, Y + 20, 60, 24);
  SeCellDiffAmt.MinValue := 0;
  SeCellDiffAmt.MaxValue := 100;
  SeCellDiffAmt.Value := 35;
  SeCellDiffAmt.OnChange := @AnyOptionChanged;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := ScrollConvert;
  Lbl.SetBounds(860, Y, 80, 18);
  Lbl.Caption := 'Tone';

  SeCellTone := TSpinEdit.Create(Self);
  SeCellTone.Parent := ScrollConvert;
  SeCellTone.SetBounds(860, Y + 20, 60, 24);
  SeCellTone.MinValue := 0;
  SeCellTone.MaxValue := 100;
  SeCellTone.Value := 0;
  SeCellTone.OnChange := @AnyOptionChanged;

  Y := 70;

  // Look
  LblLook := TLabel.Create(Self);
  LblLook.Parent := ScrollConvert;
  LblLook.SetBounds(12, Y, 120, 18);
  LblLook.Caption := 'Look';

  CbLook := TComboBox.Create(Self);
  CbLook.Parent := ScrollConvert;
  CbLook.SetBounds(12, Y + 20, 120, 24);
  CbLook.Style := csDropDownList;
  CbLook.Items.Add('realistic');
  CbLook.Items.Add('cartoon');
  CbLook.Items.Add('lineart');
  CbLook.ItemIndex := 0;
  CbLook.OnChange := @LookChanged;

  // Color Metric
  LblMetric := TLabel.Create(Self);
  LblMetric.Parent := ScrollConvert;
  LblMetric.SetBounds(150, Y, 280, 18);
  LblMetric.Caption := 'Color metric';

  CbMetric := TComboBox.Create(Self);
  CbMetric.Parent := ScrollConvert;
  CbMetric.SetBounds(150, Y + 20, 280, 24);
  CbMetric.Style := csDropDownList;
  // Keep item order in sync with TColorMetric in img2bin_types.pas.
  // New items are appended to preserve older INI index values.
  CbMetric.Items.Add('rgb (fast)');
  CbMetric.Items.Add('redmean (perceptual, recommended)');
  CbMetric.Items.Add('ycbcr (luma/chroma, weighted)');
  CbMetric.Items.Add('linear rgb (gamma-corrected)');
  CbMetric.Items.Add('cie xyz (d65)');
  CbMetric.Items.Add('cie lab ΔE76');
  CbMetric.Items.Add('cie lab ΔE94 (graphics)');
  CbMetric.Items.Add('cie lab ΔE2000');
  CbMetric.Items.Add('oklab');
  CbMetric.Items.Add('oklch (hue-aware)');
  CbMetric.Items.Add('hsv adaptive (hue-protected)');
  CbMetric.ItemIndex := 1;
  CbMetric.OnChange := @AnyOptionChanged;
  CbMetric.OnSelect := @AnyOptionChanged;

  Y := 128;

  // Checkboxes
  ChkIce := TCheckBox.Create(Self);
  ChkIce.Parent := ScrollConvert;
  ChkIce.SetBounds(12, Y, 200, 22);
  ChkIce.Caption := 'iCE (bright background)';
  ChkIce.Checked := True;

  ChkPalMatch := TCheckBox.Create(Self);
  ChkPalMatch.Parent := ScrollConvert;
  // Pre-match palette matching (optional external .hex file)
  // Place the file picker controls on the same line, to the right of the checkbox.
  ChkPalMatch.SetBounds(12, Y + 26, 220, 22);
  ChkPalMatch.Caption := 'Pre-match to palette (better matching)';
  ChkPalMatch.Checked := True;
  LblPreMatchPal := TLabel.Create(Self);
  LblPreMatchPal.Parent := ScrollConvert;
  // Keep the old label for clarity, but hide it by default since the edit + buttons live next to the checkbox.
  LblPreMatchPal.SetBounds(12, Y + 52, 260, 18);
  LblPreMatchPal.Caption := 'Custom pre-match palette file (.hex, optional)';
  LblPreMatchPal.Visible := False;

  EdPreMatchPal := TEdit.Create(Self);
  EdPreMatchPal.Parent := ScrollConvert;
  EdPreMatchPal.SetBounds(240, Y + 24, 260, 24);
  EdPreMatchPal.Text := '';
  EdPreMatchPal.Hint := 'Optional: choose a .hex palette file (2..256 colors). Leave blank to use built-in pre-match.';
  EdPreMatchPal.ShowHint := True;
  EdPreMatchPal.OnEditingDone := @EdPreMatchPalEditingDone;

  BtnPreMatchPalBrowse := TButton.Create(Self);
  BtnPreMatchPalBrowse.Parent := ScrollConvert;
  BtnPreMatchPalBrowse.SetBounds(508, Y + 22, 80, 26);
  BtnPreMatchPalBrowse.Caption := 'Browse...';
  BtnPreMatchPalBrowse.OnClick := @BtnPreMatchPalBrowseClick;

  BtnPreMatchPalClear := TButton.Create(Self);
  BtnPreMatchPalClear.Parent := ScrollConvert;
  BtnPreMatchPalClear.SetBounds(596, Y + 22, 60, 26);
  BtnPreMatchPalClear.Caption := 'Clear';
  BtnPreMatchPalClear.OnClick := @BtnPreMatchPalClearClick;

  // Bayer 4x4 strength slider (applies only when a custom .hex palette is loaded)
  // NOTE: Keep this within the default window width. Anchor the slider so it resizes on narrow/wide windows.
  LblPreMatchBayer := TLabel.Create(Self);
  LblPreMatchBayer.Parent := ScrollConvert;
  LblPreMatchBayer.SetBounds(12, Y + 52, 640, 18);
  LblPreMatchBayer.Caption := 'Custom palette Bayer strength: 50%';
  LblPreMatchBayer.Anchors := [akLeft, akTop, akRight];

  TbPreMatchBayer := TTrackBar.Create(Self);
  TbPreMatchBayer.Parent := ScrollConvert;
  // Place directly under the file picker, and let it stretch with the form.
  TbPreMatchBayer.SetBounds(12, Y + 70, 640, 32);
  TbPreMatchBayer.Anchors := [akLeft, akTop, akRight];
  TbPreMatchBayer.Min := 0;
  TbPreMatchBayer.Max := 100;
  TbPreMatchBayer.Position := 50;
  TbPreMatchBayer.Frequency := 10;
  TbPreMatchBayer.TickStyle := tsNone;
  TbPreMatchBayer.Hint := '0 disables ordered dithering for custom pre-match palettes. Higher values increase the Bayer 4x4 strength.';
  TbPreMatchBayer.ShowHint := True;
  TbPreMatchBayer.OnChange := @AnyOptionChanged;

  
  // Block / shade glyph weights (100=neutral)
  Lbl := TLabel.Create(Self);
  Lbl.Parent := ScrollConvert;
  Lbl.SetBounds(12, Y + 108, 640, 18);
  Lbl.Caption := 'Block / shade weights (100=neutral)';

  // Up block ▀
  Lbl := TLabel.Create(Self);
  Lbl.Parent := ScrollConvert;
  Lbl.SetBounds(12, Y + 130, 60, 18);
  Lbl.Caption := 'Up ▀';

  SeBlockUpWeight := TSpinEdit.Create(Self);
  SeBlockUpWeight.Parent := ScrollConvert;
  SeBlockUpWeight.SetBounds(72, Y + 126, 60, 24);
  SeBlockUpWeight.MinValue := 0;
  SeBlockUpWeight.MaxValue := 200;
  SeBlockUpWeight.Value := 100;
  SeBlockUpWeight.Hint := 'Preference for the upper-half block (▀). 100=neutral, >100 prefer, <100 discourage.';
  SeBlockUpWeight.ShowHint := True;
  SeBlockUpWeight.OnChange := @AnyOptionChanged;

  // Down block ▄
  Lbl := TLabel.Create(Self);
  Lbl.Parent := ScrollConvert;
  Lbl.SetBounds(150, Y + 130, 70, 18);
  Lbl.Caption := 'Down ▄';

  SeBlockDownWeight := TSpinEdit.Create(Self);
  SeBlockDownWeight.Parent := ScrollConvert;
  SeBlockDownWeight.SetBounds(224, Y + 126, 60, 24);
  SeBlockDownWeight.MinValue := 0;
  SeBlockDownWeight.MaxValue := 200;
  SeBlockDownWeight.Value := 100;
  SeBlockDownWeight.Hint := 'Preference for the lower-half block (▄). 100=neutral, >100 prefer, <100 discourage.';
  SeBlockDownWeight.ShowHint := True;
  SeBlockDownWeight.OnChange := @AnyOptionChanged;

  // Shade blocks ░▒▓
  Lbl := TLabel.Create(Self);
  Lbl.Parent := ScrollConvert;
  Lbl.SetBounds(310, Y + 130, 90, 18);
  Lbl.Caption := 'Shade ░▒▓';

  SeShadeBlockWeight := TSpinEdit.Create(Self);
  SeShadeBlockWeight.Parent := ScrollConvert;
  SeShadeBlockWeight.SetBounds(406, Y + 126, 60, 24);
  SeShadeBlockWeight.MinValue := 0;
  SeShadeBlockWeight.MaxValue := 200;
  SeShadeBlockWeight.Value := 100;
  SeShadeBlockWeight.Hint := 'Preference for shade blocks (░▒▓). 100=neutral, >100 prefer, <100 discourage.';
  SeShadeBlockWeight.ShowHint := True;
  SeShadeBlockWeight.OnChange := @AnyOptionChanged;
ChkPalMatch.OnClick := @AnyOptionChanged;

  // AutoShader (shader BIN)
  // NOTE: Do not read conversion options here. This is UI construction code.

  { === TAB 5: COLOR HINTS (MANUAL PALETTE BIAS) === }
TabHints := TTabSheet.Create(PageControl);
TabHints.Caption := 'Color Hints';
TabHints.PageControl := PageControl;


// Make Color Hints tab scrollable (small windows / low-res displays)
ScrollHints := TScrollBox.Create(Self);
ScrollHints.Parent := TabHints;
ScrollHints.Align := alClient;
ScrollHints.BorderStyle := bsNone;
ScrollHints.VertScrollBar.Tracking := True;
ScrollHints.HorzScrollBar.Visible := False;

Lbl := TLabel.Create(Self);
Lbl.Parent := ScrollHints;
Lbl.AutoSize := False;
Lbl.SetBounds(12, 12, 900, 36);
Lbl.Caption :=
  'Teach the converter your intended ANSI colors. ' +
  '1) Drag a selection box on the image (left panel). ' +
  '2) Choose the ANSI color here. ' +
  '3) Click "Add hint from selection". ' +
  'Hints bias palette matching so pastel/saturated colors don''t wash out.';

PbHintPalette := TPaintBox.Create(Self);
PbHintPalette.Parent := ScrollHints;
PbHintPalette.SetBounds(12, 52, 360, 40);
PbHintPalette.OnPaint := @HintPalettePaint;
PbHintPalette.OnMouseDown := @HintPaletteMouseDown;
PbHintPalette.Cursor := crHandPoint;

Lbl := TLabel.Create(Self);
Lbl.Parent := ScrollHints;
Lbl.SetBounds(12, 98, 260, 18);
Lbl.Caption := 'ANSI color to bias toward';

CbHintColor := TComboBox.Create(Self);
CbHintColor.Parent := ScrollHints;
CbHintColor.SetBounds(12, 118, 220, 24);
CbHintColor.Style := csDropDownList;
CbHintColor.Items.Add('0  Black');
CbHintColor.Items.Add('1  Blue');
CbHintColor.Items.Add('2  Green');
CbHintColor.Items.Add('3  Cyan');
CbHintColor.Items.Add('4  Red');
CbHintColor.Items.Add('5  Magenta');
CbHintColor.Items.Add('6  Brown');
CbHintColor.Items.Add('7  Light Gray');
CbHintColor.Items.Add('8  Dark Gray');
CbHintColor.Items.Add('9  Light Blue');
CbHintColor.Items.Add('10 Light Green');
CbHintColor.Items.Add('11 Light Cyan');
CbHintColor.Items.Add('12 Light Red');
CbHintColor.Items.Add('13 Light Magenta (pink)');
CbHintColor.Items.Add('14 Yellow');
CbHintColor.Items.Add('15 White');
CbHintColor.ItemIndex := 13;
CbHintColor.OnChange := @AnyOptionChanged;
  CbHintColor.OnSelect := @AnyOptionChanged;

Lbl := TLabel.Create(Self);
Lbl.Parent := ScrollHints;
Lbl.SetBounds(250, 98, 180, 18);
Lbl.Caption := 'Hint tolerance (0..255)';

SeHintTol := TSpinEdit.Create(Self);
SeHintTol.Parent := ScrollHints;
SeHintTol.SetBounds(250, 118, 180, 24);
SeHintTol.MinValue := 0;
SeHintTol.MaxValue := 255;
// Defaults tuned for "Hint → temporary palette (VGAPAL)" mode.
// Tolerance is only used for sampling / outlier filtering (not distance boosting).
SeHintTol.Value := 50;
SeHintTol.Hint := 'Higher tolerance = bias applies to a wider range of similar colors.';
SeHintTol.ShowHint := True;
SeHintTol.OnChange := @AnyOptionChanged;

Lbl := TLabel.Create(Self);
Lbl.Parent := ScrollHints;
Lbl.SetBounds(450, 98, 180, 18);
Lbl.Caption := 'Hint strength';

SeHintStrength := TSpinEdit.Create(Self);
SeHintStrength.Parent := ScrollHints;
SeHintStrength.SetBounds(450, 118, 180, 24);
SeHintStrength.MinValue := 0;
SeHintStrength.MaxValue := 50000;
// Strength is used as a weight when averaging hint samples into the temporary palette.
SeHintStrength.Value := 100;
SeHintStrength.Hint := 'Higher strength = stronger push toward the selected ANSI color.';
SeHintStrength.ShowHint := True;
SeHintStrength.OnChange := @AnyOptionChanged;

ChkHintUsePalette := TCheckBox.Create(Self);
ChkHintUsePalette.Parent := ScrollHints;
ChkHintUsePalette.AutoSize := False;
ChkHintUsePalette.SetBounds(650, 118, 380, 24);
ChkHintUsePalette.Caption := 'Use hints to build a temporary palette (VGAPAL)';
ChkHintUsePalette.Checked := True;
ChkHintUsePalette.Hint := 'Recommended: hinted ANSI indexes use the sampled RGB as their palette entry when matching.';
ChkHintUsePalette.ShowHint := True;
ChkHintUsePalette.OnChange := @AnyOptionChanged;
  ChkHintUsePalette.OnClick := @AnyOptionChanged;


ChkRefitHintPalette := TCheckBox.Create(Self);
ChkRefitHintPalette.Parent := ScrollHints;
ChkRefitHintPalette.AutoSize := False;
ChkRefitHintPalette.SetBounds(650, 142, 420, 24);
ChkRefitHintPalette.Caption := 'Refit hinted palette each pass (gentle)';
ChkRefitHintPalette.Checked := True;
ChkRefitHintPalette.Hint := 'When using multiple passes, slightly adjust ONLY hinted ANSI palette entries toward the colors actually used. Helps convergence without palette drift.';
ChkRefitHintPalette.ShowHint := True;
ChkRefitHintPalette.OnChange := @AnyOptionChanged;
  ChkRefitHintPalette.OnClick := @AnyOptionChanged;

// Optional: post-pass "snap" using hints (fix near-miss colors after rendering)
ChkHintPostFix := TCheckBox.Create(Self);
ChkHintPostFix.Parent := ScrollHints;
ChkHintPostFix.AutoSize := False;
ChkHintPostFix.SetBounds(650, 166, 420, 24);
ChkHintPostFix.Caption := 'Post-fix colors using hints (final pass)';
ChkHintPostFix.Checked := True;
ChkHintPostFix.Hint := 'After rendering, if a cell''s sampled color is very close to a hinted color, snap FG/BG to that ANSI index.';
ChkHintPostFix.ShowHint := True;
ChkHintPostFix.OnChange := @AnyOptionChanged;
  ChkHintPostFix.OnClick := @AnyOptionChanged;

Lbl := TLabel.Create(Self);
Lbl.Parent := ScrollHints;
Lbl.AutoSize := False;
Lbl.SetBounds(650, 190, 200, 18);
Lbl.Caption := 'Post-fix match % (0..100)';

SeHintPostPct := TSpinEdit.Create(Self);
SeHintPostPct.Parent := ScrollHints;
SeHintPostPct.SetBounds(650, 210, 120, 24);
SeHintPostPct.MinValue := 0;
SeHintPostPct.MaxValue := 100;
SeHintPostPct.Value := 90;
SeHintPostPct.Hint := 'Higher = more strict. 90 means only very close cells are snapped.';
SeHintPostPct.ShowHint := True;
SeHintPostPct.OnChange := @AnyOptionChanged;

BtnAddHintFromSel := TButton.Create(Self);
BtnAddHintFromSel.Parent := ScrollHints;
BtnAddHintFromSel.SetBounds(12, 152, 220, 30);
BtnAddHintFromSel.Caption := 'Add hint from selection';
BtnAddHintFromSel.OnClick := @DoAddHintFromSel;

	BtnPickHintDropper := TButton.Create(Self);
	BtnPickHintDropper.Parent := ScrollHints;
	BtnPickHintDropper.SetBounds(12, 188, 220, 30);
	BtnPickHintDropper.Caption := 'Dropper: OFF (click image)';
	BtnPickHintDropper.OnClick := @DoTogglePickHintDropper;
	BtnPickHintDropper.Hint := 'Turn on, then click the image preview to sample a color and create a hint.';
	BtnPickHintDropper.ShowHint := True;

	Lbl := TLabel.Create(Self);
	Lbl.Parent := ScrollHints;
	Lbl.SetBounds(250, 190, 180, 18);
	Lbl.Caption := 'Dropper radius (px)';

	SeHintPickRadius := TSpinEdit.Create(Self);
	SeHintPickRadius.Parent := ScrollHints;
	SeHintPickRadius.SetBounds(250, 210, 180, 24);
	SeHintPickRadius.MinValue := 0;
	SeHintPickRadius.MaxValue := 64;
	SeHintPickRadius.Value := 4;
	SeHintPickRadius.Hint := '0 = single pixel; higher averages a small square around the click.';
	SeHintPickRadius.ShowHint := True;

	LblHintPick := TLabel.Create(Self);
	LblHintPick.Parent := ScrollHints;
	LblHintPick.AutoSize := False;
	// Keep space at the far right for the hint post-fix controls.
	LblHintPick.SetBounds(450, 190, 190, 42);
	LblHintPick.Caption := 'Tip: Turn on Dropper, then click the image preview to add a hint.';
	LblHintPick.WordWrap := True;

BtnClearHints := TButton.Create(Self);
BtnClearHints.Parent := ScrollHints;
BtnClearHints.SetBounds(250, 152, 180, 30);
BtnClearHints.Caption := 'Clear hints';
BtnClearHints.OnClick := @DoClearHints;

MemoHints := TMemo.Create(Self);
MemoHints.Parent := ScrollHints;
MemoHints.SetBounds(12, 250, 900, 220);
MemoHints.Anchors := [akLeft, akTop, akRight, akBottom];
MemoHints.ReadOnly := True;
MemoHints.ScrollBars := ssVertical;
MemoHints.WordWrap := False;

{ === TAB 5: ANSI ART (GLYPHFIT) === }
  TabAnsiArt := TTabSheet.Create(PageControl);
  TabAnsiArt.Caption := 'ANSI Art';
  TabAnsiArt.PageControl := PageControl;

  AnsiArtScroll := TScrollBox.Create(TabAnsiArt);
  AnsiArtScroll.Parent := TabAnsiArt;
  AnsiArtScroll.Align := alClient;
  AnsiArtScroll.BorderStyle := bsNone;
  AnsiArtScroll.AutoScroll := True;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := AnsiArtScroll;
  Lbl.SetBounds(12, 12, 900, 18);
  Lbl.Caption := 'GlyphFit converts images by matching real DOS CP437 glyph shapes (good for rounded edges and shading).';

  LblGlyphSet := TLabel.Create(Self);
  LblGlyphSet.Parent := AnsiArtScroll;
  LblGlyphSet.SetBounds(12, 42, 160, 18);
  LblGlyphSet.Caption := 'Glyph set';

  CbGlyphSet := TComboBox.Create(Self);
  CbGlyphSet.Parent := AnsiArtScroll;
  CbGlyphSet.SetBounds(12, 62, 200, 24);
  CbGlyphSet.Style := csDropDownList;
  CbGlyphSet.Items.Add('blocks');
  CbGlyphSet.Items.Add('shading');
  CbGlyphSet.Items.Add('ansiblocks');
  CbGlyphSet.Items.Add('ansiblocks-pixel');
  CbGlyphSet.Items.Add('lines');
  CbGlyphSet.Items.Add('full');
  CbGlyphSet.Items.Add('ascii');
  CbGlyphSet.Items.Add('tronic (shade+blocks)');
  // Default to "lines"
  CbGlyphSet.ItemIndex := Ord(gsLines);
  CbGlyphSet.OnChange := @AnyOptionChanged;
  CbGlyphSet.OnSelect := @AnyOptionChanged;

  // Gradient/ramp restriction for glyphs (helps keep "pink" from getting lost, etc.)
  LblGradMode := TLabel.Create(Self);
  LblGradMode.Parent := AnsiArtScroll;
  LblGradMode.SetBounds(450, 42, 200, 18);
  LblGradMode.Caption := 'Gradient mode';

  CbGradMode := TComboBox.Create(Self);
  CbGradMode.Parent := AnsiArtScroll;
  CbGradMode.SetBounds(450, 62, 200, 24);
  CbGradMode.Style := csDropDownList;
  CbGradMode.Items.Add('off (use glyph set)');
  CbGradMode.Items.Add('fixed');
  CbGradMode.Items.Add('auto (per-cell)');
  CbGradMode.ItemIndex := 0;
  CbGradMode.OnChange := @AnyOptionChanged;
  CbGradMode.OnSelect := @AnyOptionChanged;

  LblGradSet := TLabel.Create(Self);
  LblGradSet.Parent := AnsiArtScroll;
  LblGradSet.SetBounds(450, 96, 300, 18);
  LblGradSet.Caption := 'Gradient set (fixed)';

  CbGradSet := TComboBox.Create(Self);
  CbGradSet.Parent := AnsiArtScroll;
  CbGradSet.SetBounds(450, 116, 260, 24);
  CbGradSet.Style := csDropDownList;
  GradientFillNames(CbGradSet.Items);
  if CbGradSet.Items.Count > 0 then
    CbGradSet.ItemIndex := 2
  else
    CbGradSet.ItemIndex := 0;
  CbGradSet.OnChange := @AnyOptionChanged;
  CbGradSet.OnSelect := @AnyOptionChanged;

  UpdateGradientUI;

  LblGlyphSmooth := TLabel.Create(Self);
  LblGlyphSmooth.Parent := AnsiArtScroll;
  LblGlyphSmooth.SetBounds(230, 42, 220, 18);
  LblGlyphSmooth.Caption := 'Smoothing (neighbor bias)';

  FeGlyphSmooth := TFloatSpinEdit.Create(Self);
  FeGlyphSmooth.Parent := AnsiArtScroll;
  FeGlyphSmooth.SetBounds(230, 62, 140, 24);
  FeGlyphSmooth.MinValue := 0.0;
  FeGlyphSmooth.MaxValue := 2.0;
  FeGlyphSmooth.Increment := 0.05;
  FeGlyphSmooth.Value := 0.15;
  FeGlyphSmooth.OnChange := @AnyOptionChanged;

  LblShadeBlend := TLabel.Create(Self);
  LblShadeBlend.Parent := AnsiArtScroll;
  LblShadeBlend.SetBounds(230, 96, 260, 18);
  LblShadeBlend.Caption := 'Shade blend (color extension, 0..1)';

  FeShadeBlend := TFloatSpinEdit.Create(Self);
  FeShadeBlend.Parent := AnsiArtScroll;
  FeShadeBlend.SetBounds(230, 116, 140, 24);
  FeShadeBlend.MinValue := 0.0;
  FeShadeBlend.MaxValue := 1.0;
  FeShadeBlend.Increment := 0.05;
  FeShadeBlend.Value := 0.65;
  FeShadeBlend.OnChange := @AnyOptionChanged;

  LblColorMatch := TLabel.Create(Self);
  LblColorMatch.Parent := AnsiArtScroll;
  LblColorMatch.SetBounds(12, 96, 200, 18);
  LblColorMatch.Caption := 'Color match % (hue priority)';

  SeColorMatch := TSpinEdit.Create(Self);
  SeColorMatch.Parent := AnsiArtScroll;
  SeColorMatch.SetBounds(12, 116, 200, 24);
  SeColorMatch.MinValue := 50;
  SeColorMatch.MaxValue := 200;
  SeColorMatch.Value := 130;
  SeColorMatch.OnChange := @AnyOptionChanged;

  // Fine-tune YCbCr matching (helps skin tones and saturated reds/blues in DOSBox)
  LblYCbCrWeights := TLabel.Create(Self);
  LblYCbCrWeights.Parent := AnsiArtScroll;
  LblYCbCrWeights.SetBounds(12, 148, 520, 18);
  LblYCbCrWeights.Caption := 'YCbCr weights % (Y / Cb / Cr)  - default 100 / 100 / 100';

  SeYWeight := TSpinEdit.Create(Self);
  SeYWeight.Parent := AnsiArtScroll;
  SeYWeight.SetBounds(12, 168, 70, 24);
  SeYWeight.MinValue := 50;
  SeYWeight.MaxValue := 300;
  SeYWeight.Value := 100;
  SeYWeight.Hint := 'Y (luma) weight: higher favors brightness match';
  SeYWeight.ShowHint := True;
  SeYWeight.OnChange := @AnyOptionChanged;

  SeCbWeight := TSpinEdit.Create(Self);
  SeCbWeight.Parent := AnsiArtScroll;
  SeCbWeight.SetBounds(90, 168, 70, 24);
  SeCbWeight.MinValue := 50;
  SeCbWeight.MaxValue := 300;
  SeCbWeight.Value := 110;
  SeCbWeight.Hint := 'Cb (blue/yellow) chroma weight: higher preserves blues';
  SeCbWeight.ShowHint := True;
  SeCbWeight.OnChange := @AnyOptionChanged;

  SeCrWeight := TSpinEdit.Create(Self);
  SeCrWeight.Parent := AnsiArtScroll;
  SeCrWeight.SetBounds(168, 168, 70, 24);
  SeCrWeight.MinValue := 50;
  SeCrWeight.MaxValue := 300;
  SeCrWeight.Value := 120;
  SeCrWeight.Hint := 'Cr (red/cyan) chroma weight: higher preserves reds / skin';
  SeCrWeight.ShowHint := True;
  SeCrWeight.OnChange := @AnyOptionChanged;

// AutoShader (shader BIN) controls
// Shader profile selector (toon/death/ascii/realstyle)
LblShaderProfile := TLabel.Create(Self);
LblShaderProfile.Parent := AnsiArtScroll;
LblShaderProfile.SetBounds(12, 204, 200, 18);
LblShaderProfile.Caption := 'Shader style';

CbShaderProfile := TComboBox.Create(Self);
CbShaderProfile.Parent := AnsiArtScroll;
CbShaderProfile.SetBounds(12, 224, 200, 24);
  // Allow typing a new profile name (e.g. "sudndeath", "tempus").
  // Profiles are stored as JSON files in the styles folder (created if missing).
  CbShaderProfile.Style := csDropDown;
ShaderFillProfileNames(CbShaderProfile.Items);
CbShaderProfile.ItemIndex := CbShaderProfile.Items.IndexOf(ShaderActiveProfileName);
if CbShaderProfile.ItemIndex < 0 then CbShaderProfile.ItemIndex := 0;
CbShaderProfile.OnChange := @ShaderProfileChanged;

// Explicit profile management buttons (Load / Save / New)
BtnShaderLoad := TButton.Create(Self);
BtnShaderLoad.Parent := AnsiArtScroll;
BtnShaderLoad.SetBounds(220, 224, 60, 24);
BtnShaderLoad.Caption := 'Load';
BtnShaderLoad.Hint := 'Load a TronicShade/Shader style profile from the styles folder';
BtnShaderLoad.ShowHint := True;
BtnShaderLoad.OnClick := @BtnShaderLoadClick;

BtnShaderSave := TButton.Create(Self);
BtnShaderSave.Parent := AnsiArtScroll;
BtnShaderSave.SetBounds(284, 224, 60, 24);
BtnShaderSave.Caption := 'Save';
BtnShaderSave.Hint := 'Save the current style profile to the styles folder';
BtnShaderSave.ShowHint := True;
BtnShaderSave.OnClick := @BtnShaderSaveClick;

BtnShaderNew := TButton.Create(Self);
BtnShaderNew.Parent := AnsiArtScroll;
BtnShaderNew.SetBounds(348, 224, 60, 24);
BtnShaderNew.Caption := 'New';
BtnShaderNew.Hint := 'Clear the current profile (start fresh)';
BtnShaderNew.ShowHint := True;
BtnShaderNew.OnClick := @BtnShaderNewClick;


ChkUseShader := TCheckBox.Create(Self);
ChkUseShader.Parent := AnsiArtScroll;
  ChkUseShader.SetBounds(12, 274, 360, 22);
ChkUseShader.Caption := 'Use shader BIN (curated FG/BG ramps)';
ChkUseShader.OnChange := @AnyOptionChanged;
  ChkUseShader.OnClick := @AnyOptionChanged;



// Multi-pass refinement for Shade/AutoShader/GlyphFit
Lbl := TLabel.Create(Self);
Lbl.Parent := AnsiArtScroll;
// Place refinement controls below shader import/summary to avoid overlap
Lbl.SetBounds(12, 400, 200, 18);
Lbl.Caption := 'AutoShader passes';

SeShaderPasses := TSpinEdit.Create(Self);
SeShaderPasses.Parent := AnsiArtScroll;
SeShaderPasses.SetBounds(12, 420, 200, 24);
SeShaderPasses.MinValue := 1;
SeShaderPasses.MaxValue := 8;
SeShaderPasses.Value := 4;
SeShaderPasses.Hint := 'Run multiple refinement passes (higher = closer match, slower).';
SeShaderPasses.ShowHint := True;
SeShaderPasses.OnChange := @AnyOptionChanged;

// AutoShader quality controls
Lbl := TLabel.Create(Self);
Lbl.Parent := AnsiArtScroll;
Lbl.SetBounds(12, 448, 260, 18);
Lbl.Caption := 'Use 3x3 neighborhood below match %';

SeShader3x3Pct := TSpinEdit.Create(Self);
SeShader3x3Pct.Parent := AnsiArtScroll;
SeShader3x3Pct.SetBounds(12, 468, 200, 24);
SeShader3x3Pct.MinValue := 0;
SeShader3x3Pct.MaxValue := 100;
SeShader3x3Pct.Value := 70;
SeShader3x3Pct.Hint := 'If the cell match is below this %, refine block/shade colors using a 3x3 neighborhood average. 0 = off.';
SeShader3x3Pct.ShowHint := True;
SeShader3x3Pct.OnChange := @AnyOptionChanged;

Lbl := TLabel.Create(Self);
Lbl.Parent := AnsiArtScroll;
Lbl.SetBounds(12, 496, 260, 18);
Lbl.Caption := 'Prefer blocks if block match % ≥';

SeShaderBlocksPct := TSpinEdit.Create(Self);
SeShaderBlocksPct.Parent := AnsiArtScroll;
SeShaderBlocksPct.SetBounds(12, 516, 200, 24);
SeShaderBlocksPct.MinValue := 0;
SeShaderBlocksPct.MaxValue := 100;
SeShaderBlocksPct.Value := 88;
SeShaderBlocksPct.Hint := 'If ░▒▓█ can match the cell at or above this %, pick blocks instead of ASCII. 0 = off.';
SeShaderBlocksPct.ShowHint := True;
SeShaderBlocksPct.OnChange := @AnyOptionChanged;

ChkDosBoxModel := TCheckBox.Create(Self);
ChkDosBoxModel.Parent := AnsiArtScroll;
  ChkDosBoxModel.SetBounds(12, 252, 460, 22);
  ChkDosBoxModel.Caption := 'DOSBox model (recommended for DOSBox output)';
ChkDosBoxModel.Checked := True;
ChkDosBoxModel.OnChange := @AnyOptionChanged;
  ChkDosBoxModel.OnClick := @AnyOptionChanged;

Lbl := TLabel.Create(Self);
Lbl.Parent := AnsiArtScroll;
  Lbl.SetBounds(12, 298, 260, 18);
Lbl.Caption := 'Shader rows to read (top N rows)';

SeShaderRows := TSpinEdit.Create(Self);
SeShaderRows.Parent := AnsiArtScroll;
  SeShaderRows.SetBounds(12, 318, 120, 24);
SeShaderRows.MinValue := 1;
SeShaderRows.MaxValue := 500;
SeShaderRows.Value := 200;
SeShaderRows.OnChange := @AnyOptionChanged;

BtnLoadShader := TButton.Create(Self);
BtnLoadShader.Parent := AnsiArtScroll;
  BtnLoadShader.SetBounds(150, 314, 180, 28);
BtnLoadShader.Caption := 'Import shader (BIN/ANS)...';

BtnLoadShader.OnClick := @BtnLoadShaderClick;

ChkLearnShadeOnly := TCheckBox.Create(Self);
ChkLearnShadeOnly.Parent := AnsiArtScroll;
  ChkLearnShadeOnly.SetBounds(12, 348, 520, 22);
ChkLearnShadeOnly.Caption := 'Learn shading glyphs only when importing (recommended)';
ChkLearnShadeOnly.Checked := True;

LblShaderInfo := TLabel.Create(Self);
LblShaderInfo.Parent := AnsiArtScroll;
  LblShaderInfo.SetBounds(12, 374, 900, 18);
LblShaderInfo.Caption := ShaderSummary;



  { === TAB: TRONICSHADE === }
  TabTronic := TTabSheet.Create(PageControl);
  TabTronic.Caption := 'Tronicshade';
  TabTronic.PageControl := PageControl;

  SB := TScrollBox.Create(TabTronic);
  SB.Parent := TabTronic;
  SB.Align := alClient;
  SB.BorderStyle := bsNone;
  SB.AutoScroll := True;

  GB := TGroupBox.Create(TabTronic);
  GB.Parent := SB;
  GB.Caption := 'Tronicshade (char-driven bias / "dither-like" mode)';
  // NOTE: This tab is built at runtime (no .lfm). When the root groupbox is
  // aligned alTop inside a scrollbox, Lazarus will NOT auto-size it.
  // If Height is left at the default, the content below the tip (including
  // the controls can end up clipped and appear "missing".
  GB.Align := alTop;
  GB.Height := 100; // will be recomputed after building controls
  GB.BorderSpacing.Around := 8;

  // --- Action row (full width) ---
// Top-level "retro stylizer" controls for Tronicshade (Hybrid + stylizer).
// Built to avoid overlap at different DPI/widths:
// - Left side wraps (FlowPanel)
// - Render button is pinned to the right
PAction := TPanel.Create(TabTronic);
PAction.Parent := GB;
PAction.Align := alTop;
PAction.BevelOuter := bvNone;
PAction.AutoSize := True;
PAction.BorderSpacing.Left := 8;
PAction.BorderSpacing.Right := 8;
PAction.BorderSpacing.Bottom := 8;

// Right: Render button (pinned)
PTop := TPanel.Create(TabTronic);
PTop.Parent := PAction;
PTop.Align := alRight;
PTop.BevelOuter := bvNone;
PTop.AutoSize := True;
PTop.BorderSpacing.Left := 8;

BtnRenderTronic := TButton.Create(TabTronic);
BtnRenderTronic.Parent := PTop;
BtnRenderTronic.Caption := 'Render Tronicshade';
BtnRenderTronic.Height := 34;
BtnRenderTronic.Width := 170;
BtnRenderTronic.Align := alTop;
BtnRenderTronic.OnClick := @BtnRenderTronicClick;

// Left: Style/Texture controls (wraps when narrow)
PRow := TPanel.Create(TabTronic);
PRow.Parent := PAction;
PRow.Align := alClient;
PRow.BevelOuter := bvNone;

FlowTmp := TFlowPanel.Create(TabTronic);
FlowTmp.Parent := PRow;
FlowTmp.Align := alClient;
FlowTmp.BevelOuter := bvNone;
FlowTmp.AutoWrap := True;
	// Lazarus TFlowPanel doesn't expose VCL-style HorzSpacing/VertSpacing on all versions.
	// Use a little padding here; per-control BorderSpacing can be added later if desired.
	FlowTmp.BorderSpacing.Around := 4;

	// Presets (Hybrid + Retro)
	Lbl := TLabel.Create(TabTronic);
	Lbl.Parent := FlowTmp;
	Lbl.Caption := 'Preset:';
	Lbl.Layout := tlCenter;

	CbTronicPreset := TComboBox.Create(TabTronic);
	CbTronicPreset.Parent := FlowTmp;
	CbTronicPreset.Style := csDropDownList;
	CbTronicPreset.Items.Add('Hybrid Clean');
	CbTronicPreset.Items.Add('CRT Soft');
	CbTronicPreset.Items.Add('DOS Photo');
	CbTronicPreset.Items.Add('VGA Crunch');
	CbTronicPreset.Items.Add('Block Poster');
	CbTronicPreset.Items.Add('Neon Bright');
	CbTronicPreset.Items.Add('Scanline Classic');
	CbTronicPreset.Items.Add('Retro Heavy');
	CbTronicPreset.Items.Add('ANSI Art Mode');
	CbTronicPreset.Items.Add('Rounded');
	CbTronicPreset.Items.Add('Extreme (4-Pass)');
	CbTronicPreset.ItemIndex := 1; // CRT Soft feels like a good default
	CbTronicPreset.Width := 160;
	CbTronicPreset.OnChange := @TronicPresetChanged;

Lbl := TLabel.Create(TabTronic);
Lbl.Parent := FlowTmp;
Lbl.Caption := 'Style:';
Lbl.Layout := tlCenter;

CbTronicRetroStyle := TComboBox.Create(TabTronic);
CbTronicRetroStyle.Parent := FlowTmp;
CbTronicRetroStyle.Style := csDropDownList;
CbTronicRetroStyle.Items.Add('Neutral');
CbTronicRetroStyle.Items.Add('Blocky');
CbTronicRetroStyle.Items.Add('CGA Crunch');
CbTronicRetroStyle.Items.Add('Grainy');
CbTronicRetroStyle.Items.Add('Scanline');
CbTronicRetroStyle.ItemIndex := 3; // default: Grainy
CbTronicRetroStyle.Width := 120;

Lbl := TLabel.Create(TabTronic);
Lbl.Parent := FlowTmp;
Lbl.Caption := 'Texture:';
Lbl.Layout := tlCenter;

TbTronicRetroTexture := TTrackBar.Create(TabTronic);
TbTronicRetroTexture.Parent := FlowTmp;
TbTronicRetroTexture.Orientation := trHorizontal;
TbTronicRetroTexture.Min := 0;
TbTronicRetroTexture.Max := 100;
TbTronicRetroTexture.Position := 15; // default: subtle retro
TbTronicRetroTexture.TickStyle := tsNone;
TbTronicRetroTexture.Width := 190;
TbTronicRetroTexture.Height := 34;
TbTronicRetroTexture.OnChange := @TronicRetroTextureChanged;

LblTronicRetroTexture := TLabel.Create(TabTronic);
LblTronicRetroTexture.Parent := FlowTmp;
LblTronicRetroTexture.Caption := '15';
LblTronicRetroTexture.Layout := tlCenter;

ChkTronicRetroBlocks := TCheckBox.Create(TabTronic);
ChkTronicRetroBlocks.Parent := FlowTmp;
ChkTronicRetroBlocks.Caption := 'Include blocks (full block)';
ChkTronicRetroBlocks.Checked := True;
ChkTronicRetroBlocks.AutoSize := True;

// --- Body: left library/training, right render/options ---
  PBody := TPanel.Create(TabTronic);
  PBody.Parent := GB;
  PBody.Align := alClient;
  PBody.BevelOuter := bvNone;
  PBody.BorderSpacing.Around := 8;

  PLeft := TPanel.Create(TabTronic);
  PLeft.Parent := PBody;
  PLeft.Align := alLeft;
  PLeft.Width := 300;
  PLeft.Constraints.MinWidth := 240;
  PLeft.Constraints.MaxWidth := 420;
  PLeft.BevelOuter := bvNone;
  PLeft.BorderSpacing.Right := 12;

  SplitTronic := TSplitter.Create(TabTronic);
  SplitTronic.Parent := PBody;
  SplitTronic.Align := alLeft;
  SplitTronic.Width := 6;

  PRight := TPanel.Create(TabTronic);
  PRight.Parent := PBody;
  PRight.Align := alClient;
  PRight.BevelOuter := bvNone;

  // =========================
  // LEFT: Library / Training
  // =========================
  GBTrain := TGroupBox.Create(TabTronic);
  GBTrain.Parent := PLeft;
  GBTrain.Align := alTop;
  GBTrain.Caption := 'Library / Training';
  GBTrain.Height := 260;
  GBTrain.BorderSpacing.Around := 0;

  FlowTmp := TFlowPanel.Create(TabTronic);
  FlowTmp.Parent := GBTrain;
  FlowTmp.Align := alTop;
  FlowTmp.Height := 34;
  FlowTmp.AutoWrap := False;
  FlowTmp.BevelOuter := bvNone;
  FlowTmp.BorderSpacing.Around := 8;

  BtnTronicLoad := TButton.Create(TabTronic);
  BtnTronicLoad.Parent := FlowTmp;
  BtnTronicLoad.Caption := 'Load...';
  BtnTronicLoad.AutoSize := True;
  BtnTronicLoad.BorderSpacing.Right := 6;
  BtnTronicLoad.OnClick := @BtnTronicLoadClick;

  BtnTronicSave := TButton.Create(TabTronic);
  BtnTronicSave.Parent := FlowTmp;
  BtnTronicSave.Caption := 'Save...';
  BtnTronicSave.AutoSize := True;
  BtnTronicSave.OnClick := @BtnTronicSaveClick;

  BtnTronicLoadANSI := TButton.Create(TabTronic);
  BtnTronicLoadANSI.Parent := GBTrain;
  BtnTronicLoadANSI.Align := alTop;
  BtnTronicLoadANSI.Height := 28;
  BtnTronicLoadANSI.Caption := 'Load ANSI...';
  BtnTronicLoadANSI.BorderSpacing.Around := 8;
  BtnTronicLoadANSI.OnClick := @BtnTronicLoadANSIClick;

  // 3-up row: weight / passes / mirror (grid built from panels)
  Make3CellRow(GBTrain, 62, 95, 95, CellA, CellB, CellC);

  // Cell 0: Weight
  // (Cell is first panel returned)

  LblTronicImportWeight := TLabel.Create(TabTronic);
  LblTronicImportWeight.Parent := CellA;
  LblTronicImportWeight.Align := alTop;
  LblTronicImportWeight.AutoSize := False;
  LblTronicImportWeight.Height := 18;
  LblTronicImportWeight.Caption := 'Weight';

  SeTronicImportWeight := TSpinEdit.Create(TabTronic);
  SeTronicImportWeight.Parent := CellA;
  SeTronicImportWeight.Align := alTop;
  SeTronicImportWeight.Width := 90;
  SeTronicImportWeight.MinValue := 1;
  SeTronicImportWeight.MaxValue := 50;
  SeTronicImportWeight.Value := 1;

  // Cell 1: Passes
  Cell := CellB;

  LblTronicImportPasses := TLabel.Create(TabTronic);
  LblTronicImportPasses.Parent := Cell;
  LblTronicImportPasses.Align := alTop;
  LblTronicImportPasses.AutoSize := False;
  LblTronicImportPasses.Height := 18;
  LblTronicImportPasses.Caption := 'Passes';

  SeTronicImportPasses := TSpinEdit.Create(TabTronic);
  SeTronicImportPasses.Parent := Cell;
  SeTronicImportPasses.Align := alTop;
  SeTronicImportPasses.Width := 90;
  SeTronicImportPasses.MinValue := 1;
  SeTronicImportPasses.MaxValue := 20;
  SeTronicImportPasses.Value := 1;

  // Cell 2: Mirror
  ChkTronicImportMirrorH := TCheckBox.Create(TabTronic);
  ChkTronicImportMirrorH.Parent := CellC;
  ChkTronicImportMirrorH.Align := alTop;
  ChkTronicImportMirrorH.Caption := 'Mirror H';
  ChkTronicImportMirrorH.ShowHint := True;
  ChkTronicImportMirrorH.Hint := 'Augment: mirror horizontal (learn mirrored patterns too)';
  ChkTronicImportMirrorH.Checked := False;
  ChkTronicImportMirrorH.BorderSpacing.Top := 20;

  LblTronicFile := TLabel.Create(TabTronic);
  LblTronicFile.Parent := GBTrain;
  LblTronicFile.Align := alTop;
  LblTronicFile.AutoSize := False;
  LblTronicFile.WordWrap := True;
  LblTronicFile.Height := 34;
  LblTronicFile.BorderSpacing.Around := 8;
  LblTronicFile.Caption := 'Style: (none)';

  LblTronicLib := TLabel.Create(TabTronic);
  LblTronicLib.Parent := GBTrain;
  LblTronicLib.Align := alTop;
  LblTronicLib.AutoSize := False;
  LblTronicLib.WordWrap := True;
  LblTronicLib.Height := 42;
  LblTronicLib.BorderSpacing.Left := 8;
  LblTronicLib.BorderSpacing.Right := 8;
  LblTronicLib.BorderSpacing.Bottom := 8;
  LblTronicLib.Caption := 'Lib size: 10x10=0'#13#10'5x5=0  3x3=0';

  // =========================
  // RIGHT: Render / Options
  // =========================

  // --- Core matching: 3 fields per row ---
  GBMatch := TGroupBox.Create(TabTronic);
  GBMatch.Parent := PRight;
  GBMatch.Align := alTop;
  GBMatch.Caption := 'Core';
  GBMatch.Height := 190;
  GBMatch.BorderSpacing.Bottom := 10;

  // Core row 1: Strength / Tone / Color metric
  Make3CellRow(GBMatch, 78, 210, 210, CellA, CellB, CellC);

  // (0) Strength
  Cell := CellA;
  LblTronicStrength := TLabel.Create(TabTronic);
  LblTronicStrength.Parent := Cell; LblTronicStrength.Align := alTop; LblTronicStrength.Height := 18;
  LblTronicStrength.Caption := 'Strength %';
  SeTronicStrength := TSpinEdit.Create(TabTronic);
  SeTronicStrength.Parent := Cell; SeTronicStrength.Align := alTop; SeTronicStrength.Width := 100;
  SeTronicStrength.MinValue := 0; SeTronicStrength.MaxValue := 200; SeTronicStrength.Value := 100;
  SeTronicStrength.OnChange := @AnyOptionChanged;

  // (1) Tone
  Cell := CellB;
  LblTronicTone := TLabel.Create(TabTronic);
  LblTronicTone.Parent := Cell; LblTronicTone.Align := alTop; LblTronicTone.Height := 18;
  LblTronicTone.Caption := 'Tone fit %';
  SeTronicTone := TSpinEdit.Create(TabTronic);
  SeTronicTone.Parent := Cell; SeTronicTone.Align := alTop; SeTronicTone.Width := 100;
  SeTronicTone.MinValue := 0; SeTronicTone.MaxValue := 100; SeTronicTone.Value := 35;
  SeTronicTone.OnChange := @AnyOptionChanged;

  // (2) Color metric
  Cell := CellC;
  Lbl := TLabel.Create(TabTronic);
  Lbl.Parent := Cell; Lbl.Align := alTop; Lbl.Height := 18;
  Lbl.Caption := 'Color metric';
  CbTronicColorMetric := TComboBox.Create(TabTronic);
  CbTronicColorMetric.Parent := Cell; CbTronicColorMetric.Align := alTop; CbTronicColorMetric.Style := csDropDownList;
  CbTronicColorMetric.Items.Add('Luma only');
  CbTronicColorMetric.Items.Add('RGB distance');
  CbTronicColorMetric.Items.Add('Redmean');
  CbTronicColorMetric.Items.Add('YCbCr');
  CbTronicColorMetric.Items.Add('HSV adaptive');
  CbTronicColorMetric.ItemIndex := 0;
  CbTronicColorMetric.OnChange := @AnyOptionChanged;
  CbTronicColorMetric.OnSelect := @AnyOptionChanged;

  // Core row 2: Window / Step / Glyph set
  Make3CellRow(GBMatch, 78, 210, 210, CellA, CellB, CellC);

  // (0) Window
  Cell := CellA;
  Lbl := TLabel.Create(TabTronic);
  Lbl.Parent := Cell; Lbl.Align := alTop; Lbl.Height := 18;
  Lbl.Caption := 'Window';
  SeTronicWin := TSpinEdit.Create(TabTronic);
  SeTronicWin.Parent := Cell; SeTronicWin.Align := alTop; SeTronicWin.Width := 100;
  SeTronicWin.MinValue := 6; SeTronicWin.MaxValue := 20; SeTronicWin.Value := 10;
  SeTronicWin.OnChange := @AnyOptionChanged;

  // (1) Step
  Cell := CellB;
  Lbl := TLabel.Create(TabTronic);
  Lbl.Parent := Cell; Lbl.Align := alTop; Lbl.Height := 18;
  Lbl.Caption := 'Step';
  SeTronicStep := TSpinEdit.Create(TabTronic);
  SeTronicStep.Parent := Cell; SeTronicStep.Align := alTop; SeTronicStep.Width := 100;
  SeTronicStep.MinValue := 1; SeTronicStep.MaxValue := 10; SeTronicStep.Value := 5;
  SeTronicStep.OnChange := @AnyOptionChanged;

  // (2) Glyph set
  Cell := CellC;
  Lbl := TLabel.Create(TabTronic);
  Lbl.Parent := Cell; Lbl.Align := alTop; Lbl.Height := 18;
  Lbl.Caption := 'Glyph set';
  CbTronicGlyphSet := TComboBox.Create(TabTronic);
  CbTronicGlyphSet.Parent := Cell; CbTronicGlyphSet.Align := alTop; CbTronicGlyphSet.Style := csDropDownList;
  CbTronicGlyphSet.Items.Add('blocks');
  CbTronicGlyphSet.Items.Add('shading');
  CbTronicGlyphSet.Items.Add('ansiblocks');
  CbTronicGlyphSet.Items.Add('ansiblocks-pixel');
  CbTronicGlyphSet.Items.Add('lines');
  CbTronicGlyphSet.Items.Add('full');
  CbTronicGlyphSet.Items.Add('ascii');
  CbTronicGlyphSet.Items.Add('tronic (shade+blocks)');
  CbTronicGlyphSet.ItemIndex := Ord(gsAnsiBlocksPixel);
  CbTronicGlyphSet.OnChange := @AnyOptionChanged;
  CbTronicGlyphSet.OnSelect := @AnyOptionChanged;

  // --- Diffusion ---
  GBDiff := TGroupBox.Create(TabTronic);
  GBDiff.Parent := PRight;
  GBDiff.Align := alTop;
  GBDiff.Caption := 'Diffusion';
  GBDiff.Height := 110;
  GBDiff.BorderSpacing.Bottom := 10;

  PRow := TPanel.Create(TabTronic);
  PRow.Parent := GBDiff;
  PRow.Align := alTop;
  PRow.Height := 28;
  PRow.BevelOuter := bvNone;
  PRow.BorderSpacing.Around := 8;

  Lbl := TLabel.Create(TabTronic);
  Lbl.Parent := PRow;
  Lbl.Align := alLeft;
  Lbl.Width := 110;
  Lbl.Caption := 'Model';

  CbTronicDiffModel := TComboBox.Create(TabTronic);
  CbTronicDiffModel.Parent := PRow;
  CbTronicDiffModel.Align := alClient;
  CbTronicDiffModel.Style := csDropDownList;
  CbTronicDiffModel.Items.Add('Off');
  CbTronicDiffModel.Items.Add('Ordered (Bayer 4x4)');
  CbTronicDiffModel.Items.Add('Ordered (Bayer 8x8)');
  CbTronicDiffModel.Items.Add('Floyd–Steinberg');
  CbTronicDiffModel.Items.Add('Jarvis–Judice–Ninke');
  CbTronicDiffModel.Items.Add('Atkinson');
  CbTronicDiffModel.Items.Add('Sierra Lite');
  CbTronicDiffModel.ItemIndex := 1;
  CbTronicDiffModel.OnChange := @AnyOptionChanged;
  CbTronicDiffModel.OnSelect := @AnyOptionChanged;

  PRow := TPanel.Create(TabTronic);
  PRow.Parent := GBDiff;
  PRow.Align := alTop;
  PRow.Height := 28;
  PRow.BevelOuter := bvNone;
  PRow.BorderSpacing.Left := 8;
  PRow.BorderSpacing.Right := 8;
  PRow.BorderSpacing.Bottom := 8;

  Lbl := TLabel.Create(TabTronic);
  Lbl.Parent := PRow;
  Lbl.Align := alLeft;
  Lbl.Width := 110;
  Lbl.Caption := 'Amount %';

  SeTronicDiffAmt := TSpinEdit.Create(TabTronic);
  SeTronicDiffAmt.Parent := PRow;
  SeTronicDiffAmt.Align := alLeft;
  SeTronicDiffAmt.Width := 80;
  SeTronicDiffAmt.MinValue := 0;
  SeTronicDiffAmt.MaxValue := 100;
  SeTronicDiffAmt.Value := 20;
  SeTronicDiffAmt.OnChange := @AnyOptionChanged;

  // --- Options (3 per line) ---
  GBOpts := TGroupBox.Create(TabTronic);
  GBOpts.Parent := PRight;
  GBOpts.Align := alTop;
  GBOpts.Caption := 'Options';
  GBOpts.Height := 92;
  GBOpts.BorderSpacing.Bottom := 10;

  // Options row 1
  Make3CheckRow(GBOpts, 24, 170, 170, CellA, CellB, CellC);

  ChkTronicLumaOnly := TCheckBox.Create(TabTronic);
  ChkTronicLumaOnly.Parent := CellA;
  ChkTronicLumaOnly.Align := alClient;
  ChkTronicLumaOnly.Caption := 'Luma-only';
  ChkTronicLumaOnly.ShowHint := True;
  ChkTronicLumaOnly.Hint := 'Luma-only matching (ignore hue when picking glyph/colors)';
  ChkTronicLumaOnly.Checked := True;
  ChkTronicLumaOnly.OnChange := @AnyOptionChanged;
  ChkTronicLumaOnly.OnClick := @AnyOptionChanged;

  ChkTronicAutoShader := TCheckBox.Create(TabTronic);
  ChkTronicAutoShader.Parent := CellB;
  ChkTronicAutoShader.Align := alClient;
  ChkTronicAutoShader.Caption := 'Auto tone field';
  ChkTronicAutoShader.ShowHint := True;
  ChkTronicAutoShader.Hint := 'AutoShader tone field (10x10 window, step 5)';
  ChkTronicAutoShader.Checked := True;
  ChkTronicAutoShader.OnChange := @AnyOptionChanged;
  ChkTronicAutoShader.OnClick := @AnyOptionChanged;

  ChkTronicGlyphOnly := TCheckBox.Create(TabTronic);
  ChkTronicGlyphOnly.Parent := CellC;
  ChkTronicGlyphOnly.Align := alClient;
  ChkTronicGlyphOnly.Caption := 'Glyph-only';
  ChkTronicGlyphOnly.ShowHint := True;
  ChkTronicGlyphOnly.Hint := 'Glyph-only (keep existing colors; change characters only)';
  ChkTronicGlyphOnly.Checked := False;
  ChkTronicGlyphOnly.OnChange := @AnyOptionChanged;
  ChkTronicGlyphOnly.OnClick := @AnyOptionChanged;

  // Options row 2
  Make3CheckRow(GBOpts, 24, 170, 170, CellA, CellB, CellC);

  ChkTronicEdgeShade := TCheckBox.Create(TabTronic);
  ChkTronicEdgeShade.Parent := CellA;
  ChkTronicEdgeShade.Align := alClient;
  ChkTronicEdgeShade.Caption := 'Edge texture';
  ChkTronicEdgeShade.ShowHint := True;
  ChkTronicEdgeShade.Hint := 'Edge texture (prefer shade blocks on palette boundaries)';
  ChkTronicEdgeShade.Checked := True;
  ChkTronicEdgeShade.OnChange := @AnyOptionChanged;
  ChkTronicEdgeShade.OnClick := @AnyOptionChanged;

  ChkTronicCornersShadesOnly := TCheckBox.Create(TabTronic);
  ChkTronicCornersShadesOnly.Parent := CellB;
  ChkTronicCornersShadesOnly.Align := alClient;
  ChkTronicCornersShadesOnly.Caption := 'Corners: shades';
  ChkTronicCornersShadesOnly.ShowHint := True;
  ChkTronicCornersShadesOnly.Hint := 'Corners/junctions: shades only (avoid half-blocks)';
  ChkTronicCornersShadesOnly.Checked := True;
  ChkTronicCornersShadesOnly.OnChange := @AnyOptionChanged;
  ChkTronicCornersShadesOnly.OnClick := @AnyOptionChanged;

  // --- Edge controls ---
  GBEdge := TGroupBox.Create(TabTronic);
  GBEdge.Parent := PRight;
  GBEdge.Align := alTop;
  GBEdge.Caption := 'Edge / Texture';
  GBEdge.Height := 240;

  // Edge sample row
  PRow := TPanel.Create(TabTronic);
  PRow.Parent := GBEdge;
  PRow.Align := alTop;
  PRow.Height := 28;
  PRow.BevelOuter := bvNone;
  PRow.BorderSpacing.Around := 8;

  Lbl := TLabel.Create(TabTronic);
  Lbl.Parent := PRow;
  Lbl.Align := alLeft;
  Lbl.Width := 110;
  Lbl.Caption := 'Edge sample';

  CbTronicEdgeSample := TComboBox.Create(TabTronic);
  CbTronicEdgeSample.Parent := PRow;
  CbTronicEdgeSample.Align := alLeft;
  CbTronicEdgeSample.Width := 110;
  CbTronicEdgeSample.Style := csDropDownList;
  CbTronicEdgeSample.Items.Add('2x2');
  CbTronicEdgeSample.Items.Add('3x3');
  CbTronicEdgeSample.Items.Add('4x4');
  CbTronicEdgeSample.ItemIndex := 1;
  CbTronicEdgeSample.OnChange := @AnyOptionChanged;
  CbTronicEdgeSample.OnSelect := @AnyOptionChanged;

  // Block threshold
  Lbl := TLabel.Create(TabTronic);
  Lbl.Parent := GBEdge;
  Lbl.Align := alTop;
  Lbl.AutoSize := False;
  Lbl.Height := 18;
  Lbl.BorderSpacing.Left := 8;
  Lbl.BorderSpacing.Right := 8;
  Lbl.Caption := 'Block threshold (more shading ⟷ more half-blocks)';

  PRow := TPanel.Create(TabTronic);
  PRow.Parent := GBEdge;
  PRow.Align := alTop;
  PRow.Height := 28;
  PRow.BevelOuter := bvNone;
  PRow.BorderSpacing.Left := 8;
  PRow.BorderSpacing.Right := 8;
  PRow.BorderSpacing.Bottom := 10;

  LblTronicBlockThresholdVal := TLabel.Create(TabTronic);
  LblTronicBlockThresholdVal.Parent := PRow;
  LblTronicBlockThresholdVal.Align := alRight;
  LblTronicBlockThresholdVal.Width := 40;

  TbTronicBlockThreshold := TTrackBar.Create(TabTronic);
  TbTronicBlockThreshold.Parent := PRow;
  TbTronicBlockThreshold.Align := alClient;
  TbTronicBlockThreshold.Orientation := trHorizontal;
  TbTronicBlockThreshold.Min := 0;
  TbTronicBlockThreshold.Max := 50;
  TbTronicBlockThreshold.Frequency := 5;
  TbTronicBlockThreshold.TickStyle := tsNone;
  TbTronicBlockThreshold.Position := 20;
  TbTronicBlockThreshold.OnChange := @AnyOptionChanged;
  LblTronicBlockThresholdVal.Caption := IntToStr(TbTronicBlockThreshold.Position);

  // Shade weight
  Lbl := TLabel.Create(TabTronic);
  Lbl.Parent := GBEdge;
  Lbl.Align := alTop;
  Lbl.AutoSize := False;
  Lbl.Height := 18;
  Lbl.BorderSpacing.Left := 8;
  Lbl.BorderSpacing.Right := 8;
  Lbl.Caption := 'Shade weight (edge texture strength)';

  PRow := TPanel.Create(TabTronic);
  PRow.Parent := GBEdge;
  PRow.Align := alTop;
  PRow.Height := 28;
  PRow.BevelOuter := bvNone;
  PRow.BorderSpacing.Left := 8;
  PRow.BorderSpacing.Right := 8;
  PRow.BorderSpacing.Bottom := 8;

  LblTronicShadeWeightVal := TLabel.Create(TabTronic);
  LblTronicShadeWeightVal.Parent := PRow;
  LblTronicShadeWeightVal.Align := alRight;
  LblTronicShadeWeightVal.Width := 40;

  TbTronicShadeWeight := TTrackBar.Create(TabTronic);
  TbTronicShadeWeight.Parent := PRow;
  TbTronicShadeWeight.Align := alClient;
  TbTronicShadeWeight.Orientation := trHorizontal;
  TbTronicShadeWeight.Min := 0;
  TbTronicShadeWeight.Max := 200;
  TbTronicShadeWeight.Frequency := 20;
  TbTronicShadeWeight.TickStyle := tsNone;
  TbTronicShadeWeight.Position := 120;
  TbTronicShadeWeight.OnChange := @AnyOptionChanged;
  LblTronicShadeWeightVal.Caption := IntToStr(TbTronicShadeWeight.Position);

  // Ensure the groupbox is tall enough; scrollbox handles overflow.
  // Compute required height from the tallest column (left vs right).
  TrNeedLeft := GBTrain.Height;
  TrNeedRight := (GBMatch.Height + GBMatch.BorderSpacing.Bottom) +
                 (GBDiff.Height + GBDiff.BorderSpacing.Bottom) +
                 (GBOpts.Height + GBOpts.BorderSpacing.Bottom) +
                 GBEdge.Height;
  if TrNeedLeft > TrNeedRight then
    TrNeedBody := TrNeedLeft
  else
    TrNeedBody := TrNeedRight;

  // Top area: action row + paddings
  TrNeedTop := Max(PAction.Height, BtnRenderTronic.Height) + 24;

  // Final height: top + body + breathing room
  GB.Height := TrNeedTop + TrNeedBody + 64;


{ === TAB: ANSI LAB === }
  TabAnsiLab := TTabSheet.Create(PageControl);
  TabAnsiLab.Caption := 'AnsiLab';
  TabAnsiLab.PageControl := PageControl;

  AnsiLabScroll := TScrollBox.Create(TabAnsiLab);
  AnsiLabScroll.Parent := TabAnsiLab;
  AnsiLabScroll.Align := alClient;
  AnsiLabScroll.BorderStyle := bsNone;
  AnsiLabScroll.AutoScroll := True;

  GB := TGroupBox.Create(TabAnsiLab);
  GB.Parent := AnsiLabScroll;
  GB.Caption := 'Build preset from ANSI (.ANS/.ANSI)';
  GB.SetBounds(8, 8, 900, 170);

  Lbl := TLabel.Create(TabAnsiLab);
  Lbl.Parent := GB;
  Lbl.Caption := 'Preset name';
  Lbl.SetBounds(12, 24, 140, 18);

  EdAnsiLabName := TEdit.Create(TabAnsiLab);
  EdAnsiLabName.Parent := GB;
  EdAnsiLabName.SetBounds(12, 44, 260, 24);
  EdAnsiLabName.Text := '';

  BtnAnsiLabBuild := TButton.Create(TabAnsiLab);
  BtnAnsiLabBuild.Parent := GB;
  BtnAnsiLabBuild.SetBounds(290, 40, 220, 30);
  BtnAnsiLabBuild.Caption := 'Import ANSI(s) + Save preset...';
  BtnAnsiLabBuild.OnClick := @BtnAnsiLabBuildClick;

  ChkAnsiLabTreatBlinkAsIce := TCheckBox.Create(TabAnsiLab);
  ChkAnsiLabTreatBlinkAsIce.Parent := GB;
  ChkAnsiLabTreatBlinkAsIce.Caption := 'Treat blink as bright BG (iCE)';
  ChkAnsiLabTreatBlinkAsIce.SetBounds(12, 78, 260, 22);
  ChkAnsiLabTreatBlinkAsIce.Checked := True;

  ChkAnsiLabMirrorH := TCheckBox.Create(TabAnsiLab);
  ChkAnsiLabMirrorH.Parent := GB;
  ChkAnsiLabMirrorH.Caption := 'Mirror horizontally (augment)';
  ChkAnsiLabMirrorH.SetBounds(290, 78, 260, 22);
  ChkAnsiLabMirrorH.Checked := True;

  ChkAnsiLabLearnShadeOnly := TCheckBox.Create(TabAnsiLab);
  ChkAnsiLabLearnShadeOnly.Parent := GB;
  ChkAnsiLabLearnShadeOnly.Caption := 'Learn shading glyphs only (recommended)';
  ChkAnsiLabLearnShadeOnly.SetBounds(560, 78, 320, 22);
  ChkAnsiLabLearnShadeOnly.Checked := True;

  Lbl := TLabel.Create(TabAnsiLab);
  Lbl.Parent := GB;
  Lbl.Caption := 'Max rows';
  Lbl.SetBounds(12, 108, 120, 18);

  SeAnsiLabMaxRows := TSpinEdit.Create(TabAnsiLab);
  SeAnsiLabMaxRows.Parent := GB;
  SeAnsiLabMaxRows.SetBounds(12, 128, 90, 24);
  SeAnsiLabMaxRows.MinValue := 1;
  SeAnsiLabMaxRows.MaxValue := 500;
  SeAnsiLabMaxRows.Value := 200;

  Lbl := TLabel.Create(TabAnsiLab);
  Lbl.Parent := GB;
  Lbl.Caption := 'Passes';
  Lbl.SetBounds(120, 108, 120, 18);

  SeAnsiLabPasses := TSpinEdit.Create(TabAnsiLab);
  SeAnsiLabPasses.Parent := GB;
  SeAnsiLabPasses.SetBounds(120, 128, 90, 24);
  SeAnsiLabPasses.MinValue := 1;
  SeAnsiLabPasses.MaxValue := 10;
  SeAnsiLabPasses.Value := 3;

  Lbl := TLabel.Create(TabAnsiLab);
  Lbl.Parent := GB;
  Lbl.Caption := 'Weight';
  Lbl.SetBounds(228, 108, 120, 18);

  SeAnsiLabWeight := TSpinEdit.Create(TabAnsiLab);
  SeAnsiLabWeight.Parent := GB;
  SeAnsiLabWeight.SetBounds(228, 128, 90, 24);
  SeAnsiLabWeight.MinValue := 1;
  SeAnsiLabWeight.MaxValue := 50;
  SeAnsiLabWeight.Value := 3;

  Lbl := TLabel.Create(TabAnsiLab);
  Lbl.Parent := GB;
  Lbl.Caption := 'Dedupe cap';
  Lbl.SetBounds(336, 108, 120, 18);

  SeAnsiLabDedupeCap := TSpinEdit.Create(TabAnsiLab);
  SeAnsiLabDedupeCap.Parent := GB;
  SeAnsiLabDedupeCap.SetBounds(336, 128, 90, 24);
  SeAnsiLabDedupeCap.MinValue := 1;
  SeAnsiLabDedupeCap.MaxValue := 20;
  SeAnsiLabDedupeCap.Value := 4;

  GB := TGroupBox.Create(TabAnsiLab);
  GB.Parent := AnsiLabScroll;
  GB.Caption := 'Load/apply preset';
  GB.SetBounds(8, 186, 900, 86);

  BtnAnsiLabLoadPreset := TButton.Create(TabAnsiLab);
  BtnAnsiLabLoadPreset.Parent := GB;
  BtnAnsiLabLoadPreset.SetBounds(12, 30, 200, 30);
  BtnAnsiLabLoadPreset.Caption := 'Load preset...';
  BtnAnsiLabLoadPreset.OnClick := @BtnAnsiLabLoadPresetClick;

  BtnAnsiLabApplyPreset := TButton.Create(TabAnsiLab);
  BtnAnsiLabApplyPreset.Parent := GB;
  BtnAnsiLabApplyPreset.SetBounds(224, 30, 220, 30);
  BtnAnsiLabApplyPreset.Caption := 'Apply loaded preset';
  BtnAnsiLabApplyPreset.Enabled := False;
  BtnAnsiLabApplyPreset.OnClick := @BtnAnsiLabApplyPresetClick;

  Lbl := TLabel.Create(TabAnsiLab);
  Lbl.Parent := GB;
  Lbl.SetBounds(460, 34, 420, 40);
  Lbl.Caption := 'Tip: presets save BOTH a ShaderLab profile (.json) and a TronicShade library (.tronic.json).';

  MemoAnsiLab := TMemo.Create(TabAnsiLab);
  MemoAnsiLab.Parent := AnsiLabScroll;
  MemoAnsiLab.SetBounds(8, 286, 900, 240);
  MemoAnsiLab.Anchors := [akLeft, akTop, akRight, akBottom];
  MemoAnsiLab.ScrollBars := ssVertical;
  MemoAnsiLab.WordWrap := False;
  MemoAnsiLab.ReadOnly := True;
  MemoAnsiLab.Lines.Add('AnsiLab log:');

{ === PATCHSTYLE === }
  TabCleanup := TTabSheet.Create(PageControl);
  TabCleanup.Caption := 'PatchStyle';
  TabCleanup.PageControl := PageControl;

  SB := TScrollBox.Create(TabCleanup);
  SB.Parent := TabCleanup;
  SB.Align := alClient;
  SB.BorderStyle := bsNone;
  SB.AutoScroll := True;

  GB := TGroupBox.Create(TabCleanup);
  GB.Parent := SB;
  GB.Caption := 'PatchStyle (learned patchbook + post-pass style transfer)';
  GB.SetBounds(8, 8, 620, 200);

  ChkPatchStyle := TCheckBox.Create(TabCleanup);
  ChkPatchStyle.Parent := GB;
  ChkPatchStyle.Caption := 'Enable PatchStyle post-pass';
  ChkPatchStyle.SetBounds(12, 22, 260, 22);
  ChkPatchStyle.Checked := False;

  Lbl := TLabel.Create(TabCleanup);
  Lbl.Parent := GB;
  Lbl.Caption := 'Patch sizes:';
  Lbl.SetBounds(12, 48, 80, 18);

  ChkPatch10 := TCheckBox.Create(TabCleanup);
  ChkPatch10.Parent := GB;
  ChkPatch10.Caption := '10x10';
  ChkPatch10.SetBounds(96, 46, 70, 22);
  ChkPatch10.Checked := True;

  ChkPatch5 := TCheckBox.Create(TabCleanup);
  ChkPatch5.Parent := GB;
  ChkPatch5.Caption := '5x5';
  ChkPatch5.SetBounds(170, 46, 60, 22);
  ChkPatch5.Checked := True;

  ChkPatch3 := TCheckBox.Create(TabCleanup);
  ChkPatch3.Parent := GB;
  ChkPatch3.Caption := '3x3';
  ChkPatch3.SetBounds(232, 46, 60, 22);
  ChkPatch3.Checked := True;

  Lbl := TLabel.Create(TabCleanup);
  Lbl.Parent := GB;
  Lbl.Caption := 'Loops:';
  Lbl.SetBounds(310, 48, 40, 18);

  SePatchLoops := TSpinEdit.Create(TabCleanup);
  SePatchLoops.Parent := GB;
  SePatchLoops.MinValue := 1;
  SePatchLoops.MaxValue := 8;
  SePatchLoops.Value := 1;
  SePatchLoops.SetBounds(354, 44, 60, 26);

  Lbl := TLabel.Create(TabCleanup);
  Lbl.Parent := GB;
  Lbl.Caption := 'Min match %:';
  Lbl.SetBounds(426, 48, 80, 18);

  SePatchMinMatch := TSpinEdit.Create(TabCleanup);
  SePatchMinMatch.Parent := GB;
  SePatchMinMatch.MinValue := 0;
  SePatchMinMatch.MaxValue := 100;
  SePatchMinMatch.Value := 65;
  SePatchMinMatch.SetBounds(508, 44, 52, 26);

  RgPatchMode := TRadioGroup.Create(TabCleanup);
  RgPatchMode.Parent := GB;
  RgPatchMode.Caption := 'Apply mode';
  RgPatchMode.Items.Add('Full (glyph + colors)');
  RgPatchMode.Items.Add('Glyph-only');
  RgPatchMode.ItemIndex := 0;
  RgPatchMode.SetBounds(12, 74, 240, 70);

  BtnPatchLoad := TButton.Create(TabCleanup);
  BtnPatchLoad.Parent := GB;
  BtnPatchLoad.Caption := 'Load patchbook...';
  BtnPatchLoad.SetBounds(270, 84, 150, 28);
  BtnPatchLoad.OnClick := @BtnPatchLoadClick;

  BtnPatchSave := TButton.Create(TabCleanup);
  BtnPatchSave.Parent := GB;
  BtnPatchSave.Caption := 'Save patchbook...';
  BtnPatchSave.SetBounds(428, 84, 150, 28);
  BtnPatchSave.OnClick := @BtnPatchSaveClick;

  BtnPatchClear := TButton.Create(TabCleanup);
  BtnPatchClear.Parent := GB;
  BtnPatchClear.Caption := 'Clear patchbook';
  BtnPatchClear.SetBounds(270, 118, 150, 28);
  BtnPatchClear.OnClick := @BtnPatchClearClick;

  ChkPatchBlocksOnly := TCheckBox.Create(TabCleanup);
  ChkPatchBlocksOnly.Parent := GB;
  ChkPatchBlocksOnly.Caption := 'Blocks/shades only (filter patchbook on load)';
  ChkPatchBlocksOnly.SetBounds(270, 150, 308, 22);
  ChkPatchBlocksOnly.Checked := False;

  LblPatchInfo := TLabel.Create(TabCleanup);
  LblPatchInfo.Parent := GB;
  LblPatchInfo.Caption := 'Patchbook: (empty)';
  LblPatchInfo.SetBounds(428, 124, 240, 18);

  { === PRE-RENDER FILTERS (moved into Image Adjustments) === }

  Lbl := TLabel.Create(Self);
  Lbl.Parent := TabAdjust;
  Lbl.SetBounds(12, 110, 600, 18);
  Lbl.Caption := 'Pre-render filters';

  FlowPreRender := TFlowPanel.Create(TabAdjust);
  FlowPreRender.Parent := TabAdjust;
  FlowPreRender.SetBounds(12, 132, 700, 120);
  FlowPreRender.AutoWrap := True;
  FlowPreRender.BevelOuter := bvNone;

  BtnPreReset := TButton.Create(Self);
  BtnPreReset.Parent := FlowPreRender;
  BtnPreReset.Caption := 'Reset to Original';
  BtnPreReset.Width := 140;
  BtnPreReset.Height := 32;
  BtnPreReset.BorderSpacing.Around := 6;
  BtnPreReset.Tag := 0;
  BtnPreReset.OnClick := @DoPreFilter;

  BtnPreGray := TButton.Create(Self);
  BtnPreGray.Parent := FlowPreRender;
  BtnPreGray.Caption := 'Grayscale';
  BtnPreGray.Width := 140;
  BtnPreGray.Height := 32;
  BtnPreGray.BorderSpacing.Around := 6;
  BtnPreGray.Tag := 1;
  BtnPreGray.OnClick := @DoPreFilter;

  BtnPreSharpen := TButton.Create(Self);
  BtnPreSharpen.Parent := FlowPreRender;
  BtnPreSharpen.Caption := 'Sharpen';
  BtnPreSharpen.Width := 140;
  BtnPreSharpen.Height := 32;
  BtnPreSharpen.BorderSpacing.Around := 6;
  BtnPreSharpen.Tag := 2;
  BtnPreSharpen.OnClick := @DoPreFilter;

  BtnPreBlur := TButton.Create(Self);
  BtnPreBlur.Parent := FlowPreRender;
  BtnPreBlur.Caption := 'Blur';
  BtnPreBlur.Width := 140;
  BtnPreBlur.Height := 32;
  BtnPreBlur.BorderSpacing.Around := 6;
  BtnPreBlur.Tag := 3;
  BtnPreBlur.OnClick := @DoPreFilter;

  BtnPreEdge := TButton.Create(Self);
  BtnPreEdge.Parent := FlowPreRender;
  BtnPreEdge.Caption := 'Edge Detect';
  BtnPreEdge.Width := 140;
  BtnPreEdge.Height := 32;
  BtnPreEdge.BorderSpacing.Around := 6;
  BtnPreEdge.Tag := 4;
  BtnPreEdge.OnClick := @DoPreFilter;

  BtnPrePosterize := TButton.Create(Self);
  BtnPrePosterize.Parent := FlowPreRender;
  BtnPrePosterize.Caption := 'Posterize';
  BtnPrePosterize.Width := 140;
  BtnPrePosterize.Height := 32;
  BtnPrePosterize.BorderSpacing.Around := 6;
  BtnPrePosterize.Tag := 5;
  BtnPrePosterize.OnClick := @DoPreFilter;

  BtnPreConPlus := TButton.Create(Self);
  BtnPreConPlus.Parent := FlowPreRender;
  BtnPreConPlus.Caption := 'Contrast +';
  BtnPreConPlus.Width := 140;
  BtnPreConPlus.Height := 32;
  BtnPreConPlus.BorderSpacing.Around := 6;
  BtnPreConPlus.Tag := 6;
  BtnPreConPlus.OnClick := @DoPreFilter;

  BtnPreConMinus := TButton.Create(Self);
  BtnPreConMinus.Parent := FlowPreRender;
  BtnPreConMinus.Caption := 'Contrast -';
  BtnPreConMinus.Width := 140;
  BtnPreConMinus.Height := 32;
  BtnPreConMinus.BorderSpacing.Around := 6;
  BtnPreConMinus.Tag := 7;
  BtnPreConMinus.OnClick := @DoPreFilter;

  { Bottom panels remain the same }
  PanelLeft := TPanel.Create(Self);
  PanelLeft.Parent := Self;
  PanelLeft.Align := alLeft;
  PanelLeft.Width := 420;

  Split := TSplitter.Create(Self);
  Split.Parent := Self;
  Split.Align := alLeft;

  PanelRight := TPanel.Create(Self);
  PanelRight.Parent := Self;
  PanelRight.Align := alClient;

  // Source preview paintbox
  SrcBox := TPaintBox.Create(Self);
  SrcBox.Parent := PanelLeft;
  SrcBox.Align := alClient;
  SrcBox.OnPaint := @SrcPaint;
  SrcBox.OnMouseDown := @SrcMouseDown;
  SrcBox.OnMouseMove := @SrcMouseMove;
  SrcBox.OnMouseUp := @SrcMouseUp;

  // Output preview: fixed DOS cell aspect + scrollbars
  OutScroll := TScrollBox.Create(Self);
  OutScroll.Parent := PanelRight;
  OutScroll.Align := alClient;
  OutScroll.HorzScrollBar.Visible := True;
  OutScroll.VertScrollBar.Visible := True;

  OutBox := TPaintBox.Create(Self);
  OutBox.Parent := OutScroll;
  OutBox.Align := alNone;
  OutBox.Left := 0;
  OutBox.Top := 0;
  OutBox.OnPaint := @OutPaint;
  OutBox.OnMouseDown := @OutMouseDown;

  // Bottom status bar with hotkeys for quick reference
  StatusBar := TStatusBar.Create(Self);
  StatusBar.Parent := Self;
  StatusBar.Align := alBottom;
  StatusBar.SimplePanel := True;
  StatusBar.SimpleText := 'Alt+S Save (ANSI/BIN)    Alt+R Reset defaults    F12 Render';
  StatusBar.BringToFront;
end;

procedure TMainForm.StartProgressUI(const Title: string);
var
  pnlBottom: TPanel;
begin
  ProgCancel := False;
  ProgLastPct := -1;
  ProgLastMsg := '';

  ProgLastPumpTick := GetTickCount64;
  if Assigned(ProgForm) then
    FreeAndNil(ProgForm);

  ProgForm := TForm.CreateNew(Self);
  ProgForm.Caption := Title;
  ProgForm.Position := poScreenCenter;
  ProgForm.BorderStyle := bsDialog;
  ProgForm.BorderIcons := [];
  ProgForm.Width := 520;
  ProgForm.Height := 320;

  ProgBar := TProgressBar.Create(ProgForm);
  ProgBar.Parent := ProgForm;
  ProgBar.Align := alTop;
  ProgBar.Min := 0;
  ProgBar.Max := 100;
  ProgBar.Position := 0;
  ProgBar.Height := 18;

  pnlBottom := TPanel.Create(ProgForm);
  pnlBottom.Parent := ProgForm;
  pnlBottom.Align := alBottom;
  pnlBottom.Height := 40;
  pnlBottom.BevelOuter := bvNone;

  ProgCancelBtn := TButton.Create(ProgForm);
  ProgCancelBtn.Parent := pnlBottom;
  ProgCancelBtn.Caption := 'Cancel';
  ProgCancelBtn.AnchorSideRight.Control := pnlBottom;
  ProgCancelBtn.AnchorSideRight.Side := asrRight;
  ProgCancelBtn.AnchorSideBottom.Control := pnlBottom;
  ProgCancelBtn.AnchorSideBottom.Side := asrBottom;
  ProgCancelBtn.BorderSpacing.Right := 8;
  ProgCancelBtn.BorderSpacing.Bottom := 8;
  ProgCancelBtn.Anchors := [akRight, akBottom];
  ProgCancelBtn.OnClick := @ProgCancelClick;

  ProgMemo := TMemo.Create(ProgForm);
  ProgMemo.Parent := ProgForm;
  ProgMemo.Align := alClient;
  ProgMemo.ReadOnly := True;
  ProgMemo.ScrollBars := ssVertical;
  ProgMemo.WordWrap := False;
  ProgMemo.Lines.Clear;

  ProgForm.Show;
  ProgForm.Update;
  Application.ProcessMessages;
end;

procedure TMainForm.EndProgressUI;
begin
  if Assigned(ProgForm) then
  begin
    ProgForm.Hide;
    FreeAndNil(ProgForm);
  end;
  ProgBar := nil;
  ProgMemo := nil;
  ProgCancelBtn := nil;
end;

procedure TMainForm.SetupAutoPreview;
begin
  if Assigned(FPreviewTimer) then Exit;
  FPreviewTimer := TTimer.Create(Self);
  FPreviewTimer.Enabled := False;
  // Debounce interval: fast enough to feel "live" while dragging sliders,
  // but slow enough to avoid re-rendering on every single tick.
  FPreviewTimer.Interval := 250;
  FPreviewTimer.OnTimer := @PreviewTimerTick;
end;

procedure TMainForm.RequestPreviewRender;
begin
  if not FUIReady then Exit;
  if not Assigned(FImg) then Exit;
  if not Assigned(FPreviewTimer) then Exit;

  // Mark pending and restart the timer (debounce).
  FPreviewPending := True;
  FPreviewTimer.Enabled := False;
  FPreviewTimer.Enabled := True;
end;

procedure TMainForm.PreviewTimerTick(Sender: TObject);
begin
  if not Assigned(FPreviewTimer) then Exit;
  FPreviewTimer.Enabled := False;
  if not FPreviewPending then Exit;
  if FPreviewBusy then
  begin
    // If a preview render is already running, re-arm the timer.
    FPreviewTimer.Enabled := True;
    Exit;
  end;

  FPreviewPending := False;
  if not Assigned(FImg) then Exit;

  FPreviewBusy := True;
  try
    // Silent render: no progress dialog, no report popup.
    RenderCore(False, False);
  finally
    FPreviewBusy := False;
  end;

  // If settings changed while we were rendering, schedule another pass.
  if FPreviewPending then
    FPreviewTimer.Enabled := True;
end;

procedure TMainForm.ProgCancelClick(Sender: TObject);
begin
  ProgCancel := True;
  if Assigned(ProgCancelBtn) then
    ProgCancelBtn.Enabled := False;
  // Keep UI alive; conversion loop checks Opt.CancelFlag.
  Application.ProcessMessages;
end;

procedure TMainForm.ProgressUpdate(Percent: Integer; const Msg: string);
const
  MAX_LOG_LINES = 250;
  PUMP_MS = 33; // ~30fps UI pump
var
  nowTick: QWord;
begin
  if not Assigned(ProgForm) then Exit;
  if Percent < 0 then Percent := 0;
  if Percent > 100 then Percent := 100;

  // Avoid hammering the UI: only update when something changes.
  if (Percent <> ProgLastPct) and Assigned(ProgBar) then
  begin
    ProgBar.Position := Percent;
    ProgLastPct := Percent;
  end;

  if (Msg <> '') and (Msg <> ProgLastMsg) and Assigned(ProgMemo) then
  begin
    ProgMemo.Lines.Add(Msg);

    // Keep the log from growing without bound (helps performance on long renders).
    while ProgMemo.Lines.Count > MAX_LOG_LINES do
      ProgMemo.Lines.Delete(0);

    ProgMemo.SelStart := Length(ProgMemo.Text);
    ProgMemo.SelLength := 0;
    ProgLastMsg := Msg;
  end;

  // Throttle message pumping so conversion work stays fast.
  nowTick := GetTickCount64;
  if (nowTick - ProgLastPumpTick) >= PUMP_MS then
  begin
    Application.ProcessMessages;
    ProgLastPumpTick := nowTick;
  end;
end;

procedure TMainForm.CopyFPImage(const Src: TFPMemoryImage; Dest: TFPMemoryImage);
var
  x, y: Integer;
begin
  if (Src = nil) or (Dest = nil) then Exit;
  Dest.SetSize(Src.Width, Src.Height);
  for y := 0 to Src.Height - 1 do
    for x := 0 to Src.Width - 1 do
      Dest.Colors[x, y] := Src.Colors[x, y];
end;

procedure TMainForm.UpdateSrcPreviewFromFP;
var
  x, y: Integer;
  c: TFPColor;
  p: PByte;
begin
  if (FImg = nil) then Exit;
  if (FImg.Width <= 0) or (FImg.Height <= 0) then Exit;

  FSrcBmp.PixelFormat := pf24bit;
  FSrcBmp.SetSize(FImg.Width, FImg.Height);

  for y := 0 to FImg.Height - 1 do
  begin
    p := FSrcBmp.ScanLine[y];
    for x := 0 to FImg.Width - 1 do
    begin
      c := FImg.Colors[x, y];
      { pf24bit is BGR }
      p^ := c.blue shr 8;  Inc(p);
      p^ := c.green shr 8; Inc(p);
      p^ := c.red shr 8;   Inc(p);
    end;
  end;

  SrcBox.Invalidate;
end;

procedure TMainForm.ApplyPreFilter(AFilter: Integer);
var
  x, y: Integer;
  c: TFPColor;
  r, g, b: Integer;
  tmp: TFPMemoryImage;
  rr, gg, bb: Integer;
  kx, ky: Integer;
  sumR, sumG, sumB: Integer;
  gxR, gxG, gxB, gyR, gyG, gyB: Integer;
  vR, vG, vB: Integer;
  step: Integer;
  factor: Double;
  lum: Integer;

  function Clamp255(v: Integer): Byte;
  begin
    if v < 0 then v := 0 else if v > 255 then v := 255;
    Result := Byte(v);
  end;

  procedure SetPix(ix, iy: Integer; r8, g8, b8: Integer);
  var
    cc: TFPColor;
  begin
    cc.red   := Clamp255(r8) * 257;
    cc.green := Clamp255(g8) * 257;
    cc.blue  := Clamp255(b8) * 257;
    cc.alpha := $FFFF;
    FImg.Colors[ix, iy] := cc;
  end;

  procedure GetPix(Img: TFPMemoryImage; ix, iy: Integer; out r8, g8, b8: Integer);
  var
    cc: TFPColor;
  begin
    if ix < 0 then ix := 0 else if ix >= Img.Width then ix := Img.Width - 1;
    if iy < 0 then iy := 0 else if iy >= Img.Height then iy := Img.Height - 1;
    cc := Img.Colors[ix, iy];
    r8 := cc.red shr 8;
    g8 := cc.green shr 8;
    b8 := cc.blue shr 8;
  end;

begin
  if (FImg = nil) or (FOrigImg = nil) then Exit;
  if (FImg.Width = 0) or (FImg.Height = 0) then Exit;

  { Reset }
  if AFilter = 0 then
  begin
    CopyFPImage(FOrigImg, FImg);
    Exit;
  end;

  { Fast grayscale directly on current image }
  if AFilter = 1 then
  begin
    for y := 0 to FImg.Height - 1 do
      for x := 0 to FImg.Width - 1 do
      begin
        c := FImg.Colors[x, y];
        r := c.red shr 8;
        g := c.green shr 8;
        b := c.blue shr 8;
        lum := (r * 30 + g * 59 + b * 11) div 100;
        SetPix(x, y, lum, lum, lum);
      end;
    Exit;
  end;

  tmp := TFPMemoryImage.Create(0, 0);
  try
    CopyFPImage(FImg, tmp);

    { Sharpen (3x3) }
    if AFilter = 2 then
    begin
      for y := 0 to FImg.Height - 1 do
        for x := 0 to FImg.Width - 1 do
        begin
          sumR := 0; sumG := 0; sumB := 0;
          for ky := -1 to 1 do
            for kx := -1 to 1 do
            begin
              GetPix(tmp, x + kx, y + ky, rr, gg, bb);
              if (kx = 0) and (ky = 0) then
              begin
                sumR += 5 * rr; sumG += 5 * gg; sumB += 5 * bb;
              end
              else if ((kx = 0) xor (ky = 0)) then
              begin
                sumR -= rr; sumG -= gg; sumB -= bb;
              end;
            end;
          SetPix(x, y, sumR, sumG, sumB);
        end;
      Exit;
    end;

    { Blur (box 3x3) }
    if AFilter = 3 then
    begin
      for y := 0 to FImg.Height - 1 do
        for x := 0 to FImg.Width - 1 do
        begin
          sumR := 0; sumG := 0; sumB := 0;
          for ky := -1 to 1 do
            for kx := -1 to 1 do
            begin
              GetPix(tmp, x + kx, y + ky, rr, gg, bb);
              sumR += rr; sumG += gg; sumB += bb;
            end;
          SetPix(x, y, sumR div 9, sumG div 9, sumB div 9);
        end;
      Exit;
    end;

    { Edge detect (Sobel) }
    if AFilter = 4 then
    begin
      for y := 0 to FImg.Height - 1 do
        for x := 0 to FImg.Width - 1 do
        begin
          gxR := 0; gxG := 0; gxB := 0;
          gyR := 0; gyG := 0; gyB := 0;

          { Gx }
          GetPix(tmp, x - 1, y - 1, rr, gg, bb); gxR += -1 * rr; gxG += -1 * gg; gxB += -1 * bb;
          GetPix(tmp, x + 1, y - 1, rr, gg, bb); gxR +=  1 * rr; gxG +=  1 * gg; gxB +=  1 * bb;
          GetPix(tmp, x - 1, y,     rr, gg, bb); gxR += -2 * rr; gxG += -2 * gg; gxB += -2 * bb;
          GetPix(tmp, x + 1, y,     rr, gg, bb); gxR +=  2 * rr; gxG +=  2 * gg; gxB +=  2 * bb;
          GetPix(tmp, x - 1, y + 1, rr, gg, bb); gxR += -1 * rr; gxG += -1 * gg; gxB += -1 * bb;
          GetPix(tmp, x + 1, y + 1, rr, gg, bb); gxR +=  1 * rr; gxG +=  1 * gg; gxB +=  1 * bb;

          { Gy }
          GetPix(tmp, x - 1, y - 1, rr, gg, bb); gyR += -1 * rr; gyG += -1 * gg; gyB += -1 * bb;
          GetPix(tmp, x,     y - 1, rr, gg, bb); gyR += -2 * rr; gyG += -2 * gg; gyB += -2 * bb;
          GetPix(tmp, x + 1, y - 1, rr, gg, bb); gyR += -1 * rr; gyG += -1 * gg; gyB += -1 * bb;
          GetPix(tmp, x - 1, y + 1, rr, gg, bb); gyR +=  1 * rr; gyG +=  1 * gg; gyB +=  1 * bb;
          GetPix(tmp, x,     y + 1, rr, gg, bb); gyR +=  2 * rr; gyG +=  2 * gg; gyB +=  2 * bb;
          GetPix(tmp, x + 1, y + 1, rr, gg, bb); gyR +=  1 * rr; gyG +=  1 * gg; gyB +=  1 * bb;

          vR := Trunc(Sqrt(gxR * gxR + gyR * gyR));
          vG := Trunc(Sqrt(gxG * gxG + gyG * gyG));
          vB := Trunc(Sqrt(gxB * gxB + gyB * gyB));
          if vR > 255 then vR := 255;
          if vG > 255 then vG := 255;
          if vB > 255 then vB := 255;
          SetPix(x, y, vR, vG, vB);
        end;
      Exit;
    end;

    { Posterize (4 levels) }
    if AFilter = 5 then
    begin
      step := 64;
      for y := 0 to FImg.Height - 1 do
        for x := 0 to FImg.Width - 1 do
        begin
          GetPix(tmp, x, y, rr, gg, bb);
          rr := (rr div step) * step + step div 2;
          gg := (gg div step) * step + step div 2;
          bb := (bb div step) * step + step div 2;
          SetPix(x, y, rr, gg, bb);
        end;
      Exit;
    end;

    { Contrast +/- }
    if (AFilter = 6) or (AFilter = 7) then
    begin
      if AFilter = 6 then factor := 1.15 else factor := 0.85;
      for y := 0 to FImg.Height - 1 do
        for x := 0 to FImg.Width - 1 do
        begin
          GetPix(tmp, x, y, rr, gg, bb);
          rr := Round((rr - 128) * factor + 128);
          gg := Round((gg - 128) * factor + 128);
          bb := Round((bb - 128) * factor + 128);
          SetPix(x, y, rr, gg, bb);
        end;
      Exit;
    end;

  finally
    tmp.Free;
  end;
end;

procedure TMainForm.DoPreFilter(Sender: TObject);
var
  f: Integer;
begin
  if (FImg = nil) or (FOrigImg = nil) then Exit;
  f := TComponent(Sender).Tag;
  ApplyPreFilter(f);
  UpdateSrcPreviewFromFP;
  DoRender(nil);
end;

procedure TMainForm.UpdateInfo;
var
  bytes: Int64;
  selW, selH: Integer;
  n: TRect;
begin
  if (FRows > 0) and (Length(FCells) = COLS * FRows) then
  begin
    bytes := Int64(COLS) * Int64(FRows) * 2;
    LblInfo.Caption := Format('Loaded: %s | Output: 80 x %d | BIN bytes: %d',
      [ExtractFileName(FFileName), FRows, bytes]);
  end
  else if FFileName <> '' then
    LblInfo.Caption := 'Loaded: ' + ExtractFileName(FFileName) + ' | (not rendered yet)'
  else
    LblInfo.Caption := 'Open an image, drag a box to crop, then Render.';

  if FHasSel then
  begin
    n := NormalizeRectLocal(FSel);
    selW := n.Right - n.Left;
    selH := n.Bottom - n.Top;
    LblSel.Caption := Format('Selection: (%d,%d) - (%d,%d)  size=%dx%d px',
      [n.Left, n.Top, n.Right, n.Bottom, selW, selH]);
  end
  else
    LblSel.Caption := 'Selection: (none)';
end;

function TMainForm.NormalizeRectLocal(const R: TRect): TRect;
var
  t: Integer;
begin
  Result := R;
  if Result.Left > Result.Right then begin t := Result.Left; Result.Left := Result.Right; Result.Right := t; end;
  if Result.Top > Result.Bottom then begin t := Result.Top; Result.Top := Result.Bottom; Result.Bottom := t; end;
end;

function TMainForm.AvgColorInRect(const Img: TFPCustomImage; const R: TRect): TRGB;
var
  rr: TRect;
  x, y: Integer;
  stepX, stepY: Integer;
  sumR, sumG, sumB, cnt: Int64;
  c: TRGB;
begin
  Result := RGB(0, 0, 0);
  if not Assigned(Img) then Exit;

  rr := ClampRectToImage(R, Img.Width, Img.Height);

  // Sample at most ~64x64 points for speed (good enough for swatches).
  stepX := Max(1, (rr.Right - rr.Left) div 64);
  stepY := Max(1, (rr.Bottom - rr.Top) div 64);

  sumR := 0; sumG := 0; sumB := 0; cnt := 0;

  y := rr.Top;
  while y < rr.Bottom do
  begin
    x := rr.Left;
    while x < rr.Right do
    begin
      c := FPColorToRGB(Img.Colors[x, y]);
      Inc(sumR, c.R);
      Inc(sumG, c.G);
      Inc(sumB, c.B);
      Inc(cnt);
      Inc(x, stepX);
    end;
    Inc(y, stepY);
  end;

  if cnt > 0 then
    Result := RGB(ClampByte(Integer(sumR div cnt)),
                  ClampByte(Integer(sumG div cnt)),
                  ClampByte(Integer(sumB div cnt)));
end;

procedure TMainForm.UpdateHintsUI;
const
  AnsiNames: array[0..15] of string = (
    'Black','Blue','Green','Cyan','Red','Magenta','Brown','Light Gray',
    'Dark Gray','Light Blue','Light Green','Light Cyan','Light Red','Light Magenta','Yellow','White'
  );
var
  i: Integer;
  h: TColorHint;
begin
  if not Assigned(MemoHints) then Exit;

  MemoHints.Lines.BeginUpdate;
  try
    MemoHints.Lines.Clear;
    MemoHints.Lines.Add(Format('Hints: %d   (tolerance=%d)', [Length(FColorHints), SeHintTol.Value]));
    if Length(FColorHints) = 0 then
    begin
      MemoHints.Lines.Add('No hints yet. Drag a selection on the image and click "Add hint from selection".');
      Exit;
    end;

    for i := 0 to High(FColorHints) do
    begin
      h := FColorHints[i];
      MemoHints.Lines.Add(Format('%2d) %2d %s  src=(%3d,%3d,%3d)  strength=%d',
        [i+1, h.TargetIdx, AnsiNames[h.TargetIdx], h.Src.R, h.Src.G, h.Src.B, h.Strength]));
    end;
  finally
    MemoHints.Lines.EndUpdate;
  end;

  if Assigned(PbHintPalette) then PbHintPalette.Invalidate;
end;

procedure TMainForm.HintPalettePaint(Sender: TObject);
const
  Pad = 2;
var
  pal: TPaletteKind;
  i, j: Integer;
  r: TRect;
  c: TRGB;
  col: TColor;
  wCell: Integer;
  cnt: Integer;
begin
  if not Assigned(PbHintPalette) then Exit;

  // Determine current palette profile.
  // Swatches: show the standard DOS VGA 16-color palette.
  // (This keeps the UI consistent with how the output will be displayed.)
  pal := pkVGA;

  PbHintPalette.Canvas.Brush.Color := clBtnFace;
  PbHintPalette.Canvas.FillRect(PbHintPalette.ClientRect);

  wCell := (PbHintPalette.ClientWidth - Pad*2) div 16;
  if wCell < 8 then wCell := 8;

  PbHintPalette.Canvas.Font.Size := 8;

  for i := 0 to 15 do
  begin
    r.Left := Pad + i*wCell;
    r.Top := Pad;
    r.Right := r.Left + wCell - 1;
    r.Bottom := PbHintPalette.ClientHeight - Pad;

    c := Palette16(pal, i);
    col := ColorFromRGB(c);
    PbHintPalette.Canvas.Brush.Color := col;
    PbHintPalette.Canvas.Pen.Color := clBlack;
    PbHintPalette.Canvas.Rectangle(r);

    // Hint count badge
    cnt := 0;
    for j := 0 to High(FColorHints) do
      if FColorHints[j].TargetIdx = i then Inc(cnt);

    if cnt > 0 then
    begin
      PbHintPalette.Canvas.Brush.Style := bsClear;
      PbHintPalette.Canvas.Font.Color := clWhite;
      PbHintPalette.Canvas.TextOut(r.Left + 2, r.Top + 2, IntToStr(cnt));
      PbHintPalette.Canvas.Brush.Style := bsSolid;
      PbHintPalette.Canvas.Font.Color := clBlack;
    end;
  end;

  // Highlight currently selected ANSI target.
  if Assigned(CbHintColor) and (CbHintColor.ItemIndex >= 0) then
  begin
    i := CbHintColor.ItemIndex;
    r.Left := Pad + i*wCell;
    r.Top := Pad;
    r.Right := r.Left + wCell - 1;
    r.Bottom := PbHintPalette.ClientHeight - Pad;
    PbHintPalette.Canvas.Pen.Color := clLime;
    PbHintPalette.Canvas.Pen.Width := 2;
    PbHintPalette.Canvas.Brush.Style := bsClear;
    PbHintPalette.Canvas.Rectangle(r);
    PbHintPalette.Canvas.Pen.Width := 1;
  end;
end;

procedure TMainForm.HintPaletteMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
const
  Pad = 2;
var
  wCell: Integer;
  idx: Integer;
begin
  if (Button <> mbLeft) or (not Assigned(PbHintPalette)) or (not Assigned(CbHintColor)) then Exit;

  wCell := (PbHintPalette.ClientWidth - Pad*2) div 16;
  if wCell < 8 then wCell := 8;

  idx := (X - Pad) div wCell;
  if (idx < 0) or (idx > 15) then Exit;

  CbHintColor.ItemIndex := idx;
  PbHintPalette.Invalidate;
end;

procedure TMainForm.DoAddHintFromSel(Sender: TObject);
var
  n: TRect;
  h: TColorHint;
begin
  if not Assigned(FImg) then
  begin
    ShowMessage('Open an image first.');
    Exit;
  end;
  if not FHasSel then
  begin
    ShowMessage('Drag a selection box on the image (left panel) first.');
    Exit;
  end;
  if (not Assigned(CbHintColor)) or (CbHintColor.ItemIndex < 0) then
  begin
    ShowMessage('Pick an ANSI color first.');
    Exit;
  end;

  n := NormalizeRectLocal(FSel);
  h.Src := AvgColorInRect(FImg, n);
  h.TargetIdx := Byte(CbHintColor.ItemIndex);
  h.Strength := SeHintStrength.Value;

  SetLength(FColorHints, Length(FColorHints) + 1);
  FColorHints[High(FColorHints)] := h;

  UpdateHintsUI;
end;

procedure TMainForm.DoTogglePickHintDropper(Sender: TObject);
begin
  FPickHintMode := not FPickHintMode;
  if Assigned(BtnPickHintDropper) then
  begin
    if FPickHintMode then
      BtnPickHintDropper.Caption := 'Dropper: ON (click image)'
    else
      BtnPickHintDropper.Caption := 'Dropper: OFF (click image)';
  end;
  if Assigned(LblHintPick) then
  begin
    if FPickHintMode then
      LblHintPick.Caption := 'Dropper is ON: click the image preview to sample a color and add a hint.'
    else
      LblHintPick.Caption := 'Tip: Turn on Dropper, then click the image preview to add a hint.';
  end;
end;

procedure TMainForm.AddHintFromPoint(const PImg: TPoint);
var
  r: Integer;
  rr: TRect;
  h: TColorHint;
begin
  if not Assigned(FImg) then Exit;
  if (not Assigned(CbHintColor)) or (CbHintColor.ItemIndex < 0) then Exit;

  if Assigned(SeHintPickRadius) then
    r := SeHintPickRadius.Value
  else
    r := 0;

  rr := Rect(PImg.X - r, PImg.Y - r, PImg.X + r + 1, PImg.Y + r + 1);
  h.Src := AvgColorInRect(FImg, rr);
  h.TargetIdx := Byte(CbHintColor.ItemIndex);
  h.Strength := SeHintStrength.Value;

  SetLength(FColorHints, Length(FColorHints) + 1);
  FColorHints[High(FColorHints)] := h;

  // Visual feedback: show a small selection around the picked point.
  FSel := rr;
  FHasSel := True;
  FDragging := False;

  UpdateHintsUI;
  UpdateInfo;
  SrcBox.Invalidate;
end;

procedure TMainForm.DoClearHints(Sender: TObject);
begin
  SetLength(FColorHints, 0);
  UpdateHintsUI;
end;


procedure TMainForm.AtlasOptionsChanged(Sender: TObject);
begin
  if Assigned(CbAtlasMode) then
    FAtlasMode := CbAtlasMode.ItemIndex
  else
    FAtlasMode := 0;

  BuildAtlas;
  if Assigned(AtlasBox) then AtlasBox.Invalidate;
end;

procedure TMainForm.BuildAtlas;
const
  ShadeCount = 5;
  ShadeChars: array[0..ShadeCount-1] of Byte = (32, 176, 177, 178, 219); // ' ' ░ ▒ ▓ █
var
  cw, ch: Integer;
  cellW, cellH: Integer;
  marginL, marginT: Integer;
  cols, rowsBg: Integer;
  x, y, k: Integer;
  pal: TPaletteKind;
  rfg, rbg: TRGB;
  useGrid: Boolean;
  Dx: TDOSXBound;
  Dy: TDOSYBound;
  i: Integer;
  x0, y0: Integer;
  totalW, totalH: Integer;
  s: String;
begin
  if not Assigned(FAtlasBmp) then Exit;

  cw := SeCellW.Value;
  if cw < 4 then cw := 4;
  ch := cw * 2;

  cols := 16;
  rowsBg := 8;
  if Assigned(ChkAtlasIce) and ChkAtlasIce.Checked then rowsBg := 16;

  marginL := 28;
  marginT := 28;

  pal := pkVGA;
  useGrid := Assigned(ChkAtlasShowGrid) and ChkAtlasShowGrid.Checked;

  if FAtlasMode = 1 then
  begin
    cellW := cw * ShadeCount;
    cellH := ch;
  end
  else
  begin
    cellW := cw;
    cellH := ch;
  end;

  totalW := marginL + cols * cellW;
  totalH := marginT + rowsBg * cellH;

  FAtlasBmp.SetSize(totalW + 1, totalH + 1);

  // background
  FAtlasBmp.Canvas.Brush.Color := clBlack;
  FAtlasBmp.Canvas.FillRect(Rect(0, 0, FAtlasBmp.Width, FAtlasBmp.Height));

  // bounds for DOS glyph scaling
  for i := 0 to 8 do Dx[i] := (i * cw) div 8;
  for i := 0 to 16 do Dy[i] := (i * ch) div 16;

  // labels
  FAtlasBmp.Canvas.Brush.Style := bsClear;
  FAtlasBmp.Canvas.Font.Assign(FPreviewFont);
  FAtlasBmp.Canvas.Font.Size := Max(7, (ch div 2) - 2);
  FAtlasBmp.Canvas.Font.Color := clSilver;

  for x := 0 to cols - 1 do
  begin
    s := IntToHex(x, 1);
    FAtlasBmp.Canvas.TextOut(marginL + x * cellW + 2, 4, s);
  end;

  for y := 0 to rowsBg - 1 do
  begin
    s := IntToHex(y, 1);
    FAtlasBmp.Canvas.TextOut(4, marginT + y * cellH + 2, s);
  end;

  // draw atlas cells using BIOS glyph renderer (most consistent)
  for y := 0 to rowsBg - 1 do
    for x := 0 to cols - 1 do
    begin
      rfg := Palette16(pal, x);
      rbg := Palette16(pal, y);
      x0 := marginL + x * cellW;
      y0 := marginT + y * cellH;

      if FAtlasMode = 1 then
      begin
        for k := 0 to ShadeCount - 1 do
          DrawDOSGlyph8x16Scaled(FAtlasBmp.Canvas, x0 + k * cw, y0, Dx, Dy,
            ShadeChars[k], ColorFromRGB(rfg), ColorFromRGB(rbg));
      end
      else
      begin
        DrawDOSGlyph8x16Scaled(FAtlasBmp.Canvas, x0, y0, Dx, Dy,
          219, ColorFromRGB(rfg), ColorFromRGB(rbg)); // █
      end;
    end;

  // optional grid
  if useGrid then
  begin
    FAtlasBmp.Canvas.Brush.Style := bsClear;
    FAtlasBmp.Canvas.Pen.Color := clDkGray;

    // vertical
    for x := 0 to cols do
      FAtlasBmp.Canvas.Line(marginL + x * cellW, marginT,
                            marginL + x * cellW, marginT + rowsBg * cellH);

    // horizontal
    for y := 0 to rowsBg do
      FAtlasBmp.Canvas.Line(marginL, marginT + y * cellH,
                            marginL + cols * cellW, marginT + y * cellH);
  end;

  // restore brush
  FAtlasBmp.Canvas.Brush.Style := bsSolid;

  if Assigned(AtlasBox) then
  begin
    AtlasBox.Width := FAtlasBmp.Width;
    AtlasBox.Height := FAtlasBmp.Height;
  end;
end;

procedure TMainForm.AtlasPaint(Sender: TObject);
begin
  if not Assigned(AtlasBox) then Exit;

  AtlasBox.Canvas.Brush.Color := clBlack;
  AtlasBox.Canvas.FillRect(AtlasBox.Canvas.ClipRect);

  if Assigned(FAtlasBmp) then
    AtlasBox.Canvas.Draw(0, 0, FAtlasBmp);
end;



procedure TMainForm.AddRampPair(FG, BG: Byte);
var
  i: Integer;
begin
  // avoid duplicates
  for i := 0 to High(FRampPairs) do
    if (FRampPairs[i].FG = FG) and (FRampPairs[i].BG = BG) then Exit;

  SetLength(FRampPairs, Length(FRampPairs) + 1);
  FRampPairs[High(FRampPairs)].FG := FG;
  FRampPairs[High(FRampPairs)].BG := BG;
  UpdateRampListUI;
end;

procedure TMainForm.UpdateRampListUI;
var
  i: Integer;
  s: String;
begin
  if not Assigned(LbRamp) then Exit;
  LbRamp.Items.BeginUpdate;
  try
    LbRamp.Items.Clear;
    for i := 0 to High(FRampPairs) do
    begin
      s := Format('FG %d / BG %d', [FRampPairs[i].FG, FRampPairs[i].BG]);
      LbRamp.Items.Add(s);
    end;
  finally
    LbRamp.Items.EndUpdate;
  end;
end;

procedure TMainForm.RampClearClick(Sender: TObject);
begin
  SetLength(FRampPairs, 0);
  UpdateRampListUI;
end;

procedure TMainForm.RampRemoveClick(Sender: TObject);
var
  idx, i: Integer;
begin
  if not Assigned(LbRamp) then Exit;
  idx := LbRamp.ItemIndex;
  if (idx < 0) or (idx > High(FRampPairs)) then Exit;

  for i := idx to High(FRampPairs) - 1 do
    FRampPairs[i] := FRampPairs[i+1];
  SetLength(FRampPairs, Length(FRampPairs) - 1);
  UpdateRampListUI;
end;

function TMainForm.AtlasHitTest(X, Y: Integer; out FG, BG: Integer): Boolean;
const
  ShadeCount = 5;
var
  cw, ch: Integer;
  cellW, cellH: Integer;
  marginL, marginT: Integer;
  cols, rowsBg: Integer;
  gx, gy: Integer;
begin
  Result := False;
  FG := -1; BG := -1;

  cw := SeCellW.Value;
  if cw < 4 then cw := 4;
  ch := cw * 2;

  cols := 16;
  rowsBg := 8;
  if Assigned(ChkAtlasIce) and ChkAtlasIce.Checked then rowsBg := 16;

  marginL := 28;
  marginT := 28;

  if FAtlasMode = 1 then
  begin
    cellW := cw * ShadeCount;
    cellH := ch;
  end
  else
  begin
    cellW := cw;
    cellH := ch;
  end;

  if (X < marginL) or (Y < marginT) then Exit;

  gx := (X - marginL) div cellW;
  gy := (Y - marginT) div cellH;

  if (gx < 0) or (gx >= cols) then Exit;
  if (gy < 0) or (gy >= rowsBg) then Exit;

  FG := gx;
  BG := gy;
  Result := True;
end;

procedure TMainForm.AtlasMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  fg, bg: Integer;
  i, j: Integer;
begin
  if not AtlasHitTest(X, Y, fg, bg) then Exit;

  // Left click adds FG/BG to ramp list
  if Button = mbLeft then
  begin
    AddRampPair(Byte(fg), Byte(bg));
    Exit;
  end;

  // Right click removes that pair if present
  if Button = mbRight then
  begin
    for i := 0 to High(FRampPairs) do
      if (FRampPairs[i].FG = Byte(fg)) and (FRampPairs[i].BG = Byte(bg)) then
      begin
        for j := i to High(FRampPairs) - 1 do
          FRampPairs[j] := FRampPairs[j+1];
        SetLength(FRampPairs, Length(FRampPairs) - 1);
        Break;
      end;
    UpdateRampListUI;
  end;
end;

procedure TMainForm.OutMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  cw, ch: Integer;
  cx, cy: Integer;
begin
  if (FRows <= 0) then Exit;

  cw := SeCellW.Value;
  if cw < 4 then cw := 4;
  ch := cw * 2;

  cx := X div cw;
  cy := Y div ch;

  if cx < 0 then cx := 0;
  if cx > 79 then cx := 79;
  if cy < 0 then cy := 0;
  if cy > FRows - 1 then cy := FRows - 1;

  FSelCellX := cx;
  FSelCellY := cy;

  if Assigned(SeTileX) then SeTileX.Value := cx;
  if Assigned(SeTileY) then SeTileY.Value := cy;

  if Assigned(PbTilePrev) then PbTilePrev.Invalidate;
end;

procedure TMainForm.EnsureCellSample;
var
  targetW, targetH: Integer;
  srcW, srcH: Integer;
  crop: TRect;

  function ClampI(v, lo, hi: Integer): Integer; inline;
  begin
    if v < lo then Exit(lo);
    if v > hi then Exit(hi);
    Result := v;
  end;

  function GetRGBAtBilinear(const fx, fy: Double): TRGB;
  var
    x0, y0, x1, y1: Integer;
    tx, ty: Double;
    c00, c10, c01, c11: TFPColor;
    r, g, b: Double;
    function Chan16To255(v: Word): Double; inline;
    begin
      Result := (v / 65535.0) * 255.0;
    end;
  begin
    x0 := ClampI(Floor(fx), crop.Left, crop.Right-1);
    y0 := ClampI(Floor(fy), crop.Top, crop.Bottom-1);
    x1 := ClampI(x0 + 1, crop.Left, crop.Right-1);
    y1 := ClampI(y0 + 1, crop.Top, crop.Bottom-1);
    tx := fx - x0;
    ty := fy - y0;

    c00 := FImg.Colors[x0, y0];
    c10 := FImg.Colors[x1, y0];
    c01 := FImg.Colors[x0, y1];
    c11 := FImg.Colors[x1, y1];

    r := (1-ty)*((1-tx)*Chan16To255(c00.red) + tx*Chan16To255(c10.red)) +
         ty *((1-tx)*Chan16To255(c01.red) + tx*Chan16To255(c11.red));
    g := (1-ty)*((1-tx)*Chan16To255(c00.green) + tx*Chan16To255(c10.green)) +
         ty *((1-tx)*Chan16To255(c01.green) + tx*Chan16To255(c11.green));
    b := (1-ty)*((1-tx)*Chan16To255(c00.blue) + tx*Chan16To255(c10.blue)) +
         ty *((1-tx)*Chan16To255(c01.blue) + tx*Chan16To255(c11.blue));

    Result.r := ClampI(Round(r), 0, 255);
    Result.g := ClampI(Round(g), 0, 255);
    Result.b := ClampI(Round(b), 0, 255);
  end;

var
  x, y: Integer;
  fx, fy: Double;
  c: TRGB;
  fp: TFPColor;
begin
  if (not Assigned(FImg)) or (FImg.Width <= 0) or (FImg.Height <= 0) then Exit;
  if (FRows <= 0) then Exit;

  targetW := 80 * 8;
  targetH := FRows * 16;

  if not Assigned(FCellSample) then
  begin
    FCellSample := TFPMemoryImage.Create(targetW, targetH);
    FCellSampleValid := False;
  end;

  if (FCellSample.Width <> targetW) or (FCellSample.Height <> targetH) then
  begin
    FCellSample.SetSize(targetW, targetH);
    FCellSampleValid := False;
  end;

  if FCellSampleValid then Exit;

  // Determine crop rect in source image coordinates
  crop := Rect(0, 0, FImg.Width, FImg.Height);
  if Assigned(ChkUseSel) and ChkUseSel.Checked and FHasSel then
  begin
    // normalize selection
    crop.Left := Min(FSel.Left, FSel.Right);
    crop.Right := Max(FSel.Left, FSel.Right);
    crop.Top := Min(FSel.Top, FSel.Bottom);
    crop.Bottom := Max(FSel.Top, FSel.Bottom);

    // clamp
    crop.Left := ClampI(crop.Left, 0, FImg.Width-1);
    crop.Top := ClampI(crop.Top, 0, FImg.Height-1);
    crop.Right := ClampI(crop.Right, crop.Left+1, FImg.Width);
    crop.Bottom := ClampI(crop.Bottom, crop.Top+1, FImg.Height);
  end;

  srcW := crop.Right - crop.Left;
  srcH := crop.Bottom - crop.Top;

  // Resample to cell-pixel space (80*8 by rows*16)
  for y := 0 to targetH - 1 do
  begin
    fy := crop.Top + ((y + 0.5) / targetH) * srcH - 0.5;
    for x := 0 to targetW - 1 do
    begin
      fx := crop.Left + ((x + 0.5) / targetW) * srcW - 0.5;
      c := GetRGBAtBilinear(fx, fy);
      fp.red := Round((c.r / 255.0) * 65535);
      fp.green := Round((c.g / 255.0) * 65535);
      fp.blue := Round((c.b / 255.0) * 65535);
      fp.alpha := 65535;
      FCellSample.Colors[x, y] := fp;
    end;
  end;

  FCellSampleValid := True;
end;

procedure TMainForm.ExtractTileSamples(CellX, CellY: Integer; Use3x3: Boolean; out aTile: TRGBTile128);
var
  x, y: Integer;
  sx, sy: Integer;
  ax, ay: Integer;
  cnt: Integer;
  c: TFPColor;
  r, g, b: Integer;
  function Chan16To8(v: Word): Integer; inline;
  begin
    Result := (v * 255) div 65535;
  end;
begin
  FillChar(atile, SizeOf(atile), 0);
  EnsureCellSample;
  if (not Assigned(FCellSample)) or (not FCellSampleValid) then Exit;

  for y := 0 to 15 do
  begin
    for x := 0 to 7 do
    begin
      if not Use3x3 then
      begin
        sx := CellX*8 + x;
        sy := CellY*16 + y;
        if (sx < 0) or (sx >= FCellSample.Width) or (sy < 0) or (sy >= FCellSample.Height) then
          Continue;
        c := FCellSample.Colors[sx, sy];
        atile[y*8 + x].r := Chan16To8(c.red);
        atile[y*8 + x].g := Chan16To8(c.green);
        atile[y*8 + x].b := Chan16To8(c.blue);
      end
      else
      begin
        // average a 3x3 neighborhood of cells (stabilizes color/blocks)
        r := 0; g := 0; b := 0; cnt := 0;
        for ay := -1 to 1 do
          for ax := -1 to 1 do
          begin
            sx := (CellX+ax)*8 + x;
            sy := (CellY+ay)*16 + y;
            if (sx < 0) or (sx >= FCellSample.Width) or (sy < 0) or (sy >= FCellSample.Height) then
              Continue;
            c := FCellSample.Colors[sx, sy];
            Inc(r, Chan16To8(c.red));
            Inc(g, Chan16To8(c.green));
            Inc(b, Chan16To8(c.blue));
            Inc(cnt);
          end;
        if cnt > 0 then
        begin
          atile[y*8 + x].r := r div cnt;
          atile[y*8 + x].g := g div cnt;
          atile[y*8 + x].b := b div cnt;
        end;
      end;
    end;
  end;
end;

procedure TMainForm.RenderGlyphTile(ch: Byte; fgIdx, bgIdx: Byte; out aTile: TRGBTile128);
var
  fg, bg: TRGB;
  row, col: Integer;
  mask: Byte;
  bit: Byte;
begin
  fg := Palette16(pkVGA, fgIdx);
  bg := Palette16(pkVGA, bgIdx);
  for row := 0 to 15 do
  begin
    mask := DOSFontModernDOS8x16[ch, row];
    for col := 0 to 7 do
    begin
      bit := 1 shl (7 - col);
      if (mask and bit) <> 0 then
        atile[row*8 + col] := fg
      else
        atile[row*8 + col] := bg;
    end;
  end;
end;

function TMainForm.TileMatchPct(const a, b: TRGBTile128): Integer;
var
  i: Integer;
  err: Int64;
  dr, dg, db: Integer;
  maxErr: Double;
  pct: Double;
begin
  err := 0;
  for i := 0 to 127 do
  begin
    dr := a[i].r - b[i].r;
    dg := a[i].g - b[i].g;
    db := a[i].b - b[i].b;
    err := err + Int64(dr*dr + dg*dg + db*db);
  end;

  // max per-pixel squared error = 3 * 255^2
  maxErr := 128.0 * 3.0 * 255.0 * 255.0;
  pct := 100.0 * (1.0 - (err / maxErr));
  if pct < 0 then pct := 0;
  if pct > 100 then pct := 100;
  Result := Round(pct);
end;

procedure TMainForm.TilePrevPaint(Sender: TObject);
var
  atile: TRGBTile128;
  x, y: Integer;
  scale: Integer;
  R: TRect;
  c: TRGB;
begin
  if (not Assigned(SeTileX)) or (not Assigned(SeTileY)) then Exit;
  if not Assigned(PbTilePrev) then Exit;

  PbTilePrev.Canvas.Brush.Color := clBlack;
  PbTilePrev.Canvas.FillRect(PbTilePrev.Canvas.ClipRect);

  // Show the target tile from source (using current selection toggle)
  ExtractTileSamples(SeTileX.Value, SeTileY.Value, Assigned(ChkTile3x3) and ChkTile3x3.Checked, atile);

  scale := 10;
  for y := 0 to 15 do
    for x := 0 to 7 do
    begin
      c := atile[y*8 + x];
      PbTilePrev.Canvas.Brush.Color := ColorFromRGB(c);
      R := Rect(x*scale, y*scale, (x+1)*scale, (y+1)*scale);
      PbTilePrev.Canvas.FillRect(R);
    end;
end;

procedure TMainForm.TileEvalClick(Sender: TObject);
const
  BlockCount = 5;
  BlockChars: array[0..BlockCount-1] of Byte = (32, 176, 177, 178, 219); // space, ░▒▓█
type
  TBestItem = record
    Pct: Integer;
    FG, BG: Byte;
    Ch: Byte;
    IsBlock: Boolean;
  end;
var
  target: TRGBTile128;
  cand: TRGBTile128;
  bestList: array of TBestItem;
  function AddBest(pct: Integer; fg, bg, ch: Byte; isBlock: Boolean): Boolean;
  var
    i, worstI: Integer;
    worstPct: Integer;
  begin
    // Safe default
    Result := False;
    // Keep top 25
    if Length(bestList) < 25 then
    begin
      SetLength(bestList, Length(bestList)+1);
      bestList[High(bestList)].Pct := pct;
      bestList[High(bestList)].FG := fg;
      bestList[High(bestList)].BG := bg;
      bestList[High(bestList)].Ch := ch;
      bestList[High(bestList)].IsBlock := isBlock;
      Exit(True);
    end;

    worstI := 0;
    worstPct := bestList[0].Pct;
    for i := 1 to High(bestList) do
      if bestList[i].Pct < worstPct then
      begin
        worstPct := bestList[i].Pct;
        worstI := i;
      end;

    if pct > worstPct then
    begin
      bestList[worstI].Pct := pct;
      bestList[worstI].FG := fg;
      bestList[worstI].BG := bg;
      bestList[worstI].Ch := ch;
      bestList[worstI].IsBlock := isBlock;
      Exit(True);
    end;
  end;

  procedure SortBest;
  var
    i, j: Integer;
    tmp: TBestItem;
    function Better(const a, b: TBestItem): Boolean;
    begin
      // Primary: higher match percent first
      if a.Pct <> b.Pct then Exit(a.Pct > b.Pct);
      // Secondary: prefer blocks/shades when tied (optional but useful)
      if a.IsBlock <> b.IsBlock then Exit(a.IsBlock and (not b.IsBlock));
      // Tertiary: keep deterministic ordering
      if a.FG <> b.FG then Exit(a.FG < b.FG);
      if a.BG <> b.BG then Exit(a.BG < b.BG);
      Exit(a.Ch < b.Ch);
    end;
  begin
    if Length(bestList) <= 1 then Exit;
    for i := 0 to High(bestList) - 1 do
      for j := i + 1 to High(bestList) do
        if Better(bestList[j], bestList[i]) then
        begin
          tmp := bestList[i];
          bestList[i] := bestList[j];
          bestList[j] := tmp;
        end;
  end;

var
  ramps: TRampPairArray;
  fg, bg: Byte;
  bgMax: Integer;
  iRamp,i: Integer;
  ch: Integer;
  pct: Integer;
  use3x3: Boolean;
  blocksPreferPct, use3x3BelowPct: Integer;
  kind: String;
begin
  if not Assigned(LbTileRes) then Exit;
  if (FRows <= 0) then Exit;

  use3x3 := Assigned(ChkTile3x3) and ChkTile3x3.Checked;
  ExtractTileSamples(SeTileX.Value, SeTileY.Value, use3x3, target);

  blocksPreferPct := 88;
  use3x3BelowPct := 70;
  if Assigned(SeShaderBlocksPct) then blocksPreferPct := SeShaderBlocksPct.Value;
  if Assigned(SeShader3x3Pct) then use3x3BelowPct := SeShader3x3Pct.Value;

  // Candidate ramps: use picked ramps if any, else full range
  if Length(FRampPairs) > 0 then
    ramps := FRampPairs
  else
  begin
    bgMax := 7;
    if Assigned(ChkIce) and ChkIce.Checked then bgMax := 15;
    SetLength(ramps, 0);
    for bg := 0 to bgMax do
      for fg := 0 to 15 do
        if fg <> bg then
        begin
          SetLength(ramps, Length(ramps)+1);
          ramps[High(ramps)].FG := fg;
          ramps[High(ramps)].BG := bg;
        end;
  end;

  SetLength(bestList, 0);

  // Evaluate candidates
  for iRamp := 0 to High(ramps) do
  begin
    fg := ramps[iRamp].FG;
    bg := ramps[iRamp].BG;

    // Block-only quick check
    for i := 0 to BlockCount-1 do
    begin
      ch := BlockChars[i];
      RenderGlyphTile(Byte(ch), fg, bg, cand);
      pct := TileMatchPct(target, cand);
      AddBest(pct, fg, bg, Byte(ch), True);
    end;

    // Full CP437 printable range
    for ch := 32 to 255 do
    begin
      RenderGlyphTile(Byte(ch), fg, bg, cand);
      pct := TileMatchPct(target, cand);
      AddBest(pct, fg, bg, Byte(ch), False);
    end;
  end;

  SortBest;

  LbTileRes.Items.BeginUpdate;
  try
    LbTileRes.Items.Clear;
    LbTileRes.Items.Add(Format('Tile (%d,%d)  |  3x3=%s', [SeTileX.Value, SeTileY.Value, BoolToStr(use3x3, True)]));
    LbTileRes.Items.Add(Format('Thresholds: prefer blocks >= %d%%  |  refine blocks (3x3) below %d%%', [blocksPreferPct, use3x3BelowPct]));
    LbTileRes.Items.Add('--- Top matches ---');
    for ch := 0 to Min(High(bestList), 20) do
    begin
      if bestList[ch].IsBlock then kind := 'block/shade' else kind := 'cp437';
      LbTileRes.Items.Add(Format('%3d%%  FG %2d  BG %2d  Ch %3d  %s',
        [bestList[ch].Pct, bestList[ch].FG, bestList[ch].BG, bestList[ch].Ch, kind]));
    end;
  finally
    LbTileRes.Items.EndUpdate;
  end;

  if Assigned(PbTilePrev) then PbTilePrev.Invalidate;
end;

function TMainForm.GetImageDrawRect: TRect;
var
  W, H: Integer;
  scale: Double;
  dw, dh: Integer;
  ox, oy: Integer;
begin
  if (FSrcBmp.Width <= 0) or (FSrcBmp.Height <= 0) then
    Exit(Rect(0, 0, 0, 0));

  W := SrcBox.ClientWidth;
  H := SrcBox.ClientHeight;

  scale := Min(W / FSrcBmp.Width, H / FSrcBmp.Height);
  dw := Max(1, Round(FSrcBmp.Width * scale));
  dh := Max(1, Round(FSrcBmp.Height * scale));
  ox := (W - dw) div 2;
  oy := (H - dh) div 2;

  Result := Rect(ox, oy, ox + dw, oy + dh);
end;

function TMainForm.ViewToImagePoint(const P: TPoint): TPoint;
var
  R: TRect;
  scale: Double;
  ix, iy: Integer;
begin
  R := GetImageDrawRect;
  if (R.Right <= R.Left) or (R.Bottom <= R.Top) or (FSrcBmp.Width = 0) then
    Exit(Point(0, 0));

  scale := (R.Right - R.Left) / FSrcBmp.Width;

  ix := Round((P.X - R.Left) / scale);
  iy := Round((P.Y - R.Top) / scale);

  ix := EnsureRange(ix, 0, FSrcBmp.Width - 1);
  iy := EnsureRange(iy, 0, FSrcBmp.Height - 1);

  Result := Point(ix, iy);
end;

function TMainForm.ImageToViewRect(const R: TRect): TRect;
var
  D: TRect;
  scale: Double;
begin
  D := GetImageDrawRect;
  if (D.Right <= D.Left) or (D.Bottom <= D.Top) or (FSrcBmp.Width = 0) then
    Exit(Rect(0, 0, 0, 0));

  scale := (D.Right - D.Left) / FSrcBmp.Width;

  Result.Left := D.Left + Round(R.Left * scale);
  Result.Top := D.Top + Round(R.Top * scale);
  Result.Right := D.Left + Round(R.Right * scale);
  Result.Bottom := D.Top + Round(R.Bottom * scale);
end;

procedure TMainForm.DoOpen(Sender: TObject);
var
  pic: TPicture;
  newImg, newOrig: TFPMemoryImage;
  newFileName: string;
begin
  if not OpenDlg.Execute then Exit;
  newFileName := OpenDlg.FileName;

  pic := nil;
  newImg := nil;
  newOrig := nil;

  try
    // Load into temporaries first, so a failure won't destroy the current session.
    newImg := LoadAnyImage(newFileName);

    newOrig := TFPMemoryImage.Create(0, 0);
    CopyFPImage(newImg, newOrig);

    pic := TPicture.Create;
    pic.LoadFromFile(newFileName);

    // Commit the swap only after everything succeeded.
    FFileName := newFileName;

    FreeAndNil(FImg);
    FImg := newImg;
    newImg := nil;

    FreeAndNil(FOrigImg);
    FOrigImg := newOrig;
    newOrig := nil;

    FSrcBmp.Assign(pic.Bitmap);

    FHasSel := False;
    FDragging := False;
    SetLength(FCells, 0);
    FRows := 0;

    UpdateInfo;
    SrcBox.Invalidate;
    OutBox.Invalidate;

  except
    on E: Exception do
      MessageDlg('Open failed', E.Message, mtError, [mbOK], 0);
  end;

  if Assigned(pic) then pic.Free;
  if Assigned(newImg) then newImg.Free;
  if Assigned(newOrig) then newOrig.Free;
end;


procedure TMainForm.UpdatePreMatchPaletteCache;
var
  fn: string;
  pal: TRGBArray;
begin
  fn := '';
  if Assigned(EdPreMatchPal) then
    fn := Trim(EdPreMatchPal.Text);

  // Only reload if the filename changed (avoids repeated disk reads during preview).
  if fn = FPreMatchPalFile then Exit;

  FPreMatchPalFile := fn;
  SetLength(FPreMatchPalette, 0);
  if fn = '' then Exit;

  if LoadHexPalette(fn, pal) then
  begin
    // Palette files must have at least 2 colors to be usable.
    if Length(pal) >= 2 then
      FPreMatchPalette := pal
    else
      SetLength(FPreMatchPalette, 0);
  end;
end;

function TMainForm.GetOptions: TConvertOptions;
var
  n: TRect;
  vInt: Integer;

  function SpinVal(SE: TSpinEdit): Integer;
  begin
    Result := SE.Value;
    // If the user typed a value but hasn't left the control,
    // Text can be newer than Value. Commit it.
    if TryStrToInt(Trim(SE.Text), vInt) then
    begin
      if vInt < SE.MinValue then vInt := SE.MinValue;
      if vInt > SE.MaxValue then vInt := SE.MaxValue;
      SE.Value := vInt;
      Result := vInt;
    end;
  end;
begin
  // Ensure all fields are initialized (important as options record grows).
  FillChar(Result, SizeOf(Result), 0);

  ApplyStyle(CbStyle.Text, Result);

  Result.ForcedRows := SpinVal(SeRows);
  if Result.ForcedRows = 0 then Result.ForcedRows := -1;

  Result.WinX := SpinVal(SeWinX);
  Result.WinY := SpinVal(SeWinY);

  Result.Aspect := FeAspect.Value;
  Result.Gamma := FeGamma.Value;
  Result.Contrast := FeContrast.Value;
  Result.Saturation := FeSaturation.Value;
  if Assigned(FeBrightness) then
    Result.Brightness := FeBrightness.Value
  else
    Result.Brightness := 1.00;
  Result.DitherStrength := FeDitherStrength.Value;

  Result.Ice := ChkIce.Checked;

  case LowerCase(CbPalette.Text) of
    'gray16': Result.Palette := pkGray;
    'win16':  Result.Palette := pkWin;
  else
    Result.Palette := pkVGA;
  end;
  Result.PaletteMatch := ChkPalMatch.Checked;

// Optional custom pre-match palette: if a .hex file is provided and valid (2..256 colors),
// it will be used for the pre-match stage; otherwise fall back to the built-in ANSI16 pre-match.
UpdatePreMatchPaletteCache;
Result.PreMatchHexFile := FPreMatchPalFile;
if Result.PaletteMatch and (Length(FPreMatchPalette) >= 2) then
  Result.PreMatchPalette := Copy(FPreMatchPalette)
else
  SetLength(Result.PreMatchPalette, 0);

  // Bayer 4x4 ordered dither strength for custom pre-match palettes (0..100)
  if Assigned(TbPreMatchBayer) then
    Result.PreMatchBayerStrength := TbPreMatchBayer.Position
  else
    Result.PreMatchBayerStrength := 50;

  // Global glyph bias weights (100=neutral)
  if Assigned(SeBlockUpWeight) then Result.BlockUpWeight := SpinVal(SeBlockUpWeight) else Result.BlockUpWeight := 100;
  if Assigned(SeBlockDownWeight) then Result.BlockDownWeight := SpinVal(SeBlockDownWeight) else Result.BlockDownWeight := 100;
  if Assigned(SeShadeBlockWeight) then Result.ShadeBlockWeight := SpinVal(SeShadeBlockWeight) else Result.ShadeBlockWeight := 100;
  if Assigned(CbMetric) then
    Result.ColorMetric := TColorMetric(EnsureRange(CbMetric.ItemIndex, 0, Ord(High(TColorMetric))))
  else
    Result.ColorMetric := cmRedmean;

  if Assigned(SeColorMatch) then
    Result.ColorMatchPct := SpinVal(SeColorMatch)
  else
    Result.ColorMatchPct := 100;

  // Fine weights for cmYCbCr (if other metrics are selected, these are harmless).
  if Assigned(SeYWeight) then Result.YWeightPct := SpinVal(SeYWeight) else Result.YWeightPct := 100;
  if Assigned(SeCbWeight) then Result.CbWeightPct := SpinVal(SeCbWeight) else Result.CbWeightPct := 100;
  if Assigned(SeCrWeight) then Result.CrWeightPct := SpinVal(SeCrWeight) else Result.CrWeightPct := 100;

  case LowerCase(CbDither.Text) of
    'none':        Result.Dither := dmNone;
    'atkinson':    Result.Dither := dmAtkinson;
    'jjn':         Result.Dither := dmJJN;
    'stucki':      Result.Dither := dmStucki;
    'sierra-lite': Result.Dither := dmSierraLite;
    'bayer4':      Result.Dither := dmBayer4;
  else
    Result.Dither := dmFS;
  end;


  // Cell-level diffusion (regular modes)
  if Assigned(CbCellDiffModel) then
    Result.CellDiffusionModel := TCellDiffusionModel(EnsureRange(CbCellDiffModel.ItemIndex, 0, Ord(High(TCellDiffusionModel))))
  else
    Result.CellDiffusionModel := cdmOff;
  if Assigned(SeCellDiffAmt) then Result.CellDiffusionAmount := SpinVal(SeCellDiffAmt) else Result.CellDiffusionAmount := 35;
  if Assigned(SeCellTone) then Result.CellToneCorrection := SpinVal(SeCellTone) else Result.CellToneCorrection := 0;

  case LowerCase(CbMode.Text) of
    'hires':  Result.Mode := rmHires;
    'shades': Result.Mode := rmShades;
    'cartoon': Result.Mode := rmCartoon;
    'colorbook': Result.Mode := rmColorBook;
    'glyphfit': Result.Mode := rmGlyphFit;
    'autoshader': Result.Mode := rmAutoShader;
    'tronicshade': Result.Mode := rmHybrid;
  else
    Result.Mode := rmHybrid;
  end;
  // ANSIrez mode removed
  Result.AnsiRezMode := False;
  Result.AnsiRezFilter := afMedian;



  // GlyphFit options
  if Assigned(CbGlyphSet) then
    Result.GlyphSet := TGlyphSetKind(EnsureRange(CbGlyphSet.ItemIndex, 0, Ord(High(TGlyphSetKind))))
  else
    Result.GlyphSet := gsLines;

  
  // Tronicshade uses its own isolated glyph set.
  if Assigned(CbTronicGlyphSet) then
    Result.TronicGlyphSet := TGlyphSetKind(EnsureRange(CbTronicGlyphSet.ItemIndex, 0, Ord(High(TGlyphSetKind))))
  else
    Result.TronicGlyphSet := gsAnsiBlocksPixel;

  if Assigned(ChkTronicGlyphOnly) and ChkTronicGlyphOnly.Checked then
    Result.TronicApplyMode := 1
  else
    Result.TronicApplyMode := 0;

// Tronic edge shading controls (isolated)
Result.TronicEdgeShadeEnabled := Assigned(ChkTronicEdgeShade) and ChkTronicEdgeShade.Checked;

if Assigned(CbTronicEdgeSample) then
begin
  // items: 2x2, 3x3, 4x4
  case CbTronicEdgeSample.ItemIndex of
    0: Result.TronicEdgeSampleSize := 2;
    2: Result.TronicEdgeSampleSize := 4;
  else
    Result.TronicEdgeSampleSize := 3;
  end;
end
else
  Result.TronicEdgeSampleSize := 3;

// Tronic edge post-shade tuning
if Assigned(TbTronicBlockThreshold) then
  Result.TronicBlockThreshold := TbTronicBlockThreshold.Position
else
  Result.TronicBlockThreshold := 20;

if Assigned(TbTronicShadeWeight) then
  Result.TronicShadeWeight := TbTronicShadeWeight.Position
else
  Result.TronicShadeWeight := 120;

Result.TronicCornersShadesOnly := Assigned(ChkTronicCornersShadesOnly) and ChkTronicCornersShadesOnly.Checked;



// Gradient/ramp restriction
  if Assigned(CbGradMode) then
    Result.GradientMode := TGradientMode(EnsureRange(CbGradMode.ItemIndex, 0, 2))
  else
    Result.GradientMode := gmOff;

  if Assigned(CbGradSet) then
    Result.GradientSet := EnsureRange(CbGradSet.ItemIndex, 0, GRADIENT_COUNT-1)
  else
    Result.GradientSet := 0;

  if Assigned(FeGlyphSmooth) then
    Result.GlyphSmooth := FeGlyphSmooth.Value
  else
    Result.GlyphSmooth := 0.0;

  if Assigned(FeShadeBlend) then
    Result.ShadeBlend := FeShadeBlend.Value
  else
    Result.ShadeBlend := 0.0;

  // AutoShader / GlyphFit helpers
  Result.UseShaderLib := Assigned(ChkUseShader) and ChkUseShader.Checked;
  // Shader BIN should help guide colors, but it should *never* make the render
  // fail (e.g., by providing zero valid candidates). Keep it non-strict.
  Result.ShaderStrictGlyphMatch := False;
  Result.DosBoxModel := Assigned(ChkDosBoxModel) and ChkDosBoxModel.Checked;


  // Two-cluster per-cell FG/BG guess (enabled by default; no UI control yet)
  Result.TwoClusterGuess := True;
  Result.TwoClusterStrength := 110;

  if Assigned(SeShaderPasses) then Result.AutoShaderPasses := SpinVal(SeShaderPasses)
  else Result.AutoShaderPasses := 4;
  if Assigned(SeShader3x3Pct) then Result.AutoShader3x3BelowPct := SpinVal(SeShader3x3Pct)
  else Result.AutoShader3x3BelowPct := 70;
  if Assigned(SeShaderBlocksPct) then Result.AutoShaderBlocksOnlyPct := SpinVal(SeShaderBlocksPct)
  else Result.AutoShaderBlocksOnlyPct := 88;

  Result.UseCrop := ChkUseSel.Checked and FHasSel;
  if Result.UseCrop then
  begin
    n := NormalizeRectLocal(FSel);
    Result.Crop := n;
  end
  else
    Result.Crop := Rect(0, 0, 0, 0);

// Color hints
if Assigned(SeHintTol) then
  Result.HintTolerance := SpinVal(SeHintTol)
else
  Result.HintTolerance := 0;
Result.ColorHints := FColorHints;
Result.UseHintPalette := Assigned(ChkHintUsePalette) and ChkHintUsePalette.Checked;

  // Hint post-pass snap
  Result.HintPostFix := Assigned(ChkHintPostFix) and ChkHintPostFix.Checked;
  if Assigned(SeHintPostPct) then Result.HintPostFixPct := SpinVal(SeHintPostPct)
  else Result.HintPostFixPct := 90;

  Result.RefitHintedPaletteEachPass := Assigned(ChkRefitHintPalette) and ChkRefitHintPalette.Checked;

  // Tronicshade (rmTronicShade) controls
  if Assigned(SeTronicStrength) then
    Result.TronicCharStrength := SpinVal(SeTronicStrength)
  else
    Result.TronicCharStrength := 100;
  Result.TronicLumaOnly := Assigned(ChkTronicLumaOnly) and ChkTronicLumaOnly.Checked;

  if Assigned(SeTronicTone) then Result.TronicToneCorrection := SpinVal(SeTronicTone)
  else Result.TronicToneCorrection := 20;

  // AutoShader tone field (10x10 window stepping by 5 by default)
  Result.TronicAutoShaderEnabled := Assigned(ChkTronicAutoShader) and ChkTronicAutoShader.Checked;
  if Assigned(SeTronicWin) then Result.TronicWindowSize := SpinVal(SeTronicWin) else Result.TronicWindowSize := 10;
  if Assigned(SeTronicStep) then Result.TronicWindowStep := SpinVal(SeTronicStep) else Result.TronicWindowStep := 5;

  // Diffusion model + amount
  if Assigned(CbTronicDiffModel) then
    Result.TronicDiffusionModel := TTronicDiffusionModel(EnsureRange(CbTronicDiffModel.ItemIndex, 0, Ord(High(TTronicDiffusionModel))))
  else
    Result.TronicDiffusionModel := tdmOrderedBayer4;

  if Assigned(SeTronicDiffAmt) then Result.TronicDiffusionAmount := SpinVal(SeTronicDiffAmt)
  else Result.TronicDiffusionAmount := 20;

  // Color metric (used when not in luma-only mode)
  if Assigned(CbTronicColorMetric) then
    Result.TronicColorMetric := TTronicColorMetric(EnsureRange(CbTronicColorMetric.ItemIndex, 0, Ord(High(TTronicColorMetric))))
  else
    Result.TronicColorMetric := tcmLumaOnly;

  // Legacy checkbox overrides the dropdown
  if Result.TronicLumaOnly then
    Result.TronicColorMetric := tcmLumaOnly;

  // -----------------------------------------------------------------------
  // Tronicshade isolation: when Mode=rmTronicShade, ignore global controls
  // that can interfere (shaderlib, gradients, patch-style, glyph restrictions).
  // All Tronicshade behavior is controlled from the Tronicshade tab.
  if Result.Mode = rmTronicShade then
  begin
    // Never use ShaderLib / AutoShader constraints in Tronicshade.
    Result.UseShaderLib := False;
    Result.ShaderStrictGlyphMatch := False;
    // Ignore non-tronic gradient restrictions.
    Result.GradientMode := gmOff;
    Result.GradientSet := 0;
    // Force the broad glyph cache; Tronicshade will self-restrict internally.
    Result.GlyphSet := gsFull;
    // Disable PatchStyle in Tronicshade (Tronic has its own patch logic).
    Result.PatchStyleEnabled := False;
    Result.PatchUse10 := False;
    Result.PatchUse5 := False;
    Result.PatchUse3 := False;
  end;

  // Progress/cancel hooks are assigned only during conversion.
  Result.OnProgress := nil;
  Result.CancelFlag := nil;
end;

// Apply heavier conversion knobs when HQMode is selected.
// This is intentionally slow/high-quality and should be used for both preview (when user selects HQMode)
// and export (HQ export path re-runs conversion with the same tuning).
procedure ApplyHQModeTuning(var Opt: TConvertOptions);
begin
  case Opt.HQMode of
    2:
    begin
      // Better palette matching + perceptual distance (slow, but usually closer).
      Opt.PaletteMatch := True;
      Opt.ColorMetric := cmLab2000;
      if Opt.ColorMatchPct < 140 then Opt.ColorMatchPct := 140;

      // Larger sampling window reduces speckle and improves stability.
      if Opt.WinX < 5 then Opt.WinX := 5;
      if Opt.WinY < 5 then Opt.WinY := 5;

      // Supersample the per-cell 8x16 target tile (big quality win on thin lines/diagonals).
      // Heavy, but HQMode is explicitly allowed to be slow.
      if Opt.HQSuperSample < 2 then Opt.HQSuperSample := 2;

      // Mild unsharp/micro-contrast on the 8x16 target tile to help glyph choices.
      if Opt.HQSharpAmount <= 0 then Opt.HQSharpAmount := 0.14;

      // More refinement passes for AutoShader/GlyphFit paths.
      if Opt.AutoShaderPasses < 6 then Opt.AutoShaderPasses := 6;

      // Match what you'll see in DOSBox terminals (better block/shade scoring).
      Opt.DosBoxModel := True;

      // Stronger per-cell 2-cluster guess (helps edges and two-tone regions).
      Opt.TwoClusterGuess := True;
      if Opt.TwoClusterStrength < 130 then Opt.TwoClusterStrength := 130;

      // If the user uses color hints, keep refitting hinted entries each pass.
      Opt.RefitHintedPaletteEachPass := True;
    end;
  end;
end;

procedure TMainForm.RenderCore(const ShowProgress: Boolean; const AllowTronicReport: Boolean);
var
  opt: TConvertOptions;
  trRep: TTronicRenderReport;
  showTronicReport: Boolean;
  msg: String;
  avgErr: Double;
  avgMatch: Double;
  avgToneAbs: Double;
  incBlocks: Boolean;
  rs: TTronicRetroStyle;
  tex: Integer;
  // Some conversion paths (notably GlyphFit / AutoShader) expect CancelFlag to be
  // non-nil and will dereference it frequently. For silent auto-preview renders we
  // don't show a cancel button, but we still provide a valid flag to avoid AVs.
begin
  if not Assigned(FImg) then Exit;
  opt := GetOptions;
  if opt.HQMode > 0 then
    ApplyHQModeTuning(opt);
  showTronicReport := AllowTronicReport and FShowTronicReportAfterRender and (opt.Mode = rmTronicShade);
  if showTronicReport then
    opt.TronicReport := @trRep
  else
    opt.TronicReport := nil;
  if ShowProgress then
    StartProgressUI('Converting...');
  try
    if ShowProgress then
    begin
      // Provide progress + cancel hooks to the converter.
      opt.OnProgress := @ProgressUpdate;
      opt.CancelFlag := @ProgCancel;
      ProgressUpdate(0, 'Starting conversion...');
    end
    else
    begin
      // Silent preview render.
      // Keep OnProgress nil (no UI spam), but provide a valid CancelFlag.
      ProgCancel := False;
      opt.OnProgress := nil;
      opt.CancelFlag := @ProgCancel;
    end;
    try
    // PatchStyle options (disabled for Tronicshade; it has its own isolated logic)
    if opt.Mode <> rmTronicShade then
    begin
      opt.PatchStyleEnabled := Assigned(ChkPatchStyle) and ChkPatchStyle.Checked;
      opt.PatchUse10 := Assigned(ChkPatch10) and ChkPatch10.Checked;
      opt.PatchUse5 := Assigned(ChkPatch5) and ChkPatch5.Checked;
      opt.PatchUse3 := Assigned(ChkPatch3) and ChkPatch3.Checked;
      if Assigned(SePatchLoops) then opt.PatchLoops := SePatchLoops.Value else opt.PatchLoops := 1;
      if Assigned(SePatchMinMatch) then opt.PatchMinMatchPct := SePatchMinMatch.Value else opt.PatchMinMatchPct := 65;
      if Assigned(RgPatchMode) then opt.PatchApplyMode := Byte(RgPatchMode.ItemIndex) else opt.PatchApplyMode := 0;
    end;

ConvertImageToCells(FImg, opt, FRows, FCells);

// Tronicshade (new): Hybrid output + Retro Stylizer pass (tab controls).
if Assigned(CbMode) and SameText(LowerCase(CbMode.Text), 'tronicshade') then
begin
  if Assigned(TbTronicRetroTexture) and Assigned(LblTronicRetroTexture) then
    LblTronicRetroTexture.Caption := IntToStr(TbTronicRetroTexture.Position);

  incBlocks := (not Assigned(ChkTronicRetroBlocks)) or ChkTronicRetroBlocks.Checked;
  if Assigned(CbTronicRetroStyle) then
    rs := TTronicRetroStyle(EnsureRange(CbTronicRetroStyle.ItemIndex, 0, Ord(High(TTronicRetroStyle))))
  else
    rs := trsGrainy;
  if Assigned(TbTronicRetroTexture) then
    tex := TbTronicRetroTexture.Position
  else
    tex := 15;

  if FTronicRetroPassCount > 1 then
  begin
    // Extreme preset: 4 directional passes.
    TronicRetroStylizeCellsPassEx(FCells, COLS, FRows, rs, tex, incBlocks, trpLeftToRight);
    TronicRetroStylizeCellsPassEx(FCells, COLS, FRows, rs, tex, incBlocks, trpTopToBottom);
    TronicRetroStylizeCellsPassEx(FCells, COLS, FRows, rs, tex, incBlocks, trpBottomToTop);
    TronicRetroStylizeCellsPassEx(FCells, COLS, FRows, rs, tex, incBlocks, trpRightToLeft);
  end
  else
    TronicRetroStylizeCellsEx(FCells, COLS, FRows, rs, tex, incBlocks);
end;

      // Optional TronicShade render report (shown only when Render Tronicshade was clicked)
      if showTronicReport then
      begin
        if trRep.CellsTotal > 0 then
        begin
          avgErr := trRep.SumBestErr / trRep.CellsTotal;
          avgMatch := trRep.SumMatchPct / trRep.CellsTotal;
          avgToneAbs := trRep.SumToneErrAbs / trRep.CellsTotal;
        end
        else
        begin
          avgErr := 0;
          avgMatch := 0;
          avgToneAbs := 0;
        end;

        msg :=
          'Render report'#13#10+
          '-------------'#13#10+
          'Mode: Tronicshade'#13#10+
          'Grid: ' + IntToStr(trRep.Cols) + ' x ' + IntToStr(trRep.Rows) + #13#10+
          'Cells processed: ' + IntToStr(trRep.CellsTotal) + #13#10+
          'Cells changed:   ' + IntToStr(trRep.CellsChanged) + #13#10+
          'Glyph-only locked colors: ' + IntToStr(trRep.CellsLockedColors) + #13#10+
          'Style prior used: ' + IntToStr(trRep.CellsWithStylePrior) + #13#10+
          'Edge force cells: ' + IntToStr(trRep.CellsWithEdgeForce) + #13#10+
          #13#10+
          'BestErr (avg): ' + FormatFloat('0.00', avgErr) + #13#10+
          'BestErr (min/max): ' + IntToStr(trRep.MinBestErr) + ' / ' + IntToStr(trRep.MaxBestErr) + #13#10+
          'Match% (avg): ' + FormatFloat('0.00', avgMatch) + #13#10+
          'Tone err |abs| (avg): ' + FormatFloat('0.00', avgToneAbs);

        MessageDlg(msg, mtInformation, [mbOK], 0);
      end;
    except
      on E: Exception do
      begin
        if SameText(E.Message, 'Canceled') then
        begin
          ProgressUpdate(ProgLastPct, 'Canceled.');
          Exit;
        end;
        raise;
      end;
    end;
  finally
    // Report popup is one-shot (triggered by the Tronicshade render button).
    if AllowTronicReport then
      FShowTronicReportAfterRender := False;
    if ShowProgress then
      EndProgressUI;
  end;
  UpdateInfo;
  OutBox.Invalidate;
end;

procedure TMainForm.DoRender(Sender: TObject);
begin
  // Manual render: show the progress dialog and allow the optional Tronic report.
  RenderCore(True, True);
end;

procedure TMainForm.DoSave(Sender: TObject);
var
  fn, ext: string;
  opt, hqOpt: TConvertOptions;
  expOpt: TAnsiExportOptions;
  outCells: TCellArray;
  outRows: Integer;
  useHQ: Boolean;

  procedure ApplyPatchStyleOptions(var AOpt: TConvertOptions);
  begin
    // Mirror DoRender behavior so export matches preview.
    if AOpt.Mode <> rmTronicShade then
    begin
      AOpt.PatchStyleEnabled := Assigned(ChkPatchStyle) and ChkPatchStyle.Checked;
      AOpt.PatchUse10 := Assigned(ChkPatch10) and ChkPatch10.Checked;
      AOpt.PatchUse5 := Assigned(ChkPatch5) and ChkPatch5.Checked;
      AOpt.PatchUse3 := Assigned(ChkPatch3) and ChkPatch3.Checked;
      if Assigned(SePatchLoops) then AOpt.PatchLoops := SePatchLoops.Value else AOpt.PatchLoops := 1;
      if Assigned(SePatchMinMatch) then AOpt.PatchMinMatchPct := SePatchMinMatch.Value else AOpt.PatchMinMatchPct := 65;
      if Assigned(RgPatchMode) then AOpt.PatchApplyMode := Byte(RgPatchMode.ItemIndex) else AOpt.PatchApplyMode := 0;
    end;
  end;

  procedure ApplyTronicRetroPass(var Cells: TCellArray; Rows: Integer);
  var
    incBlocks: Boolean;
    rs: TTronicRetroStyle;
    tex: Integer;
  begin
    // Keep identical behavior to DoRender for the Tronic "retro" post-pass.
    if not (Assigned(CbMode) and SameText(LowerCase(CbMode.Text), 'tronicshade')) then Exit;

    incBlocks := (not Assigned(ChkTronicRetroBlocks)) or ChkTronicRetroBlocks.Checked;
    if Assigned(CbTronicRetroStyle) then
      rs := TTronicRetroStyle(EnsureRange(CbTronicRetroStyle.ItemIndex, 0, Ord(High(TTronicRetroStyle))))
    else
      rs := trsGrainy;
    if Assigned(TbTronicRetroTexture) then
      tex := TbTronicRetroTexture.Position
    else
      tex := 15;

    if FTronicRetroPassCount > 1 then
    begin
      TronicRetroStylizeCellsPassEx(Cells, COLS, Rows, rs, tex, incBlocks, trpLeftToRight);
      TronicRetroStylizeCellsPassEx(Cells, COLS, Rows, rs, tex, incBlocks, trpTopToBottom);
      TronicRetroStylizeCellsPassEx(Cells, COLS, Rows, rs, tex, incBlocks, trpBottomToTop);
      TronicRetroStylizeCellsPassEx(Cells, COLS, Rows, rs, tex, incBlocks, trpRightToLeft);
    end
    else
      TronicRetroStylizeCellsEx(Cells, COLS, Rows, rs, tex, incBlocks);
  end;
begin
  opt := GetOptions;
  useHQ := Assigned(FImg) and (opt.HQMode > 0);

  // Normal path: keep existing behavior (update preview cells before saving).
  if Assigned(FImg) and (not useHQ) then
    DoRender(nil);

  // HQ export path: do NOT touch the preview; re-run conversion with heavier options for export only.
  if useHQ then
  begin
    hqOpt := opt;
    ApplyHQModeTuning(hqOpt);
    ApplyPatchStyleOptions(hqOpt);
    StartProgressUI('High-quality export conversion...');
    try
      hqOpt.OnProgress := @ProgressUpdate;
      hqOpt.CancelFlag := @ProgCancel;
      ProgressUpdate(0, 'Starting HQ conversion...');
      ConvertImageToCells(FImg, hqOpt, outRows, outCells);
      ApplyTronicRetroPass(outCells, outRows);
    finally
      EndProgressUI;
    end;
  end
  else
  begin
    outRows := FRows;
    outCells := FCells;
  end;

  if (outRows <= 0) or (Length(outCells) <> COLS * outRows) then Exit;

  // Default to ANSI export (more portable than BIN), but allow BIN as well.
  SaveDlg.FileName := ChangeFileExt(ExtractFileName(FFileName), '.ans');
  if not SaveDlg.Execute then Exit;

  fn := SaveDlg.FileName;
  ext := LowerCase(ExtractFileExt(fn));
  if ext = '' then
  begin
    // Add an extension based on the selected filter.
    if SaveDlg.FilterIndex = 1 then
      fn := fn + '.ans'
    else
      fn := fn + '.bin';
    ext := LowerCase(ExtractFileExt(fn));
  end;

  if (ext = '.ans') or (ext = '.ansi') then
  begin
    SetAnsiExportDefaults(fn, FFileName, expOpt);
    expOpt.IceFlag := opt.Ice;
    if not EditAnsiExportOptions(Self, fn, FFileName, expOpt) then Exit;
    try
      SaveANSIEx(fn, outCells, expOpt, FFileName);
    except
      on E: Exception do
        MessageDlg('Save failed', E.Message, mtError, [mbOK], 0);
    end;
  end
  else
    try
      SaveBIN(fn, outCells);
    except
      on E: Exception do
        MessageDlg('Save failed', E.Message, mtError, [mbOK], 0);
    end;
end;

procedure TMainForm.DoClearSel(Sender: TObject);
begin
  FHasSel := False;
  FDragging := False;
  UpdateInfo;
  SrcBox.Invalidate;
end;

procedure TMainForm.SrcPaint(Sender: TObject);
var
  D: TRect;
  selView: TRect;
begin
  SrcBox.Canvas.Brush.Color := clBlack;
  SrcBox.Canvas.FillRect(SrcBox.ClientRect);

  if (FSrcBmp.Width <= 0) or (FSrcBmp.Height <= 0) then Exit;

  D := GetImageDrawRect;
  SrcBox.Canvas.StretchDraw(D, FSrcBmp);

  if FHasSel or FDragging then
  begin
    selView := ImageToViewRect(NormalizeRectLocal(FSel));
    SrcBox.Canvas.Pen.Color := clLime;
    SrcBox.Canvas.Pen.Width := 2;
    SrcBox.Canvas.Brush.Style := bsClear;
    SrcBox.Canvas.Rectangle(selView);
    SrcBox.Canvas.Brush.Style := bsSolid;
  end;
end;

procedure TMainForm.SrcMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  pImg: TPoint;
begin
  if (FSrcBmp.Width <= 0) then Exit;

  // Dropper mode: click to sample a color hint (no dragging needed).
  if FPickHintMode then
  begin
    if Button = mbRight then
    begin
      DoTogglePickHintDropper(nil);
      Exit;
    end;
    if Button = mbLeft then
    begin
      pImg := ViewToImagePoint(Point(X, Y));
      AddHintFromPoint(pImg);
      Exit;
    end;
  end;

  if Button <> mbLeft then Exit;

  // Drag selection (optional). Some widgetsets can drop capture on TPaintBox during click-drag.
  SetCaptureControl(SrcBox);

  pImg := ViewToImagePoint(Point(X, Y));
  FDragStart := pImg;
  FSel := Rect(pImg.X, pImg.Y, pImg.X, pImg.Y);
  FDragging := True;
  FHasSel := True;

  UpdateInfo;
  SrcBox.Invalidate;
end;

procedure TMainForm.SrcMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  pImg: TPoint;
begin
  if not FDragging then Exit;
  pImg := ViewToImagePoint(Point(X, Y));
  FSel.Right := pImg.X;
  FSel.Bottom := pImg.Y;
  UpdateInfo;
  SrcBox.Invalidate;
end;

procedure TMainForm.SrcMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if Button <> mbLeft then Exit;
  if not FDragging then Exit;

  // Release capture.
  // Release mouse capture (nil = release)
	SetCaptureControl(nil);

  FDragging := False;

  if (Abs(FSel.Right - FSel.Left) < 2) or (Abs(FSel.Bottom - FSel.Top) < 2) then
    FHasSel := False;

  UpdateInfo;
  SrcBox.Invalidate;
end;

procedure TMainForm.OutPaint(Sender: TObject);
var
  cw, ch: Integer;
  x, y: Integer;
  x0, x1, y0, y1: Integer;
  cell: TCell;
  fg, bg: Integer;
  rfg, rbg: TRGB;
  glyph: UnicodeString;
  R, clip: TRect;
  pal: TPaletteKind;
  useBios: Boolean;
  Dx: TDOSXBound;
  Dy: TDOSYBound;
  i: Integer;
begin
  OutBox.Canvas.Brush.Color := clBlack;
  OutBox.Canvas.FillRect(OutBox.Canvas.ClipRect);

  if (FRows <= 0) or (Length(FCells) <> COLS * FRows) then Exit;

  useBios := Assigned(ChkBiosPreview) and ChkBiosPreview.Checked;

  cw := SeCellW.Value;
  if useBios then
  begin
    // BIOS (DOS 8x16) preview: snap to integer scaling so the bitmap font
    // stays crisp and "true" (no fractional pixel stretching).
    if cw < 8 then cw := 8;
    cw := ((cw + 4) div 8) * 8;
    if cw < 8 then cw := 8;
  end
  else
  begin
    if cw < 4 then cw := 4;
  end;
  ch := cw * 2;

  // Keep paintbox size in sync (scrollbox uses it for ranges)
  if (OutBox.Width <> COLS * cw) or (OutBox.Height <> FRows * ch) then
  begin
    OutBox.Width := COLS * cw;
    OutBox.Height := FRows * ch;
  end;

  if Assigned(SeTileY) and (FRows > 0) then
  begin
    SeTileY.MaxValue := Max(0, FRows - 1);
    if SeTileY.Value > SeTileY.MaxValue then SeTileY.Value := SeTileY.MaxValue;
  end;

  // Output preview: always show standard DOS VGA 16-color palette.
  // (The conversion itself may use other palettes or a hint-built palette,
  // but the preview is intended to match real DOS/ANSI output.)
  pal := pkVGA;

  if useBios then
  begin
    for i := 0 to 8 do Dx[i] := i * (cw div 8);
    for i := 0 to 16 do Dy[i] := i * (ch div 16);
  end
  else
  begin
    if Assigned(FPreviewFont) then
      OutBox.Canvas.Font.Assign(FPreviewFont);
    OutBox.Canvas.Font.Size := Max(6, ch - 4);
  end;

  clip := OutBox.Canvas.ClipRect;

  x0 := EnsureRange(clip.Left div cw, 0, COLS - 1);
  y0 := EnsureRange(clip.Top div ch, 0, FRows - 1);

  x1 := EnsureRange((Max(clip.Right - 1, 0)) div cw, 0, COLS - 1);
  y1 := EnsureRange((Max(clip.Bottom - 1, 0)) div ch, 0, FRows - 1);

  for y := y0 to y1 do
    for x := x0 to x1 do
    begin
      cell := FCells[y * COLS + x];
      fg := cell.Attr and $0F;
      bg := (cell.Attr shr 4) and $0F;

      rfg := Palette16(pal, fg);
      rbg := Palette16(pal, bg);

      if useBios then
      begin
        DrawDOSGlyph8x16Scaled(OutBox.Canvas, x * cw, y * ch, Dx, Dy,
          cell.Ch, ColorFromRGB(rfg), ColorFromRGB(rbg));
      end
      else
      begin
        R.Left := x * cw;
        R.Top := y * ch;
        R.Right := R.Left + cw;
        R.Bottom := R.Top + ch;

        OutBox.Canvas.Brush.Color := ColorFromRGB(rbg);
        OutBox.Canvas.FillRect(R);

        glyph := CP437Glyph(cell.Ch);
        OutBox.Canvas.Font.Color := ColorFromRGB(rfg);
        OutBox.Canvas.TextOut(R.Left + 1, R.Top, glyph);
      end;
    end;
end;

procedure TMainForm.LookChanged(Sender: TObject);
var
  s: String;
begin
  s := LowerCase(CbLook.Text);

  // Keep ANSIrez-style brightness in a sane range when switching looks.
  if Assigned(FeBrightness) then FeBrightness.Value := 1.00;

  if s = 'realistic' then
  begin
    if CbDither.Items.IndexOf('fs') >= 0 then CbDither.ItemIndex := CbDither.Items.IndexOf('fs');
    FeDitherStrength.Value := 1.00;
    FeGamma.Value := 1.00;
    FeContrast.Value := 1.10;
    FeSaturation.Value := 1.05;
    SeWinX.Value := 4;
    SeWinY.Value := 4;
    if CbMode.Items.IndexOf('hybrid') >= 0 then CbMode.ItemIndex := CbMode.Items.IndexOf('hybrid');
  end
  else if s = 'cartoon' then
  begin
    if CbDither.Items.IndexOf('atkinson') >= 0 then CbDither.ItemIndex := CbDither.Items.IndexOf('atkinson');
    FeDitherStrength.Value := 0.75;
    FeGamma.Value := 0.95;
    FeContrast.Value := 1.35;
    FeSaturation.Value := 1.35;
    SeWinX.Value := 3;
    SeWinY.Value := 3;
    if CbMode.Items.IndexOf('shades') >= 0 then CbMode.ItemIndex := CbMode.Items.IndexOf('shades');
  end
  else if s = 'lineart' then
  begin
    if CbDither.Items.IndexOf('none') >= 0 then CbDither.ItemIndex := CbDither.Items.IndexOf('none');
    FeDitherStrength.Value := 0.0;
    FeGamma.Value := 1.05;
    FeContrast.Value := 1.80;
    FeSaturation.Value := 0.15;
    SeWinX.Value := 2;
    SeWinY.Value := 2;
    if CbMode.Items.IndexOf('hires') >= 0 then CbMode.ItemIndex := CbMode.Items.IndexOf('hires');
    if CbPalette.Items.IndexOf('gray16') >= 0 then CbPalette.ItemIndex := CbPalette.Items.IndexOf('gray16');
  end;
end;

procedure TMainForm.BtnPreMatchPalBrowseClick(Sender: TObject);
begin
  if not Assigned(PreMatchPalOpenDlg) then Exit;
  if PreMatchPalOpenDlg.Execute then
  begin
    if Assigned(EdPreMatchPal) then
      EdPreMatchPal.Text := PreMatchPalOpenDlg.FileName;
    AnyOptionChanged(Sender);
  end;
end;

procedure TMainForm.BtnPreMatchPalClearClick(Sender: TObject);
begin
  if Assigned(EdPreMatchPal) then
    EdPreMatchPal.Text := '';
  AnyOptionChanged(Sender);
end;

procedure TMainForm.EdPreMatchPalEditingDone(Sender: TObject);
begin
  AnyOptionChanged(Sender);
end;

procedure TMainForm.AnyOptionChanged(Sender: TObject);
begin
  UpdateGradientUI;
  FCellSampleValid := False;
  UpdateOutScroll;
  SrcBox.Invalidate;
  OutBox.Invalidate;
  if Assigned(PbHintPalette) then PbHintPalette.Invalidate;
  // Keep Tronic slider value labels in sync
  if Assigned(TbTronicBlockThreshold) and Assigned(LblTronicBlockThresholdVal) then
    LblTronicBlockThresholdVal.Caption := IntToStr(TbTronicBlockThreshold.Position);
  if Assigned(TbTronicShadeWeight) and Assigned(LblTronicShadeWeightVal) then
    LblTronicShadeWeightVal.Caption := IntToStr(TbTronicShadeWeight.Position);

  // Enable/disable the optional pre-match palette file controls.
  // If pre-match is off, we ignore the file path anyway, but disabling makes intent clear.
  if Assigned(ChkPalMatch) then
  begin
    if Assigned(EdPreMatchPal) then EdPreMatchPal.Enabled := ChkPalMatch.Checked;
    if Assigned(BtnPreMatchPalBrowse) then BtnPreMatchPalBrowse.Enabled := ChkPalMatch.Checked;
    if Assigned(BtnPreMatchPalClear) then BtnPreMatchPalClear.Enabled := ChkPalMatch.Checked;
    if Assigned(TbPreMatchBayer) then TbPreMatchBayer.Enabled := ChkPalMatch.Checked;
    if Assigned(LblPreMatchBayer) and Assigned(TbPreMatchBayer) then
      LblPreMatchBayer.Caption := Format('Custom palette Bayer strength: %d%%', [TbPreMatchBayer.Position]);
  end;

  // Preview is updated on-demand (F12 / Render) to keep the app snappy.

end;
procedure TMainForm.BtnLoadShaderClick(Sender: TObject);
var
  iFile, maxFiles: Integer;
  fn: string;
  ok: Boolean;
  append: Boolean;
  anyImported: Boolean;
begin
  if not ShaderOpenDlg.Execute then Exit;

  maxFiles := ShaderOpenDlg.Files.Count;
  if maxFiles > 4 then maxFiles := 4;
  if maxFiles <= 0 then Exit;

  ok := False;
  anyImported := False;
  for iFile := 0 to maxFiles - 1 do
  begin
    fn := ShaderOpenDlg.Files[iFile];
    // First file resets/clears the active profile; subsequent files append/learn more.
    append := (iFile <> 0);

    // Import BIN or ANSI into the active shader profile
    if LowerCase(ExtractFileExt(fn)) = '.bin' then
      ok := ShaderImportBINToActive(fn, SeShaderRows.Value, append, ChkLearnShadeOnly.Checked)
    else if (LowerCase(ExtractFileExt(fn)) = '.ans') or (LowerCase(ExtractFileExt(fn)) = '.ansi') then
      ok := ShaderImportANSIToActive(fn, SeShaderRows.Value, append, True, ChkLearnShadeOnly.Checked)
    else
      ok := False;

    if ok then
      anyImported := True;
  end;

  if anyImported then
  begin
    // Show shader summary and enable shader usage.
    if Assigned(LblShaderInfo) then LblShaderInfo.Caption := ShaderSummary;
    if Assigned(ChkUseShader) then ChkUseShader.Checked := True;

    if Assigned(LblPatchInfo) then
    begin
      if PatchLibHasAny then LblPatchInfo.Caption := 'Patchbook: learned from import'
      else LblPatchInfo.Caption := 'Patchbook: (empty)';
    end;

    // re-render with new shader profile
    AnyOptionChanged(nil);
  end
  else
    MessageDlg('Could not import shader file(s). Please choose .BIN or .ANS/.ANSI.', mtError, [mbOK], 0);
end;

procedure TMainForm.BtnShaderLoadClick(Sender: TObject);
var
  stylesDir: string;
  fn, prof: string;
begin
  stylesDir := GetStylesDir;
  ShaderProfileOpenDlg.InitialDir := stylesDir;
  if not ShaderProfileOpenDlg.Execute then Exit;
  fn := ShaderProfileOpenDlg.FileName;
  if fn = '' then Exit;

  // Profile name is the filename (without extension)
  prof := LowerCase(Trim(ChangeFileExt(ExtractFileName(fn), '')));
  if prof = '' then Exit;

  if Assigned(CbShaderProfile) then
    CbShaderProfile.Text := prof;
  ShaderSetActiveProfile(prof);
  ShaderReloadActiveProfile;

  ShaderFillProfileNames(CbShaderProfile.Items);
  if Assigned(LblShaderInfo) then
    LblShaderInfo.Caption := ShaderSummary;
  AnyOptionChanged(nil);
end;

procedure TMainForm.BtnShaderSaveClick(Sender: TObject);
var
  stylesDir: string;
  prof: string;
  idx: Integer;
begin
  stylesDir := GetStylesDir;
  prof := '';
  if Assigned(CbShaderProfile) then prof := CbShaderProfile.Text;
  prof := LowerCase(Trim(prof));
  if prof = '' then prof := 'default';

  ShaderSetActiveProfile(prof);
  ShaderSaveActiveProfile;

  // Refresh list to include new profile names.
  if Assigned(CbShaderProfile) then
  begin
    ShaderFillProfileNames(CbShaderProfile.Items);
    idx := CbShaderProfile.Items.IndexOf(prof);
    if idx >= 0 then CbShaderProfile.ItemIndex := idx else CbShaderProfile.Text := prof;
  end;

  if Assigned(LblShaderInfo) then
    LblShaderInfo.Caption := ShaderSummary;
end;

procedure TMainForm.BtnShaderNewClick(Sender: TObject);
var
  prof: string;
begin
  prof := '';
  if Assigned(CbShaderProfile) then prof := CbShaderProfile.Text;
  prof := LowerCase(Trim(prof));
  if prof = '' then prof := 'default';
  ShaderSetActiveProfile(prof);
  ShaderClear;
  // Do not auto-save; user can hit Save after confirming the cleared state.
  if Assigned(LblShaderInfo) then
    LblShaderInfo.Caption := ShaderSummary;
  AnyOptionChanged(nil);
end;






procedure TMainForm.ShaderProfileChanged(Sender: TObject);
var
  prof: string;
  idx: Integer;
begin
  if not Assigned(CbShaderProfile) then Exit;
  prof := CbShaderProfile.Text;
  if prof = '' then Exit;

  ShaderSetActiveProfile(prof);

  // Refresh list to include newly created profiles and keep selection.
  ShaderFillProfileNames(CbShaderProfile.Items);
  idx := CbShaderProfile.Items.IndexOf(LowerCase(Trim(prof)));
  if idx >= 0 then
    CbShaderProfile.ItemIndex := idx
  else
    CbShaderProfile.Text := LowerCase(Trim(prof));

  // Helpful: ASCII profile defaults to ASCII-only glyph set.
  if (LowerCase(prof) = 'ascii') and Assigned(CbGlyphSet) then
    CbGlyphSet.ItemIndex := Ord(gsAscii);

  if Assigned(LblShaderInfo) then
    LblShaderInfo.Caption := ShaderSummary;

  AnyOptionChanged(nil);
end;

procedure TMainForm.UpdateOutScroll;
var
  cw, ch: Integer;
  useBios: Boolean;
begin
  if not Assigned(OutBox) then Exit;

  useBios := Assigned(ChkBiosPreview) and ChkBiosPreview.Checked;

  cw := SeCellW.Value;
  if useBios then
  begin
    // BIOS (DOS 8x16) preview should scale in *integer* steps
    // to stay pixel-perfect. Round cell width to nearest multiple of 8.
    if cw < 8 then cw := 8;
    cw := ((cw + 4) div 8) * 8;
    if cw < 8 then cw := 8;
  end
  else
  begin
    if cw < 4 then cw := 4;
  end;
  ch := cw * 2;

  if FRows > 0 then
  begin
    OutBox.Width := COLS * cw;
    OutBox.Height := FRows * ch;
  end;
end;

procedure TMainForm.DoPickFont(Sender: TObject);
begin
  if Assigned(ChkBiosPreview) and ChkBiosPreview.Checked then
  begin
    MessageDlg('BIOS preview is enabled. Disable it to choose a different preview font.',
      mtInformation, [mbOK], 0);
    Exit;
  end;

  if not Assigned(FontDlg) then Exit;
  FontDlg.Font.Assign(FPreviewFont);
  if FontDlg.Execute then
  begin
    FPreviewFont.Assign(FontDlg.Font);
    DoToggleBiosPreview(nil);
  end;
end;

procedure TMainForm.DoToggleBiosPreview(Sender: TObject);
begin
  if Assigned(LblFont) then
  begin
    if Assigned(ChkBiosPreview) and ChkBiosPreview.Checked then
      LblFont.Caption := 'Font: BIOS 8x16'
    else if Assigned(FPreviewFont) then
      LblFont.Caption := 'Font: ' + FPreviewFont.Name;
  end;
  if Assigned(OutBox) then OutBox.Invalidate;
end;

procedure TMainForm.SavePresetToIni(ini: TCustomIniFile);
var
  i: Integer;
begin
  if not Assigned(ini) then Exit;

  ini.WriteInteger('ui', 'Style', CbStyle.ItemIndex);
    ini.WriteInteger('ui', 'Mode', CbMode.ItemIndex);
    ini.WriteInteger('ui', 'Dither', CbDither.ItemIndex);
    ini.WriteInteger('ui', 'Palette', CbPalette.ItemIndex);
    ini.WriteString('ui', 'PaletteText', CbPalette.Text);
    ini.WriteInteger('ui', 'Look', CbLook.ItemIndex);
    ini.WriteBool('ui', 'Ice', ChkIce.Checked);
    ini.WriteBool('ui', 'UseSelection', ChkUseSel.Checked);
    ini.WriteBool('ui', 'PalMatch', ChkPalMatch.Checked);
    if Assigned(EdPreMatchPal) then
      ini.WriteString('ui', 'PreMatchHexFile', Trim(EdPreMatchPal.Text));
    if Assigned(TbPreMatchBayer) then
      ini.WriteInteger('ui', 'PreMatchBayerStrength', TbPreMatchBayer.Position);
    if Assigned(SeBlockUpWeight) then ini.WriteInteger('ui', 'BlockUpWeight', SeBlockUpWeight.Value);
    if Assigned(SeBlockDownWeight) then ini.WriteInteger('ui', 'BlockDownWeight', SeBlockDownWeight.Value);
    if Assigned(SeShadeBlockWeight) then ini.WriteInteger('ui', 'ShadeBlockWeight', SeShadeBlockWeight.Value);
ini.WriteBool('ui', 'BiosPreview', Assigned(ChkBiosPreview) and ChkBiosPreview.Checked);
ini.WriteInteger('ui', 'ColorMetric', CbMetric.ItemIndex);
    if Assigned(CbGlyphSet) then ini.WriteInteger('ui', 'GlyphSet', CbGlyphSet.ItemIndex);
    if Assigned(CbGradMode) then ini.WriteInteger('ui', 'GradMode', CbGradMode.ItemIndex);
    if Assigned(CbGradSet) then ini.WriteInteger('ui', 'GradSet', CbGradSet.ItemIndex);
    if Assigned(CbCellDiffModel) then ini.WriteInteger('ui', 'CellDiffModel', CbCellDiffModel.ItemIndex);
    if Assigned(SeCellDiffAmt) then ini.WriteInteger('ui', 'CellDiffAmount', SeCellDiffAmt.Value);
    if Assigned(SeCellTone) then ini.WriteInteger('ui', 'CellTone', SeCellTone.Value);
    if Assigned(SeTronicImportWeight) then ini.WriteInteger('ui', 'TronicImportWeight', SeTronicImportWeight.Value);
    if Assigned(SeTronicImportPasses) then ini.WriteInteger('ui', 'TronicImportPasses', SeTronicImportPasses.Value);
    if Assigned(ChkTronicImportMirrorH) then ini.WriteBool('ui', 'TronicImportMirrorH', ChkTronicImportMirrorH.Checked);

    if Assigned(CbShaderProfile) then ini.WriteString('ui', 'ShaderProfile', CbShaderProfile.Text);
    if Assigned(ChkUseShader) then ini.WriteBool('ui', 'UseShaderBin', ChkUseShader.Checked);
    if Assigned(SeShaderPasses) then ini.WriteInteger('ui', 'AutoShaderPasses', SeShaderPasses.Value);
    if Assigned(SeShader3x3Pct) then ini.WriteInteger('ui', 'AutoShader3x3BelowPct', SeShader3x3Pct.Value);
    if Assigned(SeShaderBlocksPct) then ini.WriteInteger('ui', 'AutoShaderBlocksOnlyPct', SeShaderBlocksPct.Value);
    if Assigned(ChkDosBoxModel) then ini.WriteBool('ui', 'DosBoxModel', ChkDosBoxModel.Checked);
    if Assigned(ChkLearnShadeOnly) then ini.WriteBool('ui', 'LearnShadeOnly', ChkLearnShadeOnly.Checked);
    if Assigned(SeShaderRows) then ini.WriteInteger('ui', 'ShaderRows', SeShaderRows.Value);

    ini.WriteInteger('num', 'Rows', SeRows.Value);
    ini.WriteInteger('num', 'CellW', SeCellW.Value);
    ini.WriteInteger('num', 'WinX', SeWinX.Value);
    ini.WriteInteger('num', 'WinY', SeWinY.Value);
    if Assigned(SeColorMatch) then ini.WriteInteger('num', 'ColorMatch', SeColorMatch.Value);
    if Assigned(SeYWeight) then ini.WriteInteger('num', 'YWeight', SeYWeight.Value);
    if Assigned(SeCbWeight) then ini.WriteInteger('num', 'CbWeight', SeCbWeight.Value);
    if Assigned(SeCrWeight) then ini.WriteInteger('num', 'CrWeight', SeCrWeight.Value);

    ini.WriteFloat('flt', 'Aspect', FeAspect.Value);
    ini.WriteFloat('flt', 'Gamma', FeGamma.Value);
    ini.WriteFloat('flt', 'Contrast', FeContrast.Value);
    ini.WriteFloat('flt', 'Saturation', FeSaturation.Value);
    if Assigned(FeBrightness) then
      ini.WriteFloat('flt', 'Brightness', FeBrightness.Value);
    ini.WriteFloat('flt', 'DitherStrength', FeDitherStrength.Value);
    if Assigned(FeGlyphSmooth) then ini.WriteFloat('flt', 'GlyphSmooth', FeGlyphSmooth.Value);
    if Assigned(FeShadeBlend) then ini.WriteFloat('flt', 'ShadeBlend', FeShadeBlend.Value);

    // Tronicshade
    if Assigned(SeTronicStrength) then ini.WriteInteger('tronic', 'Strength', SeTronicStrength.Value);
    if Assigned(ChkTronicLumaOnly) then ini.WriteBool('tronic', 'LumaOnly', ChkTronicLumaOnly.Checked);
    if Assigned(SeTronicTone) then ini.WriteInteger('tronic', 'Tone', SeTronicTone.Value);
    if Assigned(ChkTronicAutoShader) then ini.WriteBool('tronic', 'AutoShader', ChkTronicAutoShader.Checked);
    if Assigned(SeTronicWin) then ini.WriteInteger('tronic', 'Window', SeTronicWin.Value);
    if Assigned(SeTronicStep) then ini.WriteInteger('tronic', 'Step', SeTronicStep.Value);
    if Assigned(CbTronicDiffModel) then ini.WriteInteger('tronic', 'DiffModel', CbTronicDiffModel.ItemIndex);
    if Assigned(SeTronicDiffAmt) then ini.WriteInteger('tronic', 'DiffusionAmount', SeTronicDiffAmt.Value);
    if Assigned(CbTronicColorMetric) then ini.WriteInteger('tronic', 'ColorMetric', CbTronicColorMetric.ItemIndex);
    if Assigned(CbTronicGlyphSet) then ini.WriteInteger('tronic', 'GlyphSet', CbTronicGlyphSet.ItemIndex);
    if Assigned(ChkTronicGlyphOnly) then ini.WriteBool('tronic', 'GlyphOnly', ChkTronicGlyphOnly.Checked);
    if Assigned(ChkTronicEdgeShade) then ini.WriteBool('tronic', 'EdgeShade', ChkTronicEdgeShade.Checked);
    if Assigned(CbTronicEdgeSample) then ini.WriteInteger('tronic', 'EdgeSample', CbTronicEdgeSample.ItemIndex);
    if Assigned(TbTronicBlockThreshold) then ini.WriteInteger('tronic', 'BlockThreshold', TbTronicBlockThreshold.Position);
    if Assigned(TbTronicShadeWeight) then ini.WriteInteger('tronic', 'ShadeWeight', TbTronicShadeWeight.Position);
    if Assigned(SeTronicImportWeight) then ini.WriteInteger('tronic', 'AnsiImportWeight', SeTronicImportWeight.Value);
    if Assigned(SeTronicImportPasses) then ini.WriteInteger('tronic', 'AnsiImportPasses', SeTronicImportPasses.Value);
    if Assigned(ChkTronicImportMirrorH) then ini.WriteBool('tronic', 'AnsiImportMirrorH', ChkTronicImportMirrorH.Checked);
    if Assigned(ChkTronicCornersShadesOnly) then ini.WriteBool('tronic', 'CornersShadesOnly', ChkTronicCornersShadesOnly.Checked);
    ini.WriteString('tronic', 'StyleFile', FTronicStyleFile);

// Color hints (manual palette bias)
if Assigned(SeHintTol) then
  ini.WriteInteger('hints', 'Tolerance', SeHintTol.Value)
else
  ini.WriteInteger('hints', 'Tolerance', 0);
if Assigned(ChkHintUsePalette) then
  ini.WriteBool('hints', 'UseHintPalette', ChkHintUsePalette.Checked);
if Assigned(ChkRefitHintPalette) then
  ini.WriteBool('hints', 'RefitHintedPaletteEachPass', ChkRefitHintPalette.Checked);

// Hint post-fix snap
if Assigned(ChkHintPostFix) then
  ini.WriteBool('hints', 'PostFix', ChkHintPostFix.Checked);
if Assigned(SeHintPostPct) then
  ini.WriteInteger('hints', 'PostFixPct', SeHintPostPct.Value);
	if Assigned(SeHintPickRadius) then
	  ini.WriteInteger('hints', 'PickRadius', SeHintPickRadius.Value);
ini.WriteInteger('hints', 'Count', Length(FColorHints));
for i := 0 to High(FColorHints) do
begin
  ini.WriteInteger('hints', Format('h%d_idx', [i]), FColorHints[i].TargetIdx);
  ini.WriteInteger('hints', Format('h%d_r', [i]), FColorHints[i].Src.R);
  ini.WriteInteger('hints', Format('h%d_g', [i]), FColorHints[i].Src.G);
  ini.WriteInteger('hints', Format('h%d_b', [i]), FColorHints[i].Src.B);
  ini.WriteInteger('hints', Format('h%d_strength', [i]), FColorHints[i].Strength);
end;

    ini.WriteString('font', 'Name', FPreviewFont.Name);
    ini.WriteInteger('font', 'Size', FPreviewFont.Size);
    ini.WriteInteger('font', 'Style', Ord(fsBold in FPreviewFont.Style) * 1 +
                                       Ord(fsItalic in FPreviewFont.Style) * 2 +
                                       Ord(fsUnderline in FPreviewFont.Style) * 4 +
                                       Ord(fsStrikeOut in FPreviewFont.Style) * 8);
end;

procedure TMainForm.SavePresetToFile(const FN: string);
var
  ini: TIniFile;
begin
  ini := TIniFile.Create(FN);
  try
    SavePresetToIni(ini);
  finally
    ini.Free;
  end;
end;

procedure TMainForm.LoadPresetFromIni(ini: TCustomIniFile);
var
  st: Integer;
  mi: Integer;
  fsStyles: TFontStyles;
  s: String;
  i, cnt: Integer;
begin
  if not Assigned(ini) then Exit;
    CbStyle.ItemIndex := ini.ReadInteger('ui', 'Style', CbStyle.ItemIndex);
    CbMode.ItemIndex := ini.ReadInteger('ui', 'Mode', CbMode.ItemIndex);
    CbDither.ItemIndex := ini.ReadInteger('ui', 'Dither', CbDither.ItemIndex);
    // Backward compatible: prefer stored text (stable) over index (can shift when items change).
    s := ini.ReadString('ui', 'PaletteText', '');
    if s <> '' then
    begin
      st := CbPalette.Items.IndexOf(s);
      if st >= 0 then CbPalette.ItemIndex := st;
    end
    else
    begin
      st := ini.ReadInteger('ui', 'Palette', CbPalette.ItemIndex);
      // Old versions had only: vga16 (0), gray16 (1)
      if (CbPalette.Items.Count >= 3) and (st = 1) then
        CbPalette.ItemIndex := CbPalette.Items.IndexOf('gray16')
      else
        CbPalette.ItemIndex := st;
    end;
    CbLook.ItemIndex := ini.ReadInteger('ui', 'Look', CbLook.ItemIndex);
    ChkIce.Checked := ini.ReadBool('ui', 'Ice', ChkIce.Checked);
    ChkUseSel.Checked := ini.ReadBool('ui', 'UseSelection', ChkUseSel.Checked);
    ChkPalMatch.Checked := ini.ReadBool('ui', 'PalMatch', ChkPalMatch.Checked);
    if Assigned(EdPreMatchPal) then
      EdPreMatchPal.Text := ini.ReadString('ui', 'PreMatchHexFile', EdPreMatchPal.Text);
    if Assigned(TbPreMatchBayer) then
    begin
      i := ini.ReadInteger('ui', 'PreMatchBayerStrength', TbPreMatchBayer.Position);
      if i < TbPreMatchBayer.Min then i := TbPreMatchBayer.Min;
      if i > TbPreMatchBayer.Max then i := TbPreMatchBayer.Max;
      TbPreMatchBayer.Position := i;
    end;

    if Assigned(SeBlockUpWeight) then
    begin
      i := ini.ReadInteger('ui', 'BlockUpWeight', SeBlockUpWeight.Value);
      if i < SeBlockUpWeight.MinValue then i := SeBlockUpWeight.MinValue;
      if i > SeBlockUpWeight.MaxValue then i := SeBlockUpWeight.MaxValue;
      SeBlockUpWeight.Value := i;
    end;
    if Assigned(SeBlockDownWeight) then
    begin
      i := ini.ReadInteger('ui', 'BlockDownWeight', SeBlockDownWeight.Value);
      if i < SeBlockDownWeight.MinValue then i := SeBlockDownWeight.MinValue;
      if i > SeBlockDownWeight.MaxValue then i := SeBlockDownWeight.MaxValue;
      SeBlockDownWeight.Value := i;
    end;
    if Assigned(SeShadeBlockWeight) then
    begin
      i := ini.ReadInteger('ui', 'ShadeBlockWeight', SeShadeBlockWeight.Value);
      if i < SeShadeBlockWeight.MinValue then i := SeShadeBlockWeight.MinValue;
      if i > SeShadeBlockWeight.MaxValue then i := SeShadeBlockWeight.MaxValue;
      SeShadeBlockWeight.Value := i;
    end;
if Assigned(ChkBiosPreview) then
      ChkBiosPreview.Checked := ini.ReadBool('ui', 'BiosPreview', ChkBiosPreview.Checked);
// Clamp to valid range (older INIs or manual edits can leave invalid values)
    mi := ini.ReadInteger('ui', 'ColorMetric', CbMetric.ItemIndex);
    if (mi < 0) or (mi >= CbMetric.Items.Count) then mi := 1;
    CbMetric.ItemIndex := mi;

    // Cell-level diffusion (regular modes)
    if Assigned(CbCellDiffModel) then
    begin
      i := ini.ReadInteger('ui', 'CellDiffModel', CbCellDiffModel.ItemIndex);
      if i < 0 then i := 0;
      if i > CbCellDiffModel.Items.Count-1 then i := CbCellDiffModel.Items.Count-1;
      CbCellDiffModel.ItemIndex := i;
    end;
    if Assigned(SeCellDiffAmt) then
    begin
      SeCellDiffAmt.Value := ini.ReadInteger('ui', 'CellDiffAmount', SeCellDiffAmt.Value);
      if SeCellDiffAmt.Value < SeCellDiffAmt.MinValue then SeCellDiffAmt.Value := SeCellDiffAmt.MinValue;
      if SeCellDiffAmt.Value > SeCellDiffAmt.MaxValue then SeCellDiffAmt.Value := SeCellDiffAmt.MaxValue;
    end;
    if Assigned(SeCellTone) then
    begin
      SeCellTone.Value := ini.ReadInteger('ui', 'CellTone', SeCellTone.Value);
      if SeCellTone.Value < SeCellTone.MinValue then SeCellTone.Value := SeCellTone.MinValue;
      if SeCellTone.Value > SeCellTone.MaxValue then SeCellTone.Value := SeCellTone.MaxValue;
    end;

    if Assigned(CbGlyphSet) then CbGlyphSet.ItemIndex := ini.ReadInteger('ui', 'GlyphSet', CbGlyphSet.ItemIndex);
    if Assigned(CbGlyphSet) then
    begin
      if CbGlyphSet.ItemIndex < 0 then CbGlyphSet.ItemIndex := 0;
      if CbGlyphSet.ItemIndex >= CbGlyphSet.Items.Count then CbGlyphSet.ItemIndex := CbGlyphSet.Items.Count - 1;
    end;

    if Assigned(CbGradMode) then CbGradMode.ItemIndex := ini.ReadInteger('ui', 'GradMode', CbGradMode.ItemIndex);
    if Assigned(CbGradMode) then
    begin
      if CbGradMode.ItemIndex < 0 then CbGradMode.ItemIndex := 0;
      if CbGradMode.ItemIndex >= CbGradMode.Items.Count then CbGradMode.ItemIndex := CbGradMode.Items.Count - 1;
    end;

    if Assigned(CbGradSet) then CbGradSet.ItemIndex := ini.ReadInteger('ui', 'GradSet', CbGradSet.ItemIndex);
    if Assigned(CbGradSet) then
    begin
      if CbGradSet.ItemIndex < 0 then CbGradSet.ItemIndex := 0;
      if CbGradSet.ItemIndex >= CbGradSet.Items.Count then CbGradSet.ItemIndex := CbGradSet.Items.Count - 1;
    end;

    UpdateGradientUI;
    if Assigned(CbShaderProfile) then
    begin
      s := ini.ReadString('ui', 'ShaderProfile', '');
      if s <> '' then
      begin
        st := CbShaderProfile.Items.IndexOf(s);
        if st >= 0 then
        begin
          CbShaderProfile.ItemIndex := st;
          ShaderProfileChanged(nil);
        end;
      end;
    end;
    if Assigned(ChkUseShader) then ChkUseShader.Checked := ini.ReadBool('ui', 'UseShaderBin', ChkUseShader.Checked);
    if Assigned(ChkDosBoxModel) then ChkDosBoxModel.Checked := ini.ReadBool('ui', 'DosBoxModel', ChkDosBoxModel.Checked);
    if Assigned(SeShaderPasses) then SeShaderPasses.Value := ini.ReadInteger('ui', 'AutoShaderPasses', SeShaderPasses.Value);
    if Assigned(SeShader3x3Pct) then SeShader3x3Pct.Value := ini.ReadInteger('ui', 'AutoShader3x3BelowPct', SeShader3x3Pct.Value);
    if Assigned(SeShaderBlocksPct) then SeShaderBlocksPct.Value := ini.ReadInteger('ui', 'AutoShaderBlocksOnlyPct', SeShaderBlocksPct.Value);
    if Assigned(ChkLearnShadeOnly) then ChkLearnShadeOnly.Checked := ini.ReadBool('ui', 'LearnShadeOnly', ChkLearnShadeOnly.Checked);
    if Assigned(SeShaderRows) then SeShaderRows.Value := ini.ReadInteger('ui', 'ShaderRows', SeShaderRows.Value);

    SeRows.Value := ini.ReadInteger('num', 'Rows', SeRows.Value);
    SeCellW.Value := ini.ReadInteger('num', 'CellW', SeCellW.Value);
    SeWinX.Value := ini.ReadInteger('num', 'WinX', SeWinX.Value);
    SeWinY.Value := ini.ReadInteger('num', 'WinY', SeWinY.Value);
    if Assigned(SeColorMatch) then SeColorMatch.Value := ini.ReadInteger('num', 'ColorMatch', SeColorMatch.Value);
    if Assigned(SeYWeight) then SeYWeight.Value := ini.ReadInteger('num', 'YWeight', SeYWeight.Value);
    if Assigned(SeCbWeight) then SeCbWeight.Value := ini.ReadInteger('num', 'CbWeight', SeCbWeight.Value);
    if Assigned(SeCrWeight) then SeCrWeight.Value := ini.ReadInteger('num', 'CrWeight', SeCrWeight.Value);

    FeAspect.Value := ini.ReadFloat('flt', 'Aspect', FeAspect.Value);
    FeGamma.Value := ini.ReadFloat('flt', 'Gamma', FeGamma.Value);
    FeContrast.Value := ini.ReadFloat('flt', 'Contrast', FeContrast.Value);
    FeSaturation.Value := ini.ReadFloat('flt', 'Saturation', FeSaturation.Value);
    if Assigned(FeBrightness) then
      FeBrightness.Value := ini.ReadFloat('flt', 'Brightness', FeBrightness.Value);
    FeDitherStrength.Value := ini.ReadFloat('flt', 'DitherStrength', FeDitherStrength.Value);
    if Assigned(FeGlyphSmooth) then FeGlyphSmooth.Value := ini.ReadFloat('flt', 'GlyphSmooth', FeGlyphSmooth.Value);
    if Assigned(FeShadeBlend) then FeShadeBlend.Value := ini.ReadFloat('flt', 'ShadeBlend', FeShadeBlend.Value);

    // Tronicshade
    if Assigned(SeTronicStrength) then SeTronicStrength.Value := ini.ReadInteger('tronic', 'Strength', SeTronicStrength.Value);
    if Assigned(ChkTronicLumaOnly) then ChkTronicLumaOnly.Checked := ini.ReadBool('tronic', 'LumaOnly', ChkTronicLumaOnly.Checked);
    if Assigned(SeTronicTone) then SeTronicTone.Value := ini.ReadInteger('tronic', 'Tone', SeTronicTone.Value);

    if Assigned(SeTronicImportWeight) then
    begin
      SeTronicImportWeight.Value := ini.ReadInteger('tronic', 'AnsiImportWeight', SeTronicImportWeight.Value);
      if SeTronicImportWeight.Value < SeTronicImportWeight.MinValue then SeTronicImportWeight.Value := SeTronicImportWeight.MinValue;
      if SeTronicImportWeight.Value > SeTronicImportWeight.MaxValue then SeTronicImportWeight.Value := SeTronicImportWeight.MaxValue;
    end;


    if Assigned(SeTronicImportPasses) then
    begin
      SeTronicImportPasses.Value := ini.ReadInteger('tronic', 'AnsiImportPasses', SeTronicImportPasses.Value);
      if SeTronicImportPasses.Value < SeTronicImportPasses.MinValue then SeTronicImportPasses.Value := SeTronicImportPasses.MinValue;
      if SeTronicImportPasses.Value > SeTronicImportPasses.MaxValue then SeTronicImportPasses.Value := SeTronicImportPasses.MaxValue;
    end;
    if Assigned(ChkTronicImportMirrorH) then
      ChkTronicImportMirrorH.Checked := ini.ReadBool('tronic', 'AnsiImportMirrorH', ChkTronicImportMirrorH.Checked);

    if Assigned(ChkTronicAutoShader) then ChkTronicAutoShader.Checked := ini.ReadBool('tronic', 'AutoShader', ChkTronicAutoShader.Checked);
    if Assigned(SeTronicWin) then SeTronicWin.Value := ini.ReadInteger('tronic', 'Window', SeTronicWin.Value);
    if Assigned(SeTronicStep) then SeTronicStep.Value := ini.ReadInteger('tronic', 'Step', SeTronicStep.Value);

    // Diffusion dropdown (backwards compatible with old boolean)
    if Assigned(CbTronicDiffModel) then
    begin
      i := ini.ReadInteger('tronic', 'DiffModel', -1);
      if i < 0 then
      begin
        // Legacy: if Diffusion=True, pick Floyd–Steinberg; else default to Bayer 4x4
        if ini.ReadBool('tronic', 'Diffusion', False) then i := 3 else i := 1;
      end;
      if i < 0 then i := 0;
      if i > CbTronicDiffModel.Items.Count-1 then i := CbTronicDiffModel.Items.Count-1;
      CbTronicDiffModel.ItemIndex := i;
    end;
    if Assigned(SeTronicDiffAmt) then SeTronicDiffAmt.Value := ini.ReadInteger('tronic', 'DiffusionAmount', SeTronicDiffAmt.Value);
    if Assigned(CbTronicColorMetric) then
    begin
      i := ini.ReadInteger('tronic', 'ColorMetric', CbTronicColorMetric.ItemIndex);
      if i < 0 then i := 0;
      if i > CbTronicColorMetric.Items.Count-1 then i := CbTronicColorMetric.Items.Count-1;
      CbTronicColorMetric.ItemIndex := i;
    end;

    // Tronic glyph set (independent from global glyph set)
    if Assigned(CbTronicGlyphSet) then
    begin
      i := ini.ReadInteger('tronic', 'GlyphSet', CbTronicGlyphSet.ItemIndex);
      if i < 0 then i := 0;
      if i > CbTronicGlyphSet.Items.Count-1 then i := CbTronicGlyphSet.Items.Count-1;
      CbTronicGlyphSet.ItemIndex := i;
    end;

    // Tronicshade style file (independent)
    FTronicStyleFile := ini.ReadString('tronic', 'StyleFile', '');
    if (FTronicStyleFile <> '') and FileExists(FTronicStyleFile) then
      TronicShadeLoadFromFile(FTronicStyleFile);
    UpdateTronicInfo;

    // Color hints (manual palette bias)
if Assigned(SeHintTol) then
begin
  SeHintTol.Value := ini.ReadInteger('hints', 'Tolerance', SeHintTol.Value);
  if SeHintTol.Value < SeHintTol.MinValue then SeHintTol.Value := SeHintTol.MinValue;
  if SeHintTol.Value > SeHintTol.MaxValue then SeHintTol.Value := SeHintTol.MaxValue;
end;
if Assigned(ChkHintUsePalette) then
  ChkHintUsePalette.Checked := ini.ReadBool('hints', 'UseHintPalette', ChkHintUsePalette.Checked);
if Assigned(ChkRefitHintPalette) then
  ChkRefitHintPalette.Checked := ini.ReadBool('hints', 'RefitHintedPaletteEachPass', ChkRefitHintPalette.Checked);

// Hint post-fix snap
if Assigned(ChkHintPostFix) then
  ChkHintPostFix.Checked := ini.ReadBool('hints', 'PostFix', ChkHintPostFix.Checked);
if Assigned(SeHintPostPct) then
begin
  SeHintPostPct.Value := ini.ReadInteger('hints', 'PostFixPct', SeHintPostPct.Value);
  if SeHintPostPct.Value < SeHintPostPct.MinValue then SeHintPostPct.Value := SeHintPostPct.MinValue;
  if SeHintPostPct.Value > SeHintPostPct.MaxValue then SeHintPostPct.Value := SeHintPostPct.MaxValue;
end;
	if Assigned(SeHintPickRadius) then
	begin
	  SeHintPickRadius.Value := ini.ReadInteger('hints', 'PickRadius', SeHintPickRadius.Value);
	  if SeHintPickRadius.Value < SeHintPickRadius.MinValue then SeHintPickRadius.Value := SeHintPickRadius.MinValue;
    if Assigned(ChkTronicGlyphOnly) then ChkTronicGlyphOnly.Checked := ini.ReadBool('tronic', 'GlyphOnly', ChkTronicGlyphOnly.Checked);
    if Assigned(ChkTronicEdgeShade) then ChkTronicEdgeShade.Checked := ini.ReadBool('tronic', 'EdgeShade', ChkTronicEdgeShade.Checked);
    if Assigned(CbTronicEdgeSample) then CbTronicEdgeSample.ItemIndex := ini.ReadInteger('tronic', 'EdgeSample', CbTronicEdgeSample.ItemIndex);
    if Assigned(TbTronicBlockThreshold) then TbTronicBlockThreshold.Position := ini.ReadInteger('tronic', 'BlockThreshold', TbTronicBlockThreshold.Position);
    if Assigned(TbTronicShadeWeight) then TbTronicShadeWeight.Position := ini.ReadInteger('tronic', 'ShadeWeight', TbTronicShadeWeight.Position);
    if Assigned(ChkTronicCornersShadesOnly) then ChkTronicCornersShadesOnly.Checked := ini.ReadBool('tronic', 'CornersShadesOnly', ChkTronicCornersShadesOnly.Checked);
    if Assigned(LblTronicBlockThresholdVal) and Assigned(TbTronicBlockThreshold) then LblTronicBlockThresholdVal.Caption := IntToStr(TbTronicBlockThreshold.Position);
    if Assigned(LblTronicShadeWeightVal) and Assigned(TbTronicShadeWeight) then LblTronicShadeWeightVal.Caption := IntToStr(TbTronicShadeWeight.Position);
	  if SeHintPickRadius.Value > SeHintPickRadius.MaxValue then SeHintPickRadius.Value := SeHintPickRadius.MaxValue;
	end;

cnt := ini.ReadInteger('hints', 'Count', 0);
if cnt < 0 then cnt := 0;
if cnt > 256 then cnt := 256;
SetLength(FColorHints, cnt);
for i := 0 to cnt - 1 do
begin
  FColorHints[i].TargetIdx := Byte(EnsureRange(ini.ReadInteger('hints', Format('h%d_idx', [i]), 0), 0, 15));
  FColorHints[i].Src.R := ClampByte(ini.ReadInteger('hints', Format('h%d_r', [i]), 0));
  FColorHints[i].Src.G := ClampByte(ini.ReadInteger('hints', Format('h%d_g', [i]), 0));
  FColorHints[i].Src.B := ClampByte(ini.ReadInteger('hints', Format('h%d_b', [i]), 0));
  FColorHints[i].Strength := ini.ReadInteger('hints', Format('h%d_strength', [i]), 2500);
end;

UpdateHintsUI;

FPreviewFont.Name := ini.ReadString('font', 'Name', FPreviewFont.Name);
    FPreviewFont.Size := ini.ReadInteger('font', 'Size', FPreviewFont.Size);
    st := ini.ReadInteger('font', 'Style', Integer(FPreviewFont.Style));
    fsStyles := [];
    if (st and 1) <> 0 then Include(fsStyles, fsBold);
    if (st and 2) <> 0 then Include(fsStyles, fsItalic);
    if (st and 4) <> 0 then Include(fsStyles, fsUnderline);
    if (st and 8) <> 0 then Include(fsStyles, fsStrikeOut);
    FPreviewFont.Style := fsStyles;
    DoToggleBiosPreview(nil);

  AnyOptionChanged(nil);
end;

procedure TMainForm.LoadPresetFromFile(const FN: string);
var
  ini: TIniFile;
begin
  ini := TIniFile.Create(FN);
  try
    LoadPresetFromIni(ini);
  finally
    ini.Free;
  end;
end;

procedure TMainForm.CaptureFactoryDefaults;
var
  mem: TMemIniFile;
begin
  // Capture once after UI is created (or recapture if requested).
  if Assigned(FDefaultPresetIni) then FreeAndNil(FDefaultPresetIni);
  FDefaultPresetIni := TStringList.Create;

  mem := TMemIniFile.Create('');
  try
    SavePresetToIni(mem);
    mem.GetStrings(FDefaultPresetIni);
  finally
    mem.Free;
  end;
end;

procedure TMainForm.ResetAllSettingsToFactoryDefaults;
var
  mem: TMemIniFile;
begin
  if not Assigned(FDefaultPresetIni) or (FDefaultPresetIni.Count = 0) then
    CaptureFactoryDefaults;

  if not Assigned(FDefaultPresetIni) or (FDefaultPresetIni.Count = 0) then Exit;

  mem := TMemIniFile.Create('');
  try
    mem.SetStrings(FDefaultPresetIni);
    LoadPresetFromIni(mem);
  finally
    mem.Free;
  end;
end;

procedure TMainForm.DoLoadPreset(Sender: TObject);
begin
  if not Assigned(PresetOpenDlg) then Exit;
  if PresetOpenDlg.Execute then
    LoadPresetFromFile(PresetOpenDlg.FileName);
end;

procedure TMainForm.DoSavePreset(Sender: TObject);
begin
  if not Assigned(PresetSaveDlg) then Exit;
  if PresetSaveDlg.Execute then
    SavePresetToFile(PresetSaveDlg.FileName);
end;


procedure TMainForm.BtnPatchLoadClick(Sender: TObject);
begin
  if not Assigned(PatchOpenDlg) then Exit;
  if not PatchOpenDlg.Execute then Exit;
  if PatchLibLoadFromFile(PatchOpenDlg.FileName) then
  begin
    if Assigned(ChkPatchBlocksOnly) and ChkPatchBlocksOnly.Checked then
      PatchLibFilterBlocksOnly;
    if Assigned(LblPatchInfo) then
    begin
      if Assigned(ChkPatchBlocksOnly) and ChkPatchBlocksOnly.Checked then
        LblPatchInfo.Caption := 'Patchbook: loaded (blocks/shades only)'
      else
        LblPatchInfo.Caption := 'Patchbook: loaded';
    end;
  end
  else
    MessageDlg('Could not load patchbook.', mtError, [mbOK], 0);
end;

procedure TMainForm.BtnPatchSaveClick(Sender: TObject);
begin
  if not Assigned(PatchSaveDlg) then Exit;
  if not PatchSaveDlg.Execute then Exit;
  if not PatchLibHasAny then
  begin
    MessageDlg('Patchbook is empty. Import shader files first.', mtInformation, [mbOK], 0);
    Exit;
  end;
  if not PatchLibSaveToFile(PatchSaveDlg.FileName) then
    MessageDlg('Could not save patchbook.', mtError, [mbOK], 0);
end;

procedure TMainForm.BtnPatchClearClick(Sender: TObject);
begin
  PatchLibClear;
  if Assigned(LblPatchInfo) then LblPatchInfo.Caption := 'Patchbook: (empty)';
end;

procedure TMainForm.UpdateTronicInfo;
var
  t3, t5, t10: Integer;
  fn: string;
begin
  TronicShadeGetScaleTotals(t3, t5, t10);
  if Assigned(LblTronicLib) then
    LblTronicLib.Caption := Format('Lib size:'#13#10'10x10=%d'#13#10'5x5=%d  3x3=%d', [t10, t5, t3]);

  fn := Trim(FTronicStyleFile);
  if fn = '' then
    fn := '(none)'
  else
    fn := ExtractFileName(fn);
  if Assigned(LblTronicFile) then
    LblTronicFile.Caption := 'Style: ' + fn;
end;

procedure TMainForm.BtnTronicLoadClick(Sender: TObject);
var
  dlg: TOpenDialog;
begin
  dlg := TOpenDialog.Create(Self);
  try
    dlg.Title := 'Load Tronicshade style';
    dlg.Filter := 'Tronicshade style (*.tronic.json;*.tronic)|*.tronic.json;*.tronic|JSON (*.json)|*.json|All files (*.*)|*.*';
    dlg.Options := dlg.Options + [ofFileMustExist];
    dlg.InitialDir := GetShadersDir;
    if not dlg.Execute then Exit;
    if TronicShadeLoadFromFile(dlg.FileName) then
    begin
      FTronicStyleFile := dlg.FileName;
      UpdateTronicInfo;
    end
    else
      MessageDlg('Could not load Tronicshade style.', mtError, [mbOK], 0);
  finally
    dlg.Free;
  end;
end;

procedure TMainForm.BtnTronicSaveClick(Sender: TObject);
var
  dlg: TSaveDialog;
begin
  dlg := TSaveDialog.Create(Self);
  try
    dlg.Title := 'Save Tronicshade style';
    dlg.Filter := 'Tronicshade style (*.tronic.json)|*.tronic.json|JSON (*.json)|*.json|All files (*.*)|*.*';
    dlg.DefaultExt := 'tronic.json';
    dlg.InitialDir := GetShadersDir;
    if not dlg.Execute then Exit;
    TronicShadeSaveToFile(dlg.FileName);
    FTronicStyleFile := dlg.FileName;
    UpdateTronicInfo;
  finally
    dlg.Free;
  end;
end;

procedure TMainForm.BtnTronicLoadANSIClick(Sender: TObject);
var
  dlg: TOpenDialog;
  rep: TTronicImportReport;
  ok: Boolean;
  msg: String;
  mirrorStr: String;
begin
  dlg := TOpenDialog.Create(Self);
  try
    dlg.Title := 'Load ANSI into Tronicshade library (shade-only)';
    dlg.Filter := 'ANSI (*.ans;*.ansi)|*.ans;*.ansi|All files (*.*)|*.*';
    dlg.Options := dlg.Options + [ofFileMustExist];
    dlg.InitialDir := GetExportsDir;
    if not dlg.Execute then Exit;

    // Import ANSI into the Tronicshade library. This is independent from ShaderLab.
    // Tronicshade ANSI imports are append-only.
    ok := TronicShadeImportANSIEx(dlg.FileName, 500, True,
      IfThen(Assigned(SeTronicImportWeight), SeTronicImportWeight.Value, 1),
      Assigned(ChkTronicImportMirrorH) and ChkTronicImportMirrorH.Checked,
      IfThen(Assigned(SeTronicImportPasses), SeTronicImportPasses.Value, 1),
      4,
      Assigned(ChkIce) and ChkIce.Checked,
      rep);
    if ok then
    begin
      // This modifies the in-memory Tronicshade library; style file remains unchanged until saved.
      UpdateTronicInfo;
      if rep.MirrorH then mirrorStr := 'Yes' else mirrorStr := 'No';
      msg :=
        'Import report'#13#10+
        '-------------'#13#10+
        'File: ' + ExtractFileName(rep.FileName) + #13#10+
        'Size used: ' + IntToStr(rep.Width) + ' x ' + IntToStr(rep.HeightUsed) +
          '  (' + IntToStr(rep.TotalCells) + ' cells)' + #13#10+
        'Shade cells seen: ' + IntToStr(rep.ShadeCells) + #13#10+
        'Passes: ' + IntToStr(rep.Passes) +
          '   Weight: ' + IntToStr(rep.Weight) +
          '   MirrorH: ' + mirrorStr +
          '   DedupeCap: ' + IntToStr(rep.DedupeCap) + #13#10+
        #13#10+
        '3x3 patches  tried: ' + IntToStr(rep.Tried3) +
          '  added: ' + IntToStr(rep.Added3) +
          '  blocked: ' + IntToStr(rep.Blocked3) + #13#10+
        '5x5 patches  tried: ' + IntToStr(rep.Tried5) +
          '  added: ' + IntToStr(rep.Added5) +
          '  blocked: ' + IntToStr(rep.Blocked5) + #13#10+
        '10x10 patches tried: ' + IntToStr(rep.Tried10) +
          '  added: ' + IntToStr(rep.Added10) +
          '  blocked: ' + IntToStr(rep.Blocked10) + #13#10+
        #13#10+
        'Tip: click Save... to store it as a Tronicshade style file.';
      MessageDlg(msg, mtInformation, [mbOK], 0);
    end
    else
      MessageDlg('Could not import ANSI into Tronicshade library.', mtError, [mbOK], 0);
  finally
    dlg.Free;
  end;
end;

procedure TMainForm.TronicRetroTextureChanged(Sender: TObject);
begin
  if Assigned(LblTronicRetroTexture) and Assigned(TbTronicRetroTexture) then
    LblTronicRetroTexture.Caption := IntToStr(TbTronicRetroTexture.Position);
end;

procedure TMainForm.ApplyTronicPreset(idx: Integer);
  procedure SetSpin(se: TSpinEdit; v: Integer);
  begin
    if Assigned(se) then se.Value := EnsureRange(v, se.MinValue, se.MaxValue);
  end;
  procedure SetCombo(cb: TComboBox; v: Integer);
  begin
    if Assigned(cb) then
      cb.ItemIndex := EnsureRange(v, 0, cb.Items.Count-1);
  end;
begin
  // Presets are intended to be "good looks fast" and only touch Tronicshade.
  // They adjust: Retro Style/Texture + a few Tronic/Hybrid-ish knobs inside Tronic.
  FTronicRetroPassCount := 1;
  case idx of
    0: begin // Hybrid Clean
      SetCombo(CbTronicRetroStyle, 0); // Neutral
      if Assigned(TbTronicRetroTexture) then TbTronicRetroTexture.Position := 0;
      if Assigned(ChkTronicRetroBlocks) then ChkTronicRetroBlocks.Checked := True;
      SetCombo(CbTronicDiffModel, 1); // Ordered 4x4
      SetSpin(SeTronicDiffAmt, 20);
      SetCombo(CbTronicGlyphSet, Ord(gsAnsiBlocksPixel));
      SetCombo(CbTronicColorMetric, 0); // Luma only
      SetSpin(SeTronicStrength, 70);
      SetSpin(SeTronicTone, 0);
    end;
    1: begin // CRT Soft
      SetCombo(CbTronicRetroStyle, 3); // Grainy
      if Assigned(TbTronicRetroTexture) then TbTronicRetroTexture.Position := 15;
      if Assigned(ChkTronicRetroBlocks) then ChkTronicRetroBlocks.Checked := True;
      SetCombo(CbTronicDiffModel, 1); SetSpin(SeTronicDiffAmt, 25);
      SetCombo(CbTronicGlyphSet, Ord(gsAnsiBlocksPixel));
      SetCombo(CbTronicColorMetric, 3); // YCbCr
      SetSpin(SeTronicStrength, 80);
      SetSpin(SeTronicTone, -8);
    end;
    2: begin // DOS Photo
      SetCombo(CbTronicRetroStyle, 3); // Grainy
      if Assigned(TbTronicRetroTexture) then TbTronicRetroTexture.Position := 25;
      if Assigned(ChkTronicRetroBlocks) then ChkTronicRetroBlocks.Checked := True;
      SetCombo(CbTronicDiffModel, 3); SetSpin(SeTronicDiffAmt, 45); // Floyd–Steinberg
      SetCombo(CbTronicGlyphSet, Ord(gsTronic));
      SetCombo(CbTronicColorMetric, 4); // HSV adaptive
      SetSpin(SeTronicStrength, 85);
      SetSpin(SeTronicTone, -4);
    end;
    3: begin // VGA Crunch
      SetCombo(CbTronicRetroStyle, 2); // CGA Crunch
      if Assigned(TbTronicRetroTexture) then TbTronicRetroTexture.Position := 45;
      if Assigned(ChkTronicRetroBlocks) then ChkTronicRetroBlocks.Checked := True;
      SetCombo(CbTronicDiffModel, 1); SetSpin(SeTronicDiffAmt, 30);
      SetCombo(CbTronicGlyphSet, Ord(gsAnsiBlocksPixel));
      SetCombo(CbTronicColorMetric, 2); // Redmean
      SetSpin(SeTronicStrength, 95);
      SetSpin(SeTronicTone, 10);
    end;
    4: begin // Block Poster
      SetCombo(CbTronicRetroStyle, 1); // Blocky
      if Assigned(TbTronicRetroTexture) then TbTronicRetroTexture.Position := 60;
      if Assigned(ChkTronicRetroBlocks) then ChkTronicRetroBlocks.Checked := True;
      SetCombo(CbTronicDiffModel, 0); SetSpin(SeTronicDiffAmt, 0); // Off
      SetCombo(CbTronicGlyphSet, Ord(gsAnsiBlocks));
      SetCombo(CbTronicColorMetric, 2);
      SetSpin(SeTronicStrength, 100);
      SetSpin(SeTronicTone, 20);
    end;
    5: begin // Neon Bright
      SetCombo(CbTronicRetroStyle, 3); // Grainy
      if Assigned(TbTronicRetroTexture) then TbTronicRetroTexture.Position := 35;
      if Assigned(ChkTronicRetroBlocks) then ChkTronicRetroBlocks.Checked := True;
      SetCombo(CbTronicDiffModel, 3); SetSpin(SeTronicDiffAmt, 55);
      SetCombo(CbTronicGlyphSet, Ord(gsTronic));
      SetCombo(CbTronicColorMetric, 4);
      SetSpin(SeTronicStrength, 90);
      SetSpin(SeTronicTone, 18);
    end;
    6: begin // Scanline Classic
      SetCombo(CbTronicRetroStyle, 4); // Scanline
      if Assigned(TbTronicRetroTexture) then TbTronicRetroTexture.Position := 25;
      if Assigned(ChkTronicRetroBlocks) then ChkTronicRetroBlocks.Checked := True;
      SetCombo(CbTronicDiffModel, 1); SetSpin(SeTronicDiffAmt, 25);
      SetCombo(CbTronicGlyphSet, Ord(gsAnsiBlocksPixel));
      SetCombo(CbTronicColorMetric, 3);
      SetSpin(SeTronicStrength, 85);
      SetSpin(SeTronicTone, 0);
    end;
    7: begin // Retro Heavy
      SetCombo(CbTronicRetroStyle, 2); // CGA Crunch
      if Assigned(TbTronicRetroTexture) then TbTronicRetroTexture.Position := 75;
      if Assigned(ChkTronicRetroBlocks) then ChkTronicRetroBlocks.Checked := True;
      SetCombo(CbTronicDiffModel, 1); SetSpin(SeTronicDiffAmt, 40);
      SetCombo(CbTronicGlyphSet, Ord(gsTronic));
      SetCombo(CbTronicColorMetric, 2);
      SetSpin(SeTronicStrength, 100);
      SetSpin(SeTronicTone, 30);
    end;
    8: begin // ANSI Art Mode
      SetCombo(CbTronicRetroStyle, 1); // Blocky
      if Assigned(TbTronicRetroTexture) then TbTronicRetroTexture.Position := 40;
      if Assigned(ChkTronicRetroBlocks) then ChkTronicRetroBlocks.Checked := True;
      SetCombo(CbTronicDiffModel, 0); SetSpin(SeTronicDiffAmt, 0);
      SetCombo(CbTronicGlyphSet, Ord(gsAnsiBlocks));
      SetCombo(CbTronicColorMetric, 1); // RGB
      SetSpin(SeTronicStrength, 100);
      SetSpin(SeTronicTone, 0);
    end;

    9: begin // Rounded
      // Softer, smoother look for curves/portraits.
      SetCombo(CbTronicRetroStyle, 3); // Grainy
      if Assigned(TbTronicRetroTexture) then TbTronicRetroTexture.Position := 22;
      // Respect user's block scope preference (do not force).
      SetCombo(CbTronicDiffModel, 1); SetSpin(SeTronicDiffAmt, 25); // Ordered
      SetCombo(CbTronicGlyphSet, Ord(gsAnsiBlocksPixel));
      SetCombo(CbTronicColorMetric, 3); // YCbCr
      SetSpin(SeTronicStrength, 78);
      SetSpin(SeTronicTone, -10);
    end;

    10: begin // Extreme (4-Pass)
      // Dramatic multi-pass stylize. Do NOT override user's IncludeBlocks.
      SetCombo(CbTronicRetroStyle, 2); // CGA Crunch
      if Assigned(TbTronicRetroTexture) then TbTronicRetroTexture.Position := 95;
      SetCombo(CbTronicDiffModel, 3); SetSpin(SeTronicDiffAmt, 60); // Floyd–Steinberg
      SetCombo(CbTronicGlyphSet, Ord(gsTronic));
      SetCombo(CbTronicColorMetric, 4); // HSV adaptive
      SetSpin(SeTronicStrength, 100);
      SetSpin(SeTronicTone, 35);
      FTronicRetroPassCount := 4;
    end;
  end;

  // Update texture label + trigger recompute if needed
  TronicRetroTextureChanged(nil);
  AnyOptionChanged(nil);
end;

procedure TMainForm.TronicPresetChanged(Sender: TObject);
begin
  if not Assigned(CbTronicPreset) then Exit;
  ApplyTronicPreset(CbTronicPreset.ItemIndex);
end;

procedure TMainForm.BtnRenderTronicClick(Sender: TObject);
begin
  // Convenience: switch the main mode to TronicShade and render.
  if Assigned(CbMode) then
    CbMode.Text := 'tronicshade';
  // Show a render report popup after this render.
  FShowTronicReportAfterRender := True;
  DoRender(nil);
end;



procedure TMainForm.AnsiLabLog(const S: string);
begin
  if not Assigned(MemoAnsiLab) then Exit;
  MemoAnsiLab.Lines.Add(FormatDateTime('hh:nn:ss', Now) + '  ' + S);
end;

function SafePresetName(const S: string): string;
var
  i: Integer;
  c: Char;
begin
  Result := '';
  for i := 1 to Length(S) do
  begin
    c := S[i];
    if c in ['A'..'Z','a'..'z','0'..'9','_','-',' '] then
      Result := Result + c;
  end;
  Result := Trim(Result);
  if Result = '' then Result := 'style';
end;

procedure TMainForm.BtnAnsiLabBuildClick(Sender: TObject);
var
  dlg: TOpenDialog;
  i: Integer;
  presetName: string;
  treatIce: Boolean;
  mirrorH: Boolean;
  learnShadeOnly: Boolean;
  maxRows, passes, weight, dedupe: Integer;
  rep: TTronicImportReport;
  okT, okS: Boolean;
  tronicFN, shaderFN, presetFN: string;
  totCells, totSpace, totFull, tot25, tot50, tot75, totHU, totHD, totHL, totHR: Int64;
  shadePct, fullPct, halfPct: Double;
  recStrength, recDiffAmt, recShadeWeight, recBlockThr: Integer;
  root, rec, stats: TJSONObject;
  fs: TFileStream;
  sjson: string;
  presetIniFN: string;
  ini: TIniFile;
  modeIdx, ditherIdx, tronicDiffIdx: Integer;
begin
  dlg := TOpenDialog.Create(Self);
  try
    dlg.Title := 'Select ANSI file(s) to learn a style preset';
    dlg.Filter := 'ANSI (*.ans;*.ansi)|*.ans;*.ansi|All files (*.*)|*.*';
    dlg.Options := dlg.Options + [ofFileMustExist, ofAllowMultiSelect];
    dlg.InitialDir := GetExportsDir;
    if not dlg.Execute then Exit;
    if dlg.Files.Count = 0 then Exit;

    presetName := Trim(EdAnsiLabName.Text);
    if presetName = '' then
      presetName := ChangeFileExt(ExtractFileName(dlg.Files[0]), '');
    presetName := SafePresetName(presetName);
    EdAnsiLabName.Text := presetName;

    treatIce := (Assigned(ChkAnsiLabTreatBlinkAsIce) and ChkAnsiLabTreatBlinkAsIce.Checked);
    mirrorH := (Assigned(ChkAnsiLabMirrorH) and ChkAnsiLabMirrorH.Checked);
    learnShadeOnly := (Assigned(ChkAnsiLabLearnShadeOnly) and ChkAnsiLabLearnShadeOnly.Checked);
    maxRows := IfThen(Assigned(SeAnsiLabMaxRows), SeAnsiLabMaxRows.Value, 200);
    passes := IfThen(Assigned(SeAnsiLabPasses), SeAnsiLabPasses.Value, 3);
    weight := IfThen(Assigned(SeAnsiLabWeight), SeAnsiLabWeight.Value, 3);
    dedupe := IfThen(Assigned(SeAnsiLabDedupeCap), SeAnsiLabDedupeCap.Value, 4);

    AnsiLabLog('--- Build preset: ' + presetName + ' ---');
    AnsiLabLog(Format('ANSI files: %d   MaxRows=%d  Passes=%d  Weight=%d  Dedupe=%d  iCE=%s',
      [dlg.Files.Count, maxRows, passes, weight, dedupe, BoolToStr(treatIce, True)]));

    // Reset learning state
    TronicShadeClear;
    ShaderSetActiveProfile(presetName);
    ShaderClear;

    totCells := 0;
    totSpace := 0; totFull := 0; tot25 := 0; tot50 := 0; tot75 := 0;
    totHU := 0; totHD := 0; totHL := 0; totHR := 0;

    for i := 0 to dlg.Files.Count-1 do
    begin
      FillChar(rep, SizeOf(rep), 0);

      okT := TronicShadeImportANSIEx(dlg.Files[i], maxRows, (i > 0),
        weight, mirrorH, passes, dedupe, treatIce, rep);

      okS := ShaderImportANSIToActive(dlg.Files[i], maxRows, (i > 0), treatIce, learnShadeOnly);

      if okT then
      begin
        AnsiLabLog(Format('Tronic: %s  used=%dx%d  cells=%d  shadeCells=%d',
          [ExtractFileName(rep.FileName), rep.Width, rep.HeightUsed, rep.TotalCells, rep.ShadeCells]));
        Inc(totCells, rep.TotalCells);
        Inc(totSpace, rep.CountSpace);
        Inc(totFull, rep.CountFull);
        Inc(tot25, rep.CountShade25);
        Inc(tot50, rep.CountShade50);
        Inc(tot75, rep.CountShade75);
        Inc(totHU, rep.CountHalfUp);
        Inc(totHD, rep.CountHalfDown);
        Inc(totHL, rep.CountHalfLeft);
        Inc(totHR, rep.CountHalfRight);
      end
      else
        AnsiLabLog('Tronic import FAILED: ' + ExtractFileName(dlg.Files[i]));

      if not okS then
        AnsiLabLog('Shader import FAILED: ' + ExtractFileName(dlg.Files[i]));
    end;

    // Save outputs
    tronicFN := GetShadersDir + presetName + '.tronic.json';
    TronicShadeSaveToFile(tronicFN);
    FTronicStyleFile := tronicFN;
    UpdateTronicInfo;

    ShaderSaveActiveProfile;
    shaderFN := GetStylesDir + presetName + '.json';

    // Compute basic glyph mix
    if totCells <= 0 then totCells := 1;
    shadePct := (tot25 + tot50 + tot75) * 100.0 / totCells;
    fullPct := (totFull) * 100.0 / totCells;
    halfPct := (totHU + totHD + totHL + totHR) * 100.0 / totCells;

    // Heuristic recommended settings from the example ANSI mix.
    // - Low shadePct + high fullPct tends to be "toon/posterized"
    // - Higher shadePct + half blocks tends to be "death/gritty"
    recStrength := 170;
    recDiffAmt := 60;
    recShadeWeight := 120;
    recBlockThr := 55;

    if (shadePct < 1.0) and (fullPct > 45.0) then
    begin
      // Toon-ish: reduce texture, keep ramps bold
      recStrength := 130;
      recDiffAmt := 45;
      recShadeWeight := 90;
      recBlockThr := 65;
    end
    else if (shadePct >= 2.5) and (halfPct >= 25.0) then
    begin
      // Death-ish: more texture and blending
      recStrength := 200;
      recDiffAmt := 70;
      recShadeWeight := 140;
      recBlockThr := 48;
    end;

    // Write AnsiLab manifest
    presetFN := GetStylesDir + presetName + '.ansilab.json';
    root := TJSONObject.Create;
    try
      root.Add('version', 2);
      root.Add('name', presetName);
      root.Add('icemode', treatIce);
      root.Add('shader_profile', ExtractFileName(shaderFN));
      root.Add('tronic_style', ExtractFileName(tronicFN));

      // Full program preset (INI) capturing all settings, not just TronicShade.
      // We snapshot current UI preset, then override the key choices for this learned style.
      presetIniFN := GetPresetsDir + presetName + '.preset.ini';
      ini := TIniFile.Create(presetIniFN);
      try
        SavePresetToIni(ini);

        // Convert path defaults for ANSI-style output
        modeIdx := -1;
        ditherIdx := -1;
        tronicDiffIdx := -1;
        if Assigned(CbMode) then modeIdx := CbMode.Items.IndexOf('tronicshade');
        if Assigned(CbDither) then ditherIdx := CbDither.Items.IndexOf('bayer4');
        if Assigned(CbTronicDiffModel) then tronicDiffIdx := CbTronicDiffModel.Items.IndexOf('bayer4');

        if modeIdx >= 0 then ini.WriteInteger('ui', 'Mode', modeIdx);
        // Prefer text for palette (LoadPresetFromIni already supports PaletteText)
        ini.WriteString('ui', 'PaletteText', 'vga16');
        if ditherIdx >= 0 then ini.WriteInteger('ui', 'Dither', ditherIdx);
        ini.WriteBool('ui', 'Ice', treatIce);
        ini.WriteString('ui', 'ShaderProfile', presetName);

        // Recommended Tronic settings derived from the training ANSI mix
        ini.WriteInteger('tronic', 'Strength', recStrength);
        ini.WriteInteger('tronic', 'DiffusionAmount', recDiffAmt);
        if tronicDiffIdx >= 0 then ini.WriteInteger('tronic', 'DiffModel', tronicDiffIdx);
        ini.WriteInteger('tronic', 'ShadeWeight', recShadeWeight);
        ini.WriteInteger('tronic', 'BlockThreshold', recBlockThr);
        // Absolute path so preset works regardless of current working dir
        ini.WriteString('tronic', 'StyleFile', tronicFN);
      finally
        ini.Free;
      end;

      root.Add('program_preset', ExtractFileName(presetIniFN));

      stats := TJSONObject.Create;
      stats.Add('cells', Int64(totCells));
      stats.Add('pct_full', fullPct);
      stats.Add('pct_half', halfPct);
      stats.Add('pct_shade', shadePct);
      root.Add('stats', stats);

      rec := TJSONObject.Create;
      rec.Add('tronic_strength', recStrength);
      rec.Add('tronic_diff_model', 'bayer4');
      rec.Add('tronic_diff_amt', recDiffAmt);
      rec.Add('tronic_shade_weight', recShadeWeight);
      rec.Add('tronic_block_threshold', recBlockThr);
      root.Add('recommend', rec);

      sjson := root.AsJSON;
      fs := TFileStream.Create(presetFN, fmCreate);
      try
        fs.WriteBuffer(Pointer(sjson)^, Length(sjson));
      finally
        fs.Free;
      end;
    finally
      root.Free;
    end;

    FLastAnsiLabPreset := presetFN;

    // Refresh UI lists
    if Assigned(CbShaderProfile) then
    begin
      ShaderFillProfileNames(CbShaderProfile.Items);
      CbShaderProfile.ItemIndex := CbShaderProfile.Items.IndexOf(presetName);
    end;

    AnsiLabLog(Format('Saved: %s', [ExtractFileName(presetFN)]));
    AnsiLabLog(Format('  Tronic: %s', [ExtractFileName(tronicFN)]));
    AnsiLabLog(Format('  Shader: %s', [ExtractFileName(shaderFN)]));
    AnsiLabLog(Format('  Program preset: %s', [ExtractFileName(presetIniFN)]));
    AnsiLabLog(Format('Mix: full=%.1f%%  half=%.1f%%  shade(░▒▓)=%.1f%%', [fullPct, halfPct, shadePct]));
    AnsiLabLog(Format('Recommend: Strength=%d  Diff=%d  ShadeWeight=%d  BlockThr=%d',
      [recStrength, recDiffAmt, recShadeWeight, recBlockThr]));

    if Assigned(BtnAnsiLabApplyPreset) then
      BtnAnsiLabApplyPreset.Enabled := True;

    MessageDlg('Preset saved to: ' + presetFN, mtInformation, [mbOK], 0);
  finally
    dlg.Free;
  end;
end;

procedure TMainForm.BtnAnsiLabLoadPresetClick(Sender: TObject);
var
  dlg: TOpenDialog;
begin
  dlg := TOpenDialog.Create(Self);
  try
    dlg.Title := 'Load AnsiLab preset';
    dlg.Filter := 'AnsiLab preset (*.ansilab.json)|*.ansilab.json|JSON (*.json)|*.json|All files (*.*)|*.*';
    dlg.Options := dlg.Options + [ofFileMustExist];
    dlg.InitialDir := GetStylesDir;
    if not dlg.Execute then Exit;
    FLastAnsiLabPreset := dlg.FileName;
    AnsiLabLog('Loaded preset file: ' + ExtractFileName(FLastAnsiLabPreset));
    if Assigned(BtnAnsiLabApplyPreset) then
      BtnAnsiLabApplyPreset.Enabled := True;
  finally
    dlg.Free;
  end;
end;

procedure TMainForm.BtnAnsiLabApplyPresetClick(Sender: TObject);
var
  fs: TFileStream;
  s: string;
  json: TJSONData;
  root, rec: TJSONObject;
  shaderFile, tronicFile: string;
  ice: Boolean;
  strength, diffAmt, shadeW, blockThr: Integer;
  idx: Integer;
  progPreset: string;
begin
  if Trim(FLastAnsiLabPreset) = '' then Exit;
  if not FileExists(FLastAnsiLabPreset) then
  begin
    MessageDlg('Preset file not found.', mtError, [mbOK], 0);
    Exit;
  end;

  fs := TFileStream.Create(FLastAnsiLabPreset, fmOpenRead or fmShareDenyNone);
  try
    SetLength(s, fs.Size);
    if fs.Size > 0 then
      fs.ReadBuffer(Pointer(s)^, Length(s));
  finally
    fs.Free;
  end;

  json := GetJSON(s);
  try
    if (json = nil) or (json.JSONType <> jtObject) then
    begin
      MessageDlg('Invalid preset JSON.', mtError, [mbOK], 0);
      Exit;
    end;

    root := TJSONObject(json);
    name := root.Get('name', '');
    ice := root.Get('icemode', True);
    shaderFile := root.Get('shader_profile', '');
    tronicFile := root.Get('tronic_style', '');
    progPreset := root.Get('program_preset', '');

    // If this AnsiLab preset includes a full program preset (INI), load it first.
    // This applies *all* settings (mode, palette, dither, window, etc.) in one shot.
    if progPreset <> '' then
    begin
      if FileExists(GetPresetsDir + progPreset) then
        LoadPresetFromFile(GetPresetsDir + progPreset)
      else if FileExists(GetStylesDir + progPreset) then
        LoadPresetFromFile(GetStylesDir + progPreset)
      else if FileExists(progPreset) then
        LoadPresetFromFile(progPreset);
    end;

    // Load shader profile (by name)
    if name <> '' then
    begin
      ShaderSetActiveProfile(name);
      ShaderReloadActiveProfile;
      if Assigned(CbShaderProfile) then
      begin
        ShaderFillProfileNames(CbShaderProfile.Items);
        idx := CbShaderProfile.Items.IndexOf(name);
        if idx >= 0 then CbShaderProfile.ItemIndex := idx;
      end;
    end;

    // Load Tronic style file
    if tronicFile <> '' then
    begin
      if FileExists(GetShadersDir + tronicFile) then
        tronicFile := GetShadersDir + tronicFile
      else if FileExists(GetStylesDir + tronicFile) then
        tronicFile := GetStylesDir + tronicFile;
      if TronicShadeLoadFromFile(tronicFile) then
      begin
        FTronicStyleFile := tronicFile;
        UpdateTronicInfo;
      end;
    end;

    // Apply recommended settings
    rec := root.Objects['recommend'];
    if rec <> nil then
    begin
      strength := rec.Get('tronic_strength', 170);
      diffAmt := rec.Get('tronic_diff_amt', 60);
      shadeW := rec.Get('tronic_shade_weight', 120);
      blockThr := rec.Get('tronic_block_threshold', 55);

      if Assigned(SeTronicStrength) then SeTronicStrength.Value := strength;
      if Assigned(SeTronicDiffAmt) then SeTronicDiffAmt.Value := diffAmt;
      if Assigned(TbTronicShadeWeight) then TbTronicShadeWeight.Position := shadeW;
      if Assigned(LblTronicShadeWeightVal) then LblTronicShadeWeightVal.Caption := IntToStr(shadeW);
      if Assigned(TbTronicBlockThreshold) then TbTronicBlockThreshold.Position := blockThr;
      if Assigned(LblTronicBlockThresholdVal) then LblTronicBlockThresholdVal.Caption := IntToStr(blockThr);
      if Assigned(CbTronicDiffModel) then CbTronicDiffModel.ItemIndex := 1; // bayer4, matches our current list order (off, bayer4, bayer8, fs)
    end;

    // Set iCE checkbox to match preset (affects output BG legality)
    if Assigned(ChkIce) then ChkIce.Checked := ice;

    AnsiLabLog('Applied preset: ' + name);
    AnyOptionChanged(nil);
  finally
    json.Free;
  end;
end;

end.
