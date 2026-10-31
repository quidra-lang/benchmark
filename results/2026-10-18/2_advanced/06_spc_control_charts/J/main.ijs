ScriptPath =: >{:4!:3''
SourceDirectory =: (1+>./_1,I.ScriptPath e.'/\'){.ScriptPath
Digits =: '0123456789'
div =: 4 : '_1 x:<.(x:x)%x:y'
real =: 3 : '1.0*y'
num =: 3 : '10#.Digits i.y'
number =: 3 : 0
    if. y<0 do. '-',number -y return. end.
    text =. ''
    while. y>0 do.
        text =. ((10|y){Digits),text
        y =. y div 10
    end.
    if. #text do. text else. '0' end.
)
f4 =: 3 : 0
    negative =. y<!.0 0
    rounded =. <.!.0 ((|y)*10000.0)+0.5
    text =. (number rounded div 10000),'.',_4{.'0000',number 10000|rounded
    if. negative*.rounded~:0 do. '-',text else. text end.
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
text_line =: 3 : 0
    fields =. 0$a:
    for_box. y do.
        value =. >box
        if. 2=3!:0 value do. fields =. fields,<value
        else. fields =. fields,<number value end.
    end.
    ' ' join fields
)
add_line =: 3 : 0
    ReportLines =: ReportLines,<text_line y
    i.0
)
read_lines =: 3 : '<;._2 (1!:1 <''input/'',y)'
empty_table =: 3 : '0 2$a:'
table_keys =: 3 : '0{"1 y'
get_key =: 4 : '((table_keys y)i.<x){::1{"1 y'
put_key =: 4 : 0
    'key value' =. x
    position =. (table_keys y)i.<key
    if. position<#y do. (<value) (<position,1)}y
    else. y,1 2$(<key),<value end.
)
record =: 4 : '('' '' split x),.y'
number_list =: 3 : 0
    if. #y do. ' ' join number&.> <"0 /:~y else. 'none' end.
)
status_text =: 3 : 'y{::''stopped'';''converged'''
limits_text =: 4 : 'x,'' lcl '',(f4 ''lcl'' get_key y),'' cl '',(f4 ''cl'' get_key y),'' ucl '',f4 ''ucl'' get_key y'
load SourceDirectory,'dataset.ijs'
load SourceDirectory,'variable_charts.ijs'
load SourceDirectory,'attribute_charts.ijs'
load SourceDirectory,'run_rules.ijs'
load SourceDirectory,'capability.ijs'
load SourceDirectory,'plot.ijs'
ChartOrder =: ' ' split 'XBAR_R R XBAR_S S I MR CUSUM EWMA MA'
RuleOrder =: ' ' split '1 2 3 4 5 6 7 8 UPPER LOWER'
Families =: ' ' split 'XBAR_R XBAR_S I_MR'
FamilyCharts =: 3 2$' ' split 'XBAR_R R XBAR_S S I MR'
FamilyLabels =: 3 2$' ' split 'XBAR R XBAR S I MR'
LocationCharts =: ' ' split 'XBAR_R XBAR_S I CUSUM EWMA MA'
EventTypes =: ' ' split 'SHIFT_UP SHIFT_DOWN SPREAD_UP SPREAD_DOWN PATTERN'
pair_text =: 4 : 0
    labels =. (Families i.<x){FamilyLabels
    ((0{::labels) limits_text 0{::y),' ',(1{::labels) limits_text 1{::y
)
family_limits =: 4 : 0
    if. x-:'I_MR' do. i_mr_limits (y-1){Values
    elseif. x-:'XBAR_R' do. xbar_r_limits (y-1){Subgroups
    else. xbar_s_limits (y-1){Subgroups end.
)
family_series =: 4 : 0
    if. x-:'I_MR' do.
        values =. (y-1){Values
        (<(<y),<values),<(<}.y),<moving_ranges values
    else.
        groups =. (y-1){Subgroups
        if. x-:'XBAR_R' do. field =. 'range' else. field =. 'sd' end.
        (<(<y),<'mean' subgroup_totals groups),<(<y),<field subgroup_totals groups
    end.
)
estimate_family =: 3 : 0
    count =. Phase1
    if. y-:'I_MR' do. count =. count*Size end.
    initial =. >:i.count
    points =. initial
    passes =. 0$a:
    converged =. 0
    for_pass. >:i.'max_passes' get_key Settings do.
        limits =. y family_limits points
        series =. y family_series points
        outliers =. 0$0
        for_index. i.2 do.
            'numbers values' =. index{::series
            outliers =. outliers,((index{::limits) outside values)#numbers
        end.
        outliers =. /:~~.outliers
        passes =. passes,<'points limits outliers' record (<#points),(<limits),<outliers
        if. 0=#outliers do. converged =. 1
            break.
        end.
        if. pass<'max_passes' get_key Settings do. points =. points-.outliers end.
    end.
    'passes converged limits retained removed' record (<passes),(<converged),(<limits),(<points),<initial-.points
)
chart_limits =: 3 : 0
    position =. ChartOrder i.<y
    family =. (position div 2){::Families
    (2|position){::'limits' get_key family get_key Estimates
)
signal_subgroup =: 3 : 0
    last =. 'end' get_key y
    if. (<'chart' get_key y)e.'I';'MR' do. 1+(last-1) div Size else. last end.
)
event_of =: 3 : 0
    for_box. Events do.
        event =. >box
        if. (y>:'start' get_key event)*.y<:'end' get_key event do. event return. end.
    end.
    empty_table ''
)
has_signal =: 3 : 0
    'chart last rule' =. y
    for_box. Signals do.
        signal =. >box
        if. (chart-:'chart' get_key signal)*.last='end' get_key signal do.
            if. (0=#rule)+.rule-:'rule' get_key signal do. 1 return. end.
        end.
    end.
    0
)
chart_signals =: 4 : 0
    chosen =. 0$a:
    for_box. y do. if. x-:'chart' get_key >box do. chosen =. chosen,box end. end.
    chosen
)
build_events =: 3 : 0
    groups =. 0$0
    for_box. Signals do. groups =. groups,signal_subgroup >box end.
    Events =: 0$a:
    for_group. /:~~.groups do.
        extend =. 0
        if. #Events do. extend =. ((group-('end' get_key >{:Events))-1)<:'event_gap' get_key Settings end.
        if. extend do.
            event =. ((<'end'),<group) put_key >{:Events
            Events =: (<event) (<:#Events)}Events
        else.
            Events =: Events,<'number start end' record (<1+#Events),(<group),<group
        end.
    end.
    for_index. i.#Events do.
        event =. index{::Events
        first =. 'start' get_key event
        last =. 'end' get_key event
        signals =. ((groups>:first)*.groups<:last)#Signals
        counts =. 5$0
        starts =. 0$0
        for_box. signals do.
            signal =. >box
            direction =. 'direction' get_key signal
            chart =. 'chart' get_key signal
            if. direction-:'NONE' do. kind =. 4
            elseif. (<chart)e.LocationCharts do. kind =. -.direction-:'UP'
            else. kind =. 2+-.direction-:'UP' end.
            counts =. (1+kind{counts) kind}counts
            if. chart-:'CUSUM' do. starts =. starts,'start' get_key signal end.
        end.
        onset =. first
        if. #starts do. onset =. <./starts end.
        length =. 1+last-first
        covered =. ((first-1)+i.length){Subgroups
        mean =. (real +/'total' subgroup_totals covered)%real Size*length
        shift =. (mean-Mu0)%Sigma
        spread =. ((real_sum 'sd' subgroup_totals covered)%real length)%Sbar
        values =. 0$0
        for_coveredbox. covered do. values =. values,'values' get_key >coveredbox end.
        outofspec =. +/(values<'lsl' get_key Settings)+.values>'usl' get_key Settings
        detection =. 0$0
        for_chartbox. ChartOrder do.
            selected =. (>chartbox) chart_signals signals
            firstsignal =. 0
            if. #selected do. firstsignal =. <./signal_subgroup&>selected end.
            detection =. detection,firstsignal
        end.
        updates =. 'signals counts kind onset shift spread out_of_spec detection' record (<signals),(<counts),(<(counts i.>./counts){::EventTypes),(<onset),(<shift),(<spread),(<outofspec),<detection
        for_row. updates do. event =. row put_key event end.
        Events =: (<event) index}Events
    end.
    i.0
)
estimate_attribute =: 3 : 0
    lots =. Lots
    passes =. 0$a:
    converged =. 0
    for_pass. >:i.'max_passes' get_key Settings do.
        center =. y center_line lots
        outliers =. 0$0
        for_box. lots do.
            lot =. >box
            point =. center lot_point lot
            if. -.'ok'-:'status' get_key point do. outliers =. outliers,'number' get_key lot end.
        end.
        passes =. passes,<'lots center outliers' record (<#lots),(<'value' get_key center),<outliers
        if. 0=#outliers do. converged =. 1
            break.
        end.
        if. pass<'max_passes' get_key Settings do. lots =. (-.('number' subgroup_totals lots)e.outliers)#lots end.
    end.
    retained =. 'number' subgroup_totals lots
    points =. 0$a:
    for_box. Lots do. points =. points,<center lot_point >box end.
    numbers =. >:i.#Lots
    signals =. check_rules (<y),(<numbers),(<'z' subgroup_totals points),(<new_limits _3 0 3),<'STD' get_key Rules
    'chart passes converged retained removed points signals' record (<y),(<passes),(<converged),(<#retained),(<numbers-.retained),(<points),<signals
)
run_analysis =: 3 : 0
    Subgroups =: subgroup_statistics Values
    Estimates =: empty_table ''
    for_familybox. Families do.
        family =. >familybox
        Estimates =: ((<family),<estimate_family family) put_key Estimates
    end.
    PatternChecks =: 0$a:
    for_familybox. Families do.
        family =. >familybox
        estimate =. family get_key Estimates
        series =. family family_series 'retained' get_key estimate
        charts =. (Families i.<family){FamilyCharts
        limits =. 'limits' get_key estimate
        for_index. i.2 do.
            chart =. index{::charts
            'numbers values' =. index{::series
            signals =. check_rules (<chart),(<numbers),(<values),(index{limits),<chart get_key Rules
            PatternChecks =: PatternChecks,<'chart points signals' record (<chart),(<#values),<signals
        end.
    end.
    Mu0 =: 'cl' get_key chart_limits 'XBAR_R'
    Sigma =: (('cl' get_key chart_limits 'R')%'d2' get_key Constants)% %:real Size
    Reference =: ('cusum_k' get_key Settings)*Sigma
    Interval =: ('cusum_h' get_key Settings)*Sigma
    Sbar =: 'cl' get_key chart_limits 'S'
    Phase2 =: (Phase1+1)+i.(#Subgroups)-Phase1
    samples =. ((Phase1*Size)+1)+i.(#Values)-Phase1*Size
    Signals =: 0$a:
    for_chartbox. 6{.ChartOrder do.
        chart =. >chartbox
        if. (<chart)e.'I';'MR' do.
            numbers =. samples
            observed =. (samples-1){Values
            if. chart-:'MR' do. observed =. |observed-(samples-2){Values end.
        else.
            numbers =. Phase2
            if. (<chart)e.'XBAR_R';'XBAR_S' do. field =. 'mean'
            elseif. chart-:'R' do. field =. 'range'
            else. field =. 'sd' end.
            observed =. field subgroup_totals (numbers-1){Subgroups
        end.
        Signals =: Signals,check_rules (<chart),(<numbers),(<observed),(<chart_limits chart),<chart get_key Rules
    end.
    upper =. lower =. 0.0
    upperrun =. lowerrun =. 0
    Cusum =: Ewma =: MovingAverage =: 0$a:
    smoothed =. Mu0
    factor =. 1.0
    lambda =. 'ewma_lambda' get_key Settings
    decay =. (1.0-lambda)*(1.0-lambda)
    ratio =. lambda%(2.0-lambda)
    ewsigma =. ('ewma_l' get_key Settings)*Sigma
    EwmaWidth =: ewsigma*%:ratio
    MaWidth =: (3.0*Sigma)% %:real 'ma_span' get_key Settings
    for_groupnumber. Phase2 do.
        group =. (groupnumber-1){::Subgroups
        mean =. 'mean' get_key group
        upper =. 0.0>.upper+((mean-Mu0)-Reference)
        lower =. 0.0>.lower+((Mu0-mean)-Reference)
        if. upper>!.0 0 do. upperrun =. upperrun+1 else. upperrun =. 0 end.
        if. lower>!.0 0 do. lowerrun =. lowerrun+1 else. lowerrun =. 0 end.
        Cusum =: Cusum,<'subgroup upper lower' record (<groupnumber),(<upper),<lower
        if. upper>!.0 Interval do.
            Signals =: Signals,<new_signal (<'CUSUM'),(<'UPPER'),(<1+groupnumber-upperrun),(<groupnumber),(<upper),<'UP'
            upper =. 0.0
            upperrun =. 0
        end.
        if. lower>!.0 Interval do.
            Signals =: Signals,<new_signal (<'CUSUM'),(<'LOWER'),(<1+groupnumber-lowerrun),(<groupnumber),(<lower),<'DOWN'
            lower =. 0.0
            lowerrun =. 0
        end.
        smoothed =. (lambda*mean)+((1.0-lambda)*smoothed)
        factor =. factor*decay
        width =. ewsigma*%:ratio*(1.0-factor)
        ewma =. 'subgroup value width lcl ucl' record (<groupnumber),(<smoothed),(<width),(<Mu0-width),<Mu0+width
        Ewma =: Ewma,<ewma
        first =. (Phase1+1)>.1+groupnumber-'ma_span' get_key Settings
        count =. 1+groupnumber-first
        groups =. ((first-1)+i.count){Subgroups
        total =. +/'total' subgroup_totals groups
        width =. (3.0*Sigma)% %:real count
        value =. (real total)%real Size*count
        ma =. 'subgroup value width lcl ucl' record (<groupnumber),(<value),(<width),(<Mu0-width),<Mu0+width
        MovingAverage =: MovingAverage,<ma
        for_index. i.2 do.
            chart =. index{::'EWMA';'MA'
            point =. index{::(<ewma),<ma
            start =. index{groupnumber,first
            value =. 'value' get_key point
            if. value>!.0 'ucl' get_key point do. direction =. 'UP'
                rule =. 'UPPER'
            elseif. value<!.0 'lcl' get_key point do. direction =. 'DOWN'
                rule =. 'LOWER'
            else. continue. end.
            Signals =: Signals,<new_signal (<chart),(<rule),(<start),(<groupnumber),(<value),<direction
        end.
    end.
    keys =. 0 3$0
    for_box. Signals do.
        signal =. >box
        keys =. keys,((ChartOrder i.<'chart' get_key signal),('end' get_key signal),RuleOrder i.<'rule' get_key signal)
    end.
    Signals =: (/:keys){Signals
    build_events ''
    free =. 0$0
    for_groupnumber. Phase2 do. if. 0=#event_of groupnumber do. free =. free,groupnumber end. end.
    Proposals =: 0$a:
    for_familybox. Families do.
        family =. >familybox
        added =. free
        if. family-:'I_MR' do.
            added =. 0$0
            for_groupnumber. free do. added =. added,((groupnumber-1)*Size)+>:i.Size end.
        end.
        numbers =. ('retained' get_key family get_key Estimates),added
        Proposals =: Proposals,<'family points limits' record (<family),(<#numbers),<family family_limits numbers
    end.
    AttributeResults =: estimate_attribute&.>AttributeCharts
    CapabilityGroups =: 0$a:
    for_namebox. 'phase1';'phase2' do.
        name =. >namebox
        if. name-:'phase1' do. numbers =. 'retained' get_key 'XBAR_R' get_key Estimates else. numbers =. Phase2 end.
        groups =. (numbers-1){Subgroups
        CapabilityGroups =: CapabilityGroups,<'name subgroups result' record (<name),(<groups),<capability groups
    end.
    Rolling =: 0$a:
    first =. Phase1+1
    length =. 'rolling_window' get_key Settings
    while. (first+length-1)<:#Subgroups do.
        last =. first+length-1
        groups =. ((first-1)+i.length){Subgroups
        Rolling =: Rolling,<'first last result' record (<first),(<last),<capability groups
        first =. first+'rolling_step' get_key Settings
    end.
    i.0
)
limits_lines =: 3 : 0
    ReportLines =: 0$a:
    add_line (<'characteristic'),<'characteristic' get_key Settings
    add_line (<'subgroup_size'),<Size
    add_line (<'subgroups'),<#Subgroups
    add_line (<'samples'),<#Values
    add_line (<'phase1_subgroups'),<Phase1
    for_familybox. Families do.
        family =. >familybox
        estimate =. family get_key Estimates
        add_line (<'family'),<family
        passes =. 'passes' get_key estimate
        for_index. i.#passes do.
            pass =. index{::passes
            add_line (<'pass'),(<index+1),(<'points'),(<'points' get_key pass),(<family pair_text 'limits' get_key pass),(<'out'),<number_list 'outliers' get_key pass
        end.
        add_line (<'result'),(<status_text 'converged' get_key estimate),(<'passes'),(<#passes),(<'retained'),(<#'retained' get_key estimate),(<'removed'),<number_list 'removed' get_key estimate
    end.
    for_box. PatternChecks do.
        check =. >box
        chart =. 'chart' get_key check
        signals =. 'signals' get_key check
        for_signalbox. signals do.
            signal =. >signalbox
            add_line (<'phase1_signal'),(<chart),(<'rule' get_key signal),(<'start' get_key signal),(<'end' get_key signal),<f4 'value' get_key signal
        end.
        add_line (<'phase1_check'),(<chart),(<'points'),(<'points' get_key check),(<'signals'),<#signals
    end.
    for_box. Proposals do.
        proposal =. >box
        family =. 'family' get_key proposal
        add_line (<'proposed'),(<family),(<'points'),(<'points' get_key proposal),<family pair_text 'limits' get_key proposal
    end.
    target =. 'target ',(f4 Mu0),' sigma ',f4 Sigma
    add_line (<'cusum'),(<target),(<'k'),(<f4 Reference),(<'h'),<f4 Interval
    add_line (<'ewma'),(<target),(<'lcl'),(<f4 Mu0-EwmaWidth),(<'ucl'),<f4 Mu0+EwmaWidth
    add_line (<'ma'),(<target),(<'span'),(<'ma_span' get_key Settings),(<'lcl'),(<f4 Mu0-MaWidth),(<'ucl'),<f4 Mu0+MaWidth
    for_chartbox. ChartOrder do.
        chart =. >chartbox
        signals =. chart chart_signals Signals
        ends =. ~.'end' subgroup_totals signals
        if. (<chart)e.'I';'MR' do. points =. (#Values)-Phase1*Size else. points =. (#Subgroups)-Phase1 end.
        if. (<chart)e.6{.ChartOrder do. rules =. number&.><"0 chart get_key Rules else. rules =. 'UPPER';'LOWER' end.
        counts =. 0$a:
        for_rulebox. rules do.
            count =. 0
            for_signalbox. signals do. count =. count+(>rulebox)-:'rule' get_key >signalbox end.
            counts =. counts,<(>rulebox),':',number count
        end.
        first =. 'none'
        if. #ends do. first =. number <./ends end.
        add_line (<'phase2'),(<chart),(<'points'),(<points),(<'signals'),(<#signals),(<'signalled'),(<#ends),(<'first'),(<first),(<'by_rule'),<' ' join counts
    end.
    ReportLines
)
signal_lines =: 3 : 0
    lines =. <'chart,rule,start,end,value,direction'
    for_box. Signals do.
        signal =. >box
        fields =. (<'chart' get_key signal),(<'rule' get_key signal),(<number 'start' get_key signal),(<number 'end' get_key signal),(<f4 'value' get_key signal),<'direction' get_key signal
        lines =. lines,<',' join fields
    end.
    lines
)
event_lines =: 3 : 0
    ReportLines =: 0$a:
    add_line (<'events'),<#Events
    for_box. Events do.
        event =. >box
        counts =. 'counts' get_key event
        detection =. 'detection' get_key event
        first =. 'start' get_key event
        last =. 'end' get_key event
        add_line (<'event'),(<'number' get_key event),(<'start'),(<first),(<'end'),(<last),(<'length'),(<1+last-first),(<'signals'),(<#'signals' get_key event),(<'charts'),(<',' join (detection>0)#ChartOrder),(<'location_up'),(<0{counts),(<'location_down'),(<1{counts),(<'spread_up'),(<2{counts),(<'spread_down'),(<3{counts),(<'pattern'),(<4{counts),(<'onset'),(<'onset' get_key event),(<'shift'),(<f4 'shift' get_key event),(<'spread'),(<f4 'spread' get_key event),(<'out_of_spec'),(<'out_of_spec' get_key event),(<'type'),<'kind' get_key event
        fields =. 0$a:
        for_index. i.#ChartOrder do.
            value =. '-'
            if. index{detection do. value =. number index{detection end.
            fields =. fields,<(index{::ChartOrder),':',value
        end.
        add_line (<'detection'),(<'number' get_key event),<' ' join fields
    end.
    ReportLines
)
zone_name =: 4 : 0
    if. y>!.0 'ucl' get_key x do. 'OUT+'
    elseif. y<!.0 'lcl' get_key x do. 'OUT-'
    elseif. y>!.0 'u2' get_key x do. 'A+'
    elseif. y>!.0 'u1' get_key x do. 'B+'
    elseif. y>!.0 'cl' get_key x do. 'C+'
    elseif. y<!.0 'l2' get_key x do. 'A-'
    elseif. y<!.0 'l1' get_key x do. 'B-'
    elseif. y<!.0 'cl' get_key x do. 'C-'
    else. 'C0' end.
)
subgroup_lines =: 3 : 0
    lines =. <'subgroup,phase,mean,zone,range,sd,cusum_upper,cusum_lower,ewma,ma,signals,event'
    zone =. zones chart_limits 'XBAR_R'
    groups =. 0$0
    for_box. Signals do. groups =. groups,signal_subgroup >box end.
    removed =. 'removed' get_key 'XBAR_R' get_key Estimates
    for_box. Subgroups do.
        group =. >box
        groupnumber =. 'number' get_key group
        if. groupnumber>Phase1 do.
            phase =. 'phase2'
            index =. groupnumber-(Phase1+1)
            cusum =. index{::Cusum
            monitored =. (<f4 'upper' get_key cusum),(<f4 'lower' get_key cusum),(<f4 'value' get_key index{::Ewma),<f4 'value' get_key index{::MovingAverage
        else.
            phase =. (groupnumber e.removed){::'phase1';'excluded'
            monitored =. 4#<'-'
        end.
        event =. event_of groupnumber
        eventnumber =. '-'
        if. #event do. eventnumber =. number 'number' get_key event end.
        fields =. (<number groupnumber),(<phase),(<f4 'mean' get_key group),(<zone zone_name 'mean' get_key group),(<number 'range' get_key group),(<f4 'sd' get_key group),monitored,(<number +/groups=groupnumber),<eventnumber
        lines =. lines,<',' join fields
    end.
    lines
)
attribute_lines =: 3 : 0
    ReportLines =: 0$a:
    for_box. AttributeResults do.
        result =. >box
        chart =. 'chart' get_key result
        add_line (<'chart'),<chart
        passes =. 'passes' get_key result
        for_index. i.#passes do.
            pass =. index{::passes
            add_line (<'pass'),(<index+1),(<'lots'),(<'lots' get_key pass),(<'center'),(<f4 'center' get_key pass),(<'out'),<number_list 'outliers' get_key pass
        end.
        add_line (<'result'),(<status_text 'converged' get_key result),(<'passes'),(<#passes),(<'retained'),(<'retained' get_key result),(<'removed'),<number_list 'removed' get_key result
        points =. 'points' get_key result
        for_index. i.#Lots do.
            lot =. index{::Lots
            point =. index{::points
            if. (<chart)e.'np';'c' do. value =. number 'value' get_key point else. value =. f4 'value' get_key point end.
            add_line (<'lot'),(<'number' get_key lot),(<'size'),(<'inspected' get_key lot),(<'value'),(<value),(<'lcl'),(<f4 'lcl' get_key point),(<'ucl'),(<f4 'ucl' get_key point),(<'z'),(<f4 'z' get_key point),(<'status'),<'status' get_key point
        end.
        signals =. 'signals' get_key result
        for_signalbox. signals do.
            signal =. >signalbox
            add_line (<'signal'),(<'rule' get_key signal),(<'start' get_key signal),(<'end' get_key signal),<f4 'value' get_key signal
        end.
        add_line (<'signals'),<#signals
    end.
    ReportLines
)
capability_lines =: 3 : 0
    ReportLines =: 0$a:
    fields =. ' ' split 'mean sigma_within sigma_sbar sigma_overall cp cpu cpl cpk pp ppu ppl ppk cpm'
    for_box. CapabilityGroups do.
        group =. >box
        result =. 'result' get_key group
        subgroups =. 'subgroups' get_key group
        add_line (<'group'),(<'name' get_key group),(<'subgroups'),(<#subgroups),(<'values'),<'count' get_key result
        for_fieldbox. fields do. add_line fieldbox,<f4 (>fieldbox) get_key result end.
        for_fieldbox. 'cpk_ci';'ppk_ci' do. add_line fieldbox, f4&.><"0 (>fieldbox) get_key result end.
        add_line (<'below_lsl'),<'below' get_key result
        add_line (<'above_usl'),<'above' get_key result
        add_line (<'ppm'),<f4 'ppm' get_key result
        for_subgroupbox. subgroups do.
            subgroup =. >subgroupbox
            values =. 'values' get_key subgroup
            groupnumber =. 'number' get_key subgroup
            for_position. i.#values do.
                value =. position{values
                if. value<'lsl' get_key Settings do. side =. 'low'
                elseif. value>'usl' get_key Settings do. side =. 'high'
                else. continue. end.
                sample =. (position+1)+(groupnumber-1)*Size
                add_line (<'out_of_spec sample'),(<sample),(<'subgroup'),(<groupnumber),(<'value'),(<value),(<'side'),<side
            end.
        end.
        add_line (<'verdict'),<'verdict' get_key result
        for_binbox. 'bins' get_key result do.
            bin =. >binbox
            parts =. (<'bin'),(<'lower' get_key bin),(<'upper' get_key bin),<'frequency' get_key bin
            length =. 'length' get_key bin
            if. length do. parts =. parts,<length#'#' end.
            add_line parts,'marks' get_key bin
        end.
    end.
    for_box. Rolling do.
        window =. >box
        result =. 'result' get_key window
        add_line (<'rolling'),(<'first' get_key window),(<'last' get_key window),(<'mean'),(<f4 'mean' get_key result),(<'sigma_within'),(<f4 'sigma_within' get_key result),(<'sigma_overall'),(<f4 'sigma_overall' get_key result),(<'cpk'),(<f4 'cpk' get_key result),(<'ppk'),(<f4 'ppk' get_key result),(<'verdict'),<'verdict' get_key result
    end.
    ReportLines
)
pad3 =: 3 : '_3{.''   '',number y'
chart_lines =: 3 : 0
    ReportLines =: 0$a:
    for_chartbox. 'XBAR';'R';'S' do.
        chart =. >chartbox
        if. chart-:'XBAR' do. signalchart =. 'XBAR_R'
            field =. 'mean'
        elseif. chart-:'R' do. signalchart =. 'R'
            field =. 'range'
        else. signalchart =. 'S'
            field =. 'sd' end.
        if. chart-:'S' do. family =. 'XBAR_S' else. family =. 'XBAR_R' end.
        removed =. 'removed' get_key family get_key Estimates
        limits =. chart_limits signalchart
        add_line <('chart ',chart) limits_text limits
        for_box. Subgroups do.
            group =. >box
            groupnumber =. 'number' get_key group
            if. groupnumber>Phase1 do. mark =. '2' else. mark =. (groupnumber e.removed){::'1';'x' end.
            signalled =. (groupnumber>Phase1)*.has_signal (<signalchart),(<groupnumber),<''
            value =. field get_key group
            add_line (<pad3 groupnumber),(<mark),(<limits limits_band (<value),<signalled),<f4 value
        end.
    end.
    add_line (<'chart CUSUM h'),<f4 Interval
    for_box. Cusum do.
        point =. >box
        groupnumber =. 'subgroup' get_key point
        uppersignal =. has_signal (<'CUSUM'),(<groupnumber),<'UPPER'
        lowersignal =. has_signal (<'CUSUM'),(<groupnumber),<'LOWER'
        band =. cusum_band (<'upper' get_key point),(<'lower' get_key point),(<Interval),(<uppersignal),<lowersignal
        add_line (<pad3 groupnumber),(<band),(<f4 'upper' get_key point),<f4 'lower' get_key point
    end.
    for_index. i.2 do.
        chart =. index{::'EWMA';'MA'
        scale =. index{EwmaWidth,MaWidth
        points =. index{::(<Ewma),<MovingAverage
        add_line <('chart ',chart) limits_text new_limits (Mu0-scale),Mu0,Mu0+scale
        for_box. points do.
            point =. >box
            groupnumber =. 'subgroup' get_key point
            signalled =. has_signal (<chart),(<groupnumber),<''
            band =. width_band (<scale),(<'width' get_key point),(<'value' get_key point),(<Mu0),<signalled
            add_line (<pad3 groupnumber),(<band),(<f4 'value' get_key point),(<f4 'lcl' get_key point),<f4 'ucl' get_key point
        end.
    end.
    pictures =. ' ' split 'P_STD NP_STD C_STD U_STD'
    for_index. i.4 do.
        add_line <('chart ',index{::pictures) limits_text new_limits _3 0 3
        result =. index{::AttributeResults
        points =. 'points' get_key result
        for_lotindex. i.#Lots do.
            point =. lotindex{::points
            value =. 'z' get_key point
            band =. value standard_band 'ok'-:'status' get_key point
            add_line (<pad3 'number' get_key lotindex{::Lots),(<band),<f4 value
        end.
    end.
    ReportLines
)
write_report =: 4 : 0
    ((LF join y),LF) 1!:2 <'output/',x
    i.0
)
main =: 3 : 0
    read_dataset ''
    run_analysis ''
    1!:5 <'output'
    'limits.txt' write_report limits_lines ''
    'signals.csv' write_report signal_lines ''
    'events.txt' write_report event_lines ''
    'subgroups.csv' write_report subgroup_lines ''
    'attribute_charts.txt' write_report attribute_lines ''
    'capability.txt' write_report capability_lines ''
    'charts.txt' write_report chart_lines ''
    i.0
)
main ''
