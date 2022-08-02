unit Network.Coord;

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
  SysUtils,Types,Parse,TxtTab,Globals;

Type
  TCoordinates = Class
  private
    FCount,FZoneCount,Offset: Integer;
    FZoneCoordinates,FStopCoordinates: Boolean;
    FCoordinates: TArray<TPointF>;
    Function GetCoordinates(Node: Integer): TPointF; inline;
    Procedure ReadCoordinates(const FileName: String; StopOffset: Integer);
  public
    Constructor Create(const ZoneCoordinates: String); overload;
    Constructor Create(const StopCoordinates: String; NZones,StopOffset: Integer); overload;
    Constructor Create(const ZoneCoordinates,StopCoordinates: String; StopOffset: Integer); overload;
  public
    Property Count: Integer read FCount;
    Property ZoneCount: Integer read FZoneCount;
    Property ZoneCoordinates: Boolean read FZoneCoordinates;
    Property StopCoordinates: Boolean read FStopCoordinates;
    Property Coordinates[Node: Integer]: TPointF read GetCoordinates; default;
  end;

////////////////////////////////////////////////////////////////////////////////
implementation
////////////////////////////////////////////////////////////////////////////////

Constructor TCoordinates.Create(const ZoneCoordinates: String);
begin
  inherited Create;
  // Read zone coordinates
  FZoneCoordinates := true;
  ReadCoordinates(ZoneCoordinates,0);
  FZoneCount := FCount;
end;

Constructor TCoordinates.Create(const StopCoordinates: String; NZones,StopOffset: Integer);
begin
  inherited Create;
  // Read stop coordinates
  FCount := NZones;
  FZoneCount := NZones;
  Offset := NZones;
  FStopCoordinates := true;
  ReadCoordinates(StopCoordinates,StopOffset);
end;

Constructor TCoordinates.Create(const ZoneCoordinates,StopCoordinates: String; StopOffset: Integer);
begin
  inherited Create;
  // Read zone coordinates
  FZoneCoordinates := true;
  ReadCoordinates(ZoneCoordinates,0);
  FZoneCount := FCount;
  // Read stop coordinates
  FStopCoordinates := true;
  ReadCoordinates(StopCoordinates,StopOffset);
end;

Function TCoordinates.GetCoordinates(Node: Integer): TPointF;
begin
  Result := FCoordinates[Node];
end;

Procedure TCoordinates.ReadCoordinates(const FileName: String; StopOffset: Integer);
begin
  var Reader := TTextTableReader.Create(FileName);
  try
    // Set field indices
    var NodeFieldIndex := Reader.IndexOf(NodeFieldName,true);
    var XCoordFieldIndex := Reader.IndexOf(XCoordFieldName,true);
    var YCoordFieldIndex := Reader.IndexOf(YCoordFieldName,true);
    // Read lines
    while Reader.ReadLine do
    begin
      var Node := Reader[NodeFieldIndex].ToInt-StopOffset-1;
      if Node = FCount then
      begin
        if Length(FCoordinates) <= FCount-Offset then SetLength(FCoordinates,FCount-Offset+512);
        FCoordinates[FCount-Offset].X := Reader[1];
        FCoordinates[FCount-Offset].Y := Reader[2];
        Inc(FCount);
      end else
        raise Exception.Create('Error reading coordinates "' + FileName + '" at line ' + Reader.LineCount.ToString)
    end;
  finally
    Reader.Free;
  end;
end;

end.
