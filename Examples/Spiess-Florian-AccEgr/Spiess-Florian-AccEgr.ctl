NZONES: 2
NNODES: 6
NCLASS: 1
OFFSET: -2
STD: T
LOAD: 1
SKIM: TIM,IVT,IWAIT,WAIT,IMP
LINES: .\input\lines.dat
STOPS: .\input\stops.dat
SEGMENTS: .\input\segments.dat
LOS: file=.\input\walk-los.dat; format=txt; delim=tab
TRIPS1: file=.\input\trips.dat; format=txt; delim=tab
SKIM1: file=.\output\Spiess-Florian-AccEgr-skim.dat; format=txt; decimals=3
BOARDS: .\output\boardings.dat
VOLUMES: .\output\volumes.dat
LOG: output\Spiess-Florian-AccEgr.log
