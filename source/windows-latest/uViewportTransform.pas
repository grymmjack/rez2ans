unit uViewportTransform;

{$mode objfpc}{$H+}

interface

uses
  Types, Math;

type
  // Centralizes mapping between "image space" (working bitmap pixels) and
  // "view space" (display/overlay pixels). Right/Bottom bounds are exclusive for rects.
  TViewportTransform = class
  private
    FImageW: Integer;
    FImageH: Integer;
    FViewW: Integer;
    FViewH: Integer;
  public
    procedure SetSizes(const AImageW, AImageH, AViewW, AViewH: Integer);

    // Image (working) -> View (display)
    function ImageToViewRect(const R: TRect): TRect;

    // View (display) -> Image (working)
    function ViewToImagePoint(const P: TPoint): TPoint;

    property ImageW: Integer read FImageW;
    property ImageH: Integer read FImageH;
    property ViewW: Integer read FViewW;
    property ViewH: Integer read FViewH;
  end;

implementation

procedure TViewportTransform.SetSizes(const AImageW, AImageH, AViewW, AViewH: Integer);
begin
  FImageW := Max(1, AImageW);
  FImageH := Max(1, AImageH);
  FViewW := Max(1, AViewW);
  FViewH := Max(1, AViewH);
end;

function TViewportTransform.ImageToViewRect(const R: TRect): TRect;
var
  w, h, dw, dh: Integer;
begin
  // Integer math so the drawn rectangle matches the actual pixel selection
  // (Right/Bottom are exclusive) regardless of zoom/rounding.
  w := Max(1, FImageW);
  h := Max(1, FImageH);
  dw := Max(1, FViewW);
  dh := Max(1, FViewH);

  Result := Rect(0, 0, 0, 0);

  // Left/Top: floor mapping
  Result.Left := EnsureRange(Integer((Int64(R.Left) * dw) div w), 0, dw);
  Result.Top := EnsureRange(Integer((Int64(R.Top) * dh) div h), 0, dh);

  // Right/Bottom: ceil mapping for exclusive bounds
  Result.Right := EnsureRange(Integer((Int64(R.Right) * dw + w - 1) div w), 0, dw);
  Result.Bottom := EnsureRange(Integer((Int64(R.Bottom) * dh + h - 1) div h), 0, dh);
end;

function TViewportTransform.ViewToImagePoint(const P: TPoint): TPoint;
var
  w, h, dw, dh: Integer;
begin
  w := Max(1, FImageW);
  h := Max(1, FImageH);
  dw := Max(1, FViewW);
  dh := Max(1, FViewH);

  // floor mapping from display pixel to working pixel
  Result.X := EnsureRange(Integer((Int64(P.X) * w) div dw), 0, w - 1);
  Result.Y := EnsureRange(Integer((Int64(P.Y) * h) div dh), 0, h - 1);
end;

end.
