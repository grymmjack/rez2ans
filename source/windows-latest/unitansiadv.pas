unit UnitAnsiAdv;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ComCtrls, Spin, Math;

type
  { TAnsiAdvForm }

  TAnsiAdvForm = class(TForm)
    BtnCancel: TButton;
    BtnOK: TButton;
    CheckLumaBucket: TCheckBox;
    ComboBiasMode: TComboBox;
    GroupBias: TGroupBox;
    GroupChroma: TGroupBox;
    GroupLuma: TGroupBox;
    LabelBiasMode: TLabel;
    LabelBiasStrength: TLabel;
    LabelBucketStrength: TLabel;
    LabelBucketThreshold: TLabel;
    LabelChromaPenalty: TLabel;
    SpinBucketThreshold: TSpinEdit;
    TrackBiasStrength: TTrackBar;
    TrackBucketStrength: TTrackBar;
    TrackChromaPenalty: TTrackBar;
    procedure CheckLumaBucketChange(Sender: TObject);
    procedure FormCreate(Sender: TObject);
  public
    procedure LoadFromValues(const ABiasMode, ABiasStrength, ABucketStrength,
      ABucketThreshold, AChromaPenalty: Integer);
    procedure SaveToValues(out ABiasMode, ABiasStrength, ABucketStrength,
      ABucketThreshold, AChromaPenalty: Integer);
  end;

implementation

{$R *.lfm}

procedure TAnsiAdvForm.FormCreate(Sender: TObject);
begin
  if Assigned(ComboBiasMode) and (ComboBiasMode.Items.Count = 0) then
  begin
    ComboBiasMode.Items.Add('None');
    ComboBiasMode.Items.Add('Prefer dark');
    ComboBiasMode.Items.Add('Prefer bright');
    ComboBiasMode.Items.Add('Prefer grays');
    ComboBiasMode.Items.Add('Penalize B/W');
    ComboBiasMode.ItemIndex := 0;
  end;

  if Assigned(TrackBiasStrength) then
  begin
    TrackBiasStrength.Min := 0;
    TrackBiasStrength.Max := 100;
    TrackBiasStrength.Position := 0;
  end;

  if Assigned(CheckLumaBucket) then
  begin
    CheckLumaBucket.Checked := False;
    CheckLumaBucket.OnChange := @CheckLumaBucketChange;
  end;

  if Assigned(TrackBucketStrength) then
  begin
    TrackBucketStrength.Min := 0;
    TrackBucketStrength.Max := 100;
    TrackBucketStrength.Position := 0;
  end;

  if Assigned(SpinBucketThreshold) then
  begin
    SpinBucketThreshold.MinValue := 0;
    SpinBucketThreshold.MaxValue := 255;
    SpinBucketThreshold.Value := 128;
  end;

  if Assigned(TrackChromaPenalty) then
  begin
    TrackChromaPenalty.Min := 0;
    TrackChromaPenalty.Max := 100;
    TrackChromaPenalty.Position := 0;
  end;

  CheckLumaBucketChange(nil);
end;

procedure TAnsiAdvForm.CheckLumaBucketChange(Sender: TObject);
var
  en: Boolean;
begin
  en := Assigned(CheckLumaBucket) and CheckLumaBucket.Checked;
  if Assigned(TrackBucketStrength) then TrackBucketStrength.Enabled := en;
  if Assigned(SpinBucketThreshold) then SpinBucketThreshold.Enabled := en;
  if Assigned(LabelBucketStrength) then LabelBucketStrength.Enabled := en;
  if Assigned(LabelBucketThreshold) then LabelBucketThreshold.Enabled := en;
end;

procedure TAnsiAdvForm.LoadFromValues(const ABiasMode, ABiasStrength, ABucketStrength,
  ABucketThreshold, AChromaPenalty: Integer);
begin
  if Assigned(ComboBiasMode) then
    ComboBiasMode.ItemIndex := EnsureRange(ABiasMode, 0, Max(0, ComboBiasMode.Items.Count - 1));
  if Assigned(TrackBiasStrength) then
    TrackBiasStrength.Position := EnsureRange(ABiasStrength, TrackBiasStrength.Min, TrackBiasStrength.Max);

  if Assigned(CheckLumaBucket) then
    CheckLumaBucket.Checked := ABucketStrength > 0;
  if Assigned(TrackBucketStrength) then
    TrackBucketStrength.Position := EnsureRange(ABucketStrength, TrackBucketStrength.Min, TrackBucketStrength.Max);
  if Assigned(SpinBucketThreshold) then
    SpinBucketThreshold.Value := EnsureRange(ABucketThreshold, SpinBucketThreshold.MinValue, SpinBucketThreshold.MaxValue);

  if Assigned(TrackChromaPenalty) then
    TrackChromaPenalty.Position := EnsureRange(AChromaPenalty, TrackChromaPenalty.Min, TrackChromaPenalty.Max);

  CheckLumaBucketChange(nil);
end;

procedure TAnsiAdvForm.SaveToValues(out ABiasMode, ABiasStrength, ABucketStrength,
  ABucketThreshold, AChromaPenalty: Integer);
begin
  ABiasMode := 0;
  ABiasStrength := 0;
  ABucketStrength := 0;
  ABucketThreshold := 128;
  AChromaPenalty := 0;

  if Assigned(ComboBiasMode) then ABiasMode := ComboBiasMode.ItemIndex;
  if Assigned(TrackBiasStrength) then ABiasStrength := TrackBiasStrength.Position;

  if Assigned(CheckLumaBucket) and CheckLumaBucket.Checked then
  begin
    if Assigned(TrackBucketStrength) then ABucketStrength := TrackBucketStrength.Position;
    if Assigned(SpinBucketThreshold) then ABucketThreshold := SpinBucketThreshold.Value;
  end
  else
    ABucketStrength := 0;

  if Assigned(TrackChromaPenalty) then AChromaPenalty := TrackChromaPenalty.Position;
end;

end.
