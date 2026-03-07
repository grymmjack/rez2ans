unit UnitAbout;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls;

type

  { TFormAbout }

  TFormAbout = class(TForm)
    pTop: TPanel;
    pBottom: TPanel;
    btnOK: TButton;
    imgLogo: TImage;
    memoAbout: TMemo;
    procedure btnOKClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormShow(Sender: TObject);
  private
    procedure LoadEmbeddedLogo;
    procedure PopulateAboutText;
  public
  end;

implementation

{$R *.lfm}

{$I rez2ans_logo_png.inc}

{ TFormAbout }

procedure TFormAbout.LoadEmbeddedLogo;
var
  ms: TMemoryStream;
  png: TPortableNetworkGraphic;
begin
  if not Assigned(imgLogo) then Exit;
  ms := TMemoryStream.Create;
  try
    ms.WriteBuffer(Rez2AnsLogoPng[0], Rez2AnsLogoPngSize);
    ms.Position := 0;

    png := TPortableNetworkGraphic.Create;
    try
      png.LoadFromStream(ms);
      imgLogo.Picture.Assign(png);
    finally
      png.Free;
    end;
  finally
    ms.Free;
  end;
end;

procedure TFormAbout.PopulateAboutText;
begin
  if not Assigned(memoAbout) then Exit;

  memoAbout.Clear;
  memoAbout.Lines.Add('rez2ans v1.25');
  memoAbout.Lines.Add('by Dennis Martin');
  memoAbout.Lines.Add('suddendeath@email.com');
  memoAbout.Lines.Add('');
  memoAbout.Lines.Add('rez2ans v1.25 is a small utility for converting and working with ANSI');
  memoAbout.Lines.Add('art, built with Free Pascal/Lazarus and targeting both Windows and');
  memoAbout.Lines.Add('Linux. This release is focused primarily on small-scale ANSIs for BBSs,');
  memoAbout.Lines.Add('and the changes throughout reflect that goal. Source code will be');
  memoAbout.Lines.Add('released shortly -- stay tuned.');
  memoAbout.Lines.Add('');
  memoAbout.Lines.Add('Special thanks to grymmjack and xbit for their invaluable help,');
  memoAbout.Lines.Add('patience, and support. You two know what you did. Thanks also to');
  memoAbout.Lines.Add('everyone in the community who reached out -- the encouragement means');
  memoAbout.Lines.Add('more than you know. Hope to hear from you all.');
  memoAbout.Lines.Add('');
  memoAbout.Lines.Add('WARRANTY NOTICE');
  memoAbout.Lines.Add('');
  memoAbout.Lines.Add('rez2ans is provided as-is, with absolutely no warranty of any kind,');
  memoAbout.Lines.Add('expressed, implied, or imagined. We warrant nothing. We are not');
  memoAbout.Lines.Add('entirely certain this software exists. It may be vaporware. It may be');
  memoAbout.Lines.Add('a fever dream. If it works, consider yourself lucky. If it doesn''t,');
  memoAbout.Lines.Add('consider yourself warned. By using this software you acknowledge that');
  memoAbout.Lines.Add('you have read this warranty, understood it, and decided to throw');
  memoAbout.Lines.Add('caution to the wind anyway. Good luck out there.');
end;

procedure TFormAbout.FormCreate(Sender: TObject);
begin
  PopulateAboutText;
  LoadEmbeddedLogo;
end;

procedure TFormAbout.btnOKClick(Sender: TObject);
begin
  Close;
end;

procedure TFormAbout.FormShow(Sender: TObject);
begin
  if not Assigned(memoAbout) then Exit;
  // Ensure the memo always opens scrolled to the top (some widgetsets remember scroll pos).
  memoAbout.SelStart := 0;
  memoAbout.SelLength := 0;
  memoAbout.CaretPos := Point(0, 0);
end;

end.
