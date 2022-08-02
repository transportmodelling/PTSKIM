unit Network;

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
  Classes,SysUtils,Math,Generics.Defaults,Generics.Collections,PropSet,FloatHlp,
  matio,matio.Formats,Globals,UserClass,Connection,Network.Transit,Network.NonTransit,
  LineChoi,LineChoi.Gentile,Crowding,Crowding.WardmanWhelan;

Type
  TNonTransitConnection = Class(TConnection)
  public
    Procedure SetUserClassImpedance(const [ref] UserClass: TUserClass); override;
  end;

  TTransitConnection = Class(TConnection)
  private
    FFromStop,FToStop: Integer;
  public
    Procedure SetUserClassImpedance(const [ref] UserClass: TUserClass); override;
    Procedure PushVolumesToLine; override;
  public
    Property FromStop: Integer read FFromStop;
    Property ToStop: Integer read FToStop;
  end;

  TRouteSection = Class
  // Contains all connections between the same From and To node
  private
    FFromNode: Integer;
    FImpedance: Float64;
    FConnections: array of TConnection;
    Function GetConnections(Connection: Integer): TConnection; inline;
    Procedure AddConnection(const Connection: TConnection);
  public
    Function NConnections: Integer; inline;
    Destructor Destroy; override;
  public
    Property FromNode: Integer read FFromNode;
    Property Connections[Connection: Integer]: TConnection read GetConnections; default;
    Property Impedance: Float64 read FImpedance;
  end;

  TNode = Class
  private
    FNode: Integer;
    FLines: array of TTransitLine; // Outgoing lines
    FRouteSections: array of TRouteSection; // Incoming connections
    Function GetLines(Line: Integer): TTransitLine; inline;
    Function RouteSection(FromNode: Integer): TRouteSection;
    Function GetRouteSections(Section: Integer): TRouteSection; inline;
    Procedure Initialize(const [ref] UserClass: TUserClass;
                         const LineChoiceOptions: TLineChoiceOptionsList;
                         const LineChoiceModel: TLineChoiceModel);
  public
    Function NLines: Integer;
    Function NRouteSections: Integer;
    Destructor Destroy; override;
  public
    Property Node: Integer read FNode;
    Property Lines[Option: Integer]: TTransitLine read GetLines;
    Property RouteSections[Section: Integer]: TRouteSection read GetRouteSections; default;
  end;

  TNetwork = Class
  private
    Type
      TAcessVolumes = record
        Line,Node: Integer;
        Access: array {user class} of Float64;
      end;
    Var
      FNodes: array of TNode;
    Function GetNodes(Node: Integer): TNode; inline;
  public
    Constructor Create(const TransitNetwork: TTransitNetwork;
                       const NonTransitLevelOfService: TNonTransitLevelOfService);
    Procedure Initialize(const [ref] UserClass: TUserClass);
    Procedure MixVolumes(const UserClass: Integer; const MixFactor: Float64);
    Procedure PushVolumesToLines;
    Procedure SaveAccessTable(const FileName: String);
    Destructor Destroy; override;
  public
    Property Nodes[Node: Integer]: TNode read GetNodes; default;
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

Procedure TTransitConnection.SetUserClassImpedance(const [ref] UserClass: TUserClass);
begin
  if not Line.Overloaded(FFromStop) then
  begin
    if UserClass.CrowdingModel <> nil then
      FCrowdingPenalty := UserClass.CrowdingModel.CrowdingPenalty(Line,FromStop,ToStop)
    else
      FCrowdingPenalty := 0.0;
    FBoardingPenalty := UserClass.BoardingPenalty + Line.BoardingPenalty;
    if FCost = 0.0 then
      FImpedance := FBoardingPenalty + FCrowdingPenalty + FTime
    else
      FImpedance := FBoardingPenalty + FCrowdingPenalty + FTime + FCost/UserClass.ValueOfTime
  end else
    FImpedance := Infinity;
end;

Procedure TTransitConnection.PushVolumesToLine;
begin
  for Var UserClass := low(FMixedVolumes) to high(FMixedVolumes) do
  FLine.AddVolume(UserClass,FFromStop,FToStop,FMixedVolumes[UserClass]);
end;

////////////////////////////////////////////////////////////////////////////////

Function TRouteSection.GetConnections(Connection: Integer): TConnection;
begin
  Result := FConnections[Connection];
end;

Function TRouteSection.NConnections: Integer;
begin
  Result := Length(FConnections);
end;

Procedure TRouteSection.AddConnection(const Connection: TConnection);
begin
  var Index := NConnections;
  Setlength(FConnections,Index+1);
  FConnections[Index] := Connection;
end;

Destructor TRouteSection.Destroy;
begin
  for var Connection in FConnections do Connection.Free;
  inherited Destroy;
end;

////////////////////////////////////////////////////////////////////////////////

Function TNode.NLines: Integer;
begin
  Result := Length(FLines);
end;

Function TNode.GetLines(Line: Integer): TTransitLine;
begin
  Result := FLines[Line];
end;

Function TNode.NRouteSections: Integer;
begin
  Result := Length(FRouteSections);
end;

Function TNode.RouteSection(FromNode: Integer): TRouteSection;
begin
  // Search existing route sections
  for var RouteSection in FRouteSections do
  if RouteSection.FFromNode = FromNode then Exit(RouteSection);
  // Create new route section
  var Index := NRouteSections;
  Setlength(FRouteSections,Index+1);
  Result := TRouteSection.Create;
  Result.FFromNode := FromNode;
  FRouteSections[Index] := Result;
end;

Function TNode.GetRouteSections(Section: Integer): TRouteSection;
begin
  Result := FRouteSections[Section];
end;

Procedure TNode.Initialize(const [ref] UserClass: TUserClass;
                           const LineChoiceOptions: TLineChoiceOptionsList;
                           const LineChoiceModel: TLineChoiceModel);
begin
  if Length(FRouteSections) > 0 then
  begin
    // Calculate route section impedances
    for var RouteSection in FRouteSections do
    begin
      LineChoiceOptions.Clear;
      for var Connection in RouteSection.FConnections do
      begin
        Connection.SetUserClassImpedance(UserClass);
        if Connection.Impedance < Infinity then
        if Connection.Line = nil then
          LineChoiceOptions.AddOption(0.0,Connection.Impedance)
        else
          LineChoiceOptions.AddOption(Connection.Headway,Connection.Impedance);
      end;
      LineChoiceModel.LineChoice(LineChoiceOptions,RouteSection.FImpedance);
    end;
    // Sort route sections
    TArray.Sort<TRouteSection>(FRouteSections,TComparer<TRouteSection>.Construct(
           Function(const Left,Right: TRouteSection): Integer
           begin
             if Left.Impedance < Right.Impedance then Result := -1 else
             if Left.Impedance > Right.Impedance then Result := +1 else
             Result := 0;
           end ));
  end;
end;

Destructor TNode.Destroy;
begin
  for var RouteSection in FRouteSections do RouteSection.Free;
  inherited Destroy;
end;

////////////////////////////////////////////////////////////////////////////////

Constructor TNetwork.Create(const TransitNetwork: TTransitNetwork;
                            const NonTransitLevelOfService: TNonTransitLevelOfService);
Var
  Time,Distance,Cost: Float64;
begin
  inherited Create;
  // Initialize nodes
  SetLength(FNodes,NNodes);
  for var Node := 0 to NNodes-1 do
  begin
    FNodes[Node] := TNode.Create;
    FNodes[Node].FNode := Node;
  end;
  // Read transit network
  for var Line := 0 to TransitNetwork.NLines-1 do
  begin
    var TransitLine := TransitNetwork[Line];
    for var FromStop := 0 to TransitLine.NStops-1 do
    begin
      var FromNode := TransitLine[FromStop];
      if (FromNode >= NZones) and (FromNode < NNodes) then
      begin
        Time := 0.0;
        Distance := 0.0;
        Cost := 0.0;
        FNodes[FromNode].FLines := FNodes[FromNode].FLines + [TransitLine];
        for var ToStop := FromStop+1 to TransitLine.NStops-1 do
        begin
          var ToNode := TransitLine[ToStop];
          if (ToNode >= NZones) and (ToNode < NNodes) then
          begin
            var TransitConnection := TTransitConnection.Create;
            Time := Time + TransitLine.DwellTimes[ToStop] + TransitLine.Times[ToStop-1];
            Distance := Distance + TransitLine.Distances[ToStop-1];
            Cost := Cost + TransitLine.Costs[ToStop-1];
            TransitConnection.FConnectionType := ctTransit;
            TransitConnection.FLine := TransitLine;
            TransitConnection.FFromStop := FromStop;
            TransitConnection.FFromNode := FromNode;
            TransitConnection.FToStop := ToStop;
            TransitConnection.FToNode := ToNode;
            TransitConnection.FHeadway := TransitLine.Headway;
            TransitConnection.FTime := Time;
            TransitConnection.FDistance := Distance;
            TransitConnection.FCost := Cost;
            FNodes[ToNode].RouteSection(FromNode).AddConnection(TransitConnection);
          end else
            raise Exception.Create('Invalid node number (' + (ToNode+1).ToString + ') transit line ' + TransitLine.Name);
        end;
        if TransitLine.Circular then
        for var ToStop := 0 to FromStop-1 do
        begin
          var ToNode := TransitLine[ToStop];
          if (ToNode >= NZones) and (ToNode < NNodes) then
          begin
            var TransitConnection := TTransitConnection.Create;
            Time := Time + TransitLine.DwellTimes[ToStop] + TransitLine.Times[ToStop-1];
            Distance := Distance + TransitLine.Distances[ToStop-1];
            Cost := Cost + TransitLine.Costs[ToStop-1];
            TransitConnection.FConnectionType := ctTransit;
            TransitConnection.FLine := TransitLine;
            TransitConnection.FFromStop := FromStop;
            TransitConnection.FFromNode := FromNode;
            TransitConnection.FToStop := ToStop;
            TransitConnection.FToNode := ToNode;
            TransitConnection.FHeadway := TransitLine.Headway;
            TransitConnection.FTime := Time;
            TransitConnection.FDistance := Distance;
            TransitConnection.FCost := Cost;
            FNodes[ToNode].RouteSection(FromNode).AddConnection(TransitConnection);
          end else
            raise Exception.Create('Invalid node number (' + (ToNode+1).ToString + ') transit line ' + TransitLine.Name);
        end;
      end else
        raise Exception.Create('Invalid node number (' + (FromNode+1).ToString + ') transit line ' + TransitLine.Name);
    end;
  end;
  // Read non-transit level of service
  for var FromNode := 0 to NNodes-1 do
  begin
    NonTransitLevelOfService.ProceedToNextOrigin;
    for var ToNode := 0 to NNodes-1 do
    if (FromNode <> ToNode) and NonTransitLevelOfService.LevelOfService(ToNode,Time,Distance,Cost) then
    if ToNode < NZones then
    begin
      var EgressConnection := TNonTransitConnection.Create;
      SetLength(EgressConnection.FMixedVolumes,NUserClasses);
      EgressConnection.FConnectionType := ctEgress;
      EgressConnection.FFromNode := FromNode;
      EgressConnection.FToNode := ToNode;
      EgressConnection.FTime := Time;
      EgressConnection.FDistance := Distance;
      EgressConnection.FCost := Cost;
      FNodes[ToNode].RouteSection(FromNode).AddConnection(EgressConnection);
    end else
    begin
      for var Line := low(FNodes[ToNode].FLines) to high(FNodes[ToNode].FLines) do
      begin
        var AccessConnection := TNonTransitConnection.Create;
        SetLength(AccessConnection.FMixedVolumes,NUserClasses);
        if FromNode < NZones then
          AccessConnection.FConnectionType := ctAccess
        else
          AccessConnection.FConnectionType := ctTransfer;
        AccessConnection.FFromNode := FromNode;
        AccessConnection.FToNode := ToNode;
        AccessConnection.FLine := FNodes[ToNode].FLines[Line];
        AccessConnection.FTime := Time;
        AccessConnection.FDistance := Distance;
        AccessConnection.FCost := Cost;
        FNodes[ToNode].RouteSection(FromNode).AddConnection(AccessConnection);
      end;
    end
  end;
end;

Function TNetwork.GetNodes(Node: Integer): TNode;
begin
  Result := FNodes[Node];
end;

Procedure TNetwork.Initialize(const [ref] UserClass: TUserClass);
Var
  LineChoiceModel: TLineChoiceModel;
  LineChoiceOptions: TLineChoiceOptionsList;
begin
  LineChoiceModel := nil;
  LineChoiceOptions := nil;
  try
    LineChoiceModel := TGentileLineChoiceModel.Create;
    LineChoiceOptions := TLineChoiceOptionsList.Create;
    for var Node in FNodes do Node.Initialize(UserClass,LineChoiceOptions,LineChoiceModel);
  finally
    LineChoiceModel.Free;
    LineChoiceOptions.Free;
  end;
end;

Procedure TNetwork.MixVolumes(const UserClass: Integer; const MixFactor: Float64);
begin
  for var Node in FNodes do
  for var RouteSection in Node.FRouteSections do
  for var Connection in RouteSection.FConnections do
  Connection.MixVolumes(UserClass,MixFactor);
end;

Procedure TNetwork.PushVolumesToLines;
begin
  for var Node in FNodes do
  for var RouteSection in Node.FRouteSections do
  for var Connection in RouteSection.FConnections do
  Connection.PushVolumesToLine;
end;

Procedure TNetwork.SaveAccessTable(const FileName: String);
Var
  Volumes: TAcessVolumes;
  AccessVolumes: array {zone} of array of TAcessVolumes;
begin
  SetLength(AccessVolumes,NZones);
  // Get access volumes
  for var Node in FNodes do
  for var RouteSection in Node.FRouteSections do
  for var Connection in RouteSection.FConnections do
  if Connection.ConnectionType = ctAccess then
  begin
    var Zone := Connection.FromNode;
    Volumes.Line := Connection.Line.Line;
    Volumes.Node := Connection.ToNode;
    SetLength(Volumes.Access,NUserClasses);
    for var UserClass := 0 to NUserClasses-1 do
    Volumes.Access[UserClass] := Connection.Volumes[UserClass];
    AccessVolumes[Zone] := AccessVolumes[Zone] + [Volumes];
    Volumes.Access := nil;
  end;
  // Write table
  var Writer := TStreamWriter.Create(FileName);
  try
    // Write header
    Writer.Write(ZoneFieldName);
    Writer.Write(#9);
    Writer.Write(NodeFieldName);
    Writer.Write(#9);
    Writer.Write(LineFieldName);
    Writer.Write(#9);
    Writer.Write(UserClassFieldName);
    Writer.Write(#9);
    Writer.Write(AccessFieldName);
    Writer.WriteLine;
    // Write data
    for var Zone := 0 to NZones-1 do
    for var AccessVolume := low(AccessVolumes[Zone]) to high(AccessVolumes[Zone]) do
    for var UserClass := 0 to NUserClasses-1 do
    begin
      Writer.Write(Zone+1);
      Writer.Write(#9);
      Writer.Write(AccessVolumes[Zone,AccessVolume].Node+1);
      Writer.Write(#9);
      Writer.Write(AccessVolumes[Zone,AccessVolume].Line+1);
      Writer.Write(#9);
      Writer.Write(UserClass+1);
      Writer.Write(#9);
      Writer.Write(FormatFloat('0.##',AccessVolumes[Zone,AccessVolume].Access[UserClass]));
      Writer.WriteLine;
    end;
  finally
    Writer.Free;
  end;
end;

Destructor TNetwork.Destroy;
begin
  for var Node in FNodes do Node.Free;
  inherited Destroy;
end;

end.
