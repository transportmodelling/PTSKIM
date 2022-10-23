unit Network.NonTransit;

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
  Classes, SysUtils, Types, Math, ArrayHlp, PropSet, Parse, Ctl, matio, matio.Formats,
  Globals, UserClass, Connection, Network.Coord;

Type
  TNonTransitConnection = Class(TConnection)
  public
    Procedure SetUserClassImpedance(const [ref] UserClass: TUserClass); override;
  end;

  TNonTransitNetwork = Class
  private
    FromNode: Integer;
    MaxAccessDistance,MaxTransferDistance,MaxEgressDistance: Float64;
    UseAsTheCrowFliesAccessEgressDistances,UseAsTheCrowFliesTransferDistances: Boolean;
    // As the crow flies distance fields
    Coordinates: TCoordinates;
    DistanceFactor,TimeFactor: Float64;
    // Level of service fields
    LevelOfServiceReader: TMatrixReader;
    Times,Distances,Costs: TMatrixRow;
    Function GetLevelOfService(const ToNode: Integer; out Time,Distance,Cost: Float64): Boolean;
  public
    Constructor Create;
    Function UsesLevelOfService: Boolean;
    Function UsesAsTheCrowFliesDistances: Boolean;
    Procedure Initialize(const NodesCoordinates: TCoordinates; const DetourFactor,Speed: Float64); overload;
    Procedure Initialize(const [ref] LevelOfService: TPropertySet); overload;
    Procedure ProceedToNextOrigin;
    Function Connection(const ToNode: Integer): TNonTransitConnection;
  end;

////////////////////////////////////////////////////////////////////////////////
implementation
////////////////////////////////////////////////////////////////////////////////

Procedure TNonTransitConnection.SetUserClassImpedance(const [ref] UserClass: TUserClass);
begin
  if FCost = 0.0 then
    FImpedance := FTime
  else
    FImpedance := FTime + FCost/UserClass.ValueOfTime;
end;

////////////////////////////////////////////////////////////////////////////////

Constructor TNonTransitNetwork.Create;
begin
  inherited Create;
  FromNode := -1;
  MaxAccessDistance := CtlFile.ToFloat('ACCDST',Infinity);
  MaxTransferDistance := CtlFile.ToFloat('TRFDST',Infinity);
  MaxEgressDistance := CtlFile.ToFloat('EGRDST',Infinity);
  UseAsTheCrowFliesAccessEgressDistances := CtlFile.ToBool('AECROW','0','1',false);
  UseAsTheCrowFliesTransferDistances := CtlFile.ToBool('TRFCROW','0','1',false)
end;

Function TNonTransitNetwork.GetLevelOfService(const ToNode: Integer; out Time,Distance,Cost: Float64): Boolean;
begin
  Result := false;
  if (((FromNode < NZones) or (ToNode < NZones)) and UseAsTheCrowFliesAccessEgressDistances)
  or ((FromNode >= NZones) and (ToNode >= NZones) and UseAsTheCrowFliesTransferDistances) then
  begin
    var CrowFlyDistance := sqrt(sqr(Coordinates[FromNode].X-Coordinates[ToNode].X) +
                                sqr(Coordinates[FromNode].Y-Coordinates[ToNode].Y));
    if CrowFlyDistance > 0.0 then
    begin
      Result := true;
      Time := TimeFactor*CrowFlyDistance;
      Distance := DistanceFactor*CrowFlyDistance;
      Cost := 0.0;
    end
  end else
  begin
    if LevelOfServiceReader <> nil then
    if Times[ToNode] > 0 then
    begin
      Result := true;
      Time := Times[ToNode];
      Distance := Distances[ToNode];
      Cost := Costs[ToNode];
    end
  end;
end;

Function TNonTransitNetwork.UsesLevelOfService: Boolean;
begin
  Result := (not UseAsTheCrowFliesAccessEgressDistances) or (not UseAsTheCrowFliesTransferDistances);
end;

Function TNonTransitNetwork.UsesAsTheCrowFliesDistances: Boolean;
begin
  Result := UseAsTheCrowFliesAccessEgressDistances or UseAsTheCrowFliesTransferDistances;
end;

Procedure TNonTransitNetwork.Initialize(const NodesCoordinates: TCoordinates; const DetourFactor,Speed: Float64);
begin
  Coordinates := NodesCoordinates;
  DistanceFactor := DetourFactor;
  TimeFactor := DetourFactor/Speed;
end;

Procedure TNonTransitNetwork.Initialize(const [ref] LevelOfService: TPropertySet);
begin
  if LevelOfService.Count > 0 then
  begin
    Times.Length := NNodes;
    Distances.Length := NNodes;
    Costs.Length := NNodes;
    LevelOfServiceReader := MatrixFormats.CreateReader(LevelOfService);
    if LevelOfServiceReader = nil then raise Exception.Create('Invalid matrix format');
  end;
end;

Procedure TNonTransitNetwork.ProceedToNextOrigin;
begin
  Inc(FromNode);
  if LevelOfServiceReader <> nil then LevelOfServiceReader.Read([Times,Distances,Costs]);
end;

Function TNonTransitNetwork.Connection(const ToNode: Integer): TNonTransitConnection;
Var
  Time,Distance,Cost: Float64;
begin
  Result := nil;
  if ((FromNode >= NZones) or (ToNode >= NZones)) and (FromNode <> ToNode) then
  begin
    if GetLevelOfService(ToNode,Time,Distance,Cost) then
    if FromNode < NZones then
    begin
      if Distance < MaxAccessDistance then
      begin
        Result := TNonTransitConnection.Create;
        Result.FConnectionType := ctAccess;
      end
    end else
    if ToNode < NZones then
    begin
      if Distance < MaxEgressDistance then
      begin
        Result := TNonTransitConnection.Create;
        Result.FConnectionType := ctEgress;
      end
    end else
    begin
      if Distance < MaxTransferDistance then
      begin
        Result := TNonTransitConnection.Create;
        Result.FConnectionType := ctTransfer;
      end
    end;
    if Result <> nil then
    begin
      SetLength(Result.FMixedVolumes,NUserClasses);
      Result.FFromNode := FromNode;
      Result.FToNode := ToNode;
      Result.FTime := Time;
      Result.FDistance := Distance;
      Result.FCost := Cost;
    end
  end;
end;

end.
