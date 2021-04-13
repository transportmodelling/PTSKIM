unit Network.Transit.IniFile;

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
  SysUtils,Classes,Math,IniFiles,ArrayHlp,Parse,Globals,Network.Transit;

Type
  TIniFileLine = Class(TTransitLine)
  private
    Const
      TwoWayIdent = 'TWOWAY';
      CircularIdent = 'CIRCULAR';
      HeadwaysIdent = 'HEADWAY';
      DwellTimesIdent = 'DWELLTIME';
      CapacitiesIdent = 'CAPACITY';
      SeatsIdent = 'SEATS';
      PenaltiesIdent = 'PENALTY';
      NodesIdent = 'NODES';
      TimesIdent = 'TIME';
      DistancesIdent = 'DIST';
      CostsIdent = 'COST';
      SpeedIdent = 'SPEED';
      BoardingsIdent = 'BOARD';
      AlightingsIdent = 'ALIGHT';
      VolumesIdent = 'VOLUMES';
    Var
      TwoWay: Boolean;
      Speed: Float64;
    Procedure ReadFromStrings(const LineName: String; const NodeOffset: Integer; const LineProperties: TStrings);
    Procedure SaveVolumes(const IniFile: TMemIniFile);
    Function CreateReverseLine: TIniFileLine;
  end;

  TLinesIniFile = Class(TTransitNetwork)
  private
    IniFile: TMemIniFile;
    FLines: array of TIniFileLine;
  strict protected
    Function GetLines(Line: Integer): TTransitLine; override;
  public
    Constructor Create(const FileName: String; const NodeOffset: Integer);
    Function NLines: Integer; override;
    Procedure SaveVolumes(const FileName: String);
    Destructor Destroy; override;
  end;

////////////////////////////////////////////////////////////////////////////////
implementation
////////////////////////////////////////////////////////////////////////////////

Procedure TIniFileLine.ReadFromStrings(const LineName: String;
                                       const NodeOffset: Integer;
                                       const LineProperties: TStrings);
begin
  // Name
  FName := LineName;
  // Two way
  var TwoWayLine := Trim(LineProperties.Values[TwoWayIdent]);
  if TwoWayLine = '1' then TwoWay := true else
  if TwoWayLine <> '0' then
    raise Exception.Create('Invalid ' + TwoWayIdent + '-value line ' + LineName);
  // Cicular
  var CircularIndex := LineProperties.IndexOfName(CircularIdent);
  if CircularIndex < 0 then FCircular := false else
  begin
    var Circular := Trim(LineProperties.ValueFromIndex[CircularIndex]);
    if Circular = '0' then FCircular := false else
      if Circular = '1' then FCircular := true else
        raise Exception.Create('Invalid value ' + CircularIdent + '-property line ' + LineName);
  end;
  // Headways
  FHeadWays := TStringParser.Create(Comma,LineProperties.Values[HeadwaysIdent]).ToFloatArray;
  // Dwell times
  FDwellTimes := TStringParser.Create(Comma,LineProperties.Values[DwellTimesIdent]).ToFloatArray;
  if FDwellTimes.Length = 0 then FDwellTimes.Length := TimeOfDay+1;
  // Capacities
  FCapacities := TStringParser.Create(Comma,LineProperties.Values[CapacitiesIdent]).ToFloatArray;
  if FCapacities.Length = 0 then
  begin
    FCapacities.Length := TimeOfDay+1;
    FCapacities.Initialize(Infinity);
  end;
  // Seats
  FSeats := TStringParser.Create(Comma,LineProperties.Values[SeatsIdent]).ToFloatArray;
  if FSeats.Length = 0 then FSeats := FCapacities;
  // Boarding penalties
  FBoardingPenalties := TStringParser.Create(Comma,LineProperties.Values[PenaltiesIdent]).ToFloatArray;
  if FBoardingPenalties.Length = 0 then FBoardingPenalties.Length := NUserClasses;
  // Stop nodes
  FStopNodes := TStringParser.Create(Comma,LineProperties.Values[NodesIdent]).ToIntArray;
  for var Stop := 0 to NStops-1 do FStopNodes[Stop] := FStopNodes[Stop]-NodeOffset-1;
  // Distances
  FDistances := TStringParser.Create(Comma,LineProperties.Values[DistancesIdent]).ToFloatArray;
  if Length(FDistances) <> NSegments then
    raise Exception.Create('Invalid ' + DistancesIdent + '-property line ' + LineName);
  // Costs
  var CostIndex := LineProperties.IndexOfName(CostsIdent);
  if CostIndex < 0 then FCosts.Length := Nsegments else
  begin
    FCosts := TStringParser.Create(Comma,LineProperties.ValueFromIndex[CostIndex]).ToFloatArray;
    if Length(FCosts) <> NSegments then
      raise Exception.Create('Invalid ' + CostsIdent + '-property line ' + LineName);
  end;
  // Times
  var SpeedIndex := LineProperties.IndexOfName(SpeedIdent);
  if SpeedIndex < 0 then
  begin
    FTimes := TStringParser.Create(Comma,LineProperties.Values[TimesIdent]).ToFloatArray;
    if Length(FTimes) <> NSegments then
      raise Exception.Create('Invalid ' + TimesIdent + '-property line ' + LineName);
  end else
  begin
    if LineProperties.IndexOfName(TimesIdent) < 0 then
    begin
      FTimes.Length := NSegments;
      Speed := LineProperties.ValueFromIndex[SpeedIndex].ToDouble;
      if Speed > 0 then
        for var Segment := 0 to NSegments-1 do FTimes[Segment] := FDistances[Segment]/Speed
      else
        raise Exception.Create('Invalid ' + SpeedIdent + '-property line ' + LineName);
    end else
      raise Exception.Create('Excessive ' + TimesIdent + '-property line ' + LineName);
  end;
  // Boarding / Alightings / Volumes
  SetLength(FBoardings,NUserClasses);
  SetLength(FAlightings,NUserClasses);
  SetLength(FVolumes,NUserClasses);
  for var UserClass := 0 to NUserClasses-1 do
  begin
    FBoardings[UserClass].Length := NStops;
    FAlightings[UserClass].Length := NStops;
    FVolumes[UserClass].Length := NSegments;
  end;
  FTotalBoardings.Length := NStops;
  FTotalAlightings.Length := NStops;
  FTotalVolumes.Length := NSegments;
  PreviousVolumes.Length := NSegments;
end;

Function TIniFileLine.CreateReverseLine: TIniFileLine;
begin
  Result := TIniFileLine.Create;
  // Name
  Result.FName := FName + '-Reverse';
  // Cicular
  Result.FCircular := FCircular;
  // Headways
  Result.FHeadWays := FHeadWays;
  // Dwell times
  Result.FDwellTimes := FDwellTimes;
  // Capacities
  Result.FCapacities := FCapacities;
  // Boarding penalties
  Result.FBoardingPenalties := FBoardingPenalties;
  // Stop nodes
  Result.FStopNodes.Length := NStops;
  for var Stop := 0 to NStops-1 do Result.FStopNodes[Stop] := FStopNodes[NStops-Stop-1];
  // Speed
  Result.Speed := Speed;
  // Times
  Result.FTimes.Length := NSegments;
  for var Segment := 0 to NSegments-1 do Result.FTimes[Segment] := FTimes[NSegments-Segment-1];
  // Distances
  Result.FDistances.Length := NSegments;
  for var Segment := 0 to NSegments-1 do Result.FDistances[Segment] := FDistances[NSegments-Segment-1];
  // Costs
  Result.FCosts.Length := NSegments;
  for var Segment := 0 to NSegments-1 do Result.FCosts[Segment] := FCosts[NSegments-Segment-1];
  // Boarding / Alightings / Volumes
  SetLength(Result.FBoardings,NUserClasses);
  SetLength(Result.FAlightings,NUserClasses);
  SetLength(Result.FVolumes,NUserClasses);
  for var UserClass := 0 to NUserClasses-1 do
  begin
    Result.FBoardings[UserClass].Length := NStops;
    Result.FAlightings[UserClass].Length := NStops;
    Result.FVolumes[UserClass].Length := NSegments;
  end;
  Result.FTotalBoardings.Length := NStops;
  Result.FTotalAlightings.Length := NStops;
  Result.FTotalVolumes.Length := NSegments;
  Result.PreviousVolumes.Length := NSegments;
end;

Procedure TIniFileLine.SaveVolumes(const IniFile: TMemIniFile);
begin
  // Two-way
  IniFile.WriteString(FName,TwoWayIdent,'0');
  // Circular
  if FCircular then
    IniFile.WriteString(FName,CircularIdent,'1')
  else
    IniFile.WriteString(FName,CircularIdent,'0');
  // Headways
  var Headways := FormatFloat('0.##',FHeadways[0]);
  for var TimeOfDay := 1 to Length(FHeadways)-1 do Headways := Headways + ',' + FormatFloat('0.##',FHeadways[TimeOfDay]);
  IniFile.WriteString(FName,HeadwaysIdent,Headways);
  // Dwell times
  if FDwellTimes.MaxValue > 0.0 then
  begin
    var DwellTimes := FormatFloat('0.##',FDwellTimes[0]);
    for var TimeOfDay := 1 to Length(FDwellTimes)-1 do DwellTimes := DwellTimes + ',' + FormatFloat('0.##',FDwellTimes[TimeOfDay]);
    IniFile.WriteString(FName,DwellTimesIdent,Headways);
  end;
  // Capacities
  if FCapacities.MinValue < Infinity then
  begin
    var Capacities := FormatFloat('0.##',FCapacities[0]);
    for var TimeOfDay := 1 to Length(FCapacities)-1 do Capacities := Capacities + ',' + FormatFloat('0.##',FCapacities[TimeOfDay]);
    IniFile.WriteString(FName,CapacitiesIdent,Capacities);
  end;
  // Boarding penalties
  if FBoardingPenalties.MaxValue > 0.0 then
  begin
    var Penalties := FormatFloat('0.##',FBoardingPenalties[0]);
    for var Userclass := 1 to Length(FBoardingPenalties)-1 do Penalties := Penalties + ',' + FormatFloat('0.##',FBoardingPenalties[Userclass]);
    IniFile.WriteString(FName,PenaltiesIdent,Penalties);
  end;
  // Speed
  if Speed > 0 then IniFile.WriteFloat(FName,SpeedIdent,Speed);
  // Stop nodes
  var StopNodes := (FStopNodes[0]+1).ToString;
  for var Stop := 1 to NStops-1 do StopNodes := StopNodes + ',' + (FStopNodes[Stop]+1).ToString;
  IniFile.WriteString(FName,NodesIdent,StopNodes);
  // Times
  if Speed <= 0 then
  begin
    var Times := FormatFloat('0.##',FTimes[0]);
    for var Segment := 1 to NSegments-1 do Times := Times + ',' + FormatFloat('0.##',FTimes[Segment]);
    IniFile.WriteString(FName,TimesIdent,Times);
  end;
  // Distances
  var Distances := FormatFloat('0.##',FDistances[0]);
  for var Segment := 1 to NSegments-1 do Distances := Distances + ',' + FormatFloat('0.##',FDistances[Segment]);
  IniFile.WriteString(FName,DistancesIdent,Distances);
  // Costs
  if FCosts.MaxValue > 0.0 then
  begin
    var Costs := FormatFloat('0.##',FCosts[0]);
    for var Segment := 1 to NSegments-1 do Costs := Costs + ',' + FormatFloat('0.##',FCosts[Segment]);
    IniFile.WriteString(FName,CostsIdent,Costs);
  end;
  for var UserClass := low(FVolumes) to high(FVolumes) do
  begin
    // Boardings
    var Boardings := FormatFloat('0.##',FBoardings[UserClass,0]);
    for var Stop := 1 to NStops-1 do Boardings := Boardings + ',' + FormatFloat('0.##',FBoardings[UserClass,Stop]);
    IniFile.WriteString(FName,BoardingsIdent+(UserClass+1).ToString,Boardings);
    // Alightings
    var Alightings := FormatFloat('0.##',FAlightings[UserClass,0]);
    for var Stop := 1 to NStops-1 do Alightings := Alightings + ',' + FormatFloat('0.##',FAlightings[UserClass,Stop]);
    IniFile.WriteString(FName,AlightingsIdent+(UserClass+1).ToString,Alightings);
    // Volumes
    var Volumes := FormatFloat('0.##',FVolumes[UserClass,0]);
    for var Segment := 1 to NSegments-1 do Volumes := Volumes + ',' + FormatFloat('0.##',FVolumes[UserClass,Segment]);
    IniFile.WriteString(FName,VolumesIdent+(UserClass+1).ToString,Volumes);
  end;
end;

////////////////////////////////////////////////////////////////////////////////

Constructor TLinesIniFile.Create(const FileName: String; const NodeOffset: Integer);
Var
  LineNames,LineProperties: TStringList;
begin
  inherited Create;
  if FileExists(FileName) then
  begin
    LineNames := nil;
    LineProperties := nil;
    IniFile := TMemIniFile.Create(FileName);
    try
      LineNames := TStringList.Create;
      LineProperties := TStringList.Create;
      IniFile.ReadSections(LineNames);
      for var Line := 0 to LineNames.Count-1 do
      begin
        var TransitLine := TIniFileLine.Create;
        var LineName := LineNames[Line];
        IniFile.ReadSectionValues(LineName,LineProperties);
        TransitLine.ReadFromStrings(LineName,NodeOffset,LineProperties);
        if TransitLine.TwoWay then
        begin
          FLines := FLines + [TransitLine,TransitLine.CreateReverseLine];
          TransitLine.TwoWay := false; // Two one-way lines now!
        end else
          FLines := FLines + [TransitLine];
      end
    finally
      LineNames.Free;
      LineProperties.Free;
    end;
  end else
    raise Exception.Create('LINES file does not exist');
end;

Function TLinesIniFile.GetLines(Line: Integer): TTransitLine;
begin
  Result := FLines[Line];
end;

Function TLinesIniFile.NLines: Integer;
begin
  Result := Length(FLines);
end;

Procedure TLinesIniFile.SaveVolumes(const FileName: String);
begin
  var LoadedNetwork := TMemIniFile.Create('');
  try
    for var Line := 0 to NLines-1 do FLines[Line].SaveVolumes(LoadedNetwork);
    LoadedNetwork.Rename(FileName,false);
    LoadedNetwork.UpdateFile;
  finally
    LoadedNetwork.Free;
  end;
end;

Destructor TLinesIniFile.Destroy;
begin
  IniFile.Free;
  for var Line := 0 to NLines-1 do FLines[Line].Free;
  inherited Destroy;
end;

end.
