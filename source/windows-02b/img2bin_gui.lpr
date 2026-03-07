program img2bin_gui;

{$mode objfpc}{$H+}

uses
  Interfaces, Forms,
  mainform;

{$R *.res}

begin
  Application.Scaled:=True;
  Application.Initialize;
  Application.CreateForm(TMainForm, MainFrm);
  Application.Run;
end.
