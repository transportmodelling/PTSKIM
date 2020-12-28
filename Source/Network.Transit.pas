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
  SysUtils,Globals;

Type
  TTransitLine = Class
  // The time property gives the time moving between two sequential stop nodes
  // (a line segment) and does not include the dwell time
  private
    Function GetHeadways(TimeOfDay: Integer): Float64; inline;
    Function GetDwellTimes(TimeOfDay: Integer): Float64; inline;
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
    FHeadways,FDwellTimes,FBoardingPenalties,FTimes,FDistances,FCosts: TArray<Float64>;
    FVolumes,FBoardings,FAlightings: array of TArray<Float64>;
  public
    Function NStops: Integer; inline;
    Function NSegments: Integer; inline;
    Procedure AddVolume(const UserClass,FromStop,ToStop: Integer; const Volume: Float64);
  public
    Property Name: String read Fname;
    Property Circular: Boolean read FCircular;
    Property Headways[TimeOfDay: Integer]: Float64 read GetHeadways;
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

Procedure TTransitLine.AddVolume(const UserClass,FromStop,ToStop: Integer; const Volume: Float64);
begin
  FBoardings[UserClass,FromStop] := FBoardings[UserClass,FromStop] + Volume;
  FAlightings[UserClass,ToStop] := FAlightings[UserClass,ToStop] + Volume;
  for var Segment := FromStop to ToStop-1 do
  FVolumes[UserClass,Segment] := FVolumes[UserClass,Segment] + Volume;
end;

end.
