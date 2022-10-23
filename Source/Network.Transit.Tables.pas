unit Network.Transit.Tables;

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
  SysUtils, Classes, Math, FloatHlp, ArrayHlp, Parse, TxtTab, Ctl, Globals, Network.Transit;

Type
  TSpeedTimeDist = (stdTime,stdTimeDist,stdTimeSpeed,stdDistSpeed);

  TReversibleLine = Class(TTransitLine)
  private
    Line,ReverseLine: Integer;
    Speed,DwellTime: Float64;
    Procedure AllocateStops;
    Procedure AllocateSegments;
    Procedure Initialize(SpeedTimeDist: TSpeedTimeDist); overload;
    Procedure Initialize(const ReverseLine: TReversibleLine); overload;
    Procedure SaveStops(const Writer: TStreamWriter);
    Procedure SaveSegments(const Writer: TStreamWriter);
  end;

  TTransitNetworkTables = Class(TTransitNetwork)
  private
    FLines: array of TReversibleLine;
    Procedure ReadLinesTable(const SpeedTimeDist: TSpeedTimeDist);
    Procedure ReadStopsTable(Offset: Integer);
    Procedure ReadSegmentsTable(const SpeedTimeDist: TSpeedTimeDist);
  strict protected
    Function GetLines(Line: Integer): TTransitLine; override;
  public
    Constructor Create(Offset: Integer);
    Procedure SaveBoardingsTable;
    Procedure SaveVolumesTable;
  end;

////////////////////////////////////////////////////////////////////////////////
implementation
////////////////////////////////////////////////////////////////////////////////

Procedure TReversibleLine.AllocateStops;
begin
  if FStopNodes.Length <= FNStops then
  begin
    FStopNodes.Length := FNStops+32;
    FDwellTimes.Length := FNStops+32;
  end;
end;

Procedure TReversibleLine.AllocateSegments;
begin
  if FTimes.Length <= FNSegments then
  begin
    FTimes.Length := FNSegments+32;
    FDistances.Length := FNSegments+32;
    FCosts.Length := FNSegments+32;
  end;
end;

Procedure TReversibleLine.Initialize(SpeedTimeDist: TSpeedTimeDist);
begin
  // Allocate memory
  SetLength(FTotalVolumes,FNStops);
  SetLength(FTotalBoardings,FNStops);
  SetLength(FTotalAlightings,FNStops);
  SetLength(FTotalVolumes,FNSegments);
  SetLength(PreviousVolumes,FNSegments);
  SetLength(FBoardings,NUserClasses,FNStops);
  SetLength(FAlightings,NUserClasses,FNStops);
  SetLength(FVolumes,NUserClasses,FNSegments);
  // Calculate fields
  for var Stop := 0 to FNStops-1 do FDwellTimes[Stop].Add(DwellTime);
  for var Segment := 0 to FNSegments-1 do
  begin
    case SpeedTimeDist of
      stdTimeSpeed: FDistances[Segment] := Speed*FTimes[Segment];
      stdDistSpeed: FTimes[Segment] := FDistances[Segment]/Speed;
    end;
  end;
end;

Procedure TReversibleLine.Initialize(const ReverseLine: TReversibleLine);
begin
  // Copy nodes
  FNStops := ReverseLine.FNStops;
  FStopNodes.Length := FNStops;
  FDwellTimes.Length := FNStops;
  for var Stop := 0 to FNStops-1 do
  begin
    FStopNodes[Stop] := ReverseLine.FStopNodes[FNStops-Stop-1];
    FDwellTimes[Stop] := ReverseLine.FDwellTimes[FNStops-Stop-1];
  end;
  // Copy segments
  FNSegments := ReverseLine.FNSegments;
  FTimes.Length := FNSegments;
  FDistances.Length := FNSegments;
  FCosts.Length := FNSegments;
  for var Segment := 0 to FNSegments-1 do
  begin
    FTimes[Segment] := ReverseLine.FTimes[FNSegments-Segment-1];
    FDistances[Segment] := ReverseLine.FDistances[FNSegments-Segment-1];
    FCosts[Segment] := ReverseLine.FCosts[FNSegments-Segment-1];
  end;
end;

Procedure TReversibleLine.SaveStops(const Writer: TStreamWriter);
begin
  for var Stop := 0 to FNStops-1 do
  for var UserClass := 0 to NUserClasses-1 do
  if (FBoardings[UserClass,Stop]>0) or (FAlightings[UserClass,Stop]>0) then
  begin
    Writer.Write(Line+1);
    Writer.Write(#9);
    Writer.Write(Stop+1);
    Writer.Write(#9);
    Writer.Write(UserClass+1);
    Writer.Write(#9);
    Writer.Write(FormatFloat('0.##',FBoardings[UserClass,Stop]));
    Writer.Write(#9);
    Writer.Write(FormatFloat('0.##',FAlightings[UserClass,Stop]));
    Writer.WriteLine;
  end;
end;

Procedure TReversibleLine.SaveSegments(const Writer: TStreamWriter);
begin
  for var Segment := 0 to FNSegments-1 do
  for var UserClass := 0 to NUserClasses-1 do
  if FVolumes[UserClass,Segment] > 0 then
  begin
    Writer.Write(Line+1);
    Writer.Write(#9);
    Writer.Write(Segment+1);
    Writer.Write(#9);
    Writer.Write(UserClass+1);
    Writer.Write(#9);
    Writer.Write(FormatFloat('0.##',FVolumes[UserClass,Segment]));
    Writer.WriteLine;
  end;
end;

////////////////////////////////////////////////////////////////////////////////

Constructor TTransitNetworkTables.Create(Offset: Integer);
Var
  SpeedTimeDist: TSpeedTimeDist;
begin
  inherited Create;
  // Set speed-time-distance input mode
  var TableMode := CtlFile['STD'];
  if SameText(TableMode,'T') then SpeedTimeDist := stdTime else
  if SameText(TableMode,'TD') then SpeedTimeDist := stdTimeDist else
  if SameText(TableMode,'TS') then SpeedTimeDist := stdTimeSpeed else
  if SameText(TableMode,'DS') then SpeedTimeDist := stdDistSpeed else
  raise Exception.Create('Invalid STD-value');
  // Create network
  ReadLinesTable(SpeedTimeDist);
  ReadStopsTable(Offset);
  ReadSegmentsTable(SpeedTimeDist);
  // Initialize reverse lines
  for var Line := 0 to FNLines-1 do
  begin
    case FLines[Line].FNStops of
      0: begin
           var ReverseLine := FLines[Line].ReverseLine;
           if ReverseLine >= 0 then
             if ReverseLine < FNLines then
               if FLines[ReverseLine].FNStops > 0 then
                 FLines[Line].Initialize(FLines[ReverseLine])
               else
                 raise Exception.Create('No stops for Line ' + (Line+1).ToString)
             else
               raise Exception.Create('Invalid reverse line for line ' + (Line+1).ToString)
           else
             raise Exception.Create('No stops for Line ' + (Line+1).ToString)
         end;
      1: raise Exception.Create('Single stop for Line ' + (Line+1).ToString);
      else
        if ((FLines[Line].FNSegments<>FLines[Line].FNStops) and FLines[Line].Circular)
        or ((FLines[Line].FNSegments<>FLines[Line].FNStops-1) and (not FLines[Line].Circular)) then
        raise Exception.Create('Invalid number of segments for Line ' + (Line+1).ToString)
    end;
    FLines[Line].Initialize(SpeedTimeDist);
  end;
end;

Function TTransitNetworkTables.GetLines(Line: Integer): TTransitLine;
begin
  Result := FLines[Line];
end;

Procedure TTransitNetworkTables.ReadLinesTable(const SpeedTimeDist: TSpeedTimeDist);
begin
  var Reader := TTextTableReader.Create(CtlFile.InpFileName('LINES'));
  try
    // Set field indices
    var LineFieldIndex := Reader.IndexOf(LineFieldName,true);
    var ReverseFieldIndex := Reader.IndexOf(ReverseFieldName);
    var CircularFieldIndex := Reader.IndexOf(CircularFieldName);
    var HeadwayFieldIndex := Reader.IndexOf(HeadwayFieldName,true);
    var DwellTimeFieldIndex := Reader.IndexOf(DwellTimeFieldName);
    var CapacityFieldIndex := Reader.IndexOf(CapacityFieldName);
    var SeatsFieldIndex := Reader.IndexOf(SeatsFieldName);
    var PenaltyFieldIndex := Reader.IndexOf(PenaltyFieldName);
    var NameFieldIndex := Reader.IndexOf(NameFieldName);
    var SpeedFieldIndex := -1;
    if SpeedTimeDist in [stdTimeSpeed,stdDistSpeed] then
    SpeedFieldIndex := Reader.IndexOf(SpeedFieldName,true);
    // Read lines
    while Reader.ReadLine do
    begin
      if Reader[LineFieldIndex].ToInt = FNLines+1 then
      begin
        if Length(FLines) <= FNLines then SetLength(FLines,FNLines+64);
        FLines[FNLines] := TReversibleLine.Create;
        FLines[FNLines].Line := FNLines;
        FLines[FNLines].FHeadway := Reader[HeadwayFieldIndex];
        if SpeedFieldIndex >= 0 then FLines[FNLines].Speed := Reader[SpeedFieldIndex];
        if DwellTimeFieldIndex >= 0 then FLines[FNLines].DwellTime := Reader[DwellTimeFieldIndex];
        if PenaltyFieldIndex >= 0 then FLines[FNLines].FBoardingPenalty := Reader[PenaltyFieldIndex];
        if CapacityFieldIndex >= 0 then
          FLines[FNLines].FCapacity := Reader[CapacityFieldIndex]
        else
          FLines[FNLines].FCapacity := Infinity;
        if SeatsFieldIndex >= 0 then
          FLines[FNLines].FSeats := Reader[SeatsFieldIndex]
        else
          FLines[FNLines].FSeats := Infinity;
        if ReverseFieldIndex >= 0 then
        begin
          var ReverseLine := Reader[ReverseFieldIndex].ToInt-1;
          if (ReverseLine<0) or (ReverseLine>FNLines) or (FLines[ReverseLine].ReverseLine=FNLines) then
            FLines[FNLines].ReverseLine := ReverseLine
          else
            raise Exception.Create('Invalid ' + ReverseFieldName +
                                   '-field value in lines table at line ' + Reader.LineCount.ToString);
        end else
          FLines[FNLines].ReverseLine := -1;
        if CircularFieldIndex >= 0 then
        begin
          var Circular := Uppercase(Reader[CircularFieldIndex].ToChar);
          if (Circular = 'T') then FLines[NLines].FCircular := true else
          if (Circular = 'F') then FLines[NLines].FCircular := false else
          raise Exception.Create('Invalid ' + CircularFieldName +
                                 '-field value in lines table at line ' + Reader.LineCount.ToString);
        end;
        if NameFieldIndex >= 0 then FLines[FNLines].FName := Reader[NameFieldIndex];
        Inc(FNLines);
      end else
        raise Exception.Create('Invalid ' + LineFieldName +
                               '-field value in lines table at line ' + Reader.LineCount.ToString);
    end;
    SetLength(FLines,FNLines);
  finally
    Reader.Free;
  end;
end;

Procedure TTransitNetworkTables.ReadStopsTable(Offset: Integer);
begin
  var Reader := TTextTableReader.Create(CtlFile.InpFileName('STOPS'));
  try
    // Set field indices
    var LineFieldIndex := Reader.IndexOf(LineFieldName,true);
    var StopFieldIndex := Reader.IndexOf(StopFieldName,true);
    var NodeFieldIndex := Reader.IndexOf(NodeFieldName,true);
    var DwellTimeFieldIndex := Reader.IndexOf(DwellTimeFieldName);
    // Read stops
    while Reader.ReadLine do
    begin
      var Line := Reader[LineFieldIndex].ToInt-1;
      if (Line >= 0) and (Line < FNLines) then
      begin
        var ReverseLine := FLines[Line].ReverseLine;
        if ReverseLine < FNLines then
          if (ReverseLine < 0) or (FLines[ReverseLine].FNStops=0) then
          begin
            var Stop := Reader[StopFieldIndex].ToInt-1;
            if Stop = FLines[Line].FNStops then
            begin
              FLines[Line].AllocateStops;
              FLines[Line].FStopNodes[Stop] := Reader[NodeFieldIndex].ToInt-Offset-1;
              if DwellTimeFieldIndex >= 0 then FLines[Line].FDwellTimes[Stop] := FLines[Line].DwellTime;
              Inc(FLines[Line].FNStops);
            end else
              raise Exception.Create('Invalid ' + StopFieldName +
                                     '-field value in stops table at line ' + Reader.LineCount.ToString)
          end else
            raise Exception.Create('Cannot read stops for both line and reverse line in stops table at line ' + Reader.LineCount.ToString)
        else
          raise Exception.Create('Invalid ' + ReverseFieldName +
                                 '-field value in stops table at line ' + Reader.LineCount.ToString);
      end else
        raise Exception.Create('Invalid ' + LineFieldName +
                               '-field value in stops table at line ' + Reader.LineCount.ToString);
    end;
  finally
    Reader.Free;
  end;
end;

Procedure TTransitNetworkTables.ReadSegmentsTable(const SpeedTimeDist: TSpeedTimeDist);
begin
  var Reader := TTextTableReader.Create(CtlFile.InpFileName('SEGMENTS'));
  try
    // Set field indices
    var LineFieldIndex := Reader.IndexOf(LineFieldName,true);
    var SegmentFieldIndex := Reader.IndexOf(SegmentFieldName,true);
    var CostFieldIndex := Reader.IndexOf(CostFieldName);
    var TimeFieldIndex := -1;
    var DistanceFieldIndex := -1;
    if SpeedTimeDist in [stdTime,stdTimeDist,stdTimeSpeed] then
    TimeFieldIndex := Reader.IndexOf(TimeFieldName,true);
    if SpeedTimeDist in [stdTimeDist,stdDistSpeed] then
    DistanceFieldIndex := Reader.IndexOf(DistanceFieldName,true);
    // Read segments
    while Reader.ReadLine do
    begin
      var Line := Reader[LineFieldIndex].ToInt-1;
      if (Line >= 0) and (Line < FNLines) then
      begin
        var ReverseLine := FLines[Line].ReverseLine;
        if ReverseLine < FNLines then
          if (FLines[Line].ReverseLine < 0) or (FLines[ReverseLine].FNSegments=0) then
          begin
            var Segment := Reader[SegmentFieldIndex].ToInt-1;
            if Segment < FLines[Line].FNStops then
              if Segment = FLines[Line].FNSegments then
              begin
                FLines[Line].AllocateSegments;
                if TimeFieldIndex >= 0 then FLines[Line].FTimes[Segment] := Reader[TimeFieldIndex].ToFloat;
                if DistanceFieldIndex >= 0 then FLines[Line].FDistances[Segment] := Reader[DistanceFieldIndex].ToFloat;
                if CostFieldIndex >= 0 then FLines[Line].FCosts[Segment] := Reader[CostFieldIndex].ToFloat;
                Inc(FLines[Line].FNSegments);
              end else
                raise Exception.Create('Invalid ' + SegmentFieldName +
                                       '-field value in segments table at line ' + Reader.LineCount.ToString)
            else
              raise Exception.Create('Cannot have more segments than stop in segments table at line ' + Reader.LineCount.ToString);
          end else
            raise Exception.Create('Cannot read segments for both line and reverse line in segments table at line ' + Reader.LineCount.ToString)
        else
          raise Exception.Create('Invalid ' + ReverseFieldName +
                                 '-field value in segments table at line ' + Reader.LineCount.ToString);
      end else
        raise Exception.Create('Invalid ' + LineFieldName +
                               '-field value in segments table at line ' + Reader.LineCount.ToString);
    end;
  finally
    Reader.Free;
  end;
end;

Procedure TTransitNetworkTables.SaveBoardingsTable;
begin
  var BoardingsFileName := CtlFile.OutpFileName('BOARDS',true);
  if BoardingsFileName <> '' then
  begin
    var Writer := TStreamWriter.Create(BoardingsFileName);
    try
      // Write header
      Writer.Write(LineFieldName);
      Writer.Write(#9);
      Writer.Write(StopFieldName);
      Writer.Write(#9);
      Writer.Write(UserClassFieldName);
      Writer.Write(#9);
      Writer.Write(BoardingsFieldName);
      Writer.Write(#9);
      Writer.Write(AlightingsFieldName);
      Writer.WriteLine;
      // Write data
      for var Line := 0 to NLines-1 do FLines[Line].SaveStops(Writer);
    finally
      Writer.Free;
    end;
  end;
end;

Procedure TTransitNetworkTables.SaveVolumesTable;
begin
  var VolumesFileName := CtlFile.OutpFileName('VOLUMES',true);
  if VolumesFileName <> '' then
  begin
    var Writer := TStreamWriter.Create(VolumesFileName);
    try
      // Write header
      Writer.Write(LineFieldName);
      Writer.Write(#9);
      Writer.Write(SegmentFieldName);
      Writer.Write(#9);
      Writer.Write(UserClassFieldName);
      Writer.Write(#9);
      Writer.Write(VolumeFieldName);
      Writer.WriteLine;
      // Write data
      for var Line := 0 to NLines-1 do FLines[Line].SaveSegments(Writer);
    finally
      Writer.Free;
    end;
  end;
end;

end.
