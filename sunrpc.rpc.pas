unit sunrpc.rpc;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, sunrpc.xdr;

type
  TOpaqueAuth = Record
    flavour : int32;
    auth : array[0..399] of uint8;
    verf : array[0..399] of uint8;
  end;
  TMsgType = (Call=0,Reply);
  TMsgAcceptType = (Accept = 0, Reject);
  TAcceptType = (Success=0,ProgUnavail,ProgMismatch,ProcUnavail,GarbageArgs,Error);
  TRejectType = (RpcMismatch=0,AuthError);
  TAuthErrorType = (BadCred=0,Rejected,BadVerf,RejectedVerf,TooWeak);
  TMsg = Record
    xid : uint32;
    tag : TMsgType;
      (* TODO *)

  end;



implementation

end.

