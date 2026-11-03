LF =: 10{a.
Output =: 0$a:
num =: 3 : ',''0'' 8!:2 y'
emit =: 3 : 'Output=:Output,<y'
join =: 4 : '(#x)}.;(<x),&.>y'
fail =: 3 : 0
    Reason=:y
    throw.
)
check =: 4 : 'if. -.y do. fail x end.'
split =: 4 : 0
    result=.0$a:
    start=.0
    for_i. i.#y do.
        if. x=i{y do. result=.result,<(i-start){.start}.y
            start=.i+1 end.
    end.
    result,<start}.y
)
signedText =: 3 : 'if. y>:0 do. ''+'',num y else. num y end.'
zpad =: 4 : '(-x){.(x#''0''),num y'
decimals =: 4 : 0
    cents=.<.(100x*x)%y
    (num <.cents%100),'.',2 zpad 100|cents
)
nameList =: 3 : 'if. #y do. '' ''join /:~y else. ''none'' end.'
leap =: 3 : '(0=400|y)+.(0=4|y)*.0~:100|y'
monthLengths =: 3 : '(28+leap y)1}31 28 31 30 31 30 31 31 30 31 30 31'
parseDate =: 3 : 0
    year=.0".4{.y
    month=.0".2{.5}.y
    day=.0".8}.y
    ('invalid date ',y)check (month>:1)*.month<:12
    lengths=.monthLengths year
    ('invalid date ',y)check (day>:1)*.day<:(month-1){lengths
    result=.<:day
    for_yr. 2000+i.year-2000 do. result=.result+365+leap yr end.
    result++/(month-1){.lengths
)
dateText =: 3 : 0
    year=.2000
    rest=.y
    while. rest>:365+leap year do. rest=.rest-365+leap year
        year=.year+1 end.
    lengths=.monthLengths year
    month=.0
    while. rest>:month{lengths do. rest=.rest-month{lengths
        month=.month+1 end.
    (4 zpad year),'-',(2 zpad month+1),'-',(2 zpad rest+1),' ',(7|y+5){::;:'Mon Tue Wed Thu Fri Sat Sun'
)
getTask =: 3 : '(Names i.<y){::Tasks'
requireTask =: 3 : '(''unknown task '',y)check (<y)e.Names'
duration =: 3 : '(0{::y)-6{::y'
orderedNames =: 3 : '/:~Names'
predLinks =: 3 : 0
    result=.0$a:
    for_other. orderedNames'' do.
        for_dep. Dependencies do.
            dep=.>dep
            if. ((0{::dep)-:>other)*.(1{::dep)-:y do. result=.result,<dep end.
        end.
    end.
    result
)
succLinks =: 3 : 0
    result=.0$a:
    for_other. orderedNames'' do.
        for_dep. Dependencies do.
            dep=.>dep
            if. ((0{::dep)-:y)*.(1{::dep)-:>other do. result=.result,<dep end.
        end.
    end.
    result
)
topological =: 3 : 0
    pending=.orderedNames''
    result=.0$a:
    while. #pending do.
        selected=.''
        for_name. pending do.
            ready=.1
            for_dep. predLinks >name do.
                if. (<0{::>dep)e.pending do. ready=.0 break. end.
            end.
            if. ready do. selected=.>name break. end.
        end.
        if. 0=#selected do. result return. end.
        result=.result,<selected
        pending=.pending-.<selected
    end.
    result
)
cycleNotation =: 3 : 0
    remaining=.(orderedNames'')-.y
    walk=.,{.remaining
    while. 1 do.
        previous=.''
        for_dep. predLinks >{:walk do.
            if. (<0{::>dep)e.remaining do. previous=.0{::>dep break. end.
        end.
        at=.walk i.<previous
        if. at<#walk do.
            cycle=.(<previous),|.(at+1)}.walk
            first=.{./:cycle
            cycle=.(first}.cycle),first{.cycle
            ' -> 'join cycle,{.cycle return.
        end.
        walk=.walk,<previous
    end.
)
analysisOrder =: 3 : 0
    'no tasks'check 0<#Names
    result=.topological''
    if. (#result)<#Names do. fail 'cycle ',cycleNotation result end.
    result
)
startBound =: 3 : 0
    'dep names starts finishes d'=.y
    at=.names i.<0{::dep
    lag=.3{::dep
    kind=.2{::dep
    if. kind-:'FS' do. lag+at{finishes
    elseif. kind-:'SS' do. lag+at{starts
    else. lag+(at{finishes)-d end.
)
finishBound =: 3 : 0
    'dep names starts finishes d'=.y
    at=.names i.<1{::dep
    lag=.3{::dep
    kind=.2{::dep
    if. kind-:'FS' do. (at{starts)-lag
    elseif. kind-:'SS' do. d+(at{starts)-lag
    else. (at{finishes)-lag end.
)
margin =: 4 : 0
    names=.0{::x
    a=.names i.<0{::y
    b=.names i.<1{::y
    kind=.2{::y
    lag=.3{::y
    if. kind-:'FS' do. (b{2{::x)-(a{3{::x)+lag
    elseif. kind-:'SS' do. (b{2{::x)-(a{2{::x)+lag
    else. (b{3{::x)-(a{3{::x)+lag end.
)
calcSchedule =: 3 : 0
    'order changed replacement'=.y
    names=.orderedNames''
    d=.i.0
    for_name. names do.
        if. changed-:>name do. value=.replacement else. value=.duration getTask >name end.
        d=.d,value
    end.
    es=.ef=.ls=.lf=.(#names)$0
    for_name. order do.
        name=.>name
        at=.names i.<name
        start=.3{::getTask name
        for_dep. predLinks name do. start=.start>.startBound (< >dep),(<names),(<es),(<ef),<at{d end.
        es=.start at}es
        ef=.(start+at{d)at}ef
    end.
    length=.>./ef
    for_name. |.order do.
        name=.>name
        at=.names i.<name
        finish=.length
        for_dep. succLinks name do. finish=.finish<.finishBound (< >dep),(<names),(<ls),(<lf),<at{d end.
        lf=.finish at}lf
        ls=.(finish-at{d)at}ls
    end.
    tf=.ls-es
    ff=.length-ef
    result=.(<names),(<d),(<es),(<ef),(<ls),(<lf),(<tf),(<ff),<length
    for_name. names do.
        at=.names i.name
        value=.at{ff
        for_dep. succLinks >name do. value=.value<.result margin >dep end.
        ff=.value at}ff
    end.
    (<ff)7}result
)
criticalNames =: 3 : '(0{::y)#~0=6{::y'
scheduleFields =: 4 : 0
    at=.(0{::x)i.<y
    at&{&>2 3 4 5 6 7{x
)
byStart =: 3 : 0
    names=.0{::y
    names{~/:2{::y
)
criticalWalk =: 4 : 0
    result=.0$a:
    name=.>{:y
    critical=.criticalNames x
    for_dep. succLinks name do.
        dep=.>dep
        if. ((<1{::dep)e.critical)*.0=x margin dep do. result=.result,x criticalWalk y,<1{::dep end.
    end.
    if. #result do. result else. ,<y end.
)
criticalPaths =: 3 : 0
    critical=.criticalNames y
    result=.0$a:
    for_name. critical do.
        root=.1
        for_dep. predLinks >name do.
            dep=.>dep
            if. ((<0{::dep)e.critical)*.0=y margin dep do. root=.0 end.
        end.
        if. root do. result=.result,y criticalWalk ,name end.
    end.
    result
)
resources =: 3 : 0
    result=.0$a:
    for_task. Tasks do. result=.result,<1{::>task end.
    /:~~.result
)
usage =: 3 : 0
    'resource names starts finishes length'=.y
    result=.length$0
    for_i. i.#names do.
        task=.getTask i{::names
        if. -.resource-:1{::task do. continue. end.
        for_day. (i{starts)+i.(i{finishes)-i{starts do. result=.((day{result)+2{::task)day}result end.
    end.
    result
)
working =: 3 : '(5>7|y+5)*.-.y e.Holidays'
workingDates =: 3 : 0
    result=.i.0
    day=.StartDate
    while. (#result)<y do.
        if. working day do. result=.result,day end.
        day=.day+1
    end.
    result
)
workBetween =: 4 : 0
    total=.0
    for_day. (x+1)+i.y-x do. total=.total+working day end.
    total
)
capacityFor =: 4 : 0
    at=.CapacityNames i.<y
    if. at<#CapacityNames do. at{CapacityValues else. x end.
)
calendarReport =: 3 : 0
    dates=.workingDates 8{::y
    names=.0{::y
    for_name. byStart y do.
        at=.names i.name
        emit (>name),' ',(dateText (at{2{::y){dates),' - ',dateText (<:at{3{::y){dates
    end.
    first=.{.dates
    last=.{:dates
    emit 'project ',(dateText first),' - ',(dateText last),', ',(num 8{::y),' working days, ',(num 1+last-first),' calendar days'
    if. Deadline>:0 do.
        if. last<:Deadline do. emit 'deadline ',(dateText Deadline),' met, ',(num last workBetween Deadline),' working days to spare'
        else. emit 'deadline ',(dateText Deadline),' missed by ',(num Deadline workBetween last),' working days' end.
    end.
    spanned=.0$a:
    for_day. /:~Holidays do.
        if. (day>:first)*.(day<:last)*.5>7|day+5 do. spanned=.spanned,<dateText day end.
    end.
    text=.'none'
    if. #spanned do. text=.', 'join spanned end.
    emit 'holidays in span: ',text
)
levelReport =: 4 : 0
    names=.0{::x
    for_name. names do.
        task=.getTask >name
        capacity=.y capacityFor 1{::task
        ('capacity ',(num capacity),' too small for ',>name)check (2{::task)<:capacity
    end.
    decided=.0$a:
    starts=.finishes=.(#names)$0
    while. (#decided)<#names do.
        chosen=.''
        for_name. names do.
            if. name e.decided do. continue. end.
            ready=.1
            for_dep. predLinks >name do. if. -.(<0{::>dep)e.decided do. ready=.0 end. end.
            if. ready do.
                if. 0=#chosen do. chosen=.>name
                elseif. ((names i.name){4{::x)<(names i.<chosen){4{::x do. chosen=.>name end.
            end.
        end.
        at=.names i.<chosen
        task=.getTask chosen
        d=.duration task
        start=.3{::task
        for_dep. predLinks chosen do. start=.start>.startBound (< >dep),(<names),(<starts),(<finishes),<d end.
        while. 1 do.
            available=.1
            for_day. start+i.d do.
                used=.0
                for_name. decided do.
                    other=.names i.name
                    old=.getTask >name
                    if. ((1{::old)-:1{::task)*.(day>:other{starts)*.day<other{finishes do. used=.used+2{::old end.
                end.
                if. (used+2{::task)>y capacityFor 1{::task do. available=.0 break. end.
            end.
            if. available do. break. end.
            start=.start+1
        end.
        starts=.start at}starts
        finishes=.(start+d)at}finishes
        decided=.decided,<chosen
    end.
    length=.>./finishes
    emit 'level capacity ',(num y),': duration ',(num 8{::x),' -> ',num length
    for_name. decided do. at=.names i.name
        emit (>name),' start ',(num at{starts),' finish ',(num at{finishes),' shift ',num (at{starts)-at{2{::x end.
    for_resource. resources'' do.
        before=.>./usage (< >resource),(<names),(<2{::x),(<3{::x),<8{::x
        after=.>./usage (< >resource),(<names),(<starts),(<finishes),<length
        emit 'resource ',(>resource),' capacity ',(num y capacityFor >resource),' peak ',(num before),' -> ',num after
    end.
)
crashProject =: 4 : 0
    order=.x
    remaining=.y
    steps=.0
    result=.calcSchedule (<order),(<' '),<0
    initial=.8{::result
    reason=.''
    while. 1 do.
        chosen=.''
        for_name. orderedNames'' do.
            task=.getTask >name
            if. (-.name e.criticalNames result)+.((4{::task)<0)+.(6{::task)>:4{::task do. continue. end.
            changed=.calcSchedule (<order),name,<<:duration task
            if. (8{::changed)<8{::result do.
                if. 0=#chosen do. chosen=.>name
                elseif. (5{::task)<5{::getTask chosen do. chosen=.>name end.
            end.
        end.
        if. 0=#chosen do. reason=.'no candidate' break. end.
        task=.getTask chosen
        cost=.5{::task
        if. cost>remaining do. reason=.'insufficient budget' break. end.
        old=.duration task
        task=.(<1+6{::task)6}task
        Tasks=:(<task)(Names i.<chosen)}Tasks
        remaining=.remaining-cost
        steps=.steps+1
        result=.calcSchedule (<order),(<' '),<0
        emit 'step ',(num steps),': ',chosen,' ',(num old),' -> ',(num duration task),', cost ',(num cost),', project ',num 8{::result
    end.
    emit 'crash done: ',(num steps),' days, cost ',(num y-remaining),', project ',(num initial),' -> ',(num 8{::result),', budget left ',(num remaining),', ',reason
)
execute =: 3 : 0
    words=.' 'split y
    command=.0{::words
    args=.}.words
    select. command
    case. 'TASK' do.
        name=.0{::args
        ('task ',name,' already exists')check -.(<name)e.Names
        task=.(<0".1{::args),(2{args),(<0".3{::args),(<0),(<_1),(<0),(<0),<i.0
        Names=:Names,<name
        Tasks=:Tasks,<task
        emit 'task ',name,' added'
    case. 'DEP';'UNDEP' do.
        a=.0{::args
        b=.1{::args
        requireTask a
        requireTask b
        at=.#Dependencies
        for_i. i.#Dependencies do.
            dep=.i{::Dependencies
            if. ((0{::dep)-:a)*.(1{::dep)-:b do. at=.i break. end.
        end.
        if. command-:'DEP' do.
            ('self dependency ',a)check -.a-:b
            ('dependency ',a,' -> ',b,' already exists')check at=#Dependencies
            lag=.0".3{::args
            dep=.(<a),(<b),(2{args),<lag
            Dependencies=:Dependencies,<dep
            emit 'dependency ',a,' -> ',b,' ',(2{::args),(signedText lag),' added'
        else.
            ('no dependency ',a,' -> ',b)check at<#Dependencies
            Dependencies=:Dependencies#~(i.#Dependencies)~:at
            emit 'dependency ',a,' -> ',b,' removed'
        end.
    case. 'REMOVE' do.
        name=.0{::args
        requireTask name
        kept=.0$a:
        removed=.0
        for_dep. Dependencies do.
            dep=.>dep
            if. ((0{::dep)-:name)+.(1{::dep)-:name do. removed=.removed+1 else. kept=.kept,<dep end.
        end.
        Dependencies=:kept
        mask=.Names~:<name
        Names=:mask#Names
        Tasks=:mask#Tasks
        emit 'task ',name,' removed with ',(num removed),' dependencies'
    case. 'NOTBEFORE';'CRASHCOST';'UNCRASH';'PERT' do.
        name=.0{::args
        requireTask name
        task=.getTask name
        select. command
        case. 'NOTBEFORE' do. task=.(<0".1{::args)3}task
            emit 'notbefore ',name,' ',1{::args
        case. 'CRASHCOST' do.
            limit=.0".1{::args
            ('crash limit too large for ',name)check limit<0{::task
            ('crash limit below used days for ',name)check limit>:6{::task
            task=.(<limit)4}task
            task=.(<0".2{::args)5}task
            emit 'crash ',name,' max ',(num limit),' cost ',2{::args
        case. 'UNCRASH' do.
            emit 'uncrash ',name,' restored ',(num 6{::task),' days'
            task=.(<0)6}task
        case. 'PERT' do.
            estimate=.0".&>}.args
            'invalid estimate'check *./(}:estimate)<:}.estimate
            'o m p'=.estimate
            task=.(<estimate)7}task
            emit 'pert ',name,' expected ',((o+(4*m)+p)decimals 6),' variance ',(*:p-o)decimals 36
        end.
        Tasks=:(<task)(Names i.<name)}Tasks
    case. 'CAPACITY' do.
        at=.CapacityNames i.0{args
        value=.0".1{::args
        if. at=#CapacityNames do. CapacityNames=:CapacityNames,0{args
            CapacityValues=:CapacityValues,value
        else. CapacityValues=:value at}CapacityValues end.
        emit 'capacity ',(0{::args),' ',1{::args
    case. 'START';'HOLIDAY';'DEADLINE' do.
        date=.parseDate 0{::args
        if. command-:'START' do. StartDate=:date
            title=.'start'
        elseif. command-:'DEADLINE' do. Deadline=:date
            title=.'deadline'
        else.
            ('duplicate holiday ',0{::args)check -.date e.Holidays
            Holidays=:Holidays,date
            title=.'holiday'
        end.
        emit title,' ',dateText date
    case. 'LIST' do.
        emit 'tasks ',(num #Names),', dependencies ',(num #Dependencies),', holidays ',num #Holidays
        for_name. orderedNames'' do.
            task=.getTask >name
            previous=.0$a:
            for_dep. predLinks >name do. previous=.previous,<0{::>dep end.
            emit (>name),' duration ',(num duration task),' resource ',(1{::task),' units ',(num 2{::task),' preds ',nameList previous
        end.
    case. 'SHOW' do.
        name=.0{::args
        requireTask name
        task=.getTask name
        text=.'task ',name,' duration ',(num duration task),' resource ',(1{::task),' units ',num 2{::task
        if. 3{::task do. text=.text,' notbefore ',num 3{::task end.
        emit text
        for_title. ;:'preds succs' do.
            if. title-:<'preds' do. links=.predLinks name
                field=.0
            else. links=.succLinks name
                field=.1 end.
            entries=.0$a:
            for_dep. links do. dep=.>dep
                entries=.entries,<(field{::dep),' ',(2{::dep),signedText 3{::dep end.
            text=.'none'
            if. #entries do. text=.', 'join entries end.
            emit (>title),': ',text
        end.
        if. (4{::task)<0 do. emit 'crash: none'
        else. emit 'crash: max ',(num 4{::task),' used ',(num 6{::task),' cost ',num 5{::task end.
        estimate=.7{::task
        if. #estimate do. emit 'pert: ',' 'join num&.>estimate else. emit 'pert: none' end.
        order=.topological''
        if. (#order)<#Names do. emit 'schedule: unavailable'
        else.
            result=.calcSchedule (<order),(<' '),<0
            fields=.result scheduleFields name
            labels=.;:'ES EF LS LF TF FF'
            entries=.0$a:
            for_i. i.6 do. entries=.entries,<(i{::labels),' ',num i{fields end.
            text=.'schedule: ',' 'join entries
            if. (<name)e.criticalNames result do. text=.text,' critical' end.
            emit text
        end.
    case. 'IMPACT' do.
        name=.0{::args
        requireTask name
        reached=.0$a:
        queue=.,<name
        at=.0
        while. at<#queue do.
            current=.at{::queue
            at=.at+1
            for_dep. succLinks current do.
                next=.1{::>dep
                if. -.(<next)e.reached do. reached=.reached,<next
                    queue=.queue,<next end.
            end.
        end.
        emit 'impact ',name,': ',nameList reached-.<name
    case. do.
        order=.analysisOrder''
        if. command-:'CALENDAR' do. 'no start date'check StartDate>:0
        elseif. command-:'LOAD' do. ('unknown resource ',0{::args)check (0{args)e.resources''
        elseif. command-:'WHATIF' do. requireTask 0{::args
        elseif. command-:'VARIANCE' do. 'no baseline'check -.Baseline-:a: end.
        result=.calcSchedule (<order),(<' '),<0
        names=.0{::result
        length=.8{::result
        select. command
        case. 'CPM' do.
            width=.4>.>./#&>names
            text=.'TASK',(width-4)#' '
            for_label. ;:'DUR ES EF LS LF TF FF' do. text=.text,((5-#>label)#' '),>label end.
            emit text
            for_i. i.#names do.
                name=.i{::names
                text=.name,(width-#name)#' '
                fields=.(i{1{::result),result scheduleFields name
                for_value. fields do. word=.num value
                    text=.text,((0>.5-#word)#' '),word end.
                if. (<name)e.criticalNames result do. text=.text,' *' end.
                emit text
            end.
            emit 'project duration ',num length
        case. 'CRITICAL' do.
            paths=.criticalPaths result
            emit 'critical paths: ',num #paths
            for_path. paths do. emit ' -> 'join >path end.
        case. 'SLACK' do.
            for_value. /:~~.6{::result do. emit 'float ',(num value),': ',nameList names#~value=6{::result end.
        case. 'DRAG' do.
            for_name. criticalNames result do.
                changed=.calcSchedule (<order),name,<0
                emit (>name),' drag ',num length-8{::changed
            end.
        case. 'STATS' do.
            critical=.#criticalNames result
            counts=.3$0
            for_dep. Dependencies do.
                kind=.2{::>dep
                at=.(;:'FS SS FF')i.<kind
                counts=.(1+at{counts)at}counts
            end.
            emit 'tasks ',(num #Names),', critical ',(num critical),', dependencies ',(num #Dependencies),' (FS ',(num 0{counts),', SS ',(num 1{counts),', FF ',(num 2{counts),')'
            work=.0$a:
            for_resource. resources'' do.
                total=.0
                for_task. Tasks do. task=.>task
                    if. resource-:<1{::task do. total=.total+(duration task)*2{::task end.
                end.
                work=.work,<(>resource),' ',num total
            end.
            emit 'work ',', 'join work
            total=.+/6{::result
            emit 'float total ',(num total),', average ',total decimals #Names
            emit 'duration ',(num length),', critical share ',((100*critical)decimals #Names),'%'
        case. 'CALENDAR' do. calendarReport result
        case. 'GANTT' do.
            ('chart too wide (',(num length),' days)')check length<:60
            width=.>./#&>names
            emit (width#' '),' |',('0123456789'{~10|i.length),'|'
            for_name. byStart result do.
                at=.names i.name
                bar=.''
                for_day. i.length do.
                    mark=.' '
                    if. (day>:at{2{::result)*.day<at{3{::result do.
                        mark=.'-'
                        if. name e.criticalNames result do. mark=.'=' end.
                    elseif. (day>:at{3{::result)*.day<at{5{::result do. mark=.'.' end.
                    bar=.bar,mark
                end.
                emit (>name),((width-#>name)#' '),' |',bar,'|'
            end.
        case. 'LEVEL' do. result levelReport 0".0{::args
        case. 'LOAD' do.
            resource=.0{::args
            daily=.usage (<resource),(<names),(<2{::result),(<3{::result),<length
            peak=.>./daily
            emit 'load ',resource,': ',' 'join num&.>daily
            emit 'peak ',(num peak),' on day ',num daily i.peak
            at=.CapacityNames i.<resource
            if. at<#CapacityNames do. capacity=.at{CapacityValues
                emit 'capacity ',(num capacity),' exceeded on ',(num +/daily>capacity),' days' end.
        case. 'PERTSUM' do.
            for_path. criticalPaths result do.
                mean=.variance=.0
                for_name. >path do.
                    task=.getTask >name
                    estimate=.7{::task
                    if. 0=#estimate do. estimate=.3#duration task end.
                    'o m p'=.estimate
                    mean=.mean+o+(4*m)+p
                    variance=.variance+*:p-o
                end.
                emit (' -> 'join >path),': expected ',(mean decimals 6),' variance ',variance decimals 36
            end.
        case. 'CRASH' do. order crashProject 0".0{::args
        case. 'WHATIF' do.
            name=.0{::args
            replacement=.0".1{::args
            after=.calcSchedule (<order),(<name),<replacement
            emit 'whatif ',name,' ',(num duration getTask name),' -> ',(num replacement),': project ',(num length),' -> ',num 8{::after
            labels=.;:'ES EF TF'
            for_i. i.#names do.
                old=.i&{&>2 3 6{result
                new=.i&{&>2 3 6{after
                changes=.0$a:
                for_j. i.3 do.
                    if. (j{old)~:j{new do. changes=.changes,<(j{::labels),' ',(num j{old),'->',num j{new end.
                end.
                if. #changes do. emit (i{::names),' ',' 'join changes end.
            end.
            if. -.(criticalNames result)-:criticalNames after do. emit 'critical ',(nameList criticalNames result),' -> ',nameList criticalNames after end.
        case. 'BASELINE' do.
            Baseline=:result
            emit 'baseline saved: ',(num #Names),' tasks, duration ',num length
        case. 'VARIANCE' do.
            emit 'variance: duration ',(num 8{::Baseline),' -> ',(num length),' (',(signedText length-8{::Baseline),')'
            all=./:~~.names,0{::Baseline
            printed=.0
            for_name. all do.
                old=.(0{::Baseline)i.name
                new=.names i.name
                if. new=#names do. emit (>name),' removed'
                    printed=.1
                elseif. old=#0{::Baseline do. emit (>name),' new'
                    printed=.1
                elseif. -.((old{2{::Baseline),old{3{::Baseline)-:((new{2{::result),new{3{::result) do.
                    emit (>name),' start ',(signedText (new{2{::result)-old{2{::Baseline),' finish ',signedText (new{3{::result)-old{3{::Baseline
                    printed=.1
                end.
            end.
            if. -.printed do. emit 'no task changes' end.
        end.
    end.
)
main =: 3 : 0
    Names=:Tasks=:Dependencies=:CapacityNames=:0$a:
    CapacityValues=:Holidays=:i.0
    StartDate=:Deadline=:_1
    Baseline=:a:
    lines=.<;._2 (1!:1 <'/dev/stdin'),LF
    count=.0".0{::lines
    for_i. i.count do.
        Output=:0$a:
        try. execute (i+1){::lines
        catcht. Output=:,<'error: ',Reason end.
        if. #Output do. 1!:2&2 ;Output,&.><LF end.
    end.
)
main''
