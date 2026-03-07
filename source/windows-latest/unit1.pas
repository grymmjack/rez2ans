unit unit1;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtDlgs, ExtCtrls,
  StdCtrls, ComCtrls, Spin, Math, Types, IniFiles, Menus, FPImage,
  FPReadPNG, FPReadJPEG, FPReadBMP, FPWritePNG, LCLIntf, uDosFont8x16, uViewportTransform;

type

  TAdjustSettings = record
    RedPct: Integer;       // 100 = no change
    GreenPct: Integer;     // 100 = no change
    BluePct: Integer;      // 100 = no change
    Brightness: Integer;   // -100..100
    Contrast: Integer;     // -100..100 (mapped to 0..2)
    AutoContrast: Boolean; // Percentile luminance contrast stretch (auto-levels)
    GammaPct: Integer;     // 100 = 1.0 gamma
    SaturationPct: Integer;// 100 = no change, 0 = grayscale
    HueDeg: Integer;       // -180..180
    MidContrast: Integer;  // -100..100 (midtone contrast curve on luma)
    BlurRadius: Integer;   // 0..5
    SharpenAmt: Integer;   // 0..100
    ClarityAmt: Integer;   // 0..100
    DenoisePasses: Integer;// 0..3
    ChromaDenoiseAmt: Integer; // 0..100 (smooth chroma only; preserve luma)
    GuidedAmt: Integer;        // 0..100 (edge-preserving luma smoothing)
    EdgeAmt: Integer;      // 0..100
    EdgeStyle: Integer;    // ComboEdgeStyle index (0..)
    BilateralAmt: Integer; // 0..100 (placeholder)
    DosBiasPct: Integer;   // 0..100 (pull colors toward DOS 16 palette)
    QuantMethod: Integer;  // 0 none, 1 uniform, 2 median cut, 3 octree, 4 DOS 16
    QuantLevels: Integer;  // target colors (2..256); 256 disables (except DOS 16)
    DitherStyle: Integer;  // 0 none,1 ordered,2 FS
  end;

  TAnsiConvSettings = record
    Cols: Integer;
    Rows: Integer;
    KeepAspect: Boolean;
    AutoRows: Boolean;
    IceColors: Boolean;
    SampleMode: Integer; // 0=2x2, 1=2x3, 2=2x4
    ColorMetric: Integer; // 0=RGB, 1=Redmean, 2=CIE76(Lab), 3=RGB Manhattan, 4=Linear RGB, 5=CIE94(Lab), 6=CIEDE2000(Lab), 7=HSL Hue-first, 8=HSL Weighted
    DitherStyle: Integer; // 0=None, 1=Ordered, 2=Floyd-Steinberg
    DitherStrength: Integer; // 0..100
    StabilityPct: Integer; // 0..100 (penalize color changes between cells)
    EdgeBiasPct: Integer; // 0..100 (50=default)
    // Advanced scoring knobs (shown in the Advanced... dialog)
    BiasMode: Integer; // 0=None, 1=Prefer dark, 2=Prefer bright, 3=Prefer grays, 4=Penalize B/W
    BiasStrength: Integer; // 0..100
    LumBucketStrength: Integer; // 0..100 (0 disables)
    LumBucketThreshold: Integer; // 0..255
    ChromaPenaltyPct: Integer; // 0..100 (penalize saturation mismatch / pull neutrals toward grays)
    MultiPass4: Boolean; // Run 4 conversion layers and auto-pick best per region
    StyleId: Integer; // 0=Custom,1=Scene,2=Toon,3=Death,4=Group,5=Tutorial
    ForceBg: Boolean;
    ForceBgColor: Integer; // 0..15 (clamped based on iCE)
    Sel: TRect; // source selection rect in pixel coords (Right/Bottom exclusive)
  end;

  TSelHandle = (shNone, shN, shS, shE, shW, shNW, shNE, shSW, shSE);
  TSelDragMode = (sdNone, sdCreate, sdMove, sdResize);

  { TMainForm }

  TMainForm = class(TForm)
    BtnOpen: TButton;
    BtnSaveAnsi: TButton;
    BtnAnsiAdvanced: TButton;
    FitCheck: TCheckBox;
    CheckAutoContrast: TCheckBox;
    CheckAnsiAutoRows: TCheckBox;
    CheckAnsiKeepAspect: TCheckBox;
    CheckAnsiMultiPass: TCheckBox;
    CheckICE: TCheckBox;
    LabelAnsiStyle: TLabel;
    ComboAnsiStyle: TComboBox;

    GroupBoxTone: TTabSheet;
    GroupBoxDetail: TTabSheet;
    GroupBoxFX: TTabSheet;
    GroupBoxAnsi: TTabSheet;
    LabelAnsiCols: TLabel;
    LabelAnsiRows: TLabel;
    LabelAnsiSample: TLabel;
    LabelAnsiMetric: TLabel;
    LabelAnsiDither: TLabel;
    LabelAnsiDitherStrength: TLabel;
    LabelAnsiStability: TLabel;
    LabelAnsiEdgeBias: TLabel;
    LabelBlur: TLabel;
    LabelClarity: TLabel;
    LabelDenoise: TLabel;
    LabelChromaDenoise: TLabel;
    LabelGuided: TLabel;
    LabelEdge: TLabel;
    LabelEdgeStyle: TLabel;
    LabelGamma: TLabel;
    LabelQuantize: TLabel;
    LabelQuantMethod: TLabel;
    LabelRed: TLabel;
    LabelGreen: TLabel;
    LabelBlue: TLabel;
    LabelBrightness: TLabel;
    LabelContrast: TLabel;
    LabelSharpen: TLabel;
    LabelDither: TLabel;
    LabelDosBias: TLabel;
    LabelHue: TLabel;
    LabelMidContrast: TLabel;
    AnsiGroup: TGroupBox;
    AnsiScroll: TScrollBox;
    AnsiImage: TImage;
    AnsiStatus: TStatusBar;
    ModsTabs: TPageControl;
    TrackDosBias: TTrackBar;
    TrackRed: TTrackBar;
    TrackGreen: TTrackBar;
    TrackBlue: TTrackBar;
    TrackBrightness: TTrackBar;
    TrackContrast: TTrackBar;
    TrackGamma: TTrackBar;
    LabelSaturation: TLabel;
    TrackSaturation: TTrackBar;
    TrackBlur: TTrackBar;
    TrackSharpen: TTrackBar;
    TrackClarity: TTrackBar;
    TrackDenoise: TTrackBar;
    TrackChromaDenoise: TTrackBar;
    TrackGuided: TTrackBar;
    TrackEdge: TTrackBar;
    TrackBilateral: TTrackBar;
    TrackHue: TTrackBar;
    TrackMidContrast: TTrackBar;
    LabelBilateral: TLabel;
    SpinAnsiCols: TSpinEdit;
    SpinAnsiRows: TSpinEdit;
    ComboQuantize: TComboBox;
    ComboQuantMethod: TComboBox;
    ComboDither: TComboBox;
    ComboEdgeStyle: TComboBox;
    ComboAnsiSample: TComboBox;
    ComboAnsiMetric: TComboBox;
    CheckAnsiForceBg: TCheckBox;
    ComboAnsiForceBg: TComboBox;
    ComboAnsiDither: TComboBox;
    TrackAnsiDitherStrength: TTrackBar;
    TrackAnsiStability: TTrackBar;
    TrackAnsiEdgeBias: TTrackBar;
  LabelZoom: TLabel;
    Panel1: TPanel;
    OpenPictureDialog1: TOpenPictureDialog;
    SaveDialogAnsi: TSaveDialog;
    SourceGroup: TGroupBox;
  SourceScroll: TScrollBox;
  SourceImage: TImage;
  SourceOverlay: TPaintBox;
  SourceStatus: TStatusBar;
  ProcessTimer: TTimer;
  ZoomTrack: TTrackBar;
  procedure BtnOpenClick(Sender: TObject);
  procedure BtnSaveAnsiClick(Sender: TObject);
  procedure BtnAnsiAdvancedClick(Sender: TObject);
    procedure FitCheckChange(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormResize(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ModsChange(Sender: TObject);
    procedure AnsiControlsChange(Sender: TObject);
    procedure ProcessTimerTimer(Sender: TObject);
    procedure SourceOverlayMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure SourceOverlayMouseMove(Sender: TObject; Shift: TShiftState; X,
      Y: Integer);
    procedure SourceOverlayMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure SourceOverlayPaint(Sender: TObject);
    procedure ZoomTrackChange(Sender: TObject);
  private
    FUpdatingControls: Boolean;
    FOutputDir: string;
    FPresetsDir: string;
    FAppIniPath: string;
    FLastImageDir: string;
    FSettingsOpenDialog: TOpenDialog;
    FSettingsSaveDialog: TSaveDialog;
    FMainMenu: TMainMenu;

    FSource: TPicture;
    FSourceBitmap: TBitmap;
    FWorking: TBitmap;
    FScaled: TBitmap;
    FViewport: TViewportTransform;
    FAnsiDebounceTimer: TTimer;
    FSelActive: Boolean;
    FSelecting: Boolean;
    FSelDragMode: TSelDragMode;
    FSelDragHandle: TSelHandle;
    FSelHoverHandle: TSelHandle;
    FSelRect: TRect; // in working pixel coords (Right/Bottom exclusive)
    FSelStartW: TPoint; // drag-start mouse point in working coords
    FSelStartRect: TRect; // selection rect at drag start (working coords)
    FAnsiPreview: TBitmap;
    FAnsiBin: TBytes; // [ch,attr] pairs, length = Cols*Rows*2
    FAnsiCols: Integer;
    FAnsiRows: Integer;
    FAnsiIceUsed: Boolean; // True if current ANSI buffer uses iCE (bright) background colors
    // ANSI Advanced scoring options (configured via Advanced... dialog)
    FAnsiBiasMode: Integer;
    FAnsiBiasStrength: Integer;
    FAnsiLumBucketStrength: Integer;
    FAnsiLumBucketThreshold: Integer;
    FAnsiChromaPenaltyPct: Integer;
    FAdjustThread: TThread;
    FRequestedJobId: LongInt;
    FRunningJobId: LongInt;
    FRequestedSettings: TAdjustSettings;
    FAnsiThread: TThread;
    FAnsiRequestedJobId: LongInt;
    FAnsiRunningJobId: LongInt;
    FAnsiRequestedSettings: TAnsiConvSettings;
    FClosing: Boolean;
    FIsProcessing: Boolean;
    FAnsiIsProcessing: Boolean;
    procedure ApplyFitIfNeeded;
    procedure ApplyAdjustments;
    procedure ScheduleAdjustments;
    procedure ScheduleAnsiPreview;
    procedure UpdateViewport;
    procedure AnsiDebounceTimerTimer(Sender: TObject);
    function CaptureSettings: TAdjustSettings;
    function CaptureAnsiSettings: TAnsiConvSettings;
    function CurrentScale: Double;
    function HasImage: Boolean;
    procedure ModsSliderMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure ModsSliderKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure AnsiSliderMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure AnsiSliderKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure RequestAdjustments;
    procedure StartAdjustThread(const AJobId: LongInt; const ASettings: TAdjustSettings);
    procedure AdjustThreadTerminated(Sender: TObject);
    procedure ApplyWorkerResult(const AJobId: LongInt; const AResult: TBitmap);
    procedure SetProcessing(const AValue: Boolean);
    procedure SetAnsiProcessing(const AValue: Boolean);
    procedure RequestAnsiPreview;
    procedure StartAnsiThread(const AJobId: LongInt; const ASettings: TAnsiConvSettings);
    procedure AnsiThreadTerminated(Sender: TObject);
    procedure ApplyAnsiResult(const AJobId: LongInt; const ACells: TBytes; const APreview: TBitmap;
      const ACols, ARows: Integer);
    procedure UpdateScrollPages;
    procedure RenderScaled(const AScale: Double);
    procedure UpdateStatus;
    procedure UpdateZoomLabel;
    procedure UpdateAnsiStatus(const ACols, ARows: Integer);
    procedure ResetSelection;
    function UserDataRootDir: string;
    function GetPresetsDir: string;
    function GetOutputDir: string;
    procedure EnsureAppDirs;
    procedure LoadAppIni;
    procedure SaveAppIni;
    procedure LoadSettingsFromIni(const Ini: TIniFile);
    procedure SaveSettingsToIni(const Ini: TIniFile);
    procedure ResetFactoryDefaults;
    procedure ShowPathsHelp;
    procedure BuildMainMenu;
  procedure MenuLoadSettingsClick(Sender: TObject);
  procedure MenuSaveSettingsClick(Sender: TObject);
  procedure MenuResetDefaultsClick(Sender: TObject);
  procedure MenuLearnTutorialClick(Sender: TObject);
  procedure MenuHelpPathsClick(Sender: TObject);
  procedure MenuHelpAboutClick(Sender: TObject);
  procedure MenuExitClick(Sender: TObject);
  function ClampSelRect(const R: TRect): TRect;
  function WorkingToDisplayRect(const R: TRect): TRect;
    function DisplayToWorkingPoint(const P: TPoint): TPoint;
    function HitTestSelection(const PDisp: TPoint; out HitHandle: TSelHandle): Boolean;
    procedure UpdateSelectionCursor(const PDisp: TPoint);
  public
    procedure LoadImage(const AFileName: string);
  end;

var
  MainForm: TMainForm;
  // Tutorial style learned knobs (initialized to defaults; can be updated from ANSI corpus)
  FTutShadeBasePenalty: Double = 55000.0;
  FTutShadeEdgeMult: Double = 1.60;
  FTutShadeFlatMult: Double = 0.70;
  FTutHalfEdgeMult: Double = 1.35;
  FTutHalfFlatMult: Double = 0.95;
  FTutOrientMult: Double = 1.50;
  FTutEdgeBiasFloor: Integer = 78;
  FTutStabilityFloor: Integer = 60;
  FTutLumBucketStrength: Integer = 14;
  FTutChromaPenalty: Integer = 22;
  FTutForceBg: Boolean = True;
  FTutForceBgColor: Integer = 0;

implementation

uses
  UnitAbout, UnitAnsiAdv;

{$R *.lfm}

type
  TAdjustWorkerThread = class(TThread)
  private
    FOwner: TMainForm;
    FJobId: LongInt;
    FSettings: TAdjustSettings;
    FSourceCopy: TBitmap;
    FResult: TBitmap;
    procedure SyncApply;
  protected
    procedure Execute; override;
  public
    constructor Create(AOwner: TMainForm; const AJobId: LongInt;
      const ASettings: TAdjustSettings; ASourceCopy: TBitmap);
    destructor Destroy; override;
    function CancelRequested: Boolean; inline;
  end;

  TAnsiWorkerThread = class(TThread)
  private
    FOwner: TMainForm;
    FJobId: LongInt;
    FSettings: TAnsiConvSettings;
    FSourceCopy: TBitmap;
    FPreview: TBitmap;
    FCells: TBytes;
    FCols: Integer;
    FRows: Integer;
    procedure SyncApply;
  protected
    procedure Execute; override;
  public
    constructor Create(AOwner: TMainForm; const AJobId: LongInt;
      const ASettings: TAnsiConvSettings; ASourceCopy: TBitmap);
    destructor Destroy; override;
    function CancelRequested: Boolean; inline;
  end;

  TRGB24 = packed record
    R, G, B: Byte;
  end;
  TRGB24Array = array of TRGB24;
  TDoubleArray = array of Double;

  TOctNode = class
  public
    IsLeaf: Boolean;
    Level: Integer;
    PixelCount: Integer;
    RedSum, GreenSum, BlueSum: Int64;
    Children: array[0..7] of TOctNode;
    NextReducible: TOctNode;
    constructor Create(ALevel: Integer; AIsLeaf: Boolean);
    destructor Destroy; override;
    function AvgColor: TRGB24;
  end;

const
  DOS16_PALETTE: array[0..15] of TRGB24 = (
    (R:0;   G:0;   B:0),     // 0 black
    (R:0;   G:0;   B:170),   // 1 blue
    (R:0;   G:170; B:0),     // 2 green
    (R:0;   G:170; B:170),   // 3 cyan
    (R:170; G:0;   B:0),     // 4 red
    (R:170; G:0;   B:170),   // 5 magenta
    (R:170; G:85;  B:0),     // 6 brown
    (R:170; G:170; B:170),   // 7 light gray
    (R:85;  G:85;  B:85),    // 8 dark gray
    (R:85;  G:85;  B:255),   // 9 light blue
    (R:85;  G:255; B:85),    // 10 light green
    (R:85;  G:255; B:255),   // 11 light cyan
    (R:255; G:85;  B:85),    // 12 light red
    (R:255; G:85;  B:255),   // 13 light magenta
    (R:255; G:255; B:85),    // 14 yellow
    (R:255; G:255; B:255)    // 15 white
  );

  // Block + shade glyph set for ANSI conversion (CP437):
  // space, light/medium/dark shade, full block, half blocks (up/down/left/right).
  AREZ_GLYPHS: array[0..8] of Byte = (32, 176, 177, 178, 219, 220, 223, 221, 222);

  // 4x4 Bayer ordered dithering matrix (0..15).
  BAYER4X4: array[0..3,0..3] of Integer = (
    (0, 8, 2,10),
    (12,4,14,6),
    (3,11,1,9),
    (15,7,13,5)
  );

procedure FitDialogButtonsRight(const Dlg: TForm; const MinBtnWidth: Integer);
const
  HMargin = 10;
  Spacing = 8;
  ExtraPad = 28;
var
  btns: array of TCustomButton;
  i, j, n: Integer;
  btn: TCustomButton;
  parent: TWinControl;
  need, total: Integer;
  xRight: Integer;
  tmp: TCustomButton;
begin
  if not Assigned(Dlg) then Exit;

  SetLength(btns, 0);
  for i := 0 to Dlg.ComponentCount - 1 do
    if Dlg.Components[i] is TCustomButton then
    begin
      SetLength(btns, Length(btns) + 1);
      btns[High(btns)] := TCustomButton(Dlg.Components[i]);
    end;

  n := Length(btns);
  if n = 0 then Exit;

  parent := btns[0].Parent;
  if not Assigned(parent) then Exit;

  // Sort by current Left (keeps existing button order).
  for i := 0 to n - 2 do
    for j := i + 1 to n - 1 do
      if btns[i].Left > btns[j].Left then
      begin
        tmp := btns[i];
        btns[i] := btns[j];
        btns[j] := tmp;
      end;

  // Resize buttons based on caption width.
  for i := 0 to n - 1 do
  begin
    btn := btns[i];
    need := Dlg.Canvas.TextWidth(btn.Caption) + ExtraPad;
    if need < MinBtnWidth then need := MinBtnWidth;
    if btn.Width < need then btn.Width := need;
  end;

  // Ensure the parent (and dialog) are wide enough for the buttons row.
  total := HMargin * 2 + Spacing * (n - 1);
  for i := 0 to n - 1 do
    Inc(total, btns[i].Width);

  if parent.ClientWidth < total then
  begin
    Dlg.ClientWidth := Dlg.ClientWidth + (total - parent.ClientWidth);
    Dlg.ReAlign;
  end;

  // Right-align buttons with consistent spacing.
  xRight := parent.ClientWidth - HMargin;
  for i := n - 1 downto 0 do
  begin
    btn := btns[i];
    btn.Left := xRight - btn.Width;
    xRight := btn.Left - Spacing;
  end;
end;

function BuildAdjustedBitmap(const Source: TBitmap; const Settings: TAdjustSettings;
  Dest: TBitmap; CancelThread: TAdjustWorkerThread): Boolean;
  function Cancelled: Boolean;
  begin
    Result := Assigned(CancelThread) and CancelThread.CancelRequested;
  end;

  function ClampByte(v: Integer): Byte;
  begin
    if v < 0 then v := 0 else if v > 255 then v := 255;
    Result := v;
  end;

  function ClampInt255(v: Integer): Integer; inline;
  begin
    if v < 0 then Exit(0);
    if v > 255 then Exit(255);
    Result := v;
  end;
var
  cancelledFlag: Boolean;
  rGain, gGain, bGain: Double;
  bright, contrast, gammaVal: Double;
  saturationPct: Integer;
  hueDeg: Integer;
  midContrast: Integer;
  blurRadius: Integer;
  sharpenAmt, clarityAmt, edgeAmt, edgeStyle, bilateralAmt: Integer;
  denoisePasses: Integer;
  chromaDenoiseAmt: Integer;
  guidedAmt: Integer;
  quantMethod, quantLevels: Integer;
  ditherStyle: Integer;
  iPass: Integer;
  yCopy: Integer;
  dosBiasPct: Integer;

  autoContrast: Boolean;
  

procedure AutoContrastStretch;
const
  // 1% / 99% percentile stretch tends to work well for ANSI without blowing out noise.
  CLIP_PCT = 1.0;
var
  Hist: array[0..255] of Integer;
  x, yy, yy2, i: Integer;
  total: Integer;
  lowTarget, highTarget: Integer;
  cum: Integer;
  lowY, highY: Integer;
  row: PByte;
  r, g, b: Integer;
  lum, lum2: Integer;
  scale: Double;
begin
  FillChar(Hist, SizeOf(Hist), 0);
  total := Dest.Width * Dest.Height;
  if total <= 0 then Exit;

  // Build luminance histogram.
  for yy := 0 to Dest.Height - 1 do
  begin
    if (yy and 15) = 0 then
      if Cancelled then begin cancelledFlag := True; Exit; end;
    row := PByte(Dest.ScanLine[yy]);
    for x := 0 to Dest.Width - 1 do
    begin
      b := row[x*3 + 0];
      g := row[x*3 + 1];
      r := row[x*3 + 2];
      lum := (54*r + 183*g + 19*b) shr 8;
      Inc(Hist[lum]);
    end;
  end;

  lowTarget := EnsureRange(Round(total * (CLIP_PCT / 100.0)), 0, total);
  highTarget := EnsureRange(Round(total * (1.0 - (CLIP_PCT / 100.0))), 0, total);
  if highTarget <= lowTarget then Exit;

  // Find lowY at CLIP_PCT percentile.
  cum := 0;
  lowY := 0;
  for i := 0 to 255 do
  begin
    Inc(cum, Hist[i]);
    if cum >= lowTarget then
    begin
      lowY := i;
      Break;
    end;
  end;

  // Find highY at (1-CLIP_PCT) percentile.
  cum := 0;
  highY := 255;
  for i := 0 to 255 do
  begin
    Inc(cum, Hist[i]);
    if cum >= highTarget then
    begin
      highY := i;
      Break;
    end;
  end;

  if (highY <= lowY) then Exit;

  // Apply remap in luminance space; preserve hue by scaling RGB by lum2/lum.
  for yy2 := 0 to Dest.Height - 1 do
  begin
    if (yy2 and 15) = 0 then
      if Cancelled then begin cancelledFlag := True; Exit; end;
    row := PByte(Dest.ScanLine[yy2]);
    for x := 0 to Dest.Width - 1 do
    begin
      b := row[x*3 + 0];
      g := row[x*3 + 1];
      r := row[x*3 + 2];
      lum := (54*r + 183*g + 19*b) shr 8;

      if lum <= lowY then
        lum2 := 0
      else if lum >= highY then
        lum2 := 255
      else
        lum2 := (lum - lowY) * 255 div (highY - lowY);

      if lum <= 0 then
        scale := 0.0
      else
        scale := lum2 / lum;

      row[x*3 + 2] := ClampByte(Round(r * scale));
      row[x*3 + 1] := ClampByte(Round(g * scale));
      row[x*3 + 0] := ClampByte(Round(b * scale));
    end;
  end;
end;

procedure ToneAdjust;
  var
    x, y, i: Integer;
    row: PByte;
    invGamma: Double;
    gammaLUT: array[0..255] of Byte;
    blackMaskLUT: array[0..255] of Word; // 0..256
    t: Double;
    lum: Integer;
    m: Integer;
    rBase, gBase, bBase: Integer;
    rFull, gFull, bFull: Integer;
    rScaled, gScaled, bScaled: Double;
    val: Integer;
  const
    // Protect near-black pixels from brightness/contrast/gamma so "true blacks" stay black.
    // This ramps the tone adjustment in by luminance (0..BLACK_PROTECT_END = partial, above = full).
    BLACK_PROTECT_END = 24.0;
  begin
    if gammaVal <= 0 then
      gammaVal := 1.0;
    invGamma := 1.0 / gammaVal;
    for i := 0 to 255 do
      gammaLUT[i] := ClampByte(Round(Power(i / 255.0, invGamma) * 255.0));

    // Precompute a smoothstep mask (0..256) by luminance.
    for i := 0 to 255 do
    begin
      t := i / BLACK_PROTECT_END;
      if t < 0 then t := 0 else if t > 1 then t := 1;
      // smoothstep
      t := t * t * (3.0 - 2.0 * t);
      blackMaskLUT[i] := EnsureRange(Round(t * 256.0), 0, 256);
    end;

    for y := 0 to Dest.Height - 1 do
    begin
      if Cancelled then begin cancelledFlag := True; Exit; end;
      row := Dest.ScanLine[y];
      for x := 0 to Dest.Width - 1 do
      begin
        // Use the same ordering as pf24bit scanlines (B, G, R).
        bScaled := row[x * 3 + 0] * bGain;
        gScaled := row[x * 3 + 1] * gGain;
        rScaled := row[x * 3 + 2] * rGain;

        // Base = RGB gain only (keeps black at 0 even if gains change).
        rBase := ClampByte(Round(rScaled));
        gBase := ClampByte(Round(gScaled));
        bBase := ClampByte(Round(bScaled));

        lum := (rBase * 54 + gBase * 183 + bBase * 19) shr 8; // 0..255 perceptual luma
        m := blackMaskLUT[lum]; // 0..256

        // Full tone adjustment: gain + brightness + contrast + gamma.
        val := ClampByte(Round(rScaled + bright));
        val := ClampByte(Round((val - 128) * contrast + 128));
        rFull := gammaLUT[val];

        val := ClampByte(Round(gScaled + bright));
        val := ClampByte(Round((val - 128) * contrast + 128));
        gFull := gammaLUT[val];

        val := ClampByte(Round(bScaled + bright));
        val := ClampByte(Round((val - 128) * contrast + 128));
        bFull := gammaLUT[val];

        // Blend tone adjustment in by luminance (protect blacks).
        row[x * 3 + 2] := ClampByte(rBase + ((rFull - rBase) * m) div 256);
        row[x * 3 + 1] := ClampByte(gBase + ((gFull - gBase) * m) div 256);
        row[x * 3 + 0] := ClampByte(bBase + ((bFull - bBase) * m) div 256);
      end;
    end;
  end;

  procedure SaturationAdjust;
  var
    x, y: Integer;
    row: PByte;
    r, g, b: Integer;
    gray: Integer;
    satNum: Integer; // 0..200
  begin
    satNum := EnsureRange(saturationPct, 0, 200);
    if satNum = 100 then Exit;

    for y := 0 to Dest.Height - 1 do
    begin
      if Cancelled then begin cancelledFlag := True; Exit; end;
      row := Dest.ScanLine[y];
      for x := 0 to Dest.Width - 1 do
      begin
        b := row[x * 3 + 0];
        g := row[x * 3 + 1];
        r := row[x * 3 + 2];
        gray := (r * 54 + g * 183 + b * 19) shr 8;

        r := gray + ((r - gray) * satNum) div 100;
        g := gray + ((g - gray) * satNum) div 100;
        b := gray + ((b - gray) * satNum) div 100;

        row[x * 3 + 2] := ClampByte(r);
        row[x * 3 + 1] := ClampByte(g);
        row[x * 3 + 0] := ClampByte(b);
      end;
    end;
  end;

  procedure BiasToDos16Palette;
  const
    Dos16: array[0..15] of TRGB24 = (
      (R:0;   G:0;   B:0),     // 0 black
      (R:0;   G:0;   B:170),   // 1 blue
      (R:0;   G:170; B:0),     // 2 green
      (R:0;   G:170; B:170),   // 3 cyan
      (R:170; G:0;   B:0),     // 4 red
      (R:170; G:0;   B:170),   // 5 magenta
      (R:170; G:85;  B:0),     // 6 brown
      (R:170; G:170; B:170),   // 7 light gray
      (R:85;  G:85;  B:85),    // 8 dark gray
      (R:85;  G:85;  B:255),   // 9 light blue
      (R:85;  G:255; B:85),    // 10 light green
      (R:85;  G:255; B:255),   // 11 light cyan
      (R:255; G:85;  B:85),    // 12 light red
      (R:255; G:85;  B:255),   // 13 light magenta
      (R:255; G:255; B:85),    // 14 yellow
      (R:255; G:255; B:255)    // 15 white
    );
  var
    bias: Integer;
    x, y, i: Integer;
    row: PByte;
    r, g, b: Integer;
    bestIdx: Integer;
    bestDist, dist: Integer;
    dr, dg, db: Integer;
    tr, tg, tb: Integer;
  begin
    bias := EnsureRange(dosBiasPct, 0, 100);
    if bias <= 0 then Exit;

    for y := 0 to Dest.Height - 1 do
    begin
      if Cancelled then begin cancelledFlag := True; Exit; end;
      row := Dest.ScanLine[y];
      for x := 0 to Dest.Width - 1 do
      begin
        r := row[x * 3 + 2];
        g := row[x * 3 + 1];
        b := row[x * 3 + 0];

        bestIdx := 0;
        bestDist := High(Integer);
        for i := 0 to 15 do
        begin
          dr := r - Dos16[i].R;
          dg := g - Dos16[i].G;
          db := b - Dos16[i].B;
          dist := dr*dr + dg*dg + db*db;
          if dist < bestDist then
          begin
            bestDist := dist;
            bestIdx := i;
            if dist = 0 then Break;
          end;
        end;

        tr := Dos16[bestIdx].R;
        tg := Dos16[bestIdx].G;
        tb := Dos16[bestIdx].B;

        r := r + ((tr - r) * bias) div 100;
        g := g + ((tg - g) * bias) div 100;
        b := b + ((tb - b) * bias) div 100;

        row[x * 3 + 2] := ClampByte(r);
        row[x * 3 + 1] := ClampByte(g);
        row[x * 3 + 0] := ClampByte(b);
      end;
    end;
  end;

  procedure HueAdjust;
  var
    x, y: Integer;
    row: PByte;
    r, g, b: Integer;
    rf, gf, bf: Double;
    maxc, minc, delta: Double;
    h, s, v: Double;
    hh: Double;
    i: Integer;
    f, p, q, t: Double;
  begin
    if hueDeg = 0 then Exit;

    for y := 0 to Dest.Height - 1 do
    begin
      if Cancelled then begin cancelledFlag := True; Exit; end;
      row := Dest.ScanLine[y];
      for x := 0 to Dest.Width - 1 do
      begin
        b := row[x * 3 + 0];
        g := row[x * 3 + 1];
        r := row[x * 3 + 2];

        rf := r / 255.0;
        gf := g / 255.0;
        bf := b / 255.0;

        maxc := rf; if gf > maxc then maxc := gf; if bf > maxc then maxc := bf;
        minc := rf; if gf < minc then minc := gf; if bf < minc then minc := bf;
        delta := maxc - minc;

        v := maxc;
        if (maxc <= 0.0) or (delta <= 1e-9) then
        begin
          // grayscale or black: hue is undefined; nothing to do
          Continue;
        end;

        s := delta / maxc;

        if rf = maxc then
          h := 60.0 * ((gf - bf) / delta)
        else if gf = maxc then
          h := 60.0 * (((bf - rf) / delta) + 2.0)
        else
          h := 60.0 * (((rf - gf) / delta) + 4.0);

        h := h + hueDeg;
        while h < 0.0 do h := h + 360.0;
        while h >= 360.0 do h := h - 360.0;

        hh := h / 60.0;
        i := Trunc(hh);
        f := hh - i;
        p := v * (1.0 - s);
        q := v * (1.0 - s * f);
        t := v * (1.0 - s * (1.0 - f));

        case (i mod 6) of
          0: begin rf := v; gf := t; bf := p; end;
          1: begin rf := q; gf := v; bf := p; end;
          2: begin rf := p; gf := v; bf := t; end;
          3: begin rf := p; gf := q; bf := v; end;
          4: begin rf := t; gf := p; bf := v; end;
        else
          begin rf := v; gf := p; bf := q; end;
        end;

        row[x * 3 + 2] := ClampByte(Round(rf * 255.0));
        row[x * 3 + 1] := ClampByte(Round(gf * 255.0));
        row[x * 3 + 0] := ClampByte(Round(bf * 255.0));
      end;
    end;
  end;

  procedure MidtoneContrastAdjust;
  var
    x, y: Integer;
    row: PByte;
    r, g, b: Integer;
    lum, newLum, delta: Integer;
    a: Double; // -1..1
    xn, tn, yn: Double;
  begin
    if midContrast = 0 then Exit;
    a := EnsureRange(midContrast, -100, 100) / 100.0;

    for y := 0 to Dest.Height - 1 do
    begin
      if Cancelled then begin cancelledFlag := True; Exit; end;
      row := Dest.ScanLine[y];
      for x := 0 to Dest.Width - 1 do
      begin
        b := row[x * 3 + 0];
        g := row[x * 3 + 1];
        r := row[x * 3 + 2];

        lum := (r * 54 + g * 183 + b * 19) shr 8;
        xn := lum / 255.0;
        tn := 1.0 - Abs(2.0 * xn - 1.0); // peak at midtones, 0 at extremes
        yn := xn + a * (xn - 0.5) * tn;
        if yn < 0.0 then yn := 0.0 else if yn > 1.0 then yn := 1.0;
        newLum := Round(yn * 255.0);

        delta := newLum - lum;
        row[x * 3 + 2] := ClampInt255(r + delta);
        row[x * 3 + 1] := ClampInt255(g + delta);
        row[x * 3 + 0] := ClampInt255(b + delta);
      end;
    end;
  end;

  procedure ChromaOnlyDenoise;
  var
    amt, radius: Integer;
    w, h, n: Integer;
    x, y: Integer;
    row: PByte;
    r, g, b: Integer;
    yLum: Integer;
    idx: Integer;
    cb, cr: Integer;
    cb0, cr0: Integer;
    cbArr, crArr: array of Integer;
    cbBlur, crBlur: array of Integer;
    cbOff, crOff: Integer;
    rr, gg, bb: Integer;

    function Clamp0_255(v: Integer): Integer; inline;
    begin
      if v < 0 then Exit(0);
      if v > 255 then Exit(255);
      Result := v;
    end;

    procedure BoxBlurInt(const src: array of Integer; w, h, radius: Integer; var dst: array of Integer);
    var
      win, area: Integer;
      tmp: array of Integer;
      ext: array of Integer;
      sum: Int64;
      x, y, i: Integer;
      base: Integer;
    begin
      if (w <= 0) or (h <= 0) then Exit;
      if radius <= 0 then
      begin
        for i := 0 to w * h - 1 do
          dst[i] := src[i];
        Exit;
      end;

      win := radius * 2 + 1;
      area := win * win;

      SetLength(tmp, w * h);

      // horizontal sums (replicate edge)
      SetLength(ext, w + radius * 2);
      for y := 0 to h - 1 do
      begin
        if Cancelled then begin cancelledFlag := True; Exit; end;
        base := y * w;
        for i := 0 to radius - 1 do
          ext[i] := src[base + 0];
        for x := 0 to w - 1 do
          ext[radius + x] := src[base + x];
        for i := 0 to radius - 1 do
          ext[radius + w + i] := src[base + (w - 1)];

        sum := 0;
        for i := 0 to win - 1 do
          Inc(sum, ext[i]);

        for x := 0 to w - 1 do
        begin
          tmp[base + x] := Integer(sum);
          if x < w - 1 then
            sum := sum + ext[x + win] - ext[x];
        end;
      end;

      // vertical sums + normalize to mean
      SetLength(ext, h + radius * 2);
      for x := 0 to w - 1 do
      begin
        if Cancelled then begin cancelledFlag := True; Exit; end;
        for i := 0 to radius - 1 do
          ext[i] := tmp[0 * w + x];
        for y := 0 to h - 1 do
          ext[radius + y] := tmp[y * w + x];
        for i := 0 to radius - 1 do
          ext[radius + h + i] := tmp[(h - 1) * w + x];

        sum := 0;
        for i := 0 to win - 1 do
          Inc(sum, ext[i]);

        for y := 0 to h - 1 do
        begin
          dst[y * w + x] := Integer((sum + (area div 2)) div area);
          if y < h - 1 then
            sum := sum + ext[y + win] - ext[y];
        end;
      end;
    end;

  begin
    amt := EnsureRange(chromaDenoiseAmt, 0, 100);
    if amt <= 0 then Exit;

    w := Dest.Width;
    h := Dest.Height;
    if (w <= 0) or (h <= 0) then Exit;
    n := w * h;
    if n <= 0 then Exit;

    radius := 1 + (amt div 34); // 1..3

    SetLength(cbArr, n);
    SetLength(crArr, n);

    idx := 0;
    for y := 0 to h - 1 do
    begin
      if Cancelled then begin cancelledFlag := True; Exit; end;
      row := Dest.ScanLine[y];
      for x := 0 to w - 1 do
      begin
        b := row[x * 3 + 0];
        g := row[x * 3 + 1];
        r := row[x * 3 + 2];

        // YCbCr-ish chroma (scaled to 0..255); keep luma untouched.
        cb := 128 + ((-43 * r - 85 * g + 128 * b) shr 8);
        cr := 128 + ((128 * r - 107 * g - 21 * b) shr 8);
        cbArr[idx] := Clamp0_255(cb);
        crArr[idx] := Clamp0_255(cr);
        Inc(idx);
      end;
    end;

    SetLength(cbBlur, n);
    SetLength(crBlur, n);
    BoxBlurInt(cbArr, w, h, radius, cbBlur);
    if cancelledFlag then Exit;
    BoxBlurInt(crArr, w, h, radius, crBlur);
    if cancelledFlag then Exit;

    idx := 0;
    for y := 0 to h - 1 do
    begin
      if Cancelled then begin cancelledFlag := True; Exit; end;
      row := Dest.ScanLine[y];
      for x := 0 to w - 1 do
      begin
        b := row[x * 3 + 0];
        g := row[x * 3 + 1];
        r := row[x * 3 + 2];
        yLum := (r * 54 + g * 183 + b * 19) shr 8;

        cb0 := cbArr[idx];
        cr0 := crArr[idx];
        cb := cb0 + ((cbBlur[idx] - cb0) * amt) div 100;
        cr := cr0 + ((crBlur[idx] - cr0) * amt) div 100;

        cbOff := cb - 128;
        crOff := cr - 128;

        rr := yLum + ((359 * crOff) shr 8);
        gg := yLum - ((88 * cbOff + 183 * crOff) shr 8);
        bb := yLum + ((454 * cbOff) shr 8);

        row[x * 3 + 2] := ClampByte(rr);
        row[x * 3 + 1] := ClampByte(gg);
        row[x * 3 + 0] := ClampByte(bb);

        Inc(idx);
      end;
    end;
  end;

  procedure GuidedFilterLuma;
  var
    amt: Integer;
    w, h, n: Integer;
    r: Integer;
    eps: Single;
    win: Integer;
    invArea: Single;
    I: array of Single;
    buf1: array of Single;
    buf2: array of Single;
    tmp: array of Single;
    extRow: array of Single;
    extCol: array of Single;

    procedure BoxMean(const src: array of Single; var dst: array of Single);
    var
      x, y, i: Integer;
      base: Integer;
      sum: Single;
    begin
      if (w <= 0) or (h <= 0) then Exit;
      if r <= 0 then
      begin
        for i := 0 to n - 1 do
          dst[i] := src[i];
        Exit;
      end;

      SetLength(tmp, n);

      // horizontal sums (replicate edge)
      SetLength(extRow, w + r * 2);
      for y := 0 to h - 1 do
      begin
        if Cancelled then begin cancelledFlag := True; Exit; end;
        base := y * w;
        for i := 0 to r - 1 do
          extRow[i] := src[base + 0];
        for x := 0 to w - 1 do
          extRow[r + x] := src[base + x];
        for i := 0 to r - 1 do
          extRow[r + w + i] := src[base + (w - 1)];

        sum := 0;
        for i := 0 to win - 1 do
          sum := sum + extRow[i];

        for x := 0 to w - 1 do
        begin
          tmp[base + x] := sum;
          if x < w - 1 then
            sum := sum + extRow[x + win] - extRow[x];
        end;
      end;

      // vertical sums + normalize to mean
      SetLength(extCol, h + r * 2);
      for x := 0 to w - 1 do
      begin
        if Cancelled then begin cancelledFlag := True; Exit; end;
        for i := 0 to r - 1 do
          extCol[i] := tmp[0 * w + x];
        for y := 0 to h - 1 do
          extCol[r + y] := tmp[y * w + x];
        for i := 0 to r - 1 do
          extCol[r + h + i] := tmp[(h - 1) * w + x];

        sum := 0;
        for i := 0 to win - 1 do
          sum := sum + extCol[i];

        for y := 0 to h - 1 do
        begin
          dst[y * w + x] := sum * invArea;
          if y < h - 1 then
            sum := sum + extCol[y + win] - extCol[y];
        end;
      end;
    end;

  var
    x, y: Integer;
    row: PByte;
    rr, gg, bb: Integer;
    lum: Integer;
    idx: Integer;
    Ival, aVal, bVal, qVal, outLum: Single;
    newLum: Integer;
    delta: Integer;
    fAmt: Single;
  begin
    amt := EnsureRange(guidedAmt, 0, 100);
    if amt <= 0 then Exit;

    w := Dest.Width;
    h := Dest.Height;
    if (w <= 0) or (h <= 0) then Exit;
    n := w * h;
    if n <= 0 then Exit;

    // Map "amount" to a practical radius; final strength is still blended by amt.
    r := 2 + (amt div 25); // 2..6
    win := r * 2 + 1;
    invArea := 1.0 / (win * win);
    eps := 0.0009; // (0.03)^2 in 0..1 space

    SetLength(I, n);
    SetLength(buf1, n);
    SetLength(buf2, n);

    // I (luma) and I^2
    idx := 0;
    for y := 0 to h - 1 do
    begin
      if Cancelled then begin cancelledFlag := True; Exit; end;
      row := Dest.ScanLine[y];
      for x := 0 to w - 1 do
      begin
        bb := row[x * 3 + 0];
        gg := row[x * 3 + 1];
        rr := row[x * 3 + 2];
        lum := (rr * 54 + gg * 183 + bb * 19) shr 8;
        Ival := lum / 255.0;
        I[idx] := Ival;
        buf2[idx] := Ival * Ival;
        Inc(idx);
      end;
    end;

    // mean(I) -> buf1
    BoxMean(I, buf1);
    if cancelledFlag then Exit;

    // mean(I^2) -> buf2
    BoxMean(buf2, buf2);
    if cancelledFlag then Exit;

    // a = var/(var+eps)  and  b = mean(I) * (1 - a)
    for idx := 0 to n - 1 do
    begin
      qVal := buf2[idx] - (buf1[idx] * buf1[idx]); // var
      if qVal < 0 then qVal := 0;
      aVal := qVal / (qVal + eps);
      buf2[idx] := aVal;
      buf1[idx] := buf1[idx] * (1.0 - aVal);
    end;

    // mean(a) -> buf2
    BoxMean(buf2, buf2);
    if cancelledFlag then Exit;

    // mean(b) -> buf1
    BoxMean(buf1, buf1);
    if cancelledFlag then Exit;

    fAmt := amt / 100.0;

    // Apply: q = mean(a)*I + mean(b); blend by amt; then apply as a luma delta to RGB.
    idx := 0;
    for y := 0 to h - 1 do
    begin
      if Cancelled then begin cancelledFlag := True; Exit; end;
      row := Dest.ScanLine[y];
      for x := 0 to w - 1 do
      begin
        bb := row[x * 3 + 0];
        gg := row[x * 3 + 1];
        rr := row[x * 3 + 2];
        lum := (rr * 54 + gg * 183 + bb * 19) shr 8;

        Ival := I[idx];
        bVal := buf1[idx];
        aVal := buf2[idx];
        qVal := aVal * Ival + bVal;
        outLum := Ival + (qVal - Ival) * fAmt;
        if outLum < 0 then outLum := 0 else if outLum > 1 then outLum := 1;

        newLum := Round(outLum * 255.0);
        delta := newLum - lum;

        row[x * 3 + 2] := ClampInt255(rr + delta);
        row[x * 3 + 1] := ClampInt255(gg + delta);
        row[x * 3 + 0] := ClampInt255(bb + delta);

        Inc(idx);
      end;
    end;
  end;

  procedure BoxBlur(radius: Integer);
  var
    x, y: Integer;
    temp: TBitmap;
    k, sumB, sumG, sumR, count: Integer;
    py: Integer;
    srcRow, dstRow: PByte;
    xx: Integer;
  begin
    if radius <= 0 then Exit;
    temp := TBitmap.Create;
    try
      temp.Assign(Dest);
      temp.PixelFormat := pf24bit;
      temp.HandleType := bmDIB;
      // horizontal
      for y := 0 to Dest.Height - 1 do
      begin
        if Cancelled then begin cancelledFlag := True; Exit; end;
        dstRow := Dest.ScanLine[y];
        srcRow := temp.ScanLine[y];
        for x := 0 to Dest.Width - 1 do
        begin
          sumB := 0; sumG := 0; sumR := 0; count := 0;
          for k := -radius to radius do
          begin
            xx := EnsureRange(x + k, 0, Dest.Width - 1);
            Inc(sumB, srcRow[xx * 3 + 0]);
            Inc(sumG, srcRow[xx * 3 + 1]);
            Inc(sumR, srcRow[xx * 3 + 2]);
            Inc(count);
          end;
          dstRow[x * 3 + 0] := sumB div count;
          dstRow[x * 3 + 1] := sumG div count;
          dstRow[x * 3 + 2] := sumR div count;
        end;
      end;
      // vertical
      temp.Assign(Dest);
      for y := 0 to Dest.Height - 1 do
      begin
        if Cancelled then begin cancelledFlag := True; Exit; end;
        dstRow := Dest.ScanLine[y];
        for x := 0 to Dest.Width - 1 do
        begin
          sumB := 0; sumG := 0; sumR := 0; count := 0;
          for k := -radius to radius do
          begin
            py := EnsureRange(y + k, 0, Dest.Height - 1);
            srcRow := temp.ScanLine[py];
            Inc(sumB, srcRow[x * 3 + 0]);
            Inc(sumG, srcRow[x * 3 + 1]);
            Inc(sumR, srcRow[x * 3 + 2]);
            Inc(count);
          end;
          dstRow[x * 3 + 0] := sumB div count;
          dstRow[x * 3 + 1] := sumG div count;
          dstRow[x * 3 + 2] := sumR div count;
        end;
      end;
    finally
      temp.Free;
    end;
  end;

  procedure Median3x3;
  var
    x, y, c: Integer;
    temp: TBitmap;
    arr: array[0..8] of Byte;
    idx, swapTmp: Integer;
    srcRow: PByte;
    dstRow: PByte;
    ny, nx: Integer;
    py, px: Integer;
  begin
    temp := TBitmap.Create;
    try
      temp.Assign(Dest);
      temp.PixelFormat := pf24bit;
      temp.HandleType := bmDIB;
      for y := 0 to Dest.Height - 1 do
      begin
        if Cancelled then begin cancelledFlag := True; Exit; end;
        dstRow := Dest.ScanLine[y];
        for x := 0 to Dest.Width - 1 do
        begin
          for c := 0 to 2 do
          begin
            idx := 0;
            for ny := -1 to 1 do
            begin
              py := EnsureRange(y + ny, 0, Dest.Height - 1);
              srcRow := temp.ScanLine[py];
              for nx := -1 to 1 do
              begin
                px := EnsureRange(x + nx, 0, Dest.Width - 1);
                arr[idx] := srcRow[px * 3 + c];
                Inc(idx);
              end;
            end;
            // simple insertion sort for 9 elements
            for idx := 1 to 8 do
            begin
              swapTmp := idx;
              while (swapTmp > 0) and (arr[swapTmp] < arr[swapTmp-1]) do
              begin
                py := arr[swapTmp-1];
                arr[swapTmp-1] := arr[swapTmp];
                arr[swapTmp] := py;
                Dec(swapTmp);
              end;
            end;
            dstRow[x * 3 + c] := arr[4];
          end;
        end;
      end;
    finally
      temp.Free;
    end;
  end;

  procedure Unsharp(amountPercent: Integer; radius: Integer);
  var
    x, y: Integer;
    blur, orig: TBitmap;
    blurRow, dstRow: PByte;
    amt: Double;
    c: Integer;
  begin
    if amountPercent <= 0 then Exit;
    blur := TBitmap.Create;
    orig := TBitmap.Create;
    try
      orig.Assign(Dest);
      orig.PixelFormat := pf24bit;
      orig.HandleType := bmDIB;
      blur.Assign(Dest);
      blur.PixelFormat := pf24bit;
      blur.HandleType := bmDIB;
      if radius < 1 then radius := 1;
      // blur -> Dest then copy back to blur
      BoxBlur(radius);
      if cancelledFlag then Exit;
      blur.Assign(Dest);
      Dest.Assign(orig);
      amt := amountPercent / 100.0;
      for y := 0 to Dest.Height - 1 do
      begin
        if Cancelled then begin cancelledFlag := True; Exit; end;
        dstRow := Dest.ScanLine[y];
        blurRow := blur.ScanLine[y];
        for x := 0 to Dest.Width - 1 do
        begin
          for c := 0 to 2 do
            dstRow[x * 3 + c] := ClampByte(
              Round(dstRow[x * 3 + c] + amt * (dstRow[x * 3 + c] - blurRow[x * 3 + c]))
            );
        end;
      end;
    finally
      blur.Free;
      orig.Free;
    end;
  end;

  procedure EdgeProcess(style: Integer; strength: Integer);
  var
    x, y: Integer;
    W, H: Integer;
    temp: TBitmap;
    gx, gy, lap, mag: Integer;
    srcRow, srcRowUp, srcRowDown, dstRow: PByte;
    c: Integer;
    v: Integer;
    lumUL, lumUM, lumUR: Integer;
    lumML, lumMM, lumMR: Integer;
    lumDL, lumDM, lumDR: Integer;

    // grayscale working buffers for more advanced edge styles
    gray, blurLum, blurA, blurB, blurC, dog, sm, magArr, nms: array of Integer;
    edge8: array of Byte;
    maxEdge: Integer;
    hp, delta: Integer;
    wgt: Double;
    dirArr, state: array of Byte;
    stack: array of Integer;
    stackTop: Integer;
    idx, nx, ny, nIdx: Integer;
    absGx, absGy: Integer;
    m1, m2: Integer;
    maxNms: Integer;
    highThr, lowThr: Integer;
    maxVal: Integer;
    i: Integer;
    phi, eps, dogNorm, xdog: Double;
    factorHigh: Double;

    // wavelet buffers
    energy, cur, nxt: array of Integer;
    curW, curH, nextW, nextH: Integer;
    blockSize, level, maxLevels: Integer;
    bx, by, x2, y2: Integer;
    p00, p01, p10, p11: Integer;
    hdet, vdet, ddet, e: Integer;
    ox, oy, origX, origY, bs: Integer;

    function LumaAtRow(const row: PByte; const ax: Integer): Integer; inline;
    var
      b, g, r: Integer;
    begin
      b := row[ax * 3 + 0];
      g := row[ax * 3 + 1];
      r := row[ax * 3 + 2];
      // Rec.601-ish luma (matches old rez2ans behavior better for edge finding).
      Result := (r * 77 + g * 150 + b * 29) shr 8;
    end;

    procedure BoxBlurGray(const Src: array of Integer; var Dst: array of Integer;
      const BW, BH, Radius: Integer);
    var
      tmp: array of Integer;
      ix, iy, k: Integer;
      sum: Integer;
      count: Integer;
      left, right, top, bottom: Integer;
      xcl, ycl: Integer;
    begin
      if (BW <= 0) or (BH <= 0) then Exit;
      if Length(Dst) < BW * BH then Exit;
      if Radius <= 0 then
      begin
        for k := 0 to BW * BH - 1 do
          Dst[k] := Src[k];
        Exit;
      end;

      SetLength(tmp, BW * BH);
      count := Radius * 2 + 1;

      // horizontal
      for iy := 0 to BH - 1 do
      begin
        if Cancelled then begin cancelledFlag := True; Exit; end;
        sum := 0;
        for k := -Radius to Radius do
        begin
          xcl := EnsureRange(k, 0, BW - 1);
          Inc(sum, Src[iy * BW + xcl]);
        end;
        for ix := 0 to BW - 1 do
        begin
          tmp[iy * BW + ix] := sum div count;
          left := ix - Radius;
          right := ix + Radius + 1;
          Dec(sum, Src[iy * BW + EnsureRange(left, 0, BW - 1)]);
          Inc(sum, Src[iy * BW + EnsureRange(right, 0, BW - 1)]);
        end;
      end;

      // vertical
      for ix := 0 to BW - 1 do
      begin
        if Cancelled then begin cancelledFlag := True; Exit; end;
        sum := 0;
        for k := -Radius to Radius do
        begin
          ycl := EnsureRange(k, 0, BH - 1);
          Inc(sum, tmp[ycl * BW + ix]);
        end;
        for iy := 0 to BH - 1 do
        begin
          Dst[iy * BW + ix] := sum div count;
          top := iy - Radius;
          bottom := iy + Radius + 1;
          Dec(sum, tmp[EnsureRange(top, 0, BH - 1) * BW + ix]);
          Inc(sum, tmp[EnsureRange(bottom, 0, BH - 1) * BW + ix]);
        end;
      end;
    end;
  begin
    if (style <= 0) or (strength <= 0) then Exit;
    if (Dest.Width < 3) or (Dest.Height < 3) then Exit;
    W := Dest.Width;
    H := Dest.Height;

    temp := TBitmap.Create;
    try
      temp.Assign(Dest);
      temp.PixelFormat := pf24bit;
      temp.HandleType := bmDIB;

      if style = 1 then
      begin
        // Old rez2ans-style Sobel edge map baked into the image by *darkening* edges.
        // This tends to preserve shapes for ANSI conversion better than bright halos.
        for y := 1 to H - 2 do
        begin
          if Cancelled then begin cancelledFlag := True; Exit; end;
          dstRow := Dest.ScanLine[y];
          srcRow := temp.ScanLine[y];
          srcRowUp := temp.ScanLine[y - 1];
          srcRowDown := temp.ScanLine[y + 1];

          for x := 1 to W - 2 do
          begin
            lumUL := LumaAtRow(srcRowUp, x - 1);
            lumUM := LumaAtRow(srcRowUp, x);
            lumUR := LumaAtRow(srcRowUp, x + 1);
            lumML := LumaAtRow(srcRow, x - 1);
            lumMR := LumaAtRow(srcRow, x + 1);
            lumDL := LumaAtRow(srcRowDown, x - 1);
            lumDM := LumaAtRow(srcRowDown, x);
            lumDR := LumaAtRow(srcRowDown, x + 1);

            gx := (-lumUL + lumUR) + (-2 * lumML + 2 * lumMR) + (-lumDL + lumDR);
            gy := (-lumUL - 2 * lumUM - lumUR) + (lumDL + 2 * lumDM + lumDR);

            mag := (Abs(gx) + Abs(gy)) div 4;
            if mag > 255 then mag := 255;
            if mag < 4 then mag := 0; // small noise gate

            delta := (mag * strength) div 100;
            if delta <> 0 then
            begin
              dstRow[x * 3 + 0] := ClampByte(srcRow[x * 3 + 0] - delta);
              dstRow[x * 3 + 1] := ClampByte(srcRow[x * 3 + 1] - delta);
              dstRow[x * 3 + 2] := ClampByte(srcRow[x * 3 + 2] - delta);
            end
            else
            begin
              dstRow[x * 3 + 0] := srcRow[x * 3 + 0];
              dstRow[x * 3 + 1] := srcRow[x * 3 + 1];
              dstRow[x * 3 + 2] := srcRow[x * 3 + 2];
            end;
          end;
        end;
      end
      else
      begin
        // Advanced styles: operate on a grayscale buffer.
        SetLength(gray, W * H);
        for y := 0 to H - 1 do
        begin
          if Cancelled then begin cancelledFlag := True; Exit; end;
          srcRow := temp.ScanLine[y];
          for x := 0 to W - 1 do
          gray[y * W + x] := (srcRow[x * 3 + 2] * 77 + srcRow[x * 3 + 1] * 150 + srcRow[x * 3 + 0] * 29) shr 8;
        end;

        SetLength(edge8, W * H);
        FillChar(edge8[0], Length(edge8) * SizeOf(edge8[0]), 0);
        maxEdge := 0;

        case style of
          2: // Sobel Detect (edge mask for enhancement)
            begin
              for y := 1 to H - 2 do
              begin
                if Cancelled then begin cancelledFlag := True; Exit; end;
                for x := 1 to W - 2 do
                begin
                  idx := y * W + x;
                  lumUL := gray[idx - W - 1];
                  lumUM := gray[idx - W];
                  lumUR := gray[idx - W + 1];
                  lumML := gray[idx - 1];
                  lumMR := gray[idx + 1];
                  lumDL := gray[idx + W - 1];
                  lumDM := gray[idx + W];
                  lumDR := gray[idx + W + 1];

                  gx := (lumUR + 2*lumMR + lumDR) - (lumUL + 2*lumML + lumDL);
                  gy := (lumDL + 2*lumDM + lumDR) - (lumUL + 2*lumUM + lumUR);
                  mag := (Abs(gx) + Abs(gy)) div 4;
                  if mag > 255 then mag := 255;
                  if mag < 4 then mag := 0;
                  edge8[idx] := Byte(mag);
                  if mag > maxEdge then maxEdge := mag;
                end;
              end;
            end;

          3: // Laplacian Detect (edge mask for enhancement)
            begin
              for y := 1 to H - 2 do
              begin
                if Cancelled then begin cancelledFlag := True; Exit; end;
                for x := 1 to W - 2 do
                begin
                  idx := y * W + x;
                  lap :=
                    (gray[idx - W - 1] + gray[idx - W] + gray[idx - W + 1] +
                     gray[idx - 1]                 + gray[idx + 1] +
                     gray[idx + W - 1] + gray[idx + W] + gray[idx + W + 1]) -
                    8 * gray[idx];
                  mag := Abs(lap) div 8;
                  if mag > 255 then mag := 255;
                  if mag < 4 then mag := 0;
                  edge8[idx] := Byte(mag);
                  if mag > maxEdge then maxEdge := mag;
                end;
              end;
            end;

          4: // Canny Detect
            begin
              SetLength(sm, W * H);
              BoxBlurGray(gray, sm, W, H, 1);
              if cancelledFlag then Exit;

              SetLength(magArr, W * H);
              SetLength(dirArr, W * H);
              FillChar(magArr[0], Length(magArr) * SizeOf(magArr[0]), 0);
              FillChar(dirArr[0], Length(dirArr) * SizeOf(dirArr[0]), 0);

              for y := 1 to H - 2 do
              begin
                if Cancelled then begin cancelledFlag := True; Exit; end;
                for x := 1 to W - 2 do
                begin
                  idx := y * W + x;
                  lumUL := sm[(y-1) * W + (x-1)];
                  lumUM := sm[(y-1) * W + (x  )];
                  lumUR := sm[(y-1) * W + (x+1)];
                  lumML := sm[(y  ) * W + (x-1)];
                  lumMR := sm[(y  ) * W + (x+1)];
                  lumDL := sm[(y+1) * W + (x-1)];
                  lumDM := sm[(y+1) * W + (x  )];
                  lumDR := sm[(y+1) * W + (x+1)];

                  gx := (lumUR + 2*lumMR + lumDR) - (lumUL + 2*lumML + lumDL);
                  gy := (lumDL + 2*lumDM + lumDR) - (lumUL + 2*lumUM + lumUR);
                  mag := Abs(gx) + Abs(gy);
                  magArr[idx] := mag;

                  absGx := Abs(gx);
                  absGy := Abs(gy);
                  // 0,45,90,135 degree buckets using integer ratio thresholds (~tan 22.5 = 0.414)
                  if (absGx * 41) > (absGy * 100) then
                    dirArr[idx] := 0
                  else if (absGy * 41) > (absGx * 100) then
                    dirArr[idx] := 2
                  else if ((gx xor gy) >= 0) then
                    dirArr[idx] := 1
                  else
                    dirArr[idx] := 3;
                end;
              end;

              SetLength(nms, W * H);
              FillChar(nms[0], Length(nms) * SizeOf(nms[0]), 0);
              maxNms := 0;
              for y := 1 to H - 2 do
              begin
                if Cancelled then begin cancelledFlag := True; Exit; end;
                for x := 1 to W - 2 do
                begin
                  idx := y * W + x;
                  mag := magArr[idx];
                  case dirArr[idx] of
                    0: begin m1 := magArr[idx - 1];     m2 := magArr[idx + 1];     end;
                    1: begin m1 := magArr[idx - W + 1]; m2 := magArr[idx + W - 1]; end;
                    2: begin m1 := magArr[idx - W];     m2 := magArr[idx + W];     end;
                  else
                         begin m1 := magArr[idx - W - 1]; m2 := magArr[idx + W + 1]; end;
                  end;
                  if (mag >= m1) and (mag >= m2) then
                    nms[idx] := mag
                  else
                    nms[idx] := 0;
                  if nms[idx] > maxNms then
                    maxNms := nms[idx];
                end;
              end;

              if maxNms <= 0 then Exit;

              // Keep thresholds stable; "strength" controls enhancement amount later.
              factorHigh := 0.25;
              highThr := Max(1, Round(maxNms * factorHigh));
              lowThr := Max(1, Round(highThr * 0.40));

              SetLength(state, W * H);
              FillChar(state[0], Length(state) * SizeOf(state[0]), 0);
              SetLength(stack, W * H);
              stackTop := 0;

              for idx := 0 to W * H - 1 do
              begin
                if nms[idx] >= highThr then
                begin
                  state[idx] := 2;
                  stack[stackTop] := idx;
                  Inc(stackTop);
                end
                else if nms[idx] >= lowThr then
                  state[idx] := 1;
              end;

              while stackTop > 0 do
              begin
                if Cancelled then begin cancelledFlag := True; Exit; end;
                Dec(stackTop);
                idx := stack[stackTop];
                x := idx mod W;
                y := idx div W;
                for ny := Max(0, y - 1) to Min(H - 1, y + 1) do
                  for nx := Max(0, x - 1) to Min(W - 1, x + 1) do
                  begin
                    nIdx := ny * W + nx;
                    if state[nIdx] = 1 then
                    begin
                      state[nIdx] := 2;
                      stack[stackTop] := nIdx;
                      Inc(stackTop);
                    end;
                  end;
              end;

              // edge mask (0..255) for enhancement pass
              for idx := 0 to W * H - 1 do
              begin
                if state[idx] = 2 then
                  v := ClampByte(Round(nms[idx] * 255.0 / maxNms))
                else
                  v := 0;
                edge8[idx] := v;
                if v > maxEdge then maxEdge := v;
              end;
            end;

          5: // DoG Detect
            begin
              SetLength(blurA, W * H);
              SetLength(blurB, W * H);
              SetLength(dog, W * H);
              BoxBlurGray(gray, blurA, W, H, 1);
              if cancelledFlag then Exit;
              BoxBlurGray(gray, blurB, W, H, 2);
              if cancelledFlag then Exit;

              for i := 0 to W * H - 1 do
              begin
                v := Abs(blurA[i] - blurB[i]);
                dog[i] := v;
              end;

              for i := 0 to W * H - 1 do
              begin
                if Cancelled then begin cancelledFlag := True; Exit; end;
                mag := dog[i];
                if mag > 255 then mag := 255;
                if mag < 4 then mag := 0;
                edge8[i] := Byte(mag);
                if mag > maxEdge then maxEdge := mag;
              end;
            end;

          6: // HED (Multi-scale) - approximation via summed Sobel at multiple blur radii
            begin
              SetLength(blurA, W * H);
              SetLength(blurB, W * H);
              SetLength(blurC, W * H);
              SetLength(dog, W * H); // reuse as edge-sum buffer

              BoxBlurGray(gray, blurA, W, H, 1);
              if cancelledFlag then Exit;
              BoxBlurGray(gray, blurB, W, H, 2);
              if cancelledFlag then Exit;
              BoxBlurGray(gray, blurC, W, H, 3);
              if cancelledFlag then Exit;

              FillChar(dog[0], Length(dog) * SizeOf(dog[0]), 0);
              for y := 1 to H - 2 do
              begin
                if Cancelled then begin cancelledFlag := True; Exit; end;
                for x := 1 to W - 2 do
                begin
                  idx := y * W + x;

                  // blurA
                  lumUL := blurA[idx - W - 1];
                  lumUM := blurA[idx - W];
                  lumUR := blurA[idx - W + 1];
                  lumML := blurA[idx - 1];
                  lumMR := blurA[idx + 1];
                  lumDL := blurA[idx + W - 1];
                  lumDM := blurA[idx + W];
                  lumDR := blurA[idx + W + 1];
                  gx := (lumUR + 2*lumMR + lumDR) - (lumUL + 2*lumML + lumDL);
                  gy := (lumDL + 2*lumDM + lumDR) - (lumUL + 2*lumUM + lumUR);
                  mag := Abs(gx) + Abs(gy);

                  // blurB
                  lumUL := blurB[idx - W - 1];
                  lumUM := blurB[idx - W];
                  lumUR := blurB[idx - W + 1];
                  lumML := blurB[idx - 1];
                  lumMR := blurB[idx + 1];
                  lumDL := blurB[idx + W - 1];
                  lumDM := blurB[idx + W];
                  lumDR := blurB[idx + W + 1];
                  gx := (lumUR + 2*lumMR + lumDR) - (lumUL + 2*lumML + lumDL);
                  gy := (lumDL + 2*lumDM + lumDR) - (lumUL + 2*lumUM + lumUR);
                  mag := mag + Abs(gx) + Abs(gy);

                  // blurC
                  lumUL := blurC[idx - W - 1];
                  lumUM := blurC[idx - W];
                  lumUR := blurC[idx - W + 1];
                  lumML := blurC[idx - 1];
                  lumMR := blurC[idx + 1];
                  lumDL := blurC[idx + W - 1];
                  lumDM := blurC[idx + W];
                  lumDR := blurC[idx + W + 1];
                  gx := (lumUR + 2*lumMR + lumDR) - (lumUL + 2*lumML + lumDL);
                  gy := (lumDL + 2*lumDM + lumDR) - (lumUL + 2*lumUM + lumUR);
                  mag := mag + Abs(gx) + Abs(gy);

                  dog[idx] := mag;
                  // Max possible ~6120; keep scale stable without global normalization.
                  v := mag div 24;
                  if v > 255 then v := 255;
                  if v < 4 then v := 0;
                  edge8[idx] := Byte(v);
                  if v > maxEdge then maxEdge := v;
                end;
              end;
            end;

          7, 8: // XDoG Lines / Coherent Lines (XDoG + simple closing)
            begin
              SetLength(blurA, W * H);
              SetLength(blurB, W * H);
              SetLength(dog, W * H);

              BoxBlurGray(gray, blurA, W, H, 1);
              if cancelledFlag then Exit;
              BoxBlurGray(gray, blurB, W, H, 2);
              if cancelledFlag then Exit;

              maxVal := 0;
              for i := 0 to W * H - 1 do
              begin
                v := Abs(blurA[i] - blurB[i]);
                dog[i] := v;
                if v > maxVal then maxVal := v;
              end;
              if maxVal <= 0 then Exit;

              eps := 0.25 - 0.20 * (strength / 100.0); // 0.05..0.25
              if eps < 0.01 then eps := 0.01;
              phi := 4.0 + strength * 0.25;            // 4..29

              // build edge map into sm[] (0..255)
              SetLength(sm, W * H);
              for i := 0 to W * H - 1 do
              begin
                dogNorm := dog[i] / maxVal;
                xdog := 1.0 + tanh(phi * (dogNorm - eps));
                sm[i] := ClampByte(Round(255.0 * (xdog / 2.0)));
              end;

              if style = 8 then
              begin
                // simple morphological closing (dilate then erode) to connect small gaps
                SetLength(nms, W * H);
                FillChar(nms[0], Length(nms) * SizeOf(nms[0]), 0);
                // dilate
                for y := 1 to H - 2 do
                begin
                  if Cancelled then begin cancelledFlag := True; Exit; end;
                  for x := 1 to W - 2 do
                  begin
                    idx := y * W + x;
                    v := sm[idx];
                    v := Max(v, sm[idx - 1]);
                    v := Max(v, sm[idx + 1]);
                    v := Max(v, sm[idx - W]);
                    v := Max(v, sm[idx + W]);
                    v := Max(v, sm[idx - W - 1]);
                    v := Max(v, sm[idx - W + 1]);
                    v := Max(v, sm[idx + W - 1]);
                    v := Max(v, sm[idx + W + 1]);
                    nms[idx] := v;
                  end;
                end;
                // erode
                for y := 1 to H - 2 do
                begin
                  if Cancelled then begin cancelledFlag := True; Exit; end;
                  for x := 1 to W - 2 do
                  begin
                    idx := y * W + x;
                    v := nms[idx];
                    v := Min(v, nms[idx - 1]);
                    v := Min(v, nms[idx + 1]);
                    v := Min(v, nms[idx - W]);
                    v := Min(v, nms[idx + W]);
                    v := Min(v, nms[idx - W - 1]);
                    v := Min(v, nms[idx - W + 1]);
                    v := Min(v, nms[idx + W - 1]);
                    v := Min(v, nms[idx + W + 1]);
                    sm[idx] := v;
                  end;
                end;
              end;

              for i := 0 to W * H - 1 do
              begin
                if Cancelled then begin cancelledFlag := True; Exit; end;
                v := ClampByte(sm[i]);
                edge8[i] := v;
                if v > maxEdge then maxEdge := v;
              end;
            end;

          9: // Wavelet (Haar) detect
            begin
              SetLength(energy, W * H);
              FillChar(energy[0], Length(energy) * SizeOf(energy[0]), 0);

              // number of levels based on strength (more strength -> more scales)
              if strength >= 67 then maxLevels := 3
              else if strength >= 34 then maxLevels := 2
              else maxLevels := 1;

              cur := gray; // shared buffer is fine; we never mutate it
              curW := W;
              curH := H;
              blockSize := 1;

              for level := 1 to maxLevels do
              begin
                if Cancelled then begin cancelledFlag := True; Exit; end;
                if (curW < 2) or (curH < 2) then Break;

                nextW := curW div 2;
                nextH := curH div 2;
                if (nextW <= 0) or (nextH <= 0) then Break;
                SetLength(nxt, nextW * nextH);

                bs := blockSize * 2; // block size in original pixels for this level

                for by := 0 to nextH - 1 do
                begin
                  if Cancelled then begin cancelledFlag := True; Exit; end;
                  y2 := by * 2;
                  for bx := 0 to nextW - 1 do
                  begin
                    x2 := bx * 2;
                    p00 := cur[y2 * curW + x2];
                    p01 := cur[y2 * curW + x2 + 1];
                    p10 := cur[(y2 + 1) * curW + x2];
                    p11 := cur[(y2 + 1) * curW + x2 + 1];

                    nxt[by * nextW + bx] := (p00 + p01 + p10 + p11) div 4;

                    hdet := Abs(p00 - p01 + p10 - p11);
                    vdet := Abs(p00 + p01 - p10 - p11);
                    ddet := Abs(p00 - p01 - p10 + p11);
                    e := (hdet + vdet + ddet) div 4; // scale down a bit

                    origX := bx * bs;
                    origY := by * bs;
                    for oy := 0 to bs - 1 do
                      for ox := 0 to bs - 1 do
                        if (origX + ox < W) and (origY + oy < H) then
                          Inc(energy[(origY + oy) * W + (origX + ox)], e);
                  end;
                end;

                cur := nxt;
                curW := nextW;
                curH := nextH;
                blockSize := blockSize * 2;
              end;

              maxVal := 0;
              for i := 0 to W * H - 1 do
                if energy[i] > maxVal then maxVal := energy[i];
              if maxVal <= 0 then Exit;

              for i := 0 to W * H - 1 do
              begin
                if Cancelled then begin cancelledFlag := True; Exit; end;
                v := ClampByte(Round(energy[i] * 255.0 / maxVal));
                edge8[i] := v;
                if v > maxEdge then maxEdge := v;
              end;
            end;
        end;

        if maxEdge <= 0 then Exit;

        // Bake edges into the color image by darkening (old rez2ans behavior).
        for y := 0 to H - 1 do
        begin
          if Cancelled then begin cancelledFlag := True; Exit; end;
          srcRow := temp.ScanLine[y];
          dstRow := Dest.ScanLine[y];
          for x := 0 to W - 1 do
          begin
            idx := y * W + x;
            mag := edge8[idx];
            if mag < 4 then
            begin
              dstRow[x * 3 + 0] := srcRow[x * 3 + 0];
              dstRow[x * 3 + 1] := srcRow[x * 3 + 1];
              dstRow[x * 3 + 2] := srcRow[x * 3 + 2];
              Continue;
            end;
            delta := (mag * strength) div 100;
            dstRow[x * 3 + 0] := ClampByte(srcRow[x * 3 + 0] - delta);
            dstRow[x * 3 + 1] := ClampByte(srcRow[x * 3 + 1] - delta);
            dstRow[x * 3 + 2] := ClampByte(srcRow[x * 3 + 2] - delta);
          end;
        end;
      end;
    finally
      temp.Free;
    end;
  end;

  procedure QuantizeUniformRGB(targetColors: Integer);
  const
    Ordered4x4: array[0..3,0..3] of Integer = (
      (0, 8, 2,10),
      (12,4,14,6),
      (3,11,1,9),
      (15,7,13,5)
    );
  var
    W, H: Integer;
    levelsR, levelsG, levelsB: Integer;
    prod, nextR, nextG, nextB: Integer;
    stepR, stepG, stepB, stepMin: Double;
    x, y: Integer;
    row: PByte;
    r, g, b: Integer;
    adjR, adjG, adjB: Integer;
    qR, qG, qB: Integer;
    diffR, diffG, diffB: Integer;
    delta: Integer;
    errCurR, errCurG, errCurB: array of Integer;
    errNextR, errNextG, errNextB: array of Integer;
    tmp: array of Integer;

    function QuantStep(v: Integer; step: Double): Integer; inline;
    begin
      Result := ClampInt255(Round(Round(v / step) * step));
    end;

    procedure ClearErr(var A: array of Integer);
    var
      i: Integer;
    begin
      for i := 0 to High(A) do
        A[i] := 0;
    end;
  begin
    if targetColors < 2 then Exit;
    W := Dest.Width;
    H := Dest.Height;
    if (W <= 0) or (H <= 0) then Exit;

    // Choose a near-cubic RGB grid whose size <= targetColors.
    levelsR := Max(2, Floor(Power(targetColors, 1.0/3.0)));
    levelsG := levelsR;
    levelsB := levelsR;
    while (levelsR * levelsG * levelsB) < targetColors do
    begin
      nextR := (levelsR + 1) * levelsG * levelsB;
      nextG := levelsR * (levelsG + 1) * levelsB;
      nextB := levelsR * levelsG * (levelsB + 1);

      prod := levelsR * levelsG * levelsB;
      if (nextR <= targetColors) and (nextR >= nextG) and (nextR >= nextB) then
        Inc(levelsR)
      else if (nextG <= targetColors) and (nextG >= nextB) then
        Inc(levelsG)
      else if (nextB <= targetColors) then
        Inc(levelsB)
      else
        Break;

      if (levelsR * levelsG * levelsB) = prod then
        Break;
    end;

    stepR := 255.0 / (levelsR - 1);
    stepG := 255.0 / (levelsG - 1);
    stepB := 255.0 / (levelsB - 1);
    stepMin := Min(stepR, Min(stepG, stepB));

    if ditherStyle = 2 then
    begin
      SetLength(errCurR, W + 2);
      SetLength(errCurG, W + 2);
      SetLength(errCurB, W + 2);
      SetLength(errNextR, W + 2);
      SetLength(errNextG, W + 2);
      SetLength(errNextB, W + 2);
      ClearErr(errCurR); ClearErr(errCurG); ClearErr(errCurB);
      ClearErr(errNextR); ClearErr(errNextG); ClearErr(errNextB);

      for y := 0 to H - 1 do
      begin
        if Cancelled then begin cancelledFlag := True; Exit; end;
        row := Dest.ScanLine[y];
        for x := 0 to W - 1 do
        begin
          r := row[x*3 + 2];
          g := row[x*3 + 1];
          b := row[x*3 + 0];

          adjR := ClampInt255(r + (errCurR[x] div 16));
          adjG := ClampInt255(g + (errCurG[x] div 16));
          adjB := ClampInt255(b + (errCurB[x] div 16));

          qR := QuantStep(adjR, stepR);
          qG := QuantStep(adjG, stepG);
          qB := QuantStep(adjB, stepB);

          row[x*3 + 2] := qR;
          row[x*3 + 1] := qG;
          row[x*3 + 0] := qB;

          diffR := adjR - qR;
          diffG := adjG - qG;
          diffB := adjB - qB;

          // Errors are stored scaled by 16; distribute weights (7/3/5/1)/16.
          errCurR[x + 1] := errCurR[x + 1] + diffR * 7;
          errCurG[x + 1] := errCurG[x + 1] + diffG * 7;
          errCurB[x + 1] := errCurB[x + 1] + diffB * 7;

          if x > 0 then
          begin
            errNextR[x - 1] := errNextR[x - 1] + diffR * 3;
            errNextG[x - 1] := errNextG[x - 1] + diffG * 3;
            errNextB[x - 1] := errNextB[x - 1] + diffB * 3;
          end;

          errNextR[x] := errNextR[x] + diffR * 5;
          errNextG[x] := errNextG[x] + diffG * 5;
          errNextB[x] := errNextB[x] + diffB * 5;

          errNextR[x + 1] := errNextR[x + 1] + diffR * 1;
          errNextG[x + 1] := errNextG[x + 1] + diffG * 1;
          errNextB[x + 1] := errNextB[x + 1] + diffB * 1;
        end;

        tmp := errCurR; errCurR := errNextR; errNextR := tmp; ClearErr(errNextR);
        tmp := errCurG; errCurG := errNextG; errNextG := tmp; ClearErr(errNextG);
        tmp := errCurB; errCurB := errNextB; errNextB := tmp; ClearErr(errNextB);
      end;
      Exit;
    end;

    // Ordered dithering (lightweight) or none.
    for y := 0 to H - 1 do
    begin
      if Cancelled then begin cancelledFlag := True; Exit; end;
      row := Dest.ScanLine[y];
      for x := 0 to W - 1 do
      begin
        r := row[x*3 + 2];
        g := row[x*3 + 1];
        b := row[x*3 + 0];

        if ditherStyle = 1 then
        begin
          delta := Round((Ordered4x4[y and 3, x and 3] - 7) * (stepMin / 16));
          r := ClampInt255(r + delta);
          g := ClampInt255(g + delta);
          b := ClampInt255(b + delta);
        end;

        row[x*3 + 2] := QuantStep(r, stepR);
        row[x*3 + 1] := QuantStep(g, stepG);
        row[x*3 + 0] := QuantStep(b, stepB);
      end;
    end;
  end;

  procedure QuantizeWithPalette(const Pal: array of TRGB24);
  const
    Ordered4x4: array[0..3,0..3] of Integer = (
      (0, 8, 2,10),
      (12,4,14,6),
      (3,11,1,9),
      (15,7,13,5)
    );
  var
    W, H: Integer;
    x, y: Integer;
    row: PByte;
    r, g, b: Integer;
    adjR, adjG, adjB: Integer;
    diffR, diffG, diffB: Integer;
    bestIdx: Integer;
    bestDist, dist: Integer;
    dr, dg, db: Integer;
    delta: Integer;
    errCurR, errCurG, errCurB: array of Integer;
    errNextR, errNextG, errNextB: array of Integer;
    tmp: array of Integer;

    function NearestIndex(ar, ag, ab: Integer): Integer; inline;
    var
      i: Integer;
    begin
      Result := 0;
      bestDist := High(Integer);
      for i := 0 to High(Pal) do
      begin
        dr := ar - Pal[i].R;
        dg := ag - Pal[i].G;
        db := ab - Pal[i].B;
        dist := dr*dr + dg*dg + db*db;
        if dist < bestDist then
        begin
          bestDist := dist;
          Result := i;
          if dist = 0 then Break;
        end;
      end;
    end;

    procedure ClearErr(var A: array of Integer);
    var
      i: Integer;
    begin
      for i := 0 to High(A) do
        A[i] := 0;
    end;
  begin
    if Length(Pal) = 0 then Exit;
    W := Dest.Width;
    H := Dest.Height;

    if ditherStyle = 2 then
    begin
      SetLength(errCurR, W + 2);
      SetLength(errCurG, W + 2);
      SetLength(errCurB, W + 2);
      SetLength(errNextR, W + 2);
      SetLength(errNextG, W + 2);
      SetLength(errNextB, W + 2);
      ClearErr(errCurR); ClearErr(errCurG); ClearErr(errCurB);
      ClearErr(errNextR); ClearErr(errNextG); ClearErr(errNextB);

      for y := 0 to H - 1 do
      begin
        if Cancelled then begin cancelledFlag := True; Exit; end;
        row := Dest.ScanLine[y];
        for x := 0 to W - 1 do
        begin
          r := row[x*3 + 2];
          g := row[x*3 + 1];
          b := row[x*3 + 0];

          adjR := ClampInt255(r + (errCurR[x] div 16));
          adjG := ClampInt255(g + (errCurG[x] div 16));
          adjB := ClampInt255(b + (errCurB[x] div 16));

          bestIdx := NearestIndex(adjR, adjG, adjB);
          row[x*3 + 2] := Pal[bestIdx].R;
          row[x*3 + 1] := Pal[bestIdx].G;
          row[x*3 + 0] := Pal[bestIdx].B;

          diffR := adjR - Pal[bestIdx].R;
          diffG := adjG - Pal[bestIdx].G;
          diffB := adjB - Pal[bestIdx].B;

          errCurR[x + 1] := errCurR[x + 1] + diffR * 7;
          errCurG[x + 1] := errCurG[x + 1] + diffG * 7;
          errCurB[x + 1] := errCurB[x + 1] + diffB * 7;

          if x > 0 then
          begin
            errNextR[x - 1] := errNextR[x - 1] + diffR * 3;
            errNextG[x - 1] := errNextG[x - 1] + diffG * 3;
            errNextB[x - 1] := errNextB[x - 1] + diffB * 3;
          end;

          errNextR[x] := errNextR[x] + diffR * 5;
          errNextG[x] := errNextG[x] + diffG * 5;
          errNextB[x] := errNextB[x] + diffB * 5;

          errNextR[x + 1] := errNextR[x + 1] + diffR * 1;
          errNextG[x + 1] := errNextG[x + 1] + diffG * 1;
          errNextB[x + 1] := errNextB[x + 1] + diffB * 1;
        end;

        tmp := errCurR; errCurR := errNextR; errNextR := tmp; ClearErr(errNextR);
        tmp := errCurG; errCurG := errNextG; errNextG := tmp; ClearErr(errNextG);
        tmp := errCurB; errCurB := errNextB; errNextB := tmp; ClearErr(errNextB);
      end;
      Exit;
    end;

    for y := 0 to H - 1 do
    begin
      if Cancelled then begin cancelledFlag := True; Exit; end;
      row := Dest.ScanLine[y];
      for x := 0 to W - 1 do
      begin
        r := row[x*3 + 2];
        g := row[x*3 + 1];
        b := row[x*3 + 0];

        if ditherStyle = 1 then
        begin
          // small, palette-size-based nudge before mapping
          delta := Round((Ordered4x4[y and 3, x and 3] - 7) * ((255.0 / Max(2, Length(Pal))) / 16));
          r := ClampInt255(r + delta);
          g := ClampInt255(g + delta);
          b := ClampInt255(b + delta);
        end;

        bestIdx := NearestIndex(r, g, b);
        row[x*3 + 2] := Pal[bestIdx].R;
        row[x*3 + 1] := Pal[bestIdx].G;
        row[x*3 + 0] := Pal[bestIdx].B;
      end;
    end;
  end;

  function BuildPaletteMedianCut(targetColors: Integer): TRGB24Array;
  type
    TColorBox = record
      Start, Count: Integer;
      MinR, MaxR: Byte;
      MinG, MaxG: Byte;
      MinB, MaxB: Byte;
    end;
  var
    samples: TRGB24Array;
    sampleCount: Integer;
    boxes: array of TColorBox;
    boxCount: Integer;
    W, H: Integer;
    stepXY: Integer;
    x, y: Integer;
    row: PByte;
    c: TRGB24;
    bi, bestBi: Integer;
    rangeR, rangeG, rangeB, bestRange: Integer;
    channel: Integer;
    mid: Integer;
    newBox: TColorBox;
    i: Integer;
    sumR, sumG, sumB: Int64;
    t: TRGB24;

    procedure PushSample(const s: TRGB24);
    begin
      if sampleCount >= Length(samples) then
        SetLength(samples, Max(1024, Length(samples) * 2));
      samples[sampleCount] := s;
      Inc(sampleCount);
    end;

    procedure ComputeBounds(var b: TColorBox);
    var
      i2: Integer;
      s: TRGB24;
    begin
      b.MinR := 255; b.MinG := 255; b.MinB := 255;
      b.MaxR := 0;   b.MaxG := 0;   b.MaxB := 0;
      for i2 := b.Start to b.Start + b.Count - 1 do
      begin
        s := samples[i2];
        if s.R < b.MinR then b.MinR := s.R;
        if s.R > b.MaxR then b.MaxR := s.R;
        if s.G < b.MinG then b.MinG := s.G;
        if s.G > b.MaxG then b.MaxG := s.G;
        if s.B < b.MinB then b.MinB := s.B;
        if s.B > b.MaxB then b.MaxB := s.B;
      end;
    end;

    function ChannelValue(const s: TRGB24; const ch: Integer): Byte; inline;
    begin
      case ch of
        0: Result := s.R;
        1: Result := s.G;
      else
        Result := s.B;
      end;
    end;

    procedure QuickSortColors(L, R, ch: Integer);
    var
      I2, J2: Integer;
      pivot: Byte;
    begin
      I2 := L;
      J2 := R;
      pivot := ChannelValue(samples[(L + R) div 2], ch);
      repeat
        while ChannelValue(samples[I2], ch) < pivot do Inc(I2);
        while ChannelValue(samples[J2], ch) > pivot do Dec(J2);
        if I2 <= J2 then
        begin
          t := samples[I2];
          samples[I2] := samples[J2];
          samples[J2] := t;
          Inc(I2);
          Dec(J2);
        end;
      until I2 > J2;
      if L < J2 then QuickSortColors(L, J2, ch);
      if I2 < R then QuickSortColors(I2, R, ch);
    end;
  begin
    Result := nil;
    if targetColors < 2 then Exit;

    W := Dest.Width;
    H := Dest.Height;
    if (W <= 0) or (H <= 0) then Exit;

    sampleCount := 0;
    SetLength(samples, 0);

    // sample (bounded) for speed
    stepXY := 1;
    if (Int64(W) * Int64(H)) > 200000 then
      stepXY := Max(1, Trunc(Sqrt((Int64(W) * Int64(H)) / 200000.0)));

    for y := 0 to H - 1 do
    begin
      if (y mod stepXY) <> 0 then Continue;
      if Cancelled then begin cancelledFlag := True; Result := nil; Exit; end;
      row := Dest.ScanLine[y];
      for x := 0 to W - 1 do
      begin
        if (x mod stepXY) <> 0 then Continue;
        c.R := row[x*3 + 2];
        c.G := row[x*3 + 1];
        c.B := row[x*3 + 0];
        PushSample(c);
      end;
    end;

    if sampleCount = 0 then Exit;
    SetLength(samples, sampleCount);

    SetLength(boxes, targetColors);
    boxCount := 1;
    boxes[0].Start := 0;
    boxes[0].Count := Length(samples);
    ComputeBounds(boxes[0]);

    while boxCount < targetColors do
    begin
      if Cancelled then begin cancelledFlag := True; Result := nil; Exit; end;

      bestBi := -1;
      bestRange := -1;
      channel := 0;
      for bi := 0 to boxCount - 1 do
      begin
        if boxes[bi].Count < 2 then Continue;
        rangeR := boxes[bi].MaxR - boxes[bi].MinR;
        rangeG := boxes[bi].MaxG - boxes[bi].MinG;
        rangeB := boxes[bi].MaxB - boxes[bi].MinB;
        if Max(rangeR, Max(rangeG, rangeB)) > bestRange then
        begin
          bestRange := Max(rangeR, Max(rangeG, rangeB));
          bestBi := bi;
        end;
      end;

      if (bestBi < 0) or (bestRange <= 0) then Break;

      rangeR := boxes[bestBi].MaxR - boxes[bestBi].MinR;
      rangeG := boxes[bestBi].MaxG - boxes[bestBi].MinG;
      rangeB := boxes[bestBi].MaxB - boxes[bestBi].MinB;
      if (rangeR >= rangeG) and (rangeR >= rangeB) then channel := 0
      else if (rangeG >= rangeB) then channel := 1
      else channel := 2;

      QuickSortColors(boxes[bestBi].Start,
                      boxes[bestBi].Start + boxes[bestBi].Count - 1,
                      channel);

      mid := boxes[bestBi].Count div 2;
      newBox := boxes[bestBi];
      newBox.Start := boxes[bestBi].Start + mid;
      newBox.Count := boxes[bestBi].Count - mid;
      boxes[bestBi].Count := mid;
      ComputeBounds(boxes[bestBi]);
      ComputeBounds(newBox);

      boxes[boxCount] := newBox;
      Inc(boxCount);
    end;

    SetLength(Result, boxCount);
    for bi := 0 to boxCount - 1 do
    begin
      sumR := 0; sumG := 0; sumB := 0;
      for i := boxes[bi].Start to boxes[bi].Start + boxes[bi].Count - 1 do
      begin
        sumR := sumR + samples[i].R;
        sumG := sumG + samples[i].G;
        sumB := sumB + samples[i].B;
      end;
      if boxes[bi].Count > 0 then
      begin
        Result[bi].R := ClampByte(Integer(sumR div boxes[bi].Count));
        Result[bi].G := ClampByte(Integer(sumG div boxes[bi].Count));
        Result[bi].B := ClampByte(Integer(sumB div boxes[bi].Count));
      end;
    end;
  end;

  procedure QuantizeMedianCut(targetColors: Integer);
  var
    pal: TRGB24Array;
  begin
    pal := BuildPaletteMedianCut(targetColors);
    if cancelledFlag then Exit;
    QuantizeWithPalette(pal);
  end;

  procedure QuantizeOctree(targetColors: Integer);
  const
    Ordered4x4: array[0..3,0..3] of Integer = (
      (0, 8, 2,10),
      (12,4,14,6),
      (3,11,1,9),
      (15,7,13,5)
    );
  var
    root: TOctNode;
    reducible: array[0..7] of TOctNode;
    leafCount: Integer;
    x, y, i: Integer;
    W, H: Integer;
    row: PByte;
    r, g, b: Integer;
    adjR, adjG, adjB: Integer;
    diffR, diffG, diffB: Integer;
    delta: Integer;
    errCurR, errCurG, errCurB: array of Integer;
    errNextR, errNextG, errNextB: array of Integer;
    tmp: array of Integer;

    function ColorIndex(ar, ag, ab, level: Integer): Integer; inline;
    var
      shift: Integer;
    begin
      shift := 7 - level;
      Result := (((ar shr shift) and 1) shl 2) or (((ag shr shift) and 1) shl 1) or ((ab shr shift) and 1);
    end;

    procedure AddReducible(n: TOctNode);
    begin
      n.NextReducible := reducible[n.Level];
      reducible[n.Level] := n;
    end;

    procedure AddColorToTree(ar, ag, ab: Integer);
    var
      node, child: TOctNode;
      level, idx: Integer;
    begin
      node := root;
      for level := 0 to 7 do
      begin
        Inc(node.PixelCount);
        Inc(node.RedSum, ar);
        Inc(node.GreenSum, ag);
        Inc(node.BlueSum, ab);

        if node.IsLeaf then Exit;

        idx := ColorIndex(ar, ag, ab, level);
        if node.Children[idx] = nil then
        begin
          child := TOctNode.Create(level + 1, level = 7); // leaf at level 8
          node.Children[idx] := child;
          if child.IsLeaf then
            Inc(leafCount)
          else
            AddReducible(child);
        end;
        node := node.Children[idx];
      end;

      Inc(node.PixelCount);
      Inc(node.RedSum, ar);
      Inc(node.GreenSum, ag);
      Inc(node.BlueSum, ab);
    end;

    procedure ReduceOnce;
    var
      level: Integer;
      node: TOctNode;
      child: TOctNode;
      leafChildren: Integer;
      j: Integer;
    begin
      level := 7;
      while (level >= 0) and (reducible[level] = nil) do
        Dec(level);
      if level < 0 then Exit;

      node := reducible[level];
      reducible[level] := node.NextReducible;
      node.NextReducible := nil;

      leafChildren := 0;
      for j := 0 to 7 do
      begin
        child := node.Children[j];
        if child <> nil then
        begin
          if child.IsLeaf then Inc(leafChildren);
          child.Free;
          node.Children[j] := nil;
        end;
      end;
      node.IsLeaf := True;
      leafCount := leafCount - leafChildren + 1;
    end;

    function FindNodeForColor(ar, ag, ab: Integer): TOctNode; inline;
    var
      node: TOctNode;
      level, idx: Integer;
    begin
      node := root;
      for level := 0 to 7 do
      begin
        if node.IsLeaf then Break;
        idx := ColorIndex(ar, ag, ab, level);
        if node.Children[idx] = nil then Break;
        node := node.Children[idx];
      end;
      Result := node;
    end;

    procedure ClearErr(var A: array of Integer);
    var
      j: Integer;
    begin
      for j := 0 to High(A) do
        A[j] := 0;
    end;
  begin
    if targetColors < 2 then Exit;
    if (Dest.Width <= 0) or (Dest.Height <= 0) then Exit;

    for i := 0 to 7 do
      reducible[i] := nil;
    leafCount := 0;

    root := TOctNode.Create(0, False);
    try
      AddReducible(root);

      W := Dest.Width;
      H := Dest.Height;

      // build tree
      for y := 0 to H - 1 do
      begin
        if Cancelled then begin cancelledFlag := True; Exit; end;
        row := Dest.ScanLine[y];
        for x := 0 to W - 1 do
        begin
          r := row[x*3 + 2];
          g := row[x*3 + 1];
          b := row[x*3 + 0];
          AddColorToTree(r, g, b);
          while (leafCount > targetColors) do
            ReduceOnce;
        end;
      end;

      // map pixels
      if ditherStyle = 2 then
      begin
        SetLength(errCurR, W + 2);
        SetLength(errCurG, W + 2);
        SetLength(errCurB, W + 2);
        SetLength(errNextR, W + 2);
        SetLength(errNextG, W + 2);
        SetLength(errNextB, W + 2);
        ClearErr(errCurR); ClearErr(errCurG); ClearErr(errCurB);
        ClearErr(errNextR); ClearErr(errNextG); ClearErr(errNextB);

        for y := 0 to H - 1 do
        begin
          if Cancelled then begin cancelledFlag := True; Exit; end;
          row := Dest.ScanLine[y];
          for x := 0 to W - 1 do
          begin
            r := row[x*3 + 2];
            g := row[x*3 + 1];
            b := row[x*3 + 0];

            adjR := ClampInt255(r + (errCurR[x] div 16));
            adjG := ClampInt255(g + (errCurG[x] div 16));
            adjB := ClampInt255(b + (errCurB[x] div 16));

            with FindNodeForColor(adjR, adjG, adjB).AvgColor do
            begin
              row[x*3 + 2] := R;
              row[x*3 + 1] := G;
              row[x*3 + 0] := B;
              diffR := adjR - R;
              diffG := adjG - G;
              diffB := adjB - B;
            end;

            errCurR[x + 1] := errCurR[x + 1] + diffR * 7;
            errCurG[x + 1] := errCurG[x + 1] + diffG * 7;
            errCurB[x + 1] := errCurB[x + 1] + diffB * 7;

            if x > 0 then
            begin
              errNextR[x - 1] := errNextR[x - 1] + diffR * 3;
              errNextG[x - 1] := errNextG[x - 1] + diffG * 3;
              errNextB[x - 1] := errNextB[x - 1] + diffB * 3;
            end;

            errNextR[x] := errNextR[x] + diffR * 5;
            errNextG[x] := errNextG[x] + diffG * 5;
            errNextB[x] := errNextB[x] + diffB * 5;

            errNextR[x + 1] := errNextR[x + 1] + diffR * 1;
            errNextG[x + 1] := errNextG[x + 1] + diffG * 1;
            errNextB[x + 1] := errNextB[x + 1] + diffB * 1;
          end;

          tmp := errCurR; errCurR := errNextR; errNextR := tmp; ClearErr(errNextR);
          tmp := errCurG; errCurG := errNextG; errNextG := tmp; ClearErr(errNextG);
          tmp := errCurB; errCurB := errNextB; errNextB := tmp; ClearErr(errNextB);
        end;
        Exit;
      end;

      for y := 0 to H - 1 do
      begin
        if Cancelled then begin cancelledFlag := True; Exit; end;
        row := Dest.ScanLine[y];
        for x := 0 to W - 1 do
        begin
          r := row[x*3 + 2];
          g := row[x*3 + 1];
          b := row[x*3 + 0];

          if ditherStyle = 1 then
          begin
            delta := Round((Ordered4x4[y and 3, x and 3] - 7) * ((255.0 / targetColors) / 16));
            r := ClampInt255(r + delta);
            g := ClampInt255(g + delta);
            b := ClampInt255(b + delta);
          end;

          with FindNodeForColor(r, g, b).AvgColor do
          begin
            row[x*3 + 2] := R;
            row[x*3 + 1] := G;
            row[x*3 + 0] := B;
          end;
        end;
      end;
    finally
      root.Free;
    end;
  end;

  function BuildPalettePopularity(targetColors: Integer): TRGB24Array;
  const
    SHIFT = 3; // 5 bits per channel
    BINS = 32768;
  var
    W, H: Integer;
    stepXY: Integer;
    x, y: Integer;
    row: PByte;
    r, g, b: Integer;
    idx: Integer;
    counts: array of Integer;
    sumR, sumG, sumB: array of Int64;
    topIdx: array of Integer;
    topCnt: array of Integer;
    i, j: Integer;
    n: Integer;
    c: Integer;
  begin
    Result := nil;
    if targetColors < 2 then Exit;

    W := Dest.Width;
    H := Dest.Height;
    if (W <= 0) or (H <= 0) then Exit;

    SetLength(counts, BINS);
    SetLength(sumR, BINS);
    SetLength(sumG, BINS);
    SetLength(sumB, BINS);

    // Sample on very large images for speed.
    stepXY := 1;
    if (Int64(W) * Int64(H)) > 400000 then
      stepXY := Max(1, Trunc(Sqrt((Int64(W) * Int64(H)) / 400000.0)));

    for y := 0 to H - 1 do
    begin
      if (y mod stepXY) <> 0 then Continue;
      if Cancelled then begin cancelledFlag := True; Result := nil; Exit; end;
      row := Dest.ScanLine[y];
      for x := 0 to W - 1 do
      begin
        if (x mod stepXY) <> 0 then Continue;
        b := row[x * 3 + 0];
        g := row[x * 3 + 1];
        r := row[x * 3 + 2];
        idx := ((r shr SHIFT) shl 10) or ((g shr SHIFT) shl 5) or (b shr SHIFT);
        Inc(counts[idx]);
        sumR[idx] := sumR[idx] + r;
        sumG[idx] := sumG[idx] + g;
        sumB[idx] := sumB[idx] + b;
      end;
    end;

    SetLength(topIdx, targetColors);
    SetLength(topCnt, targetColors);
    for i := 0 to targetColors - 1 do
    begin
      topIdx[i] := 0;
      topCnt[i] := -1;
    end;

    for idx := 0 to BINS - 1 do
    begin
      c := counts[idx];
      if c <= 0 then Continue;
      if c <= topCnt[targetColors - 1] then Continue;

      j := targetColors - 1;
      while (j > 0) and (c > topCnt[j - 1]) do
      begin
        topCnt[j] := topCnt[j - 1];
        topIdx[j] := topIdx[j - 1];
        Dec(j);
      end;
      topCnt[j] := c;
      topIdx[j] := idx;
    end;

    n := 0;
    while (n < targetColors) and (topCnt[n] > 0) do Inc(n);
    if n <= 0 then Exit;

    SetLength(Result, n);
    for i := 0 to n - 1 do
    begin
      idx := topIdx[i];
      c := counts[idx];
      if c <= 0 then Continue;
      Result[i].R := ClampByte(Integer(sumR[idx] div c));
      Result[i].G := ClampByte(Integer(sumG[idx] div c));
      Result[i].B := ClampByte(Integer(sumB[idx] div c));
    end;
  end;

  procedure QuantizePopularity(targetColors: Integer);
  var
    pal: TRGB24Array;
  begin
    pal := BuildPalettePopularity(targetColors);
    if cancelledFlag then Exit;
    QuantizeWithPalette(pal);
  end;

  function BuildPaletteWu(targetColors: Integer): TRGB24Array;
  type
    TWuBox = record
      r0, r1: Integer;
      g0, g1: Integer;
      b0, b1: Integer;
    end;
  const
    BINS = 33; // 0..32 (with 0 as "empty" border)
    MAXC = 32;
  var
    W, H: Integer;
    stepXY: Integer;
    x, y: Integer;
    row: PByte;
    r, g, b: Integer;
    ri, gi, bi: Integer;
    idx: Integer;
    vwt, vmr, vmg, vmb, vm2: array of Int64;
    cubes: array of TWuBox;
    cubeVar: array of Double;
    cubeCount: Integer;
    i, j: Integer;
    best: Integer;
    bestV: Double;
    c1, c2: TWuBox;
    wv: Int64;
    sr, sg, sb: Int64;

    function VIndex(rp, gp, bp: Integer): Integer; inline;
    begin
      Result := (rp * BINS + gp) * BINS + bp;
    end;

    function Vol(const c: TWuBox; const m: array of Int64): Int64; inline;
    begin
      Result :=
        m[VIndex(c.r1, c.g1, c.b1)] -
        m[VIndex(c.r0, c.g1, c.b1)] -
        m[VIndex(c.r1, c.g0, c.b1)] -
        m[VIndex(c.r1, c.g1, c.b0)] +
        m[VIndex(c.r0, c.g0, c.b1)] +
        m[VIndex(c.r0, c.g1, c.b0)] +
        m[VIndex(c.r1, c.g0, c.b0)] -
        m[VIndex(c.r0, c.g0, c.b0)];
    end;

    function VarianceBox(const c: TWuBox): Double;
    var
      wt: Int64;
      rsum, gsum, bsum: Int64;
      xx: Int64;
    begin
      wt := Vol(c, vwt);
      if wt <= 0 then Exit(0.0);
      rsum := Vol(c, vmr);
      gsum := Vol(c, vmg);
      bsum := Vol(c, vmb);
      xx := Vol(c, vm2);
      Result := xx - ( (Double(rsum) * Double(rsum) +
                        Double(gsum) * Double(gsum) +
                        Double(bsum) * Double(bsum)) / Double(wt) );
      if Result < 0 then Result := 0.0;
    end;

    function TryCut(const src: TWuBox; axis, pos: Integer; out a, b: TWuBox; out score: Double): Boolean;
    var
      w1, w2: Int64;
    begin
      a := src;
      b := src;
      case axis of
        0: begin a.r1 := pos; b.r0 := pos; end;
        1: begin a.g1 := pos; b.g0 := pos; end;
      else
        begin a.b1 := pos; b.b0 := pos; end;
      end;

      w1 := Vol(a, vwt);
      w2 := Vol(b, vwt);
      if (w1 <= 0) or (w2 <= 0) then Exit(False);

      score := VarianceBox(a) + VarianceBox(b);
      Result := True;
    end;

    function CutBest(const src: TWuBox; out a, b: TWuBox): Boolean;
    var
      axis: Integer;
      pos, first, last: Integer;
      bestScore: Double;
      score: Double;
      ta, tb: TWuBox;
      found: Boolean;
    begin
      found := False;
      bestScore := 1.0e300;
      a := src;
      b := src;

      for axis := 0 to 2 do
      begin
        case axis of
          0: begin first := src.r0 + 1; last := src.r1 - 1; end;
          1: begin first := src.g0 + 1; last := src.g1 - 1; end;
        else
          begin first := src.b0 + 1; last := src.b1 - 1; end;
        end;
        if first > last then Continue;

        for pos := first to last do
        begin
          if Cancelled then begin cancelledFlag := True; Exit(False); end;
          if TryCut(src, axis, pos, ta, tb, score) then
            if score < bestScore then
            begin
              bestScore := score;
              a := ta;
              b := tb;
              found := True;
            end;
        end;
      end;

      Result := found;
    end;

  var
    rp, gp, bp: Integer;
    id0, id1, id2, id3, id4, id5, id6: Integer;
    hwt, hmr, hmg, hmb, hm2: Int64;
  begin
    Result := nil;
    if targetColors < 2 then Exit;

    W := Dest.Width;
    H := Dest.Height;
    if (W <= 0) or (H <= 0) then Exit;

    SetLength(vwt, BINS * BINS * BINS);
    SetLength(vmr, BINS * BINS * BINS);
    SetLength(vmg, BINS * BINS * BINS);
    SetLength(vmb, BINS * BINS * BINS);
    SetLength(vm2, BINS * BINS * BINS);

    // Sample on very large images for speed.
    stepXY := 1;
    if (Int64(W) * Int64(H)) > 600000 then
      stepXY := Max(1, Trunc(Sqrt((Int64(W) * Int64(H)) / 600000.0)));

    for y := 0 to H - 1 do
    begin
      if (y mod stepXY) <> 0 then Continue;
      if Cancelled then begin cancelledFlag := True; Result := nil; Exit; end;
      row := Dest.ScanLine[y];
      for x := 0 to W - 1 do
      begin
        if (x mod stepXY) <> 0 then Continue;
        b := row[x * 3 + 0];
        g := row[x * 3 + 1];
        r := row[x * 3 + 2];

        ri := (r shr 3) + 1;
        gi := (g shr 3) + 1;
        bi := (b shr 3) + 1;
        idx := VIndex(ri, gi, bi);

        Inc(vwt[idx]);
        vmr[idx] := vmr[idx] + r;
        vmg[idx] := vmg[idx] + g;
        vmb[idx] := vmb[idx] + b;
        vm2[idx] := vm2[idx] + (Int64(r) * r + Int64(g) * g + Int64(b) * b);
      end;
    end;

    // Build 3D integral volumes (in place).
    for rp := 1 to MAXC do
    begin
      if Cancelled then begin cancelledFlag := True; Result := nil; Exit; end;
      for gp := 1 to MAXC do
        for bp := 1 to MAXC do
        begin
          idx := VIndex(rp, gp, bp);

          hwt := vwt[idx];
          hmr := vmr[idx];
          hmg := vmg[idx];
          hmb := vmb[idx];
          hm2 := vm2[idx];

          id0 := VIndex(rp - 1, gp, bp);
          id1 := VIndex(rp, gp - 1, bp);
          id2 := VIndex(rp, gp, bp - 1);
          id3 := VIndex(rp - 1, gp - 1, bp);
          id4 := VIndex(rp - 1, gp, bp - 1);
          id5 := VIndex(rp, gp - 1, bp - 1);
          id6 := VIndex(rp - 1, gp - 1, bp - 1);

          vwt[idx] := hwt + vwt[id0] + vwt[id1] + vwt[id2] - vwt[id3] - vwt[id4] - vwt[id5] + vwt[id6];
          vmr[idx] := hmr + vmr[id0] + vmr[id1] + vmr[id2] - vmr[id3] - vmr[id4] - vmr[id5] + vmr[id6];
          vmg[idx] := hmg + vmg[id0] + vmg[id1] + vmg[id2] - vmg[id3] - vmg[id4] - vmg[id5] + vmg[id6];
          vmb[idx] := hmb + vmb[id0] + vmb[id1] + vmb[id2] - vmb[id3] - vmb[id4] - vmb[id5] + vmb[id6];
          vm2[idx] := hm2 + vm2[id0] + vm2[id1] + vm2[id2] - vm2[id3] - vm2[id4] - vm2[id5] + vm2[id6];
        end;
    end;

    SetLength(cubes, targetColors);
    SetLength(cubeVar, targetColors);
    cubeCount := 1;
    cubes[0].r0 := 0; cubes[0].r1 := MAXC;
    cubes[0].g0 := 0; cubes[0].g1 := MAXC;
    cubes[0].b0 := 0; cubes[0].b1 := MAXC;
    cubeVar[0] := VarianceBox(cubes[0]);

    for i := 1 to targetColors - 1 do
    begin
      if Cancelled then begin cancelledFlag := True; Result := nil; Exit; end;

      best := -1;
      bestV := 0.0;
      for j := 0 to cubeCount - 1 do
        if cubeVar[j] > bestV then
        begin
          bestV := cubeVar[j];
          best := j;
        end;

      if (best < 0) or (bestV <= 0.0) then Break;

      if not CutBest(cubes[best], c1, c2) then
      begin
        cubeVar[best] := 0.0;
        Break;
      end;

      cubes[best] := c1;
      cubes[cubeCount] := c2;
      cubeVar[best] := VarianceBox(c1);
      cubeVar[cubeCount] := VarianceBox(c2);
      Inc(cubeCount);
    end;

    SetLength(Result, cubeCount);
    for i := 0 to cubeCount - 1 do
    begin
      wv := Vol(cubes[i], vwt);
      if wv <= 0 then
      begin
        Result[i].R := 0;
        Result[i].G := 0;
        Result[i].B := 0;
        Continue;
      end;
      sr := Vol(cubes[i], vmr);
      sg := Vol(cubes[i], vmg);
      sb := Vol(cubes[i], vmb);

      Result[i].R := ClampByte(Integer(sr div wv));
      Result[i].G := ClampByte(Integer(sg div wv));
      Result[i].B := ClampByte(Integer(sb div wv));
    end;
  end;

  procedure QuantizeWu(targetColors: Integer);
  var
    pal: TRGB24Array;
  begin
    pal := BuildPaletteWu(targetColors);
    if cancelledFlag then Exit;
    QuantizeWithPalette(pal);
  end;

  function BuildPaletteKMeansPP(targetColors: Integer): TRGB24Array;
  const
    MAX_SAMPLES = 60000;
    MAX_ITERS = 12;
  type
    TCentroid = record
      R, G, B: Double;
    end;
  var
    W, H: Integer;
    stepXY: Integer;
    x, y: Integer;
    row: PByte;
    samples: TRGB24Array;
    sampleCount: Integer;
    K: Integer;
    cent: array of TCentroid;
    assign: array of Integer;
    dist2: array of Int64;
    sumDist: Double;
    pick: Double;
    i, j, iter: Integer;
    bestIdx: Integer;
    bestD: Int64;
    dr, dg, db: Int64;
    candDist: Int64;
    sumR, sumG, sumB: array of Int64;
    cnt: array of Integer;
    seed: Cardinal;
    cand: Integer;

    function NextRand(var s: Cardinal): Cardinal; inline;
    begin
      s := s * 1664525 + 1013904223;
      Result := s;
    end;

    function Rand01(var s: Cardinal): Double; inline;
    begin
      Result := (NextRand(s) and $FFFFFF) / $1000000;
    end;

    procedure PushSample(const s: TRGB24);
    begin
      if sampleCount >= Length(samples) then
        SetLength(samples, Max(1024, Length(samples) * 2));
      samples[sampleCount] := s;
      Inc(sampleCount);
    end;

    procedure InitSamples;
    var
      c: TRGB24;
      sx, sy: Integer;
    begin
      sampleCount := 0;
      SetLength(samples, 0);

      stepXY := 1;
      if (Int64(W) * Int64(H)) > MAX_SAMPLES then
        stepXY := Max(1, Trunc(Sqrt((Int64(W) * Int64(H)) / MAX_SAMPLES)));

      // Use while-loops here: some FPC builds are picky about FOR loop counters
      // inside nested procedures and report "Illegal counter variable".
      sy := 0;
      while sy < H do
      begin
        if (sy mod stepXY) = 0 then
        begin
          if Cancelled then begin cancelledFlag := True; Exit; end;
          row := Dest.ScanLine[sy];
          sx := 0;
          while sx < W do
          begin
            if (sx mod stepXY) = 0 then
            begin
              c.R := row[sx * 3 + 2];
              c.G := row[sx * 3 + 1];
              c.B := row[sx * 3 + 0];
              PushSample(c);
            end;
            Inc(sx);
          end;
        end;
        Inc(sy);
      end;

      SetLength(samples, sampleCount);
    end;

  begin
    Result := nil;
    if targetColors < 2 then Exit;

    W := Dest.Width;
    H := Dest.Height;
    if (W <= 0) or (H <= 0) then Exit;

    InitSamples;
    if cancelledFlag then Exit;
    if sampleCount <= 0 then Exit;

    K := Min(targetColors, sampleCount);
    SetLength(cent, K);
    SetLength(assign, sampleCount);
    SetLength(dist2, sampleCount);

    // Local deterministic seed (no global RandSeed use).
    seed := $9E3779B9;
    if sampleCount > 0 then
      seed := seed xor (Cardinal(samples[0].R) shl 16) xor (Cardinal(samples[0].G) shl 8) xor Cardinal(samples[0].B);
    seed := seed xor Cardinal(sampleCount) * 2654435761;

    // Pick first centroid.
    cand := Integer(NextRand(seed) mod Cardinal(sampleCount));
    cent[0].R := samples[cand].R;
    cent[0].G := samples[cand].G;
    cent[0].B := samples[cand].B;

    // KMeans++ seeding.
    for j := 1 to K - 1 do
    begin
      if Cancelled then begin cancelledFlag := True; Exit; end;
      sumDist := 0.0;
      for i := 0 to sampleCount - 1 do
      begin
        if (i and 2047) = 0 then
          if Cancelled then begin cancelledFlag := True; Exit; end;
        bestD := High(Int64);
        for bestIdx := 0 to j - 1 do
        begin
          dr := samples[i].R - Round(cent[bestIdx].R);
          dg := samples[i].G - Round(cent[bestIdx].G);
          db := samples[i].B - Round(cent[bestIdx].B);
          candDist := dr * dr + dg * dg + db * db;
          if candDist < bestD then bestD := candDist;
        end;
        dist2[i] := bestD;
        sumDist := sumDist + bestD;
      end;

      if sumDist <= 0.0 then
      begin
        cand := Integer(NextRand(seed) mod Cardinal(sampleCount));
        cent[j].R := samples[cand].R;
        cent[j].G := samples[cand].G;
        cent[j].B := samples[cand].B;
        Continue;
      end;

      pick := Rand01(seed) * sumDist;
      cand := sampleCount - 1;
      for i := 0 to sampleCount - 1 do
      begin
        pick := pick - dist2[i];
        if pick <= 0 then
        begin
          cand := i;
          Break;
        end;
      end;
      cent[j].R := samples[cand].R;
      cent[j].G := samples[cand].G;
      cent[j].B := samples[cand].B;
    end;

    SetLength(sumR, K);
    SetLength(sumG, K);
    SetLength(sumB, K);
    SetLength(cnt, K);

    // Lloyd iterations.
    for iter := 1 to MAX_ITERS do
    begin
      if Cancelled then begin cancelledFlag := True; Exit; end;
      for j := 0 to K - 1 do
      begin
        sumR[j] := 0;
        sumG[j] := 0;
        sumB[j] := 0;
        cnt[j] := 0;
      end;

      for i := 0 to sampleCount - 1 do
      begin
        if (i and 2047) = 0 then
          if Cancelled then begin cancelledFlag := True; Exit; end;
        bestIdx := 0;
        bestD := High(Int64);
        for j := 0 to K - 1 do
        begin
          dr := samples[i].R - Round(cent[j].R);
          dg := samples[i].G - Round(cent[j].G);
          db := samples[i].B - Round(cent[j].B);
          candDist := dr * dr + dg * dg + db * db;
          if candDist < bestD then
          begin
            bestD := candDist;
            bestIdx := j;
          end;
        end;
        assign[i] := bestIdx;
        sumR[bestIdx] := sumR[bestIdx] + samples[i].R;
        sumG[bestIdx] := sumG[bestIdx] + samples[i].G;
        sumB[bestIdx] := sumB[bestIdx] + samples[i].B;
        Inc(cnt[bestIdx]);
      end;

      for j := 0 to K - 1 do
      begin
        if cnt[j] <= 0 then
        begin
          cand := Integer(NextRand(seed) mod Cardinal(sampleCount));
          cent[j].R := samples[cand].R;
          cent[j].G := samples[cand].G;
          cent[j].B := samples[cand].B;
          Continue;
        end;
        cent[j].R := sumR[j] / cnt[j];
        cent[j].G := sumG[j] / cnt[j];
        cent[j].B := sumB[j] / cnt[j];
      end;
    end;

    SetLength(Result, K);
    for j := 0 to K - 1 do
    begin
      Result[j].R := ClampByte(Integer(Round(cent[j].R)));
      Result[j].G := ClampByte(Integer(Round(cent[j].G)));
      Result[j].B := ClampByte(Integer(Round(cent[j].B)));
    end;
  end;

  procedure QuantizeKMeansPP(targetColors: Integer);
  var
    pal: TRGB24Array;
  begin
    pal := BuildPaletteKMeansPP(targetColors);
    if cancelledFlag then Exit;
    QuantizeWithPalette(pal);
  end;

  procedure QuantizeAndDither;
  const
    Dos16: array[0..15] of TRGB24 = (
      (R:0;   G:0;   B:0),
      (R:0;   G:0;   B:170),
      (R:0;   G:170; B:0),
      (R:0;   G:170; B:170),
      (R:170; G:0;   B:0),
      (R:170; G:0;   B:170),
      (R:170; G:85;  B:0),
      (R:170; G:170; B:170),
      (R:85;  G:85;  B:85),
      (R:85;  G:85;  B:255),
      (R:85;  G:255; B:85),
      (R:85;  G:255; B:255),
      (R:255; G:85;  B:85),
      (R:255; G:85;  B:255),
      (R:255; G:255; B:85),
      (R:255; G:255; B:255)
    );
  begin
    if (quantMethod <= 0) then Exit;

    case quantMethod of
      1, 2, 3, 5, 6, 7:
        begin
          if (quantLevels < 2) or (quantLevels >= 256) then Exit; // 256 = "no quant"
          case quantMethod of
            1: QuantizeUniformRGB(quantLevels);
            2: QuantizeMedianCut(quantLevels);
            3: QuantizeOctree(quantLevels);
            5: QuantizePopularity(quantLevels);
            6: QuantizeWu(quantLevels);
            7: QuantizeKMeansPP(quantLevels);
          end;
        end;
      4:
        QuantizeWithPalette(Dos16);
    end;
  end;

begin
  Result := False;
  if not Assigned(Source) then Exit;
  if (Source.Width <= 0) or (Source.Height <= 0) then Exit;

  cancelledFlag := False;
  if Cancelled then Exit;

  rGain := Settings.RedPct / 100.0;
  gGain := Settings.GreenPct / 100.0;
  bGain := Settings.BluePct / 100.0;
  bright := Settings.Brightness;
  contrast := 1.0 + (Settings.Contrast / 100.0);
  gammaVal := Settings.GammaPct / 100.0;
  saturationPct := Settings.SaturationPct;
  hueDeg := Settings.HueDeg;
  midContrast := Settings.MidContrast;
  blurRadius := Settings.BlurRadius;
  sharpenAmt := Settings.SharpenAmt;
  clarityAmt := Settings.ClarityAmt;
  denoisePasses := Settings.DenoisePasses;
  chromaDenoiseAmt := Settings.ChromaDenoiseAmt;
  guidedAmt := Settings.GuidedAmt;
  edgeAmt := Settings.EdgeAmt;
  edgeStyle := Settings.EdgeStyle;
  bilateralAmt := Settings.BilateralAmt;
  ditherStyle := Settings.DitherStyle;
  dosBiasPct := Settings.DosBiasPct;
  autoContrast := Settings.AutoContrast;
  quantMethod := Settings.QuantMethod;
  quantLevels := Settings.QuantLevels;

  Dest.SetSize(Source.Width, Source.Height);
  Dest.PixelFormat := pf24bit;
  Dest.HandleType := bmDIB;
  Dest.Transparent := False;
  for yCopy := 0 to Dest.Height - 1 do
  begin
    if Cancelled then begin cancelledFlag := True; Exit(False); end;
    Move(Source.ScanLine[yCopy]^, Dest.ScanLine[yCopy]^, Dest.Width * 3);
  end;

    if autoContrast then
  begin
    AutoContrastStretch;
    if cancelledFlag then Exit(False);
  end;

  ToneAdjust;
  if cancelledFlag then Exit(False);

  HueAdjust;
  if cancelledFlag then Exit(False);

  SaturationAdjust;
  if cancelledFlag then Exit(False);

  MidtoneContrastAdjust;
  if cancelledFlag then Exit(False);

  if chromaDenoiseAmt > 0 then
  begin
    ChromaOnlyDenoise;
    if cancelledFlag then Exit(False);
  end;

  if guidedAmt > 0 then
  begin
    GuidedFilterLuma;
    if cancelledFlag then Exit(False);
  end;

  BiasToDos16Palette;
  if cancelledFlag then Exit(False);

  if blurRadius > 0 then
  begin
    BoxBlur(blurRadius);
    if cancelledFlag then Exit(False);
  end;

  if denoisePasses > 0 then
    for iPass := 1 to denoisePasses do
    begin
      Median3x3;
      if cancelledFlag then Exit(False);
    end;

  if bilateralAmt > 0 then
  begin
    BoxBlur(1); // placeholder for bilateral smoothing
    if cancelledFlag then Exit(False);
  end;

  if sharpenAmt > 0 then
  begin
    Unsharp(sharpenAmt, 1);
    if cancelledFlag then Exit(False);
  end;

  if clarityAmt > 0 then
  begin
    Unsharp(clarityAmt div 2, 0);
    if cancelledFlag then Exit(False);
  end;

  if (edgeAmt > 0) and (edgeStyle > 0) then
  begin
    EdgeProcess(edgeStyle, edgeAmt);
    if cancelledFlag then Exit(False);
  end;

  if quantMethod > 0 then
  begin
    QuantizeAndDither;
    if cancelledFlag then Exit(False);
  end;

  Result := not cancelledFlag;
end;

function BuildAnsiPreview(const Source: TBitmap; const Settings: TAnsiConvSettings;
  out Cells: TBytes; Preview: TBitmap; out OutCols, OutRows: Integer;
  CancelThread: TAnsiWorkerThread; out CellCost: TDoubleArray): Boolean;
  function Cancelled: Boolean;
  begin
    Result := Assigned(CancelThread) and CancelThread.CancelRequested;
  end;

  function ClampInt(v, lo, hi: Integer): Integer; inline;
  begin
    if v < lo then Exit(lo);
    if v > hi then Exit(hi);
    Result := v;
  end;

  function DistRedmeanSq(R1, G1, B1, R2, G2, B2: Integer): Double; inline;
  var
    rmean, dr, dg, db: Integer;
    wR, wB: Integer;
  begin
    rmean := (R1 + R2) shr 1;
    dr := R1 - R2;
    dg := G1 - G2;
    db := B1 - B2;

    // Weights scaled by 256 for integer math; returns a comparable "squared" distance.
    wR := 512 + rmean;         // (2 + rmean/256) * 256
    wB := 512 + (255 - rmean); // (2 + (255-rmean)/256) * 256

    Result := ((wR * dr * dr) / 256.0) + (4.0 * dg * dg) + ((wB * db * db) / 256.0);
  end;

  function SrgbToLinear(const C8: Integer): Double; inline;
  var
    c: Double;
  begin
    c := C8 / 255.0;
    if c <= 0.04045 then
      Result := c / 12.92
    else
      Result := Power((c + 0.055) / 1.055, 2.4);
  end;

  function Fxyz(const t: Double): Double; inline;
  const
    EPS = 216.0 / 24389.0; // (6/29)^3
    KAP = 24389.0 / 27.0;  // (29/3)^3
  begin
    if t > EPS then
      Result := Power(t, 1.0 / 3.0)
    else
      Result := (KAP * t + 16.0) / 116.0;
  end;

  procedure RgbToLab(const R8, G8, B8: Integer; out LVal, AVal, BVal: Double); inline;
  const
    REF_X = 0.95047;
    REF_Z = 1.08883;
  var
    Rlin, Glin, Blin: Double;
    Xr, Yr, Zr: Double;
    fx, fy, fz: Double;
  begin
    Rlin := SrgbToLinear(R8);
    Glin := SrgbToLinear(G8);
    Blin := SrgbToLinear(B8);

    // Linear sRGB -> XYZ (D65)
    Xr := (0.4124564 * Rlin + 0.3575761 * Glin + 0.1804375 * Blin) / REF_X;
    Yr := (0.2126729 * Rlin + 0.7151522 * Glin + 0.0721750 * Blin);
    Zr := (0.0193339 * Rlin + 0.1191920 * Glin + 0.9503041 * Blin) / REF_Z;

    fx := Fxyz(Xr);
    fy := Fxyz(Yr);
    fz := Fxyz(Zr);

    LVal := 116.0 * fy - 16.0;
    AVal := 500.0 * (fx - fy);
    BVal := 200.0 * (fy - fz);
  end;

  function DistRgbManhattanSq(R1, G1, B1, R2, G2, B2: Integer): Double; inline;
  var
    d: Integer;
  begin
    d := Abs(R1 - R2) + Abs(G1 - G2) + Abs(B1 - B2);
    Result := d * Double(d);
  end;

  function DeltaE94Sq(const L1, A1, B1, L2, A2, B2: Double): Double; inline;
  // CIE94 (graphic arts) squared distance in Lab space.
  var
    dL, dA, dB: Double;
    C1, C2, dC: Double;
    dH2: Double;
    SC, SH: Double;
    t: Double;
  begin
    dL := L1 - L2;
    dA := A1 - A2;
    dB := B1 - B2;

    C1 := Sqrt(A1 * A1 + B1 * B1);
    C2 := Sqrt(A2 * A2 + B2 * B2);
    dC := C1 - C2;
    dH2 := dA * dA + dB * dB - dC * dC;
    if dH2 < 0 then dH2 := 0;

    // kL=kC=kH=1, K1=0.045, K2=0.015
    SC := 1.0 + 0.045 * C1;
    SH := 1.0 + 0.015 * C1;

    t := (dL * dL) +
         (dC / SC) * (dC / SC) +
         (dH2 / (SH * SH));
    if t < 0 then t := 0;
    Result := t;
  end;

  function Pow7(const x: Double): Double; inline;
  begin
    Result := x * x * x * x * x * x * x;
  end;

  function DeltaE2000Sq(const L1, A1, B1, L2, A2, B2: Double): Double;
  // CIEDE2000 squared distance. Returns DeltaE00^2 to avoid a sqrt at call sites.
  const
    POW25_7 = 6103515625.0; // 25^7
  var
    C1, C2, Cbar, G: Double;
    a1p, a2p: Double;
    C1p, C2p, Cbarp: Double;
    h1p, h2p, hbarp: Double;
    dLp, dCp: Double;
    dhp: Double;
    Lbarp: Double;
    T: Double;
    dTheta: Double;
    Rc: Double;
    Sl, Sc, Sh: Double;
    Rt: Double;
    dLterm, dCterm, dHterm: Double;
    hpDiff: Double;
    tmp: Double;
  begin
    C1 := Sqrt(A1 * A1 + B1 * B1);
    C2 := Sqrt(A2 * A2 + B2 * B2);
    Cbar := (C1 + C2) * 0.5;

    tmp := Pow7(Cbar);
    if tmp <= 0 then
      G := 0.0
    else
      G := 0.5 * (1.0 - Sqrt(tmp / (tmp + POW25_7)));

    a1p := (1.0 + G) * A1;
    a2p := (1.0 + G) * A2;

    C1p := Sqrt(a1p * a1p + B1 * B1);
    C2p := Sqrt(a2p * a2p + B2 * B2);
    Cbarp := (C1p + C2p) * 0.5;

    if C1p <= 1e-12 then
      h1p := 0.0
    else
    begin
      h1p := ArcTan2(B1, a1p) * 180.0 / Pi;
      if h1p < 0.0 then h1p := h1p + 360.0;
    end;

    if C2p <= 1e-12 then
      h2p := 0.0
    else
    begin
      h2p := ArcTan2(B2, a2p) * 180.0 / Pi;
      if h2p < 0.0 then h2p := h2p + 360.0;
    end;

    dLp := L2 - L1;
    dCp := C2p - C1p;

    if (C1p * C2p) <= 1e-12 then
      dhp := 0.0
    else
    begin
      hpDiff := h2p - h1p;
      if hpDiff > 180.0 then hpDiff := hpDiff - 360.0
      else if hpDiff < -180.0 then hpDiff := hpDiff + 360.0;
      dhp := hpDiff;
    end;

    dHp := 2.0 * Sqrt(C1p * C2p) * Sin(DegToRad(dhp * 0.5));

    Lbarp := (L1 + L2) * 0.5;

    if (C1p * C2p) <= 1e-12 then
      hbarp := h1p + h2p
    else
    begin
      hpDiff := Abs(h1p - h2p);
      if hpDiff <= 180.0 then
        hbarp := (h1p + h2p) * 0.5
      else if (h1p + h2p) < 360.0 then
        hbarp := (h1p + h2p + 360.0) * 0.5
      else
        hbarp := (h1p + h2p - 360.0) * 0.5;
    end;

    T :=
      1.0
      - 0.17 * Cos(DegToRad(hbarp - 30.0))
      + 0.24 * Cos(DegToRad(2.0 * hbarp))
      + 0.32 * Cos(DegToRad(3.0 * hbarp + 6.0))
      - 0.20 * Cos(DegToRad(4.0 * hbarp - 63.0));

    dTheta := 30.0 * Exp(-Sqr((hbarp - 275.0) / 25.0));

    tmp := Pow7(Cbarp);
    if tmp <= 0 then
      Rc := 0.0
    else
      Rc := 2.0 * Sqrt(tmp / (tmp + POW25_7));

    Sl := 1.0 + (0.015 * Sqr(Lbarp - 50.0)) / Sqrt(20.0 + Sqr(Lbarp - 50.0));
    Sc := 1.0 + 0.045 * Cbarp;
    Sh := 1.0 + 0.015 * Cbarp * T;

    Rt := -Sin(DegToRad(2.0 * dTheta)) * Rc;

    dLterm := dLp / Sl;
    dCterm := dCp / Sc;
    dHterm := dHp / Sh;

    Result := dLterm * dLterm + dCterm * dCterm + dHterm * dHterm + Rt * dCterm * dHterm;
    if Result < 0.0 then Result := 0.0;
  end;

  procedure RgbToHsl(const R8, G8, B8: Integer; out H, S, L: Double); inline;
  var
    rf, gf, bf: Double;
    maxc, minc, delta: Double;
    hh: Double;
  begin
    rf := R8 / 255.0;
    gf := G8 / 255.0;
    bf := B8 / 255.0;

    maxc := rf; if gf > maxc then maxc := gf; if bf > maxc then maxc := bf;
    minc := rf; if gf < minc then minc := gf; if bf < minc then minc := bf;
    L := (maxc + minc) * 0.5;
    delta := maxc - minc;

    if delta <= 1e-12 then
    begin
      H := 0.0;
      S := 0.0;
      Exit;
    end;

    if L < 0.5 then
      S := delta / (maxc + minc)
    else
      S := delta / (2.0 - maxc - minc);

    if rf = maxc then
      hh := (gf - bf) / delta
    else if gf = maxc then
      hh := 2.0 + (bf - rf) / delta
    else
      hh := 4.0 + (rf - gf) / delta;

    H := hh * 60.0;
    if H < 0.0 then H := H + 360.0;
    if H >= 360.0 then H := H - 360.0;
  end;

  function HslDistSq(const H1, S1, L1, H2, S2, L2: Double; const Mode: Integer): Double; inline;
  var
    dh, ds, dl: Double;
    wH, wS, wL: Double;
    satFactor: Double;
  begin
    dh := Abs(H1 - H2);
    if dh > 180.0 then dh := 360.0 - dh;
    dh := dh / 180.0; // 0..1

    ds := Abs(S1 - S2);
    dl := Abs(L1 - L2);

    // Hue is unstable for near-gray colors; down-weight it as saturation drops.
    satFactor := Min(S1, S2);
    dh := dh * satFactor;

    if Mode = 7 then
    begin
      // Hue-first: hue heavy, lightness moderate, saturation light.
      wH := 6.0;
      wL := 2.0;
      wS := 0.75;
    end
    else
    begin
      // Weighted: still hue-heavy but more balanced.
      wH := 4.0;
      wL := 2.0;
      wS := 1.0;
    end;

    Result :=
      Sqr(dh * wH * 255.0) +
      Sqr(dl * wL * 255.0) +
      Sqr(ds * wS * 255.0);
  end;

  function HueLerp(const H1, H2, W: Double): Double; inline;
  // Interpolate hue along the shortest arc (degrees 0..360).
  var
    d, h: Double;
  begin
    d := H2 - H1;
    if d > 180.0 then d := d - 360.0
    else if d < -180.0 then d := d + 360.0;
    h := H1 + d * W;
    while h < 0.0 do h := h + 360.0;
    while h >= 360.0 do h := h - 360.0;
    Result := h;
  end;

  procedure BuildGlyphMask(glyph: Byte; sampleW, sampleH: Integer; var mask: array of Byte);
  var
    dx, dy: Integer;
    x0, x1, y0, y1: Integer;
    x, y: Integer;
    bits: Byte;
    ink, total: Integer;
    bitMask: Byte;
    begin
      if (sampleW <= 0) or (sampleH <= 0) then Exit;
      if Length(mask) < sampleW * sampleH then Exit;

    for dy := 0 to sampleH - 1 do
    begin
      y0 := (dy * 16) div sampleH;
      y1 := ((dy + 1) * 16) div sampleH - 1;
      if y1 < y0 then y1 := y0;
      for dx := 0 to sampleW - 1 do
      begin
        x0 := (dx * 8) div sampleW;
        x1 := ((dx + 1) * 8) div sampleW - 1;
        if x1 < x0 then x1 := x0;

        ink := 0;
        total := 0;
        for y := y0 to y1 do
        begin
          bits := DOS_FONT_8X16[Ord(glyph) * 16 + y];
          for x := x0 to x1 do
          begin
            bitMask := Byte(1 shl (7 - x));
            if (bits and bitMask) <> 0 then Inc(ink);
            Inc(total);
          end;
        end;

        // Store fractional coverage (0..255) instead of a binary mask.
        if total <= 0 then
          mask[dy * sampleW + dx] := 0
        else
          mask[dy * sampleW + dx] := Byte(ClampInt(Round(ink * 255.0 / total), 0, 255));
      end;
    end;
  end;

  function TutGlyphKind(const G: Byte): Integer; inline;
  // Classification tuned to the block/half-block/shade glyph set.
  begin
    case G of
      176, 177, 178: Exit(2);          // shaded fills
      219: Exit(3);                    // solid ink
      221, 222: Exit(4);               // vertical-ish half blocks (left/right)
      220, 223: Exit(5);               // horizontal-ish half blocks (upper/lower)
    else
      Exit(0);                         // generic/space
    end;
  end;

  function ClampByteI(v: Integer): Byte; inline;
  begin
    if v < 0 then Exit(0);
    if v > 255 then Exit(255);
    Result := Byte(v);
  end;

const
  // Heuristic weights for tutorial-inspired mode (base factors; scaled by learned knobs).
  TUT_EDGE_BONUS        = 60000.0;
  TUT_EDGE_PENALTY      = 80000.0;
  TUT_FLAT_BONUS        = 22000.0;
  TUT_BLOCK_BONUS       = 38000.0;
  TUT_HALF_PENALTY      = 12000.0;
  TUT_SHADE_EDGE_PEN    = 120000.0;
  TUT_SHADE_SAT_PEN     = 90000.0;
  TUT_SHADE_BONUS       = 24000.0;

var
  cols, rows: Integer;
  sampleW, sampleH, sampleN: Integer;
  sel: TRect;
  selW, selH: Integer;
  scaledW, scaledH: Integer;
  mapX: array of Integer;
  mapY: array of Integer;
  x, y: Integer;
  sx, sy: Integer;
  p: Integer;
  rowPtr: PByte;
  r, g, b: Integer;
  srcX, srcY: Integer;
  px, py: Integer;
  metric: Integer;
  needLab, needLin, needHsl: Boolean;
  i, j, pairCount: Integer;
  dr, dg: Integer;
  pixR, pixG, pixB, pixLum: array[0..7] of Byte;
  distPal: array[0..7,0..15] of Double;
  palL, palA, palB: array[0..15] of Double;
  sL, sA, sB: array[0..7] of Double;
  palLinR, palLinG, palLinB: array[0..15] of Double;
  sLinR, sLinG, sLinB: array[0..7] of Double;
  palHslH, palHslS, palHslL: array[0..15] of Double;
  sHslH, sHslS, sHslL: array[0..7] of Double;
  domLinR, domLinG, domLinB: Double;
  domH, domS, domHslL: Double;
  dL, dA, dBv: Double;
  glyphMasks: array of TBytes;
  gi: Integer;
  mask: TBytes;
  minMask, maxMask: Integer;
  w, invW: Double;
  maskV: Integer;
  mixR, mixG, mixB: Integer;
  mixL, mixA, mixLabB: Double;
  mixLinR, mixLinG, mixLinB: Double;
  mixH, mixS, mixHslL: Double;
  dbI: Integer;
  fg, bg: Integer;
  cost: Double;
  bestCost, glyphBestCost: Double;
  bestGlyph: Byte;
  bestFg, bestBg: Integer;
  glyphBestFg, glyphBestBg: Integer;
  attr: Byte;
  bgMax: Integer;
  bgStart, bgEnd: Integer;
  forcedBg: Integer;
  glyphRow, glyphCol: Integer;
  bits: Byte;
  dstRow: PByte;
  dstBase: Integer;
  fgRGB, bgRGB: TRGB24;
  sumR, sumG, sumB: Integer;
  avgR, avgG, avgB: Integer;
  sumLum: Integer;
  avgLum: Integer;
  maxC, minC: Integer;
  cellSat: Double;
  lumL, lumR, lumT, lumB: Integer;
  dxLum, dyLum: Integer;
  edgeStrength: Double;
  dominantIdx, dominantBase: Integer;
  bestDom: Double;
  domL, domA, domB: Double;
  shadePenalty, edgePenalty, orientPenalty, stabilityPenalty: Double;
  tutPenalty: Double;
  isShade, isHalf: Boolean;
  glyphCode: Byte;
  tutKind: Integer;
  bestGi: Integer;
  glyphCoverage: array of Double;
  sumMask: Integer;
  cov: Double;

  // ANSI-side options
  ditherStyle, ditherStrength: Integer;
  stabilityPct, edgeBiasPct: Integer;
  stabilityFactor, edgeFactor: Double;
  orderedDelta: Integer;
  biasMode, biasStrengthPct: Integer;
  lumBucketStrengthPct, lumBucketThreshold: Integer;
  chromaPenaltyPct: Integer;
  // Style-driven glyph/shading bias (affects shade vs half-block usage)
  styleId: Integer;
  tutMode: Boolean;
  shadeBasePenalty: Double;
  shadeEdgeMult, shadeFlatMult: Double;
  halfEdgeMult, halfFlatMult: Double;
  orientMult: Double;
  biasK, lumBucketK, chromaK: Double;
  palBiasW: array[0..15] of Double;
  palLum: array[0..15] of Byte;
  palScale: Double;
  satDiff: Double;
  blendLum, blendSat: Double;

  // Floyd-Steinberg error diffusion on the cell grid (stored scaled by 16)
  errCurR, errCurG, errCurB: array of Integer;
  errNextR, errNextG, errNextB: array of Integer;
  tmpErr: array of Integer;
  errIdx: Integer;
  deltaR, deltaG, deltaB: Integer;
  adjTargetR, adjTargetG, adjTargetB: Integer;
  diffR, diffG, diffB: Integer;
  renderR, renderG, renderB: Integer;
  grad: Integer;

  // Color stability (neighbor penalties)
  prevFgRow, prevBgRow: array of Integer;
  curFgRow, curBgRow: array of Integer;
  prevGlyphRow, curGlyphRow: array of Byte;
  tmpRow: array of Integer;
  tmpGlyphRow: array of Byte;

  function PalDistSq(c1, c2: Integer): Double; inline;
  var
    dr, dg, dbI: Integer;
    dLv, dAv, dBv: Double;
  begin
    if c1 = c2 then Exit(0.0);
    case metric of
      2:
        begin
          dLv := palL[c1] - palL[c2];
          dAv := palA[c1] - palA[c2];
          dBv := palB[c1] - palB[c2];
          Result := dLv*dLv + dAv*dAv + dBv*dBv;
        end;
      5:
        Result := DeltaE94Sq(palL[c1], palA[c1], palB[c1], palL[c2], palA[c2], palB[c2]);
      6:
        Result := DeltaE2000Sq(palL[c1], palA[c1], palB[c1], palL[c2], palA[c2], palB[c2]);
      1:
        Result := DistRedmeanSq(
          DOS16_PALETTE[c1].R, DOS16_PALETTE[c1].G, DOS16_PALETTE[c1].B,
          DOS16_PALETTE[c2].R, DOS16_PALETTE[c2].G, DOS16_PALETTE[c2].B
        );
      3:
        Result := DistRgbManhattanSq(
          DOS16_PALETTE[c1].R, DOS16_PALETTE[c1].G, DOS16_PALETTE[c1].B,
          DOS16_PALETTE[c2].R, DOS16_PALETTE[c2].G, DOS16_PALETTE[c2].B
        );
      4:
        begin
          dLv := palLinR[c1] - palLinR[c2];
          dAv := palLinG[c1] - palLinG[c2];
          dBv := palLinB[c1] - palLinB[c2];
          Result := dLv*dLv + dAv*dAv + dBv*dBv;
        end;
      7, 8:
        Result := HslDistSq(
          palHslH[c1], palHslS[c1], palHslL[c1],
          palHslH[c2], palHslS[c2], palHslL[c2],
          metric
        );
    else
      begin
        dr := Integer(DOS16_PALETTE[c1].R) - DOS16_PALETTE[c2].R;
        dg := Integer(DOS16_PALETTE[c1].G) - DOS16_PALETTE[c2].G;
        dbI := Integer(DOS16_PALETTE[c1].B) - DOS16_PALETTE[c2].B;
        Result := dr*dr + dg*dg + dbI*dbI;
      end;
    end;
  end;
begin
  Result := False;
  OutCols := 0;
  OutRows := 0;
  Cells := nil;
  if not Assigned(Source) then Exit;
  if (Source.Width <= 0) or (Source.Height <= 0) then Exit;
  if not Assigned(Preview) then Exit;

  // Clamp conversion size (keeps the preview responsive and matches save limits).
  cols := ClampInt(Settings.Cols, 1, 320);
  rows := ClampInt(Settings.Rows, 1, 320);

  sampleW := 2;
  case Settings.SampleMode of
    0: sampleH := 2;
    1: sampleH := 3;
    2: sampleH := 4;
  else
    sampleH := 4;
  end;
  sampleN := sampleW * sampleH;
  if sampleN > (High(pixR) + 1) then sampleN := High(pixR) + 1;

  bgMax := 7;
  if Settings.IceColors then
    bgMax := 15;
  bgStart := 0;
  bgEnd := bgMax;
  forcedBg := 0;
  if Settings.ForceBg then
  begin
    forcedBg := ClampInt(Settings.ForceBgColor, 0, bgMax);
    bgStart := forcedBg;
    bgEnd := forcedBg;
  end;

  metric := ClampInt(Settings.ColorMetric, 0, 8);
  biasMode := ClampInt(Settings.BiasMode, 0, 4);
  biasStrengthPct := ClampInt(Settings.BiasStrength, 0, 100);
  lumBucketStrengthPct := ClampInt(Settings.LumBucketStrength, 0, 100);
  lumBucketThreshold := ClampInt(Settings.LumBucketThreshold, 0, 255);
    chromaPenaltyPct := ClampInt(Settings.ChromaPenaltyPct, 0, 100);

  styleId := ClampInt(Settings.StyleId, 0, 5);

  // Style-driven shading behavior:
  //  - Scene: "artpack" vibe (more shade blocks / heavier ramps)
  //  - Toon: mostly solid blocks + crisp shadow steps (minimize 176/177/178)
  //  - Tutorial: classic tutor look (block-dominant, half-block curves, minimal shade on flats)
  shadeBasePenalty := 0.0;
  shadeEdgeMult := 1.0;
  shadeFlatMult := 1.0;
  halfEdgeMult := 1.0;
  halfFlatMult := 1.0;
  orientMult := 1.0;

  case styleId of
    1: begin // Scene
      shadeBasePenalty := -4000.0;
      shadeEdgeMult := 0.95;
      shadeFlatMult := 1.80;
      halfEdgeMult := 0.90;
      halfFlatMult := 1.20;
      orientMult := 0.95;
    end;
    2: begin // Toon
      // Strongly discourage shade glyphs; rely on solid blocks + half blocks for "shadow steps".
      shadeBasePenalty := 65000.0;
      shadeEdgeMult := 1.25;
      shadeFlatMult := 0.25;
      halfEdgeMult := 1.05;
      halfFlatMult := 0.45;
      orientMult := 1.20;
    end;
    5: begin // Tutorial style bias
      shadeBasePenalty := FTutShadeBasePenalty;
      shadeEdgeMult := FTutShadeEdgeMult;
      shadeFlatMult := FTutShadeFlatMult;
      halfEdgeMult := FTutHalfEdgeMult;
      halfFlatMult := FTutHalfFlatMult;
      orientMult := FTutOrientMult;
    end;
  end;

  tutMode := styleId = 5;
  if tutMode and (not Settings.ForceBg) then
  begin
    // Classic ANSI tutorials are usually drawn on black.
    bgStart := ClampInt(FTutForceBgColor, 0, bgMax);
    bgEnd := bgStart;
    forcedBg := bgStart;
  end;

  needLab := (metric = 2) or (metric = 5) or (metric = 6);
  needLin := (metric = 4);
  needHsl := (metric = 7) or (metric = 8) or (chromaPenaltyPct > 0);

  if needLab then
    for i := 0 to 15 do
      RgbToLab(DOS16_PALETTE[i].R, DOS16_PALETTE[i].G, DOS16_PALETTE[i].B, palL[i], palA[i], palB[i]);

  if needLin then
    for i := 0 to 15 do
    begin
      palLinR[i] := SrgbToLinear(DOS16_PALETTE[i].R) * 255.0;
      palLinG[i] := SrgbToLinear(DOS16_PALETTE[i].G) * 255.0;
      palLinB[i] := SrgbToLinear(DOS16_PALETTE[i].B) * 255.0;
    end;

  if needHsl then
    for i := 0 to 15 do
      RgbToHsl(DOS16_PALETTE[i].R, DOS16_PALETTE[i].G, DOS16_PALETTE[i].B, palHslH[i], palHslS[i], palHslL[i]);

  // Perceptual luma for palette colors (same weights as we use for samples).
  for i := 0 to 15 do
    palLum[i] := Byte((DOS16_PALETTE[i].R * 54 + DOS16_PALETTE[i].G * 183 + DOS16_PALETTE[i].B * 19) shr 8);

  // Metric-scaled constants for advanced scoring knobs.
  palScale := 0.0;
  pairCount := 0;
  for i := 0 to 15 do
    for j := i + 1 to 15 do
    begin
      palScale := palScale + PalDistSq(i, j);
      Inc(pairCount);
    end;
  if pairCount > 0 then palScale := palScale / pairCount else palScale := 1.0;
  if palScale < 1.0 then palScale := 1.0;

  // Bias weights (positive values are preferred => cost reduced; negative => penalized).
  for i := 0 to 15 do
    palBiasW[i] := 0.0;
  case biasMode of
    1: // Prefer dark
      for i := 0 to 15 do
        if (i and 8) = 0 then palBiasW[i] := 1.0;
    2: // Prefer bright
      for i := 0 to 15 do
        if (i and 8) <> 0 then palBiasW[i] := 1.0;
    3: // Prefer grays
      begin
        palBiasW[0] := 1.0;
        palBiasW[8] := 1.0;
        palBiasW[7] := 1.0;
        palBiasW[15] := 1.0;
      end;
    4: // Penalize pure black/white
      begin
        palBiasW[0] := -1.0;
        palBiasW[15] := -1.0;
      end;
  end;

  biasK := palScale * (biasStrengthPct / 100.0) * 0.01;
  lumBucketK := palScale * (lumBucketStrengthPct / 100.0) * 0.02;
  chromaK := palScale * (chromaPenaltyPct / 100.0) * 0.04;

  // Precompute glyph masks for this sampling mode (fixed block/shade set).
  SetLength(glyphMasks, Length(AREZ_GLYPHS));
  SetLength(glyphCoverage, Length(AREZ_GLYPHS));
  for gi := 0 to High(AREZ_GLYPHS) do
  begin
    SetLength(glyphMasks[gi], sampleN);
    FillChar(glyphMasks[gi][0], sampleN, 0);
    BuildGlyphMask(AREZ_GLYPHS[gi], sampleW, sampleH, glyphMasks[gi]);

    sumMask := 0;
    for p := 0 to sampleN - 1 do
      Inc(sumMask, glyphMasks[gi][p]);
    glyphCoverage[gi] := sumMask / (sampleN * 255.0);
  end;

  // clamp selection (Right/Bottom exclusive)
  sel := Settings.Sel;
  sel.Left := ClampInt(sel.Left, 0, Source.Width);
  sel.Top := ClampInt(sel.Top, 0, Source.Height);
  sel.Right := ClampInt(sel.Right, 0, Source.Width);
  sel.Bottom := ClampInt(sel.Bottom, 0, Source.Height);
  if (sel.Right <= sel.Left) or (sel.Bottom <= sel.Top) then
    sel := Rect(0, 0, Source.Width, Source.Height);

  selW := Max(1, sel.Right - sel.Left);
  selH := Max(1, sel.Bottom - sel.Top);

  scaledW := cols * sampleW;
  scaledH := rows * sampleH;
  if scaledW <= 0 then scaledW := 1;
  if scaledH <= 0 then scaledH := 1;

  // Precompute source coordinate for each sample point (nearest-neighbor at the
  // center of each sample cell). This avoids using Canvas in the worker thread.
  SetLength(mapX, scaledW);
  for px := 0 to scaledW - 1 do
    mapX[px] := sel.Left + ClampInt((px * selW + (scaledW div 2)) div scaledW, 0, selW - 1);
  SetLength(mapY, scaledH);
  for py := 0 to scaledH - 1 do
    mapY[py] := sel.Top + ClampInt((py * selH + (scaledH div 2)) div scaledH, 0, selH - 1);

  SetLength(Cells, cols * rows * 2);
  SetLength(CellCost, cols * rows);
  Preview.PixelFormat := pf24bit;
  Preview.HandleType := bmDIB;
  Preview.Transparent := False;
  Preview.SetSize(cols * 8, rows * 16);

  // ANSI-side options
  ditherStyle := ClampInt(Settings.DitherStyle, 0, 2);
  ditherStrength := ClampInt(Settings.DitherStrength, 0, 100);
  if (ditherStyle = 0) or (ditherStrength <= 0) then
    ditherStyle := 0;

  stabilityPct := ClampInt(Settings.StabilityPct, 0, 100);
  stabilityFactor := stabilityPct / 100.0;

  edgeBiasPct := ClampInt(Settings.EdgeBiasPct, 0, 100);
  edgeFactor := edgeBiasPct / 50.0; // 50 = "normal", 0 disables edge heuristics

  // Track neighbor colors for stability penalties.
  SetLength(prevFgRow, cols);
  SetLength(prevBgRow, cols);
  SetLength(curFgRow, cols);
  SetLength(curBgRow, cols);
  SetLength(prevGlyphRow, cols);
  SetLength(curGlyphRow, cols);
  for i := 0 to cols - 1 do
  begin
    prevFgRow[i] := 7;
    prevBgRow[i] := bgStart;
    curFgRow[i] := 7;
    curBgRow[i] := bgStart;
    prevGlyphRow[i] := 32;
    curGlyphRow[i] := 32;
  end;

  // Cell-grid dithering (Floyd-Steinberg)
  if ditherStyle = 2 then
  begin
    SetLength(errCurR, cols + 2);
    SetLength(errCurG, cols + 2);
    SetLength(errCurB, cols + 2);
    SetLength(errNextR, cols + 2);
    SetLength(errNextG, cols + 2);
    SetLength(errNextB, cols + 2);

    FillChar(errCurR[0], Length(errCurR) * SizeOf(errCurR[0]), 0);
    FillChar(errCurG[0], Length(errCurG) * SizeOf(errCurG[0]), 0);
    FillChar(errCurB[0], Length(errCurB) * SizeOf(errCurB[0]), 0);
    FillChar(errNextR[0], Length(errNextR) * SizeOf(errNextR[0]), 0);
    FillChar(errNextG[0], Length(errNextG) * SizeOf(errNextG[0]), 0);
    FillChar(errNextB[0], Length(errNextB) * SizeOf(errNextB[0]), 0);
  end;

  for y := 0 to rows - 1 do
  begin
    if Cancelled then Exit(False);

    if ditherStyle = 2 then
    begin
      FillChar(errNextR[0], Length(errNextR) * SizeOf(errNextR[0]), 0);
      FillChar(errNextG[0], Length(errNextG) * SizeOf(errNextG[0]), 0);
      FillChar(errNextB[0], Length(errNextB) * SizeOf(errNextB[0]), 0);
    end;

    for x := 0 to cols - 1 do
    begin
      // Extra cancellation points so a new request stops quickly while crunching.
      if ((x and 7) = 0) and Cancelled then Exit(False);
      // sample pixels for this cell directly from the selected source region
      p := 0;
      sumR := 0;
      sumG := 0;
      sumB := 0;
      sumLum := 0;
      for sy := 0 to sampleH - 1 do
      begin
        if Cancelled then Exit(False);
        srcY := mapY[y * sampleH + sy];
        rowPtr := Source.ScanLine[srcY];
        for sx := 0 to sampleW - 1 do
        begin
          srcX := mapX[x * sampleW + sx];
          b := rowPtr[srcX * 3 + 0];
          g := rowPtr[srcX * 3 + 1];
          r := rowPtr[srcX * 3 + 2];
          pixR[p] := r;
          pixG[p] := g;
          pixB[p] := b;
          // Perceptual luma (Rec.709-ish) for edge/brightness heuristics.
          // Integer weights sum to 256: 54/256=0.2109, 183/256=0.7148, 19/256=0.0742.
          pixLum[p] := Byte((r * 54 + g * 183 + b * 19) shr 8);
          Inc(sumR, r);
          Inc(sumG, g);
          Inc(sumB, b);
          Inc(sumLum, pixLum[p]);
          Inc(p);
        end;
      end;

      // Cell-level stats for shading heuristics.
      avgR := sumR div sampleN;
      avgG := sumG div sampleN;
      avgB := sumB div sampleN;
      avgLum := sumLum div sampleN;
      maxC := Max(avgR, Max(avgG, avgB));
      minC := Min(avgR, Min(avgG, avgB));
      if maxC <= 0 then
        cellSat := 0.0
      else
        cellSat := (maxC - minC) / maxC; // 0..1

      // Edge strength estimate from the 2xN sample grid.
      // Use sum-of-abs deltas (more robust on diagonals than "difference of averages").
      dxLum := 0;
      for sy := 0 to sampleH - 1 do
      begin
        lumL := pixLum[sy * sampleW + 0];
        lumR := pixLum[sy * sampleW + 1];
        dxLum := dxLum + Abs(lumL - lumR);
      end;
      dxLum := dxLum div sampleH; // 0..255

      dyLum := 0;
      if sampleH > 1 then
      begin
        for sy := 0 to sampleH - 2 do
        begin
          lumT := (pixLum[sy * sampleW + 0] + pixLum[sy * sampleW + 1]) div 2;
          lumB := (pixLum[(sy + 1) * sampleW + 0] + pixLum[(sy + 1) * sampleW + 1]) div 2;
          dyLum := dyLum + Abs(lumT - lumB);
        end;
        dyLum := dyLum div (sampleH - 1); // 0..255
      end;

      edgeStrength := Max(dxLum, dyLum) / 255.0; // 0..1

      // Dominant base palette index (0..7) from the average cell color.
      dominantIdx := 0;
      bestDom := 1.0e100;
      case metric of
        2:
          begin
            RgbToLab(avgR, avgG, avgB, domL, domA, domB);
            for i := 0 to 15 do
            begin
              dL := domL - palL[i];
              dA := domA - palA[i];
              dBv := domB - palB[i];
              cost := dL*dL + dA*dA + dBv*dBv;
              if cost < bestDom then
              begin
                bestDom := cost;
                dominantIdx := i;
              end;
            end;
          end;
        5:
          begin
            RgbToLab(avgR, avgG, avgB, domL, domA, domB);
            for i := 0 to 15 do
            begin
              cost := DeltaE94Sq(domL, domA, domB, palL[i], palA[i], palB[i]);
              if cost < bestDom then
              begin
                bestDom := cost;
                dominantIdx := i;
              end;
            end;
          end;
        6:
          begin
            RgbToLab(avgR, avgG, avgB, domL, domA, domB);
            for i := 0 to 15 do
            begin
              cost := DeltaE2000Sq(domL, domA, domB, palL[i], palA[i], palB[i]);
              if cost < bestDom then
              begin
                bestDom := cost;
                dominantIdx := i;
              end;
            end;
          end;
        1:
          begin
            for i := 0 to 15 do
            begin
              cost := DistRedmeanSq(avgR, avgG, avgB, DOS16_PALETTE[i].R, DOS16_PALETTE[i].G, DOS16_PALETTE[i].B);
              if cost < bestDom then
              begin
                bestDom := cost;
                dominantIdx := i;
              end;
            end;
          end;
        3:
          begin
            for i := 0 to 15 do
            begin
              cost := DistRgbManhattanSq(avgR, avgG, avgB, DOS16_PALETTE[i].R, DOS16_PALETTE[i].G, DOS16_PALETTE[i].B);
              if cost < bestDom then
              begin
                bestDom := cost;
                dominantIdx := i;
              end;
            end;
          end;
        4:
          begin
            domLinR := SrgbToLinear(avgR) * 255.0;
            domLinG := SrgbToLinear(avgG) * 255.0;
            domLinB := SrgbToLinear(avgB) * 255.0;
            for i := 0 to 15 do
            begin
              dL := domLinR - palLinR[i];
              dA := domLinG - palLinG[i];
              dBv := domLinB - palLinB[i];
              cost := dL*dL + dA*dA + dBv*dBv;
              if cost < bestDom then
              begin
                bestDom := cost;
                dominantIdx := i;
              end;
            end;
          end;
        7, 8:
          begin
            RgbToHsl(avgR, avgG, avgB, domH, domS, domHslL);
            for i := 0 to 15 do
            begin
              cost := HslDistSq(domH, domS, domHslL, palHslH[i], palHslS[i], palHslL[i], metric);
              if cost < bestDom then
              begin
                bestDom := cost;
                dominantIdx := i;
              end;
            end;
          end;
      else
        begin
          for i := 0 to 15 do
          begin
            dr := avgR - DOS16_PALETTE[i].R;
            dg := avgG - DOS16_PALETTE[i].G;
            dbI := avgB - DOS16_PALETTE[i].B;
            cost := dr*dr + dg*dg + dbI*dbI;
            if cost < bestDom then
            begin
              bestDom := cost;
              dominantIdx := i;
            end;
          end;
        end;
      end;
      dominantBase := dominantIdx and 7;

      // ANSI-side dithering: adjust the target samples before we solve fg/bg/glyph.
      deltaR := 0;
      deltaG := 0;
      deltaB := 0;
      adjTargetR := avgR;
      adjTargetG := avgG;
      adjTargetB := avgB;

      if ditherStyle = 1 then
      begin
        // Ordered dither on luma (applied to all channels equally).
        orderedDelta := Round((BAYER4X4[y and 3, x and 3] - 7) * (ditherStrength / 100.0) * 2.0);
        deltaR := orderedDelta;
        deltaG := orderedDelta;
        deltaB := orderedDelta;
      end
      else if ditherStyle = 2 then
      begin
        // Floyd-Steinberg: apply accumulated error for this cell (error arrays are scaled by 16).
        errIdx := x + 1;
        deltaR := errCurR[errIdx] div 16;
        deltaG := errCurG[errIdx] div 16;
        deltaB := errCurB[errIdx] div 16;
      end;

      if ditherStyle <> 0 then
      begin
        adjTargetR := ClampInt(avgR + deltaR, 0, 255);
        adjTargetG := ClampInt(avgG + deltaG, 0, 255);
        adjTargetB := ClampInt(avgB + deltaB, 0, 255);
        deltaR := adjTargetR - avgR;
        deltaG := adjTargetG - avgG;
        deltaB := adjTargetB - avgB;
        for p := 0 to sampleN - 1 do
        begin
          pixR[p] := ClampByteI(Integer(pixR[p]) + deltaR);
          pixG[p] := ClampByteI(Integer(pixG[p]) + deltaG);
          pixB[p] := ClampByteI(Integer(pixB[p]) + deltaB);
        end;
      end;

      // Precompute distances from each sample point to each DOS16 palette color.
      for p := 0 to sampleN - 1 do
      begin
        if needLab then
          RgbToLab(pixR[p], pixG[p], pixB[p], sL[p], sA[p], sB[p]);
        if needLin then
        begin
          sLinR[p] := SrgbToLinear(pixR[p]) * 255.0;
          sLinG[p] := SrgbToLinear(pixG[p]) * 255.0;
          sLinB[p] := SrgbToLinear(pixB[p]) * 255.0;
        end;
        if needHsl then
          RgbToHsl(pixR[p], pixG[p], pixB[p], sHslH[p], sHslS[p], sHslL[p]);

        for i := 0 to 15 do
        begin
          case metric of
            2:
              begin
                dL := sL[p] - palL[i];
                dA := sA[p] - palA[i];
                dBv := sB[p] - palB[i];
                distPal[p][i] := dL*dL + dA*dA + dBv*dBv;
              end;
            5:
              distPal[p][i] := DeltaE94Sq(sL[p], sA[p], sB[p], palL[i], palA[i], palB[i]);
            6:
              distPal[p][i] := DeltaE2000Sq(sL[p], sA[p], sB[p], palL[i], palA[i], palB[i]);
            1:
              distPal[p][i] := DistRedmeanSq(pixR[p], pixG[p], pixB[p],
                DOS16_PALETTE[i].R, DOS16_PALETTE[i].G, DOS16_PALETTE[i].B);
            3:
              distPal[p][i] := DistRgbManhattanSq(pixR[p], pixG[p], pixB[p],
                DOS16_PALETTE[i].R, DOS16_PALETTE[i].G, DOS16_PALETTE[i].B);
            4:
              begin
                dL := sLinR[p] - palLinR[i];
                dA := sLinG[p] - palLinG[i];
                dBv := sLinB[p] - palLinB[i];
                distPal[p][i] := dL*dL + dA*dA + dBv*dBv;
              end;
            7, 8:
              distPal[p][i] := HslDistSq(sHslH[p], sHslS[p], sHslL[p],
                palHslH[i], palHslS[i], palHslL[i], metric);
          else
              begin
                dr := Integer(pixR[p]) - DOS16_PALETTE[i].R;
                dg := Integer(pixG[p]) - DOS16_PALETTE[i].G;
                dbI := Integer(pixB[p]) - DOS16_PALETTE[i].B;
                distPal[p][i] := dr*dr + dg*dg + dbI*dbI;
              end;
          end;

          // Advanced scoring knobs: luminance bucketing, chroma penalty, and palette bias.
          if (lumBucketK > 0.0) and
             ((pixLum[p] >= lumBucketThreshold) <> (palLum[i] >= lumBucketThreshold)) then
            distPal[p][i] := distPal[p][i] + lumBucketK;

          if (chromaK > 0.0) then
          begin
            satDiff := sHslS[p] - palHslS[i];
            distPal[p][i] := distPal[p][i] + chromaK * (satDiff * satDiff);
          end;

          if biasK <> 0.0 then
            distPal[p][i] := distPal[p][i] - biasK * palBiasW[i];
        end;
      end;

      bestCost := 1.0e100;
      bestGlyph := 32;
      bestFg := 7;
      bestBg := bgStart;
      bestGi := 0;

      for gi := 0 to High(AREZ_GLYPHS) do
      begin
        glyphCode := AREZ_GLYPHS[gi];
        mask := glyphMasks[gi];
        minMask := 255;
        maxMask := 0;

        for p := 0 to sampleN - 1 do
        begin
          if mask[p] < minMask then minMask := mask[p];
          if mask[p] > maxMask then maxMask := mask[p];
        end;

        glyphBestCost := 1.0e100;
        glyphBestFg := 7;
        glyphBestBg := 0;

        isShade := (glyphCode = 176) or (glyphCode = 177) or (glyphCode = 178);
        isHalf := (glyphCode = 220) or (glyphCode = 223) or (glyphCode = 221) or (glyphCode = 222);

        if (maxMask = 0) then
        begin
          // All background.
          glyphBestCost := 1.0e100;
          glyphBestBg := bgStart;
          for bg := bgStart to bgEnd do
          begin
            if Cancelled then Exit(False);
            cost := 0.0;
            for p := 0 to sampleN - 1 do
              cost := cost + distPal[p][bg];

            if stabilityFactor > 0.0 then
            begin
              stabilityPenalty := 0.0;
              if x > 0 then
                stabilityPenalty := stabilityPenalty + (PalDistSq(bg, curBgRow[x - 1]) * 0.25);
              if y > 0 then
                stabilityPenalty := stabilityPenalty + (PalDistSq(bg, prevBgRow[x]) * 0.18);
              cost := cost + stabilityPenalty * stabilityFactor;
            end;

            if cost < glyphBestCost then
            begin
              glyphBestCost := cost;
              glyphBestBg := bg;
            end;
          end;
          glyphBestFg := 7;
        end
        else if (minMask = 255) then
        begin
          // All foreground.
          glyphBestCost := 1.0e100;
          glyphBestFg := 0;
          for fg := 0 to 15 do
          begin
            cost := 0.0;
            for p := 0 to sampleN - 1 do
              cost := cost + distPal[p][fg];

            if stabilityFactor > 0.0 then
            begin
              stabilityPenalty := 0.0;
              if x > 0 then
                stabilityPenalty := stabilityPenalty + (PalDistSq(fg, curFgRow[x - 1]) * 0.12);
              if y > 0 then
                stabilityPenalty := stabilityPenalty + (PalDistSq(fg, prevFgRow[x]) * 0.08);
              cost := cost + stabilityPenalty * stabilityFactor;
            end;

            if cost < glyphBestCost then
            begin
              glyphBestCost := cost;
              glyphBestFg := fg;
            end;
          end;
          glyphBestBg := bgStart;
        end
        else
        begin
          for fg := 0 to 15 do
            for bg := bgStart to bgEnd do
              if fg <> bg then
              begin
                // Mixed glyph: match each sample against the effective blended color.
                cost := 0.0;
                for p := 0 to sampleN - 1 do
                begin
                  maskV := mask[p];
                  if maskV = 0 then
                    cost := cost + distPal[p][bg]
                  else if maskV = 255 then
                    cost := cost + distPal[p][fg]
                  else
                  begin
                    w := maskV / 255.0;
                    invW := 1.0 - w;

                    case metric of
                      2:
                        begin
                          mixL := palL[bg] * invW + palL[fg] * w;
                          mixA := palA[bg] * invW + palA[fg] * w;
                          mixLabB := palB[bg] * invW + palB[fg] * w;
                          dL := sL[p] - mixL;
                          dA := sA[p] - mixA;
                          dBv := sB[p] - mixLabB;
                          cost := cost + (dL*dL + dA*dA + dBv*dBv);
                        end;
                      5:
                        begin
                          mixL := palL[bg] * invW + palL[fg] * w;
                          mixA := palA[bg] * invW + palA[fg] * w;
                          mixLabB := palB[bg] * invW + palB[fg] * w;
                          cost := cost + DeltaE94Sq(sL[p], sA[p], sB[p], mixL, mixA, mixLabB);
                        end;
                      6:
                        begin
                          mixL := palL[bg] * invW + palL[fg] * w;
                          mixA := palA[bg] * invW + palA[fg] * w;
                          mixLabB := palB[bg] * invW + palB[fg] * w;
                          cost := cost + DeltaE2000Sq(sL[p], sA[p], sB[p], mixL, mixA, mixLabB);
                        end;
                      4:
                        begin
                          mixLinR := palLinR[bg] * invW + palLinR[fg] * w;
                          mixLinG := palLinG[bg] * invW + palLinG[fg] * w;
                          mixLinB := palLinB[bg] * invW + palLinB[fg] * w;
                          dL := sLinR[p] - mixLinR;
                          dA := sLinG[p] - mixLinG;
                          dBv := sLinB[p] - mixLinB;
                          cost := cost + (dL*dL + dA*dA + dBv*dBv);
                        end;
                      7, 8:
                        begin
                          mixH := HueLerp(palHslH[bg], palHslH[fg], w);
                          mixS := palHslS[bg] * invW + palHslS[fg] * w;
                          mixHslL := palHslL[bg] * invW + palHslL[fg] * w;
                          cost := cost + HslDistSq(sHslH[p], sHslS[p], sHslL[p], mixH, mixS, mixHslL, metric);
                        end;
                    else
                        begin
                          // Integer blend in RGB space (DOS16 palette is sRGB-ish already).
                          mixR := (DOS16_PALETTE[bg].R * (255 - maskV) + DOS16_PALETTE[fg].R * maskV + 127) div 255;
                          mixG := (DOS16_PALETTE[bg].G * (255 - maskV) + DOS16_PALETTE[fg].G * maskV + 127) div 255;
                          mixB := (DOS16_PALETTE[bg].B * (255 - maskV) + DOS16_PALETTE[fg].B * maskV + 127) div 255;
                          case metric of
                            1:
                              cost := cost + DistRedmeanSq(pixR[p], pixG[p], pixB[p], mixR, mixG, mixB);
                            3:
                              cost := cost + DistRgbManhattanSq(pixR[p], pixG[p], pixB[p], mixR, mixG, mixB);
                          else
                              begin
                                dr := Integer(pixR[p]) - mixR;
                                dg := Integer(pixG[p]) - mixG;
                                dbI := Integer(pixB[p]) - mixB;
                                cost := cost + dr*dr + dg*dg + dbI*dbI;
                              end;
                          end;
                        end;
                    end;

                    // Advanced scoring knobs for blended colors (match the same logic used in distPal[]).
                    if (lumBucketK > 0.0) then
                    begin
                      blendLum := palLum[bg] * invW + palLum[fg] * w;
                      if ((pixLum[p] >= lumBucketThreshold) <> (blendLum >= lumBucketThreshold)) then
                        cost := cost + lumBucketK;
                    end;

                    if (chromaK > 0.0) then
                    begin
                      blendSat := palHslS[bg] * invW + palHslS[fg] * w;
                      satDiff := sHslS[p] - blendSat;
                      cost := cost + chromaK * (satDiff * satDiff);
                    end;

                    if biasK <> 0.0 then
                      cost := cost - biasK * (palBiasW[bg] * invW + palBiasW[fg] * w);
                  end;
                end;

                // Penalize rapid color changes between neighboring cells.
                stabilityPenalty := 0.0;
                if stabilityFactor > 0.0 then
                begin
                  if x > 0 then
                    stabilityPenalty := stabilityPenalty +
                      (PalDistSq(fg, curFgRow[x - 1]) * 0.12) +
                      (PalDistSq(bg, curBgRow[x - 1]) * 0.25);
                  if y > 0 then
                    stabilityPenalty := stabilityPenalty +
                      (PalDistSq(fg, prevFgRow[x]) * 0.08) +
                      (PalDistSq(bg, prevBgRow[x]) * 0.18);
                  cost := cost + stabilityPenalty * stabilityFactor;
                end;

                // Heuristics:
                // - Prefer half-blocks on strong edges (avoid dithered shade patterns at edges).
                // - Prefer shade blocks inside regions; bias shade blocks toward same-hue (base) fg/bg,
                //   with fg bright and bg dark for saturated colors.
                shadePenalty := 0.0;
                edgePenalty := 0.0;
                orientPenalty := 0.0;
                tutPenalty := 0.0;
                tutPenalty := 0.0;

                if isShade then
                begin
                  // discourage shade blocks right on strong edges
                  if edgeStrength > 0.25 then
                    edgePenalty := (edgeStrength - 0.25) * 120000.0 * edgeFactor * shadeEdgeMult;

                  // Crush near-black: avoid "dither-black" shade patterns, prefer true black.
                  // Use an absolute chroma test (max-min) so tiny tinted noise near black still crushes.
                  if (avgLum < 32) and ((maxC - minC) < 24) then
                    shadePenalty := shadePenalty + (32 - avgLum) * 6000.0;

                  // inside flatter regions (not near-black), slightly prefer shade blocks over hard half-block steps
                  if (avgLum >= 32) and (edgeStrength < 0.18) then
                    shadePenalty := shadePenalty - (0.18 - edgeStrength) * 30000.0 * shadeFlatMult;

                  // for saturated colors (and not strong edges), bias toward a single base color pair
                  if (cellSat > 0.25) and (edgeStrength < 0.22) then
                  begin
                    if ((fg and 7) <> dominantBase) then
                      shadePenalty := shadePenalty + 50000.0 * cellSat;
                    if ((bg and 7) <> dominantBase) then
                      shadePenalty := shadePenalty + 50000.0 * cellSat;

                    if ((fg and 7) <> (bg and 7)) then
                      shadePenalty := shadePenalty + 80000.0 * cellSat;

                    // prefer fg bright and bg dark (more "shaded" look)
                    if (fg and 8) = 0 then
                      shadePenalty := shadePenalty + 30000.0 * cellSat;
                    if (bg and 8) <> 0 then
                      shadePenalty := shadePenalty + 30000.0 * cellSat;
                  end;

                  shadePenalty := shadePenalty + shadeBasePenalty;
                end;

                if isHalf then
                begin
                  // On edges, slightly prefer half-blocks (they carry orientation better than dithery shades).
                  if edgeStrength > 0.18 then
                    edgePenalty := edgePenalty - (edgeStrength - 0.18) * 25000.0 * edgeFactor * halfEdgeMult;

                  // inside flat-ish regions, avoid half-blocks (they look like hard steps)
                  if edgeStrength < 0.18 then
                    edgePenalty := edgePenalty + (0.18 - edgeStrength) * 60000.0 * halfFlatMult;

                  // Orientation bias on strong edges (only when direction is clear).
                  // This avoids "wrong" half-block orientation on diagonals.
                  if edgeStrength > 0.22 then
                  begin
                    // vertical edge => prefer left/right half blocks (221/222)
                    if dxLum > (dyLum * 4) div 3 then
                    begin
                      if (glyphCode = 220) or (glyphCode = 223) then
                        orientPenalty := (edgeStrength - 0.18) * 70000.0 * edgeFactor * orientMult;
                    end
                    // horizontal edge => prefer upper/lower half blocks (220/223)
                    else if dyLum > (dxLum * 4) div 3 then
                    begin
                      if (glyphCode = 221) or (glyphCode = 222) then
                        orientPenalty := (edgeStrength - 0.18) * 70000.0 * edgeFactor * orientMult;
                    end;
                  end;
                end;

                // Tutorial-style heuristics: bias toward blocks/half-blocks; controlled shade.
                if tutMode then
                begin
                  tutKind := TutGlyphKind(glyphCode);
                  if edgeStrength > 0.18 then
                  begin
                    // on edges prefer half-blocks to follow contours; shade costs more here
                    if tutKind in [4,5] then
                      tutPenalty := tutPenalty - TUT_EDGE_BONUS * edgeStrength
                    else if tutKind = 2 then
                      tutPenalty := tutPenalty + TUT_EDGE_PENALTY * edgeStrength;
                    if tutKind = 2 then
                      tutPenalty := tutPenalty + TUT_SHADE_EDGE_PEN * edgeStrength;
                  end
                  else if edgeStrength < 0.18 then
                  begin
                    // in flats prefer solid blocks and some half hatching; allow gentle shade on small gradients
                    if tutKind = 3 then
                      tutPenalty := tutPenalty - TUT_BLOCK_BONUS * (0.18 - edgeStrength);
                    if tutKind in [4,5] then
                      tutPenalty := tutPenalty + TUT_HALF_PENALTY * (0.18 - edgeStrength) * 0.5;
                    if tutKind = 2 then
                    begin
                      grad := Max(dxLum, dyLum);
                      if grad > 8 then
                        tutPenalty := tutPenalty - TUT_SHADE_BONUS * (grad / 255.0);
                      // shade on saturated color gets penalized (tutorials favor gray ramps)
                      if cellSat > 0.18 then
                        tutPenalty := tutPenalty + TUT_SHADE_SAT_PEN * cellSat;
                    end;
                  end;

                  // Orientation continuity for half-blocks (keep curves smooth).
                  if isHalf then
                  begin
                    if x > 0 then
                    begin
                      if ((tutKind = 4) and (TutGlyphKind(curGlyphRow[x-1]) = 4)) or
                         ((tutKind = 5) and (TutGlyphKind(curGlyphRow[x-1]) = 5)) then
                        tutPenalty := tutPenalty - TUT_EDGE_BONUS * 0.15
                      else if TutGlyphKind(curGlyphRow[x-1]) in [4,5] then
                        tutPenalty := tutPenalty + TUT_EDGE_PENALTY * 0.10;
                    end;
                    if y > 0 then
                    begin
                      if ((tutKind = 4) and (TutGlyphKind(prevGlyphRow[x]) = 4)) or
                         ((tutKind = 5) and (TutGlyphKind(prevGlyphRow[x]) = 5)) then
                        tutPenalty := tutPenalty - TUT_EDGE_BONUS * 0.10
                      else if TutGlyphKind(prevGlyphRow[x]) in [4,5] then
                        tutPenalty := tutPenalty + TUT_EDGE_PENALTY * 0.08;
                    end;
                  end;
                end;

                cost := cost + shadePenalty + edgePenalty + orientPenalty + tutPenalty;
                if cost < glyphBestCost then
                begin
                  glyphBestCost := cost;
                  glyphBestFg := fg;
                  glyphBestBg := bg;
                end;
              end;
        end;

        if glyphBestCost < bestCost then
        begin
          bestCost := glyphBestCost;
          bestGlyph := AREZ_GLYPHS[gi];
          bestFg := glyphBestFg;
          bestBg := glyphBestBg;
          bestGi := gi;
        end;
      end;

        // Remember neighbor colors for stability penalties.
        curFgRow[x] := bestFg;
        curBgRow[x] := bestBg;
        curGlyphRow[x] := bestGlyph;

        // Floyd-Steinberg dithering: diffuse residual cell-color error to neighbors.
        if ditherStyle = 2 then
        begin
          cov := glyphCoverage[bestGi];
          renderR := Round(DOS16_PALETTE[bestBg and 15].R * (1.0 - cov) + DOS16_PALETTE[bestFg and 15].R * cov);
          renderG := Round(DOS16_PALETTE[bestBg and 15].G * (1.0 - cov) + DOS16_PALETTE[bestFg and 15].G * cov);
          renderB := Round(DOS16_PALETTE[bestBg and 15].B * (1.0 - cov) + DOS16_PALETTE[bestFg and 15].B * cov);

          diffR := adjTargetR - renderR;
          diffG := adjTargetG - renderG;
          diffB := adjTargetB - renderB;

          // Scale error by dither strength (0..100) and distribute weights (7/3/5/1)/16.
          diffR := Round(diffR * (ditherStrength / 100.0));
          diffG := Round(diffG * (ditherStrength / 100.0));
          diffB := Round(diffB * (ditherStrength / 100.0));

          errCurR[errIdx + 1] := errCurR[errIdx + 1] + diffR * 7;
          errCurG[errIdx + 1] := errCurG[errIdx + 1] + diffG * 7;
          errCurB[errIdx + 1] := errCurB[errIdx + 1] + diffB * 7;

          errNextR[errIdx - 1] := errNextR[errIdx - 1] + diffR * 3;
          errNextG[errIdx - 1] := errNextG[errIdx - 1] + diffG * 3;
          errNextB[errIdx - 1] := errNextB[errIdx - 1] + diffB * 3;

          errNextR[errIdx] := errNextR[errIdx] + diffR * 5;
          errNextG[errIdx] := errNextG[errIdx] + diffG * 5;
          errNextB[errIdx] := errNextB[errIdx] + diffB * 5;

          errNextR[errIdx + 1] := errNextR[errIdx + 1] + diffR * 1;
          errNextG[errIdx + 1] := errNextG[errIdx + 1] + diffG * 1;
          errNextB[errIdx + 1] := errNextB[errIdx + 1] + diffB * 1;
        end;

        // per-cell unary cost for multi-pass merging
        CellCost[y * cols + x] := bestCost;

      // store cell [ch,attr]
        attr := Byte(bestFg and $0F) or Byte((bestBg and $07) shl 4);
        if Settings.IceColors and ((bestBg and 8) <> 0) then
          attr := attr or $80;

        Cells[(y * cols + x) * 2 + 0] := bestGlyph;
        Cells[(y * cols + x) * 2 + 1] := attr;

        // draw glyph into preview bitmap
        fgRGB := DOS16_PALETTE[bestFg and 15];
        bgRGB := DOS16_PALETTE[bestBg and 15];
        for glyphRow := 0 to 15 do
        begin
          bits := DOS_FONT_8X16[Ord(bestGlyph) * 16 + glyphRow];
          dstRow := Preview.ScanLine[y * 16 + glyphRow];
          dstBase := (x * 8) * 3;
          for glyphCol := 0 to 7 do
          begin
            if (bits and (1 shl (7 - glyphCol))) <> 0 then
            begin
              dstRow[dstBase + glyphCol * 3 + 0] := fgRGB.B;
              dstRow[dstBase + glyphCol * 3 + 1] := fgRGB.G;
              dstRow[dstBase + glyphCol * 3 + 2] := fgRGB.R;
            end
            else
            begin
              dstRow[dstBase + glyphCol * 3 + 0] := bgRGB.B;
              dstRow[dstBase + glyphCol * 3 + 1] := bgRGB.G;
              dstRow[dstBase + glyphCol * 3 + 2] := bgRGB.R;
            end;
          end;
        end;
      end;

      // End-of-row state updates for stability + dithering.
  tmpRow := prevFgRow; prevFgRow := curFgRow; curFgRow := tmpRow;
  tmpRow := prevBgRow; prevBgRow := curBgRow; curBgRow := tmpRow;
  tmpGlyphRow := prevGlyphRow; prevGlyphRow := curGlyphRow; curGlyphRow := tmpGlyphRow;

  if ditherStyle = 2 then
  begin
    tmpErr := errCurR; errCurR := errNextR; errNextR := tmpErr;
    tmpErr := errCurG; errCurG := errNextG; errNextG := tmpErr;
        tmpErr := errCurB; errCurB := errNextB; errNextB := tmpErr;
      end;
    end;

    OutCols := cols;
    OutRows := rows;
    Result := True;
end;

{ TOctNode }

constructor TOctNode.Create(ALevel: Integer; AIsLeaf: Boolean);
var
  i: Integer;
begin
  inherited Create;
  Level := ALevel;
  IsLeaf := AIsLeaf;
  PixelCount := 0;
  RedSum := 0;
  GreenSum := 0;
  BlueSum := 0;
  NextReducible := nil;
  for i := 0 to 7 do
    Children[i] := nil;
end;

destructor TOctNode.Destroy;
var
  i: Integer;
begin
  for i := 0 to 7 do
    Children[i].Free;
  inherited Destroy;
end;

function TOctNode.AvgColor: TRGB24;
var
  v: Int64;
begin
  if PixelCount <= 0 then
  begin
    Result.R := 0;
    Result.G := 0;
    Result.B := 0;
    Exit;
  end;

  v := RedSum div PixelCount;
  if v < 0 then v := 0 else if v > 255 then v := 255;
  Result.R := v;

  v := GreenSum div PixelCount;
  if v < 0 then v := 0 else if v > 255 then v := 255;
  Result.G := v;

  v := BlueSum div PixelCount;
  if v < 0 then v := 0 else if v > 255 then v := 255;
  Result.B := v;
end;

constructor TAdjustWorkerThread.Create(AOwner: TMainForm; const AJobId: LongInt;
  const ASettings: TAdjustSettings; ASourceCopy: TBitmap);
begin
  inherited Create(True);
  FreeOnTerminate := True;
  FOwner := AOwner;
  FJobId := AJobId;
  FSettings := ASettings;
  FSourceCopy := ASourceCopy;
  FResult := nil;
end;

destructor TAdjustWorkerThread.Destroy;
begin
  FResult.Free;
  FSourceCopy.Free;
  inherited Destroy;
end;

function TAdjustWorkerThread.CancelRequested: Boolean;
begin
  Result := Terminated;
end;

procedure TAdjustWorkerThread.SyncApply;
begin
  if Assigned(FOwner) and Assigned(FResult) then
    FOwner.ApplyWorkerResult(FJobId, FResult);
end;

procedure TAdjustWorkerThread.Execute;
var
  dest: TBitmap;
begin
  dest := nil;
  try
    if Terminated then Exit;

    dest := TBitmap.Create;
    dest.PixelFormat := pf24bit;
    dest.HandleType := bmDIB;
    dest.Transparent := False;

    if not BuildAdjustedBitmap(FSourceCopy, FSettings, dest, Self) then
      Exit;
    if Terminated then Exit;

    // hand off to main thread
    FResult := dest;
    dest := nil;
    Synchronize(@SyncApply);
  finally
    dest.Free;
  end;
end;

constructor TAnsiWorkerThread.Create(AOwner: TMainForm; const AJobId: LongInt;
  const ASettings: TAnsiConvSettings; ASourceCopy: TBitmap);
begin
  inherited Create(True);
  FreeOnTerminate := True;
  FOwner := AOwner;
  FJobId := AJobId;
  FSettings := ASettings;
  FSourceCopy := ASourceCopy;
  FPreview := nil;
  FCells := nil;
  FCols := 0;
  FRows := 0;
end;

destructor TAnsiWorkerThread.Destroy;
begin
  FPreview.Free;
  FSourceCopy.Free;
  inherited Destroy;
end;

function TAnsiWorkerThread.CancelRequested: Boolean;
begin
  Result := Terminated;
end;

procedure TAnsiWorkerThread.SyncApply;
begin
  if Assigned(FOwner) and Assigned(FPreview) and (Length(FCells) > 0) then
    FOwner.ApplyAnsiResult(FJobId, FCells, FPreview, FCols, FRows);
end;

procedure TAnsiWorkerThread.Execute;
var
  prev: TBitmap;
  cells: TBytes;
  costs: TDoubleArray;
  c, r: Integer;

  function GlyphClass(const G: Byte): Byte; inline;
  begin
    // Rough density classes for seam penalties.
    case G of
      32: Result := 0;                // space
      176: Result := 1;               // light shade
      177: Result := 2;               // medium shade
      178: Result := 3;               // dark shade
      219: Result := 4;               // full block
      220, 223, 221, 222: Result := 2;// half blocks (treat as medium)
    else
      Result := 2;
    end;
  end;

  function DecodeBgIdx(const Attr: Byte; const Ice: Boolean): Byte; inline;
  begin
    Result := (Attr shr 4) and 7;
    if Ice and ((Attr and $80) <> 0) then
      Result := Result or 8;
  end;

  function RgbDistNorm(const A, B: Byte): Double; inline;
  var
    dr, dg, db: Integer;
  begin
    dr := Integer(DOS16_PALETTE[A].R) - Integer(DOS16_PALETTE[B].R);
    dg := Integer(DOS16_PALETTE[A].G) - Integer(DOS16_PALETTE[B].G);
    db := Integer(DOS16_PALETTE[A].B) - Integer(DOS16_PALETTE[B].B);
    // Normalize by max possible squared distance (3 * 255^2).
    Result := (dr*dr + dg*dg + db*db) / 195075.0;
  end;

  procedure RenderPreviewFromCells(const ACells: TBytes; const ACols, ARows: Integer; Dest: TBitmap);
  var
    x, y, glyphRow, glyphCol: Integer;
    glyph: Byte;
    attr: Byte;
    fgIdx, bgIdx: Byte;
    fgRGB, bgRGB: TRGB24;
    bits: Byte;
    dstRow: PByte;
    dstBase: Integer;
    ice: Boolean;
  begin
    ice := FSettings.IceColors ;
    if not Assigned(Dest) then Exit;
    Dest.PixelFormat := pf24bit;
    Dest.HandleType := bmDIB;
    Dest.Transparent := False;
    Dest.SetSize(ACols * 8, ARows * 16);

    for y := 0 to ARows - 1 do
      for x := 0 to ACols - 1 do
      begin
        glyph := ACells[(y * ACols + x) * 2 + 0];
        attr := ACells[(y * ACols + x) * 2 + 1];
        fgIdx := attr and $0F;
        bgIdx := DecodeBgIdx(attr, ice);
        fgRGB := DOS16_PALETTE[fgIdx and 15];
        bgRGB := DOS16_PALETTE[bgIdx and 15];
        for glyphRow := 0 to 15 do
        begin
          bits := DOS_FONT_8X16[Ord(glyph) * 16 + glyphRow];
          dstRow := Dest.ScanLine[y * 16 + glyphRow];
          dstBase := (x * 8) * 3;
          for glyphCol := 0 to 7 do
          begin
            if (bits and (1 shl (7 - glyphCol))) <> 0 then
            begin
              dstRow[dstBase + glyphCol * 3 + 0] := fgRGB.B;
              dstRow[dstBase + glyphCol * 3 + 1] := fgRGB.G;
              dstRow[dstBase + glyphCol * 3 + 2] := fgRGB.R;
            end
            else
            begin
              dstRow[dstBase + glyphCol * 3 + 0] := bgRGB.B;
              dstRow[dstBase + glyphCol * 3 + 1] := bgRGB.G;
              dstRow[dstBase + glyphCol * 3 + 2] := bgRGB.R;
            end;
          end;
        end;
      end;
  end;

  function ClampInt(v, lo, hi: Integer): Integer; inline;
  begin
    if v < lo then Exit(lo);
    if v > hi then Exit(hi);
    Result := v;
  end;

  procedure DeriveLayerSettings(const Base: TAnsiConvSettings; out S0, S1, S2, S3: TAnsiConvSettings);
  var
    SB: TAnsiConvSettings;
    style: Integer;
  begin
    // Style-aware 4-layer presets.
    // We apply an overlay to the user\'s settings (SB), then derive four candidates from that.
    SB := Base;
    style := ClampInt(Base.StyleId, 0, 5);

    case style of
      1: begin // Scene (artpack-ish heavy shading)
        SB.IceColors := True;
        if SB.ColorMetric <= 1 then SB.ColorMetric := 6; // CIEDE2000
        // Prefer ordered dither for coherent ramps; multipass will provide extra texture where needed.
        if SB.DitherStyle = 0 then SB.DitherStyle := 1; // ordered
        SB.DitherStrength := ClampInt(Max(SB.DitherStrength, 55), 0, 100);
        SB.StabilityPct := ClampInt(Max(SB.StabilityPct, 32), 0, 100);
        SB.EdgeBiasPct := ClampInt(Max(SB.EdgeBiasPct, 52), 0, 100);
        SB.LumBucketStrength := ClampInt(Max(SB.LumBucketStrength, 18), 0, 100);
      end;
      2: begin // Toon (flat areas + controlled banded shading, crisp edges)
        // Keep dithering minimal, but allow a small ordered dither so gradients don't collapse to a single flat tone.
        SB.IceColors := False; // default off; one candidate layer will enable iCE for extra midtones
        if SB.DitherStyle = 0 then SB.DitherStyle := 1; // ordered
        SB.DitherStrength := ClampInt(Max(SB.DitherStrength, 6), 0, 18);
        SB.StabilityPct := ClampInt(Max(SB.StabilityPct, 48), 0, 100);
        SB.EdgeBiasPct := ClampInt(Max(SB.EdgeBiasPct, 65), 0, 100);
        // Encourage banding (toon shading) without crushing everything into a single bucket.
        SB.LumBucketStrength := ClampInt(Max(SB.LumBucketStrength, 32), 0, 100);
        SB.LumBucketThreshold := ClampInt(Max(SB.LumBucketThreshold, 90), 0, 255);
        SB.ChromaPenaltyPct := ClampInt(Min(SB.ChromaPenaltyPct, 10), 0, 100);
        if SB.ColorMetric <= 1 then SB.ColorMetric := 6;
      end;
      3: begin // Death (dark / high-contrast, heavy BG continuity)
        SB.IceColors := True;
        SB.BiasMode := 1; // Prefer dark
        SB.BiasStrength := ClampInt(Max(SB.BiasStrength, 65), 0, 100);
        SB.ForceBg := True;
        SB.ForceBgColor := 0;
        if SB.DitherStyle = 0 then SB.DitherStyle := 1; // Ordered
        SB.DitherStrength := ClampInt(Max(SB.DitherStrength, 50), 0, 100);
        SB.StabilityPct := ClampInt(Max(SB.StabilityPct, 45), 0, 100);
        SB.EdgeBiasPct := ClampInt(Max(SB.EdgeBiasPct, 60), 0, 100);
        SB.LumBucketStrength := ClampInt(Max(SB.LumBucketStrength, 25), 0, 100);
        SB.ChromaPenaltyPct := ClampInt(Max(SB.ChromaPenaltyPct, 20), 0, 100);
        if SB.ColorMetric <= 1 then SB.ColorMetric := 6;
      end;
      4: begin // Group (blocky scene vibe, heavy dithering + iCE)
        SB.IceColors := True;
        if SB.DitherStyle = 0 then SB.DitherStyle := 2; // FS
        SB.DitherStrength := ClampInt(Max(SB.DitherStrength, 75), 0, 100);
        SB.StabilityPct := ClampInt(Max(SB.StabilityPct, 35), 0, 100);
        SB.EdgeBiasPct := ClampInt(ClampInt(SB.EdgeBiasPct, 35, 70), 0, 100);
        SB.LumBucketStrength := ClampInt(Max(SB.LumBucketStrength, 15), 0, 100);
        SB.ChromaPenaltyPct := ClampInt(Max(SB.ChromaPenaltyPct, 10), 0, 100);
        if SB.ColorMetric <= 1 then SB.ColorMetric := 6;
      end;
      5: begin // Tutorial (classic block-heavy ANSI vibe)
        SB.DitherStyle := 0; // keep crisp blocks; hatching comes from half-blocks
        SB.DitherStrength := 0;
        SB.StabilityPct := ClampInt(Max(SB.StabilityPct, FTutStabilityFloor), 0, 100);
        SB.EdgeBiasPct := ClampInt(Max(SB.EdgeBiasPct, FTutEdgeBiasFloor), 0, 100);
        SB.LumBucketStrength := ClampInt(Max(SB.LumBucketStrength, FTutLumBucketStrength), 0, 100);
        SB.ChromaPenaltyPct := ClampInt(Max(SB.ChromaPenaltyPct, FTutChromaPenalty), 0, 100);
        SB.ForceBg := FTutForceBg;
        SB.ForceBgColor := ClampInt(FTutForceBgColor, 0, 15);
        SB.BiasMode := 1; // prefer dark
      end;
    end;

    // Layer 0: Balanced (styled base)
    S0 := SB;

    // Default deltas (good for Custom + Scene)
    S1 := SB;
    S1.EdgeBiasPct := ClampInt(SB.EdgeBiasPct + 25, 60, 100);
    S1.StabilityPct := ClampInt(SB.StabilityPct - 15, 0, 100);
    if S1.DitherStyle <> 0 then
      S1.DitherStrength := ClampInt(SB.DitherStrength + 10, 0, 100);

    S2 := SB;
    S2.EdgeBiasPct := ClampInt(SB.EdgeBiasPct - 20, 0, 60);
    S2.StabilityPct := ClampInt(SB.StabilityPct + 35, 0, 100);
    if S2.DitherStyle <> 0 then
      S2.DitherStrength := ClampInt(SB.DitherStrength - 20, 0, 100);

    S3 := SB;
    S3.EdgeBiasPct := ClampInt(SB.EdgeBiasPct - 10, 0, 70);
    S3.StabilityPct := ClampInt(SB.StabilityPct + 10, 0, 100);
    if S3.ColorMetric <= 1 then
      S3.ColorMetric := 6; // CIEDE2000
    if S3.DitherStyle = 0 then
      S3.DitherStyle := 1; // ordered
    S3.DitherStrength := ClampInt(SB.DitherStrength + 5, 0, 100);

    // Style-specific tweaks
    case style of
      1: begin // Scene
        // Candidate set for "artpack-ish" shading:
        //  - S1: texture/shade (stronger dither, looser stability)
        //  - S2: region/base (more stable, lower dither)
        //  - S3: edge/ink (crisp, no dither)
        S1.EdgeBiasPct := ClampInt(SB.EdgeBiasPct + 12, 50, 100);
        S1.StabilityPct := ClampInt(SB.StabilityPct - 10, 0, 100);
        if S1.DitherStyle = 0 then S1.DitherStyle := 1;
        S1.DitherStrength := ClampInt(SB.DitherStrength + 18, 0, 100);

        S2.EdgeBiasPct := ClampInt(SB.EdgeBiasPct - 6, 0, 80);
        S2.StabilityPct := ClampInt(SB.StabilityPct + 28, 0, 100);
        if S2.DitherStyle <> 0 then
          S2.DitherStrength := ClampInt(SB.DitherStrength - 24, 0, 100);

        S3.EdgeBiasPct := ClampInt(SB.EdgeBiasPct + 28, 60, 100);
        S3.StabilityPct := ClampInt(SB.StabilityPct - 6, 0, 100);
        S3.DitherStyle := 0;
        S3.DitherStrength := 0;
      end;
      2: begin // Toon
        // Candidate set for toon:
        //  - S1: edge/ink (very crisp, no dither)
        //  - S2: smooth banding (very low ordered dither)
        //  - S3: color/shading helper (enables iCE to create extra midtones without heavy texture)
        S1.EdgeBiasPct := ClampInt(SB.EdgeBiasPct + 28, 75, 100);
        S1.StabilityPct := ClampInt(SB.StabilityPct - 8, 0, 100);
        S1.DitherStyle := 0;
        S1.DitherStrength := 0;

        S2.EdgeBiasPct := ClampInt(SB.EdgeBiasPct - 15, 0, 80);
        S2.StabilityPct := ClampInt(SB.StabilityPct + 30, 0, 100);
        S2.DitherStyle := 1; // ordered
        S2.DitherStrength := 8;

        S3.EdgeBiasPct := ClampInt(SB.EdgeBiasPct - 8, 0, 85);
        S3.StabilityPct := ClampInt(SB.StabilityPct + 12, 0, 100);
        S3.ColorMetric := 6;
        S3.IceColors := True;
        S3.DitherStyle := 1; // ordered
        S3.DitherStrength := 14;
      end;
      3: begin // Death
        S1.EdgeBiasPct := ClampInt(SB.EdgeBiasPct + 30, 60, 100);
        S1.StabilityPct := ClampInt(SB.StabilityPct - 10, 0, 100);

        S2.EdgeBiasPct := ClampInt(SB.EdgeBiasPct - 15, 0, 70);
        S2.StabilityPct := ClampInt(SB.StabilityPct + 35, 0, 100);
        if S2.DitherStyle <> 0 then
          S2.DitherStrength := ClampInt(SB.DitherStrength - 15, 0, 100);

        S3.EdgeBiasPct := ClampInt(SB.EdgeBiasPct - 10, 0, 70);
        S3.StabilityPct := ClampInt(SB.StabilityPct + 15, 0, 100);
        S3.ColorMetric := 6;
        if S3.DitherStyle = 0 then S3.DitherStyle := 1;
        S3.DitherStrength := ClampInt(SB.DitherStrength + 5, 0, 100);
      end;
      4: begin // Group
        S1.EdgeBiasPct := ClampInt(SB.EdgeBiasPct + 22, 55, 100);
        S1.StabilityPct := ClampInt(SB.StabilityPct - 10, 0, 100);

        S2.EdgeBiasPct := ClampInt(SB.EdgeBiasPct - 18, 0, 60);
        S2.StabilityPct := ClampInt(SB.StabilityPct + 30, 0, 100);
        if S2.DitherStyle <> 0 then
          S2.DitherStrength := ClampInt(SB.DitherStrength - 15, 0, 100);

        S3.EdgeBiasPct := ClampInt(SB.EdgeBiasPct - 8, 0, 70);
        S3.StabilityPct := ClampInt(SB.StabilityPct + 12, 0, 100);
        S3.ColorMetric := 6;
        if S3.DitherStyle = 0 then S3.DitherStyle := 2;
        S3.DitherStrength := ClampInt(SB.DitherStrength + 5, 0, 100);
      end;
      5: begin // Tutorial
        // Candidates stay close; vary block vs half-block weight.
        S1.EdgeBiasPct := ClampInt(SB.EdgeBiasPct + 12, 70, 100);
        S1.StabilityPct := ClampInt(SB.StabilityPct + 8, 0, 100);
        if S1.DitherStyle <> 0 then
          S1.DitherStrength := ClampInt(SB.DitherStrength + 10, 0, 70);

        S2.EdgeBiasPct := ClampInt(SB.EdgeBiasPct - 10, 0, 80);
        S2.StabilityPct := ClampInt(SB.StabilityPct - 10, 0, 100);
        S2.DitherStyle := 0; // pure block pass
        S2.DitherStrength := 0;

        S3.EdgeBiasPct := ClampInt(SB.EdgeBiasPct + 5, 0, 100);
        S3.StabilityPct := ClampInt(SB.StabilityPct + 18, 0, 100);
        if S3.DitherStyle <> 0 then
          S3.DitherStrength := ClampInt(SB.DitherStrength + 4, 0, 70);
      end;
    end;
  end;

  function RunCandidate(const S: TAnsiConvSettings; out OutCells: TBytes; out OutCost: TDoubleArray;
    out OutCols, OutRows: Integer): Boolean;
  var
    tmpPrev: TBitmap;
  begin
    Result := False;
    if Terminated then Exit;
    tmpPrev := TBitmap.Create;
    try
      tmpPrev.PixelFormat := pf24bit;
      tmpPrev.HandleType := bmDIB;
      tmpPrev.Transparent := False;
      if not BuildAnsiPreview(FSourceCopy, S, OutCells, tmpPrev, OutCols, OutRows, Self, OutCost) then
        Exit(False);
      if Terminated then Exit(False);
      Result := True;
    finally
      tmpPrev.Free;
    end;
  end;

  procedure MultiPassMerge;
    // Shading-aware merge. We compare the *effective* rendered cell color (glyph coverage mixing FG/BG),
    // and we also encourage BG continuity to avoid visible seams in shaded regions.
    //
    // Improvements over the previous merge:
    //  - Adaptive blending: stronger smoothing in low-edge (flat) areas, looser on edges to preserve detail.
    //  - Diagonal neighbors: reduces "stair-step" seams and checkerboard artifacts.
    //  - Tile-based initialization: encourages coherent regions before ICM refinement.
    //
    // These weights intentionally bias toward larger coherent regions while still allowing local improvements.

  var
    S0, S1, S2, S3: TAnsiConvSettings;
    candCells: array[0..3] of TBytes;
    candCost: array[0..3] of TDoubleArray;
    fgArr, bgArr: array[0..3] of array of Byte;
    covArr: array[0..3] of array of Byte;      // 0..255 glyph coverage (FG fraction)
    effR, effG, effB: array[0..3] of array of Byte; // effective rendered color per cell
    cols0, rows0: Integer;
    colsK, rowsK: Integer;
    n, idx, x, y, pass, k, nb: Integer;
    labels: array of Byte;
    lambdaMap: array of Double;
    switchMap: array of Double;
    lumaMap: array of Byte;
    bestK: Integer;
    bestE, e, u, minCost, denom: Double;
    nbIdx: Integer;
    tx, ty, xx, yy, x0, y0, x1, y1: Integer;
    sumTile: Double;
    seam: Double;
    counts: array[0..3] of Integer;
    majority, curL, cntMax: Integer;
    uCur, uMaj, seamCur, seamMaj, eCur, eMaj: Double;
    glyph: Byte;
    attr: Byte;
    pop8: array[0..255] of Byte;
    fgRGB, bgRGB: TRGB24;
    covInt: Integer;

    // Style-tunable merge parameters (defaults are the original constants below)
    lambdaMin, lambdaMax: Double;
    switchMin, switchMax: Double;
    effW, bgW, densW: Double;
    diagW: Double;
    sweeps: Integer;
    smoothPasses: Integer;
    smoothBias: Double;
    tileSize: Integer;

    procedure InitPop8;
    var
      i, v, c: Integer;
    begin
      for i := 0 to 255 do
      begin
        v := i;
        c := 0;
        while v <> 0 do
        begin
          Inc(c, v and 1);
          v := v shr 1;
        end;
        pop8[i] := Byte(c);
      end;
    end;

    function GlyphCoverage255(const g: Byte): Byte; inline;
    var
      r: Integer;
      sum: Integer;
    begin
      sum := 0;
      for r := 0 to 15 do
        Inc(sum, pop8[DOS_FONT_8X16[Ord(g) * 16 + r]]);
      // 8x16 = 128 pixels. Scale to 0..255 for cheap blending.
      Result := Byte((sum * 255 + 64) div 128);
    end;

    function RgbDistNormRGB(const r1, g1, b1, r2, g2, b2: Byte): Double; inline;
    var
      dr, dg, db: Integer;
    begin
      dr := Integer(r1) - Integer(r2);
      dg := Integer(g1) - Integer(g2);
      db := Integer(b1) - Integer(b2);
      Result := (dr*dr + dg*dg + db*db) / 195075.0;
    end;

    
    procedure ComputeAdaptiveMaps;
    var
      small: TBitmap;
      row: PByte;
      r, g, b: Byte;
      lum: Integer;
      dx, dy: Integer;
      edge: Double;
      ii, xx2, yy2: Integer;
    begin
      SetLength(lumaMap, n);
      SetLength(lambdaMap, n);
      SetLength(switchMap, n);

      small := TBitmap.Create;
      try
        small.PixelFormat := pf24bit;
        small.HandleType := bmDIB;
        small.Transparent := False;
        small.SetSize(cols0, rows0);

        // Fast heuristic: downscale the adjusted source to the cell grid and compute a luma edge strength.
        // This lets us blend harder in smooth areas while preserving detail near edges.
        small.Canvas.StretchDraw(Rect(0, 0, cols0, rows0), FSourceCopy);

        for yy2 := 0 to rows0 - 1 do
        begin
          row := small.ScanLine[yy2];
          for xx2 := 0 to cols0 - 1 do
          begin
            b := row[xx2 * 3 + 0];
            g := row[xx2 * 3 + 1];
            r := row[xx2 * 3 + 2];
            lum := (54 * Integer(r) + 183 * Integer(g) + 19 * Integer(b)) shr 8;
            lumaMap[yy2 * cols0 + xx2] := Byte(lum);
          end;
        end;
      finally
        small.Free;
      end;

      for yy2 := 0 to rows0 - 1 do
      begin
        for xx2 := 0 to cols0 - 1 do
        begin
          ii := yy2 * cols0 + xx2;

          dx := 0;
          dy := 0;
          if xx2 > 0 then dx := dx + (Integer(lumaMap[ii]) - Integer(lumaMap[ii - 1]));
          if xx2 < cols0 - 1 then dx := dx + (Integer(lumaMap[ii + 1]) - Integer(lumaMap[ii]));
          if yy2 > 0 then dy := dy + (Integer(lumaMap[ii]) - Integer(lumaMap[ii - cols0]));
          if yy2 < rows0 - 1 then dy := dy + (Integer(lumaMap[ii + cols0]) - Integer(lumaMap[ii]));

          edge := Sqrt((dx * dx + dy * dy) / (2.0 * 255.0 * 255.0));
          if edge > 1.0 then edge := 1.0;

          lambdaMap[ii] := lambdaMin + (lambdaMax - lambdaMin) * (1.0 - edge);
          switchMap[ii] := switchMin + (switchMax - switchMin) * (1.0 - edge);
        end;
      end;
    end;

function UnaryNorm(const K: Integer; const I: Integer): Double; inline;
    begin
      // Normalize per-cell so seam weights are stable across metrics.
      minCost := candCost[0][I];
      if candCost[1][I] < minCost then minCost := candCost[1][I];
      if candCost[2][I] < minCost then minCost := candCost[2][I];
      if candCost[3][I] < minCost then minCost := candCost[3][I];
      denom := minCost + 1.0;
      Result := (candCost[K][I] - minCost) / denom;
      if Result < 0 then Result := 0;
    end;

    function SeamCost(const KA, IA, KB, IB: Integer): Double; inline;
    var
      distEff, distBg, dens: Double;
      bgA, bgB: Byte;
    begin
      if KA = KB then Exit(0.0);

      // Effective rendered color continuity (captures shading from FG/BG + glyph coverage).
      distEff := RgbDistNormRGB(effR[KA][IA], effG[KA][IA], effB[KA][IA],
                               effR[KB][IB], effG[KB][IB], effB[KB][IB]);

      // Encourage background continuity as a low-frequency "base layer".
      bgA := bgArr[KA][IA];
      bgB := bgArr[KB][IB];
      distBg := RgbDistNorm(bgA, bgB);

      // Encourage similar coverage (glyph density) across boundaries to avoid texture seams.
      dens := Abs(Integer(covArr[KA][IA]) - Integer(covArr[KB][IB])) / 255.0;

      Result := 0.5 * (switchMap[IA] + switchMap[IB]) + effW * distEff + bgW * distBg + densW * dens;
    end;

  begin
    // Merge-tuning defaults (matches the original constants).
    lambdaMin := 0.38;
    lambdaMax := 0.82;
    switchMin := 0.12;
    switchMax := 0.30;
    effW := 0.60;
    bgW := 0.42;
    densW := 0.32;
    diagW := 0.60;
    sweeps := 6;
    smoothPasses := 2;
    smoothBias := 0.06;
    tileSize := 4;

    // Style presets tweak merge behavior: Toon/Death prefer stronger region coherence;
    // Group keeps more texture; Scene keeps defaults.
    case ClampInt(FSettings.StyleId, 0, 5) of
      1: begin // Scene
        lambdaMin := 0.40;
        lambdaMax := 0.84;
        switchMin := 0.12;
        switchMax := 0.30;
        effW := 0.66;
        bgW := 0.50;
        densW := 0.30;
        diagW := 0.62;
        sweeps := 6;
        smoothPasses := 2;
        smoothBias := 0.06;
      end;
      2: begin // Toon
        // Keep regions cohesive, but don't over-penalize density changes (ramps) or you lose toon shading.
        lambdaMin := 0.45;
        lambdaMax := 0.88;
        switchMin := 0.14;
        switchMax := 0.32;
        effW := 0.74;
        bgW := 0.58;
        densW := 0.28;
        diagW := 0.65;
        sweeps := 7;
        smoothPasses := 2;
        smoothBias := 0.06;
      end;
      3: begin // Death
        lambdaMin := 0.42;
        lambdaMax := 0.88;
        switchMin := 0.16;
        switchMax := 0.36;
        effW := 0.68;
        bgW := 0.62;
        densW := 0.42;
        diagW := 0.65;
        sweeps := 7;
        smoothPasses := 3;
        smoothBias := 0.08;
      end;
      4: begin // Group
        lambdaMin := 0.32;
        lambdaMax := 0.78;
        switchMin := 0.10;
        switchMax := 0.26;
        effW := 0.56;
        bgW := 0.36;
        densW := 0.25;
        diagW := 0.60;
        sweeps := 5;
        smoothPasses := 2;
        smoothBias := 0.05;
      end;
      5: begin // Tutorial
        lambdaMin := 0.55;
        lambdaMax := 0.92;
        switchMin := 0.08;
        switchMax := 0.18;
        effW := 0.74;
        bgW := 0.54;
        densW := 0.36;
        diagW := 0.70;
        sweeps := 7;
        smoothPasses := 3;
        smoothBias := 0.08;
      end;
    end;

    InitPop8;

    DeriveLayerSettings(FSettings, S0, S1, S2, S3);

    if not RunCandidate(S0, candCells[0], candCost[0], cols0, rows0) then Exit;
    if not RunCandidate(S1, candCells[1], candCost[1], colsK, rowsK) then Exit;
    if (colsK <> cols0) or (rowsK <> rows0) then Exit;
    if not RunCandidate(S2, candCells[2], candCost[2], colsK, rowsK) then Exit;
    if (colsK <> cols0) or (rowsK <> rows0) then Exit;
    if not RunCandidate(S3, candCells[3], candCost[3], colsK, rowsK) then Exit;
    if (colsK <> cols0) or (rowsK <> rows0) then Exit;

    n := cols0 * rows0;
    SetLength(labels, n);
    ComputeAdaptiveMaps;

    // Pre-decode cell attributes and effective colors for seam cost.
    for k := 0 to 3 do
    begin
      SetLength(fgArr[k], n);
      SetLength(bgArr[k], n);
      SetLength(covArr[k], n);
      SetLength(effR[k], n);
      SetLength(effG[k], n);
      SetLength(effB[k], n);
      for idx := 0 to n - 1 do
      begin
        glyph := candCells[k][idx * 2 + 0];
        attr := candCells[k][idx * 2 + 1];

        fgArr[k][idx] := attr and $0F;
        bgArr[k][idx] := DecodeBgIdx(attr, FSettings.IceColors);

        covArr[k][idx] := GlyphCoverage255(glyph);

        // Effective rendered color = mix(FG, BG, coverage).
        // This is what the eye tracks for shading continuity.
        fgRGB := DOS16_PALETTE[fgArr[k][idx] and 15];
        bgRGB := DOS16_PALETTE[bgArr[k][idx] and 15];
        covInt := covArr[k][idx]; // 0..255

        effR[k][idx] := Byte((covInt * Integer(fgRGB.R) + (255 - covInt) * Integer(bgRGB.R) + 127) div 255);
        effG[k][idx] := Byte((covInt * Integer(fgRGB.G) + (255 - covInt) * Integer(bgRGB.G) + 127) div 255);
        effB[k][idx] := Byte((covInt * Integer(fgRGB.B) + (255 - covInt) * Integer(bgRGB.B) + 127) div 255);
      end;
    end;

    // Init labels: best unary.
    for idx := 0 to n - 1 do
    begin
      bestK := 0;
      bestE := candCost[0][idx];
      for k := 1 to 3 do
        if candCost[k][idx] < bestE then
        begin
          bestE := candCost[k][idx];
          bestK := k;
        end;
      labels[idx] := Byte(bestK);
    end;


    // Tile-based initialization: pick a single best candidate per small region first.
    // This reduces early speckle and gives ICM a coherent starting point.
    for ty := 0 to (rows0 - 1) div tileSize do
    begin
      if Terminated then Exit;
      y0 := ty * tileSize;
      y1 := Min(rows0, y0 + tileSize) - 1;
      for tx := 0 to (cols0 - 1) div tileSize do
      begin
        x0 := tx * tileSize;
        x1 := Min(cols0, x0 + tileSize) - 1;

        bestK := 0;
        bestE := 1.0e100;
        for k := 0 to 3 do
        begin
          sumTile := 0.0;
          for yy := y0 to y1 do
            for xx := x0 to x1 do
              sumTile := sumTile + UnaryNorm(k, yy * cols0 + xx);

          if sumTile < bestE then
          begin
            bestE := sumTile;
            bestK := k;
          end;
        end;

        for yy := y0 to y1 do
          for xx := x0 to x1 do
            labels[yy * cols0 + xx] := Byte(bestK);
      end;
    end;

    // ICM refinement sweeps to reduce patchwork and improve shading continuity.
    for pass := 1 to sweeps do
    begin
      for y := 0 to rows0 - 1 do
      begin
        if Terminated then Exit;
        for x := 0 to cols0 - 1 do
        begin
          idx := y * cols0 + x;
          bestK := labels[idx];
          bestE := 1.0e100;
          for k := 0 to 3 do
          begin
            u := UnaryNorm(k, idx);
            seam := 0.0;
            // 4-neighborhood
            if x > 0 then
            begin
              nbIdx := idx - 1;
              nb := labels[nbIdx];
              seam := seam + SeamCost(k, idx, nb, nbIdx);
            end;
            if x < cols0 - 1 then
            begin
              nbIdx := idx + 1;
              nb := labels[nbIdx];
              seam := seam + SeamCost(k, idx, nb, nbIdx);
            end;
            if y > 0 then
            begin
              nbIdx := idx - cols0;
              nb := labels[nbIdx];
              seam := seam + SeamCost(k, idx, nb, nbIdx);
            end;
            if y < rows0 - 1 then
            begin
              nbIdx := idx + cols0;
              nb := labels[nbIdx];
              seam := seam + SeamCost(k, idx, nb, nbIdx);
            end;

            // Diagonals help reduce stair-step seams and checkerboard artifacts.
            if (x > 0) and (y > 0) then
            begin
              nbIdx := idx - cols0 - 1;
              nb := labels[nbIdx];
              seam := seam + diagW * SeamCost(k, idx, nb, nbIdx);
            end;
            if (x < cols0 - 1) and (y > 0) then
            begin
              nbIdx := idx - cols0 + 1;
              nb := labels[nbIdx];
              seam := seam + diagW * SeamCost(k, idx, nb, nbIdx);
            end;
            if (x > 0) and (y < rows0 - 1) then
            begin
              nbIdx := idx + cols0 - 1;
              nb := labels[nbIdx];
              seam := seam + diagW * SeamCost(k, idx, nb, nbIdx);
            end;
            if (x < cols0 - 1) and (y < rows0 - 1) then
            begin
              nbIdx := idx + cols0 + 1;
              nb := labels[nbIdx];
              seam := seam + diagW * SeamCost(k, idx, nb, nbIdx);
            end;

            e := u + lambdaMap[idx] * seam;
            if e < bestE then
            begin
              bestE := e;
              bestK := k;
            end;
          end;
          labels[idx] := Byte(bestK);
        end;
      end;
    end;

    // Extra label smoothing: remove isolated "islands" and enforce stronger shading blends.
    // We bias toward the majority neighbor label unless the current choice is noticeably better.
    for pass := 1 to smoothPasses do
    begin
      for y := 0 to rows0 - 1 do
      begin
        if Terminated then Exit;
        for x := 0 to cols0 - 1 do
        begin
          idx := y * cols0 + x;
          curL := labels[idx];

          counts[0] := 0; counts[1] := 0; counts[2] := 0; counts[3] := 0;
          if x > 0 then Inc(counts[labels[idx - 1]]);
          if x < cols0 - 1 then Inc(counts[labels[idx + 1]]);
          if y > 0 then Inc(counts[labels[idx - cols0]]);
          if y < rows0 - 1 then Inc(counts[labels[idx + cols0]]);

          // Majority vote among 4-neighbors.
          majority := 0;
          cntMax := counts[0];
          if counts[1] > cntMax then begin majority := 1; cntMax := counts[1]; end;
          if counts[2] > cntMax then begin majority := 2; cntMax := counts[2]; end;
          if counts[3] > cntMax then begin majority := 3; cntMax := counts[3]; end;

          if (majority <> curL) and (cntMax >= 3) then
          begin
            // Compare energies with the same seam formulation used in ICM.
            uCur := UnaryNorm(curL, idx);
            seamCur := 0.0;
            uMaj := UnaryNorm(majority, idx);
            seamMaj := 0.0;

            if x > 0 then
            begin
              nbIdx := idx - 1; nb := labels[nbIdx];
              seamCur := seamCur + SeamCost(curL, idx, nb, nbIdx);
              seamMaj := seamMaj + SeamCost(majority, idx, nb, nbIdx);
            end;
            if x < cols0 - 1 then
            begin
              nbIdx := idx + 1; nb := labels[nbIdx];
              seamCur := seamCur + SeamCost(curL, idx, nb, nbIdx);
              seamMaj := seamMaj + SeamCost(majority, idx, nb, nbIdx);
            end;
            if y > 0 then
            begin
              nbIdx := idx - cols0; nb := labels[nbIdx];
              seamCur := seamCur + SeamCost(curL, idx, nb, nbIdx);
              seamMaj := seamMaj + SeamCost(majority, idx, nb, nbIdx);
            end;
            if y < rows0 - 1 then
            begin
              nbIdx := idx + cols0; nb := labels[nbIdx];
              seamCur := seamCur + SeamCost(curL, idx, nb, nbIdx);
              seamMaj := seamMaj + SeamCost(majority, idx, nb, nbIdx);
            end;

            // Diagonals (weighted) for more coherent shading regions.
            if (x > 0) and (y > 0) then
            begin
              nbIdx := idx - cols0 - 1; nb := labels[nbIdx];
              seamCur := seamCur + diagW * SeamCost(curL, idx, nb, nbIdx);
              seamMaj := seamMaj + diagW * SeamCost(majority, idx, nb, nbIdx);
            end;
            if (x < cols0 - 1) and (y > 0) then
            begin
              nbIdx := idx - cols0 + 1; nb := labels[nbIdx];
              seamCur := seamCur + diagW * SeamCost(curL, idx, nb, nbIdx);
              seamMaj := seamMaj + diagW * SeamCost(majority, idx, nb, nbIdx);
            end;
            if (x > 0) and (y < rows0 - 1) then
            begin
              nbIdx := idx + cols0 - 1; nb := labels[nbIdx];
              seamCur := seamCur + diagW * SeamCost(curL, idx, nb, nbIdx);
              seamMaj := seamMaj + diagW * SeamCost(majority, idx, nb, nbIdx);
            end;
            if (x < cols0 - 1) and (y < rows0 - 1) then
            begin
              nbIdx := idx + cols0 + 1; nb := labels[nbIdx];
              seamCur := seamCur + diagW * SeamCost(curL, idx, nb, nbIdx);
              seamMaj := seamMaj + diagW * SeamCost(majority, idx, nb, nbIdx);
            end;

            eCur := uCur + lambdaMap[idx] * seamCur;
            eMaj := uMaj + lambdaMap[idx] * seamMaj;

            if eMaj <= eCur + smoothBias then
              labels[idx] := Byte(majority);
          end;
        end;
      end;
    end;

    // Build merged cells.
    SetLength(cells, n * 2);
    for idx := 0 to n - 1 do
    begin
      k := labels[idx];
      cells[idx * 2 + 0] := candCells[k][idx * 2 + 0];
      cells[idx * 2 + 1] := candCells[k][idx * 2 + 1];
    end;

    // Render final preview.
    prev := TBitmap.Create;
    prev.PixelFormat := pf24bit;
    prev.HandleType := bmDIB;
    prev.Transparent := False;
    RenderPreviewFromCells(cells, cols0, rows0, prev);

    FCells := cells;
    FCols := cols0;
    FRows := rows0;
    FPreview := prev;
    prev := nil;
    Synchronize(@SyncApply);
  end;

begin
  prev := nil;
  try
    if Terminated then Exit;

    if FSettings.MultiPass4 then
    begin
      MultiPassMerge;
      Exit;
    end;

    prev := TBitmap.Create;
    prev.PixelFormat := pf24bit;
    prev.HandleType := bmDIB;
    prev.Transparent := False;

    if not BuildAnsiPreview(FSourceCopy, FSettings, cells, prev, c, r, Self, costs) then
      Exit;
    if Terminated then Exit;

    FCells := cells;
    FCols := c;
    FRows := r;
    FPreview := prev;
    prev := nil;
    Synchronize(@SyncApply);
  finally
    prev.Free;
  end;
end;

procedure TMainForm.FormCreate(Sender: TObject);
begin
  FClosing := False;
  FUpdatingControls := False;
  FOutputDir := '';
  FPresetsDir := '';
  FAppIniPath := '';
  FLastImageDir := '';
  FSettingsOpenDialog := nil;
  FSettingsSaveDialog := nil;
  FMainMenu := nil;

  KeyPreview := True;
  OnKeyDown := @FormKeyDown;

  FSource := TPicture.Create;
  FSourceBitmap := TBitmap.Create;
  FSourceBitmap.PixelFormat := pf24bit;
  FScaled := TBitmap.Create;
  FScaled.PixelFormat := pf24bit;
  FViewport := TViewportTransform.Create;
  FAnsiDebounceTimer := TTimer.Create(Self);
  FAnsiDebounceTimer.Enabled := False;
  FAnsiDebounceTimer.Interval := 200;
  FAnsiDebounceTimer.OnTimer := @AnsiDebounceTimerTimer;
  FWorking := TBitmap.Create;
  FWorking.PixelFormat := pf24bit;
  FAnsiPreview := TBitmap.Create;
  FAnsiPreview.PixelFormat := pf24bit;
  FAdjustThread := nil;
  FRequestedJobId := 0;
  FRunningJobId := 0;
  FAnsiThread := nil;
  FAnsiRequestedJobId := 0;
  FAnsiRunningJobId := 0;
  FAnsiCols := 0;
  FAnsiRows := 0;
  FAnsiBiasMode := 0;
  FAnsiBiasStrength := 0;
  FAnsiLumBucketStrength := 0;
  FAnsiLumBucketThreshold := 128;
  FAnsiChromaPenaltyPct := 0;
  SetProcessing(False);
  SetAnsiProcessing(False);
  ZoomTrack.Min := 25;   // 25% minimum
  ZoomTrack.Max := 125;  // cap at 125% of full size
  ZoomTrack.Position := 100;
  UpdateZoomLabel;
  UpdateScrollPages;
  if Assigned(SourceStatus) then
    SourceStatus.SimpleText := 'No image loaded';

  // Apply source mods on release (mouse/key) to avoid spawning work while dragging.
  TrackRed.OnChange := nil;
  TrackGreen.OnChange := nil;
  TrackBlue.OnChange := nil;
  TrackBrightness.OnChange := nil;
  TrackContrast.OnChange := nil;
  TrackGamma.OnChange := nil;
  TrackSaturation.OnChange := nil;
  TrackBlur.OnChange := nil;
  TrackSharpen.OnChange := nil;
  TrackClarity.OnChange := nil;
  TrackDenoise.OnChange := nil;
  TrackChromaDenoise.OnChange := nil;
  TrackGuided.OnChange := nil;
  TrackEdge.OnChange := nil;
  TrackBilateral.OnChange := nil;
  TrackDosBias.OnChange := nil;
  TrackHue.OnChange := nil;
  TrackMidContrast.OnChange := nil;

  TrackRed.OnMouseUp := @ModsSliderMouseUp;
  TrackGreen.OnMouseUp := @ModsSliderMouseUp;
  TrackBlue.OnMouseUp := @ModsSliderMouseUp;
  TrackBrightness.OnMouseUp := @ModsSliderMouseUp;
  TrackContrast.OnMouseUp := @ModsSliderMouseUp;
  TrackGamma.OnMouseUp := @ModsSliderMouseUp;
  TrackSaturation.OnMouseUp := @ModsSliderMouseUp;
  TrackBlur.OnMouseUp := @ModsSliderMouseUp;
  TrackSharpen.OnMouseUp := @ModsSliderMouseUp;
  TrackClarity.OnMouseUp := @ModsSliderMouseUp;
  TrackDenoise.OnMouseUp := @ModsSliderMouseUp;
  TrackChromaDenoise.OnMouseUp := @ModsSliderMouseUp;
  TrackGuided.OnMouseUp := @ModsSliderMouseUp;
  TrackEdge.OnMouseUp := @ModsSliderMouseUp;
  TrackBilateral.OnMouseUp := @ModsSliderMouseUp;
  TrackDosBias.OnMouseUp := @ModsSliderMouseUp;
  TrackHue.OnMouseUp := @ModsSliderMouseUp;
  TrackMidContrast.OnMouseUp := @ModsSliderMouseUp;

  TrackRed.OnKeyUp := @ModsSliderKeyUp;
  TrackGreen.OnKeyUp := @ModsSliderKeyUp;
  TrackBlue.OnKeyUp := @ModsSliderKeyUp;
  TrackBrightness.OnKeyUp := @ModsSliderKeyUp;
  TrackContrast.OnKeyUp := @ModsSliderKeyUp;
  TrackGamma.OnKeyUp := @ModsSliderKeyUp;
  TrackSaturation.OnKeyUp := @ModsSliderKeyUp;
  TrackBlur.OnKeyUp := @ModsSliderKeyUp;
  TrackSharpen.OnKeyUp := @ModsSliderKeyUp;
  TrackClarity.OnKeyUp := @ModsSliderKeyUp;
  TrackDenoise.OnKeyUp := @ModsSliderKeyUp;
  TrackChromaDenoise.OnKeyUp := @ModsSliderKeyUp;
  TrackGuided.OnKeyUp := @ModsSliderKeyUp;
  TrackEdge.OnKeyUp := @ModsSliderKeyUp;
  TrackBilateral.OnKeyUp := @ModsSliderKeyUp;
  TrackDosBias.OnKeyUp := @ModsSliderKeyUp;
  TrackHue.OnKeyUp := @ModsSliderKeyUp;
  TrackMidContrast.OnKeyUp := @ModsSliderKeyUp;

  // reduce flicker and make manual scrolling feel smoother
  SourceScroll.DoubleBuffered := True;
  SourceScroll.HorzScrollBar.Tracking := True;
  SourceScroll.VertScrollBar.Tracking := True;

  ProcessTimer.Enabled := False;
  ProcessTimer.Interval := 150; // debounce heavy processing

  // ANSI preview defaults
  if Assigned(SpinAnsiCols) then
  begin
    SpinAnsiCols.MinValue := 1;
    SpinAnsiCols.MaxValue := 200;
    SpinAnsiCols.Value := 80;
    SpinAnsiCols.OnChange := @AnsiControlsChange;
  end;
  if Assigned(SpinAnsiRows) then
  begin
    SpinAnsiRows.MinValue := 1;
    SpinAnsiRows.MaxValue := 200;
    SpinAnsiRows.Value := 25;
    SpinAnsiRows.OnChange := @AnsiControlsChange;
  end;
  if Assigned(CheckAnsiKeepAspect) then
  begin
    CheckAnsiKeepAspect.Checked := True;
    CheckAnsiKeepAspect.OnChange := @AnsiControlsChange;
  end;
  if Assigned(CheckAnsiAutoRows) then
  begin
    CheckAnsiAutoRows.Checked := True;
    CheckAnsiAutoRows.OnChange := @AnsiControlsChange;
  end;
  if Assigned(CheckAnsiMultiPass) then
  begin
    CheckAnsiMultiPass.Checked := False;
    CheckAnsiMultiPass.OnChange := @AnsiControlsChange;
  end;
  if Assigned(CheckICE) then
  begin
    CheckICE.Checked := False;
    CheckICE.OnChange := @AnsiControlsChange;
  end;
  if Assigned(ComboAnsiSample) then
  begin
    ComboAnsiSample.ItemIndex := 2; // 2x4
    ComboAnsiSample.OnChange := @AnsiControlsChange;
  end;
  if Assigned(ComboAnsiMetric) then
  begin
    ComboAnsiMetric.ItemIndex := 1; // Redmean
    ComboAnsiMetric.OnChange := @AnsiControlsChange;
  end;
  if Assigned(CheckAnsiForceBg) then
  begin
    CheckAnsiForceBg.Checked := False;
    CheckAnsiForceBg.OnChange := @AnsiControlsChange;
  end;
  if Assigned(ComboAnsiForceBg) then
  begin
    ComboAnsiForceBg.ItemIndex := 0;
    ComboAnsiForceBg.Enabled := False;
    ComboAnsiForceBg.OnChange := @AnsiControlsChange;
  end;
  if Assigned(ComboAnsiDither) then
  begin
    ComboAnsiDither.ItemIndex := 0; // None
    ComboAnsiDither.OnChange := @AnsiControlsChange;
  end;
  if Assigned(TrackAnsiDitherStrength) then
  begin
    TrackAnsiDitherStrength.Min := 0;
    TrackAnsiDitherStrength.Max := 100;
    TrackAnsiDitherStrength.Position := 40;
    TrackAnsiDitherStrength.Enabled := False;
    TrackAnsiDitherStrength.OnChange := nil;
    TrackAnsiDitherStrength.OnMouseUp := @AnsiSliderMouseUp;
    TrackAnsiDitherStrength.OnKeyUp := @AnsiSliderKeyUp;
  end;
  if Assigned(TrackAnsiStability) then
  begin
    TrackAnsiStability.Min := 0;
    TrackAnsiStability.Max := 100;
    TrackAnsiStability.Position := 0;
    TrackAnsiStability.OnChange := nil;
    TrackAnsiStability.OnMouseUp := @AnsiSliderMouseUp;
    TrackAnsiStability.OnKeyUp := @AnsiSliderKeyUp;
  end;
  if Assigned(TrackAnsiEdgeBias) then
  begin
    TrackAnsiEdgeBias.Min := 0;
    TrackAnsiEdgeBias.Max := 100;
    TrackAnsiEdgeBias.Position := 50;
    TrackAnsiEdgeBias.OnChange := nil;
    TrackAnsiEdgeBias.OnMouseUp := @AnsiSliderMouseUp;
    TrackAnsiEdgeBias.OnKeyUp := @AnsiSliderKeyUp;
  end;
  if Assigned(BtnSaveAnsi) then
  begin
    BtnSaveAnsi.Enabled := False;
    BtnSaveAnsi.OnClick := @BtnSaveAnsiClick;
  end;
  if Assigned(BtnAnsiAdvanced) then
  begin
    BtnAnsiAdvanced.Enabled := True;
    BtnAnsiAdvanced.OnClick := @BtnAnsiAdvancedClick;
  end;

  if Assigned(AnsiScroll) then
  begin
    AnsiScroll.DoubleBuffered := True;
    AnsiScroll.HorzScrollBar.Tracking := True;
    AnsiScroll.VertScrollBar.Tracking := True;
  end;

  // Per-user storage (presets/output) + auto-saved config INI.
  FPresetsDir := GetPresetsDir;
  FOutputDir := GetOutputDir;
  FAppIniPath := UserDataRootDir + 'rez2ans.ini';
  EnsureAppDirs;

  // Settings (preset) dialogs.
  FSettingsOpenDialog := TOpenDialog.Create(Self);
  FSettingsOpenDialog.Title := 'Load Settings';
  FSettingsOpenDialog.Filter := 'Rez2ans settings (*.ini)|*.ini|All files (*.*)|*.*';
  if (FPresetsDir <> '') and DirectoryExists(FPresetsDir) then
    FSettingsOpenDialog.InitialDir := FPresetsDir;

  FSettingsSaveDialog := TSaveDialog.Create(Self);
  FSettingsSaveDialog.Title := 'Save Settings';
  FSettingsSaveDialog.DefaultExt := 'ini';
  FSettingsSaveDialog.Filter := 'Rez2ans settings (*.ini)|*.ini|All files (*.*)|*.*';
  if (FPresetsDir <> '') and DirectoryExists(FPresetsDir) then
    FSettingsSaveDialog.InitialDir := FPresetsDir;

  // Main menu (load/save settings, help paths, shortcuts).
  BuildMainMenu;

  // Load last session config (safe even if missing/corrupt).
  LoadAppIni;

  if Assigned(OpenPictureDialog1) and (FLastImageDir <> '') and DirectoryExists(FLastImageDir) then
    OpenPictureDialog1.InitialDir := FLastImageDir;
  if Assigned(SaveDialogAnsi) and (FOutputDir <> '') and DirectoryExists(FOutputDir) then
    SaveDialogAnsi.InitialDir := FOutputDir;

  UpdateAnsiStatus(0, 0);
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  SaveAppIni;
  FClosing := True;
  ProcessTimer.Enabled := False;
  if Assigned(FAnsiDebounceTimer) then
    FAnsiDebounceTimer.Enabled := False;
  FreeAndNil(FViewport);
  FreeAndNil(FAnsiDebounceTimer);
  if Assigned(FAdjustThread) then
  begin
    FAdjustThread.Terminate;
    // Ensure any pending Synchronize/OnTerminate calls are processed so we don't
    // tear down UI while the worker still references it.
    while Assigned(FAdjustThread) do
      CheckSynchronize(50);
  end;
  if Assigned(FAnsiThread) then
  begin
    FAnsiThread.Terminate;
    while Assigned(FAnsiThread) do
      CheckSynchronize(50);
  end;
  FWorking.Free;
  FAnsiPreview.Free;
  FSourceBitmap.Free;
  FScaled.Free;
  FSource.Free;
end;

procedure TMainForm.ModsChange(Sender: TObject);
begin
  if FUpdatingControls then Exit;
  // Combos call this; apply immediately (processing happens in the worker thread).
  ScheduleAdjustments;
end;

procedure TMainForm.AnsiControlsChange(Sender: TObject);
var
  cols, rows: Integer;
  w, h: Integer;
  autoRows: Integer;
  sel: TRect;
begin
  if FClosing then Exit;
  if FUpdatingControls then Exit;

  if Assigned(CheckAnsiForceBg) and Assigned(ComboAnsiForceBg) then
  begin
    ComboAnsiForceBg.Enabled := CheckAnsiForceBg.Checked;
    // When iCE is off, backgrounds are limited to 0..7 (no bright BG).
    if Assigned(CheckICE) and (not CheckICE.Checked) and (ComboAnsiForceBg.ItemIndex > 7) then
      ComboAnsiForceBg.ItemIndex := ComboAnsiForceBg.ItemIndex and 7;
  end;

  if Assigned(ComboAnsiDither) and Assigned(TrackAnsiDitherStrength) then
    TrackAnsiDitherStrength.Enabled := ComboAnsiDither.ItemIndex <> 0;
  if Assigned(CheckAnsiMultiPass) and Assigned(ComboAnsiStyle) then
  begin
    ComboAnsiStyle.Enabled := CheckAnsiMultiPass.Checked;
    if Assigned(LabelAnsiStyle) then
      LabelAnsiStyle.Enabled := CheckAnsiMultiPass.Checked;
  end;


  if Assigned(CheckAnsiKeepAspect) and Assigned(CheckAnsiAutoRows) then
    if (not CheckAnsiKeepAspect.Checked) and CheckAnsiAutoRows.Checked then
      CheckAnsiAutoRows.Checked := False;

  cols := 80;
  if Assigned(SpinAnsiCols) then
    cols := SpinAnsiCols.Value;

  if Assigned(SpinAnsiRows) then
    rows := SpinAnsiRows.Value
  else
    rows := 25;

  if Assigned(CheckAnsiAutoRows) and CheckAnsiAutoRows.Checked and
     Assigned(CheckAnsiKeepAspect) and CheckAnsiKeepAspect.Checked and HasImage then
  begin
    sel := ClampSelRect(FSelRect);
    w := Max(1, sel.Right - sel.Left);
    h := Max(1, sel.Bottom - sel.Top);
    if (w > 0) and (h > 0) then
    begin
      // 8x16 cell aspect ratio
      autoRows := Max(1, Round(cols * (h / w) * (8.0 / 16.0)));
      if Assigned(SpinAnsiRows) then
      begin
        SpinAnsiRows.OnChange := nil;
        SpinAnsiRows.Value := autoRows;
        SpinAnsiRows.OnChange := @AnsiControlsChange;
        SpinAnsiRows.Enabled := False;
      end;
      rows := autoRows;
    end;
  end
  else if Assigned(SpinAnsiRows) then
    SpinAnsiRows.Enabled := True;

  ScheduleAnsiPreview;
end;

procedure TMainForm.ProcessTimerTimer(Sender: TObject);
begin
  ProcessTimer.Enabled := False;
  ApplyAdjustments;
end;


procedure TMainForm.SourceOverlayPaint(Sender: TObject);
const
  HANDLE_SIZE = 11;
  HANDLE_HALF = HANDLE_SIZE div 2;
var
  dr: TRect;
  leftPx, rightPx, topPx, bottomPx: Integer;
  midX, midY: Integer;

  procedure DrawHandle(cx, cy: Integer);
  var
    hr: TRect;
  begin
    hr := Rect(cx - HANDLE_HALF, cy - HANDLE_HALF, cx + HANDLE_HALF + 1, cy + HANDLE_HALF + 1);
    SourceOverlay.Canvas.Brush.Style := bsSolid;
    SourceOverlay.Canvas.Brush.Color := clYellow;
    SourceOverlay.Canvas.Pen.Style := psSolid;
    SourceOverlay.Canvas.Pen.Color := clBlack;
    SourceOverlay.Canvas.Rectangle(hr);

    // Inner highlight so the handle stays visible on bright backgrounds.
    InflateRect(hr, -2, -2);
    if (hr.Right > hr.Left) and (hr.Bottom > hr.Top) then
    begin
      SourceOverlay.Canvas.Brush.Color := clWhite;
      SourceOverlay.Canvas.Pen.Color := clBlack;
      SourceOverlay.Canvas.Rectangle(hr);
    end;
  end;
begin
  if not Assigned(SourceOverlay) then Exit;
  if not HasImage then Exit;

  dr := WorkingToDisplayRect(ClampSelRect(FSelRect));
  if (dr.Right <= dr.Left) or (dr.Bottom <= dr.Top) then Exit;

  // Frame: high-contrast triple stroke so it stands out on any image.
  SourceOverlay.Canvas.Brush.Style := bsClear;

  SourceOverlay.Canvas.Pen.Style := psSolid;
  SourceOverlay.Canvas.Pen.Color := clBlack;
  SourceOverlay.Canvas.Pen.Width := 3;
  SourceOverlay.Canvas.Rectangle(dr.Left - 2, dr.Top - 2, dr.Right + 2, dr.Bottom + 2);

  SourceOverlay.Canvas.Pen.Width := 1;
  SourceOverlay.Canvas.Pen.Style := psSolid;
  SourceOverlay.Canvas.Pen.Color := clYellow;
  SourceOverlay.Canvas.Rectangle(dr.Left - 1, dr.Top - 1, dr.Right + 1, dr.Bottom + 1);

  SourceOverlay.Canvas.Pen.Style := psDot;
  SourceOverlay.Canvas.Pen.Color := clWhite;
  SourceOverlay.Canvas.Rectangle(dr);

  SourceOverlay.Canvas.Pen.Style := psSolid;
  SourceOverlay.Canvas.Pen.Width := 1;

  // Handles (draw inside the rectangle bounds).
  leftPx := dr.Left;
  topPx := dr.Top;
  rightPx := dr.Right - 1;
  bottomPx := dr.Bottom - 1;
  if rightPx < leftPx then rightPx := leftPx;
  if bottomPx < topPx then bottomPx := topPx;
  midX := (leftPx + rightPx) div 2;
  midY := (topPx + bottomPx) div 2;

  DrawHandle(leftPx, topPx);       // NW
  DrawHandle(rightPx, topPx);      // NE
  DrawHandle(leftPx, bottomPx);    // SW
  DrawHandle(rightPx, bottomPx);   // SE
  DrawHandle(midX, topPx);         // N
  DrawHandle(midX, bottomPx);      // S
  DrawHandle(leftPx, midY);        // W
  DrawHandle(rightPx, midY);       // E
end;

procedure TMainForm.SourceOverlayMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  h: TSelHandle;
  pw: TPoint;
begin
  if FClosing then Exit;
  if not HasImage then Exit;
  if not Assigned(SourceOverlay) then Exit;

  if Button = mbRight then
  begin
    ResetSelection;
    UpdateStatus;
    ScheduleAnsiPreview;
    Exit;
  end;

  if Button <> mbLeft then Exit;

  pw := DisplayToWorkingPoint(Point(X, Y));
  FSelecting := True;
  FSelStartW := pw;
  FSelStartRect := ClampSelRect(FSelRect);
  FSelDragHandle := shNone;
  FSelDragMode := sdNone;

  // Shift+drag always creates a new selection (handy when selection covers the whole image).
  if (ssShift in Shift) or (not HitTestSelection(Point(X, Y), h)) then
  begin
    FSelDragMode := sdCreate;
    FSelActive := True;
    FSelRect := Rect(pw.X, pw.Y, pw.X + 1, pw.Y + 1);
  end
  else
  begin
    if h <> shNone then
    begin
      FSelDragMode := sdResize;
      FSelDragHandle := h;
    end
    else
      FSelDragMode := sdMove;
  end;

  SourceOverlay.Invalidate;
end;

procedure TMainForm.SourceOverlayMouseMove(Sender: TObject; Shift: TShiftState; X,
  Y: Integer);
var
  pw: TPoint;
  dx, dy: Integer;
  r: TRect;
  imgW, imgH: Integer;
  w, h: Integer;
begin
  if not HasImage then Exit;
  if not Assigned(SourceOverlay) then Exit;

  if not FSelecting then
  begin
    UpdateSelectionCursor(Point(X, Y));
    Exit;
  end;

  pw := DisplayToWorkingPoint(Point(X, Y));

  case FSelDragMode of
    sdCreate:
      begin
        r.Left := Min(FSelStartW.X, pw.X);
        r.Top := Min(FSelStartW.Y, pw.Y);
        r.Right := Max(FSelStartW.X, pw.X) + 1;
        r.Bottom := Max(FSelStartW.Y, pw.Y) + 1;
        FSelRect := ClampSelRect(r);
      end;

    sdMove:
      begin
        dx := pw.X - FSelStartW.X;
        dy := pw.Y - FSelStartW.Y;
        r := Rect(FSelStartRect.Left + dx, FSelStartRect.Top + dy,
                  FSelStartRect.Right + dx, FSelStartRect.Bottom + dy);

        imgW := FWorking.Width;
        imgH := FWorking.Height;
        w := r.Right - r.Left;
        h := r.Bottom - r.Top;
        if w > imgW then w := imgW;
        if h > imgH then h := imgH;

        if r.Left < 0 then
        begin
          r.Left := 0;
          r.Right := r.Left + w;
        end;
        if r.Top < 0 then
        begin
          r.Top := 0;
          r.Bottom := r.Top + h;
        end;
        if r.Right > imgW then
        begin
          r.Right := imgW;
          r.Left := r.Right - w;
        end;
        if r.Bottom > imgH then
        begin
          r.Bottom := imgH;
          r.Top := r.Bottom - h;
        end;

        FSelRect := ClampSelRect(r);
      end;

    sdResize:
      begin
        r := FSelStartRect;

        // Left edge
        if FSelDragHandle in [shNW, shW, shSW] then
          r.Left := Min(pw.X, r.Right - 1);
        // Right edge
        if FSelDragHandle in [shNE, shE, shSE] then
          r.Right := Max(pw.X + 1, r.Left + 1);
        // Top edge
        if FSelDragHandle in [shNW, shN, shNE] then
          r.Top := Min(pw.Y, r.Bottom - 1);
        // Bottom edge
        if FSelDragHandle in [shSW, shS, shSE] then
          r.Bottom := Max(pw.Y + 1, r.Top + 1);

        FSelRect := ClampSelRect(r);
      end;
  else
    Exit;
  end;

  SourceOverlay.Invalidate;
end;

procedure TMainForm.SourceOverlayMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if Button <> mbLeft then Exit;
  if not FSelecting then Exit;

  FSelecting := False;
  FSelRect := ClampSelRect(FSelRect);
  FSelActive := True;
  FSelDragMode := sdNone;
  FSelDragHandle := shNone;
  FSelHoverHandle := shNone;

  UpdateStatus;
  ScheduleAnsiPreview;
  if Assigned(SourceOverlay) then
    SourceOverlay.Invalidate;
end;

procedure TMainForm.ModsSliderMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if FUpdatingControls then Exit;
  // Apply on release (mouse drag/click).
  ScheduleAdjustments;
end;

procedure TMainForm.ModsSliderKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if FUpdatingControls then Exit;
  // Apply on release (keyboard adjustments).
  ScheduleAdjustments;
end;

procedure TMainForm.AnsiSliderMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if FUpdatingControls then Exit;
  ScheduleAnsiPreview;
end;

procedure TMainForm.AnsiSliderKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if FUpdatingControls then Exit;
  ScheduleAnsiPreview;
end;

procedure TMainForm.BtnOpenClick(Sender: TObject);
begin
  if Assigned(OpenPictureDialog1) then
  begin
    if (FLastImageDir <> '') and DirectoryExists(FLastImageDir) then
      OpenPictureDialog1.InitialDir := FLastImageDir;
  end;
  if OpenPictureDialog1.Execute then
    LoadImage(OpenPictureDialog1.FileName);
end;

procedure TMainForm.BtnAnsiAdvancedClick(Sender: TObject);
var
  dlg: TAnsiAdvForm;
  bm, bs, ls, lt, cp: Integer;
begin
  dlg := TAnsiAdvForm.Create(Self);
  try
    dlg.LoadFromValues(FAnsiBiasMode, FAnsiBiasStrength, FAnsiLumBucketStrength,
      FAnsiLumBucketThreshold, FAnsiChromaPenaltyPct);
    if dlg.ShowModal = mrOk then
    begin
      dlg.SaveToValues(bm, bs, ls, lt, cp);
      FAnsiBiasMode := bm;
      FAnsiBiasStrength := bs;
      FAnsiLumBucketStrength := ls;
      FAnsiLumBucketThreshold := lt;
      FAnsiChromaPenaltyPct := cp;
      ScheduleAnsiPreview;
    end;
  finally
    dlg.Free;
  end;
end;

procedure TMainForm.BtnSaveAnsiClick(Sender: TObject);
const
  // DOS color index (0..7) to ANSI SGR color number (0..7)
  DosBaseToAnsi: array[0..7] of Byte = (0, 4, 2, 6, 1, 5, 3, 7);
  CRLF: array[0..1] of Byte = (13, 10);
type
  TSaveFmt = (sfCancel, sfAnsi, sfBin, sfPng);
var
  fileName: string;
  ext: string;
  canAnsi: Boolean;
  fs: TFileStream;
  x, y: Integer;
  idx: Integer;
  ch, attr: Byte;
  curAttr: Byte;
  fg, bg: Integer;
  bgFull: Integer;
  codes: string;
  seq: RawByteString;
  fmt: TSaveFmt;

  function AskSaveFormat: TSaveFmt;
  var
    dlg: TForm;
    i: Integer;
    btn: TCustomButton;
    msg: string;
    mr: Integer;
  begin
    Result := sfCancel;

    if canAnsi then
    begin
      msg :=
        'Choose output format:' + LineEnding + LineEnding +
        'ANSI (.ans) - for 80 columns or less' + LineEnding +
        'Binary (.bin) - raw screen dump' + LineEnding +
        'Image (.png) - ANSI preview bitmap' + LineEnding + LineEnding +
        'Current columns: ' + IntToStr(FAnsiCols) + '   rows: ' + IntToStr(FAnsiRows);
      dlg := CreateMessageDialog(msg, mtConfirmation, [mbYes, mbNo, mbIgnore, mbCancel]);
    end
    else
    begin
      msg :=
        'Choose output format:' + LineEnding + LineEnding +
        'Binary (.bin) - raw screen dump' + LineEnding +
        'Image (.png) - ANSI preview bitmap' + LineEnding + LineEnding +
        'Note: ANSI (.ans) save is only available for 80 columns or less.' + LineEnding +
        'Current columns: ' + IntToStr(FAnsiCols) + '   rows: ' + IntToStr(FAnsiRows);
      dlg := CreateMessageDialog(msg, mtConfirmation, [mbYes, mbNo, mbCancel]);
    end;

    try
      dlg.Caption := 'Save output';
      // Re-label buttons to meaningful format choices.
      for i := 0 to dlg.ComponentCount - 1 do
        if dlg.Components[i] is TCustomButton then
        begin
          btn := TCustomButton(dlg.Components[i]);
          case btn.ModalResult of
            mrYes:
              if canAnsi then btn.Caption := 'ANSI (.ans)' else btn.Caption := 'Binary (.bin)';
            mrNo:
              if canAnsi then btn.Caption := 'Binary (.bin)' else btn.Caption := 'Image (.png)';
            mrIgnore:
              btn.Caption := 'Image (.png)';
            mrCancel:
              btn.Caption := 'Cancel';
          end;
        end;

      FitDialogButtonsRight(dlg, 120);

      mr := dlg.ShowModal;
      case mr of
        mrYes:
          if canAnsi then Result := sfAnsi else Result := sfBin;
        mrNo:
          if canAnsi then Result := sfBin else Result := sfPng;
        mrIgnore:
          Result := sfPng;
      else
        Result := sfCancel;
      end;
    finally
      dlg.Free;
    end;
  end;

  procedure EnsureExt(const AExtNoDot: string);
  begin
    if ExtractFileExt(fileName) = '' then
      fileName := fileName + '.' + AExtNoDot;
    ext := LowerCase(ExtractFileExt(fileName));
  end;

  procedure WriteRaw(const s: RawByteString);
  begin
    if s = '' then Exit;
    fs.WriteBuffer(Pointer(s)^, Length(s));
  end;

  procedure WriteAttr(a: Byte);
  var
    baseFg, baseBg: Integer;
    brightFg: Boolean;
    brightBg: Boolean;
    ice: Boolean;
  begin
    fg := a and $0F;
    bg := (a shr 4) and $07;
    ice := ((Assigned(CheckICE) and CheckICE.Checked) or FAnsiIceUsed);
    brightBg := ice and ((a and $80) <> 0);
    if brightBg then
      bgFull := bg + 8
    else
      bgFull := bg;

    baseFg := fg and 7;
    baseBg := bgFull and 7;
    brightFg := fg >= 8;

    codes := '0';
    if brightBg then
      codes := codes + ';5'; // blink bit used as BG high bit in iCE viewers
    if brightFg then
      codes := codes + ';1';
    codes := codes + ';' + IntToStr(30 + DosBaseToAnsi[baseFg]);
    codes := codes + ';' + IntToStr(40 + DosBaseToAnsi[baseBg]);

    seq := #27'[' + RawByteString(codes) + 'm';
    WriteRaw(seq);
  end;

  procedure SaveAsAnsi(const fn: string);
  var
    ix, iy: Integer;
    resetSeq: RawByteString;
  begin
    fs := TFileStream.Create(fn, fmCreate);
    try
      // Start with a reset for safety/compatibility.
      resetSeq := #27'[0m';
      WriteRaw(resetSeq);
      curAttr := $FF; // force first write

      for iy := 0 to FAnsiRows - 1 do
      begin
        for ix := 0 to FAnsiCols - 1 do
        begin
          idx := (iy * FAnsiCols + ix) * 2;
          ch := FAnsiBin[idx + 0];
          attr := FAnsiBin[idx + 1];
          if attr <> curAttr then
          begin
            WriteAttr(attr);
            curAttr := attr;
          end;
          if ch = 0 then ch := 32;
          fs.WriteBuffer(ch, 1);
        end;
        // Only write CRLF if the line does NOT reach 80 columns.
        // For exactly 80 columns, rely on terminal auto-wrap for correct ANSI art rendering.
        if FAnsiCols < 80 then
        begin
          fs.WriteBuffer(CRLF[0], Length(CRLF));
          curAttr := $FF; // after CRLF, force re-emit attr for next line (safer)
        end;
      end;

      // Final reset (safe for shells/viewers).
      WriteRaw(resetSeq);
    finally
      fs.Free;
    end;
  end;

  procedure SaveAsBin(const fn: string);
  type
    // SAUCE record (128 bytes). Used by ANSI/ASCII editors to understand dimensions, iCE color, etc.
    // For BinaryText (.BIN), the content is a raw screen dump of [Ch,Attr] pairs.
    // SAUCE DataType=5 (BinaryText). TInfo1 = bytes per line (must be even), TInfo2 = number of lines.
    TSauceRec = packed record
      ID: array[0..4] of AnsiChar;        // 'SAUCE'
      Version: array[0..1] of AnsiChar;   // '00'
      Title: array[0..34] of AnsiChar;
      Author: array[0..19] of AnsiChar;
      Group: array[0..19] of AnsiChar;
      Date: array[0..7] of AnsiChar;      // YYYYMMDD
      FileSize: LongInt;                  // size of content *before* EOF/COMNT/SAUCE
      DataType: Byte;
      FileType: Byte;
      TInfo1: Word;
      TInfo2: Word;
      TInfo3: Word;
      TInfo4: Word;
      Comments: Byte;
      Flags: Byte;
      TInfoS: array[0..21] of AnsiChar;   // 22 bytes
    end;
  const
    SAUCE_ID: array[0..4] of AnsiChar = ('S','A','U','C','E');
    SAUCE_VER: array[0..1] of AnsiChar = ('0','0');
    SAUCE_COMNT: array[0..4] of AnsiChar = ('C','O','M','N','T');
  var
    Sauce: TSauceRec;
    dt, title: string;
    outBody: TBytes;
    userCols, userRows: Integer;
    outCols, outRows: Integer;
    srcRowBytes, dstRowBytes: Integer;
    bodyBytes: Integer;
    cellCount: Integer;
    i: Integer;
    r: Integer;
    srcOfs, dstOfs: Integer;
    b: Byte;
    comment: AnsiString;
    line: array[0..63] of AnsiChar;

    procedure FillSauceField(var Dest; const S: string; MaxLen: Integer);
    var
      tmp: RawByteString;
      n: Integer;
    begin
      if MaxLen <= 0 then Exit;
      FillChar(Dest, MaxLen, Ord(' '));
      tmp := RawByteString(S);
      n := Length(tmp);
      if n > MaxLen then n := MaxLen;
      if n > 0 then
        Move(Pointer(tmp)^, Dest, n);
    end;
  begin
    userCols := FAnsiCols;
    userRows := FAnsiRows;
    if (userCols <= 0) or (userRows <= 0) then Exit;
    if Length(FAnsiBin) < (userCols * userRows * 2) then Exit;

    // Hard caps (also enforced in conversion), plus make width even so SAUCE width/2 is exact.
    outCols := userCols;
    outRows := userRows;
    if outCols > 320 then outCols := 320;
    if outRows > 320 then outRows := 320;
    if (outCols and 1) <> 0 then
    begin
      if outCols < 320 then
        Inc(outCols)
      else
        Dec(outCols); // keep within 320 while forcing even
    end;

    srcRowBytes := userCols * 2;
    dstRowBytes := outCols * 2;

    bodyBytes := dstRowBytes * outRows;
    if bodyBytes <= 0 then Exit;

    SetLength(outBody, bodyBytes);

    // Fill entire output with padding cell: space + attr $00
    cellCount := outCols * outRows;
    for i := 0 to cellCount - 1 do
    begin
      outBody[i * 2] := 32;      // ' '
      outBody[i * 2 + 1] := $00; // black-on-black
    end;

    // Copy real converted cells into the padded buffer (clamp in case rows/cols were capped).
    for r := 0 to Min(userRows, outRows) - 1 do
    begin
      srcOfs := r * srcRowBytes;
      dstOfs := r * dstRowBytes;
      Move(FAnsiBin[srcOfs], outBody[dstOfs], Min(srcRowBytes, dstRowBytes));
    end;

    fs := TFileStream.Create(fn, fmCreate);
    try
      if Length(outBody) > 0 then
        fs.WriteBuffer(outBody[0], Length(outBody));

      // EOF marker (SUB). Many SAUCE-aware tools expect this before COMNT/SAUCE.
      b := $1A;
      fs.WriteBuffer(b, 1);

      // Comment block (1 line)
      comment := AnsiString('made by rez2ans');
      FillChar(line, SizeOf(line), Ord(' '));
      for i := 1 to Length(comment) do
        if i <= 64 then line[i - 1] := AnsiChar(comment[i]);
      fs.WriteBuffer(SAUCE_COMNT, SizeOf(SAUCE_COMNT));
      fs.WriteBuffer(line, SizeOf(line));

      // SAUCE record
      FillChar(Sauce, SizeOf(Sauce), 0);
      Move(SAUCE_ID, Sauce.ID, 5);
      Move(SAUCE_VER, Sauce.Version, 2);

      title := ExtractFileName(ChangeFileExt(fn, ''));
      FillSauceField(Sauce.Title, title, 35);
      FillSauceField(Sauce.Author, 'rez2ans', 20);
      FillSauceField(Sauce.Group, '', 20);

      dt := FormatDateTime('yyyymmdd', Date);
      FillSauceField(Sauce.Date, dt, 8);

      // Size of content BEFORE EOF/COMNT/SAUCE
      Sauce.FileSize := LongInt(Length(outBody));
      Sauce.DataType := 5; // BinaryText
      Sauce.FileType := Byte(outCols div 2); // width = FileType * 2

      // Keep these consistent (some tools look at them even for BIN)
      Sauce.TInfo1 := Word(dstRowBytes); // bytes per line (2 bytes per cell)
      Sauce.TInfo2 := Word(outRows);
      Sauce.TInfo3 := 0;
      Sauce.TInfo4 := 0;

      Sauce.Comments := 1; // one 64-byte comment line

      // Bit 0: iCE / non-blink ON
      if ((Assigned(CheckICE) and CheckICE.Checked) or FAnsiIceUsed) then
        Sauce.Flags := 1
      else
        Sauce.Flags := 0;

      FillSauceField(Sauce.TInfoS, 'IBM VGA', 22);

      fs.WriteBuffer(Sauce, SizeOf(Sauce));
    finally
      fs.Free;
    end;
  end;

  procedure SavePreviewAsPng(const fn: string);
  var
    img: TFPMemoryImage;
    writer: TFPWriterPNG;
    xb, yb: Integer;
    row: PByte;
    c: TFPColor;
    tmp: TBitmap;
    bmp: TBitmap;
  begin
    if not Assigned(FAnsiPreview) then Exit;
    if (FAnsiPreview.Width <= 0) or (FAnsiPreview.Height <= 0) then Exit;

    bmp := FAnsiPreview;
    tmp := nil;
    if bmp.PixelFormat <> pf24bit then
    begin
      tmp := TBitmap.Create;
      tmp.PixelFormat := pf24bit;
      tmp.HandleType := bmDIB;
      tmp.Transparent := False;
      tmp.SetSize(bmp.Width, bmp.Height);
      tmp.Canvas.Draw(0, 0, bmp);
      bmp := tmp;
    end;

    img := TFPMemoryImage.Create(bmp.Width, bmp.Height);
    writer := TFPWriterPNG.Create;
    try
      for yb := 0 to bmp.Height - 1 do
      begin
        row := bmp.ScanLine[yb];
        for xb := 0 to bmp.Width - 1 do
        begin
          c.Red := row[xb * 3 + 2] * $101;
          c.Green := row[xb * 3 + 1] * $101;
          c.Blue := row[xb * 3 + 0] * $101;
          c.Alpha := $FFFF;
          img.Colors[xb, yb] := c;
        end;
      end;
      img.SaveToFile(fn, writer);
    finally
      writer.Free;
      img.Free;
      tmp.Free;
    end;
  end;
begin
  if Length(FAnsiBin) = 0 then
  begin
    ShowMessage('No output data to save yet.');
    Exit;
  end;
  if (FAnsiCols <= 0) or (FAnsiRows <= 0) then Exit;
  if not Assigned(SaveDialogAnsi) then Exit;

  canAnsi := FAnsiCols <= 80;
  fmt := AskSaveFormat;
  if fmt = sfCancel then Exit;

  EnsureAppDirs;
  if (FOutputDir <> '') and Assigned(SaveDialogAnsi) then
    SaveDialogAnsi.InitialDir := FOutputDir;

  case fmt of
    sfAnsi:
      begin
        SaveDialogAnsi.Filter := 'ANSI files (*.ans)|*.ans|All files|*.*';
        SaveDialogAnsi.DefaultExt := 'ans';
        if (SaveDialogAnsi.FileName = '') or (ExtractFilePath(SaveDialogAnsi.FileName) = '') then
          if FOutputDir <> '' then
            SaveDialogAnsi.FileName := IncludeTrailingPathDelimiter(FOutputDir) + 'output.ans'
          else
            SaveDialogAnsi.FileName := 'output.ans'
        else
          SaveDialogAnsi.FileName := ChangeFileExt(SaveDialogAnsi.FileName, '.ans');
      end;
    sfBin:
      begin
        SaveDialogAnsi.Filter := 'Binary screen dump (*.bin)|*.bin|All files|*.*';
        SaveDialogAnsi.DefaultExt := 'bin';
        if (SaveDialogAnsi.FileName = '') or (ExtractFilePath(SaveDialogAnsi.FileName) = '') then
          if FOutputDir <> '' then
            SaveDialogAnsi.FileName := IncludeTrailingPathDelimiter(FOutputDir) + 'output.bin'
          else
            SaveDialogAnsi.FileName := 'output.bin'
        else
          SaveDialogAnsi.FileName := ChangeFileExt(SaveDialogAnsi.FileName, '.bin');
      end;
    sfPng:
      begin
        SaveDialogAnsi.Filter := 'PNG image (*.png)|*.png|All files|*.*';
        SaveDialogAnsi.DefaultExt := 'png';
        if (SaveDialogAnsi.FileName = '') or (ExtractFilePath(SaveDialogAnsi.FileName) = '') then
          if FOutputDir <> '' then
            SaveDialogAnsi.FileName := IncludeTrailingPathDelimiter(FOutputDir) + 'output.png'
          else
            SaveDialogAnsi.FileName := 'output.png'
        else
          SaveDialogAnsi.FileName := ChangeFileExt(SaveDialogAnsi.FileName, '.png');
      end;
  else
    begin
      SaveDialogAnsi.Filter := 'All files|*.*';
      SaveDialogAnsi.DefaultExt := '';
    end;
  end;

  if not SaveDialogAnsi.Execute then Exit;

  fileName := SaveDialogAnsi.FileName;
  ext := LowerCase(ExtractFileExt(fileName));

  if ext = '' then
    EnsureExt(LowerCase(SaveDialogAnsi.DefaultExt));

  if ext = '.ans' then
  begin
    if not canAnsi then
    begin
      ShowMessage('ANSI save is intended for 80 columns or less. Use .bin or .png for wider output.');
      Exit;
    end;
    SaveAsAnsi(fileName);
  end
  else if ext = '.bin' then
    SaveAsBin(fileName)
  else if ext = '.png' then
    SavePreviewAsPng(fileName)
  else
  begin
    // Fallback: save binary when extension is unknown.
    EnsureExt('bin');
    SaveAsBin(fileName);
  end;
end;

procedure TMainForm.FitCheckChange(Sender: TObject);
begin
  if FUpdatingControls then Exit;
  ApplyFitIfNeeded;
  RenderScaled(CurrentScale);
  UpdateStatus;
end;

procedure TMainForm.FormResize(Sender: TObject);
begin
  UpdateScrollPages;
  if Assigned(AnsiScroll) then
  begin
    AnsiScroll.HorzScrollBar.Page := AnsiScroll.ClientWidth;
    AnsiScroll.VertScrollBar.Page := AnsiScroll.ClientHeight;
    AnsiScroll.HorzScrollBar.Increment := Max(8, AnsiScroll.ClientWidth div 20);
    AnsiScroll.VertScrollBar.Increment := Max(8, AnsiScroll.ClientHeight div 20);
  end;
  ApplyFitIfNeeded;
  RenderScaled(CurrentScale);
  UpdateStatus;
end;

procedure TMainForm.ZoomTrackChange(Sender: TObject);
begin
  if FUpdatingControls then Exit;
  UpdateZoomLabel;
  RenderScaled(CurrentScale);
  UpdateStatus;
end;

function TMainForm.CurrentScale: Double;
begin
  Result := ZoomTrack.Position / 100.0;
end;

function TMainForm.HasImage: Boolean;
begin
  Result := Assigned(FSourceBitmap) and
            (FSourceBitmap.Width > 0) and
            (FSourceBitmap.Height > 0);
end;

procedure TMainForm.LoadImage(const AFileName: string);
var
  tmp: TBitmap;
begin
  FLastImageDir := ExtractFileDir(AFileName);
  if Assigned(OpenPictureDialog1) and (FLastImageDir <> '') then
    OpenPictureDialog1.InitialDir := FLastImageDir;

  FSource.LoadFromFile(AFileName);          // supports PNG/JPG via LCL readers
  tmp := TBitmap.Create;
  try
    tmp.PixelFormat := pf24bit;
    tmp.SetSize(FSource.Width, FSource.Height);
    tmp.Canvas.Brush.Color := clBlack;
    tmp.Canvas.FillRect(0, 0, tmp.Width, tmp.Height);
    tmp.Canvas.Draw(0, 0, FSource.Graphic); // flattens any alpha onto black
    FSourceBitmap.Assign(tmp);
    FSourceBitmap.PixelFormat := pf24bit;
    FSourceBitmap.HandleType := bmDIB;
    FSourceBitmap.Transparent := False;
  finally
    tmp.Free;
  end;

  if (FSourceBitmap.Width = 0) or (FSourceBitmap.Height = 0) then
  begin
    ShowMessage('Unable to load image or unsupported format: ' + AFileName);
    Exit;
  end;
  UpdateScrollPages;
  ApplyFitIfNeeded;
  // Show original immediately; heavy adjustments run in background.
  FWorking.Assign(FSourceBitmap);
  ResetSelection;
  RenderScaled(CurrentScale);
  UpdateStatus;
  ScheduleAnsiPreview;
  ApplyAdjustments;
end;

procedure TMainForm.ApplyFitIfNeeded;
var
  fitScale: Double;
  baseW, baseH: Integer;
begin
  if not (FitCheck.Checked and HasImage) then
    Exit;

  if (SourceScroll.ClientWidth = 0) or (SourceScroll.ClientHeight = 0) then
    Exit;

  baseW := FSourceBitmap.Width;
  baseH := FSourceBitmap.Height;
  if Assigned(FWorking) and (FWorking.Width > 0) and (FWorking.Height > 0) then
  begin
    baseW := FWorking.Width;
    baseH := FWorking.Height;
  end;
  if (baseW <= 0) or (baseH <= 0) then Exit;

  fitScale := Min(
                SourceScroll.ClientWidth / baseW,
                SourceScroll.ClientHeight / baseH
              );

  fitScale := Min(fitScale, 1.0); // shrink to fit; never auto-upscale
  fitScale := EnsureRange(fitScale, ZoomTrack.Min / 100.0, ZoomTrack.Max / 100.0);

  ZoomTrack.OnChange := nil; // avoid recursion when adjusting slider programmatically
  ZoomTrack.Position := Round(fitScale * 100);
  ZoomTrack.OnChange := @ZoomTrackChange;

  UpdateZoomLabel;
end;

function TMainForm.CaptureSettings: TAdjustSettings;
begin
  Result.RedPct := TrackRed.Position;
  Result.GreenPct := TrackGreen.Position;
  Result.BluePct := TrackBlue.Position;
  Result.Brightness := TrackBrightness.Position;
  Result.Contrast := TrackContrast.Position;
  Result.AutoContrast := Assigned(CheckAutoContrast) and CheckAutoContrast.Checked;
  Result.GammaPct := TrackGamma.Position;
  Result.SaturationPct := TrackSaturation.Position;
  Result.HueDeg := TrackHue.Position;
  Result.MidContrast := TrackMidContrast.Position;
  Result.BlurRadius := TrackBlur.Position;
  Result.SharpenAmt := TrackSharpen.Position;
  Result.ClarityAmt := TrackClarity.Position;
  Result.DenoisePasses := TrackDenoise.Position;
  Result.ChromaDenoiseAmt := TrackChromaDenoise.Position;
  Result.GuidedAmt := TrackGuided.Position;
  Result.EdgeAmt := TrackEdge.Position;
  Result.EdgeStyle := ComboEdgeStyle.ItemIndex;
  Result.BilateralAmt := TrackBilateral.Position;
  Result.DosBiasPct := TrackDosBias.Position;
  Result.DitherStyle := ComboDither.ItemIndex;
  Result.QuantMethod := ComboQuantMethod.ItemIndex;
  Result.QuantLevels := StrToIntDef(ComboQuantize.Text, 256);
end;

function TMainForm.CaptureAnsiSettings: TAnsiConvSettings;
var
  cols, rows: Integer;
  w, h: Integer;
  sel: TRect;
begin
  cols := 80;
  rows := 25;
  if Assigned(SpinAnsiCols) then cols := SpinAnsiCols.Value;
  if Assigned(SpinAnsiRows) then rows := SpinAnsiRows.Value;

  Result.Cols := cols;
  Result.Rows := rows;
  Result.KeepAspect := Assigned(CheckAnsiKeepAspect) and CheckAnsiKeepAspect.Checked;
  Result.AutoRows := Assigned(CheckAnsiAutoRows) and CheckAnsiAutoRows.Checked;
  Result.IceColors := Assigned(CheckICE) and CheckICE.Checked;
  if Assigned(ComboAnsiSample) then
    Result.SampleMode := ComboAnsiSample.ItemIndex
  else
    Result.SampleMode := 2;

  if Assigned(ComboAnsiMetric) then
    Result.ColorMetric := ComboAnsiMetric.ItemIndex
  else
    Result.ColorMetric := 0;

  if Assigned(ComboAnsiDither) then
    Result.DitherStyle := ComboAnsiDither.ItemIndex
  else
    Result.DitherStyle := 0;
  if Assigned(TrackAnsiDitherStrength) then
    Result.DitherStrength := TrackAnsiDitherStrength.Position
  else
    Result.DitherStrength := 0;
  if Assigned(TrackAnsiStability) then
    Result.StabilityPct := TrackAnsiStability.Position
  else
    Result.StabilityPct := 0;
  if Assigned(TrackAnsiEdgeBias) then
    Result.EdgeBiasPct := TrackAnsiEdgeBias.Position
  else
    Result.EdgeBiasPct := 50;

  Result.BiasMode := FAnsiBiasMode;
  Result.BiasStrength := FAnsiBiasStrength;
  Result.LumBucketStrength := FAnsiLumBucketStrength;
  Result.LumBucketThreshold := FAnsiLumBucketThreshold;
  Result.ChromaPenaltyPct := FAnsiChromaPenaltyPct;

  Result.MultiPass4 := Assigned(CheckAnsiMultiPass) and CheckAnsiMultiPass.Checked;

  if Assigned(ComboAnsiStyle) then
    Result.StyleId := ComboAnsiStyle.ItemIndex
  else
    Result.StyleId := 0;


  Result.ForceBg := Assigned(CheckAnsiForceBg) and CheckAnsiForceBg.Checked;
  if Assigned(ComboAnsiForceBg) then
    Result.ForceBgColor := ComboAnsiForceBg.ItemIndex
  else
    Result.ForceBgColor := 0;

  if HasImage then
    sel := ClampSelRect(FSelRect)
  else
    sel := Rect(0, 0, 0, 0);
  Result.Sel := sel;

  if Result.AutoRows and Result.KeepAspect and HasImage then
  begin
    w := Max(1, sel.Right - sel.Left);
    h := Max(1, sel.Bottom - sel.Top);
    if (w > 0) and (h > 0) then
    begin
      Result.Rows := Max(1, Round(Result.Cols * (h / w) * (8.0 / 16.0)));
      if Assigned(SpinAnsiRows) then
      begin
        SpinAnsiRows.OnChange := nil;
        SpinAnsiRows.Value := Result.Rows;
        SpinAnsiRows.OnChange := @AnsiControlsChange;
        SpinAnsiRows.Enabled := False;
      end;
    end;
  end;
  if Assigned(SpinAnsiRows) and (not Result.AutoRows) then
    SpinAnsiRows.Enabled := True;
end;

procedure TMainForm.ApplyAdjustments;
begin
  RequestAdjustments;
end;

procedure TMainForm.ScheduleAdjustments;
begin
  if FClosing then Exit;
  if Assigned(ProcessTimer) then
  begin
    ProcessTimer.Enabled := False;
    ProcessTimer.Enabled := True;
  end
  else
    ApplyAdjustments;
end;

procedure TMainForm.ScheduleAnsiPreview;
begin
  if FClosing then Exit;
  if Assigned(FAnsiDebounceTimer) then
  begin
    FAnsiDebounceTimer.Enabled := False;
    FAnsiDebounceTimer.Enabled := True;
  end
  else
    RequestAnsiPreview;
end;

procedure TMainForm.UpdateViewport;
var
  vw, vh: Integer;
begin
  if not HasImage then Exit;
  if not Assigned(FViewport) then Exit;

  vw := 0; vh := 0;
  if Assigned(SourceOverlay) and (SourceOverlay.Width > 0) and (SourceOverlay.Height > 0) then
  begin
    vw := SourceOverlay.Width;
    vh := SourceOverlay.Height;
  end
  else if Assigned(SourceImage) and (SourceImage.Width > 0) and (SourceImage.Height > 0) then
  begin
    vw := SourceImage.Width;
    vh := SourceImage.Height;
  end;

  if (vw <= 0) or (vh <= 0) then Exit;
  FViewport.SetSizes(FWorking.Width, FWorking.Height, vw, vh);
end;

procedure TMainForm.AnsiDebounceTimerTimer(Sender: TObject);
begin
  if Assigned(FAnsiDebounceTimer) then
    FAnsiDebounceTimer.Enabled := False;
  RequestAnsiPreview;
end;

procedure TMainForm.SetProcessing(const AValue: Boolean);
begin
  FIsProcessing := AValue;
  UpdateStatus;
end;

procedure TMainForm.SetAnsiProcessing(const AValue: Boolean);
begin
  FAnsiIsProcessing := AValue;
  if Assigned(BtnSaveAnsi) then
    BtnSaveAnsi.Enabled := (not FAnsiIsProcessing) and (Length(FAnsiBin) > 0);
  UpdateAnsiStatus(FAnsiCols, FAnsiRows);
end;

procedure TMainForm.RequestAdjustments;
begin
  if FClosing then Exit;
  if not HasImage then Exit;

  Inc(FRequestedJobId);
  FRequestedSettings := CaptureSettings;

  SetProcessing(True);

  if Assigned(FAdjustThread) then
  begin
    // Cancel current job; when it exits we'll start the latest request.
    FAdjustThread.Terminate;
    Exit;
  end;

  StartAdjustThread(FRequestedJobId, FRequestedSettings);
end;

procedure TMainForm.RequestAnsiPreview;
begin
  if FClosing then Exit;
  if not HasImage then Exit;

  // Clear iCE usage flag for the pending conversion.
  FAnsiIceUsed := False;

  Inc(FAnsiRequestedJobId);
  FAnsiRequestedSettings := CaptureAnsiSettings;

  SetAnsiProcessing(True);
  UpdateAnsiStatus(FAnsiRequestedSettings.Cols, FAnsiRequestedSettings.Rows);

  if Assigned(FAnsiThread) then
  begin
    FAnsiThread.Terminate;
    Exit;
  end;

  StartAnsiThread(FAnsiRequestedJobId, FAnsiRequestedSettings);
end;

procedure TMainForm.StartAdjustThread(const AJobId: LongInt; const ASettings: TAdjustSettings);
var
  srcCopy: TBitmap;
  thr: TAdjustWorkerThread;
  y: Integer;
begin
  if FClosing then Exit;
  if not HasImage then Exit;

  srcCopy := TBitmap.Create;
  try
    srcCopy.PixelFormat := pf24bit;
    srcCopy.HandleType := bmDIB;
    srcCopy.Transparent := False;
    srcCopy.SetSize(FSourceBitmap.Width, FSourceBitmap.Height);
    for y := 0 to srcCopy.Height - 1 do
      Move(FSourceBitmap.ScanLine[y]^, srcCopy.ScanLine[y]^, srcCopy.Width * 3);
  except
    srcCopy.Free;
    raise;
  end;

  thr := TAdjustWorkerThread.Create(Self, AJobId, ASettings, srcCopy);
  thr.OnTerminate := @AdjustThreadTerminated;
  FAdjustThread := thr;
  FRunningJobId := AJobId;
  thr.Start;
end;

procedure TMainForm.StartAnsiThread(const AJobId: LongInt; const ASettings: TAnsiConvSettings);
var
  srcCopy: TBitmap;
  thr: TAnsiWorkerThread;
  y: Integer;
begin
  if FClosing then Exit;
  if not HasImage then Exit;

  srcCopy := TBitmap.Create;
  try
    srcCopy.PixelFormat := pf24bit;
    srcCopy.HandleType := bmDIB;
    srcCopy.Transparent := False;
    srcCopy.SetSize(FWorking.Width, FWorking.Height);
    for y := 0 to srcCopy.Height - 1 do
      Move(FWorking.ScanLine[y]^, srcCopy.ScanLine[y]^, srcCopy.Width * 3);
  except
    srcCopy.Free;
    raise;
  end;

  thr := TAnsiWorkerThread.Create(Self, AJobId, ASettings, srcCopy);
  thr.OnTerminate := @AnsiThreadTerminated;
  FAnsiThread := thr;
  FAnsiRunningJobId := AJobId;
  thr.Start;
end;

procedure TMainForm.AdjustThreadTerminated(Sender: TObject);
var
  endedJob: LongInt;
begin
  endedJob := FRunningJobId;

  if Sender = FAdjustThread then
    FAdjustThread := nil;
  FRunningJobId := 0;

  if FClosing then Exit;
  if not HasImage then
  begin
    SetProcessing(False);
    Exit;
  end;

  // If something changed while we were running, kick off the latest request now.
  if FRequestedJobId > endedJob then
    StartAdjustThread(FRequestedJobId, FRequestedSettings)
  else
    SetProcessing(False);
end;

procedure TMainForm.AnsiThreadTerminated(Sender: TObject);
var
  endedJob: LongInt;
begin
  endedJob := FAnsiRunningJobId;

  if Sender = FAnsiThread then
    FAnsiThread := nil;
  FAnsiRunningJobId := 0;

  if FClosing then Exit;
  if not HasImage then
  begin
    SetAnsiProcessing(False);
    Exit;
  end;

  if FAnsiRequestedJobId > endedJob then
    StartAnsiThread(FAnsiRequestedJobId, FAnsiRequestedSettings)
  else
    SetAnsiProcessing(False);
end;

procedure TMainForm.ApplyWorkerResult(const AJobId: LongInt; const AResult: TBitmap);
begin
  if FClosing then Exit;
  if not HasImage then Exit;
  if AJobId <> FRequestedJobId then Exit; // stale result
  if not Assigned(AResult) then Exit;

  FWorking.Assign(AResult);
  if HasImage then
    FSelRect := ClampSelRect(FSelRect);
  RenderScaled(CurrentScale);
  UpdateStatus;
  ScheduleAnsiPreview;
end;

procedure TMainForm.ApplyAnsiResult(const AJobId: LongInt; const ACells: TBytes;
  const APreview: TBitmap; const ACols, ARows: Integer);
var
  ii: Integer;
begin
  if FClosing then Exit;
  if not HasImage then Exit;
  if AJobId <> FAnsiRequestedJobId then Exit;
  if not Assigned(APreview) then Exit;

  FAnsiBin := ACells;
  FAnsiCols := ACols;
  FAnsiRows := ARows;

  // Detect whether this ANSI uses iCE colors (bright background bit stored in $80).
  // We keep this separate from the UI checkbox so export/preview stay correct even if the user toggles the option later.
  FAnsiIceUsed := False;
  if Length(FAnsiBin) >= 2 then
  begin
    for ii := 1 to Length(FAnsiBin) - 1 do
      if (ii and 1) = 1 then // attr bytes are at odd indices
        if (FAnsiBin[ii] and $80) <> 0 then
        begin
          FAnsiIceUsed := True;
          Break;
        end;
  end;

  FAnsiPreview.Assign(APreview);
  if Assigned(AnsiImage) then
  begin
    AnsiImage.Picture.Assign(FAnsiPreview);
    // Avoid relying on AutoSize timing; explicitly size the control to the preview bitmap.
    AnsiImage.AutoSize := False;
    AnsiImage.Stretch := False;
    AnsiImage.Center := False;
    AnsiImage.SetBounds(AnsiImage.Left, AnsiImage.Top, FAnsiPreview.Width, FAnsiPreview.Height);
    AnsiImage.Invalidate;
  end;
  if Assigned(AnsiScroll) then
  begin
    AnsiScroll.HorzScrollBar.Range := FAnsiPreview.Width;
    AnsiScroll.VertScrollBar.Range := FAnsiPreview.Height;
    AnsiScroll.HorzScrollBar.Page := AnsiScroll.ClientWidth;
    AnsiScroll.VertScrollBar.Page := AnsiScroll.ClientHeight;
    if FAnsiCols <= 80 then
      AnsiScroll.HorzScrollBar.Position := 0;
  end;
  if Assigned(BtnSaveAnsi) then
    BtnSaveAnsi.Enabled := Length(FAnsiBin) > 0;

  UpdateAnsiStatus(FAnsiCols, FAnsiRows);
end;

procedure TMainForm.RenderScaled(const AScale: Double);
var
  W, H: Integer;
begin
  if not HasImage then
    Exit;

  if AScale <= 0 then
    Exit;

  W := Max(1, Round(FWorking.Width * AScale));
  H := Max(1, Round(FWorking.Height * AScale));

  FScaled.SetSize(W, H);
  FScaled.PixelFormat := pf24bit;
  FScaled.Canvas.Brush.Color := clBlack;
  FScaled.Canvas.FillRect(0, 0, W, H);
  FScaled.Canvas.StretchDraw(Rect(0, 0, W, H), FWorking);

  SourceImage.Picture.Assign(FScaled);
  // Avoid relying on AutoSize timing; explicitly size the controls to the scaled bitmap.
  SourceImage.AutoSize := False;
  SourceImage.Stretch := False;
  SourceImage.Center := False;
  SourceImage.SetBounds(SourceImage.Left, SourceImage.Top, W, H);

  SourceScroll.HorzScrollBar.Range := W;
  SourceScroll.VertScrollBar.Range := H;
  if Assigned(SourceOverlay) then
  begin
    SourceOverlay.SetBounds(SourceImage.Left, SourceImage.Top, W, H);
    SourceOverlay.BringToFront;
    SourceOverlay.Invalidate;
  end;
  SourceImage.Invalidate;
  UpdateViewport;
  UpdateStatus;
end;

procedure TMainForm.UpdateZoomLabel;
begin
  LabelZoom.Caption := Format('Zoom: %d%%', [ZoomTrack.Position]);
end;

procedure TMainForm.UpdateStatus;
var
  sel: TRect;
  sw, sh: Integer;
begin
  if HasImage and (SourceStatus.Panels.Count >= 3) then
  begin
    SourceStatus.Panels[0].Text := Format('Original: %dx%d', [FSourceBitmap.Width, FSourceBitmap.Height]);
    SourceStatus.Panels[1].Text := Format('Zoom: %d%%', [ZoomTrack.Position]);
    sel := ClampSelRect(FSelRect);
    sw := Max(0, sel.Right - sel.Left);
    sh := Max(0, sel.Bottom - sel.Top);
    SourceStatus.Panels[2].Text := Format('View: %dx%d  Sel: %dx%d', [FScaled.Width, FScaled.Height, sw, sh]);
    if SourceStatus.Panels.Count >= 4 then
    begin
      if FIsProcessing then
        SourceStatus.Panels[3].Text := 'Processing...'
      else
        SourceStatus.Panels[3].Text := 'Ready';
    end;
  end
  else
  begin
    SourceStatus.SimpleText := 'No image loaded';
  end;
end;

procedure TMainForm.ResetSelection;
begin
  if not HasImage then
  begin
    FSelActive := False;
    FSelRect := Rect(0, 0, 0, 0);
    Exit;
  end;

  FSelRect := Rect(0, 0, FWorking.Width, FWorking.Height);
  FSelActive := True;
  FSelecting := False;
  FSelDragMode := sdNone;
  FSelDragHandle := shNone;
  FSelHoverHandle := shNone;

  if Assigned(SourceOverlay) then
    SourceOverlay.Invalidate;
end;

function TMainForm.ClampSelRect(const R: TRect): TRect;
var
  l, t, rr, bb: Integer;
  w, h: Integer;
begin
  Result := R;
  if not HasImage then
    Exit(Rect(0, 0, 0, 0));

  w := FWorking.Width;
  h := FWorking.Height;
  if (w <= 0) or (h <= 0) then
    Exit(Rect(0, 0, 0, 0));

  l := Min(Result.Left, Result.Right);
  rr := Max(Result.Left, Result.Right);
  t := Min(Result.Top, Result.Bottom);
  bb := Max(Result.Top, Result.Bottom);

  // Right/Bottom are exclusive. Ensure we always have at least 1 pixel selected.
  l := EnsureRange(l, 0, w - 1);
  rr := EnsureRange(rr, 1, w);
  if rr <= l then rr := Min(w, l + 1);

  t := EnsureRange(t, 0, h - 1);
  bb := EnsureRange(bb, 1, h);
  if bb <= t then bb := Min(h, t + 1);

  Result := Rect(l, t, rr, bb);
end;

function TMainForm.WorkingToDisplayRect(const R: TRect): TRect;
begin
  Result := Rect(0, 0, 0, 0);
  if not HasImage then Exit;
  UpdateViewport;
  if Assigned(FViewport) then
    Result := FViewport.ImageToViewRect(R);
end;

function TMainForm.DisplayToWorkingPoint(const P: TPoint): TPoint;
begin
  Result := Point(0, 0);
  if not HasImage then Exit;
  UpdateViewport;
  if Assigned(FViewport) then
    Result := FViewport.ViewToImagePoint(P);
end;

function TMainForm.HitTestSelection(const PDisp: TPoint; out HitHandle: TSelHandle): Boolean;
const
  HANDLE_SIZE = 13;
  HANDLE_HALF = HANDLE_SIZE div 2;
var
  dr: TRect;
  leftPx, rightPx, topPx, bottomPx: Integer;
  midX, midY: Integer;

  function PtInHandle(cx, cy: Integer): Boolean;
  var
    hr: TRect;
  begin
    hr := Rect(cx - HANDLE_HALF, cy - HANDLE_HALF, cx + HANDLE_HALF + 1, cy + HANDLE_HALF + 1);
    Result := PtInRect(hr, PDisp);
  end;
begin
  Result := False;
  HitHandle := shNone;
  if not HasImage then Exit;
  if not (FSelActive or FSelecting) then Exit;

  dr := WorkingToDisplayRect(ClampSelRect(FSelRect));
  if (dr.Right <= dr.Left) or (dr.Bottom <= dr.Top) then Exit;

  leftPx := dr.Left;
  topPx := dr.Top;
  rightPx := dr.Right - 1;
  bottomPx := dr.Bottom - 1;
  if rightPx < leftPx then rightPx := leftPx;
  if bottomPx < topPx then bottomPx := topPx;
  midX := (leftPx + rightPx) div 2;
  midY := (topPx + bottomPx) div 2;

  // Handles first.
  if PtInHandle(leftPx, topPx) then begin HitHandle := shNW; Exit(True); end;
  if PtInHandle(rightPx, topPx) then begin HitHandle := shNE; Exit(True); end;
  if PtInHandle(leftPx, bottomPx) then begin HitHandle := shSW; Exit(True); end;
  if PtInHandle(rightPx, bottomPx) then begin HitHandle := shSE; Exit(True); end;
  if PtInHandle(midX, topPx) then begin HitHandle := shN; Exit(True); end;
  if PtInHandle(midX, bottomPx) then begin HitHandle := shS; Exit(True); end;
  if PtInHandle(leftPx, midY) then begin HitHandle := shW; Exit(True); end;
  if PtInHandle(rightPx, midY) then begin HitHandle := shE; Exit(True); end;

  // Inside selection -> move.
  if PtInRect(dr, PDisp) then
    Exit(True);
end;

procedure TMainForm.UpdateSelectionCursor(const PDisp: TPoint);
var
  h: TSelHandle;
begin
  if not Assigned(SourceOverlay) then Exit;

  if not HasImage then
  begin
    SourceOverlay.Cursor := crDefault;
    Exit;
  end;

  if HitTestSelection(PDisp, h) then
  begin
    case h of
      shN, shS: SourceOverlay.Cursor := crSizeNS;
      shE, shW: SourceOverlay.Cursor := crSizeWE;
      shNW, shSE: SourceOverlay.Cursor := crSizeNWSE;
      shNE, shSW: SourceOverlay.Cursor := crSizeNESW;
    else
      SourceOverlay.Cursor := crSizeAll;
    end;
  end
  else
    SourceOverlay.Cursor := crCross;
end;

procedure TMainForm.UpdateAnsiStatus(const ACols, ARows: Integer);
var
  sampleText: string;
  iceText: string;
begin
  if not Assigned(AnsiStatus) then Exit;

  if AnsiStatus.Panels.Count >= 3 then
  begin
    if (ACols > 0) and (ARows > 0) then
      AnsiStatus.Panels[0].Text := Format('ANSI: %dx%d', [ACols, ARows])
    else
      AnsiStatus.Panels[0].Text := 'ANSI:';

    if Assigned(ComboAnsiSample) then
      sampleText := 'Sample: ' + ComboAnsiSample.Text
    else
      sampleText := 'Sample:';
    AnsiStatus.Panels[1].Text := sampleText;

    if Assigned(CheckICE) then
    begin
      if CheckICE.Checked then iceText := 'iCE: On' else iceText := 'iCE: Off';
    end
    else
      iceText := 'iCE:';
    AnsiStatus.Panels[2].Text := iceText;

    if AnsiStatus.Panels.Count >= 4 then
    begin
      if FAnsiIsProcessing then
        AnsiStatus.Panels[3].Text := 'Processing...'
      else
        AnsiStatus.Panels[3].Text := 'Ready';
    end;
  end
  else
  begin
    if (ACols > 0) and (ARows > 0) then
      AnsiStatus.SimpleText := Format('ANSI: %dx%d', [ACols, ARows])
    else
      AnsiStatus.SimpleText := 'ANSI preview';
  end;
end;

procedure TMainForm.UpdateScrollPages;
begin
  if Assigned(SourceScroll) then
  begin
    SourceScroll.HorzScrollBar.Page := SourceScroll.ClientWidth;
    SourceScroll.VertScrollBar.Page := SourceScroll.ClientHeight;
    SourceScroll.HorzScrollBar.Increment := Max(8, SourceScroll.ClientWidth div 20); // ~5% per step
    SourceScroll.VertScrollBar.Increment := Max(8, SourceScroll.ClientHeight div 20);
  end;
end;

function TMainForm.UserDataRootDir: string;
begin
  // Per-user, per-app writable directory (Windows: AppData\Roaming\<App>\)
  Result := IncludeTrailingPathDelimiter(GetAppConfigDir(False));
end;

function TMainForm.GetPresetsDir: string;
begin
  Result := UserDataRootDir + 'presets' + DirectorySeparator;
end;

function TMainForm.GetOutputDir: string;
begin
  Result := UserDataRootDir + 'output' + DirectorySeparator;
end;

procedure TMainForm.EnsureAppDirs;
  procedure SafeForceDirs(const Dir: string);
  begin
    try
      if Dir <> '' then
        ForceDirectories(Dir);
    except
      // ignore
    end;
  end;
begin
  if FPresetsDir = '' then FPresetsDir := GetPresetsDir;
  if FOutputDir = '' then FOutputDir := GetOutputDir;
  SafeForceDirs(UserDataRootDir);
  SafeForceDirs(FPresetsDir);
  SafeForceDirs(FOutputDir);
end;

procedure TMainForm.LoadSettingsFromIni(const Ini: TIniFile);
var
  v: Integer;
  s: string;
begin
  if not Assigned(Ini) then Exit;

  // UI
  if Assigned(FitCheck) then
    FitCheck.Checked := Ini.ReadBool('UI', 'FitOnLoad', FitCheck.Checked);

  if Assigned(ZoomTrack) then
  begin
    v := Ini.ReadInteger('UI', 'ZoomPct', ZoomTrack.Position);
    ZoomTrack.Position := EnsureRange(v, ZoomTrack.Min, ZoomTrack.Max);
    UpdateZoomLabel;
  end;

  s := Ini.ReadString('UI', 'LastImageDir', '');
  if s <> '' then
    FLastImageDir := s;

  // Source mods
  if Assigned(TrackRed) then
    TrackRed.Position := EnsureRange(Ini.ReadInteger('Source', 'RedPct', TrackRed.Position), TrackRed.Min, TrackRed.Max);
  if Assigned(TrackGreen) then
    TrackGreen.Position := EnsureRange(Ini.ReadInteger('Source', 'GreenPct', TrackGreen.Position), TrackGreen.Min, TrackGreen.Max);
  if Assigned(TrackBlue) then
    TrackBlue.Position := EnsureRange(Ini.ReadInteger('Source', 'BluePct', TrackBlue.Position), TrackBlue.Min, TrackBlue.Max);
  if Assigned(TrackBrightness) then
    TrackBrightness.Position := EnsureRange(Ini.ReadInteger('Source', 'Brightness', TrackBrightness.Position), TrackBrightness.Min, TrackBrightness.Max);
  if Assigned(TrackContrast) then
    TrackContrast.Position := EnsureRange(Ini.ReadInteger('Source', 'Contrast', TrackContrast.Position), TrackContrast.Min, TrackContrast.Max);
  if Assigned(CheckAutoContrast) then
    CheckAutoContrast.Checked := Ini.ReadBool('Source', 'AutoContrast', CheckAutoContrast.Checked);
  if Assigned(TrackGamma) then
    TrackGamma.Position := EnsureRange(Ini.ReadInteger('Source', 'GammaPct', TrackGamma.Position), TrackGamma.Min, TrackGamma.Max);
  if Assigned(TrackSaturation) then
    TrackSaturation.Position := EnsureRange(Ini.ReadInteger('Source', 'SaturationPct', TrackSaturation.Position), TrackSaturation.Min, TrackSaturation.Max);
  if Assigned(TrackHue) then
    TrackHue.Position := EnsureRange(Ini.ReadInteger('Source', 'HueDeg', TrackHue.Position), TrackHue.Min, TrackHue.Max);
  if Assigned(TrackMidContrast) then
    TrackMidContrast.Position := EnsureRange(Ini.ReadInteger('Source', 'MidContrast', TrackMidContrast.Position), TrackMidContrast.Min, TrackMidContrast.Max);
  if Assigned(TrackBlur) then
    TrackBlur.Position := EnsureRange(Ini.ReadInteger('Source', 'BlurRadius', TrackBlur.Position), TrackBlur.Min, TrackBlur.Max);
  if Assigned(TrackSharpen) then
    TrackSharpen.Position := EnsureRange(Ini.ReadInteger('Source', 'SharpenAmt', TrackSharpen.Position), TrackSharpen.Min, TrackSharpen.Max);
  if Assigned(TrackClarity) then
    TrackClarity.Position := EnsureRange(Ini.ReadInteger('Source', 'ClarityAmt', TrackClarity.Position), TrackClarity.Min, TrackClarity.Max);
  if Assigned(TrackDenoise) then
    TrackDenoise.Position := EnsureRange(Ini.ReadInteger('Source', 'DenoisePasses', TrackDenoise.Position), TrackDenoise.Min, TrackDenoise.Max);
  if Assigned(TrackChromaDenoise) then
    TrackChromaDenoise.Position := EnsureRange(Ini.ReadInteger('Source', 'ChromaDenoiseAmt', TrackChromaDenoise.Position), TrackChromaDenoise.Min, TrackChromaDenoise.Max);
  if Assigned(TrackGuided) then
    TrackGuided.Position := EnsureRange(Ini.ReadInteger('Source', 'GuidedAmt', TrackGuided.Position), TrackGuided.Min, TrackGuided.Max);
  if Assigned(TrackEdge) then
    TrackEdge.Position := EnsureRange(Ini.ReadInteger('Source', 'EdgeAmt', TrackEdge.Position), TrackEdge.Min, TrackEdge.Max);
  if Assigned(TrackBilateral) then
    TrackBilateral.Position := EnsureRange(Ini.ReadInteger('Source', 'BilateralAmt', TrackBilateral.Position), TrackBilateral.Min, TrackBilateral.Max);
  if Assigned(TrackDosBias) then
    TrackDosBias.Position := EnsureRange(Ini.ReadInteger('Source', 'DosBiasPct', TrackDosBias.Position), TrackDosBias.Min, TrackDosBias.Max);

  if Assigned(ComboEdgeStyle) then
  begin
    v := Ini.ReadInteger('Source', 'EdgeStyle', ComboEdgeStyle.ItemIndex);
    ComboEdgeStyle.ItemIndex := EnsureRange(v, 0, Max(0, ComboEdgeStyle.Items.Count - 1));
  end;

  if Assigned(ComboQuantMethod) then
  begin
    v := Ini.ReadInteger('Source', 'QuantMethod', ComboQuantMethod.ItemIndex);
    ComboQuantMethod.ItemIndex := EnsureRange(v, 0, Max(0, ComboQuantMethod.Items.Count - 1));
  end;

  if Assigned(ComboQuantize) then
  begin
    v := Ini.ReadInteger('Source', 'QuantLevels', StrToIntDef(ComboQuantize.Text, 256));
    ComboQuantize.Text := IntToStr(EnsureRange(v, 2, 256));
  end;

  if Assigned(ComboDither) then
  begin
    v := Ini.ReadInteger('Source', 'DitherStyle', ComboDither.ItemIndex);
    ComboDither.ItemIndex := EnsureRange(v, 0, Max(0, ComboDither.Items.Count - 1));
  end;

  // ANSI preview
  if Assigned(SpinAnsiCols) then
  begin
    v := Ini.ReadInteger('Ansi', 'Cols', SpinAnsiCols.Value);
    SpinAnsiCols.Value := EnsureRange(v, SpinAnsiCols.MinValue, SpinAnsiCols.MaxValue);
  end;

  if Assigned(SpinAnsiRows) then
  begin
    v := Ini.ReadInteger('Ansi', 'Rows', SpinAnsiRows.Value);
    SpinAnsiRows.Value := EnsureRange(v, SpinAnsiRows.MinValue, SpinAnsiRows.MaxValue);
  end;

  if Assigned(CheckAnsiKeepAspect) then
    CheckAnsiKeepAspect.Checked := Ini.ReadBool('Ansi', 'KeepAspect', CheckAnsiKeepAspect.Checked);

  if Assigned(CheckAnsiAutoRows) then
    CheckAnsiAutoRows.Checked := Ini.ReadBool('Ansi', 'AutoRows', CheckAnsiAutoRows.Checked);

  if Assigned(CheckICE) then
    CheckICE.Checked := Ini.ReadBool('Ansi', 'IceColors', CheckICE.Checked);

  if Assigned(CheckAnsiMultiPass) then
    CheckAnsiMultiPass.Checked := Ini.ReadBool('Ansi', 'MultiPass4', CheckAnsiMultiPass.Checked);

  if Assigned(ComboAnsiStyle) then
  begin
    v := Ini.ReadInteger('Ansi', 'Style', ComboAnsiStyle.ItemIndex);
    ComboAnsiStyle.ItemIndex := EnsureRange(v, 0, Max(0, ComboAnsiStyle.Items.Count - 1));
  end;


  if Assigned(ComboAnsiSample) then
  begin
    v := Ini.ReadInteger('Ansi', 'SampleMode', ComboAnsiSample.ItemIndex);
    ComboAnsiSample.ItemIndex := EnsureRange(v, 0, Max(0, ComboAnsiSample.Items.Count - 1));
  end;

  if Assigned(ComboAnsiMetric) then
  begin
    v := Ini.ReadInteger('Ansi', 'ColorMetric', ComboAnsiMetric.ItemIndex);
    ComboAnsiMetric.ItemIndex := EnsureRange(v, 0, Max(0, ComboAnsiMetric.Items.Count - 1));
  end;

  if Assigned(CheckAnsiForceBg) then
    CheckAnsiForceBg.Checked := Ini.ReadBool('Ansi', 'ForceBg', CheckAnsiForceBg.Checked);

  if Assigned(ComboAnsiForceBg) then
  begin
    v := Ini.ReadInteger('Ansi', 'ForceBgColor', ComboAnsiForceBg.ItemIndex);
    ComboAnsiForceBg.ItemIndex := EnsureRange(v, 0, Max(0, ComboAnsiForceBg.Items.Count - 1));
  end;

  if Assigned(ComboAnsiDither) then
  begin
    v := Ini.ReadInteger('Ansi', 'DitherStyle', ComboAnsiDither.ItemIndex);
    ComboAnsiDither.ItemIndex := EnsureRange(v, 0, Max(0, ComboAnsiDither.Items.Count - 1));
  end;

  if Assigned(TrackAnsiDitherStrength) then
  begin
    v := Ini.ReadInteger('Ansi', 'DitherStrength', TrackAnsiDitherStrength.Position);
    TrackAnsiDitherStrength.Position := EnsureRange(v, TrackAnsiDitherStrength.Min, TrackAnsiDitherStrength.Max);
  end;

  if Assigned(TrackAnsiStability) then
  begin
    v := Ini.ReadInteger('Ansi', 'StabilityPct', TrackAnsiStability.Position);
    TrackAnsiStability.Position := EnsureRange(v, TrackAnsiStability.Min, TrackAnsiStability.Max);
  end;

  if Assigned(TrackAnsiEdgeBias) then
  begin
    v := Ini.ReadInteger('Ansi', 'EdgeBiasPct', TrackAnsiEdgeBias.Position);
    TrackAnsiEdgeBias.Position := EnsureRange(v, TrackAnsiEdgeBias.Min, TrackAnsiEdgeBias.Max);
  end;

  // ANSI advanced scoring options (no direct main-form controls)
  FAnsiBiasMode := EnsureRange(Ini.ReadInteger('AnsiAdv', 'BiasMode', FAnsiBiasMode), 0, 4);
  FAnsiBiasStrength := EnsureRange(Ini.ReadInteger('AnsiAdv', 'BiasStrength', FAnsiBiasStrength), 0, 100);
  FAnsiLumBucketStrength := EnsureRange(Ini.ReadInteger('AnsiAdv', 'LumBucketStrength', FAnsiLumBucketStrength), 0, 100);
  FAnsiLumBucketThreshold := EnsureRange(Ini.ReadInteger('AnsiAdv', 'LumBucketThreshold', FAnsiLumBucketThreshold), 0, 255);
  FAnsiChromaPenaltyPct := EnsureRange(Ini.ReadInteger('AnsiAdv', 'ChromaPenaltyPct', FAnsiChromaPenaltyPct), 0, 100);

  // Tutorial learned knobs
  FTutShadeBasePenalty := Ini.ReadFloat('Tut', 'ShadeBasePenalty', FTutShadeBasePenalty);
  FTutShadeEdgeMult := Ini.ReadFloat('Tut', 'ShadeEdgeMult', FTutShadeEdgeMult);
  FTutShadeFlatMult := Ini.ReadFloat('Tut', 'ShadeFlatMult', FTutShadeFlatMult);
  FTutHalfEdgeMult := Ini.ReadFloat('Tut', 'HalfEdgeMult', FTutHalfEdgeMult);
  FTutHalfFlatMult := Ini.ReadFloat('Tut', 'HalfFlatMult', FTutHalfFlatMult);
  FTutOrientMult := Ini.ReadFloat('Tut', 'OrientMult', FTutOrientMult);
  FTutEdgeBiasFloor := EnsureRange(Ini.ReadInteger('Tut', 'EdgeBiasFloor', FTutEdgeBiasFloor), 0, 100);
  FTutStabilityFloor := EnsureRange(Ini.ReadInteger('Tut', 'StabilityFloor', FTutStabilityFloor), 0, 100);
  FTutLumBucketStrength := EnsureRange(Ini.ReadInteger('Tut', 'LumBucketStrength', FTutLumBucketStrength), 0, 100);
  FTutChromaPenalty := EnsureRange(Ini.ReadInteger('Tut', 'ChromaPenalty', FTutChromaPenalty), 0, 100);
  FTutForceBg := Ini.ReadBool('Tut', 'ForceBg', FTutForceBg);
  FTutForceBgColor := EnsureRange(Ini.ReadInteger('Tut', 'ForceBgColor', FTutForceBgColor), 0, 15);

  // Keep dependent UI in sync.
  if Assigned(CheckAnsiForceBg) and Assigned(ComboAnsiForceBg) then
    ComboAnsiForceBg.Enabled := CheckAnsiForceBg.Checked;
  if Assigned(ComboAnsiDither) and Assigned(TrackAnsiDitherStrength) then
    TrackAnsiDitherStrength.Enabled := ComboAnsiDither.ItemIndex <> 0;
  if Assigned(CheckAnsiMultiPass) and Assigned(ComboAnsiStyle) then
  begin
    ComboAnsiStyle.Enabled := CheckAnsiMultiPass.Checked;
    if Assigned(LabelAnsiStyle) then
      LabelAnsiStyle.Enabled := CheckAnsiMultiPass.Checked;
  end;

end;

procedure TMainForm.SaveSettingsToIni(const Ini: TIniFile);
begin
  if not Assigned(Ini) then Exit;

  // UI
  if Assigned(FitCheck) then
    Ini.WriteBool('UI', 'FitOnLoad', FitCheck.Checked);
  if Assigned(ZoomTrack) then
    Ini.WriteInteger('UI', 'ZoomPct', ZoomTrack.Position);
  if FLastImageDir <> '' then
    Ini.WriteString('UI', 'LastImageDir', FLastImageDir);

  // Source mods
  if Assigned(TrackRed) then Ini.WriteInteger('Source', 'RedPct', TrackRed.Position);
  if Assigned(TrackGreen) then Ini.WriteInteger('Source', 'GreenPct', TrackGreen.Position);
  if Assigned(TrackBlue) then Ini.WriteInteger('Source', 'BluePct', TrackBlue.Position);
  if Assigned(TrackBrightness) then Ini.WriteInteger('Source', 'Brightness', TrackBrightness.Position);
  if Assigned(TrackContrast) then Ini.WriteInteger('Source', 'Contrast', TrackContrast.Position);
  if Assigned(CheckAutoContrast) then Ini.WriteBool('Source', 'AutoContrast', CheckAutoContrast.Checked);
  if Assigned(TrackGamma) then Ini.WriteInteger('Source', 'GammaPct', TrackGamma.Position);
  if Assigned(TrackSaturation) then Ini.WriteInteger('Source', 'SaturationPct', TrackSaturation.Position);
  if Assigned(TrackHue) then Ini.WriteInteger('Source', 'HueDeg', TrackHue.Position);
  if Assigned(TrackMidContrast) then Ini.WriteInteger('Source', 'MidContrast', TrackMidContrast.Position);
  if Assigned(TrackBlur) then Ini.WriteInteger('Source', 'BlurRadius', TrackBlur.Position);
  if Assigned(TrackSharpen) then Ini.WriteInteger('Source', 'SharpenAmt', TrackSharpen.Position);
  if Assigned(TrackClarity) then Ini.WriteInteger('Source', 'ClarityAmt', TrackClarity.Position);
  if Assigned(TrackDenoise) then Ini.WriteInteger('Source', 'DenoisePasses', TrackDenoise.Position);
  if Assigned(TrackChromaDenoise) then Ini.WriteInteger('Source', 'ChromaDenoiseAmt', TrackChromaDenoise.Position);
  if Assigned(TrackGuided) then Ini.WriteInteger('Source', 'GuidedAmt', TrackGuided.Position);
  if Assigned(TrackEdge) then Ini.WriteInteger('Source', 'EdgeAmt', TrackEdge.Position);
  if Assigned(TrackBilateral) then Ini.WriteInteger('Source', 'BilateralAmt', TrackBilateral.Position);
  if Assigned(TrackDosBias) then Ini.WriteInteger('Source', 'DosBiasPct', TrackDosBias.Position);

  if Assigned(ComboEdgeStyle) then Ini.WriteInteger('Source', 'EdgeStyle', ComboEdgeStyle.ItemIndex);
  if Assigned(ComboQuantMethod) then Ini.WriteInteger('Source', 'QuantMethod', ComboQuantMethod.ItemIndex);
  if Assigned(ComboQuantize) then Ini.WriteInteger('Source', 'QuantLevels', StrToIntDef(ComboQuantize.Text, 256));
  if Assigned(ComboDither) then Ini.WriteInteger('Source', 'DitherStyle', ComboDither.ItemIndex);

  // ANSI preview
  if Assigned(SpinAnsiCols) then Ini.WriteInteger('Ansi', 'Cols', SpinAnsiCols.Value);
  if Assigned(SpinAnsiRows) then Ini.WriteInteger('Ansi', 'Rows', SpinAnsiRows.Value);
  if Assigned(CheckAnsiKeepAspect) then Ini.WriteBool('Ansi', 'KeepAspect', CheckAnsiKeepAspect.Checked);
  if Assigned(CheckAnsiAutoRows) then Ini.WriteBool('Ansi', 'AutoRows', CheckAnsiAutoRows.Checked);
  if Assigned(CheckICE) then Ini.WriteBool('Ansi', 'IceColors', CheckICE.Checked);
  if Assigned(CheckAnsiMultiPass) then Ini.WriteBool('Ansi', 'MultiPass4', CheckAnsiMultiPass.Checked);
  if Assigned(ComboAnsiStyle) then Ini.WriteInteger('Ansi', 'Style', ComboAnsiStyle.ItemIndex);
  if Assigned(ComboAnsiSample) then Ini.WriteInteger('Ansi', 'SampleMode', ComboAnsiSample.ItemIndex);
  if Assigned(ComboAnsiMetric) then Ini.WriteInteger('Ansi', 'ColorMetric', ComboAnsiMetric.ItemIndex);
  if Assigned(CheckAnsiForceBg) then Ini.WriteBool('Ansi', 'ForceBg', CheckAnsiForceBg.Checked);
  if Assigned(ComboAnsiForceBg) then Ini.WriteInteger('Ansi', 'ForceBgColor', ComboAnsiForceBg.ItemIndex);
  if Assigned(ComboAnsiDither) then Ini.WriteInteger('Ansi', 'DitherStyle', ComboAnsiDither.ItemIndex);
  if Assigned(TrackAnsiDitherStrength) then Ini.WriteInteger('Ansi', 'DitherStrength', TrackAnsiDitherStrength.Position);
  if Assigned(TrackAnsiStability) then Ini.WriteInteger('Ansi', 'StabilityPct', TrackAnsiStability.Position);
  if Assigned(TrackAnsiEdgeBias) then Ini.WriteInteger('Ansi', 'EdgeBiasPct', TrackAnsiEdgeBias.Position);

  // ANSI advanced scoring options
  Ini.WriteInteger('AnsiAdv', 'BiasMode', FAnsiBiasMode);
  Ini.WriteInteger('AnsiAdv', 'BiasStrength', FAnsiBiasStrength);
  Ini.WriteInteger('AnsiAdv', 'LumBucketStrength', FAnsiLumBucketStrength);
  Ini.WriteInteger('AnsiAdv', 'LumBucketThreshold', FAnsiLumBucketThreshold);
  Ini.WriteInteger('AnsiAdv', 'ChromaPenaltyPct', FAnsiChromaPenaltyPct);

  // Tutorial learned knobs
  Ini.WriteFloat('Tut', 'ShadeBasePenalty', FTutShadeBasePenalty);
  Ini.WriteFloat('Tut', 'ShadeEdgeMult', FTutShadeEdgeMult);
  Ini.WriteFloat('Tut', 'ShadeFlatMult', FTutShadeFlatMult);
  Ini.WriteFloat('Tut', 'HalfEdgeMult', FTutHalfEdgeMult);
  Ini.WriteFloat('Tut', 'HalfFlatMult', FTutHalfFlatMult);
  Ini.WriteFloat('Tut', 'OrientMult', FTutOrientMult);
  Ini.WriteInteger('Tut', 'EdgeBiasFloor', FTutEdgeBiasFloor);
  Ini.WriteInteger('Tut', 'StabilityFloor', FTutStabilityFloor);
  Ini.WriteInteger('Tut', 'LumBucketStrength', FTutLumBucketStrength);
  Ini.WriteInteger('Tut', 'ChromaPenalty', FTutChromaPenalty);
  Ini.WriteBool('Tut', 'ForceBg', FTutForceBg);
  Ini.WriteInteger('Tut', 'ForceBgColor', FTutForceBgColor);
end;

procedure TMainForm.LoadAppIni;
var
  Ini: TIniFile;
begin
  if FAppIniPath = '' then
    FAppIniPath := UserDataRootDir + 'rez2ans.ini';
  if not FileExists(FAppIniPath) then Exit;

  try
    Ini := TIniFile.Create(FAppIniPath);
    try
      FUpdatingControls := True;
      try
        LoadSettingsFromIni(Ini);
      finally
        FUpdatingControls := False;
      end;
    finally
      Ini.Free;
    end;
  except
    // ignore corrupt ini
  end;
end;

procedure TMainForm.SaveAppIni;
var
  Ini: TIniFile;
begin
  if FAppIniPath = '' then
    FAppIniPath := UserDataRootDir + 'rez2ans.ini';

  try
    EnsureAppDirs;
    Ini := TIniFile.Create(FAppIniPath);
    try
      SaveSettingsToIni(Ini);
    finally
      Ini.Free;
    end;
  except
    // ignore
  end;
end;

procedure TMainForm.ResetFactoryDefaults;
begin
  FUpdatingControls := True;
  try
    if Assigned(FitCheck) then FitCheck.Checked := True;
    if Assigned(ZoomTrack) then
    begin
      ZoomTrack.Position := 100;
      UpdateZoomLabel;
    end;

    if Assigned(TrackRed) then TrackRed.Position := 100;
    if Assigned(TrackGreen) then TrackGreen.Position := 100;
    if Assigned(TrackBlue) then TrackBlue.Position := 100;
    if Assigned(TrackBrightness) then TrackBrightness.Position := 0;
    if Assigned(TrackContrast) then TrackContrast.Position := 0;
    if Assigned(CheckAutoContrast) then CheckAutoContrast.Checked := False;
    if Assigned(TrackGamma) then TrackGamma.Position := 100;
    if Assigned(TrackSaturation) then TrackSaturation.Position := 100;
    if Assigned(TrackHue) then TrackHue.Position := 0;
    if Assigned(TrackMidContrast) then TrackMidContrast.Position := 0;

    if Assigned(TrackBlur) then TrackBlur.Position := 0;
    if Assigned(TrackSharpen) then TrackSharpen.Position := 0;
    if Assigned(TrackClarity) then TrackClarity.Position := 0;
    if Assigned(TrackDenoise) then TrackDenoise.Position := 0;
    if Assigned(TrackChromaDenoise) then TrackChromaDenoise.Position := 0;
    if Assigned(TrackGuided) then TrackGuided.Position := 0;
    if Assigned(TrackEdge) then TrackEdge.Position := 0;
    if Assigned(TrackBilateral) then TrackBilateral.Position := 0;
    if Assigned(ComboEdgeStyle) then ComboEdgeStyle.ItemIndex := 1; // Sobel Enhance

    if Assigned(ComboQuantize) then ComboQuantize.Text := '256';
    if Assigned(ComboDither) then ComboDither.ItemIndex := 0; // None
    if Assigned(ComboQuantMethod) then ComboQuantMethod.ItemIndex := 1; // Uniform RGB
    if Assigned(TrackDosBias) then TrackDosBias.Position := 0;

    if Assigned(SpinAnsiCols) then SpinAnsiCols.Value := 80;
    if Assigned(SpinAnsiRows) then SpinAnsiRows.Value := 25;
    if Assigned(CheckAnsiKeepAspect) then CheckAnsiKeepAspect.Checked := True;
    if Assigned(CheckAnsiAutoRows) then CheckAnsiAutoRows.Checked := True;
    if Assigned(CheckICE) then CheckICE.Checked := False;
    if Assigned(CheckAnsiMultiPass) then CheckAnsiMultiPass.Checked := False;
    if Assigned(ComboAnsiStyle) then
    begin
      ComboAnsiStyle.ItemIndex := 0;
      ComboAnsiStyle.Enabled := False;
    end;
    if Assigned(LabelAnsiStyle) then LabelAnsiStyle.Enabled := False;
    if Assigned(ComboAnsiSample) then ComboAnsiSample.ItemIndex := 2; // 2x4
    if Assigned(ComboAnsiMetric) then ComboAnsiMetric.ItemIndex := 1; // Redmean
    if Assigned(CheckAnsiForceBg) then CheckAnsiForceBg.Checked := False;
    if Assigned(ComboAnsiForceBg) then
    begin
      ComboAnsiForceBg.ItemIndex := 0;
      ComboAnsiForceBg.Enabled := False;
    end;
    if Assigned(ComboAnsiDither) then ComboAnsiDither.ItemIndex := 0; // None
    if Assigned(TrackAnsiDitherStrength) then
    begin
      TrackAnsiDitherStrength.Position := 40;
      TrackAnsiDitherStrength.Enabled := False;
    end;
    if Assigned(TrackAnsiStability) then TrackAnsiStability.Position := 0;
    if Assigned(TrackAnsiEdgeBias) then TrackAnsiEdgeBias.Position := 50;
    FAnsiBiasMode := 0;
    FAnsiBiasStrength := 0;
    FAnsiLumBucketStrength := 0;
    FAnsiLumBucketThreshold := 128;
    FAnsiChromaPenaltyPct := 0;

    if HasImage then
      ResetSelection;
  finally
    FUpdatingControls := False;
  end;

  UpdateStatus;
  if HasImage then
  begin
    ApplyFitIfNeeded;
    RenderScaled(CurrentScale);
    ApplyAdjustments;
    ScheduleAnsiPreview;
  end;
end;

procedure TMainForm.ShowPathsHelp;
var
  msg: string;
  dlg: TForm;
  i: Integer;
  btn: TCustomButton;
begin
  EnsureAppDirs;
  msg := 'Output directory:' + LineEnding + FOutputDir + LineEnding + LineEnding +
         'Presets directory:' + LineEnding + FPresetsDir + LineEnding + LineEnding +
         'Config INI:' + LineEnding + FAppIniPath;

  dlg := CreateMessageDialog(msg, mtInformation, [mbOK, mbYes]);
  try
    dlg.Caption := 'rez2ans paths';
    // Re-label buttons to something meaningful.
    for i := 0 to dlg.ComponentCount - 1 do
      if dlg.Components[i] is TCustomButton then
      begin
        btn := TCustomButton(dlg.Components[i]);
        if btn.ModalResult = mrYes then
          btn.Caption := 'Open output folder';
      end;

    FitDialogButtonsRight(dlg, 140);

    if dlg.ShowModal = mrYes then
      OpenDocument(FOutputDir);
  finally
    dlg.Free;
  end;
end;

procedure TMainForm.MenuLoadSettingsClick(Sender: TObject);
var
  fn: string;
  Ini: TIniFile;
begin
  EnsureAppDirs;
  if not Assigned(FSettingsOpenDialog) then Exit;
  if (FPresetsDir <> '') and DirectoryExists(FPresetsDir) then
    FSettingsOpenDialog.InitialDir := FPresetsDir;

  if not FSettingsOpenDialog.Execute then Exit;
  fn := FSettingsOpenDialog.FileName;
  if fn = '' then Exit;

  try
    Ini := TIniFile.Create(fn);
    try
      FUpdatingControls := True;
      try
        LoadSettingsFromIni(Ini);
      finally
        FUpdatingControls := False;
      end;
    finally
      Ini.Free;
    end;
  except
    on E: Exception do
      MessageDlg('Load settings failed', E.Message, mtError, [mbOK], 0);
  end;

  UpdateStatus;
  if HasImage then
  begin
    ApplyFitIfNeeded;
    RenderScaled(CurrentScale);
    ApplyAdjustments;
    ScheduleAnsiPreview;
  end;
end;

procedure TMainForm.MenuSaveSettingsClick(Sender: TObject);
var
  fn: string;
  Ini: TIniFile;
begin
  EnsureAppDirs;
  if not Assigned(FSettingsSaveDialog) then Exit;
  if (FPresetsDir <> '') and DirectoryExists(FPresetsDir) then
    FSettingsSaveDialog.InitialDir := FPresetsDir;

  if (FSettingsSaveDialog.FileName = '') or (ExtractFilePath(FSettingsSaveDialog.FileName) = '') then
  begin
    if FPresetsDir <> '' then
      FSettingsSaveDialog.FileName := IncludeTrailingPathDelimiter(FPresetsDir) + 'preset.ini'
    else
      FSettingsSaveDialog.FileName := 'preset.ini';
  end;

  if not FSettingsSaveDialog.Execute then Exit;
  fn := FSettingsSaveDialog.FileName;
  if fn = '' then Exit;

  try
    Ini := TIniFile.Create(fn);
    try
      SaveSettingsToIni(Ini);
    finally
      Ini.Free;
    end;
  except
    on E: Exception do
      MessageDlg('Save settings failed', E.Message, mtError, [mbOK], 0);
  end;
end;

procedure TMainForm.MenuLearnTutorialClick(Sender: TObject);
  function ClampLocal(const v, lo, hi: Integer): Integer; inline;
  begin
    if v < lo then Exit(lo);
    if v > hi then Exit(hi);
    Exit(v);
  end;
  procedure ApplyLearnedToControls;
  begin
    if Assigned(TrackAnsiEdgeBias) then
      TrackAnsiEdgeBias.Position := ClampLocal(FTutEdgeBiasFloor, TrackAnsiEdgeBias.Min, TrackAnsiEdgeBias.Max);
    if Assigned(TrackAnsiStability) then
      TrackAnsiStability.Position := ClampLocal(FTutStabilityFloor, TrackAnsiStability.Min, TrackAnsiStability.Max);
    if Assigned(CheckAnsiForceBg) then
      CheckAnsiForceBg.Checked := FTutForceBg;
    if Assigned(ComboAnsiForceBg) then
    begin
      ComboAnsiForceBg.Enabled := FTutForceBg;
      ComboAnsiForceBg.ItemIndex := ClampLocal(FTutForceBgColor, 0, ComboAnsiForceBg.Items.Count - 1);
    end;
    // Switch to Tutorial style and enable multipass to make style selectable.
    if Assigned(CheckAnsiMultiPass) then
      CheckAnsiMultiPass.Checked := True;
    if Assigned(ComboAnsiStyle) then
      ComboAnsiStyle.ItemIndex := 5;
  end;

  function IsAnsiTutorialFile(const fn: string): Boolean;
  var
    ext: String;
  begin
    ext := LowerCase(ExtractFileExt(fn));
    Result := (ext = '.ans') or (ext = '.asc') or (ext = '.ice') or (ext = '.pur') or
              (ext = '.skn') or (ext = '.000') or (ext = '.001') or (ext = '.002') or (ext = '.003');
  end;

  procedure AnalyzeAnsiDir(const Dir: string; out blockR, halfR, shadeR, spaceR: Double);
  var
    sr: TSearchRec;
    path: string;
    fs: TFileStream;
    buf: array[0..8191] of Byte;
    n, i: Integer;
    b: Byte;
    total: Int64;
    cntBlock, cntHalf, cntShade, cntSpace: Int64;
    inEsc: Boolean;
  begin
    blockR := 0; halfR := 0; shadeR := 0; spaceR := 0;
    total := 0; cntBlock := 0; cntHalf := 0; cntShade := 0; cntSpace := 0;
    if (Dir = '') or (not DirectoryExists(Dir)) then Exit;

    if FindFirst(IncludeTrailingPathDelimiter(Dir) + '*.*', faAnyFile, sr) = 0 then
    begin
      repeat
        if (sr.Attr and faDirectory) = 0 then
        begin
          path := IncludeTrailingPathDelimiter(Dir) + sr.Name;
          if not IsAnsiTutorialFile(path) then Continue;
          fs := TFileStream.Create(path, fmOpenRead or fmShareDenyNone);
          try
            inEsc := False;
            repeat
              n := fs.Read(buf, SizeOf(buf));
              for i := 0 to n - 1 do
              begin
                b := buf[i];
                if inEsc then
                begin
                  if (b >= 64) and (b <= 126) then
                    inEsc := False;
                  Continue;
                end;
                if b = 27 then
                begin
                  inEsc := True;
                  Continue;
                end;
                Inc(total);
                case b of
                  32: Inc(cntSpace);
                  219: Inc(cntBlock);
                  176, 177, 178: Inc(cntShade);
                  220, 223, 221, 222: Inc(cntHalf);
                end;
              end;
            until n = 0;
          finally
            fs.Free;
          end;
        end;
      until FindNext(sr) <> 0;
      FindClose(sr);
    end;
    if total > 0 then
    begin
      blockR := cntBlock / total;
      halfR := cntHalf / total;
      shadeR := cntShade / total;
      spaceR := cntSpace / total;
    end;
  end;

var
  dir: string;
  blockR, halfR, shadeR, spaceR: Double;
  shadeWeight, halfWeight: Double;
begin
  dir := 'Z:\ansituts';
  AnalyzeAnsiDir(dir, blockR, halfR, shadeR, spaceR);

  // Derive tutorial knobs from observed ratios.
  shadeWeight := 1.0 - EnsureRange(shadeR * 12.0, 0.0, 0.9);
  halfWeight := EnsureRange(halfR * 10.0, 0.1, 1.0);

  FTutShadeBasePenalty := 25000.0 + shadeWeight * 70000.0;                // 25k..95k
  FTutShadeEdgeMult := 1.25 + shadeWeight * 0.6;                          // 1.25..1.85
  FTutShadeFlatMult := 0.55 + (1.0 - shadeWeight) * 0.6;                  // 0.55..1.15
  FTutHalfEdgeMult := 1.1 + halfWeight * 0.6;                             // 1.1..1.7
  FTutHalfFlatMult := 0.85 + (1.0 - halfWeight) * 0.3;                    // 0.85..1.15
  FTutOrientMult := 1.3 + halfWeight * 0.4;                               // 1.3..1.7
  FTutEdgeBiasFloor := ClampLocal(60 + Round(halfR * 200.0) + Round(blockR * 100.0), 60, 90);
  FTutStabilityFloor := 60;
  FTutLumBucketStrength := 14;
  FTutChromaPenalty := 22;
  FTutForceBg := True;
  FTutForceBgColor := 0;

  ApplyLearnedToControls;
  ScheduleAnsiPreview;
end;

procedure TMainForm.MenuResetDefaultsClick(Sender: TObject);
begin
  ResetFactoryDefaults;
end;

procedure TMainForm.MenuHelpPathsClick(Sender: TObject);
begin
  ShowPathsHelp;
end;

procedure TMainForm.MenuHelpAboutClick(Sender: TObject);
var
  f: TFormAbout;
begin
  f := TFormAbout.Create(Self);
  try
    f.ShowModal;
  finally
    f.Free;
  end;
end;

procedure TMainForm.MenuExitClick(Sender: TObject);
begin
  Close;
end;

procedure TMainForm.BuildMainMenu;
var
  miFile, miSettings, miHelp: TMenuItem;
  mi: TMenuItem;
begin
  if Assigned(FMainMenu) then Exit;

  FMainMenu := TMainMenu.Create(Self);
  Menu := FMainMenu;

  miFile := TMenuItem.Create(FMainMenu);
  miFile.Caption := '&File';
  FMainMenu.Items.Add(miFile);

  mi := TMenuItem.Create(FMainMenu);
  mi.Caption := '&Open image...';
  mi.ShortCut := ShortCut(Ord('O'), [ssCtrl]);
  mi.OnClick := @BtnOpenClick;
  miFile.Add(mi);

  mi := TMenuItem.Create(FMainMenu);
  mi.Caption := '&Save output...';
  mi.ShortCut := ShortCut(Ord('S'), [ssCtrl]);
  mi.OnClick := @BtnSaveAnsiClick;
  miFile.Add(mi);

  mi := TMenuItem.Create(FMainMenu);
  mi.Caption := '-';
  miFile.Add(mi);

  mi := TMenuItem.Create(FMainMenu);
  mi.Caption := 'E&xit';
  mi.OnClick := @MenuExitClick;
  miFile.Add(mi);

  miSettings := TMenuItem.Create(FMainMenu);
  miSettings.Caption := '&Settings';
  FMainMenu.Items.Add(miSettings);

  mi := TMenuItem.Create(FMainMenu);
  mi.Caption := '&Load settings...';
  mi.OnClick := @MenuLoadSettingsClick;
  miSettings.Add(mi);

  mi := TMenuItem.Create(FMainMenu);
  mi.Caption := '&Save settings...';
  mi.OnClick := @MenuSaveSettingsClick;
  miSettings.Add(mi);

  mi := TMenuItem.Create(FMainMenu);
  mi.Caption := '-';
  miSettings.Add(mi);

  mi := TMenuItem.Create(FMainMenu);
  mi.Caption := 'Learn tutorial style...';
  mi.OnClick := @MenuLearnTutorialClick;
  miSettings.Add(mi);

  mi := TMenuItem.Create(FMainMenu);
  mi.Caption := '-';
  miSettings.Add(mi);

  mi := TMenuItem.Create(FMainMenu);
  mi.Caption := '&Reset defaults';
  mi.ShortCut := ShortCut(Ord('R'), [ssAlt]);
  mi.OnClick := @MenuResetDefaultsClick;
  miSettings.Add(mi);

  miHelp := TMenuItem.Create(FMainMenu);
  miHelp.Caption := '&Help';
  FMainMenu.Items.Add(miHelp);

  mi := TMenuItem.Create(FMainMenu);
  mi.Caption := '&Paths...';
  mi.OnClick := @MenuHelpPathsClick;
  miHelp.Add(mi);

  mi := TMenuItem.Create(FMainMenu);
  mi.Caption := '-';
  miHelp.Add(mi);

  mi := TMenuItem.Create(FMainMenu);
  mi.Caption := '&About...';
  mi.OnClick := @MenuHelpAboutClick;
  miHelp.Add(mi);
end;

procedure TMainForm.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  // Alt+R = factory reset.
  if (Key = Ord('R')) and (ssAlt in Shift) then
  begin
    Key := 0;
    ResetFactoryDefaults;
    Exit;
  end;
end;

end.
