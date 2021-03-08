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
  SysUtils,Globals,UserClass,Network.Transit;

Type
  // Access: from zone node to transit node
  // Transit: transit line between transit nodes
  // Transfer: non-transit between transit nodes
  // Egress: from transit node to zone node
  TConnectionType = (ctAccess,ctTransit,ctTransfer,ctEgress);

  TConnection = Class
  private
    UserClassVolume: Float64;
    Function GetVolumes(UserClass: Integer): Float64; inline;
  protected
    FConnectionType: TConnectionType;
    FFromNode,FToNode: Integer;
    FLine: TTransitLine;
    FImpedance,FHeadway,FBoardingPenalty,FCrowdingPenalty,FTime,FDistance,FCost: Float64;
    FMixedVolumes: TArray<Float64>;
  public
    Constructor Create;
    Procedure SetUserClassImpedance(const [ref] UserClass: TUserClass); virtual; abstract;
    Procedure AddVolume(const Volume: Float64);
    Procedure MixVolumes(const UserClass: Integer; const MixFactor: Float64);
    Procedure PushVolumesToLine; virtual;
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
  SetLength(FMixedVolumes,NUserClasses);
end;

Function TConnection.GetVolumes(UserClass: Integer): Float64;
begin
  Result := FMixedVolumes[UserClass];
end;

Procedure TConnection.AddVolume(const Volume: Float64);
begin
  UserClassVolume := UserClassVolume + Volume;
end;

Procedure TConnection.MixVolumes(const UserClass: Integer; const MixFactor: Float64);
begin
  FMixedVolumes[UserClass] := (1-MixFactor)*FMixedVolumes[UserClass] + MixFactor*UserClassVolume;
  UserClassVolume := 0.0;
end;

Procedure TConnection.PushVolumesToLine;
begin
end;

end.
