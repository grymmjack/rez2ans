unit img2bin_gradients;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  TGradientSet = record
    Name: string;
    Chars: AnsiString;  // CP437/ASCII bytes only
    Comment: string;
  end;

  // Fixed-size lookup table for allowed characters (0..255).
  // We use a named type because FPC does not allow specifying bounds directly
  // in a procedure parameter (i.e. "array[0..255] of ..." in the parameter list).
  TAllowedCharMap = array[0..255] of Boolean;

const
  // Keep these CP437/ASCII-only. (Some Unicode shapes don't exist in CP437.)
  GRADIENT_COUNT = 8;

  Gradients: array[0..GRADIENT_COUNT-1] of TGradientSet = (
    // BASIC ASCII GRADIENT (10 levels)
    (Name: 'Basic ASCII';
     Chars: ' .:-=+*#%@';
     Comment: '10 levels - Simple ASCII: space (dark) to @ (bright).'),

    // EXTENDED ASCII GRADIENT (8 levels)
    (Name: 'Punctuation';
     Chars: ' `''".,:;';
     Comment: '8 levels - Subtle punctuation density.'),

    // BLOCK SHADING (5 levels)
    (Name: 'Block Shade';
     Chars: ' '#176#177#178#219;
     Comment: '5 levels - CP437 blocks: space, ░▒▓█.'),

    // DETAILED ASCII GRADIENT (many levels)
    (Name: 'Ultra Detailed';
     Chars: ' `.-'''':_,^=;><+!rc*/z?sLTv)J7(|Fi{C}fI31tlu[neoZ5Yxjya]2ESwqkP6h9d4VpOGbUAKXHm8RD#$Bg0MNWQ%&@';
     Comment: 'High detail gradient (slow, but detailed).'),

    // SIMPLE 3-LEVEL
    (Name: 'Three Level';
     Chars: ' '#177#219;
     Comment: '3 levels - space, ▒, █.'),

    // NUMERIC GRADIENT
    (Name: 'Numbers';
     Chars: ' 1234567890';
     Comment: 'Digits as density ramp.'),

    // DENSITY GRADIENT
    (Name: 'Density';
     Chars: ' .,:;!~-_+<>i?/\|()1{}[]rcvxzjftLCJUYXZO0Qo@';
     Comment: 'Curated ASCII density order.'),

    // CUSTOM SMOOTH GRADIENT
    (Name: 'Smooth';
     Chars: ' `''".,-~:;=!*+<>i^lI?/\|()1{}[]rcvu7LCJnzjftYXZO0Qo#MW&8%B@$';
     Comment: 'Balanced smooth ramp (good default).')
  );

procedure GradientFillNames(Items: TStrings);
function GradientChars(Index: Integer): AnsiString;
procedure GradientAllowed(Index: Integer; var Allowed: TAllowedCharMap);

implementation

procedure GradientFillNames(Items: TStrings);
var
  i: Integer;
begin
  if Items = nil then Exit;
  Items.BeginUpdate;
  try
    Items.Clear;
    for i := 0 to GRADIENT_COUNT-1 do
      Items.Add(Gradients[i].Name);
  finally
    Items.EndUpdate;
  end;
end;

function GradientChars(Index: Integer): AnsiString;
begin
  if (Index < 0) or (Index >= GRADIENT_COUNT) then
    Exit('');
  Result := Gradients[Index].Chars;
end;

procedure GradientAllowed(Index: Integer; var Allowed: TAllowedCharMap);
var
  s: AnsiString;
  i: Integer;
  b: Byte;
begin
  FillChar(Allowed, SizeOf(Allowed), 0);
  if (Index < 0) or (Index >= GRADIENT_COUNT) then Exit;
  s := Gradients[Index].Chars;
  for i := 1 to Length(s) do
  begin
    b := Ord(s[i]);
    Allowed[b] := True;
  end;
  // Always allow space (dark)
  Allowed[Ord(' ')] := True;
end;

end.
