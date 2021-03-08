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

  TVolumeTotals = record
    Boardings,FirstBoardings,Alightings,LastAlightings: array {node} of Float64;
    AccessTrips,EgressTrips: array {zone} of array {stop} of Float64;
    Procedure SaveStopTotals(const FileName: String);
  end;

  TNetwork = Class
  private
    FNodes: array of TNode;
    Function GetNodes(Node: Integer): TNode; inline;
  public
    Constructor Create(const TransitNetwork: TTransitNetwork;
                       const NonTransitNetwork: TNonTransitNetwork);
    Procedure Initialize(const [ref] UserClass: TUserClass);
    Procedure MixVolumes(const UserClass: Integer; const MixFactor: Float64);
    Procedure PushVolumesToLines;
    Function VolumeTotals: TVolumeTotals;
    Destructor Destroy; override;
  public
    Property Nodes[Node: Integer]: TNode read GetNodes; default;
  end;

////////////////////////////////////////////////////////////////////////////////
implementation
////////////////////////////////////////////////////////////////////////////////

Procedure TTransitConnection.SetUserClassImpedance(const [ref] UserClass: TUserClass);
begin
  if not Line.Overloaded(FFromStop) then
  begin
    if UserClass.CrowdingModel <> nil then
      FCrowdingPenalty := UserClass.CrowdingModel.CrowdingPenalty(Line,FromStop,ToStop)
    else
      FCrowdingPenalty := 0.0;
    FBoardingPenalty := UserClass.BoardingPenalty + Line.BoardingPenalties[UserClass.UserClass];
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

Procedure TVolumeTotals.SaveStopTotals(const FileName: String);
begin
  var Writer := TStreamWriter.Create(FileName);
  try
    Writer.Write('Stop');
    Writer.Write(#9);
    Writer.Write('Boardings');
    Writer.Write(#9);
    Writer.Write('FirstBoardings');
    Writer.Write(#9);
    Writer.Write('Alightings');
    Writer.Write(#9);
    Writer.WriteLine('LastAlightings');
    for var Stop := 0 to NNodes-NZones-1 do
    begin
      Writer.Write(Stop+NZones+1);
      Writer.Write(#9);
      Writer.Write(FormatFloat('0.##',Boardings[Stop]));
      Writer.Write(#9);
      Writer.Write(FormatFloat('0.##',FirstBoardings[Stop]));
      Writer.Write(#9);
      Writer.Write(FormatFloat('0.##',Alightings[Stop]));
      Writer.Write(#9);
      Writer.WriteLine(FormatFloat('0.##',LastAlightings[Stop]));
    end;
  finally
    Writer.Free;
  end;
end;

////////////////////////////////////////////////////////////////////////////////

Constructor TNetwork.Create(const TransitNetwork: TTransitNetwork;
                            const NonTransitNetwork: TNonTransitNetwork);
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
        var Time := 0.0;
        var Distance := 0.0;
        var Cost := 0.0;
        FNodes[FromNode].FLines := FNodes[FromNode].FLines + [TransitLine];
        for var ToStop := FromStop+1 to TransitLine.NStops-1 do
        begin
          var ToNode := TransitLine[ToStop];
          if (ToNode >= NZones) and (ToNode < NNodes) then
          begin
            var TransitConnection := TTransitConnection.Create;
            Time := Time + TransitLine.Times[ToStop-1] + TransitLine.DwellTimes[TimeOfday];
            Distance := Distance + TransitLine.Distances[ToStop-1];
            Cost := Cost + TransitLine.Costs[ToStop-1];
            TransitConnection.FConnectionType := ctTransit;
            TransitConnection.FLine := TransitLine;
            TransitConnection.FFromStop := FromStop;
            TransitConnection.FFromNode := FromNode;
            TransitConnection.FToStop := ToStop;
            TransitConnection.FToNode := ToNode;
            TransitConnection.FHeadway := TransitLine.Headways[TimeOfDay];
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
            Time := Time + TransitLine.Times[ToStop-1] + TransitLine.DwellTimes[TimeOfday];
            Distance := Distance + TransitLine.Distances[ToStop-1];
            Cost := Cost + TransitLine.Costs[ToStop-1];
            TransitConnection.FConnectionType := ctTransit;
            TransitConnection.FLine := TransitLine;
            TransitConnection.FFromStop := FromStop;
            TransitConnection.FFromNode := FromNode;
            TransitConnection.FToStop := ToStop;
            TransitConnection.FToNode := ToNode;
            TransitConnection.FHeadway := TransitLine.Headways[TimeOfDay];
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
    NonTransitNetwork.ProceedToNextOrigin;
    for var ToNode := 0 to NNodes-1 do
    begin
      var Connection := NonTransitNetwork.Connection(ToNode);
      if Connection <> nil then FNodes[ToNode].RouteSection(FromNode).AddConnection(Connection);
    end;
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

Function TNetwork.VolumeTotals: TVolumeTotals;
begin
  SetLength(Result.Boardings,NNodes-NZones);
  SetLength(Result.FirstBoardings,NNodes-NZones);
  SetLength(Result.Alightings,NNodes-NZones);
  SetLength(Result.LastAlightings,NNodes-NZones);
  SetLength(Result.AccessTrips,NZones,NNodes-NZones);
  SetLength(Result.EgressTrips,NZones,NNodes-NZones);
  // Calculate totals
  for var Node in FNodes do
  for var RouteSection in Node.FRouteSections do
  for var Connection in RouteSection.FConnections do
  for var UserClass := 0 to NUserClasses-1 do
  begin
    var Volume := Connection.Volumes[UserClass];
    case Connection.ConnectionType of
      ctAccess:
        begin
          Result.FirstBoardings[Connection.ToNode-NZones].Add(Volume);
          Result.AccessTrips[Connection.FromNode,Connection.ToNode-NZones].Add(Volume);
        end;
      ctTransit:
        begin
          Result.Boardings[Connection.FromNode-NZones].Add(Volume);
          Result.Alightings[Connection.ToNode-NZones].Add(Volume);
        end;
      ctEgress:
        begin
          Result.LastAlightings[Connection.FromNode-NZones].Add(Volume);
          Result.EgressTrips[Connection.ToNode,Connection.FromNode-NZones].Add(Volume);
        end;
    end;
  end;
end;

Destructor TNetwork.Destroy;
begin
  for var Node in FNodes do Node.Free;
  inherited Destroy;
end;

end.
