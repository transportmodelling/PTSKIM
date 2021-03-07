unit Crowding;

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
  Globals,Network.Transit;

Type
  TCrowdingModel = Class
  strict protected
    // Crowding multipliers
    Function SeatedMultiplier(const SeatingCapacity,TotalCapacity,Volume: Float64): Float64; virtual; abstract;
    Function StandingMultiplier(const SeatingCapacity,TotalCapacity,Volume: Float64): Float64; virtual; abstract;
  public
    Function CrowdingPenalty(const Line: TTransitLine; const FromStop,ToStop: Integer): Float64;
  end;

////////////////////////////////////////////////////////////////////////////////
implementation
////////////////////////////////////////////////////////////////////////////////

Function TCrowdingModel.CrowdingPenalty(const Line: TTransitLine; const FromStop,ToStop: Integer): Float64;
Var
  Standing,StandingProbability,Multiplier: Float64;
begin
  Result := 0.0;
  var LineSeats := Line.Seats[TimeOfDay];
  var LineCapacity := Line.Capacities[TimeOfDay];
  // Initialize standing probability
  var Boardings := Line.TotalBoardings[FromStop];
  var Volume := Line.TotalVolumes[FromStop];
  if Volume < LineSeats then Standing := 0.0 else Standing := Volume-LineSeats;
  if Standing > 0.0 then
    if Boardings > Standing then
      StandingProbability := Standing/Boardings
    else
      StandingProbability := 1.0
  else
    StandingProbability := 0.0;
  // Sum crowding penalties line segments
  for var Segment := FromStop to ToStop-1 do
  begin
    var Time := Line.Times[Segment];
    // Seated passengers
    if Volume < LineCapacity then
      Multiplier := SeatedMultiplier(LineSeats,LineCapacity,Volume)
    else
      Multiplier := SeatedMultiplier(LineSeats,LineCapacity,LineCapacity);
    if Multiplier > 1.0 then
    Result := Result + (1-StandingProbability)*(Multiplier-1.0)*Time;
    // Standing passengers
    if StandingProbability > 0.0 then
    begin
      if Volume < LineCapacity then
        Multiplier := StandingMultiplier(LineSeats,LineCapacity,Volume)
      else
        Multiplier := StandingMultiplier(LineSeats,LineCapacity,LineCapacity);
      if Multiplier > 1.0 then
      Result := Result + StandingProbability*(Multiplier-1.0)*Time;
    end;
    // Update standing probability
    if (StandingProbability > 0.0) and (Segment < ToStop-1) then
    begin
      var Alightings := Line.TotalAlightings[Segment+1];
      if Alightings < Standing then
      begin
        var SeatAcquisitionProbability := Alightings/Standing;
        StandingProbability := (1-SeatAcquisitionProbability)*StandingProbability;
      end else
        StandingProbability := 0.0;
      Standing := Standing - Alightings + Line.TotalBoardings[Segment+1];
      Volume := Volume - Alightings + Line.TotalBoardings[Segment+1];
    end;
  end;
end;

end.
