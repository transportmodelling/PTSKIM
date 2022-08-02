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
  Classes,SysUtils,Types,ArrayHlp,PropSet,Parse,matio,matio.Formats,Globals,UserClass,Connection;

Type
  TNonTransitLevelOfService = Class
  private
    FromNode: Integer;
    MaxAccessDist,MaxTransferDist,MaxEgressDist: Float64;
    AsTheCrowFliesAccessEgressDistances,AsTheCrowFliesTransferDistances: Boolean;
    // As the crow flies distance fields
    Coordinates: TArray<TPointF>;
    DistanceFactor,TimeFactor: Float64;
    // Level of service fields
    LevelOfServiceReader: TMatrixReader;
    Times,Distances,Costs: TMatrixRow;
    Function GetLevelOfService(const ToNode: Integer; out Time,Distance,Cost: Float64): Boolean;
  public
    Constructor Create(MaxAccessDistance,MaxTransferDistance,MaxEgressDistance: Float64;
                       UseAsTheCrowFliesAccessEgressDistances,UseAsTheCrowFliesTransferDistances: Boolean);
    Function UsesLevelOfService: Boolean;
    Function UsesAsTheCrowFliesDistances: Boolean;
    Procedure Initialize(const NodesFileName: String; const DetourFactor,Speed: Float64); overload;
    Procedure Initialize(const [ref] LevelOfService: TPropertySet); overload;
    Procedure ProceedToNextOrigin;
    Function LevelOfService(const ToNode: Integer; out Time,Distance,Cost: Float64): Boolean;
  end;

////////////////////////////////////////////////////////////////////////////////
implementation
////////////////////////////////////////////////////////////////////////////////

Constructor TNonTransitLevelOfService.Create(MaxAccessDistance,MaxTransferDistance,MaxEgressDistance: Float64;
                                      UseAsTheCrowFliesAccessEgressDistances,UseAsTheCrowFliesTransferDistances: Boolean);
begin
  inherited Create;
  FromNode := -1;
  MaxAccessDist := MaxAccessDistance;
  MaxTransferDist := MaxTransferDistance;
  MaxEgressDist := MaxEgressDistance;
  AsTheCrowFliesAccessEgressDistances := UseAsTheCrowFliesAccessEgressDistances;
  AsTheCrowFliesTransferDistances := UseAsTheCrowFliesTransferDistances;
end;

Function TNonTransitLevelOfService.GetLevelOfService(const ToNode: Integer; out Time,Distance,Cost: Float64): Boolean;
begin
  Result := false;
  if (((FromNode < NZones) or (ToNode < NZones)) and AsTheCrowFliesAccessEgressDistances)
  or ((FromNode >= NZones) and (ToNode >= NZones) and AsTheCrowFliesTransferDistances) then
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

Function TNonTransitLevelOfService.UsesLevelOfService: Boolean;
begin
  Result := (not AsTheCrowFliesAccessEgressDistances) or (not AsTheCrowFliesTransferDistances);
end;

Function TNonTransitLevelOfService.UsesAsTheCrowFliesDistances: Boolean;
begin
  Result := AsTheCrowFliesAccessEgressDistances or AsTheCrowFliesTransferDistances;
end;

Procedure TNonTransitLevelOfService.Initialize(const NodesFileName: String; const DetourFactor,Speed: Float64);
begin
  DistanceFactor := DetourFactor;
  TimeFactor := DetourFactor/Speed;
  // Read coordinates
  var NNodes := 0;
  var Reader := TStreamReader.Create(NodesFileName,TEncoding.ANSI);
  try
    var Parser := TStringParser.Create(Space);
    while not Reader.EndOfStream do
    begin
      Inc(NNodes);
      Parser.ReadLine(Reader);
      if Length(Coordinates) < NNodes then SetLength(Coordinates,NNodes+512);
      if Parser.Count >= 3 then
        if Parser.Int[0] = NNodes then
        begin
          Coordinates[NNodes-1].X := Parser[1];
          Coordinates[NNodes-1].Y := Parser[2];
        end else
          raise Exception.Create('Error reading coordinates node ' + NNodes.ToString)
      else
        raise Exception.Create('Error reading coordinates node ' + NNodes.ToString)
    end;
    SetLength(Coordinates,NNodes);
  finally
    Reader.Free;
  end;
end;

Procedure TNonTransitLevelOfService.Initialize(const [ref] LevelOfService: TPropertySet);
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

Procedure TNonTransitLevelOfService.ProceedToNextOrigin;
begin
  Inc(FromNode);
  if LevelOfServiceReader <> nil then LevelOfServiceReader.Read([Times,Distances,Costs]);
end;

Function TNonTransitLevelOfService.LevelOfService(const ToNode: Integer; out Time,Distance,Cost: Float64): Boolean;
begin
  Result := false;
  if ((FromNode >= NZones) or (ToNode >= NZones)) and (FromNode <> ToNode) then
  begin
    if GetLevelOfService(ToNode,Time,Distance,Cost) then
    if FromNode < NZones then
    begin
      if Distance < MaxAccessDist then Result := true
    end else
    if ToNode < NZones then
    begin
      if Distance < MaxEgressDist then
      begin
        Result := true;
      end
    end else
    begin
      if Distance < MaxTransferDist then
      begin
        Result := true;
      end
    end;
  end;
end;

end.
