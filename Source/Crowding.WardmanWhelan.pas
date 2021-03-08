unit Crowding.WardmanWhelan;

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
  Crowding;

Type
  TPurpose = (ppCommuting,ppOther);

  TWardmanWhelanCrowdingModel = Class(TCrowdingModel)
  //
  // Crowding model, based on the article:
  //
  // Wardman, M., and G.A. Whelan (2011) 20 Years or railway crowding valuation
  // studies: evidence and lessons from British experience.
  // Transport Reviews, 31, 379-398
  //
  // A trend line for the multipliers from this aricle is used, following:
  //
  // Bel, N. (2013) Crowding in train passenger assignment: A study on the
  // implementation of the influence of crowding on train passenger choice
  // behavior in assignment models.
  // Master thesis, Delft University of Technology, Delft, The Netherlands
  //
  private
    FPurpose: TPurpose;
    a,b,c,d: Float64;
  strict protected
    Function SeatedMultiplier(const SeatingCapacity,TotalCapacity,Volume: Float64): Float64; override;
    Function StandingMultiplier(const SeatingCapacity,TotalCapacity,Volume: Float64): Float64; override;
  public
    Constructor Create(Purpose: TPurpose);
    Property Purpose: TPurpose read FPurpose;
  end;

////////////////////////////////////////////////////////////////////////////////
implementation
////////////////////////////////////////////////////////////////////////////////

Constructor TWardmanWhelanCrowdingModel.Create(Purpose: TPurpose);
begin
  inherited Create;
  FPurpose := Purpose;
  case Purpose of
    ppCommuting:
      begin
        a := 0.7090;
        b := 0.3904;
        c := 1.0740;
        d := 0.4102;
      end;
    ppOther:
      begin
        a := 0.8539;
        b := 0.3894;
        c := 1.2854;
        d := 0.4120;
      end;
  end;
end;

Function TWardmanWhelanCrowdingModel.SeatedMultiplier(const SeatingCapacity,TotalCapacity,Volume: Float64): Float64;
begin
  Result := a*exp(b*Volume/SeatingCapacity);
end;

Function TWardmanWhelanCrowdingModel.StandingMultiplier(const SeatingCapacity,TotalCapacity,Volume: Float64): Float64;
begin
  Result := c*exp(d*Volume/SeatingCapacity);
end;

end.
