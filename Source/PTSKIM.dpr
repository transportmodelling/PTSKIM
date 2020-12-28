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
  Parse,
  PropSet,
  matio,
  matio.Formats,
  matio.Text,
  Polynom in 'Polynom.pas',
  Spline in 'Spline.pas',
  PFL in 'PFL.pas',
  Log in 'Log.pas',
  Globals in 'Globals.pas',
  Connection in 'Connection.pas',
  Network in 'Network.pas',
  Network.Transit in 'Network.Transit.pas',
  Network.Transit.IniFile in 'Network.Transit.IniFile.pas',
  Network.NonTransit in 'Network.NonTransit.pas',
  PathBld in 'PathBld.pas',
  SkimVar in 'SkimVar.pas',
  LineChoi in 'LineChoi.pas',
  LineChoi.Gentile in 'LineChoi.Gentile.pas';

Type
  TPTSkim = Class
  public
    Procedure Execute(ControlFileName: String);
  end;

Procedure TPTSkim.Execute(ControlFileName: String);
Var
  ControlFile: TPropertySet;
  LogFile: TLogFile;
  UserClasses: array of TuserClass;
  NonTransitNetwork: TNonTransitNetwork;
  TransitNetwork: TLinesIniFile;
  Network: TNetwork;
  PathBuilders: array of TPathBuilder;
  DestinationsLoop: TParallelFor;
  SkimVar: String;
  NThreads,NSkim: Integer;
  SkimVariables: TArray<String>;
  SkimVars: array of TSkimVar;
  Volumes: array of TFloat32MatrixRow;
  SkimRows: TFloat32MatrixRows;
  SkimData: array of TFloat32MatrixRows;
  VolumesReader: TMatrixReader;
  SkimWriter: TMatrixWriter;
begin
  LogFile := nil;
  NonTransitNetwork := nil;
  TransitNetwork := nil;
  Network := nil;
  DestinationsLoop := nil;
  try
    try
      ControlFile.NameValueSeparator := ':';
      ControlFile.PropertiesSeparator := ';';
      ControlFile.AsStrings := TFile.ReadAllLines(ControlFileName);
      // Create log file
      var LogFileName := ControlFile.ToFileName('LOG',false);
      if LogFileName <> '' then
      begin
        LogFile := TLogFile.Create(LogFileName);
        LogFile.Log('Control file',ControlFileName);
      end;
      // Set parameters
      NZones := ControlFile.ToInt('NZONES',0);
      NNodes := ControlFile.ToInt('NNODES');
      NUserClasses := ControlFile.ToInt('NCLASS');
      if (NZones >= 0) and (NNodes > NZones) then
      begin
        var Offset := ControlFile.ToInt('OFFSET',0);
        var TimeOfDay := ControlFile.ToInt('TOD')-1;
        var Load := ControlFile.ToInt('LOAD',0);
        // Set userclasses
        SetLength(UserClasses,NUserClasses);
        var VOT := ControlFile.Parse('VOT',Comma).ToFloatArray;
        var BoardingPenalty := ControlFile.Parse('PENALTY',Comma).ToFloatArray;
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
        end;
        // Set skim-variables
        if ControlFile.Contains('SKIM',SkimVar) then
        begin
          SkimVariables := TStringParser.Create(Comma,SkimVar).ToStrArray;
          if Length(SkimVariables) > 0 then
          begin
            for var Skim := low(SkimVariables) to high(SkimVariables) do
            if SameText(SkimVariables[Skim],'IMP') then SkimVars := SkimVars + [TImpedanceSkim.Create] else
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
        var NSkimVar := Length(SkimVars);
        // Create non-transit network
        NonTransitNetwork := TNonTransitNetwork.Create(ControlFile.ToFloat('ACCDST',Infinity),
                                                       ControlFile.ToFloat('TRFDST',Infinity),
                                                       ControlFile.ToFloat('EGRDST',Infinity),
                                                       ControlFile.ToBool('AECROW','0','1',false),
                                                       ControlFile.ToBool('TRFCROW','0','1',false));
        if NonTransitNetwork.UsesLevelOfService then NonTransitNetwork.Initialize(ControlFile['LOS']);
        if NonTransitNetwork.UsesAsTheCrowFliesDistances then
          NonTransitNetwork.Initialize(ControlFile.ToFileName('COORD',true),
                                       ControlFile.ToFloat('DETOUR',1.0),
                                       CONTROLFile.ToFloat('SPEED'));
        // Create network
        TransitNetwork := TLinesIniFile.Create(ControlFile.ToFileName('LINES',true),Offset);
        Network := TNetwork.Create(TimeOfDay,TransitNetwork,NonTransitNetwork);
        // Prepare for parallel execution
        NThreads := ControlFile.ToInt('NTHREADS',0);
        if NThreads <= 0 then NThreads := TThread.ProcessorCount-NThreads;
        if NThreads < 1 then NThreads := 1;
        SetLength(PathBuilders,NThreads);
        for var Thread := 0 to NThreads-1 do PathBuilders[Thread] := TPathBuilder.Create(Network);
        DestinationsLoop := TParallelFor.Create;
        // Load & Skim network
        if (Load > 0) or (NSkimVar > 0) then
        begin
          if NZones = 0 then
            NSkim := NNodes  // Stop to stop assignment
          else
            NSkim := NZones; // Zone to zone assignment
          if Load > 0 then SetLength(Volumes,NSkim,NSkim);
          if NSkimVar > 0 then
          begin
            SetLength(SkimData,NSkim);
            for var Node := 0 to NSkim-1 do SkimData[Node] := TFloat32MatrixRows.Create(Length(SkimVars),NSkim);
          end;
          for var UserClass := 0 to NUserClasses-1 do
          begin
            Network.Initialize(UserClasses[UserClass]);
            // Read volumes
            if Load > 0 then
            begin
              // Read from file
              var TripsLabel := ControlFile['TRIPS'+(UserClass+1).ToString];
              VolumesReader := MatrixFormats.CreateReader(TripsLabel);
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
                  PathBuilders[Thread].TopoligicalSort;
                  if Load > 0 then PathBuilders[Thread].Assign(Volumes[Destination]);
                  if NSkimVar > 0 then PathBuilders[Thread].Skim(0,NSkim-1,SkimVars,SkimData[Destination]);
               end);
            // Write skim data
            if NSkimVar > 0 then
            begin
              SkimRows := nil;
              SkimWriter := nil;
              var SkimLabel := 'SKIM'+(UserClass+1).ToString;
              try
                if ControlFile.ToBool('TRNSP','0','1',false) then
                begin
                  SetLength(SkimVariables,2*NSkimVar);
                  for var Skim := 0 to NSkimVar-1 do SkimVariables[Skim+NSkimVar] := SkimVariables[Skim] + '_tr';
                  SkimRows := TFloat32MatrixRows.Create(2*NSkimVar,NSkim);
                  SkimWriter := MatrixFormats.CreateWriter(ControlFile[SkimLabel],SkimLabel,SkimVariables,NSkim);
                  for var Origin := 0 to NSkim-1 do
                  begin
                    for var Skim := 0 to NSkimVar-1 do
                    for var Destination := 0 to NSkim-1 do
                    begin
                      SkimRows[Skim,Destination] := SkimData[Destination][Skim,Origin];
                      SkimRows[Skim+NSkimVar,Destination] := SkimData[Origin][Skim,Destination];
                    end;
                    SkimWriter.Write(SkimRows);
                  end;
                end else
                begin
                  SkimRows := TFloat32MatrixRows.Create(NSkimVar,NSkim);
                  SkimWriter := MatrixFormats.CreateWriter(ControlFile[SkimLabel],SkimLabel,SkimVariables,NSkim);
                  for var Origin := 0 to NSkim-1 do
                  begin
                    for var Skim := 0 to NSkimVar-1 do
                    for var Destination := 0 to NSkim-1 do SkimRows[Skim,Destination] := SkimData[Destination][Skim,Origin];
                    SkimWriter.Write(SkimRows);
                  end;
                end;
              finally
                SkimRows.Free;
                SkimWriter.Free;
              end;
            end;
            // Copy volumes to network
            if Load > 0 then
            for var Thread := 0 to NThreads-1 do PathBuilders[Thread].PushVolumes(UserClass);
          end;
          // Save network volumes
          if Load > 0 then
          begin
            var FileName := ControlFile.ToFileName('LOADS',false);
            Network.PushVolumes;
            TransitNetwork.SaveVolumes(FileName);
          end;
        end
      end else
        raise Exception.Create('Invalid value NNodes or NZones');
    except
      on E: Exception do
      begin
        ExitCode := 1;
        if LogFile <> nil then
          LogFile.Log(E)
        else
          writeln(E.Message);
      end;
    end;
  finally
    for var Node := low(SkimData) to high(SkimData) do SkimData[Node].Free;
    for var Thread := low(PathBuilders) to high(PathBuilders) do PathBuilders[Thread].Free;
    DestinationsLoop.Free;
    LogFile.Free;
    NonTransitNetwork.Free;
    TransitNetwork.Free;
    Network.Free;
  end
end;

////////////////////////////////////////////////////////////////////////////////

begin
  if ParamCount > 0 then
  begin
    var ControlFileName := ExpandFileName(ParamStr(1));
    if FileExists(ControlFileName) then
    begin
      var BaseDir := IncludeTrailingPathDelimiter(ExtractFileDir(ControlFileName));
      FormatSettings.DecimalSeparator := '.';
      // All relative paths are supposed to be relative to the control file path!
      TPropertySet.BaseDirectory := BaseDir;
      TTextMatrixWriter.RowLabel := 'Orig';
      TTextMatrixWriter.ColumnLabel := 'Dest';
      var Skim := TPTSkim.Create;
      try
        Skim.Execute(ControlFileName);
      finally
        Skim.Free;
      end
    end else
      writeln('Control file does not exist');
  end else
    writeln('Usage PTSKIM <control file>');
end.
