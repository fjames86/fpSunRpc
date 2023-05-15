unit sunrpc.rpc;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, sunrpc.xdr;

type
  TOpaqueAuth = Record
    flavour : int32;
    alen : uint32;
    auth : array[0..399] of uint8;
    vlen : uint32;
    verf : array[0..399] of uint8;
  end;
  POpaqueAuth = ^TOpaqueAuth;
  TMismatch = Record
     high, low : uint32;
  end;

  TMsgType = (Call=0,Reply);
  TMsgAcceptType = (Accept = 0, Reject);
  TAcceptType = (Success=0,ProgUnavail,ProgMismatch,ProcUnavail,GarbageArgs,Error);
  TRejectType = (RpcMismatch=0,AuthError);
  TAuthErrorType = (BadCred=0,Rejected,BadVerf,RejectedVerf,TooWeak);
  TMsg = Record
    xid : uint32;
    case msgType : TMsgType of
    Call : (rpcvers,prog,vers,proc : uint32; cauth,cverf : TOpaqueAuth);
    Reply : (case acceptType : TMsgAcceptType of
              Accept: (rverf : TOpaqueAuth; case acceptStat : TAcceptType of ProgMismatch : (progMismatch : TMismatch));
              Reject:  (case rejectType : TRejectType of
                          RpcMismatch : (rpcVersMismatch : TMismatch);
                          AuthError : (authStat : TAuthErrorType)));
  end;
  PMsg = ^TMsg;
  TProvider = class(TObject)
    public
      next : TProvider;
      flavour : uint32;
      function CAuth(msg : PMsg; ctx : pointer) : boolean; virtual; abstract;
      function CVerf(msg : PMsg; ctx : pointer) : boolean; virtual; abstract;
      function SAuth(msg : PMsg; var ctx : pointer) : boolean; virtual; abstract;
      function CMArgs(xdr : PXdr; xstart, xend : uint32; ctx : pointer) : boolean; virtual; abstract;
      function CMRes(xdr : PXdr; xstart, xend : uint32; ctx : pointer) : boolean; virtual; abstract;
      function SMArgs(xdr : PXdr; xstart, xend : uint32; ctx : pointer) : boolean; virtual; abstract;
      function SMRes(xdr : PXdr; xstart, xend : uint32; ctx : pointer) : boolean; virtual; abstract;
  end;
  PRpcInc = ^TRpcInc;
  TRpcInc = record
    xdr : TXdr;
    msg : TMsg;
    pvr : TProvider;
    pctx : pointer;
  end;

  PRpcProc = ^TRpcProc;
  TRpcProc = record
    proc : uint32;
    cb : function(inc : PRpcInc) : boolean;
  end;
  PRpcVers = ^TRpcVers;
  TRpcVers = record
    next : PRpcVers;
    vers : uint32;
    procs : array of TRpcProc;
  end;
  PRpcProg = ^TRpcProg;
  TRpcProg = record
    next : PRpcProg;
    prog : uint32;
    vers : PRpcVers;
  end;
  TWaiter = class
    next : TWaiter;
    xid : uint32;
    timeout : uint64;
    pvr : TProvider;
    pctx : pointer;

    procedure OnReply(inc : PRpcInc); virtual; abstract;
    procedure OnTimeout(); virtual; abstract;
  end;

  function EncodeRpcMsg(xdr : PXdr; msg : PMsg) : boolean;
  function DecodeRpcMsg(xdr : PXdr; msg : PMsg) : boolean;

  procedure RegisterProgram(p : PRpcProg);
  function LookupProgram(prog, vers, proc: uint32; var pp : PRpcProg; var vv : PRpcVers; var pc : PRpcProc) : boolean;
  procedure RegisterProvider(pvr : TProvider);
  function LookupProvider(flav : uint32) : TProvider;
  procedure InitCall(inc : PRpcInc; prog,vers,proc : uint32; var handle : integer);
  procedure CompleteCall(inc : PRpcInc; handle : integer);
  procedure InitAcceptReply(inc : PRpcInc; xid : uint32; acceptStat : TAcceptType; var handle : integer);
  procedure CompleteAcceptReply(inc : PRpcInc; handle : integer);
  procedure InitRejectreply(inc : PRpcInc; xid : uint32; authStat : TAuthErrorType);

  procedure AwaitReply(waiter : TWaiter);
  procedure InvokeWaiter(xid : uint32; inc : PRpcInc);
  procedure ServiceWaiters();

  function RpcProcessIncoming(inc : PRpcInc) : boolean;

implementation

  var providers : TProvider;
      programs : PRpcProg;
      baseXid : uint32;
      waiters : TWaiter;


function EncodeOpaqueAuth(xdr : PXdr; auth : POpaqueAuth) : boolean;
    var sts : boolean;
begin
    sts := EncodeI32(xdr, auth^.flavour);
    sts := EncodeOpaque(xdr, auth^.auth, auth^.alen);
    sts := EncodeOpaque(xdr, auth^.verf, auth^.vlen);
    Result := sts;
end;

function DecodeOpaqueAuth(xdr : PXdr; auth : POpaqueAuth) : boolean;
    var sts : boolean;
begin
    sts := DecodeI32(xdr, auth^.flavour);
    sts := DecodeOpaque(xdr, auth^.auth, auth^.alen);
    sts := DecodeOpaque(xdr, auth^.verf, auth^.vlen);
    Result := sts;
end;

function EncodeRpcMsg(xdr : PXdr; msg : PMsg) : boolean;
  var sts : boolean;
begin
  sts := EncodeI32(xdr, msg^.xid);
  if sts then exit(sts);
  sts := EncodeI32(xdr, int32(msg^.msgType));
  if sts then exit(sts);

  case msg^.msgType of
  Call: begin
    sts := EncodeI32(xdr, msg^.rpcvers);
    if sts then exit(sts);
    sts := EncodeI32(xdr, msg^.prog);
    if sts then exit(sts);
    sts := EncodeI32(xdr, msg^.vers);
    if sts then exit(sts);
    sts := EncodeI32(xdr, msg^.proc);
    if sts then exit(sts);
    sts := EncodeOpaqueAuth(xdr, @msg^.cauth);
    if sts then exit(sts);
    sts := EncodeOpaqueAuth(xdr, @msg^.cverf);
    if sts then exit(sts);
  end;
  Reply: begin
    case msg^.acceptType of
    Accept: begin
      sts := EncodeOpaqueAuth(xdr, @msg^.rverf);
      if sts then exit(sts);
      if msg^.acceptStat = ProgMismatch then
      begin
        sts := EncodeI32(xdr, msg^.progMismatch.low);
        if sts then exit(sts);
        sts := EncodeI32(xdr, msg^.progMismatch.high);
        if sts then exit(sts);
        end;
      end;
    Reject: begin
      case msg^.rejectType of
      RpcMismatch : begin
        sts := EncodeI32(xdr, msg^.progMismatch.low);
        if sts then exit(sts);
        sts := EncodeI32(xdr, msg^.progMismatch.high);
        if sts then exit(sts);
        end;
      AuthError: begin
        sts := EncodeI32(xdr, int32(msg^.authStat));
        if sts then exit(sts);
        end;
      end;
    end;
  end;
  end;
  end;

  result := sts;
end;

function DecodeRpcMsg(xdr : PXdr; msg : PMsg) : boolean;
  var sts : boolean;
begin
  sts := DecodeU32(xdr, msg^.xid);
  if sts then exit(sts);
  sts := DecodeI32(xdr, int32(msg^.msgType));
  if sts then exit(sts);

  case msg^.msgType of
  Call: begin
    sts := DecodeU32(xdr, msg^.rpcvers);
    if sts then exit(sts);
    sts := DecodeU32(xdr, msg^.prog);
    if sts then exit(sts);
    sts := DecodeU32(xdr, msg^.vers);
    if sts then exit(sts);
    sts := DecodeU32(xdr, msg^.proc);
    if sts then exit(sts);
    sts := DecodeOpaqueAuth(xdr, @msg^.cauth);
    if sts then exit(sts);
    sts := DecodeOpaqueAuth(xdr, @msg^.cverf);
    if sts then exit(sts);
  end;
  Reply: begin
    case msg^.acceptType of
    Accept: begin
      sts := DecodeOpaqueAuth(xdr, @msg^.rverf);
      if sts then exit(sts);
      if msg^.acceptStat = ProgMismatch then
      begin
        sts := DecodeU32(xdr, msg^.progMismatch.low);
        if sts then exit(sts);
        sts := DecodeU32(xdr, msg^.progMismatch.high);
        if sts then exit(sts);
        end;
      end;
    Reject: begin
      case msg^.rejectType of
      RpcMismatch : begin
        sts := DecodeU32(xdr, msg^.progMismatch.low);
        if sts then exit(sts);
        sts := DecodeU32(xdr, msg^.progMismatch.high);
        if sts then exit(sts);
        end;
      AuthError: begin
        sts := DecodeI32(xdr, int32(msg^.authStat));
        if sts then exit(sts);
        end;
      end;
    end;
  end;
  end;
  end;

  result := sts;
end;


procedure RegisterProgram(p : PRpcProg);
begin
  p^.next := programs;
  programs := p;
end;

function LookupProgram(prog, vers, proc: uint32; var pp : PRpcProg; var vv : PRpcVers; var pc : PRpcProc) : boolean;
  var pprog : PRpcProg;
      pvers : PRpcVers;
      i : integer;
begin
  pprog := programs;
  while pprog <> nil do
  begin
    if pprog^.prog = prog then
    begin
        pvers := pprog^.vers;
        if pvers^.vers = vers then
        begin
                while pvers <> nil do
                begin
                          for i := 0 to length(pvers^.procs) do
                          if pvers^.procs[i].proc = proc then
                          begin
                              pp := pprog;
                              vv := pvers;
                              pc := @pvers^.procs[i];
                              exit(false);
                          end;
                end;
        end;
        pvers := pvers^.next;
    end;
    pprog := pprog^.next;
  end;

  Result := true;
end;

procedure RegisterProvider(pvr : TProvider); begin
   pvr.next := providers;
   providers := pvr;
end;

function LookupProvider(flav : uint32) : TProvider;
  var p : TProvider;
begin
  p := providers;
  while p <> nil do
  begin
    if p.flavour = flav then exit(p);
    p := p.next;
  end;
  exit(nil);
end;

procedure InitCall(inc : PRpcInc; prog,vers,proc : uint32; var handle : integer);
begin
    inc^.msg.xid := baseXid;
    baseXid := baseXid + 1;
    inc^.msg.msgType := Call;
    inc^.msg.rpcvers := 2;
    inc^.msg.prog := prog;
    inc^.msg.vers := vers;
    inc^.msg.proc := proc;
    if inc^.pvr <> nil then
       inc^.pvr.CAuth(@inc^.msg, inc^.pctx);

    ResetXdr(@inc^.xdr);
    EncodeRpcMsg(@inc^.xdr, @inc^.msg);
    handle := inc^.xdr.offset;
end;

procedure CompleteCall(inc : PRpcInc; handle : integer);
begin

  if inc^.pvr <> nil then
     inc^.pvr.cmargs(@inc^.xdr, handle, inc^.xdr.offset, inc^.pctx);

end;

procedure InitAcceptReply(inc : PRpcInc; xid : uint32; acceptStat : TAcceptType; var handle : integer);
begin
    inc^.msg.xid := xid;
    inc^.msg.msgType := Reply;
    inc^.msg.acceptType := Accept;
    inc^.msg.acceptStat := acceptStat;

    ResetXdr(@inc^.xdr);
    EncodeRpcMsg(@inc^.xdr, @inc^.msg);
    handle := inc^.xdr.offset;
end;

procedure CompleteAcceptReply(inc : PRpcInc; handle : integer);
begin
  if inc^.pvr <> nil then
     inc^.pvr.SMRes(@inc^.xdr, handle, inc^.xdr.offset, inc^.pctx);
end;

procedure InitRejectreply(inc : PRpcInc; xid : uint32; authStat : TAuthErrorType);
begin
    inc^.msg.xid := xid;
    inc^.msg.msgType := Reply;
    inc^.msg.acceptType := Reject;
    inc^.msg.rejectType := AuthError;
    inc^.msg.authStat := authStat;

    ResetXdr(@inc^.xdr);
    EncodeRpcMsg(@inc^.xdr, @inc^.msg);
end;

procedure AwaitReply(waiter : TWaiter);
begin
  waiter.next := waiters;
  waiters := waiter;
end;

function RpcNow() : uint64;
begin
  Result := TimeStampToMSecs(DateTimeToTimeStamp(Now));
end;

procedure ServiceWaiters();
  var w, timeouts, prev, next : TWaiter;
      now : uint64;
begin
  w := waiters;
  timeouts := nil;
  prev := nil;
  now := RpcNow();

  while w <> nil do
  begin
      if now >= w.timeout then
      begin
          next := w.next;

          if prev <> nil then prev.next := next
          else waiters := next;

          w.next := timeouts;
          timeouts := w;

          w := next;
      end
      else begin
        prev := w;
        w := w.next;
      end;
  end;
  w := timeouts;
  while w <> nil do begin
    next := w.next;
    w.OnTimeout();
    w := next;
  end;

end;

procedure InvokeWaiter(xid : uint32; inc : PRpcInc);
  var w, prev : TWaiter;
begin
  w := waiters;
  prev := nil;
  while w <> nil do
  begin
    if w.xid = xid then
    begin
        if prev <> nil then prev.next := w.next
        else waiters := w.next;

        inc^.pvr := w.pvr;
        inc^.pctx := w.pctx;
        w.OnReply(inc);
        exit;
    end;

    prev := w;
    w := w.next;
  end;

end;

function RpcProcessIncoming(inc : PRpcInc): boolean;
  var sts : boolean;
      p : PRpcProg;
      v : PRpcVers;
      pc : PRpcProc;
begin
  sts := DecodeRpcMsg(@inc^.xdr, @inc^.msg);
  if sts then exit(sts);

  case inc^.msg.msgType of
  Call: begin
    (* lookup proc *)
    sts := LookupProgram(inc^.msg.prog, inc^.msg.vers, inc^.msg.proc, p, v, pc);
    if sts then
    begin
      (* no program registered *)
    end
    else
    begin
      (* invoke rpc *)
    end;

  end;
  Reply: begin
  end;
  end;


  Result := false;
end;

end.

