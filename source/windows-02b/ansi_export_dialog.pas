unit ansi_export_dialog;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls,
  ansi_export_opts;

function EditAnsiExportOptions(AOwner: TComponent;
  const OutName, SourceImagePath: string;
  var Opt: TAnsiExportOptions): Boolean;

implementation

type
  TAnsiExportOptionsForm = class(TForm)
  private
    chkTrim: TCheckBox;
    chkClear: TCheckBox;
    lblEOL: TLabel;
    cmbEOL: TComboBox;

    chkSauce: TCheckBox;
    lblTitle: TLabel;
    lblAuthor: TLabel;
    lblGroup: TLabel;
    edtTitle: TEdit;
    edtAuthor: TEdit;
    edtGroup: TEdit;
    chkSourceComment: TCheckBox;
    chkIceFlag: TCheckBox;

    chkCopySource: TCheckBox;

    btnOK: TButton;
    btnCancel: TButton;

    procedure UpdateEnabled;
    procedure SauceToggled(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
  end;

constructor TAnsiExportOptionsForm.Create(AOwner: TComponent);
var
  root: TPanel;
  row: TPanel;

  function NewRow: TPanel;
  begin
    Result := TPanel.Create(root);
    Result.Parent := root;
    Result.Align := alTop;
    Result.BevelOuter := bvNone;
    Result.AutoSize := True;
    Result.BorderSpacing.Around := 6;
  end;

  procedure AddSpacer(h: Integer);
  var
    sp: TPanel;
  begin
    sp := TPanel.Create(root);
    sp.Parent := root;
    sp.Align := alTop;
    sp.BevelOuter := bvNone;
    sp.Height := h;
  end;

begin
  inherited Create(AOwner);
  Caption := 'ANSI Export Options (BBS/CP437)';
  Position := poScreenCenter;
  BorderStyle := bsDialog;
  AutoSize := True;
  Constraints.MinWidth := 520;

  root := TPanel.Create(Self);
  root.Parent := Self;
  root.Align := alClient;
  root.BevelOuter := bvNone;
  root.AutoSize := True;

  // Formatting
  row := NewRow;
  chkTrim := TCheckBox.Create(row);
  chkTrim.Parent := row;
  chkTrim.Caption := 'Trim trailing spaces (keeps colored spaces)';
  chkTrim.Align := alTop;

  chkClear := TCheckBox.Create(row);
  chkClear.Parent := row;
  chkClear.Caption := 'Clear screen + Home cursor at start (ESC[2J ESC[H])';
  chkClear.Align := alTop;

  lblEOL := TLabel.Create(row);
  lblEOL.Parent := row;
  lblEOL.Caption := 'Line endings';
  lblEOL.Align := alTop;
  lblEOL.BorderSpacing.Top := 6;

  cmbEOL := TComboBox.Create(row);
  cmbEOL.Parent := row;
  cmbEOL.Align := alTop;
  cmbEOL.Style := csDropDownList;
  cmbEOL.Items.Add('CR (classic .ANS)');
  cmbEOL.Items.Add('CRLF (Windows)');
  cmbEOL.Items.Add('LF (Unix)');
  cmbEOL.ItemIndex := 0;

  AddSpacer(4);

  // SAUCE
  row := NewRow;
  chkSauce := TCheckBox.Create(row);
  chkSauce.Parent := row;
  chkSauce.Caption := 'Add SAUCE metadata';
  chkSauce.Align := alTop;
  chkSauce.OnChange := @SauceToggled;

  // Title
  lblTitle := TLabel.Create(row);
  lblTitle.Parent := row;
  lblTitle.Caption := 'Title';
  lblTitle.Align := alTop;
  lblTitle.BorderSpacing.Top := 6;

  edtTitle := TEdit.Create(row);
  edtTitle.Parent := row;
  edtTitle.Align := alTop;

  // Author
  lblAuthor := TLabel.Create(row);
  lblAuthor.Parent := row;
  lblAuthor.Caption := 'Author';
  lblAuthor.Align := alTop;
  lblAuthor.BorderSpacing.Top := 6;

  edtAuthor := TEdit.Create(row);
  edtAuthor.Parent := row;
  edtAuthor.Align := alTop;

  // Group
  lblGroup := TLabel.Create(row);
  lblGroup.Parent := row;
  lblGroup.Caption := 'Group';
  lblGroup.Align := alTop;
  lblGroup.BorderSpacing.Top := 6;

  edtGroup := TEdit.Create(row);
  edtGroup.Parent := row;
  edtGroup.Align := alTop;

  chkSourceComment := TCheckBox.Create(row);
  chkSourceComment.Parent := row;
  chkSourceComment.Caption := 'Add SOURCE comment (COMNT block)';
  chkSourceComment.Align := alTop;
  chkSourceComment.BorderSpacing.Top := 6;

  chkIceFlag := TCheckBox.Create(row);
  chkIceFlag.Parent := row;
  chkIceFlag.Caption := 'Set iCE colors flag in SAUCE (bit0)';
  chkIceFlag.Align := alTop;

  AddSpacer(4);

  // Copy source image
  row := NewRow;
  chkCopySource := TCheckBox.Create(row);
  chkCopySource.Parent := row;
  chkCopySource.Caption := 'Copy source image beside ANSI file ("*_source.<ext>")';
  chkCopySource.Align := alTop;

  AddSpacer(6);

  // Buttons
  row := NewRow;
  row.BorderSpacing.Around := 8;

  btnOK := TButton.Create(row);
  btnOK.Parent := row;
  btnOK.Caption := 'OK';
  btnOK.ModalResult := mrOk;
  btnOK.Default := True;
  btnOK.Width := 90;
  btnOK.Align := alLeft;

  btnCancel := TButton.Create(row);
  btnCancel.Parent := row;
  btnCancel.Caption := 'Cancel';
  btnCancel.ModalResult := mrCancel;
  btnCancel.Cancel := True;
  btnCancel.Width := 90;
  btnCancel.BorderSpacing.Left := 10;
  btnCancel.Align := alLeft;

  UpdateEnabled;
end;

procedure TAnsiExportOptionsForm.UpdateEnabled;
var
  en: Boolean;
begin
  en := chkSauce.Checked;
  lblTitle.Enabled := en;
  lblAuthor.Enabled := en;
  lblGroup.Enabled := en;
  edtTitle.Enabled := en;
  edtAuthor.Enabled := en;
  edtGroup.Enabled := en;
  chkSourceComment.Enabled := en;
  chkIceFlag.Enabled := en;
end;

procedure TAnsiExportOptionsForm.SauceToggled(Sender: TObject);
begin
  UpdateEnabled;
end;

function EditAnsiExportOptions(AOwner: TComponent;
  const OutName, SourceImagePath: string;
  var Opt: TAnsiExportOptions): Boolean;
var
  f: TAnsiExportOptionsForm;
begin
  f := TAnsiExportOptionsForm.Create(AOwner);
  try
    // defaults -> controls
    f.chkTrim.Checked := Opt.TrimTrailingSpaces;
    f.chkClear.Checked := Opt.ClearScreenHome;

    case Opt.LineEnding of
      aleCR:   f.cmbEOL.ItemIndex := 0;
      aleCRLF: f.cmbEOL.ItemIndex := 1;
      aleLF:   f.cmbEOL.ItemIndex := 2;
    else
      f.cmbEOL.ItemIndex := 0;
    end;

    f.chkSauce.Checked := Opt.AddSauce;
    f.edtTitle.Text := string(Opt.SauceTitle);
    f.edtAuthor.Text := string(Opt.SauceAuthor);
    f.edtGroup.Text := string(Opt.SauceGroup);
    f.chkSourceComment.Checked := Opt.AddSourceComment;
    f.chkIceFlag.Checked := Opt.IceFlag;

    f.chkCopySource.Checked := Opt.CopySourceImage and (SourceImagePath <> '') and FileExists(SourceImagePath);
    if (SourceImagePath = '') or (not FileExists(SourceImagePath)) then
    begin
      f.chkCopySource.Checked := False;
      f.chkCopySource.Enabled := False;
      f.chkCopySource.Caption := f.chkCopySource.Caption + ' (no source image)';
    end;

    f.UpdateEnabled;

    Result := (f.ShowModal = mrOk);
    if Result then
    begin
      Opt.TrimTrailingSpaces := f.chkTrim.Checked;
      Opt.ClearScreenHome := f.chkClear.Checked;

      case f.cmbEOL.ItemIndex of
        1: Opt.LineEnding := aleCRLF;
        2: Opt.LineEnding := aleLF;
      else
        Opt.LineEnding := aleCR;
      end;

      case f.cmbEOL.ItemIndex of
        1: Opt.LineEnding := aleCRLF;
        2: Opt.LineEnding := aleLF;
      else
        Opt.LineEnding := aleCR;
      end;

      Opt.AddSauce := f.chkSauce.Checked;
      Opt.SauceTitle := AnsiString(f.edtTitle.Text);
      Opt.SauceAuthor := AnsiString(f.edtAuthor.Text);
      Opt.SauceGroup := AnsiString(f.edtGroup.Text);
      Opt.AddSourceComment := f.chkSourceComment.Checked;
      Opt.IceFlag := f.chkIceFlag.Checked;

      Opt.CopySourceImage := f.chkCopySource.Checked and (SourceImagePath <> '') and FileExists(SourceImagePath);
    end;
  finally
    f.Free;
  end;
end;

end.
