LF =: 10 { a.
METHOD_NAMES =: ;: 'GET HEAD POST PUT DELETE PATCH OPTIONS'
REASONS =: ;: 'fields date time ip method path status bytes latency'
FILTER_KEYS =: ;: 'METHOD STATUS IP PATH'
LOWER_KEYS =: ;: 'method status ip path'
QUERY_NAMES =: ;: 'SUMMARY MALFORMED STATUS METHODS TOP HOURLY TIMELINE BANDWIDTH VISITORS LATENCY HISTOGRAM APDEX ERRORS SLOWEST SESSIONS BURST PEAK GAPS IP RANGE FILTER UNFILTER RESET STATE'
NEED_RECORDS =: ;: 'STATUS METHODS TOP HOURLY TIMELINE BANDWIDTH VISITORS HISTOGRAM APDEX ERRORS SLOWEST BURST PEAK GAPS'
NUMERIC_KINDS =: ;: 'limit minutes width threshold length times'
NUMERIC_UPPER =: 100 1440 100000 100000 86400 1000
FORMS =: <;._2 (0 : 0)
-
-
-
-
kind limit
-
minutes
-
-
path
width
threshold
-
limit
ip minutes
length times
length
length
ip
date time date time
key value
subject
-
-
)

split =: 4 : 0
    <;._1 x,y
)

words =: 3 : 0
    parts =. ' ' split y
    parts #~ 0 < #&> parts
)

join =: 4 : 0
    result =. ''
    for_i. i.#y do.
        if. i > 0 do. result =. result,x end.
        result =. result, >i{y
    end.
    result
)

number =: 3 : 0
    ,'0' 8!:2 y
)

emit =: 3 : 0
    parts =. 0$a:
    for_item. y do.
        value =. >item
        if. 2 = 3!:0 value do.
            parts =. parts,<value
        else.
            parts =. parts,<number value
        end.
    end.
    ((' ' join parts),LF) 1!:2 4
    i.0
)

floor_ratio =: 4 : 0
    <. (x: x) % x: y
)

padded =: 4 : 0
    text =. number y
    ((0 >. x-#text)#'0'),text
)

decimal =: 3 : 0
    'numerator denominator places' =. y
    scale =. 10x ^ places
    value =. (numerator*scale) floor_ratio denominator
    (number value floor_ratio scale),'.',places padded scale|value
)

percent =: 3 : 0
    'part whole' =. y
    (decimal (100x*part),whole,2),'%'
)

bytes_text =: 3 : 0
    if. y < 1024 do. (number y),'B' return. end.
    if. y < 1048576 do. (decimal y,1024,1),'KB' return. end.
    if. y < 1073741824 do. (decimal y,1048576,1),'MB' return. end.
    (decimal y,1073741824,1),'GB'
)

bar_line =: 3 : 0
    'label count maximum' =. y
    if. count = 0 do.
        emit label;count
    else.
        width =. ((30*count)+maximum-1) floor_ratio maximum
        emit label;count;(width#'#')
    end.
)

digits =: 3 : 0
    (0<#y) *. *./ y e. '0123456789'
)

canonical =: 4 : 0
    if. (0=#y)+.(#y)>x do. 0 return. end.
    if. -. digits y do. 0 return. end.
    (1=#y) +. '0' ~: {.y
)

leap =: 3 : 0
    (0=4|y) *. ((0~:100|y) +. 0=400|y)
)

month_days =: 4 : 0
    days =. 31 28 31 30 31 30 31 31 30 31 30 31
    ((y-1){days) + ((y=2)*leap x)
)

valid_date =: 3 : 0
    if. 10 ~: #y do. 0 return. end.
    if. -. '--' -: 4 7{y do. 0 return. end.
    if. -. digits 0 1 2 3 5 6 8 9{y do. 0 return. end.
    year =. 0".4{.y
    month =. 0".2{.5}.y
    day =. 0".8}.y
    if. (year<2000)+.(year>2059)+.(month<1)+.month>12 do. 0 return. end.
    (day>:1) *. day <: year month_days month
)

valid_time =: 3 : 0
    if. 8 ~: #y do. 0 return. end.
    if. -. '::' -: 2 5{y do. 0 return. end.
    if. -. digits 0 1 3 4 6 7{y do. 0 return. end.
    values =. 0".&> ':' split y
    *./ values < 24 60 60
)

valid_ip =: 3 : 0
    parts =. '.' split y
    if. 4 ~: #parts do. 0 return. end.
    for_part. parts do.
        text =. >part
        if. -. 3 canonical text do. 0 return. end.
        if. 255 < 0".text do. 0 return. end.
    end.
    1
)

ip_number =: 3 : 0
    256x #. 0".&> '.' split y
)

valid_status =: 3 : 0
    if. (3~:#y)+.-.digits y do. 0 return. end.
    value =. 0".y
    (value>:100) *. value<:599
)

status_class =: 3 : 0
    if. 3 ~: #y do. 0 return. end.
    ('xx'-:1}.y) *. ({.y)e.'12345'
)

filter_value =: 4 : 0
    select. x
        case. 'METHOD' do. (<y) e. METHOD_NAMES
        case. 'STATUS' do. (status_class y) +. valid_status y
        case. 'IP' do. valid_ip y
        case. 'PATH' do. '/' = {.y
        case. do. 0
    end.
)

status_matches =: 4 : 0
    if. status_class x do.
        (0".{.x) = y floor_ratio 100
    else.
        y = 0".x
    end.
)

validate_argument =: 4 : 0
    'value args' =. y
    numeric =. NUMERIC_KINDS i. <x
    if. numeric < #NUMERIC_KINDS do.
        if. -. 6 canonical value do. 'invalid number' return. end.
        n =. 0".value
        if. (n<1)+.n>numeric{NUMERIC_UPPER do. 'invalid number' return. end.
        '' return.
    end.
    select. x
        case. 'kind' do.
            if. -. (<value) e. ;:'PATHS IPS' do. 'invalid kind' return. end.
        case. 'path' do.
            if. '/' ~: {.value do. 'invalid path' return. end.
        case. 'ip' do.
            if. -. valid_ip value do. 'invalid ip' return. end.
        case. 'date' do.
            if. -. valid_date value do. 'invalid timestamp' return. end.
        case. 'time' do.
            if. -. valid_time value do. 'invalid timestamp' return. end.
        case. 'key' do.
            if. -. (<value) e. FILTER_KEYS do. 'invalid key' return. end.
        case. 'subject' do.
            if. -. (<value) e. FILTER_KEYS,<'RANGE' do. 'invalid key' return. end.
        case. 'value' do.
            if. -. (0{::args) filter_value value do. 'invalid value' return. end.
    end.
    ''
)

malformed_reason =: 3 : 0
    if. 8 ~: #y do. 0 return. end.
    if. -. valid_date 0{::y do. 1 return. end.
    if. -. valid_time 1{::y do. 2 return. end.
    if. -. valid_ip 2{::y do. 3 return. end.
    if. -. (3{y) e. METHOD_NAMES do. 4 return. end.
    if. '/' ~: {.4{::y do. 5 return. end.
    if. -. valid_status 5{::y do. 6 return. end.
    if. -. 8 canonical 6{::y do. 7 return. end.
    if. -. 6 canonical 7{::y do. 8 return. end.
    _1
)

day_number =: 3 : 0
    year =. 0".4{.y
    month =. 0".2{.5}.y
    result =. (0".8}.y)-1
    for_prior. 2000+i.year-2000 do. result =. result+365+leap prior end.
    for_prior. 1+i.month-1 do. result =. result+year month_days prior end.
    result
)

seconds_of =: 3 : 0
    'date clock' =. y
    hours =. 0".2{.clock
    minutes =. 0".2{.3}.clock
    seconds =. 0".6}.clock
    (86400*day_number date)+(3600*hours)+(60*minutes)+seconds
)

interval_label =: 3 : 0
    days =. y floor_ratio 86400
    minutes =. (86400|y) floor_ratio 60
    year =. 2000
    while. days >: 365+leap year do.
        days =. days-(365+leap year)
        year =. year+1
    end.
    month =. 1
    while. days >: year month_days month do.
        days =. days-year month_days month
        month =. month+1
    end.
    (4 padded year),'-',(2 padded month),'-',(2 padded days+1),' ',(2 padded minutes floor_ratio 60),':',2 padded 60|minutes
)

normalize_path =: 3 : 0
    raw =. (y i.'?'){.y
    kept =. 0$a:
    for_part. '/' split raw do.
        text =. >part
        if. text-:'..' do.
            if. #kept do. kept =. }:kept end.
        elseif. (0<#text)*.-.text-:'.' do.
            kept =. kept,<text
        end.
    end.
    normalized =. 0$a:
    for_part. kept do.
        text =. >part
        if. digits text do.
            text =. '{id}'
        elseif. ((#text)>:8) *. (*./text e.'0123456789abcdef') *. +./text e.'0123456789' do.
            text =. '{hex}'
        end.
        normalized =. normalized,<text
    end.
    '/', '/' join normalized
)

LogDates =: 0$a:
LogStamps =: 0$a:
LogIps =: 0$a:
LogMethods =: 0$a:
LogPaths =: 0$a:
LogIpNumbers =: i.0
LogSeconds =: i.0
LogLines =: i.0
LogHours =: i.0
LogStatus =: i.0
LogBytes =: i.0
LogLatency =: i.0
BadLines =: i.0
BadReasons =: i.0
LogLineCount =: 0
TimeOrder =: i.0
Filters =: 4$<''
TimeRange =: i.0
RangeLabels =: 0$a:

ingest =: 3 : 0
    LogLineCount =: >:LogLineCount
    fields =. words y
    reason =. malformed_reason fields
    if. reason >: 0 do.
        BadLines =: BadLines,LogLineCount
        BadReasons =: BadReasons,reason
        i.0 return.
    end.
    date =. 0{::fields
    clock =. 1{::fields
    LogDates =: LogDates,<date
    LogStamps =: LogStamps,<date,' ',clock
    LogIps =: LogIps,2{fields
    LogMethods =: LogMethods,3{fields
    LogPaths =: LogPaths,<normalize_path 4{::fields
    LogIpNumbers =: LogIpNumbers,ip_number 2{::fields
    LogSeconds =: LogSeconds,seconds_of date;clock
    LogLines =: LogLines,LogLineCount
    LogHours =: LogHours,0".2{.clock
    LogStatus =: LogStatus,0".5{::fields
    LogBytes =: LogBytes,0".6{::fields
    LogLatency =: LogLatency,0".7{::fields
    i.0
)

selected =: 3 : 0
    idx =. TimeOrder
    if. #TimeRange do.
        values =. idx{LogSeconds
        idx =. idx #~ (({.TimeRange)<:values) *. values<:{:TimeRange
    end.
    value =. 0{::Filters
    if. #value do. idx =. idx #~ (<value)=idx{LogMethods end.
    value =. 1{::Filters
    if. #value do. idx =. idx #~ value status_matches idx{LogStatus end.
    value =. 2{::Filters
    if. #value do. idx =. idx #~ (<value)=idx{LogIps end.
    value =. 3{::Filters
    if. #value do. idx =. idx #~ (<value)=idx{LogPaths end.
    idx
)

group_indices =: 4 : 0
    values =. y{x
    groups =. 0$a:
    for_key. ~.values do.
        groups =. groups,<y #~ key=values
    end.
    groups
)

ranked_groups =: 4 : 0
    if. 0=#y do. y return. end.
    samples =. {.&>y
    labels =. samples{x
    if. 32 ~: 3!:0 labels do. labels =. <"0 labels end.
    order =. /: (<"0 -#&>y),.labels
    order{y
)

window_peak =: 4 : 0
    seconds =. y{LogSeconds
    begin =. 0
    best =. 0
    first =. 0
    last =. 0
    for_i. i.#y do.
        while. ((i{seconds)-begin{seconds)>:x do. begin =. >:begin end.
        size =. 1+i-begin
        if. size>best do.
            best =. size
            first =. begin
            last =. i
        end.
    end.
    best,(first{y),last{y
)

apdex_counts =: 4 : 0
    latency =. y{LogLatency
    ok =. (y{LogStatus)<500
    sat =. +/ok *. latency<:x
    tol =. +/ok *. (latency>x) *. latency<:4*x
    sat,tol,(#y)-(sat+tol)
)

apdex_rating =: 3 : 0
    'points total' =. y
    if. (100*points)>:94*total do. 'excellent' return. end.
    if. (100*points)>:85*total do. 'good' return. end.
    if. (100*points)>:70*total do. 'fair' return. end.
    if. (100*points)>:50*total do. 'poor' return. end.
    'unacceptable'
)

run_query =: 3 : 0
    'name args idx' =. y
    n =. #idx
    select. name
        case. 'SUMMARY' do.
            emit 'SUMMARY';'lines';LogLineCount;'valid';(#LogSeconds);'malformed';#BadLines
            emit 'requests';n;'bytes';(+/idx{LogBytes);'ips';(#~.idx{LogIps);'paths';#~.idx{LogPaths
            if. n=0 do.
                emit 'span';'none'
            else.
                emit 'span';(({.idx){::LogStamps);(({:idx){::LogStamps);(({:idx){LogSeconds)-({.idx){LogSeconds
            end.

        case. 'MALFORMED' do.
            emit 'MALFORMED';#BadLines
            for_reason. i.#REASONS do.
                lines =. BadLines #~ reason=BadReasons
                if. #lines do. emit (reason{REASONS),(<#lines),<"0 lines end.
            end.

        case. 'STATUS' do.
            emit 'STATUS';n
            classes =. (idx{LogStatus) floor_ratio 100
            for_class. 1+i.5 do.
                count =. +/class=classes
                emit ((number class),'xx');count;percent count,n
            end.
            values =. idx{LogStatus
            for_status. /:~ ~.values do.
                count =. +/status=values
                emit status;count;percent count,n
            end.

        case. 'METHODS' do.
            groups =. LogMethods group_indices idx
            groups =. LogMethods ranked_groups groups
            emit 'METHODS';n
            for_group. groups do.
                members =. >group
                emit (({.members){::LogMethods);(#members);percent (#members),n
            end.

        case. 'TOP' do.
            kind =. 0{::args
            limit =. 0".1{::args
            if. kind-:'IPS' do.
                groups =. LogIps group_indices idx
                groups =. LogIpNumbers ranked_groups groups
                labels =. LogIps
            else.
                groups =. LogPaths group_indices idx
                groups =. LogPaths ranked_groups groups
                labels =. LogPaths
            end.
            shown =. limit <. #groups
            emit 'TOP';kind;shown;'of';#groups
            rank =. 0
            previous =. _1
            for_i. i.shown do.
                members =. i{::groups
                if. previous~:#members do. rank=.i+1 end.
                previous =. #members
                emit rank;(({.members){::labels);(#members);percent (#members),n
            end.

        case. 'HOURLY' do.
            counts =. +/"1 (i.24) =/ idx{LogHours
            maximum =. >./counts
            emit 'HOURLY';n;'peak';(2 padded counts i.maximum);maximum
            for_hour. i.24 do.
                bar_line (2 padded hour);(hour{counts);maximum
            end.

        case. 'TIMELINE';'HISTOGRAM' do.
            parameter =. 0".0{::args
            if. name-:'TIMELINE' do.
                width =. 60*parameter
                values =. (idx{LogSeconds) floor_ratio width
            else.
                width =. parameter
                values =. (idx{LogLatency) floor_ratio width
            end.
            low =. <./values
            high =. >./values
            if. (high-low)>:60 do.
                emit 'ERROR';'too many buckets'
                i.0 return.
            end.
            buckets =. low+i.1+high-low
            counts =. +/"1 buckets =/ values
            emit name;parameter;#buckets
            maximum =. >./counts
            for_i. i.#buckets do.
                start =. width*i{buckets
                if. name-:'TIMELINE' do.
                    label =. interval_label start
                else.
                    label =. (number start),'-',number start+width-1
                end.
                bar_line label;(i{counts);maximum
            end.

        case. 'BANDWIDTH' do.
            dates =. /:~ ~.idx{LogDates
            volume =. +/idx{LogBytes
            emit 'BANDWIDTH';(#dates);volume;bytes_text volume
            for_date. dates do.
                members =. idx #~ date=idx{LogDates
                volume =. +/members{LogBytes
                emit (>date);(#members);volume;bytes_text volume
            end.

        case. 'VISITORS' do.
            groups =. LogIps group_indices idx
            firstdates =. ({.&>groups){LogDates
            dates =. /:~ ~.idx{LogDates
            emit 'VISITORS';(#dates);#groups
            for_date. dates do.
                members =. idx #~ date=idx{LogDates
                unique =. #~.members{LogIps
                fresh =. +/date=firstdates
                emit (>date);'unique';unique;'new';fresh;'returning';unique-fresh
            end.

        case. 'LATENCY' do.
            label =. 'all'
            members =. idx
            if. #args do.
                label =. normalize_path 0{::args
                members =. idx #~ (<label)=idx{LogPaths
            end.
            if. 0=#members do.
                emit 'LATENCY';'no records'
                i.0 return.
            end.
            values =. /:~ members{LogLatency
            count =. #values
            trim =. count floor_ratio 10
            trimmed =. (trim+i.count-2*trim){values
            p50 =. (((50*count)+99) floor_ratio 100)-1
            p90 =. (((90*count)+99) floor_ratio 100)-1
            p99 =. (((99*count)+99) floor_ratio 100)-1
            emit 'LATENCY';label;'count';count;'min';({.values);'p50';(p50{values);'p90';(p90{values);'p99';(p99{values);'max';({:values);'mean';(decimal (+/values),count,2);'trimmed';decimal (+/trimmed),(#trimmed),2

        case. 'APDEX' do.
            threshold =. 0".0{::args
            'sat tol frustrated' =. threshold apdex_counts idx
            points =. (2*sat)+tol
            emit 'APDEX';threshold;(decimal points,(2*n),3);(apdex_rating points,2*n);'satisfied';sat;'tolerating';tol;'frustrated';frustrated
            groups =. LogPaths group_indices idx
            sortkeys =. 0 3$a:
            for_group. groups do.
                members =. >group
                'sat tol frustrated' =. threshold apdex_counts members
                numerator =. (2*sat)+tol
                score =. (x:numerator) % x:2*#members
                key =. (<score),(<-#members),({.members){LogPaths
                sortkeys =. sortkeys,1 3$key
            end.
            for_position. /:sortkeys do.
                members =. position{::groups
                'sat tol frustrated' =. threshold apdex_counts members
                numerator =. (2*sat)+tol
                emit (({.members){::LogPaths);(decimal numerator,(2*#members),3);(apdex_rating numerator,2*#members);#members
            end.

        case. 'ERRORS' do.
            failed =. +/(idx{LogStatus)>:400
            emit 'ERRORS';failed;'of';n;percent failed,n
            candidates =. LogPaths group_indices idx
            groups =. 0$a:
            sortkeys =. 0 3$a:
            for_group. candidates do.
                members =. >group
                failed =. +/(members{LogStatus)>:400
                if. failed=0 do. continue. end.
                groups =. groups,<members
                rate =. (x:failed) % x:#members
                key =. (<-rate),(<-failed),({.members){LogPaths
                sortkeys =. sortkeys,1 3$key
            end.
            for_position. /:sortkeys do.
                members =. position{::groups
                classes =. (members{LogStatus) floor_ratio 100
                client =. +/classes=4
                server =. +/classes=5
                emit (({.members){::LogPaths);(#members);client;server;percent (client+server),#members
            end.

        case. 'SLOWEST' do.
            endpoints =. LogMethods ,&.> (<' '),&.>LogPaths
            groups =. endpoints group_indices idx
            sortkeys =. 0 4$a:
            for_group. groups do.
                members =. >group
                latency =. members{LogLatency
                average =. (x:+/latency) % x:#members
                key =. (<-average),(< (- >./latency)),(({.members){LogPaths),({.members){LogMethods
                sortkeys =. sortkeys,1 4$key
            end.
            order =. /:sortkeys
            shown =. (#groups)<.0".0{::args
            emit 'SLOWEST';shown;'of';#groups
            for_i. i.shown do.
                members =. (i{order){::groups
                latency =. members{LogLatency
                emit (i+1);(({.members){::LogMethods);(({.members){::LogPaths);'count';(#members);'avg';(decimal (+/latency),(#members),2);'max';>./latency
            end.

        case. 'SESSIONS' do.
            ip =. 0{::args
            minutes =. 30
            if. 2=#args do. minutes=.0".1{::args end.
            members =. idx #~ (<ip)=idx{LogIps
            if. 0=#members do.
                emit 'SESSIONS';'no records'
                i.0 return.
            end.
            times =. members{LogSeconds
            starts =. ,0
            for_i. 1+i.(#members)-1 do.
                if. ((i{times)-(i-1){times)>60*minutes do. starts=.starts,i end.
            end.
            starts =. starts,#members
            sessions =. 0$a:
            duration =. 0
            for_i. i.(#starts)-1 do.
                first =. i{starts
                length =. ((i+1){starts)-first
                session =. (first+i.length){members
                sessions =. sessions,<session
                duration =. duration+(({:session){LogSeconds)-({.session){LogSeconds
            end.
            count =. #sessions
            emit 'SESSIONS';ip;'timeout';minutes;'count';count;'requests';(#members);'avg_duration';(decimal duration,count,1);'avg_requests';decimal (#members),count,1
            for_i. i.count do.
                session =. i{::sessions
                duration =. (({:session){LogSeconds)-({.session){LogSeconds
                emit (i+1);(({.session){::LogStamps);(({:session){::LogStamps);duration;(#session);#~.session{LogPaths
            end.

        case. 'BURST' do.
            width =. 0".0{::args
            threshold =. 0".1{::args
            failed =. idx #~ (idx{LogStatus)>:400
            groups =. LogIps group_indices failed
            matches =. 0 4$0
            for_group. groups do.
                members =. >group
                peak =. width window_peak members
                if. ({.peak)>:threshold do.
                    matches =. matches,1 4$({.members),peak
                end.
            end.
            sortkeys =. (-1{"1 matches),.(0{"1 matches){LogIpNumbers
            emit 'BURST';width;threshold;#matches
            for_row. (/:sortkeys){matches do.
                'sample count first last' =. row
                emit (sample{::LogIps);count;(first{::LogStamps);last{::LogStamps
            end.

        case. 'PEAK' do.
            width =. 0".0{::args
            'count first last' =. width window_peak idx
            emit 'PEAK';width;count;(first{::LogStamps);last{::LogStamps

        case. 'GAPS' do.
            threshold =. 0".0{::args
            times =. idx{LogSeconds
            gaps =. i.0
            for_i. 1+i.n-1 do.
                if. ((i{times)-(i-1){times)>:threshold do. gaps=.gaps,i end.
            end.
            emit 'GAPS';threshold;#gaps
            for_i. gaps do.
                first =. (i-1){idx
                last =. i{idx
                emit (first{::LogStamps);(last{::LogStamps);(last{LogSeconds)-first{LogSeconds
            end.

        case. 'IP' do.
            ip =. 0{::args
            members =. idx #~ (<ip)=idx{LogIps
            if. 0=#members do.
                emit 'IP';'no records'
                i.0 return.
            end.
            paths =. LogPaths group_indices members
            emit 'IP';ip;'requests';(#members);'bytes';(+/members{LogBytes);'errors';(+/(members{LogStatus)>:400);'paths';#paths
            emit 'first';(({.members){::LogStamps);'last';({:members){::LogStamps
            groups =. LogMethods group_indices members
            groups =. LogMethods ranked_groups groups
            parts =. <'methods'
            for_group. groups do.
                groupmembers =. >group
                parts =. parts,(({.groupmembers){LogMethods),<#groupmembers
            end.
            emit parts
            classes =. (members{LogStatus) floor_ratio 100
            parts =. <'classes'
            for_class. 1+i.5 do.
                parts =. parts,(< (number class),'xx'),<+/class=classes
            end.
            emit parts
            paths =. LogPaths ranked_groups paths
            for_group. (3<.#paths){.paths do.
                groupmembers =. >group
                emit 'path';(({.groupmembers){::LogPaths);#groupmembers
            end.

        case. 'RANGE' do.
            first =. seconds_of 2{.args
            last =. seconds_of 2}.args
            if. first>last do.
                emit 'ERROR';'invalid range'
                i.0 return.
            end.
            TimeRange =: first,last
            RangeLabels =: (<' ' join 2{.args),<' ' join 2}.args
            emit (<'RANGE'),RangeLabels,(<'active'),<#selected ''

        case. 'FILTER' do.
            'key value' =. args
            position =. FILTER_KEYS i.<key
            if. key-:'PATH' do. value=.normalize_path value end.
            Filters =: (<value) position}Filters
            emit 'FILTER';key;value;'active';#selected ''

        case. 'UNFILTER' do.
            key =. 0{::args
            if. key-:'RANGE' do.
                if. 0=#TimeRange do.
                    emit 'ERROR';'not filtered'
                    i.0 return.
                end.
                TimeRange =: i.0
                RangeLabels =: 0$a:
            else.
                position =. FILTER_KEYS i.<key
                if. 0=#position{::Filters do.
                    emit 'ERROR';'not filtered'
                    i.0 return.
                end.
                Filters =: (< '') position}Filters
            end.
            emit 'UNFILTER';key;'active';#selected ''

        case. 'RESET' do.
            TimeRange =: i.0
            RangeLabels =: 0$a:
            Filters =: 4$<''
            emit 'RESET';'active';#selected ''

        case. 'STATE' do.
            label =. '-'
            if. #TimeRange do. label=.' ' join RangeLabels end.
            parts =. 'STATE';'active';n;'range';label
            for_i. i.4 do.
                value =. i{::Filters
                if. 0=#value do. value=.'-' end.
                parts =. parts,(i{LOWER_KEYS),<value
            end.
            emit parts
    end.
    i.0
)

execute =: 3 : 0
    fields =. words y
    name =. 0{::fields
    index =. QUERY_NAMES i.<name
    if. index=#QUERY_NAMES do.
        emit 'ERROR';'unknown query'
        i.0 return.
    end.
    args =. }.fields
    formtext =. index{::FORMS
    form =. words formtext
    if. formtext-:'-' do. form=.0$a: end.
    minimum =. (#form)-(index e.9 14)
    if. ((#args)<minimum)+.(#args)>#form do.
        emit 'ERROR';'wrong arguments'
        i.0 return.
    end.
    for_i. i.#args do.
        reason =. (i{::form) validate_argument (i{::args);<args
        if. #reason do.
            emit 'ERROR';reason
            i.0 return.
        end.
    end.
    idx =. selected ''
    if. ((<name)e.NEED_RECORDS)*.0=#idx do.
        emit name;'no records'
    else.
        run_query name;args;<idx
    end.
    i.0
)

main =: 3 : 0
    lines =. <;._2 (1!:1 3),LF
    separator =. lines i.<'---'
    for_line. separator{.lines do. ingest >line end.
    TimeOrder =: /:LogSeconds,.LogLines
    position =. separator+1
    while. position<#lines do.
        text =. position{::lines
        if. text-:'END' do. break. end.
        execute text
        position =. position+1
    end.
    i.0
)

main ''
