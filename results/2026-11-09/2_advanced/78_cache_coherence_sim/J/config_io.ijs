decimal_integer =: 3 : 0
    if. 0=#y do.
        0 return.
    end.
    if. -.*./y e.'0123456789' do.
        0 return.
    end.
    (1=#y)+.'0'~:{.y
)
valid_hex_address =: 3 : '(8=#y)*.*./y e.''0123456789abcdef'''
hex_value =: 3 : '16#.(''0123456789abcdef''i.y)'
hex_address =: 3 : '''0123456789abcdef''{~(8#16)#:y'
read_lines =: 3 : '<;._2 (1!:1 <y)'
split_words =: 3 : '<;._1 '' '',y'
read_config =: 3 : 0
    Scenarios =: 0$a:
    RegionNames =: 0$a:
    RegionStarts =: i.0
    RegionEnds =: i.0
    WatchBlocks =: i.0
    for_line. read_lines 'input/config.txt' do.
        fields =. split_words >line
        kind =. 0{::fields
        values =. }.fields
        select. kind
        case. 'CORES' do. NumberCores =: ".0{::values
        case. 'LINE' do. LineSize =: ".0{::values
        case. 'L1' do. 'L1Size L1Ways' =: ".' 'join values
        case. 'L2' do. 'L2Size L2Ways' =: ".' 'join values
        case. 'LATENCY' do. 'T1 T2 TM TB' =: ".' 'join values
        case. 'SCENARIO' do. Scenarios =: Scenarios,<values
        case. 'PRIMARY' do. PrimaryName =: 0{::values
        case. 'INTERVAL' do. IntervalWidth =: ".0{::values
        case. 'TOP' do. Top =: ".0{::values
        case. 'REGION' do.
            RegionNames =: RegionNames,0{values
            RegionStarts =: RegionStarts,hex_value 1{::values
            RegionEnds =: RegionEnds,hex_value 2{::values
        case. 'WATCH' do.
            WatchBlocks =: WatchBlocks,(hex_value 0{::values)intdiv LineSize
        end.
    end.
    L1Sets =: L1Size intdiv LineSize*L1Ways
    L2Sets =: L2Size intdiv LineSize*L2Ways
    CacheCapacity =: L1Sets*L1Ways
    WordsPerLine =: LineSize intdiv 4
    TraceLines =: read_lines 'input/trace.txt'
)
write_lines =: 4 : 0
    text =. ''
    if. #y do.
        text =. (LF join y),LF
    end.
    text 1!:2 <'output/',x
)
