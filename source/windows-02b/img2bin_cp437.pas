unit img2bin_cp437;

{$mode objfpc}{$H+}

interface

uses
  img2bin_types;

function CP437Glyph(b: Byte): UnicodeString;

implementation

function CP437Glyph(b: Byte): UnicodeString;
begin
  case b of
    CH_SPACE: Result := ' ';
    CH_LIGHT: Result := '░';
    CH_MED:   Result := '▒';
    CH_DARK:  Result := '▓';
    CH_FULL:  Result := '█';
    CH_LOW:   Result := '▄';
    CH_LEFT:  Result := '▌';
    CH_RIGHT: Result := '▐';
    CH_UP:    Result := '▀';
  else
    if (b >= 32) and (b < 127) then
      Result := UnicodeString(Chr(b))
    else
      Result := '?';
  end;
end;

end.


end.
