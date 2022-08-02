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
  SysUtils,Classes,Math,FloatHlp,Globals;

Type
  TTransitLine = Class
  // The time property gives the time moving between two sequential stop nodes
  // (a line segment) and does not include the dwell time
  private
    Function GetStopNodes(Stop: Integer): Integer; inline;
    Function GetDwellTimes(Stop: Integer): Float64; inline;
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
  protected
    FName: string;
    FLine,FNStops,FNSegments: Integer;
    FCircular: Boolean;
    FHeadway,FBoardingPenalty,FSeats,FCapacity: Float64;
    FStopNodes: TArray<Integer>;
    FDwellTimes,FTimes,FDistances,FCosts,
    FTotalBoardings,FTotalAlightings,FTotalVolumes,PreviousVolumes: TArray<Float64>;
    FBoardings,FAlightings,FVolumes: array of TArray<Float64>;
  public
    Procedure ResetVolumes;
    Procedure AddVolume(const UserClass,FromStop,ToStop: Integer; const Volume: Float64);
    Function Overloaded(Stop: Integer): Boolean;
  public
    Property Name: String read Fname;
    Property Line: Integer read FLine;
    Property NStops: Integer read FNStops;
    Property NSegments: Integer read FNSegments;
    Property Circular: Boolean read FCircular;
    Property Headway: Float64 read FHeadway;
    Property Seats: Float64 read FSeats;
    Property Capacity: Float64 read FCapacity;
    Property BoardingPenalty: Float64 read FBoardingPenalty;
    Property StopNodes[Stop: Integer]: Integer read GetStopNodes; default;
    Property DwellTimes[Stop: Integer]: Float64 read GetDwellTimes;
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
    FNLines: Integer;
    Function GetLines(Line: Integer): TTransitLine; virtual; abstract;
  public
    Procedure ResetVolumes;
    Function Convergence: Float64;
  public
    Property NLines: Integer read FNLines;
    Property Lines[Line: Integer]: TTransitLine read GetLines; default;
  end;

////////////////////////////////////////////////////////////////////////////////
implementation
////////////////////////////////////////////////////////////////////////////////

Function TTransitLine.GetStopNodes(Stop: Integer): Integer;
begin
  Result := FStopNodes[Stop];
end;

Function TTransitLine.GetDwellTimes(Stop: Integer): Float64;
begin
  Result := FDwellTimes[Stop];
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

Function TTransitLine.Overloaded(Stop: Integer): Boolean;
begin
  Result := (FTotalVolumes[Stop] > FCapacity);
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
