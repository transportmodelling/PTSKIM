NNODES: 4
NCLASS: 2
STD: T
LOAD: 100
IMPSKM: 10
CROWD: 1,2
SKIM: TIM,IVT,IWAIT,WAIT,IMP
LINES: .\input\lines.dat
STOPS: .\input\stops.dat
SEGMENTS: .\input\segments.dat
TRIPS1: file=.\input\trips1.dat; format=txt; delim=tab
TRIPS2: file=.\input\trips2.dat; format=txt; delim=tab
SKIM1: file=.\output\Crowding-skim1.dat; format=txt; decimals=3
SKIM2: file=.\output\Crowding-skim2.dat; format=txt; decimals=3
BOARDS: .\output\boardings.dat
VOLUMES: .\output\volumes.dat
LOG: .\output\Crowding.log
