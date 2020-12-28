unit Connection;

////////////////////////////////////////////////////////////////////////////////
//
// Author: Jaap Baak
// https://github.com/transportmodelling/PTSKIM
//
////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////
interface
////////////////////////////////////////////////////////////////////////////////

Uses
  SysUtils,Globals,Network.Transit;

Type
  // Access: from zone node to transit node
  // Transit: transit line between transit nodes
  // Transfer: non-transit between transit nodes
  // Egress: from transit node to zone node
  TConnectionType = (ctAccess,ctTransit,ctTransfer,ctEgress);

  TConnection = Class
  protected
    FConnectionType: TConnectionType;
    FFromNode,FToNode: Integer;
    FLine: TTransitLine;
    FImpedance,FHeadway,FPenalty,FTime,FDistance,FCost: Float64;
    FVolumes: TArray<Float64>;
    Function GetVolumes(UserClass: Integer): Float64; inline;
  public
    Constructor Create;
    Procedure SetUserClassImpedance(const [ref] UserClass: TUserClass); virtual; abstract;
    Procedure AddVolume(const UserClass: Integer; const Volume: Float64);
    Procedure PushVolumes; virtual;
  public
    Property ConnectionType: TConnectionType read FConnectionType;
    Property FromNode: Integer read FFromNode;
    Property ToNode: Integer read FToNode;
    Property Line: TTransitLine read FLine;
    Property Headway: Float64 read FHeadway;
    Property Time: Float64 read FTime;
    Property Distance: Float64 read FDistance;
    Property Cost: Float64 read FCost;
    Property Impedance: Float64 read FImpedance;
    Property Volumes[UserClas: Integer]: Float64 read GetVolumes;
  end;

////////////////////////////////////////////////////////////////////////////////
implementation
////////////////////////////////////////////////////////////////////////////////

Constructor TConnection.Create;
begin
  inherited Create;
  SetLength(FVolumes,NUserClasses);
end;

Function TConnection.GetVolumes(UserClass: Integer): Float64;
begin
  Result := FVolumes[UserClass];
end;

Procedure TConnection.AddVolume(const UserClass: Integer; const Volume: Float64);
begin
  FVolumes[UserClass] := FVolumes[UserClass] + Volume;
end;

Procedure TConnection.PushVolumes;
begin
end;

end.
