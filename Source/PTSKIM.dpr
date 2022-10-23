program PTSKIM;

////////////////////////////////////////////////////////////////////////////////
//
// Author: Jaap Baak
// https://github.com/transportmodelling/PTSKIM
//
////////////////////////////////////////////////////////////////////////////////

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.Classes,
  System.SysUtils,
  System.IOUtils,
  System.Math,
  ArrayHlp,
  Parse,
  PropSet,
  matio,
  matio.formats,
  matio.text,
  FloatHlp,
  Polynom,
  Spline,
  PFL,
  Ctl, Log,
  Globals in 'Globals.pas',
  UserClass in 'UserClass.pas',
  Connection in 'Connection.pas',
  Network in 'Network.pas',
  Network.Transit in 'Network.Transit.pas',
  Network.NonTransit in 'Network.NonTransit.pas',
  PathBld in 'PathBld.pas',
  SkimVar in 'SkimVar.pas',
  LineChoi in 'LineChoi.pas',
  LineChoi.Gentile in 'LineChoi.Gentile.pas',
  Crowding in 'Crowding.pas',
  Crowding.WardmanWhelan in 'Crowding.WardmanWhelan.pas',
  Network.Transit.Tables in 'Network.Transit.Tables.pas',
  Network.Coord in 'Network.Coord.pas';

Type
  TPTSkim = Class
  public
    Procedure Execute;
  end;

Procedure TPTSkim.Execute;
Var
  SpeedTimeDist: TSpeedTimeDist;
  UserClasses: array of TUserClass;
  Coordinates: TCoordinates;
  NonTransitNetwork: TNonTransitNetwork;
  TransitNetwork: TTransitNetworkTables;
  Network: TNetwork;
  PathBuilders: array of TPathBuilder;
  DestinationsLoop: TParallelFor;
  SkimVar: String;
  NThreads,NSkim: Integer;
  SkimVariables: TArray<String>;
  SkimVars: array of TSkimVar;
  Volumes: array of TFloat32MatrixRow;
  RoutesCount,ImpedanceCount: array {destination} of TArray<Byte>;
  SkimData: array {user class} of array {destination} of array {skim var} of TFloat64MatrixRow;
  VolumesReader: TMatrixReader;
  SkimRows: array of TFloat64MatrixRow;
  SkimWriter: TMatrixWriter;
begin
  if ParamCount > 0 then
  begin
    var ControlFileName := ParamStr(1);
    if CtlFile.Read(ControlFileName) then
    begin
      Coordinates := nil;
      NonTransitNetwork := nil;
      TransitNetwork := nil;
      Network := nil;
      DestinationsLoop := nil;
      try
        try
          // Open log file
          LogFile := TLogFile.Create(CtlFile.ToFileName('LOG'),false);
          LogFile.Log('Ctl-file',ExpandFileName(ControlFileName));
          LogFile.Log;
          // Init headers text matrices
          TTextMatrixWriter.RowLabel := 'Orig';
          TTextMatrixWriter.ColumnLabel := 'Dest';
          // Set parameters
          var Offset := CtlFile.ToInt('OFFSET',0);
          if CtlFile.Contains('ZONES') then
          begin
            if CtlFile.Contains('NODES') then
            begin
              Coordinates := TCoordinates.Create(CtlFile.InpFileName('ZONES'),CtlFile.InpFileName('NODES'),Offset);
              NZones := Coordinates.ZoneCount;
              NNodes := Coordinates.Count;
            end else
            begin
              Coordinates := TCoordinates.Create(CtlFile.InpFileName('ZONES'));
              NZones := Coordinates.ZoneCount;
              NNodes := CtlFile.ToInt('NNODES');
            end;
          end else
          begin
            NZones := CtlFile.ToInt('NZONES',0);
            if CtlFile.Contains('NODES') then
            begin
              Coordinates := TCoordinates.Create(CtlFile.InpFileName('NODES'),NZones,Offset);
              NNodes := Coordinates.Count;
            end else
              NNodes := CtlFile.ToInt('NNODES');
          end;
          NUserClasses := CtlFile.ToInt('NCLASS');
          if (NZones >= 0) and (NNodes > NZones) then
          begin
            // Set userclasses
            SetLength(UserClasses,NUserClasses);
            var Crowding := false;
            var VOT := CtlFile.Parse('VOT',Comma).ToFloatArray;
            var BoardingPenalty := CtlFile.Parse('PENALTY',Comma).ToFloatArray;
            var CrowdingModel := CtlFile.Parse('CROWD',Comma).ToIntArray;
            for var UserClass := 0 to NUserClasses-1 do
            begin
              UserClasses[UserClass].UserClass := UserClass;
              if Length(BoardingPenalty) = 0 then
                UserClasses[UserClass].BoardingPenalty := 0.0
              else
                UserClasses[UserClass].BoardingPenalty := BoardingPenalty[UserClass];
              if Length(VOT) = 0 then
                UserClasses[UserClass].ValueOfTime := 0.0
              else
                UserClasses[UserClass].ValueOfTime := VOT[UserClass];
              if Length(CrowdingModel) = 0 then
                UserClasses[UserClass].CrowdingModel := nil
              else
                case CrowdingModel[UserClass] of
                  0: UserClasses[UserClass].CrowdingModel := nil;
                  1: begin
                       Crowding := true;
                       UserClasses[UserClass].CrowdingModel := TWardmanWhelanCrowdingModel.Create(ppCommuting);
                     end;
                  2: begin
                       Crowding := true;
                       UserClasses[UserClass].CrowdingModel := TWardmanWhelanCrowdingModel.Create(ppOther);
                     end
                  else raise Exception.Create('Invalid crowding model');
                end
            end;
            // Set skim-variables
            var ImpedanceSkim := -1;
            if CtlFile.Contains('SKIM',SkimVar) then
            begin
              SkimVariables := TStringParser.Create(Comma,SkimVar).ToStrArray;
              if Length(SkimVariables) > 0 then
              begin
                for var Skim := low(SkimVariables) to high(SkimVariables) do
                if SameText(SkimVariables[Skim],'IMP') then
                begin
                  ImpedanceSkim := Skim;
                  SkimVars := SkimVars + [TImpedanceSkim.Create];
                end else
                if SameText(SkimVariables[Skim],'IWAIT') then SkimVars := SkimVars + [TInitialWaitTimeSkim.Create] else
                if SameText(SkimVariables[Skim],'WAIT') then SkimVars := SkimVars + [TWaitTimeSkim.Create] else
                if SameText(SkimVariables[Skim],'BRD') then SkimVars := SkimVars + [TBoardingsSkim.Create] else
                if SameText(SkimVariables[Skim],'TIM') then SkimVars := SkimVars + [TTimeSkim.Create] else
                if SameText(SkimVariables[Skim],'IVT') then SkimVars := SkimVars + [TInVehicleTimeSkim.Create] else
                if SameText(SkimVariables[Skim],'DST') then SkimVars := SkimVars + [TDistanceSkim.Create] else
                if SameText(SkimVariables[Skim],'IVD') then SkimVars := SkimVars + [TInvehicleDistanceSkim.Create] else
                if SameText(SkimVariables[Skim],'CST') then SkimVars := SkimVars + [TCostSkim.Create] else
                  raise Exception.Create('Unknown skim variable ' + SkimVariables[Skim]);
              end;
            end;
            // Set skim range
            var NSkimVar := Length(SkimVars);
            if NSkimVar > 0 then
            begin
              SetLength(SkimData,NUserClasses);
              if NZones = 0 then
                NSkim := NNodes // Stop to stop skim
              else
                NSkim := NZones // Zone to zone skim
            end else
              NSkim := 0;
            // Create non-transit network
            NonTransitNetwork := TNonTransitNetwork.Create;
            if NonTransitNetwork.UsesLevelOfService then NonTransitNetwork.Initialize(CtlFile.InpProperties('LOS',true));
            if NonTransitNetwork.UsesAsTheCrowFliesDistances then
              NonTransitNetwork.Initialize(Coordinates,
                                           CtlFile.ToFloat('DETOUR',1.0),
                                           CtlFile.ToFloat('SPEED'));
            // Set speed-time-distance input mode
            // Create network
            TransitNetwork := TTransitNetworkTables.Create(Offset);
            Network := TNetwork.Create(TransitNetwork,NonTransitNetwork);
            // Determine number of iterations
            var Converged := CtlFile.ToFloat('CONV',1E-6);
            var MaxIter := CtlFile.ToInt('LOAD',0);
            var LoadNetwork := (MaxIter > 0);
            var FirstImpedanceIter := 0;
            if MaxIter < 256 then
            begin
              if MaxIter > 0 then
              begin
                SetLength(Volumes,NSkim,NSkim);
                if MaxIter > 1 then
                begin
                  SetLength(RoutesCount,NSkim,NSkim);
                  if (ImpedanceSkim >= 0) and Crowding then
                  begin
                    SetLength(ImpedanceCount,NSkim,NSkim);
                    FirstImpedanceIter := MaxIter-CtlFile.ToInt('IMPSKM')+1;
                    if FirstImpedanceIter <= 0 then raise Exception.Create('Invalid IMPSKM-value');
                  end;
                end;
              end else
                if NSkimVar > 0 then MaxIter := 1;
            end else
              raise Exception.Create('Invalid LOAD-value');
            // Prepare for parallel execution
            NThreads := CtlFile.ToInt('NTHREADS',0);
            if NThreads <= 0 then NThreads := TThread.ProcessorCount-NThreads;
            if NThreads < 1 then NThreads := 1;
            SetLength(PathBuilders,NThreads);
            for var Thread := 0 to NThreads-1 do PathBuilders[Thread] := TPathBuilder.Create(Network);
            DestinationsLoop := TParallelFor.Create;
            // Load & Skim network
            var Iter := 0;
            var Convergence := Infinity;
            while (Iter < MaxIter) and (Convergence > Converged) do
            begin
              Inc(Iter);
              for var UserClass := 0 to NUserClasses-1 do
              begin
                Network.Initialize(UserClasses[UserClass]);
                // Allocate skim data
                if (Iter = 1) and (NSkimVar > 0) then SetLength(SkimData[UserClass],NSkim,NSkimVar,NSkim);
                var UserClassSkimData := SkimData[UserClass];
                // Read volumes
                if LoadNetwork then
                begin
                  // Read from file
                  var TripsLabel := 'TRIPS'+(UserClass+1).ToString;
                  if Iter = 1 then
                    VolumesReader := MatrixFormats.CreateReader(CtlFile.InpProperties(TripsLabel))
                  else
                    // Log input file only once
                    VolumesReader := MatrixFormats.CreateReader(CtlFile[TripsLabel]);
                  try
                    for var Node := 0 to NSkim-1 do VolumesReader.Read(Volumes[Node]);
                  finally
                    VolumesReader.Free;
                  end;
                  // Transpose volumes
                  for var Origin := 0 to NSkim-1 do
                  for var Destination := Origin+1 to NSkim-1do
                  begin
                    var XChange := Volumes[Origin,Destination];
                    Volumes[Origin,Destination] := Volumes[Destination,Origin];
                    Volumes[Destination,Origin] := XChange;
                  end;
                end;
                // Iterate destinations
                DestinationsLoop.Execute(NThreads,0,NSkim-1,
                   Procedure(Destination,Thread: Integer)
                   begin
                      PathBuilders[Thread].BuildPaths(Destination);
                      PathBuilders[Thread].TopologicalSort;
                      if MaxIter > 0 then
                      begin
                        if (UserClass = 0) and (MaxIter > 1) then
                        begin
                          PathBuilders[Thread].UpdateRoutesCountCount(RoutesCount[Destination]);
                          if (FirstImpedanceIter > 0) and (Iter >= FirstImpedanceIter) then
                          PathBuilders[Thread].UpdateRoutesCountCount(ImpedanceCount[Destination]);
                        end;
                        if LoadNetwork then PathBuilders[Thread].Assign(Volumes[Destination]);
                      end;
                      if NSkimVar > 0 then
                      if FirstImpedanceIter = 0 then
                        for var SkimVar := low(SkimVars) to high(SkimVars) do
                        begin
                          if Iter = 1 then
                            PathBuilders[Thread].Skim(NSkim-1,SkimVars[SkimVar],UserClassSkimData[Destination,SkimVar])
                          else
                            PathBuilders[Thread].Skim(NSkim-1,RoutesCount[Destination],SkimVars[SkimVar],UserClassSkimData[Destination,SkimVar])
                        end
                      else
                        for var SkimVar := low(SkimVars) to high(SkimVars) do
                        begin
                          if SkimVar = ImpedanceSkim then
                          begin
                            if Iter = FirstImpedanceIter then
                              PathBuilders[Thread].Skim(NSkim-1,SkimVars[SkimVar],UserClassSkimData[Destination,SkimVar])
                            else
                              if Iter > FirstImpedanceIter then
                              PathBuilders[Thread].Skim(NSkim-1,ImpedanceCount[Destination],SkimVars[SkimVar],UserClassSkimData[Destination,SkimVar])
                          end else
                          begin
                            if Iter = 1 then
                              PathBuilders[Thread].Skim(NSkim-1,SkimVars[SkimVar],UserClassSkimData[Destination,SkimVar])
                            else
                              PathBuilders[Thread].Skim(NSkim-1,RoutesCount[Destination],SkimVars[SkimVar],UserClassSkimData[Destination,SkimVar])
                          end;
                        end
                   end);
                // Copy volumes to network
                if LoadNetwork then
                begin
                  var MixFactor := 1/Iter;
                  for var Thread := 0 to NThreads-1 do PathBuilders[Thread].PushVolumesToNetwork;
                  Network.MixVolumes(UserClass,MixFactor);
                end;
                // Write skim data
                if (NSkimVar > 0) and ((Iter = MaxIter) or (Convergence <= Converged)) then
                begin
                  SkimRows := nil;
                  SkimWriter := nil;
                  var SkimLabel := 'SKIM'+(UserClass+1).ToString;
                  try
                    if CtlFile.ToBool('TRNSP','0','1',false) then
                    begin
                      SetLength(SkimVariables,2*NSkimVar);
                      SetLength(SkimRows,2*NSkimVar);
                      for var Skim := 0 to NSkimVar-1 do
                      begin
                        SkimVariables[Skim+NSkimVar] := SkimVariables[Skim] + '_tr';
                        SkimRows[Skim].Length := NSkim;
                      end;
                      SkimWriter := MatrixFormats.CreateWriter(CtlFile.OutpProperties(SkimLabel),SkimLabel,SkimVariables,NSkim);
                      for var Origin := 0 to NSkim-1 do
                      begin
                        for var Skim := 0 to NSkimVar-1 do
                        begin
                          SkimRows[NSkimVar+Skim] := UserClassSkimData[Origin][Skim];
                          for var Destination := 0 to NSkim-1 do
                          SkimRows[Skim,Destination] := UserClassSkimData[Destination][Skim,Origin];
                        end;
                        SkimWriter.Write(SkimRows);
                      end;
                    end else
                    begin
                      SetLength(SkimRows,NSkimVar,NSkim);
                      SkimWriter := MatrixFormats.CreateWriter(CtlFile.OutpProperties(SkimLabel),SkimLabel,SkimVariables,NSkim);
                      for var Origin := 0 to NSkim-1 do
                      begin
                        for var Skim := 0 to NSkimVar-1 do
                        for var Destination := 0 to NSkim-1 do
                        SkimRows[Skim,Destination] := UserClassSkimData[Destination][Skim,Origin];
                        SkimWriter.Write(SkimRows);
                      end;
                    end;
                  finally
                    SkimWriter.Free;
                    Finalize(SkimData[UserClass]);
                  end;
                end;
              end;
              // Load transit lines
              TransitNetwork.ResetVolumes;
              Network.PushVolumesToLines;
              // Calculate convergence
              Convergence := TransitNetwork.Convergence;
              if (LogFile <> nil) and (MaxIter > 1) then
              LogFile.Log('Convergence iteration ' + Iter.ToString + ': ' + FormatFloat('0.0000',Convergence));
            end;
            // Save output tables
            if LoadNetwork then
            begin
              TransitNetwork.SaveBoardingsTable;
              TransitNetwork.SaveVolumesTable;
            end;
          end else
            raise Exception.Create('Invalid value NNodes or NZones');
        except
          on E: Exception do
          begin
            ExitCode := 1;
            if LogFile <> nil then
            begin
              LogFile.Log;
              Logfile.Log(E)
            end else
              writeln('ERROR: ' + E.Message);
          end;
        end;
      finally
        for var Thread := low(PathBuilders) to high(PathBuilders) do PathBuilders[Thread].Free;
        DestinationsLoop.Free;
        Coordinates.Free;
        NonTransitNetwork.Free;
        TransitNetwork.Free;
        Network.Free;
        LogFile.Free;
      end;
    end
  end else
    writeln('Usage: ',ExtractFileName(ParamStr(0)),' "<control-file-name>"');
end;

////////////////////////////////////////////////////////////////////////////////

begin
  var Skim := TPTSkim.Create;
  try
    Skim.Execute;
  finally
    Skim.Free;
  end
end.
