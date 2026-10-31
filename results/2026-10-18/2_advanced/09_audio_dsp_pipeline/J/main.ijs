ScriptPath =: >{:4!:3''
SourceDirectory =: (1+>./_1,I.ScriptPath e.'/\'){.ScriptPath
Digits =: '0123456789'
Lowercase =: 'abcdefghijklmnopqrstuvwxyz'
div =: 4 : '_1 x:<.(x:x)%x:y'
num =: 3 : '10#.Digits i.y'
signed_num =: 3 : 0
    if. '-'={.y do. -num }.y else. num y end.
)
number =: 3 : 0
    if. y<0 do. '-',number -y return. end.
    text =. ''
    while. y>0 do.
        text =. ((10|y){Digits),text
        y =. y div 10
    end.
    if. #text do. text else. '0' end.
)
split =: 4 : 0
    parts =. 0$a:
    while. 1 do.
        position =. y i.x
        parts =. parts,<position{.y
        if. position=#y do. parts return. end.
        y =. (position+1)}.y
    end.
)
join =: 4 : 0
    text =. ''
    for_index. i.#y do.
        if. index do. text =. text,x end.
        text =. text,index{::y
    end.
    text
)
read_lines =: 3 : '<;._2 (1!:1 <''input/'',y)'
empty_table =: 3 : '0 2$a:'
table_keys =: 3 : '0{"1 y'
has_key =: 4 : '(<x)e.table_keys y'
get_key =: 4 : '((table_keys y)i.<x){::1{"1 y'
put_key =: 4 : 0
    'key value' =. x
    position =. (table_keys y)i.<key
    if. position<#y do. (<value) (<position,1)}y
    else. y,1 2$(<key),<value end.
)
record =: 4 : '('' '' split x),.y'
load SourceDirectory,'signals.ijs'
load SourceDirectory,'effects.ijs'
load SourceDirectory,'filters.ijs'
load SourceDirectory,'dynamics.ijs'
load SourceDirectory,'analysis.ijs'
kv =: 4 : 'x,''='',number y'
ceil_divide =: 4 : '-(-x) div y'
milliseconds =: 4 : '(1000*x) div y'
two_decimals =: 3 : '(number y div 100),''.'',_2{.''00'',number 100|y'
frequency_text =: 4 : 'two_decimals (100*x) rdiv y'
right_pad =: 4 : '((0>.x-#y)#'' ''),y'
text_line =: 3 : 0
    fields =. 0$a:
    for_box. y do.
        value =. >box
        if. 2~:3!:0 value do. value =. number value end.
        fields =. fields,<value
    end.
    ' ' join fields
)
bad =: 3 : 0
    CommandError =: y
    ''
)
argument_specs =: 3 : 0
    arguments =. 0$a:
    if. 0=#y do. arguments return. end.
    for_box. ' ' split y do.
        fields =. ':' split >box
        name =. 0{::fields
        if. (<name)e.'dst';'var' do. kind =. 'name'
        elseif. name-:'src' do. kind =. 'signal'
        elseif. name-:'metric' do. kind =. 'metric'
        elseif. name-:'op' do. kind =. 'operator'
        else. kind =. 'integer' end.
        low =. high =. ''
        if. 3=#fields do. low =. 1{::fields
            high =. 2{::fields end.
        arguments =. arguments,<'name kind low high' record (<name),(<kind),(<low),<high
    end.
    arguments
)
define_command =: 3 : 0
    'name fixed repeated minimum maximum' =. y
    command =. 'fixed repeated minimum maximum' record (<argument_specs fixed),(<argument_specs repeated),(<minimum),<maximum
    Commands =: ((<name),<command) put_key Commands
    i.0
)
command_table =: 3 : 0
    Commands =: empty_table ''
    define_command (<'SET'),(<'var value:-10000000:10000000'),(<'op operand:-10000000:10000000'),(<0),<1
    for_namebox. 'IMPULSE';'STEP' do. define_command namebox,(<'dst rate:1000:48000 count:1:20000 pos:0:count-1 amp:-32768:32767'),(<''),(<0),<0 end.
    define_command (<'NOISE'),(<'dst rate:1000:48000 count:1:20000 seed:1:2147483646'),(<''),(<0),<0
    define_command (<'GAIN'),(<'dst src num:-65536:65536 den:1:65536'),(<''),(<0),<0
    define_command (<'MIX'),(<'dst den:1:65536'),(<'src weight:-65536:65536'),(<1),<8
    define_command (<'DELAY'),(<'dst src samples:0:20000'),(<''),(<0),<0
    define_command (<'ECHO'),(<'dst src delay:1:20000 num:-65536:65536 den:1:65536 tail:0:20000'),(<''),(<0),<0
    define_command (<'RESAMPLE'),(<'dst src new_rate:1000:48000'),(<''),(<0),<0
    define_command (<'FADE'),(<'dst src in:0:L out:0:L'),(<''),(<0),<0
    define_command (<'TRIM'),(<'dst src start:0:L-1 count:1:L-start'),(<''),(<0),<0
    define_command (<'CONCAT'),(<'dst'),(<'src'),(<2),<8
    define_command (<'FIR'),(<'dst src divisor:1:1000000'),(<'tap:-32768:32767'),(<1),<64
    define_command (<'BIQUAD'),(<'dst src'),(<'b0:-65536:65536 b1:-65536:65536 b2:-65536:65536 a1:-65536:65536 a2:-65536:65536'),(<1),<4
    define_command (<'MOVAVG'),(<'dst src width:1:1000'),(<''),(<0),<0
    define_command (<'DCBLOCK'),(<'dst src num:0:65535 den:num+1:65536'),(<''),(<0),<0
    define_command (<'NORMALIZE'),(<'dst src target:1:32767'),(<''),(<0),<0
    define_command (<'GATE'),(<'dst src threshold:1:32768 hold:0:20000'),(<''),(<0),<0
    define_command (<'ENVELOPE'),(<'dst src attack:1:32768 release:1:32768'),(<''),(<0),<0
    define_command (<'COMPRESS'),(<'dst src threshold:1:32767 ratio_num:1:100 ratio_den:1:ratio_num attack:1:32768 release:1:32768'),(<''),(<0),<0
    define_command (<'ANALYZE'),(<'src min_hz:1:rate/2-1 max_hz:min_hz+1:rate/2'),(<''),(<0),<0
    define_command (<'COMPARE'),(<'src src'),(<''),(<0),<0
    define_command (<'EXPECT'),(<'src metric op value:-1000000000:1000000000'),(<''),(<0),<0
    define_command (<'SEGMENTS'),(<'src threshold:1:32768 gap:1:20000 min_length:1:20000'),(<''),(<0),<0
    define_command (<'ONSETS'),(<'src attack:1:32768 release:1:32768 threshold:1:32767 min_gap:1:20000'),(<''),(<0),<0
    define_command (<'PITCHTRACK'),(<'src frame:16:L hop:1:frame min_hz:1:rate/2-1 max_hz:min_hz+1:rate/2 threshold:0:32767'),(<''),(<0),<0
    define_command (<'EXCERPT'),(<'src start:0:L-1 count:1:1000'),(<''),(<0),<0
    define_command (<'PLOT'),(<'src start:0:L-1 count:1:L-start columns:8:min(120,count) half:2:20 attack:1:32768 release:1:32768'),(<''),(<0),<0
    define_command (<'METER'),(<'src block:1:20000'),(<''),(<0),<0
    define_command (<'HISTOGRAM'),(<'src bins:2:64'),(<''),(<0),<0
    for_namebox. 'TRACE';'SAVE' do. define_command namebox,(<'src'),(<''),(<0),<0 end.
    i.0
)
GeneratorNames =: ' ' split 'IMPULSE STEP NOISE GAIN MIX DELAY ECHO RESAMPLE FADE TRIM CONCAT FIR BIQUAD MOVAVG DCBLOCK NORMALIZE GATE ENVELOPE COMPRESS'
MetricNames =: ' ' split 'samples peak rms sum zero_crossings clipped'
valid_name =: 3 : 0
    if. (0=#y)+.(#y)>16 do. 0 return. end.
    (({.y)e.Lowercase)*.*./(}.y)e.Lowercase,Digits,'_'
)
valid_integer =: 3 : 0
    if. y-:'-0' do. 0 return. end.
    if. '-'={.y do. y =. }.y end.
    if. (0=#y)+.(#y)>10 do. 0 return. end.
    if. ((#y)>1)*.'0'={.y do. 0 return. end.
    *./y e.Digits
)
resolve_bound =: 3 : 0
    'bound known source' =. y
    if. ({.bound)e.Digits,'-' do. signed_num bound return. end.
    select. bound
    case. 'count-1' do. ('count' get_key known)-1
    case. 'min(120,count)' do. 120<.'count' get_key known
    case. 'min_hz+1' do. 1+'min_hz' get_key known
    case. 'num+1' do. 1+'num' get_key known
    case. 'L' do. #'samples' get_key source
    case. 'L-1' do. <:#'samples' get_key source
    case. 'L-start' do. (#'samples' get_key source)-'start' get_key known
    case. 'rate/2' do. ('rate' get_key source) div 2
    case. 'rate/2-1' do. <:('rate' get_key source) div 2
    case. do. bound get_key known
    end.
)
parse_arguments =: 4 : 0
    if. -.x has_key Commands do. bad 'unknown command ',x return. end.
    command =. x get_key Commands
    fixed =. 'fixed' get_key command
    repeated =. 'repeated' get_key command
    extra =. (#y)-#fixed
    if. #repeated do.
        if. (extra<('minimum' get_key command)*#repeated)+.(extra>('maximum' get_key command)*#repeated)+.0~:(#repeated)|extra do. bad 'wrong number of arguments' return. end.
    elseif. extra~:0 do. bad 'wrong number of arguments' return. end.
    values =. sources =. 0$a:
    known =. empty_table ''
    for_index. i.#y do.
        if. index<#fixed do. descriptor =. index{::fixed else. descriptor =. ((#repeated)|(index-#fixed)){::repeated end.
        name =. 'name' get_key descriptor
        kind =. 'kind' get_key descriptor
        token =. index{::y
        select. kind
        case. 'name' do.
            if. -.valid_name token do. bad 'bad name ',token return. end.
            value =. token
        case. 'signal' do.
            if. -.token has_key Signals do. bad 'unknown signal ',token return. end.
            value =. token get_key Signals
            sources =. sources,<value
        case. 'metric' do.
            if. -. (<token)e.MetricNames do. bad 'unknown metric ',token return. end.
            value =. token
        case. 'operator' do.
            if. x-:'SET' do. operators =. '+';'-';'*';'/' else. operators =. ' ' split 'eq ne lt le gt ge' end.
            if. -. (<token)e.operators do. bad 'unknown operator ',token return. end.
            value =. token
        case. 'integer' do.
            if. '$'={.token do.
                if. -. (}.token) has_key Variables do. bad 'undefined variable ',token return. end.
                value =. (}.token) get_key Variables
            else.
                if. -.valid_integer token do. bad 'bad integer ',token return. end.
                value =. signed_num token
            end.
            source =. empty_table ''
            if. #sources do. source =. 0{::sources end.
            low =. resolve_bound (<'low' get_key descriptor),(<known),<source
            high =. resolve_bound (<'high' get_key descriptor),(<known),<source
            if. (value<low)+.value>high do. bad name,' out of range' return. end.
            known =. ((<name),<value) put_key known
        end.
        values =. values,<value
    end.
    (<values),<sources
)
require_same_rate =: 3 : 0
    rate =. 'rate' get_key 0{::y
    for_box. y do. if. rate~:'rate' get_key >box do. bad 'rate mismatch' return. end. end.
    i.0
)
generate_signal =: 3 : 0
    'linenumber name values sources' =. y
    dst =. 0{::values
    args =. }.values
    extras =. empty_table ''
    if. (<name)e.'IMPULSE';'STEP';'NOISE' do.
        rate =. 0{::args
        select. name
        case. 'IMPULSE' do. samples =. impulse >}.args
        case. 'STEP' do. samples =. step_signal >}.args
        case. 'NOISE' do. samples =. noise >}.args
        end.
    else.
        source =. 0{::sources
        samples =. 'samples' get_key source
        rate =. 'rate' get_key source
        result =. empty_table ''
        select. name
        case. 'GAIN' do. result =. gain (<samples),}.args
        case. 'MIX' do.
            require_same_rate sources
            if. #CommandError do. '' return. end.
            tracks =. 0$a:
            for_box. sources do. tracks =. tracks,<'samples' get_key >box end.
            weights =. >(2+2*i.#sources){args
            result =. mix (<tracks),(<weights),0{args
        case. 'DELAY' do.
            count =. 1{::args
            if. ((#samples)+count)>20000 do. bad 'result too long' return. end.
            samples =. samples delay_signal count
        case. 'ECHO' do.
            if. (|2{::args)>:3{::args do. bad 'unstable feedback' return. end.
            if. ((#samples)+4{::args)>20000 do. bad 'result too long' return. end.
            result =. echo (<samples),}.args
        case. 'RESAMPLE' do.
            newrate =. 1{::args
            if. (resampled_length (#samples),rate,newrate)>20000 do. bad 'result too long' return. end.
            samples =. resample (<samples),(<rate),<newrate
            rate =. newrate
        case. 'FADE' do. samples =. fade (<samples),}.args
        case. 'TRIM' do. samples =. (2{::args){.(1{::args)}.samples
        case. 'CONCAT' do.
            require_same_rate sources
            if. #CommandError do. '' return. end.
            tracks =. 0$a:
            for_box. sources do. tracks =. tracks,<'samples' get_key >box end.
            if. (+/#&>tracks)>20000 do. bad 'result too long' return. end.
            samples =. ;tracks
        case. 'FIR' do. result =. fir (<samples),(1{args),<>2}.args
        case. 'BIQUAD' do.
            coefficients =. >}.args
            sections =. <"1 (((#coefficients) div 5),5)$coefficients
            result =. biquad (<samples),<sections
            result =. 'samples sections clipped' record (<'samples' get_key result),(<#sections),<'clipped' get_key result
        case. 'MOVAVG' do. samples =. samples moving_average 1{::args
        case. 'DCBLOCK' do. result =. dc_block (<samples),}.args
        case. 'NORMALIZE' do. result =. samples normalize 1{::args
        case. 'GATE' do. result =. gate (<samples),}.args
        case. 'ENVELOPE' do. samples =. envelope (<samples),}.args
        case. 'COMPRESS' do. result =. compress (<samples),}.args
        end.
        if. #result do.
            samples =. 'samples' get_key result
            extras =. }.result
        end.
    end.
    origin =. 'line ',(number linenumber),' ',name
    signal =. signal_record (<dst),(<rate),(<samples),(<origin),<sources
    Signals =: ((<dst),<signal) put_key Signals
    fields =. (<dst),(<'rate' kv rate),(<'samples' kv #samples),(<'peak' kv peak samples),<'sum' kv +/samples
    for_row. extras do.
        'key value' =. row
        fields =. fields,<key kv value
    end.
    text_line fields
)
plot_row =: 3 : 0
    'value scale rows' =. y
    ((scale-value)*(rows-1)) rdiv 2*scale
)
waveform_plot =: 3 : 0
    'source start count columns half attack release' =. y
    samples =. 'samples' get_key source
    rate =. 'rate' get_key source
    window =. count{.start}.samples
    levels =. count{.start}.envelope (<samples),(<attack),<release
    rows =. 1+2*half
    scale =. 1>.peak window
    grid =. (rows,columns)$' '
    for_column. i.columns do.
        first =. (column*count) div columns
        last =. ((column+1)*count) div columns
        part =. (last-first){.first}.window
        top =. plot_row (>./part),scale,rows
        bottom =. plot_row (<./part),scale,rows
        level =. scale<.>./(last-first){.first}.levels
        marks =. (plot_row level,scale,rows),plot_row (-level),scale,rows
        for_row. i.rows do.
            if. row e.marks do. symbol =. '*'
            elseif. (row>:top)*.row<:bottom do. symbol =. '#'
            elseif. row=half do. symbol =. '-'
            else. symbol =. ' ' end.
            grid =. symbol (<row,column)}grid
        end.
    end.
    fields =. (<'PLOT'),(<'name' get_key source),(<'rate' kv rate),(<'start' kv start),(<'count' kv count),(<'columns' kv columns),(<'rows' kv rows),(<'scale' kv scale),(<'attack' kv attack),<'release' kv release
    lines =. <text_line fields
    for_row. i.rows do.
        label =. ''
        if. row=0 do. label =. number scale
        elseif. row=half do. label =. '0'
        elseif. row=rows-1 do. label =. number -scale end.
        lines =. lines,<(6 right_pad label),' |',(row{grid),'|'
    end.
    axis =. columns#'-'
    axis =. '+' (10*i.1+(columns-1) div 10)}axis
    lines =. lines,<'       +',axis,'+'
    time =. '    ms'
    for_column. 10*i.1+(columns-1) div 10 do.
        index =. start+(column*count) div columns
        time =. time,((0>.(8+column)-#time)#' '),number index milliseconds rate
    end.
    lines,<time
)
meter_plot =: 4 : 0
    samples =. 'samples' get_key x
    rate =. 'rate' get_key x
    blocks =. (#samples) ceil_divide y
    fields =. (<'METER'),(<'name' get_key x),(<'rate' kv rate),(<'samples' kv #samples),(<'block' kv y),<'blocks' kv blocks
    lines =. <text_line fields
    for_index. i.blocks do.
        first =. index*y
        count =. y<.(#samples)-first
        part =. count{.first}.samples
        p =. peak part
        q =. rms part
        np =. (p*40) rdiv 32768
        nq =. (q*40) rdiv 32768
        bar =. ''
        for_position. i.40 do.
            if. position<nq do. symbol =. '#'
            elseif. position<np do. symbol =. '-'
            else. symbol =. ' ' end.
            bar =. bar,symbol
        end.
        text =. (6 right_pad number first milliseconds rate),' |',bar,'| ',('peak' kv p),' ',('rms' kv q),' ','clipped' kv count_clipped part
        lines =. lines,<text
    end.
    lines
)
histogram_plot =: 4 : 0
    samples =. 'samples' get_key x
    bins =. y
    counts =. bins$0
    for_value. samples do.
        bin =. ((value+32768)*bins) div 65536
        counts =. (1+bin{counts) bin}counts
    end.
    edges =. 0$0
    for_bin. i.bins+1 do. edges =. edges,((bin*65536) ceil_divide bins)-32768 end.
    top =. >./counts
    fields =. (<'HISTOGRAM'),(<'name' get_key x),(<'rate' kv 'rate' get_key x),(<'samples' kv #samples),(<'bins' kv bins),<'max' kv top
    lines =. <text_line fields
    for_bin. i.bins do.
        text =. (6 right_pad number bin{edges),' ',(6 right_pad number ((bin+1){edges)-1),' ',(5 right_pad number bin{counts),' |',(((bin{counts)*50) rdiv top)#'#'
        lines =. lines,<text
    end.
    lines
)
pitch_row =: 3 : 0
    'rate start level lag low high' =. y
    band =. 41#' '
    prefix =. (6 right_pad number start milliseconds rate),' |'
    if. lag<0 do. prefix,band,'| unvoiced ','rms' kv level return. end.
    position =. 0
    if. high>low do. position =. ((high-lag)*40) rdiv high-low end.
    band =. 'o' position}band
    prefix,band,'| ',('lag' kv lag),' hz=',(rate frequency_text lag),' ','rms' kv level
)
trace_lines =: 4 : 0
    lines =. <( (2*x)#' '),('name' get_key y),' <- ','origin' get_key y
    for_box. 'ingredients' get_key y do. lines =. lines,(x+1) trace_lines >box end.
    lines
)
metric_value =: 4 : 0
    select. x
    case. 'samples' do. #y
    case. 'peak' do. peak y
    case. 'rms' do. rms y
    case. 'sum' do. +/y
    case. 'zero_crossings' do. zero_crossings y
    case. 'clipped' do. count_clipped y
    end.
)
lag_range =: 3 : 0
    'rate minimum maximum' =. y
    (rate ceil_divide maximum),rate div minimum
)
execute_command =: 3 : 0
    'linenumber name values sources' =. y
    if. (<name)e.GeneratorNames do. <generate_signal y return. end.
    if. name-:'SET' do.
        variable =. 0{::values
        result =. 1{::values
        if. 4=#values do.
            operator =. 2{::values
            operand =. 3{::values
            if. (operator-:'/')*.operand=0 do. bad 'division by zero' return. end.
            select. operator
            case. '+' do. result =. result+operand
            case. '-' do. result =. result-operand
            case. '*' do. result =. result*operand
            case. '/' do. result =. result div operand
            end.
            if. (|result)>10000000 do. bad 'value out of range' return. end.
        end.
        Variables =: ((<variable),<result) put_key Variables
        <variable kv result return.
    end.
    source =. 0{::values
    args =. }.values
    samples =. 'samples' get_key source
    rate =. 'rate' get_key source
    sourcename =. 'name' get_key source
    length =. #samples
    select. name
    case. 'ANALYZE' do.
        'low high' =. lag_range rate,>args
        if. low>high do. bad 'empty lag range' return. end.
        if. high>:length do. bad 'signal too short' return. end.
        lag =. pitch_lag (<samples),(<low),<high
        lagtext =. hztext =. 'none'
        if. lag>0 do. lagtext =. number lag
            hztext =. rate frequency_text lag end.
        fields =. (<sourcename),(<number peak samples),(<number rms samples),(<number zero_crossings samples),(<number count_clipped samples),(<crest_fraction samples),(<lagtext),<hztext
        AnalysisLines =: AnalysisLines,<',' join fields
        <sourcename,' lags=',(number low),'-',number high
    case. 'COMPARE' do.
        second =. 0{::args
        require_same_rate (<source),<second
        if. #CommandError do. '' return. end.
        othersamples =. 'samples' get_key second
        count =. length>.#othersamples
        a =. samples,(count-length)$0
        b =. othersamples,(count-#othersamples)$0
        differences =. a-b
        nonzero =. I.differences~:0
        first =. 'none'
        if. #nonzero do. first =. number {.nonzero end.
        <text_line (<sourcename),(<'name' get_key second),(<'differing' kv #nonzero),(<'max_diff' kv peak differences),(<'first=',first),<'error_energy' kv energy differences
    case. 'EXPECT' do.
        'metric operator target' =. args
        value =. metric metric_value samples
        select. operator
        case. 'eq' do. passed =. value=target
        case. 'ne' do. passed =. value~:target
        case. 'lt' do. passed =. value<target
        case. 'le' do. passed =. value<:target
        case. 'gt' do. passed =. value>target
        case. 'ge' do. passed =. value>:target
        end.
        if. passed do. Passed =: Passed+1 else. Failed =: Failed+1 end.
        result =. passed{::'fail';'pass'
        <text_line (<sourcename),(<metric kv value),(<operator),(<target),<result
    case. 'SEGMENTS' do.
        'threshold gap minimum' =. >args
        found =. 0 2$0
        for_index. I.(|samples)>:threshold do.
            extend =. 0
            if. #found do. extend =. (index-(<(<:#found),1){found)<:gap end.
            if. extend do. found =. index (<(<:#found),1)}found
            else. found =. found,index,index end.
        end.
        reported =. 0 2$0
        for_bounds. found do. if. (1+({:bounds)-{.bounds)>:minimum do. reported =. reported,bounds end. end.
        lines =. <sourcename,' ','segments' kv #reported
        for_index. i.#reported do.
            'first last' =. index{reported
            part =. (1+last-first){.first}.samples
            text =. text_line (<'  segment'),(<index+1),(<'start' kv first),(<'end' kv last),(<'start_ms' kv first milliseconds rate),(<'end_ms' kv last milliseconds rate),(<'peak' kv peak part),(<'rms' kv rms part),<'crossings' kv zero_crossings part
            lines =. lines,<text
        end.
        lines
    case. 'ONSETS' do.
        'attack release threshold gap' =. >args
        levels =. envelope (<samples),(<attack),<release
        onsets =. 0$0
        for_index. i.length do.
            rising =. (index{levels)>:threshold
            if. index>0 do. rising =. rising*.((index-1){levels)<threshold end.
            if. rising do.
                accept =. 1
                if. #onsets do. accept =. (index-{:onsets)>:gap end.
                if. accept do. onsets =. onsets,index end.
            end.
        end.
        intervals =. (}.onsets)-}:onsets
        tempo =. 'none'
        if. 2<:#onsets do.
            middle =. ((#onsets)-2) div 2
            interval =. middle{/:~intervals
            tempo =. two_decimals (6000*rate) rdiv interval
        end.
        lines =. <sourcename,' ',('onsets' kv #onsets),' tempo=',tempo
        for_index. i.#onsets do.
            onset =. index{onsets
            interval =. 'none'
            if. index>0 do. interval =. number (index-1){intervals end.
            lines =. lines,<text_line (<'  onset'),(<index+1),(<'sample' kv onset),(<'ms' kv onset milliseconds rate),<'interval=',interval
        end.
        lines
    case. 'PITCHTRACK' do.
        'frame hop minimum maximum threshold' =. >args
        'low high' =. lag_range rate,minimum,maximum
        if. low>high do. bad 'empty lag range' return. end.
        if. high>:frame do. bad 'frame too short' return. end.
        count =. 1+(length-frame) div hop
        rows =. 0$a:
        voiced =. 0
        for_index. i.count do.
            first =. index*hop
            part =. frame{.first}.samples
            level =. rms part
            lag =. _1
            if. level>:threshold do. lag =. pitch_lag (<part),(<low),<high end.
            if. lag>0 do. voiced =. voiced+1 end.
            rows =. rows,<pitch_row rate,first,level,lag,low,high
        end.
        fields =. (<'PITCHTRACK'),(<sourcename),(<'rate' kv rate),(<'frame' kv frame),(<'hop' kv hop),(<'lags=',(number low),'-',number high),(<'threshold' kv threshold),(<'frames' kv count),<'voiced' kv voiced
        Waveforms =: Waveforms,(<text_line fields),rows
        <text_line (<sourcename),(<'frames' kv count),<'voiced' kv voiced
    case. 'EXCERPT' do.
        'start count' =. >args
        count =. count<.length-start
        fields =. (<'EXCERPT'),(<sourcename),(<'rate' kv rate),(<'samples' kv length),(<'start' kv start),<'count' kv count
        Excerpts =: Excerpts,<text_line fields
        for_offset. 8*i.1+(count-1) div 8 do.
            size =. 8<.count-offset
            part =. size{.(start+offset)}.samples
            line =. (5 right_pad number start+offset),':'
            for_value. part do. line =. line,' ',6 right_pad number value end.
            Excerpts =: Excerpts,<line
        end.
        <text_line (<sourcename),(<'start' kv start),<'count' kv count
    case. 'PLOT' do.
        'start count columns half attack release' =. >args
        Waveforms =: Waveforms,waveform_plot values
        <text_line (<sourcename),(<'start' kv start),(<'count' kv count),(<'columns' kv columns),<'rows' kv 1+2*half
    case. 'METER' do.
        block =. 0{::args
        Waveforms =: Waveforms,source meter_plot block
        <sourcename,' ','block' kv block
    case. 'HISTOGRAM' do.
        bins =. 0{::args
        Waveforms =: Waveforms,source histogram_plot bins
        <sourcename,' ','bins' kv bins
    case. 'TRACE' do. (<sourcename),1 trace_lines source
    case. 'SAVE' do.
        Saved =: Saved,format_signal source
        <sourcename,' ','samples' kv length
    end.
)
write_lines =: 4 : 0
    ((LF join y),LF#~0<#y) 1!:2 <'output/',x
    i.0
)
main =: 3 : 0
    command_table ''
    Signals =: Variables =: empty_table ''
    Log =: Excerpts =: Waveforms =: Saved =: 0$a:
    AnalysisLines =: <'signal,peak,rms,zero_crossings,clipped,crest,pitch_lag,pitch_hz'
    Steps =: Errors =: Passed =: Failed =: 0
    for_signalbox. read_signals '' do.
        signal =. >signalbox
        name =. 'name' get_key signal
        samples =. 'samples' get_key signal
        Signals =: ((<name),<signal) put_key Signals
        Log =: Log,<text_line (<'load'),(<name),(<'rate' kv 'rate' get_key signal),(<'samples' kv #samples),<'peak' kv peak samples
    end.
    lines =. read_lines 'pipeline.txt'
    for_index. i.#lines do.
        line =. index{::lines
        if. 0=#line do. continue. end.
        if. '#'={.line do. continue. end.
        tokens =. ' ' split line
        name =. 0{::tokens
        CommandError =: ''
        parsed =. name parse_arguments }.tokens
        if. 0=#CommandError do.
            'values sources' =. parsed
            result =. execute_command (<index+1),(<name),(<values),<sources
        end.
        prefix =. 'line ',(number index+1),': '
        if. #CommandError do.
            Errors =: Errors+1
            Log =: Log,<prefix,'error: ',CommandError
        else.
            Steps =: Steps+1
            Log =: Log,(<prefix,name,' ',0{::result),}.result
        end.
    end.
    for_namebox. /:~table_keys Signals do.
        name =. >namebox
        signal =. name get_key Signals
        samples =. 'samples' get_key signal
        Log =: Log,<text_line (<'signal'),(<name),(<'rate' kv 'rate' get_key signal),(<'samples' kv #samples),(<'peak' kv peak samples),<'rms' kv rms samples
    end.
    Log =: Log,<text_line (<'summary'),(<'steps' kv Steps),(<'errors' kv Errors),(<'signals' kv #Signals),(<'passed' kv Passed),<'failed' kv Failed
    1!:5 <'output'
    'log.txt' write_lines Log
    'analysis.csv' write_lines AnalysisLines
    'excerpts.txt' write_lines Excerpts
    'waveforms.txt' write_lines Waveforms
    'signals_out.txt' write_lines Saved
    i.0
)
main ''
