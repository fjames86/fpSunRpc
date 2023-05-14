{ This file was automatically created by Lazarus. Do not edit!
  This source is only used to compile and install the package.
 }

unit sunrpc;

{$warn 5023 off : no warning about unused units}
interface

uses
  sunrpc.xdr, sunrpc.rpc, LazarusPackageIntf;

implementation

procedure Register;
begin
end;

initialization
  RegisterPackage('sunrpc', @Register);
end.
