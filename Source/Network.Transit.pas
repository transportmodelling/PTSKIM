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
    Function GetSeats(TimeOfDay: Integer): Float64; inline;
    Function GetCapacities(TimeOfDay: Integer): Float64; inline;
    Function GetBoardingPenalties(UserClass: Integer): Float64; inline;
    Function GetStopNodes(Stop: Integer): Integer; inline;
    Function GetTimes(Segment: Integer): Float64; inline;
    Function GetDistances(Segment: Integer): Float64; inline;
    Function GetCosts(Segment: Integer): Float64; inline;
    Function GetBoardings(UserClass,Stop: Integer): Float64; inline;
    Function GetTotalBoardings(Stop: Integer): Float64; inline;
    Function GetAlightings(UserClass,Stop: Integer): Float64; inline;
    Function GetTotalAlightings(Stop: Integer): Float64; inline;
    Function GetVolumes(UserClass,Segment: Integer): Float64; inline;
    Function GetTotalVolumes(Segment: Integer): Float64; inline;
    Function Convergence: Float64;
  strict protected
    FName: string;
    FCircular: Boolean;
    FStopNodes: TArray<Integer>;
    FHeadways,FDwellTimes,FSeats,FCapacities,FBoardingPenalties,FTimes,FDistances,FCosts,
    FTotalBoardings,FTotalAlightings,FTotalVolumes,PreviousVolumes: TArray<Float64>;
    FVolumes,FBoardings,FAlightings: array of TArray<Float64>;
  public
    Function NStops: Integer; inline;
    Function NSegments: Integer; inline;
    Procedure ResetVolumes;
    Procedure AddVolume(const UserClass,FromStop,ToStop: Integer; const Volume: Float64);
    Function Overloaded(Stop: Integer): Boolean;
  public
    Property Name: String read Fname;
    Property Circular: Boolean read FCircular;
    Property Headways[TimeOfDay: Integer]: Float64 read GetHeadways;
    Property Seats[TimeOfDay: Integer]: Float64 read GetSeats;
    Property Capacities[TimeOfDay: Integer]: Float64 read GetCapacities;
    Property DwellTimes[TimeOfDay: Integer]: Float64 read GetDwellTimes;
    Property BoardingPenalties[UserClass: Integer]: Float64 read GetBoardingPenalties;
    Property StopNodes[Stop: Integer]: Integer read GetStopNodes; default;
    Property Times[Segment: Integer]: Float64 read GetTimes;
    Property Distances[Segment: Integer]: Float64 read GetDistances;
    Property Costs[Segment: Integer]: Float64 read GetCosts;
    Property Boardings[UserClass,Stop: Integer]: Float64 read GetBoardings;
    Property TotalBoardings[Stop: Integer]: Float64 read GetTotalBoardings;
    Property Alightings[UserClass,Stop: Integer]: Float64 read GetAlightings;
    Property TotalAlightings[Stop: Integer]: Float64 read GetTotalAlightings;
    Property Volumes[UserClass,Segment: Integer]: Float64 read GetVolumes;
    Property TotalVolumes[Segment: Integer]: Float64 read GetTotalVolumes;
  end;

  TTransitNetwork = Class
  strict protected
    Function GetLines(Line: Integer): TTransitLine; virtual; abstract;
  public
    Function NLines: Integer; virtual; abstract;
    Procedure ResetVolumes;
    Function Convergence: Float64;
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

Function TTransitLine.GetSeats(TimeOfDay: Integer): Float64;
begin
  try
    Result := FSeats[TimeOfDay];
  except
    raise Exception.Create('Seats transit line ' + FName + ' not available for time of day ' + (TimeOfDay+1).ToString);
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

Function TTransitLine.GetBoardings(UserClass,Stop: Integer): Float64;
begin
  Result := FBoardings[UserClass,Stop]
end;

Function TTransitLine.GetTotalBoardings(Stop: Integer): Float64;
begin
  Result := FTotalBoardings[Stop];
end;

Function TTransitLine.GetAlightings(UserClass,Stop: Integer): Float64;
begin
  Result := FAlightings[UserClass,Stop]
end;

Function TTransitLine.GetTotalAlightings(Stop: Integer): Float64;
begin
  Result := FTotalAlightings[Stop]
end;

Function TTransitLine.GetVolumes(UserClass,Segment: Integer): Float64;
begin
  if UserClass < Length(FVolumes) then
    Result := FVolumes[UserClass,Segment]
  else
    Result := 0.0;
end;

Function TTransitLine.GetTotalVolumes(Segment: Integer): Float64;
begin
  Result := FTotalVolumes[Segment];
end;

Function TTransitLine.Convergence: Double;
begin
  Result := 0.0;
  for var Segment := 0 to NSegments-1 do
  Result := Result + Abs(FTotalVolumes[Segment]-PreviousVolumes[Segment]);
end;

Function TTransitLine.NStops: Integer;
begin
  Result := Length(FStopNodes);
end;

Function TTransitLine.NSegments: Integer;
begin
  if FCircular then Result := NStops else Result := NStops-1;
end;

Function TTransitLine.Overloaded(Stop: Integer): Boolean;
begin
  Result := (FTotalVolumes[Stop] > FCapacities[TimeOfDay]);
end;

Procedure TTransitLine.ResetVolumes;
begin
  for var Stop := 0 to NStops-1 do
  begin
    for var UserClass := 0 to NUserClasses-1 do
    begin
      FBoardings[UserClass,Stop] := 0.0;
      FAlightings[UserClass,Stop] := 0.0;
    end;
    FTotalBoardings[Stop] := 0.0;
    FTotalAlightings[Stop] := 0.0;
  end;
  for var Segment := 0 to NSegments-1 do
  begin
    for var UserClass := 0 to NUserClasses-1 do FVolumes[UserClass,Segment] := 0.0;
    PreviousVolumes[Segment] := FTotalVolumes[Segment];
    FTotalVolumes[Segment] := 0.0;
  end;
end;

Procedure TTransitLine.AddVolume(const UserClass,FromStop,ToStop: Integer; const Volume: Float64);
begin
  FBoardings[UserClass,FromStop] := FBoardings[UserClass,FromStop] + Volume;
  FTotalBoardings[FromStop] := FTotalBoardings[FromStop] + Volume;
  FAlightings[UserClass,ToStop] := FAlightings[UserClass,ToStop] + Volume;
  FTotalAlightings[ToStop] := FTotalAlightings[ToStop] + Volume;
  for var Segment := FromStop to ToStop-1 do
  begin
    FVolumes[UserClass,Segment] := FVolumes[UserClass,Segment] + Volume;
    FTotalVolumes[Segment] := FTotalVolumes[Segment] + Volume;
  end;
end;

////////////////////////////////////////////////////////////////////////////////

Procedure TTransitNetwork.ResetVolumes;
begin
  for var Line := 0 to NLines-1 do Lines[Line].ResetVolumes;
end;

Function TTransitNetwork.Convergence: Float64;
begin
  var NLineSegments := 0;
  var AbsVolumeDiff := 0.0;
  for var Line := 0 to NLines-1 do
  begin
    NLineSegments := NLineSegments + Lines[Line].NSegments;
    AbsVolumeDiff := AbsVolumeDiff + Lines[Line].Convergence;
  end;
  Result := AbsVolumeDiff/NLineSegments;
end;

end.
