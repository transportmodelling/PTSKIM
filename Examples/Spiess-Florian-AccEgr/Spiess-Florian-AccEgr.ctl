NZONES: 2
NNODES: 6
NCLASS: 1
OFFSET: -2
TOD: 1
LOAD: 1
ACCEGR: 1
SKIM: TIM,IVT,DST,CST,IWAIT,WAIT,IMP
LINES: .\input\Spiess-Florian.lin
LOS: file=.\input\walk-los.dat; format=txt; delim=space
TRIPS1: file=.\input\trips.dat; format=txt; delim=space
SKIM1: file=.\output\Spiess-Florian-AccEgr-skim.dat; format=txt; decimals=3
LOADS: .\output\Spiess-Florian-AccEgr.vol
LOG: output\Spiess-Florian-AccEgr.log
