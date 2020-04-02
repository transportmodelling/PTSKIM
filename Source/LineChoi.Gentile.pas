unit LineChoi.Gentile;

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
  Math,LineChoi,Polynom,Spline;

Type
  TGentileLineChoiceModel = Class(TLineChoiceModel)
  // Line choice model as proposed by Gentile et al, 2005:
  // Route Choice on Transit Networks with Online Information at Stops.
  // Transportation Science 29(3), 289-297
  // For the case of deterministic line headways
  public
    Procedure LineChoice(const LineOptions: TLineChoiceOptions;
                         var LineProbabilities: array of Float64;
                         var WaitTime: Float64); override;
  end;

////////////////////////////////////////////////////////////////////////////////
implementation
////////////////////////////////////////////////////////////////////////////////

Procedure TGentileLineChoiceModel.LineChoice(const LineOptions: TLineChoiceOptions;
                                             var LineProbabilities: array of Float64;
                                             var WaitTime: Float64);
begin
  if LineOptions.NOptions > 1 then
  begin
    WaitTime := 0;
    for var Line := 0 to LineOptions.NOptions-1 do
    if LineOptions.TimeToDestination(Line) < Infinity then
    begin
      var Headway := LineOptions.Headway(Line);
      var TimeToDestination := LineOptions.TimeToDestination(Line);
      if Headway > 0 then
      begin
        // Transit option
        var BoardingSpline := TSpline.Create([0,Headway],[1/Headway]);
        var Polynomial := TPolynomial.Create([0,1/Headway]);
        var WaitTimeSpline := TSpline.Create([0,Headway],[Polynomial]);
        for var AlternativeLine := 0 to LineOptions.NOptions-1 do
        if (Line <> AlternativeLine) and (LineOptions.TimeToDestination(AlternativeLine) < Infinity) then
        begin
          var AlternativeHeadway := LineOptions.Headway(AlternativeLine);
          var AlternativeTimeToDestination := LineOptions.TimeToDestination(AlternativeLine);
          var TimeDiff := AlternativeTimeToDestination-TimeToDestination;
          var MaxWait := AlternativeHeadway+TimeDiff;
          if MaxWait < 0 then
          begin
            BoardingSpline.Nullify;
            WaitTimeSpline.Nullify;
            Break;
          end else
          if TimeDiff < 0 then
          begin
            Polynomial := [1-(TimeToDestination-AlternativeTimeToDestination)/AlternativeHeadway,-1/AlternativeHeadway];
            var Spline := TSpline.Create([0,MaxWait],[Polynomial]);
            BoardingSpline := BoardingSpline*Spline;
            WaitTimeSpline := WaitTimeSpline*Spline;
          end else
          if AlternativeHeadway > 0 then
          begin
            // Transit alternative
            Polynomial := [1-(TimeToDestination-AlternativeTimeToDestination)/AlternativeHeadway,-1/AlternativeHeadway];
            var Spline := TSpline.Create([0,TimeDiff,MaxWait],[1,Polynomial]);
            BoardingSpline := BoardingSpline*Spline;
            WaitTimeSpline := WaitTimeSpline*Spline;
          end else
          begin
            // Non-transit alternative
            var Spline := TSpline.Create([0,TimeDiff],[1]);
            BoardingSpline := BoardingSpline*Spline;
            WaitTimeSpline := WaitTimeSpline*Spline;
          end;
        end;
        LineProbabilities[Line] := BoardingSpline.Integrate;
        WaitTime := WaitTime + WaitTimeSpline.Integrate;
      end else
      begin
        //Non-transit option
        LineProbabilities[Line] := 1;
        for var AlternativeLine := 0 to LineOptions.NOptions-1 do
        if Line <> AlternativeLine then
        begin
          var AlternativeHeadway := LineOptions.Headway(AlternativeLine);
          var AlternativeTimeToDestination := LineOptions.TimeToDestination(AlternativeLine);
          if AlternativeHeadway > 0 then
          begin
            // Transit alternative
            if AlternativeTimeToDestination < TimeToDestination then
            begin
              var TimeDiff := TimeToDestination-AlternativeTimeToDestination;
              if TimeDiff <= AlternativeHeadway then
                LineProbabilities[Line] := LineProbabilities[Line]*(1-TimeDiff/AlternativeHeadway)
              else
                begin
                  LineProbabilities[Line] := 0;
                  Break;
                end;
            end;
          end else
          begin
            // Non-transit alternative
            if AlternativeTimeToDestination < TimeToDestination then
            begin
              LineProbabilities[Line] := 0;
              Break;
            end;
          end;
        end;
      end;
    end else LineProbabilities[Line] := 0;
  end else
  if LineOptions.NOptions = 1 then
  begin
    LineProbabilities[0] := 1.0;
    WaitTime := LineOptions.Headway(0)/2;
  end;
end;

end.
