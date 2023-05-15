unit sunrpc.xdr;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  TXdr = record
    offset : integer;
    count : integer;
    buf : array of uint8;
  end;
  PXdr = ^TXdr;

  function EncodeI32(xdr : PXdr; x : int32) : boolean;
  function DecodeI32(xdr : PXdr; var x : int32) : boolean;
  function EncodeI64(xdr : PXdr; x : int64) : boolean;
  function DecodeI64(xdr : PXdr; var x : int64) : boolean;
  function EncodeU32(xdr : PXdr; x : uint32) : boolean;
  function DecodeU32(xdr : PXdr; var x : uint32) : boolean;
  function EncodeU64(xdr : PXdr; x : uint64) : boolean;
  function DecodeU64(xdr : PXdr; var x : uint64) : boolean;
  function EncodeBoolean(xdr : PXdr; x : boolean) : boolean;
  function DecodeBoolean(xdr : PXdr; var x : boolean) : boolean;
  function EncodeString(xdr : PXdr; x : string) : boolean;
  function DecodeString(xdr : PXdr; x : pchar; var len : integer) : boolean;
  function EncodeFixed(xdr : PXdr; x : array of uint8; count : integer) : boolean;
  function DecodeFixed(xdr : PXdr; x : array of uint8; count : integer) : boolean;
  function DecodeFixed(xdr : PXdr; x : array of uint8; count : uint32) : boolean;
  function EncodeOpaque(xdr : PXdr; x : array of uint8; count : integer) : boolean;
  function DecodeOpaque(xdr : PXdr; x : array of uint8; var count : integer) : boolean;
  function DecodeOpaque(xdr : PXdr; x : array of uint8; var count : uint32) : boolean;
  procedure ResetXdr(xdr : PXdr);

implementation

uses strings;

function EncodeI32(xdr : PXdr; x : int32) : boolean;
       var i : integer;
           p : array of uint8;
begin
       if xdr^.offset + 4 > xdr^.Count then
          exit(true);

       p := xdr^.buf;
       i := xdr^.offset;
       p[i] := (x shr 24) and $ff;
       p[i + 1] := (x shr 16) and $ff;
       p[i + 2] := (x shr 8) and $ff;
       p[i + 3] := x and $ff;
       xdr^.offset := i + 4;
       Result := false;
end;

function DecodeI32(xdr : PXdr; var x : int32) : boolean;
       var i : integer;
           p : array of uint8;
begin
       if xdr^.offset + 4 > xdr^.count then
          exit(true);

       i := xdr^.offset;
       p := xdr^.buf;
       x := (p[i] shl 24) or (p[i +1] shl 16) or (p[i + 2] shl 8) or p[i + 3];
       xdr^.offset := i + 4;

       Result := false;
end;

function EncodeU32(xdr : PXdr; x : uint32) : boolean;
begin
       Result := EncodeI32(xdr, int32(x));
end;

function DecodeU32(xdr : PXdr; var x : uint32) : boolean;
begin
       Result := EncodeI32(xdr, uint32(x));
end;

function EncodeU64(xdr : PXdr; x : uint64) : boolean;
begin
       Result := EncodeI32(xdr, uint64(x));
end;

function DecodeU64(xdr : PXdr; var x : uint64) : boolean;
begin
       Result := EncodeI32(xdr, uint64(x));
end;

function EncodeI64(xdr : PXdr; x : int64) : boolean;
    var sts : boolean;
begin
       sts := EncodeI32(xdr, x shr 32);
       if sts then exit(sts);
       sts := EncodeI32(xdr, x and $ffffffff);
       Result := sts;
end;

function DecodeI64(xdr : PXdr; var x : int64) : boolean;
         var h, l : int32;
             sts : boolean;
begin
       h := 0;
       l := 0;
       sts := DecodeI32(xdr, h);
       if sts then exit(sts);
       sts := DecodeI32(xdr, l);
       if sts then exit(sts);
       x := (h shl 32) or l;
       Result := false;
end;

function EncodeBoolean(xdr : PXdr; x : boolean) : boolean;
    var i : int32;
begin
     if x then i := 1 else i := 0;
     Result := EncodeI32(xdr, i);
end;

function DecodeBoolean(xdr : PXdr; var x : boolean) : boolean;
    var i : int32;
        sts : boolean;
begin
   i := 0;
   sts := DecodeI32(xdr, i);
   if sts then exit(sts);
   if i <> 0 then x := true else x := false;
   Result := false;
end;

function EncodeString(xdr : PXdr; x : string) : boolean;
    var sts : boolean;
        i : integer;
begin
   sts := EncodeI32(xdr, length(x));
   if sts then exit(sts);

   if xdr^.offset + length(x) > xdr^.count then
      exit(false);

   for i := 0 to length(x) - 1 do
   begin
     x[xdr^.offset + i] := x[i];
   end;
   xdr^.offset := xdr^.offset + i;
   if length(x) mod 4 <> 0 then
      xdr^.offset := xdr^.offset + 4 - (length(x) mod 4);

   Result := false;
end;

function DecodeString(xdr : PXdr; x : pchar; var len : integer) : boolean;
    var sts : boolean;
begin
     len := 0;
     sts := DecodeI32(xdr, len);
     if sts then exit(sts);

     strlcopy(x, @xdr^.buf[xdr^.offset], len);

     xdr^.offset := xdr^.offset + len;
     if (len mod 4) <> 0 then xdr^.offset := xdr^.offset + 4 - (len mod 4);
     Result := false;
end;

function EncodeFixed(xdr : PXdr; x : array of uint8; count : integer) : boolean;
    var i : integer;
begin
     if xdr^.offset + count > xdr^.count then exit(true);

     for i := 0 to count - 1 do
         xdr^.buf[xdr^.offset + i] := x[i];

     xdr^.offset := xdr^.offset + count;
     Result := false;
end;

function DecodeFixed(xdr : PXdr; x : array of uint8; count : integer) : boolean;
    var i : integer;
begin
     if xdr^.offset + count > xdr^.count then exit(true);

     for i := 0 to count - 1 do
         x[i] := xdr^.buf[xdr^.offset + i];
     xdr^.offset := xdr^.offset + count;
     Result := false;
end;
function DecodeFixed(xdr : PXdr; x : array of uint8; count : uint32) : boolean;
begin
      Result := DecodeFixed(xdr, x, integer(count));
end;

function EncodeOpaque(xdr : PXdr; x : array of uint8; count : integer) : boolean;
    var sts : boolean;
begin
    sts := EncodeI32(xdr, count);
    if sts then exit(sts);

    Result := EncodeFixed(xdr, x, count);
end;

function DecodeOpaque(xdr : PXdr; x : array of uint8; var count : integer) : boolean;
    var sts : boolean;
begin
    sts := DecodeI32(xdr, count);
    if sts then exit(sts);

    Result := DecodeFixed(xdr, x, count);
end;
function DecodeOpaque(xdr : PXdr; x : array of uint8; var count : uint32) : boolean;
begin
    Result := DecodeOpaque(xdr, x, integer(count));
end;

procedure ResetXdr(xdr : PXdr);
begin
    xdr^.offset := 0;
    xdr^.count := high(xdr^.buf);
end;

end.



