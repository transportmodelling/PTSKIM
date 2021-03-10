unit PathBld;

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
  SysUtils,Math,Generics.Defaults,Generics.Collections,FloatHlp,matio,Globals,Connection,
  Network,Network.Transit,LineChoi,LineChoi.Gentile;

Type
  // Forward declarations
  TPathNode = Class;
  TPathConnection = Class;

  TSkimVar = Class
  protected
    Function Value(const Node: TPathNode): Float64; virtual; abstract;
  end;

  TNodeSkimVar = Class(TSkimVar)
  protected
    Function NodeContribution(const Node: TPathNode): Float64; virtual; abstract;
    Function Value(const Node: TPathNode): Float64; override; final;
  end;

  TConnectionSkimVar = Class(TSkimVar)
  protected
    Function FromNodeContribution(const Node: TPathNode): Float64; virtual;
    Function ConnectionContribution(const Connection: TPathConnection): Float64; virtual; abstract;
    Function Value(const Node: TPathNode): Float64; override; final;
  end;

  TPathConnection = Class
  private
    ConnectionVolume,HyperPathImpedance: Float64;
    FFromNode,FToNode: TPathNode;
    FConnection: TConnection;
    FromNodeOption: Integer;
    Function Headway: Float64; virtual;
    Function CalculateHyperpathImpedance: Float64; virtual;
    Procedure AddVolume(const Volume: Float64); virtual;
    Function Skim(const SkimVar: TConnectionSkimVar): Float64; virtual;
  public
    Function ConnectionType: TConnectionType; inline;
  public
    Property FromNode: TPathNode read FFromNode;
    Property ToNode: TPathNode read FToNode;
    Property Connection: TConnection read FConnection;
  end;

  TAccessPathConnection = Class(TPathConnection)
  private
    FBoardingNode: TPathNode;
    BoardingNodeOption: Integer;
    Function Headway: Float64; override;
    Function CalculateHyperpathImpedance: Float64; override;
    Procedure AddVolume(const Volume: Float64); override;
    Function Skim(const SkimVar: TConnectionSkimVar): Float64; override;
  public
    Property BoardingNode: TPathNode read FBoardingNode;
  end;

  TEgressPathConnection = Class(TPathConnection)
  private
    Function CalculateHyperpathImpedance: Float64; override;
  end;

  TPathNode = Class
  // DijkstraImpedance & HyperPathImpedance give the total weighted time
  // (including wait time and penalties) to the destination
  private
    FNode: Integer;
    FWaitTime,DijkstraImpedance,HyperPathImpedance,SkimValue,Volume: Float64;
    IsDestination,IsInList: Boolean;
    Next: TPathNode;
    Lines: array of TTransitLine; // Outgoing lines
    LineOptions: array of TPathConnection; // Best (outgoing) line connections
    LineProbabilities: array of Float64;
    Connections: array of TPathConnection; // Incoming connections
    Procedure InitDijkstra;
    Procedure InitHyperPath;
    Function GetLineOptions(const Options: TLineChoiceOptionsList): Boolean;
    Procedure UpdateFromNodes(var Last: TPathNode);
    Procedure PropagateVolume;
    Function NLines: Integer; inline;
    Function LineIndex(const TransitLine: TTransitLine): Integer;
  public
    Destructor Destroy; override;
  public
    Property Node: Integer read FNode;
    Property WaitTime: Float64 read FWaitTime;
    Property Impedance: Float64 read HyperPathImpedance;
  end;

  TPathBuilder = Class
  private
    Const
      InfProxy = 0.0;
    Var
      FNetwork: TNetwork;
      Nodes,SortedNodes: array of TPathNode;
      LineChoiceOptions: TLineChoiceOptionsList;
      LineChoiceModel: TLineChoiceModel;
    Procedure BackwardDijkstra(const Destination: Integer);
    Procedure HyperpathDijkstra(const Destination: Integer);
  public
    Constructor Create(const Network: TNetwork);
    Procedure BuildPaths(const Destination: Integer);
    Procedure UpdateRoutesCountCount(var RoutesCount: TArray<Byte>);
    Procedure TopologicalSort;
    Procedure Skim(const SkimTo: Integer;
                   const SkimVar: TSkimVar;
                   const SkimData: TFloat64MatrixRow); overload;
    Procedure Skim(const SkimTo: Integer;
                   const RoutesCount: TArray<Byte>;
                   const SkimVar: TSkimVar;
                   const SkimData: TFloat64MatrixRow); overload;
    Procedure Assign(const Volumes: TFloat32MatrixRow);
    Procedure PushVolumesToNetwork;
    Destructor Destroy; override;
  public
    Property Network: TNetwork read FNetwork;
  end;

////////////////////////////////////////////////////////////////////////////////
implementation
////////////////////////////////////////////////////////////////////////////////

Function TNodeSkimVar.Value(const Node: TPathNode): Float64;
begin
  Result := NodeContribution(Node);
  var OptionIndex := 0;
  for var Line := low(Node.Lines) to high(Node.Lines) do
  begin
    var Option := Node.LineOptions[Line];
    if Option  <> nil then
    if Option.HyperPathImpedance < Infinity then
    begin
      Result := Result + Node.LineProbabilities[OptionIndex]*Option.FToNode.SkimValue;
      Inc(OptionIndex);
    end;
  end;
end;

////////////////////////////////////////////////////////////////////////////////

Function TConnectionSkimVar.FromNodeContribution(const Node: TPathNode): Float64;
begin
  Result := 0.0;
end;

Function TConnectionSkimVar.Value(const Node: TPathNode): Float64;
begin
  Result := FromNodeContribution(Node);
  var OptionIndex := 0;
  for var Line := low(Node.Lines) to high(Node.Lines) do
  begin
    var Option := Node.LineOptions[Line];
    if Option  <> nil then
    if Option.HyperPathImpedance < Infinity then
    begin
      Result := Result + Node.LineProbabilities[OptionIndex]*(Option.FToNode.SkimValue+Option.Skim(Self));
      Inc(OptionIndex);
    end;
  end;
end;

////////////////////////////////////////////////////////////////////////////////

Function TPathConnection.ConnectionType: TConnectionType;
begin
  Result := Connection.ConnectionType;
end;

Function TPathConnection.Headway: Float64;
begin
  Result := Connection.Headway;
end;

Function TPathConnection.CalculateHyperpathImpedance: Float64;
begin
  Result := FConnection.Impedance + FToNode.HyperPathImpedance;
end;

Procedure TPathConnection.AddVolume(const Volume: Float64);
begin
  ConnectionVolume := ConnectionVolume + Volume;
end;

Function TPathConnection.Skim(const SkimVar: TConnectionSkimVar): Float64;
begin
  Result := SkimVar.ConnectionContribution(Self);
end;

////////////////////////////////////////////////////////////////////////////////

Function TAccessPathConnection.Headway: Float64;
begin
  var TransitConnection := FBoardingNode.LineOptions[BoardingNodeOption];
  if TransitConnection <> nil then
    Result := TransitConnection.Headway
  else
    Result := 0.0;
end;

Function TAccessPathConnection.CalculateHyperpathImpedance: Float64;
begin
  if FBoardingNode.IsDestination then
    Result := Infinity
  else
    begin
      var TransitConnection := FBoardingNode.LineOptions[BoardingNodeOption];
      if TransitConnection <> nil then
      begin
        FToNode := TransitConnection.FToNode;
        Result := FConnection.Impedance + TransitConnection.FConnection.Impedance + FToNode.HyperPathImpedance;
      end else
        Result := Infinity;
    end;
end;

Procedure TAccessPathConnection.AddVolume(const Volume: Float64);
begin
  inherited AddVolume(Volume);
  var TransitConnection := FBoardingNode.LineOptions[BoardingNodeOption];
  if TransitConnection <> nil then TransitConnection.AddVolume(Volume);
end;

Function TAccessPathConnection.Skim(const SkimVar: TConnectionSkimVar): Float64;
begin
  var TransitConnection := FBoardingNode.LineOptions[BoardingNodeOption];
  if TransitConnection <> nil then
    Result := SkimVar.ConnectionContribution(Self) + SkimVar.ConnectionContribution(TransitConnection)
  else
    Result := Infinity;
end;

////////////////////////////////////////////////////////////////////////////////

Function TEgressPathConnection.CalculateHyperpathImpedance: Float64;
begin
  if FToNode.IsDestination then
    Result := FConnection.Impedance + FToNode.HyperPathImpedance
  else
    Result := Infinity;
end;

////////////////////////////////////////////////////////////////////////////////

Procedure TPathNode.InitDijkstra;
begin
  IsInList := false;
  DijkstraImpedance := Infinity;
end;

Procedure TPathNode.InitHyperPath;
begin
  IsInList := false;
  HyperPathImpedance := Infinity;
  for var Line := low(Lines) to high(Lines) do LineOptions[Line] := nil;
end;

Function TPathNode.GetLineOptions(const Options: TLineChoiceOptionsList): Boolean;
begin
  Result := false;
  Options.Clear;
  for var Line := low(Lines) to high(Lines) do
  begin
    var Option := LineOptions[Line];
    if Option  <> nil then
    if Option.HyperPathImpedance < Infinity then
    begin
      Result := true;
      Options.AddOption(Option.Headway,Option.HyperPathImpedance);
    end;
  end;
end;

Procedure TPathNode.UpdateFromNodes(var Last: TPathNode);
begin
  for var Connection in Connections do
  begin
    var FromNode := Connection.FromNode;
    if FromNode.DijkstraImpedance > DijkstraImpedance then
    begin
      var FromNodeOption := Connection.FromNodeOption;
      var ConnectionImpedance := Connection.CalculateHyperpathImpedance;
      if ConnectionImpedance < Infinity then
      if (FromNode.LineOptions[FromNodeOption] = nil)
      or (ConnectionImpedance < FromNode.LineOptions[FromNodeOption].HyperPathImpedance) then
      begin
        Connection.HyperPathImpedance := ConnectionImpedance;
        if not FromNode.IsInList then
        begin
          FromNode.IsInList := true;
          Last.Next := FromNode;
          Last := FromNode;
          Last.Next := nil;
        end;
        FromNode.LineOptions[FromNodeOption] := Connection;
      end;
    end;
  end;
end;

Procedure TPathNode.PropagateVolume;
begin
  var OptionIndex := 0;
  for var Line := 0 to Nlines-1 do
  begin
    var Option := LineOptions[Line];
    if Option  <> nil then
    if Option.HyperPathImpedance < Infinity then
    begin
      var LineVolume := LineProbabilities[OptionIndex]*Volume;
      Option.AddVolume(LineVolume);
      Option.FToNode.Volume := Option.FToNode.Volume + LineVolume;
      Inc(OptionIndex);
    end;
  end;
end;

Function TPathNode.NLines: Integer;
begin
  Result := Length(Lines);
end;

Function TPathNode.LineIndex(const TransitLine: TTransitLine): Integer;
begin
  // Search existing lines
  for var Line := 0 to NLines-1 do
  if Lines[Line] = TransitLine then Exit(Line);
  // Create new line
  Result := NLines;
  Setlength(Lines,Result+1);
  Setlength(LineOptions,Result+1);
  SetLength(LineProbabilities,Result+1);
  Lines[Result] := TransitLine;
end;

Destructor TPathNode.Destroy;
begin
  for var Connection in Connections do Connection.Free;
  inherited Destroy;
end;

////////////////////////////////////////////////////////////////////////////////

Constructor TPathBuilder.Create(const Network: TNetwork);
begin
  inherited Create;
  FNetwork := Network;
  LineChoiceModel := TGentileLineChoiceModel.Create;
  LineChoiceOptions := TLineChoiceOptionsList.Create;
  // Create nodes
  SetLength(Nodes,NNodes);
  SetLength(SortedNodes,NNodes);
  for var Node := 0 to NNodes-1 do
  begin
    var PathNode := TPathNode.Create;
    var NetworkNode := Network.Nodes[Node];
    PathNode.FNode := Node;
    SetLength(PathNode.Lines,NetworkNode.NLines);
    SetLength(PathNode.LineOptions,NetworkNode.NLines);
    SetLength(PathNode.LineProbabilities,NetworkNode.NLines);
    for var Line := 0 to NetworkNode.NLines-1 do PathNode.Lines[Line] := NetworkNode.Lines[Line];
    Nodes[Node] := PathNode;
  end;
  // Add connections to nodes
  for var Node := 0 to NNodes-1 do
  begin
    var NConnections := 0;
    var PathNode := Nodes[Node];
    var NetworkNode := Network.Nodes[Node];
    for var Section := 0 to NetworkNode.NRouteSections-1 do
    begin
      var RouteSection := NetworkNode.RouteSections[Section];
      for var Connection := 0 to RouteSection.NConnections-1 do
      begin
        var NetworkConnection := RouteSection.Connections[Connection];
        var FromNode := Nodes[NetworkConnection.FromNode];
        if NetworkConnection.ConnectionType = ctTransit then
         begin
           var SkimConnection := TPathConnection.Create;
           Inc(NConnections);
           if Length(PathNode.Connections) < NConnections then SetLength(PathNode.Connections,NConnections+256);
           SkimConnection.FFromNode := FromNode;
           SkimConnection.FToNode := Nodes[NetworkConnection.ToNode];
           SkimConnection.FConnection := NetworkConnection;
           SkimConnection.FromNodeOption := FromNode.LineIndex(NetworkConnection.Line);
           PathNode.Connections[NConnections-1] := SkimConnection;
         end;
        if NetworkConnection.ConnectionType in [ctAccess,ctTransfer] then
        for var Line := 0 to NetworkNode.NLines-1 do
        begin
          var TransitLine := NetworkNode.Lines[Line];
          var SkimConnection := TAccessPathConnection.Create;
          var BoardingNode := Nodes[NetworkConnection.ToNode];
          Inc(NConnections);
          if Length(PathNode.Connections) < NConnections then SetLength(PathNode.Connections,NConnections+256);
          SkimConnection.FFromNode := FromNode;
          SkimConnection.FBoardingNode := BoardingNode;
          SkimConnection.FConnection := NetworkConnection;
          SkimConnection.FromNodeOption := FromNode.LineIndex(TransitLine);
          SkimConnection.BoardingNodeOption := BoardingNode.LineIndex(TransitLine);
          PathNode.Connections[NConnections-1] := SkimConnection;
        end;
        if NetworkConnection.ConnectionType in [ctTransfer,ctEgress] then
        begin
          var SkimConnection := TEgressPathConnection.Create;
          Inc(NConnections);
          if Length(PathNode.Connections) < NConnections then SetLength(PathNode.Connections,NConnections+256);
          SkimConnection.FFromNode := FromNode;
          SkimConnection.FToNode := Nodes[NetworkConnection.ToNode];
          SkimConnection.FConnection := NetworkConnection;
          SkimConnection.FromNodeOption := FromNode.LineIndex(NetworkConnection.Line);
          PathNode.Connections[NConnections-1] := SkimConnection;
        end;
      end;
    end;
    SetLength(PathNode.Connections,NConnections);
  end;
end;

Procedure TPathBuilder.BackwardDijkstra(const Destination: Integer);
// Label correcting backward Dijkstra algorithm
begin
  // Initialize candidate list
  for var Node in Nodes do Node.InitDijkstra;
  var First := Nodes[Destination];
  var Last := First;
  First.IsInList := true;
  First.Next := nil;
  First.DijkstraImpedance := 0.0;
  // Iterate candidate list
  while First <> nil do
  begin
    // Update from nodes route sections
    var NetworkNode := FNetwork[First.FNode];
    for var Section := 0 to NetworkNode.NRouteSections-1 do
    begin
      var RouteSection := NetworkNode.RouteSections[Section];
      var FromNode := Nodes[RouteSection.FromNode];
      var TestImpedance := First.DijkstraImpedance + RouteSection.Impedance;
      if TestImpedance < FromNode.DijkstraImpedance then
      begin
        FromNode.DijkstraImpedance := TestImpedance;
        if not FromNode.IsInList then
        begin
          FromNode.IsInList := true;
          Last.Next := FromNode;
          Last := FromNode;
          Last.Next := nil;
        end;
      end;
    end;
    // Remove first from list
    First.IsInList := false;
    First := First.Next;
  end;
end;

Procedure TPathBuilder.HyperpathDijkstra(const Destination: Integer);
// Label correcting hyperpath Dijkstra algorithm
begin
  // Initialize candidate list
  for var Node in Nodes do Node.InitHyperPath;
  var First := Nodes[Destination];
  var Last := First;
  First.IsInList := true;
  First.Next := nil;
  First.HyperPathImpedance := 0.0;
  First.UpdateFromNodes(Last);
  First.IsInList := false;
  First := First.Next;
  // Iterate list
  while First <> nil do
  begin
    // Apply line choice model
    if First.GetLineOptions(LineChoiceOptions) then
    begin
      LineChoiceModel.LineChoice(LineChoiceOptions,First.LineProbabilities,First.FWaitTime,First.HyperPathImpedance);
      First.UpdateFromNodes(Last);
    end;
    // Remove first from list
    First.IsInList := false;
    First := First.Next;
  end;
end;

Procedure TPathBuilder.BuildPaths(const Destination: Integer);
begin
  Nodes[Destination].IsDestination := true;
  try
    BackwardDijkstra(Destination);
    HyperpathDijkstra(Destination);
  finally
    Nodes[Destination].IsDestination := false;
  end;
end;

Procedure TPathBuilder.UpdateRoutesCountCount(var RoutesCount: TArray<Byte>);
begin
  for var Node := low(RoutesCount) to high(RoutesCount) do
  if Nodes[Node].HyperPathImpedance < Infinity then
  Inc(RoutesCount[Node]);
end;

Procedure TPathBuilder.TopologicalSort;
begin
  for var Node := 0 to NNodes-1 do SortedNodes[Node] := Nodes[Node];
  TArray.Sort<TPathNode>(SortedNodes,TComparer<TPathNode>.Construct(
         Function(const Left,Right: TPathNode): Integer
         begin
           if Left.DijkstraImpedance < Right.DijkstraImpedance then Result := -1 else
           if Left.DijkstraImpedance > Right.DijkstraImpedance then Result := +1 else
           Result := 0;
         end ));
end;

Procedure TPathBuilder.Skim(const SkimTo: Integer;
                            const SkimVar: TSkimVar;
                            const SkimData: TFloat64MatrixRow);
begin
  // Skim
  SortedNodes[0].SkimValue := 0.0;
  for var Node := 1 to NNodes-1 do
  if SortedNodes[Node].HyperPathImpedance < Infinity then
    SortedNodes[Node].SkimValue := SkimVar.Value(SortedNodes[Node])
  else
    SortedNodes[Node].SkimValue := Infinity;
  // Copy to skim data
  for var Node := 0 to SkimTo do
  if Nodes[Node].HyperPathImpedance < Infinity then
    SkimData[Node] := Nodes[Node].SkimValue
  else
    SkimData[Node] := InfProxy;
end;

Procedure TPathBuilder.Skim(const SkimTo: Integer;
                            const RoutesCount: TArray<Byte>;
                            const SkimVar: TSkimVar;
                            const SkimData: TFloat64MatrixRow);
begin
  // Skim
  SortedNodes[0].SkimValue := 0.0;
  for var Node := 1 to NNodes-1 do
  if SortedNodes[Node].HyperPathImpedance < Infinity then
    SortedNodes[Node].SkimValue := SkimVar.Value(SortedNodes[Node])
  else
    SortedNodes[Node].SkimValue := Infinity;
  // Copy to skim data
  for var Node := 0 to SkimTo do
  if Nodes[Node].HyperPathImpedance < Infinity then
  begin
    var MixFactor := 1/RoutesCount[Node];
    SkimData[Node] := (1-MixFactor)*SkimData[Node] + MixFactor*Nodes[Node].SkimValue;
  end;
end;

Procedure TPathBuilder.Assign(const Volumes: TFloat32MatrixRow);
begin
  // Init node volumes
  for var Node := 0 to Length(Volumes)-1 do Nodes[Node].Volume := Volumes[Node];
  for var Node := Length(Volumes) to NNodes-1 do Nodes[Node].Volume := 0.0;
  // Propagate volumes through network
  for var Node := NNodes-1 downto 0 do SortedNodes[Node].PropagateVolume;
end;

Procedure TPathBuilder.PushVolumesToNetwork;
begin
  for var Node in Nodes do
  for var Connection in Node.Connections do
  begin
    var NetworkConnection := Connection.Connection;
    NetworkConnection.AddVolume(Connection.ConnectionVolume);
    Connection.ConnectionVolume := 0.0;
  end;
end;

Destructor TPathBuilder.Destroy;
begin
  LineChoiceOptions.Free;
  for var Node in Nodes do Node.Free;
  inherited Destroy;
end;

end.
