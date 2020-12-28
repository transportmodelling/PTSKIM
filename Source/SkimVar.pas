unit SkimVar;

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
  Connection,Network,PathBld;

Type
  TImpedanceSkim = Class(TSkimVar)
  protected
    Function Value(const Node: TPathNode): Float64; override;
  end;

  TInitialWaitTimeSkim = Class(TSkimVar)
  protected
    Function Value(const Node: TPathNode): Float64; override;
  end;

  TWaitTimeSkim = Class(TNodeSkimVar)
  strict Protected
    Function NodeContribution(const Node: TPathNode): Float64; override;
  end;

  TBoardingsSkim = Class(TNodeSkimVar)
  strict Protected
    Function NodeContribution(const Node: TPathNode): Float64; override;
  end;

  TInVehicleTimeSkim = Class(TConnectionSkimVar)
  strict protected
    Function ConnectionContribution(const Connection: TPathConnection): Float64; override;
  end;

  TInVehicleDistanceSkim = Class(TConnectionSkimVar)
  strict protected
    Function ConnectionContribution(const Connection: TPathConnection): Float64; override;
  end;

  TTimeSkim = Class(TConnectionSkimVar)
  strict protected
    Function FromNodeContribution(const Node: TPathNode): Float64; override;
    Function ConnectionContribution(const Connection: TPathConnection): Float64; override;
  end;

  TDistanceSkim = Class(TConnectionSkimVar)
  strict protected
    Function ConnectionContribution(const Connection: TPathConnection): Float64; override;
  end;

  TCostSkim = Class(TConnectionSkimVar)
  strict protected
    Function ConnectionContribution(const Connection: TPathConnection): Float64; override;
  end;

////////////////////////////////////////////////////////////////////////////////
implementation
////////////////////////////////////////////////////////////////////////////////

Function TImpedanceSkim.Value(const Node: TPathNode): Float64;
begin
  Result := Node.Impedance;
end;

////////////////////////////////////////////////////////////////////////////////

Function TInitialWaitTimeSkim.Value(const Node: TPathNode): Float64;
begin
  Result := Node.WaitTime;
end;

////////////////////////////////////////////////////////////////////////////////

Function TWaitTimeSkim.NodeContribution(const Node: TPathNode): Float64;
begin
  Result := Node.WaitTime;
end;

////////////////////////////////////////////////////////////////////////////////

Function TBoardingsSkim.NodeContribution(const Node: TPathNode): Float64;
begin
  Result := 1;
end;

////////////////////////////////////////////////////////////////////////////////

Function TInVehicleTimeSkim.ConnectionContribution(const Connection: TPathConnection): Float64;
begin
  if Connection.ConnectionType = ctTransit then
    Result := Connection.Connection.Time
  else
    Result := 0.0;
end;

////////////////////////////////////////////////////////////////////////////////

Function TInVehicleDistanceSkim.ConnectionContribution(const Connection: TPathConnection): Float64;
begin
  if Connection.ConnectionType = ctTransit then
    Result := Connection.Connection.Distance
  else
    Result := 0.0;
end;

////////////////////////////////////////////////////////////////////////////////

Function TTimeSkim.FromNodeContribution(const Node: TPathNode): Float64;
begin
  Result := Node.WaitTime;
end;

Function TTimeSkim.ConnectionContribution(const Connection: TPathConnection): Float64;
begin
  Result := Connection.Connection.Time;
end;

////////////////////////////////////////////////////////////////////////////////

Function TDistanceSkim.ConnectionContribution(const Connection: TPathConnection): Float64;
begin
  Result := Connection.Connection.Distance;
end;

////////////////////////////////////////////////////////////////////////////////

Function TCostSkim.ConnectionContribution(const Connection: TPathConnection): Float64;
begin
  Result := Connection.Connection.Cost;
end;

end.
