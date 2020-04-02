unit LineChoi;

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
  Math;

Type
  TLineChoiceOptions = Class
  public
    Function NOptions: Integer; virtual; abstract;
    Function Headway(Option: Integer): Float64; virtual; abstract;
    Function TimeToDestination(Option: Integer): Float64; virtual; abstract;
  end;

  TLineChoiceOptionsList = Class(TLineChoiceOptions)
  private
    FNOptions,Capacity: Integer;
    FHeadways,FTimesToDestination: array of Float64;
  public
    // Manage content
    Procedure Clear;
    Procedure AddOption(const Headway,TimeToDestination: Float64);
    // Query content
    Function NOptions: Integer; override;
    Function Headway(Option: Integer): Float64; override;
    Function TimeToDestination(Option: Integer): Float64; override;
  end;

  TLineChoiceModel = Class
  private
    Probabilities: array of Float64;
  public
    Procedure LineChoice(const LineOptions: TLineChoiceOptions;
                         var LineProbabilities: array of Float64;
                         var WaitTime: Float64); overload; virtual; abstract;
  public
    Procedure LineChoice(const LineOptions: TLineChoiceOptions;
                         var LineProbabilities: array of Float64;
                         var WaitTime,TimeToDestination: Float64); overload;
    Procedure LineChoice(const LineOptions: TLineChoiceOptions;
                         var WaitTime,TimeToDestination: Float64); overload;
    Procedure LineChoice(const LineOptions: TLineChoiceOptions;
                         var TimeToDestination: Float64); overload;
  end;

////////////////////////////////////////////////////////////////////////////////
implementation
////////////////////////////////////////////////////////////////////////////////

Procedure TLineChoiceOptionsList.Clear;
begin
  FNOptions := 0;
end;

Procedure TLineChoiceOptionsList.AddOption(const Headway,TimeToDestination: Float64);
begin
  // Ensure capacity
  if FNOptions = Capacity then
  begin
    Capacity := Capacity + 32;
    SetLength(FHeadways,Capacity);
    SetLength(FTimesToDestination,Capacity);
  end;
  // Add option
  FHeadways[FNOptions] := Headway;
  FTimesToDestination[FNOPtions] := TimeToDestination;
  Inc(FNOptions);
end;

Function TLineChoiceOptionsList.NOptions: Integer;
begin
  Result := FNOptions;
end;

Function TLineChoiceOptionsList.Headway(Option: Integer): Float64;
begin
  Result := FHeadways[Option];
end;

Function TLineChoiceOptionsList.TimeToDestination(Option: Integer): Float64;
begin
  Result := FTimesToDestination[Option];
end;

////////////////////////////////////////////////////////////////////////////////

Procedure TLineChoiceModel.LineChoice(const LineOptions: TLineChoiceOptions;
                                      var LineProbabilities: array of Float64;
                                      var WaitTime,TimeToDestination: Float64);
begin
  var NOptions := LineOptions.NOptions;
  if NOptions > 0 then
  begin
    // Apply model
    if NOptions = 1 then
    begin
      LineProbabilities[0] := 1.0;
      WaitTime := LineOptions.Headway(0)/2;
    end else LineChoice(LineOptions,LineProbabilities,WaitTime);
    // Calculate time to destination
    TimeToDestination := WaitTime;
    for var Option := 0 to LineOptions.NOptions-1 do
    TimeToDestination := TimeToDestination + LineProbabilities[Option]*LineOptions.TimeToDestination(Option);
  end else
  begin
    WaitTime := Infinity;
    TimeToDestination := Infinity;
  end;
end;

Procedure TLineChoiceModel.LineChoice(const LineOptions: TLineChoiceOptions;
                                      var WaitTime,TimeToDestination: Float64);
begin
  var NOptions := LineOptions.NOptions;
  if Length(Probabilities) < NOptions then SetLength(Probabilities,NOptions+64);
  LineChoice(LineOptions,Probabilities,WaitTime,TimeToDestination);
end;

Procedure TLineChoiceModel.LineChoice(const LineOptions: TLineChoiceOptions;
                                      var TimeToDestination: Float64);
Var
  WaitTime: Float64;
begin
  LineChoice(LineOptions,WaitTime,TimeToDestination);
end;

end.
