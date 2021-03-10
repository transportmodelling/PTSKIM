NNODES: 4
NCLASS: 2
TOD: 1
LOAD: 100
IMPSKM: 10
CROWD: 1,2
SKIM: TIM,IVT,DST,CST,IWAIT,WAIT,IMP
LINES: input\Crowding.lin
TRIPS1: file=input\trips1.dat; format=txt; delim=space
TRIPS2: file=input\trips2.dat; format=txt; delim=space
SKIM1: file=output\Crowding-skim1.dat; format=txt; decimals=3
SKIM2: file=output\Crowding-skim2.dat; format=txt; decimals=3
LOADS: output\Crowding.vol
LOG: output\Crowding.log
