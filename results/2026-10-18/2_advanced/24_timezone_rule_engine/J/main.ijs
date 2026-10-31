ScriptPath =: >{:4!:3''
SourceDirectory =: (1+>./_1,I.ScriptPath e.'/\'){.ScriptPath
Digits =: '0123456789'
div =: 4 : '_1 x:<.(x:x)%x:y'
num =: 3 : '10#.Digits i.y'
number =: 3 : 0
    prefix =. ''
    if. y<0 do. prefix =. '-'
        y =. -y end.
    text =. ''
    while. y>0 do.
        text =. ((10|y){Digits),text
        y =. y div 10
    end.
    if. #text do. prefix,text else. '0' end.
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
        value =. index{::y
        if. 2~:3!:0 value do. value =. number value end.
        text =. text,value
    end.
    text
)
format =: 4 : 0
    parts =. '|' split x
    text =. 0{::parts
    for_index. i.#y do.
        value =. index{::y
        if. 2~:3!:0 value do. value =. number value end.
        text =. text,value,(index+1){::parts
    end.
    text
)
ascii_order =: 3 : '/: > (a.&i.)&.> y'
read_lines =: 3 : '<;._2 (1!:1 <''input/'',y)'
load SourceDirectory,'day_rules.ijs'
load SourceDirectory,'tz_parser.ijs'
load SourceDirectory,'transitions.ijs'
load SourceDirectory,'resolver.ijs'
load SourceDirectory,'report.ijs'
year_start =: 3 : 'DaySeconds*day_number y,1 1'
names_or_none =: 4 : 0
    if. #y do. x join y else. 'none' end.
)
indented =: 3 : 0
    lines =. {.y
    for_line. }.y do. lines =. lines,<'  ',>line end.
    lines
)
merge_intervals =: 3 : 0
    merged =. 0 2$0
    for_interval. (/:y){y do.
        'low high' =. interval
        if. #merged do.
            if. low<:1{_1{merged do.
                previous =. _1{merged
                merged =. ((0{previous),high>.1{previous)(_1)}merged
                continue.
            end.
        end.
        merged =. merged,low,high
    end.
    merged
)
intersect_intervals =: 4 : 0
    pieces =. 0 2$0
    for_first. x do.
        for_second. y do.
            low =. (0{first)>.0{second
            high =. (1{first)<.1{second
            if. low<high do. pieces =. pieces,low,high end.
        end.
    end.
    merge_intervals pieces
)
parse_zone_line =: 3 : 0
    offset =. parse_stdoff 0{::y
    rules_text =. 1{::y
    rule_set =. ''
    save =. 0
    if. ({.rules_text)e.Digits do. save =. parse_save rules_text
    elseif. -.rules_text-:'-' do. rule_set =. rules_text end.
    format_text =. 2{::y
    (0<#rule_set)check_format format_text
    until =. 0$a:
    if. (#y)>3 do. until =. parse_until 3}.y end.
    (<offset),(<rules_text),(<rule_set),(<save),(<format_text),(<until),(<NegativeInfinity),<PositiveInfinity
)
parse_rule =: 4 : 0
    from =. parse_year 2{::y
    to =. from parse_to 3{::y
    if. -.('-'-:4{::y)do. field_fail 'syntax error' end.
    month =. parse_month 5{::y
    day =. month parse_day_spec 6{::y
    'at kind' =. parse_time 7{::y
    save =. parse_save 8{::y
    letter =. parse_letter 9{::y
    (<x),(<y),(1{y),(<from),(<to),(<month),(<day),(<at),(<kind),(<save),<letter
)
add_block_line =: 4 : 0
    members =. x{::BlockLines
    SourceBlocks =: x y}SourceBlocks
    SourcePositions =: (#members)y}SourcePositions
    BlockLines =: (<members,y)x}BlockLines
    i.0
)
read_sources =: 3 : 0
    SourceNumbers =: SourceBlocks =: SourcePositions =: SourceFieldErrors =: 0$0
    SourceFields =: SourceKinds =: SourceZoneLines =: SourceErrors =: 0$a:
    raws =. read_lines 'tzdata.txt'
    for_number. i.#raws do.
        content =. line_content number{::raws
        if. 0=#content do. continue. end.
        fields =. split_fields content
        kind =. 'unknown'
        if. ' '={.content do. kind =. 'continuation'
        elseif. ({.fields)e.'Rule';'Zone';'Link' do. kind =. 0{::fields end.
        SourceNumbers =: SourceNumbers,number+1
        SourceFields =: SourceFields,<fields
        SourceKinds =: SourceKinds,<kind
        SourceBlocks =: SourceBlocks,_1
        SourcePositions =: SourcePositions,0
        SourceFieldErrors =: SourceFieldErrors,0
        SourceZoneLines =: SourceZoneLines,<0$a:
        SourceErrors =: SourceErrors,<''
    end.
    BlockNames =: BlockLines =: 0$a:
    BlockNumbers =: 0$0
    for_index. i.#SourceNumbers do.
        kind =. index{::SourceKinds
        if. kind-:'Zone' do.
            fields =. index{::SourceFields
            BlockNames =: BlockNames,1{fields
            BlockNumbers =: BlockNumbers,index{SourceNumbers
            BlockLines =: BlockLines,<0$0
            ((#BlockNames)-1)add_block_line index
        elseif. kind-:'continuation' do.
            if. index=0 do. continue. end.
            previous =. index-1
            block =. previous{SourceBlocks
            if. block<0 do. continue. end.
            previous_kind =. previous{::SourceKinds
            count =. #previous{::SourceFields
            if. ((previous_kind-:'Zone')*.count>:6)+.((previous_kind-:'continuation')*.count>:4)do.
                block add_block_line index
            end.
        end.
    end.
    i.0
)
parse_fields =: 3 : 0
    kind =. y{::SourceKinds
    fields =. y{::SourceFields
    count =. #fields
    if. (kind-:'unknown')+.((kind-:'continuation')*.0>y{SourceBlocks)do. field_fail 'syntax error' end.
    valid =. 0
    if. kind-:'Rule' do. valid =. count=10
    elseif. kind-:'Zone' do. valid =. (count>:5)*.count<:9
    elseif. kind-:'continuation' do. valid =. (count>:3)*.count<:7
    elseif. kind-:'Link' do. valid =. count=3 end.
    if. -.valid do. field_fail 'syntax error' end.
    if. kind-:'Rule' do.
        rule =. (y{SourceNumbers)parse_rule fields
        name =. 2{::rule
        set =. RuleNames i.<name
        if. set=#RuleNames do.
            RuleNames =: RuleNames,<name
            RuleSets =: RuleSets,<0$0
        end.
        RuleSets =: (<(set{::RuleSets),#Rules)set}RuleSets
        Rules =: Rules,<rule
    elseif. kind-:'Zone' do. SourceZoneLines =: (<parse_zone_line 2}.fields)y}SourceZoneLines
    elseif. kind-:'continuation' do. SourceZoneLines =: (<parse_zone_line fields)y}SourceZoneLines end.
    i.0
)
structural_error =: 3 : 0
    kind =. y{::SourceKinds
    fields =. y{::SourceFields
    line =. y{::SourceZoneLines
    if. kind-:'Zone' do.
        name =. 1{::fields
        if. (<name)e.SeenZoneNames do. 'duplicate zone ',name return. end.
        SeenZoneNames =: SeenZoneNames,<name
    end.
    rule_set =. 2{::line
    if. #rule_set do.
        if. -.(<rule_set)e.RuleNames do. 'unknown rule ',rule_set return. end.
    end.
    until =. 5{::line
    if. 0=#until do. '' return. end.
    members =. (y{SourceBlocks){::BlockLines
    position =. y{SourcePositions
    if. kind-:'continuation' do.
        previous =. (position-1){members
        if. 0=previous{SourceFieldErrors do.
            previous_until =. 5{::previous{::SourceZoneLines
            if. (5{::until)<:5{::previous_until do. 'until not increasing' return. end.
        end.
    end.
    if. position=(#members)-1 do. 'missing continuation' return. end.
    ''
)
standard_letter =: 3 : 0
    for_instance. y do.
        rule =. (1{instance){::Rules
        if. 0=9{::rule do. 10{::rule return. end.
    end.
    ''
)
define_zone =: 3 : 0
    name =. y{::BlockNames
    lines =. 0$a:
    periods =. 0$a:
    applied =. (#Rules)$0
    start =. NegativeInfinity
    for_source. y{::BlockLines do.
        line =. source{::SourceZoneLines
        line =. (<start)6}line
        'offset rules_text rule_set save format_text until' =. 6{.line
        switches =. 0$a:
        ending =. PositiveInfinity
        if. 0=#rule_set do.
            if. #until do. ending =. (5{::until)-adjustment (4{until),(<offset),<save end.
            switches =. switches,<(<start),(<save),<''
        else.
            instances =. (RuleNames i.<rule_set){::Sequences
            'pre instances_applied ending' =. instances run_instances (<offset),(<start),<until
            save =. 0
            letter =. standard_letter instances
            if. #pre do.
                rule =. ({:pre){::Rules
                save =. 9{::rule
                letter =. 10{::rule
            end.
            switches =. switches,<(<start),(<save),<letter
            for_instance. instances_applied do.
                'time index' =. instance
                rule =. index{::Rules
                switches =. switches,<(<time),(9{rule),10{rule
                applied =. (1+index{applied)index}applied
            end.
        end.
        for_switch. switches do.
            'time save letter' =. >switch
            period =. (<time),(<offset+save),(<save~:0),<format_text abbreviation (<save),<letter
            keep =. 1
            if. #periods do. keep =. -. (}.period)-:}._1{::periods end.
            if. keep do. periods =. periods,<period end.
        end.
        line =. (<ending)7}line
        lines =. lines,<line
        start =. ending
    end.
    ZoneNames =: ZoneNames,<name
    Zones =: Zones,<(<name),(<lines),(<0$a:),(<applied),<periods
    i.0
)
read_database =: 3 : 0
    read_sources''
    Rules =: RuleNames =: RuleSets =: Sequences =: 0$a:
    for_index. i.#SourceNumbers do.
        try. parse_fields index
        catcht.
            SourceFieldErrors =: 1 index}SourceFieldErrors
            SourceErrors =: (<FieldProblem)index}SourceErrors
        end.
    end.
    SeenZoneNames =: 0$a:
    for_index. i.#SourceNumbers do.
        if. #index{::SourceZoneLines do. SourceErrors =: (<structural_error index)index}SourceErrors end.
    end.
    for_members. RuleSets do. Sequences =: Sequences,<instance_sequence >members end.
    ZoneNames =: Zones =: AliasNames =: 0$a:
    AliasZones =: 0$0
    BlockDefined =: (#BlockNames)$0
    for_block. i.#BlockNames do.
        if. *./0=#&>(block{::BlockLines){SourceErrors do.
            BlockDefined =: 1 block}BlockDefined
            define_zone block
        end.
    end.
    for_index. I.SourceKinds=<'Link' do.
        if. #index{::SourceErrors do. continue. end.
        fields =. index{::SourceFields
        target =. 1{::fields
        alias =. 2{::fields
        zone_index =. ZoneNames i.<target
        if. zone_index=#ZoneNames do. SourceErrors =: (<'unknown link target ',target)index}SourceErrors
        elseif. ((<alias)e.ZoneNames)+.(<alias)e.AliasNames do. SourceErrors =: (<'duplicate link ',alias)index}SourceErrors
        else.
            AliasNames =: AliasNames,<alias
            AliasZones =: AliasZones,zone_index
            zone =. zone_index{::Zones
            zone =. (<(2{::zone),<alias)2}zone
            Zones =: (<zone)zone_index}Zones
        end.
    end.
    i.0
)
find_zone =: 3 : 0
    index =. ZoneNames i.<y
    if. index<#ZoneNames do. index return. end.
    index =. AliasNames i.<y
    if. index<#AliasNames do. index{AliasZones else. _1 end.
)
error_lines =: 3 : 0
    lines =. 0$a:
    for_index. I.0<#&>SourceErrors do.
        lines =. lines,<'line |: |'format (index{SourceNumbers);index{::SourceErrors
    end.
    lines
)
offset_shift =: 4 : '(1{::y{::x)-1{::(y-1){::x'
transitions_between =: 4 : 0
    'low high' =. y
    indices =. 1+i.(#x)-1
    times =. indices{period_starts x
    indices#~(low<:times)*.times<high
)
change_at =: 4 : 'change_text (0{y{::x),(<(y-1){::x),<y{::x'
transition_line =: 4 : 0
    time =. 0{::y{::x
    shift =. x offset_shift y
    kind =. 'no shift'
    if. shift>0 do. kind =. 'gap ',duration_text shift
    elseif. shift<0 do. kind =. 'overlap ',duration_text -shift end.
    before =. local_text time+1{::(y-1){::x
    after =. local_text time+1{::y{::x
    (x change_at y),' (local ',before,' -> ',after,', ',kind,')'
)
shifts_text =: 4 : 0
    gaps =. overlaps =. unchanged =. 0
    for_index. y do.
        shift =. x offset_shift index
        if. shift>0 do. gaps =. gaps+1
        elseif. shift<0 do. overlaps =. overlaps+1
        else. unchanged =. unchanged+1 end.
    end.
    'gaps |, overlaps |, no shift |'format gaps;overlaps;unchanged
)
candidate_text =: 4 : 0
    'local index' =. y
    period =. index{::x
    (ut_text local-1{::period),' (',(state_text period),')'
)
chosen_candidate =: 4 : 0
    if. (#y)=1 do. {.y
    elseif. (#y)=2 do.
        if. x-:'EARLIER' do. {.y
        elseif. x-:'LATER' do. {:y
        else. _1 end.
    else. _1 end.
)
unresolved_text =: 4 : 0
    'local candidates' =. y
    if. #candidates do.
        'AMBIGUOUS ',(x candidate_text local,0{candidates),' or ',x candidate_text local,1{candidates
    else.
        index =. x skipping_transition local
        time =. 0{::index{::x
        before =. local_text time+1{::(index-1){::x
        after =. local_text time+1{::index{::x
        'NONEXISTENT gap ',before,' to ',after,' at ',ut_text time
    end.
)
working_hours =: 4 : 0
    'start end' =. y
    pieces =. 0 2$0
    for_index. x nearby start,end do.
        period =. index{::x
        low =. (start-1{::period)>.0{::period
        high =. (end-1{::period)<.x end_of index
        if. low<high do. pieces =. pieces,low,high end.
    end.
    merge_intervals pieces
)
parse_value =: 4 : 0
    year =. num 4{.y
    if. (year<1800)+.year>2099 do. PositiveInfinity return. end.
    if. x-:'year' do. year return. end.
    month =. num 2{.5}.y
    day =. num 2{.8}.y
    if. (month<1)+.month>12 do. PositiveInfinity return. end.
    if. (day<1)+.day>days_in_month year,month do. PositiveInfinity return. end.
    if. x-:'date' do. day_number year,month,day return. end.
    hour =. num 2{.11}.y
    minute =. num 2{.14}.y
    second =. num 2{.17}.y
    if. (hour>23)+.(minute>59)+.second>59 do. PositiveInfinity return. end.
    time_value year,month,day,hour,minute,second
)
query_fail =: 3 : 0
    QueryProblem =: y
    throw.
)
to_utc =: 3 : 0
    'zone local option' =. y
    periods =. 4{::zone{::Zones
    candidates =. periods local_candidates local
    index =. option chosen_candidate candidates
    if. index<0 do. periods unresolved_text (<local),<candidates
    else. periods candidate_text local,index end.
)
to_local =: 3 : 0
    'zone time' =. y
    periods =. 4{::zone{::Zones
    period =. (periods index_at time){::periods
    (local_text time+1{::period),' (',(state_text period),')'
)
convert_local =: 3 : 0
    'source target local option' =. y
    periods =. 4{::source{::Zones
    candidates =. periods local_candidates local
    index =. option chosen_candidate candidates
    if. index<0 do. periods unresolved_text (<local),<candidates return. end.
    time =. local-1{::index{::periods
    target_periods =. 4{::target{::Zones
    period =. (target_periods index_at time){::target_periods
    target_local =. time+1{::period
    shift =. (target_local div DaySeconds)-local div DaySeconds
    shift_text =. number shift
    if. shift>0 do. shift_text =. '+',shift_text end.
    (local_text target_local),' (',(state_text period),') at ',(ut_text time),', day shift ',shift_text
)
lookup_offset =: 3 : 0
    'zone time' =. y
    periods =. 4{::zone{::Zones
    index =. periods index_at time
    text =. state_text index{::periods
    if. index do. text =. text,' since ',ut_text 0{::index{::periods end.
    if. (index+1)<#periods do. text =. text,' until ',ut_text 0{::(index+1){::periods end.
    text
)
query_transitions =: 3 : 0
    'query zone first last' =. y
    if. first>last do. query_fail 'invalid range' end.
    periods =. 4{::zone{::Zones
    selected =. periods transitions_between (year_start first),year_start last+1
    block =. <query
    for_index. selected do. block =. block,<periods transition_line index end.
    block =. block,<periods shifts_text selected
    TransitionBlocks =: TransitionBlocks,<block
    'transitions: ',number #selected
)
query_duration =: 3 : 0
    'zone locals words' =. y
    periods =. 4{::zone{::Zones
    offsets =. 0$0
    for_index. i.2 do.
        candidates =. periods local_candidates index{locals
        if. (#candidates)=2 do. 'AMBIGUOUS ',index{::words return. end.
        if. 0=#candidates do. 'NONEXISTENT ',index{::words return. end.
        offsets =. offsets,1{::({.candidates){::periods
    end.
    elapsed =. ((1{locals)-1{offsets)-((0{locals)-0{offsets)
    change =. (1{offsets)-0{offsets
    (number elapsed),' s (',(duration_text elapsed),'), wall clock ',(duration_text (1{locals)-0{locals),', offset change ',offset_text change
)
query_meeting =: 3 : 0
    'day zone_indices words' =. y
    start =. (DaySeconds*day)+WorkStart
    end =. (DaySeconds*day)+WorkEnd
    periods =. 4{::({.zone_indices){::Zones
    common =. periods working_hours start,end
    for_zone. }.zone_indices do.
        periods =. 4{::zone{::Zones
        common =. common intersect_intervals periods working_hours start,end
    end.
    if. 0=#common do. 'NONE' return. end.
    pieces =. 0$a:
    for_interval. common do.
        'low high' =. interval
        members =. 0$a:
        for_index. i.#zone_indices do.
            periods =. 4{::(index{zone_indices){::Zones
            period =. (periods index_at low){::periods
            members =. members,<(index{::words),' ',(local_text low+1{::period),' ',3{::period
        end.
        text =. (ut_text low),' to ',(ut_text high),' (',(duration_text high-low),') [',(', 'join members),']'
        pieces =. pieces,<text
    end.
    '; 'join pieces
)
answer_query =: 3 : 0
    'query command words values option' =. y
    select. command
    case. 'TOUTC' do. to_utc (<0{values),(<1{values),<option
    case. 'TOLOCAL' do. to_local 2{.values
    case. 'CONVERT' do. convert_local (<0{values),(<1{values),(<2{values),<option
    case. 'OFFSET' do. lookup_offset 2{.values
    case. 'TRANSITIONS' do. query_transitions (<query),(<0{values),(<1{values),<2{values
    case. 'DURATION' do. query_duration (<0{values),(<}.values),<}.words
    case. 'MEETING' do. query_meeting (<0{values),(<}.values),<}.words
    end.
)
run_query =: 3 : 0
    fields =. split_fields y
    command =. 0{::fields
    words =. }.fields
    option =. ''
    if. (<command)e.'TOUTC';'CONVERT' do.
        if. ({:words)e.'EARLIER';'LATER' do. option =. >{:words
            words =. }:words end.
    end.
    select. command
    case. 'MEETING' do. kinds =. (<'date'),((#words)-1)$<'zone'
    case. 'CONVERT' do. kinds =. 'zone';'zone';'local'
    case. 'TRANSITIONS' do. kinds =. 'zone';'year';'year'
    case. 'DURATION' do. kinds =. 'zone';'local';'local'
    case. 'TOUTC' do. kinds =. 'zone';'local'
    case. do. kinds =. 'zone';'ut'
    end.
    try.
        values =. 0$0
        for_index. i.#words do.
            word =. index{::words
            kind =. index{::kinds
            if. kind-:'zone' do.
                value =. find_zone word
                if. value<0 do. query_fail 'unknown zone ',word end.
            else.
                value =. kind parse_value word
                if. value=PositiveInfinity do. query_fail 'invalid value ',word end.
            end.
            values =. values,value
        end.
        result =. answer_query (<y),(<command),(<words),(<values),<option
    catcht. result =. 'ERROR ',QueryProblem
    end.
    Answers =: Answers,<y,' => ',result
    i.0
)
zone_rule_sets =: 3 : 0
    names =. 0$a:
    for_line. 1{::y do.
        name =. 2{::>line
        if. #name do.
            if. -.(<name)e.names do. names =. names,<name end.
        end.
    end.
    names
)
rule_text =: 3 : 0
    fields =. 1{::y
    'rule ',(2{::y),' ',(2{::fields),' ',(3{::fields),' ',(5{::fields),' ',(6{::fields),' ',(clock_text 7{::y),(8{::y),' ',(clock_text 9{::y),' ',9{::fields
)
database_block =: 3 : 0
    rule_indices =. I.SourceKinds=<'Rule'
    link_indices =. I.SourceKinds=<'Link'
    valid_rules =. +/0=#&>rule_indices{SourceErrors
    valid_links =. +/0=#&>link_indices{SourceErrors
    used =. 0$a:
    line_count =. 0
    for_zone. Zones do.
        zone =. >zone
        used =. ~.used,zone_rule_sets zone
        line_count =. line_count+#1{::zone
    end.
    unused =. RuleNames#~-.RuleNames e.used
    invalid =. 0$a:
    for_index. I.-.BlockDefined do.
        invalid =. invalid,<'| (line |)'format (index{::BlockNames);index{BlockNumbers
    end.
    lines =. <'DATABASE'
    lines =. lines,<'rule lines: | valid, | invalid'format valid_rules;(#rule_indices)-valid_rules
    lines =. lines,<'zones: | defined, | invalid'format (#Zones);(#BlockNames)-#Zones
    lines =. lines,<'zone lines: | in defined zones'format <line_count
    lines =. lines,<'links: | defined, | invalid'format valid_links;(#link_indices)-valid_links
    lines =. lines,<'errors: |'format <#error_lines''
    lines =. lines,<'unused rules: ',' 'names_or_none unused
    lines =. lines,<'invalid zones: ',(', 'names_or_none invalid)
    for_set. i.#RuleNames do.
        name =. set{::RuleNames
        members =. set{::RuleSets
        first =. 2099
        last =. 1800
        maximum =. 0
        for_index. members do.
            rule =. index{::Rules
            first =. first<.3{::rule
            last =. last>.4{::rule
            maximum =. maximum+.'max'-:3{::1{::rule
        end.
        last_text =. number last
        if. maximum do. last_text =. 'max' end.
        count =. 0
        for_zone. Zones do. count =. count+(<name)e.zone_rule_sets >zone end.
        lines =. lines,<'rule set |: lines |, years |-|, zones |'format name;(#members);first;last_text;count
    end.
    lines
)
dst_lines =: 4 : 0
    year =. 0{split_time y
    minimum =. 2100
    maximum =. 1799
    pieces =. 0 2$0
    for_index. i.#x do.
        period =. index{::x
        if. -.2{::period do. continue. end.
        start_year =. 0{split_time 0{::period
        minimum =. minimum<.start_year
        maximum =. maximum>.start_year
        start =. (year_start year)>.0{::period
        end =. (year_start year+1)<.x end_of index
        if. start<end do. pieces =. pieces,start,end end.
    end.
    lines =. <'dst years: none'
    if. minimum<:maximum do. lines =. <'dst years: |-|'format minimum;maximum end.
    total =. 0
    for_interval. merge_intervals pieces do.
        'start end' =. interval
        lines =. lines,<'dst period: | to | (|)'format (ut_text start);(ut_text end);duration_text end-start
        total =. total+end-start
    end.
    lines,<'dst total |: |'format year;duration_text total
)
zone_block =: 4 : 0
    reference =. x
    'name zone_lines aliases applied periods' =. y
    lines =. (<'ZONE ',name),<'aliases: ',' 'names_or_none aliases
    for_index. i.#zone_lines do.
        line =. index{::zone_lines
        'offset rules_text rule_set save format_text until start end' =. line
        notation =. rule_set
        if. 0=#notation do.
            notation =. '-'
            if. -.rules_text-:'-' do. notation =. clock_text save end.
        end.
        text =. 'line |: | | |'format (index+1);(offset_text offset);notation;format_text
        if. index do. text =. text,' from ',ut_text start end.
        if. #until do.
            notation =. ' 'join (3{.until),<(clock_text 3{::until),4{::until
            text =. text,' until ',notation,' = ',ut_text end
        end.
        count =. #periods transitions_between start,end
        lines =. lines,<text,', transitions ',number count
    end.
    for_rule_set. zone_rule_sets y do.
        set =. RuleNames i.rule_set
        for_index. set{::RuleSets do.
            lines =. lines,<(rule_text index{::Rules),', applied ',number index{applied
        end.
    end.
    offsets =. 0$0
    states =. 0$a:
    state_counts =. 0$0
    for_period. periods do.
        period =. >period
        offsets =. offsets,1{::period
        state =. state_text period
        index =. states i.<state
        if. index=#states do. states =. states,<state
            state_counts =. state_counts,0 end.
        state_counts =. (1+index{state_counts)index}state_counts
    end.
    lines =. lines,<'offset range: | to |'format (offset_text <./offsets);offset_text >./offsets
    for_index. i.#states do. lines =. lines,<'state |, periods |'format (index{::states);index{state_counts end.
    index =. periods index_at reference
    period =. index{::periods
    line_number =. 0
    for_position. i.#zone_lines do.
        line =. position{::zone_lines
        if. ((6{::line)<:reference)*.reference<7{::line do. line_number =. position+1
            break. end.
    end.
    lines =. lines,<'reference: | (|), line |'format (local_text reference+1{::period);(state_text period);line_number
    previous =. next =. 'none'
    if. index do. previous =. periods change_at index end.
    if. (index+1)<#periods do. next =. periods change_at index+1 end.
    lines =. lines,<'previous transition: ',previous
    lines =. lines,<'next transition: ',next
    every =. 1+i.(#periods)-1
    lines =. lines,<'transitions: |, |'format (#every);periods shifts_text every
    lines,periods dst_lines reference
)
main =: 3 : 0
    read_database''
    params =. read_lines 'params.txt'
    reference =. 'ut'parse_value 1{::split_fields 0{::params
    workday =. split_fields 1{::params
    'start end' =. 1 2{workday
    WorkStart =: (3600*num 2{.start)+60*num 2{.3}.start
    WorkEnd =: (3600*num 2{.end)+60*num 2{.3}.end
    Answers =: TransitionBlocks =: 0$a:
    for_query. read_lines 'queries.txt' do. run_query >query end.
    blocks =. <indented database_block''
    for_index. ascii_order ZoneNames do. blocks =. blocks,<indented reference zone_block index{::Zones end.
    1!:5 ::0: <'output'
    'output/answers.txt'write_lines Answers
    'output/errors.txt'write_lines error_lines''
    'output/transitions.txt'write_blocks TransitionBlocks
    'output/zone_summary.txt'write_blocks blocks
    i.0
)
main''
