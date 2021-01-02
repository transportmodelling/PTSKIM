unit Network.Transit;

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
  SysUtils,Math,FloatHlp,Globals;

Type
  TTransitLine = Class
  // The time property gives the time moving between two sequential stop nodes
  // (a line segment) and does not include the dwell time
  private
    Function GetHeadways(TimeOfDay: Integer): Float64; inline;
    Function GetDwellTimes(TimeOfDay: Integer): Float64; inline;
    Function GetCapacities(TimeOfDay: Integer): Float64; inline;
    Function GetBoardingPenalties(UserClass: Integer): Float64; inline;
    Function GetStopNodes(Stop: Integer): Integer; inline;
    Function GetTimes(Segment: Integer): Float64; inline;
    Function GetDistances(Segment: Integer): Float64; inline;
    Function GetCosts(Segment: Integer): Float64; inline;
    Function GetVolumes(UserClass,Segment: Integer): Float64; inline;
  strict protected
    FName: string;
    FCircular: Boolean;
    FStopNodes: TArray<Integer>;
    FHeadways,FDwellTimes,FCapacities,FBoardingPenalties,FTimes,FDistances,FCosts: TArray<Float64>;
    FVolumes,FBoardings,FAlightings,StoredVolumes,StoredBoardings,StoredAlightings: array of TArray<Float64>;
  public
    Function NStops: Integer; inline;
    Function NSegments: Integer; inline;
    Procedure StoreVolumes;
    Procedure AddVolume(const UserClass,FromStop,ToStop: Integer; const Volume: Float64);
    Function MixStoredVolumes(MixFactor: Float64): Float64;
    Function TotalVolume(Segment: Integer): Float64;
    Function SegmentOverload(Segment: Integer): Float64;
    Function TotalOverload: Float64;
  public
    Property Name: String read Fname;
    Property Circular: Boolean read FCircular;
    Property Headways[TimeOfDay: Integer]: Float64 read GetHeadways;
    Property Capacities[TimeOfDay: Integer]: Float64 read GetCapacities;
    Property DwellTimes[TimeOfDay: Integer]: Float64 read GetDwellTimes;
    Property BoardingPenalties[UserClass: Integer]: Float64 read GetBoardingPenalties;
    Property StopNodes[Stop: Integer]: Integer read GetStopNodes; default;
    Property Times[Segment: Integer]: Float64 read GetTimes;
    Property Distances[Segment: Integer]: Float64 read GetDistances;
    Property Costs[Segment: Integer]: Float64 read GetCosts;
    Property Volumes[UserClass,Segment: Integer]: Float64 read GetVolumes;
  end;

  TTransitNetwork = Class
  strict protected
    Function GetLines(Line: Integer): TTransitLine; virtual; abstract;
  public
    Function NLines: Integer; virtual; abstract;
    Procedure StoreVolumes;
    Function MixStoredVolumes(MixFactor: Float64): Float64;
  public
    Property Lines[Line: Integer]: TTransitLine read GetLines; default;
  end;

////////////////////////////////////////////////////////////////////////////////
implementation
////////////////////////////////////////////////////////////////////////////////

Function TTransitLine.GetHeadways(TimeOfDay: Integer): Float64;
begin
  try
    Result := FHeadways[TimeOfDay];
  except
    raise Exception.Create('Headway transit line ' + FName + ' not available for time of day ' + (TimeOfDay+1).ToString);
  end;
end;

Function TTransitLine.GetDwellTimes(TimeOfDay: Integer): Float64;
begin
  try
    Result := FDwellTimes[TimeOfDay];
  except
    raise Exception.Create('Dwell time transit line ' + FName + ' not available for time of day ' + (TimeOfDay+1).ToString);
  end;
end;

Function TTransitLine.GetCapacities(TimeOfDay: Integer): Float64;
begin
  try
    Result := FCapacities[TimeOfDay];
  except
    raise Exception.Create('Capacity transit line ' + FName + ' not available for time of day ' + (TimeOfDay+1).ToString);
  end;
end;

Function TTransitLine.GetBoardingPenalties(UserClass: Integer): Float64;
begin
  try
    Result := FBoardingPenalties[UserClass];
  except
    raise Exception.Create('Boarding penalty transit line ' + FName + ' not available for user class ' + (UserClass+1).ToString);
  end;
end;

Function TTransitLine.GetStopNodes(Stop: Integer): Integer;
begin
  Result := FStopNodes[Stop];
end;

Function TTransitLine.GetTimes(Segment: Integer): Float64;
begin
  Result := FTimes[Segment];
end;

Function TTransitLine.GetDistances(Segment: Integer): Float64;
begin
  Result := FDistances[Segment];
end;

Function TTransitLine.GetCosts(Segment: Integer): Float64;
begin
  Result := FCosts[Segment];
end;

Function TTransitLine.GetVolumes(UserClass,Segment: Integer): Float64;
begin
  if UserClass < Length(FVolumes) then
    Result := FVolumes[UserClass,Segment]
  else
    Result := 0.0;
end;

Function TTransitLine.NStops: Integer;
begin
  Result := Length(FStopNodes);
end;

Function TTransitLine.NSegments: Integer;
begin
  if FCircular then Result := NStops else Result := NStops-1;
end;

Function TTransitLine.TotalVolume(Segment: Integer): Float64;
begin
  Result := 0.0;
  for var UserClass := low(FVolumes) to high(FVolumes) do
  Result := Result + FVolumes[UserClass,Segment];
end;

Function TTransitLine.SegmentOverload(Segment: Integer): Float64;
begin
  var Capacity := FCapacities[TimeOfDay];
  if Capacity < Infinity then
  begin
    var SegmentVolume := TotalVolume(Segment);
    if SegmentVolume > FCapacities[TimeOfDay] then
      Result := Result + SegmentVolume - Capacity
    else
      Result := 0.0;
  end else
    Result := 0.0;
end;

Function TTransitLine.TotalOverload: Float64;
begin
  Result := 0.0;
  for var Segment := 0 to NSegments-1 do Result.Add(SegmentOverload(Segment));
end;

Procedure TTransitLine.StoreVolumes;
begin
  for var UserClass := 0 to NUserClasses-1 do
  begin
    for var Stop := 0 to NStops-1 do
    begin
      StoredBoardings[UserClass,Stop] := FBoardings[UserClass,Stop];
      FBoardings[UserClass,Stop] := 0.0;
      StoredAlightings[UserClass,Stop] := FAlightings[UserClass,Stop];
      FAlightings[UserClass,Stop] := 0.0;
    end;
    for var Segment := 0 to NSegments-1 do
    begin
      StoredVolumes[UserClass,Segment] := FVolumes[UserClass,Segment];
      FVolumes[UserClass,Segment] := 0.0;
    end;
  end;
end;

Procedure TTransitLine.AddVolume(const UserClass,FromStop,ToStop: Integer; const Volume: Float64);
begin
  FBoardings[UserClass,FromStop] := FBoardings[UserClass,FromStop] + Volume;
  FAlightings[UserClass,ToStop] := FAlightings[UserClass,ToStop] + Volume;
  for var Segment := FromStop to ToStop-1 do
  FVolumes[UserClass,Segment] := FVolumes[UserClass,Segment] + Volume;
end;

Function TTransitLine.MixStoredVolumes(MixFactor: Float64): Float64;
begin
  var Factor := 1-MixFactor;
  // Mix boardings and alightings
  for var UserClass := 0 to NUserClasses-1 do
  begin
    for var Stop := 0 to NStops-1 do
    begin
      FBoardings[UserClass,Stop] := Factor*StoredBoardings[UserClass,Stop] +
                                       MixFactor*FBoardings[UserClass,Stop];
      FAlightings[UserClass,Stop] := Factor*StoredAlightings[UserClass,Stop] +
                                        MixFactor*FAlightings[UserClass,Stop];
    end;
    // Mix volumes
    Result := 0.0;
    for var Segment := 0 to NSegments-1 do
    begin
      FVolumes[UserClass,Segment] := Factor*StoredVolumes[UserClass,Segment] +
                                     MixFactor*FVolumes[UserClass,Segment];
      Result := Result + Abs(StoredVolumes[UserClass,Segment]-FVolumes[UserClass,Segment]);
    end;
  end;
end;

////////////////////////////////////////////////////////////////////////////////

Procedure TTransitNetwork.StoreVolumes;
begin
  for var Line := 0 to NLines-1 do Lines[Line].StoreVolumes;
end;

Function TTransitNetwork.MixStoredVolumes(MixFactor: Float64): Float64;
begin
  var NLineSegments := 0;
  var AbsVolumeDiff := 0.0;
  for var Line := 0 to NLines-1 do
  begin
    NLineSegments := NLineSegments + Lines[Line].NSegments;
    AbsVolumeDiff := AbsVolumeDiff + Lines[Line].MixStoredVolumes(MixFactor);
  end;
  Result := AbsVolumeDiff/NLineSegments;
end;

end.
