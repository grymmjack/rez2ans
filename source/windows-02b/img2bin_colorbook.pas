unit img2bin_colorbook;

{$mode objfpc}{$H+}

interface

uses
  Math,
  img2bin_types;

// Build "coloring book" cells:
// - Flatten areas into solid colors
// - Draw black outlines around color regions
//
// NOTE: This works in the existing converter pipeline by using the already-quantized
//       2x2 subpixel indices (idx). It intentionally ignores dithering detail.
procedure BuildCellsColorBook(
  const idx: array of Byte;
  rows: Integer;
  Ice: Boolean;
  Pal: TPaletteKind;
  var cells: array of TCell
);

function AttrByte(FG, BG: Byte; Ice: Boolean): Byte; inline;

implementation

uses
  img2bin_palette;

const
  SUBW = COLS * 2;
  // Majority filter radius (in cells). 1 = 3x3 neighborhood.
  SMOOTH_R = 0;
  // Outline thickness in cells.
  OUTLINE_THICKNESS = 2;
  // Extra edge detection: mark outlines even when the quantized color index matches,
  // based on cell-average RGB gradients.
  EDGE_GRAD_TH = 900;

function AttrByte(FG, BG: Byte; Ice: Boolean): Byte; inline;
begin
  if not Ice then BG := BG and $07;
  Result := ((BG and $0F) shl 4) or (FG and $0F);
end;

function Mix4(const a, b, c, d: TRGB): TRGB; inline;
begin
  Result.R := Byte((Integer(a.R)+Integer(b.R)+Integer(c.R)+Integer(d.R)) div 4);
  Result.G := Byte((Integer(a.G)+Integer(b.G)+Integer(c.G)+Integer(d.G)) div 4);
  Result.B := Byte((Integer(a.B)+Integer(b.B)+Integer(c.B)+Integer(d.B)) div 4);
end;

procedure BuildCellsColorBook(
  const idx: array of Byte;
  rows: Integer;
  Ice: Boolean;
  Pal: TPaletteKind;
  var cells: array of TCell
);
var
  keys, keys2: array of Byte;        // per-cell color index (0..15)
  cellAvg: array of TRGB;            // per-cell averaged color (for edge/gradient detection)
  edge, edge2: array of Boolean;     // outline mask
  // NOTE: loop counters are declared locally in nested procedures (FPC restriction).

  function CIndex(cx, cy: Integer): Integer; inline;
  begin
    Result := cy*COLS + cx;
  end;

  function IdxAt(sx, sy: Integer): Byte; inline;
  begin
    Result := idx[sy*SUBW + sx];
  end;

  procedure ComputeKeys;
  var
    tlI, trI, blI, brI: Byte;
    tl, tr, bl, br: TRGB;
    avg: TRGB;
    k, cx, cy: Integer;
  begin
    SetLength(keys, COLS * rows);
    SetLength(cellAvg, COLS * rows);
    for cy := 0 to rows - 1 do
      for cx := 0 to COLS - 1 do
      begin
        tlI := IdxAt(2*cx,   2*cy);
        trI := IdxAt(2*cx+1, 2*cy);
        blI := IdxAt(2*cx,   2*cy+1);
        brI := IdxAt(2*cx+1, 2*cy+1);

        tl := Palette16(Pal, tlI);
        tr := Palette16(Pal, trI);
        bl := Palette16(Pal, blI);
        br := Palette16(Pal, brI);
        avg := Mix4(tl, tr, bl, br);
        cellAvg[CIndex(cx,cy)] := avg;

        // If the 2x2 block is uniform, keep it (avoids unnecessary palette snaps)
        if (tlI = trI) and (tlI = blI) and (tlI = brI) then
          keys[CIndex(cx,cy)] := tlI
        else
        begin
          k := NearestAnsi16(avg, Pal);
          keys[CIndex(cx,cy)] := Byte(k and $0F);
        end;
      end;
  end;

  procedure SmoothKeysMajority;
  var
    cx, cy, nx, ny, j, bestK, bestC, k: Integer;
    counts: array[0..15] of Integer;
  begin
    SetLength(keys2, Length(keys));
    for cy := 0 to rows - 1 do
      for cx := 0 to COLS - 1 do
      begin
        for j := 0 to 15 do counts[j] := 0;

        for ny := Max(0, cy - SMOOTH_R) to Min(rows - 1, cy + SMOOTH_R) do
          for nx := Max(0, cx - SMOOTH_R) to Min(COLS - 1, cx + SMOOTH_R) do
          begin
            k := keys[CIndex(nx, ny)] and $0F;
            Inc(counts[k]);
          end;

        bestK := keys[CIndex(cx, cy)] and $0F;
        bestC := counts[bestK];
        for j := 0 to 15 do
          if counts[j] > bestC then
          begin
            bestC := counts[j];
            bestK := j;
          end;
        keys2[CIndex(cx, cy)] := Byte(bestK);
      end;
  end;

  procedure BuildOutlineMask;
  var
    cx, cy, k0: Integer;
    i0, inb, ii, t: Integer;
  begin
    SetLength(edge, COLS * rows);
    for ii := 0 to High(edge) do edge[ii] := False;

    for cy := 0 to rows - 1 do
      for cx := 0 to COLS - 1 do
      begin
        k0 := keys2[CIndex(cx, cy)];
        i0 := CIndex(cx, cy);

        // Primary outlines: region boundaries (after majority smoothing)
        if (cx > 0)      and (keys2[CIndex(cx-1, cy)] <> k0) then edge[i0] := True;
        if (cx < COLS-1) and (keys2[CIndex(cx+1, cy)] <> k0) then edge[i0] := True;
        if (cy > 0)      and (keys2[CIndex(cx, cy-1)] <> k0) then edge[i0] := True;
        if (cy < rows-1) and (keys2[CIndex(cx, cy+1)] <> k0) then edge[i0] := True;

        // Secondary outlines: strong gradients even if palette index matches
        // (helps keep pencil/ink edges from being swallowed by smoothing)
        if not edge[i0] then
        begin
          if (cx > 0) then
          begin
            inb := CIndex(cx-1, cy);
            if PalDist2(cellAvg[i0], cellAvg[inb]) >= EDGE_GRAD_TH then edge[i0] := True;
          end;
          if (not edge[i0]) and (cx < COLS-1) then
          begin
            inb := CIndex(cx+1, cy);
            if PalDist2(cellAvg[i0], cellAvg[inb]) >= EDGE_GRAD_TH then edge[i0] := True;
          end;
          if (not edge[i0]) and (cy > 0) then
          begin
            inb := CIndex(cx, cy-1);
            if PalDist2(cellAvg[i0], cellAvg[inb]) >= EDGE_GRAD_TH then edge[i0] := True;
          end;
          if (not edge[i0]) and (cy < rows-1) then
          begin
            inb := CIndex(cx, cy+1);
            if PalDist2(cellAvg[i0], cellAvg[inb]) >= EDGE_GRAD_TH then edge[i0] := True;
          end;
        end;
      end;

    // Thicken outlines (simple dilation)
    if OUTLINE_THICKNESS > 1 then
    begin
      SetLength(edge2, Length(edge));
      for t := 1 to OUTLINE_THICKNESS - 1 do
      begin
        for ii := 0 to High(edge2) do edge2[ii] := edge[ii];
        for cy := 0 to rows - 1 do
          for cx := 0 to COLS - 1 do
          begin
            ii := CIndex(cx, cy);
            if not edge[ii] then Continue;
            if cx > 0      then edge2[CIndex(cx-1, cy)] := True;
            if cx < COLS-1 then edge2[CIndex(cx+1, cy)] := True;
            if cy > 0      then edge2[CIndex(cx, cy-1)] := True;
            if cy < rows-1 then edge2[CIndex(cx, cy+1)] := True;
          end;
        edge := edge2;
      end;
    end;
  end;

  procedure EmitCells;
  var
    fg, bg: Byte;
    ch: Byte;
    cx, cy, ii: Integer;
  begin
    // Safety: if caller gave wrong array size, avoid AV.
    if Length(cells) < COLS * rows then Exit;

    for cy := 0 to rows - 1 do
      for cx := 0 to COLS - 1 do
      begin
        ii := CIndex(cx, cy);
        if edge[ii] then
        begin
          ch := CH_FULL;
          fg := 0;
          bg := 0;
        end
        else
        begin
          ch := CH_FULL;
          fg := keys2[ii] and $0F;
          bg := 0;
        end;
        cells[ii].Ch := ch;
        cells[ii].Attr := AttrByte(fg, bg, Ice);
      end;
  end;

begin
  if rows <= 0 then Exit;
  if Length(idx) < SUBW * rows * 2 then Exit;

  ComputeKeys;
  SmoothKeysMajority;
  BuildOutlineMask;
  EmitCells;
end;

end.
