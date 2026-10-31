load 'waveform_io.ijs'
load 'picker.ijs'
load 'associator.ijs'
load 'locator.ijs'
load 'magnitude.ijs'
integer =: 3 : 0
    text =. ":y
    '-'(I.text='_')}text
)
scaled =: 4 : 0
    factor =. 1x
    for_i. i.x do.
        factor =. factor*10
    end.
    value =. x:<.0.5+(|y)*factor
    if. y<0.0 do.
        value =. -value
    end.
    value
)
decimal =: 4 : 0
    factor =. 1x
    for_i. i.x do.
        factor =. factor*10
    end.
    rounded =. x scaled y
    absolute =. |rounded
    fraction =. integer factor|absolute
    sign =. (rounded<0)#'-'
    sign,(integer absolute intdiv factor),'.',((x-#fraction)$'0'),fraction
)
time_text =: 3 : 0
    fraction =. integer 100|y
    (integer y intdiv 100),'.',((2-#fraction)$'0'),fraction
)
join =: 4 : 0
    result =. ''
    for_i. i.#y do.
        if. i do.
            result =. result,x
        end.
        result =. result,i{::y
    end.
    result
)
yes_no =: 3 : 'y{::;:''no yes'''
pick_time =: 3 : '(0.0+(<y,1){PickMeta)%100.0'
station_ordered =: 3 : 'y /: 0{"1 y{PickMeta'
observations =: 4 : 0
    result =. 0 4$0.0
    for_index. y do.
        station =. (<index,0){PickMeta
        observed =. pick_time index
        if. x do.
            observed =. observed-station{TimeCorrections
        end.
        result =. result,(0.0+station{StationCoordinates),observed
    end.
    result
)
collect_picks =: 3 : 0
    PickMeta =: 0 5$0x
    PickRatios =: i.0
    WaveStatistics =: 0 7$0x
    for_station. i.#StationCodes do.
        args =. (<station),(<station{StationStarts),<Params
        'meta ratios statistics' =. args detect_station station{::Samples
        PickMeta =: PickMeta,meta
        PickRatios =: PickRatios,ratios
        WaveStatistics =: WaveStatistics,statistics
    end.
    order =. /:1 0{"1 PickMeta
    PickMeta =: order{PickMeta
    PickRatios =: order{PickRatios
    PickStates =: (#PickMeta)$0
    PickEvents =: (#PickMeta)$0
    FirstResiduals =: (#PickMeta)$0.0
    FinalResiduals =: (#PickMeta)$0.0
    i.0
)
locate_candidates =: 3 : 0
    associated =. (AssociationWindow,MinimumStations,#StationCodes)associate PickMeta
    Candidates =: 0$a:
    Events =: 0$a:
    for_candidate_index. i.#associated do.
        original =. candidate_index{::associated
        ordered =. station_ordered original
        first_pass =. run_location (<0 observations ordered),(<Velocity),<GridRanges
        first_result =. 1{::first_pass
        errors =. 2{::first_result
        bad =. (|errors)>ResidualLimit
        retained =. (-.bad)#ordered
        dropped =. bad#ordered
        dropped_errors =. bad#errors
        rejected =. (0<#dropped)*.(#retained)<MinimumStations
        has_second =. (-.rejected)*.0<#dropped
        second_pass =. first_pass
        event_number =. 0
        if. rejected do.
            PickStates =: 4 ordered}PickStates
        else.
            if. has_second do.
                second_pass =. run_location (<0 observations retained),(<Velocity),<GridRanges
            end.
            adopted =. 1{::second_pass
            event_number =. 1+#Events
            PickStates =: 1 retained}PickStates
            PickEvents =: event_number retained}PickEvents
            FirstResiduals =: (2{::adopted)retained}FirstResiduals
            PickStates =: 2 dropped}PickStates
            PickEvents =: event_number dropped}PickEvents
            Events =: Events,<(<event_number),(<retained),<adopted
        end.
        record =. (<candidate_index+1),(<{.original),(<ordered),(<retained),(<dropped),(<dropped_errors),(<first_pass),(<second_pass),(<has_second),(<rejected),<event_number
        Candidates =: Candidates,<record
    end.
    BeforeByStation =: (#StationCodes)$<i.0
    AfterByStation =: (#StationCodes)$<i.0
    MagnitudeByStation =: (#StationCodes)$<i.0
    for_event. Events do.
        'number used first' =. >event
        for_index. used do.
            station =. (<index,0){PickMeta
            values =. (station{::BeforeByStation),index{FirstResiduals
            BeforeByStation =: (<values)station}BeforeByStation
        end.
    end.
    TimeCorrections =: (#StationCodes)$0.0
    for_station. i.#StationCodes do.
        values =. station{::BeforeByStation
        if. #values do.
            TimeCorrections =: ((ordered_sum values)%#values)station}TimeCorrections
        end.
    end.
    i.0
)
quality_for_event =: 3 : 0
    'number used first final obs start_rms' =. y
    solution =. 0{::final
    ellipse =. error_ellipse (<solution),(<obs),<Velocity
    angles =. i.0
    nearest =. _
    for_index. used do.
        station =. (<index,0){PickMeta
        coordinates =. 0.0+station{StationCoordinates
        dx =. (0{coordinates)-0{solution
        dy =. (1{coordinates)-1{solution
        angle =. ((atan2 dx,dy)*180.0)%PI
        if. angle<0.0 do.
            angle =. angle+360.0
        end.
        angles =. angles,angle
        nearest =. nearest<.%:(dx*dx)+dy*dy
    end.
    angles =. /:~angles
    gap =. (({.angles)+360.0)-{:angles
    for_i. i.<:#angles do.
        gap =. gap>.((i+1){angles)-i{angles
    end.
    grade =. 'C'
    measurements =. gap,(3{::final),0{ellipse
    if. *./measurements<:QualityA do.
        grade =. 'A'
    elseif. *./measurements<:QualityB do.
        grade =. 'B'
    end.
    first_solution =. 0{::first
    dx =. (0{solution)-0{first_solution
    dy =. (1{solution)-1{first_solution
    dh =. %:(dx*dx)+dy*dy
    dz =. (2{solution)-2{first_solution
    jacks =. 0$a:
    maximum =. 0
    maximum_shift =. _1.0
    for_removed. i.#used do.
        remaining =. (removed~:i.#obs)#obs
        run =. geiger (<solution),(<remaining),<Velocity
        change =. (3{.0{::run)-3{.solution
        shift =. %:((0{change)*0{change)+(1{change)*1{change
        station =. (<(removed{used),0){PickMeta
        jacks =. jacks,<(<station),<change,shift
        if. shift>maximum_shift do.
            maximum =. removed
            maximum_shift =. shift
        end.
    end.
    (<ellipse),(<gap),(<nearest),(<grade),(<dh),(<dz),(<jacks),<maximum
)
relocate_events =: 3 : 0
    for_e. i.#Events do.
        'number used first' =. e{::Events
        obs =. 1 observations used
        start_rms =. rms (0{first),(<obs),<Velocity
        final =. geiger (0{first),(<obs),<Velocity
        errors =. 2{::final
        FinalResiduals =: errors used}FinalResiduals
        for_i. i.#used do.
            index =. i{used
            station =. (<index,0){PickMeta
            values =. (station{::AfterByStation),i{errors
            AfterByStation =: (<values)station}AfterByStation
        end.
        event =. (<number),(<used),(<first),(<final),(<obs),<start_rms
        quality =. quality_for_event event
        event =. event,<quality
        Events =: (<event)e}Events
    end.
    i.0
)
compute_magnitudes =: 3 : 0
    for_e. i.#Events do.
        event =. e{::Events
        'number used first final obs start_rms quality' =. event
        solution =. 0{::final
        local_values =. i.0
        duration_values =. i.0
        records =. 0$a:
        for_index. used do.
            meta =. index{PickMeta
            station =. 0{meta
            radius =. (solution distance 0.0+station{StationCoordinates)%1000.0
            args =. (<3{meta),(<2{meta),(<4{meta),(<radius),(<LocalMagnitude),<DurationMagnitude
            record =. per_pick_magnitude args
            values =. 0{::record
            records =. records,<record
            duration_values =. duration_values,2{values
            if. 1{::record do.
                local_values =. local_values,1{values
            end.
        end.
        has_ml =. 0<#local_values
        ml =. 0.0
        if. has_ml do.
            ml =. median local_values
        end.
        md =. median duration_values
        for_i. i.#records do.
            record =. i{::records
            if. 1{::record do.
                station =. (<(i{used),0){PickMeta
                values =. (station{::MagnitudeByStation),(1{0{::record)-ml
                MagnitudeByStation =: (<values)station}MagnitudeByStation
            end.
        end.
        event =. event,(<records),(<has_ml),(<ml),(<md),(<0.0),<0
        Events =: (<event)e}Events
    end.
    MagnitudeCorrections =: (#StationCodes)$0.0
    for_station. i.#StationCodes do.
        values =. station{::MagnitudeByStation
        if. #values do.
            MagnitudeCorrections =: ((ordered_sum values)%#values)station}MagnitudeCorrections
        end.
    end.
    for_e. i.#Events do.
        event =. e{::Events
        used =. 1{::event
        records =. 7{::event
        corrected =. i.0
        for_i. i.#records do.
            record =. i{::records
            if. 1{::record do.
                station =. (<(i{used),0){PickMeta
                corrected =. corrected,(1{0{::record)-station{MagnitudeCorrections
            end.
        end.
        mlc =. 0.0
        if. #corrected do.
            mlc =. median corrected
        end.
        event =. (<mlc)11}event
        Events =: (<event)e}Events
    end.
    i.0
)
travel_regression =: 3 : 0
    points =. 0 2$0.0
    sd =. 0.0
    st =. 0.0
    sdd =. 0.0
    sdt =. 0.0
    for_event. Events do.
        event =. >event
        solution =. 0{::3{::event
        for_index. 1{::event do.
            station =. (<index,0){PickMeta
            radius =. (solution distance 0.0+station{StationCoordinates)%1000.0
            travel =. (pick_time index)-3{solution
            points =. points,radius,travel
            sd =. sd+radius
            st =. st+travel
            sdd =. sdd+radius*radius
            sdt =. sdt+radius*travel
        end.
    end.
    count =. 0.0+#points
    slope =. ((count*sdt)-sd*st)%((count*sdd)-sd*sd)
    intercept =. (st-slope*sd)%count
    total =. 0.0
    for_point. points do.
        residual =. ((1{point)-intercept)-slope*0{point
        total =. total+residual*residual
    end.
    (<#points),(<1000.0%slope),(<intercept),<%:total%count
)
cluster_events =: 3 : 0
    Clusters =: 0$a:
    visited =. (#Events)$0
    for_initial. i.#Events do.
        if. initial{visited do.
            continue.
        end.
        visited =. 1 initial}visited
        queue =. ,initial
        members =. i.0
        cursor =. 0
        while. cursor<#queue do.
            index =. cursor{queue
            cursor =. cursor+1
            members =. members,index
            first =. 0{::3{::index{::Events
            for_other. i.#Events do.
                if. other{visited do.
                    continue.
                end.
                second =. 0{::3{::other{::Events
                difference =. first-second
                spatial =. %:ordered_sum *:3{.difference
                if. ((|3{difference)<:1{ClusterLimits)*.spatial<:0{ClusterLimits do.
                    visited =. 1 other}visited
                    queue =. queue,other
                end.
            end.
        end.
        members =. /:~members
        center =. 3$0.0
        low =. _
        high =. __
        for_index. members do.
            event =. index{::Events
            event =. (<1+#Clusters)12}event
            Events =: (<event)index}Events
            solution =. 0{::3{::event
            center =. center+3{.solution
            low =. low<.3{solution
            high =. high>.3{solution
        end.
        center =. center%#members
        Clusters =: Clusters,<(<members),(<center),<high-low
    end.
    i.0
)
reassociate =: 3 : 0
    station_sets =. ((#Events),#StationCodes)$0
    for_e. i.#Events do.
        for_index. 1{::e{::Events do.
            station =. (<index,0){PickMeta
            station_sets =. 1 (<e,station)}station_sets
        end.
    end.
    Added =: i.0
    for_index. i.#PickMeta do.
        if. index{PickStates do.
            continue.
        end.
        station =. (<index,0){PickMeta
        best =. _1
        best_error =. 0.0
        for_e. i.#Events do.
            if. (<e,station){station_sets do.
                continue.
            end.
            solution =. 0{::3{::e{::Events
            radius =. solution distance 0.0+station{StationCoordinates
            residual =. (((pick_time index)-3{solution)-radius%Velocity)-station{TimeCorrections
            if. (|residual)<:ResidualLimit do.
                if. (best<0)+.(|residual)<|best_error do.
                    best =. e
                    best_error =. residual
                end.
            end.
        end.
        if. best>:0 do.
            PickStates =: 3 index}PickStates
            PickEvents =: (best+1)index}PickEvents
            FinalResiduals =: best_error index}FinalResiduals
            station_sets =. 1 (<best,station)}station_sets
            Added =: Added,index
        end.
    end.
    i.0
)
solution_text =: 3 : 0
    'heading solution error iteration' =. y
    prefix =. heading
    if. iteration do.
        prefix =. prefix,' ',integer iteration
    end.
    prefix,' x=',(1 decimal 0{solution),' y=',(1 decimal 1{solution),' z=',(1 decimal 2{solution),' t0=',(3 decimal 3{solution),' rms=',4 decimal error
)
pass_lines =: 3 : 0
    'number indices run' =. y
    'grid result' =. run
    'solution trace errors error' =. result
    codes =. ((0{"1 indices{PickMeta){StationCodes)
    lines =. <'PASS ',(integer number),' stations=',','join codes
    lines =. lines,<solution_text (<'GRID'),(0{grid),(1{grid),<0
    lines =. lines,<'PROFILE ',' 'join (4&decimal)&.>2{::grid
    for_i. i.#trace do.
        record =. i{trace
        lines =. lines,<solution_text (<'ITER'),(<4{.record),(<4{record),<i+1
    end.
    for_i. i.#indices do.
        index =. i{indices
        meta =. index{PickMeta
        station =. 0{meta
        radius =. solution distance 0.0+station{StationCoordinates
        lines =. lines,<'RES ',(station{::StationCodes),' dist=',(1 decimal radius),' tt=',(4 decimal radius%Velocity),' obs=',(time_text 1{meta),' res=',4 decimal i{errors
    end.
    lines
)
location_lines =: 3 : 0
    lines =. 0$a:
    for_candidate. Candidates do.
        'number first original retained dropped dropped_errors pass1 pass2 has_second rejected event_number' =. >candidate
        first_sample =. (<first,1){PickMeta
        lines =. lines,<'CANDIDATE ',(integer number),' picks=',(integer #original),' first=',time_text first_sample
        lines =. lines,pass_lines (<1),(<original),<pass1
        for_i. i.#dropped do.
            index =. i{dropped
            station =. (<index,0){PickMeta
            lines =. lines,<'DROP ',(station{::StationCodes),' res=',4 decimal i{dropped_errors
        end.
        if. rejected do.
            lines =. lines,<'RESULT REJECTED stations=',integer #retained
        else.
            if. has_second do.
                lines =. lines,pass_lines (<2),(<retained),<pass2
            end.
            lines =. lines,<'RESULT EVENT ',integer event_number
        end.
    end.
    lines =. lines,<'CORRECTIONS'
    for_station. i.#StationCodes do.
        lines =. lines,<(station{::StationCodes),' n=',(integer #station{::BeforeByStation),' correction=',4 decimal station{TimeCorrections
    end.
    depths =. i.0
    all_rms =. i.0
    grades =. 0 0 0
    for_event. Events do.
        'number used first final obs start_rms quality records has_ml ml md mlc cluster' =. >event
        'solution trace errors error' =. final
        'ellipse gap nearest grade dh dz jacks maximum' =. quality
        lines =. lines,<'EVENT ',integer number
        lines =. lines,<solution_text (<'START'),(0{first),(<start_rms),<0
        for_i. i.#trace do.
            record =. i{trace
            lines =. lines,<solution_text (<'ITER'),(<4{.record),(<4{record),<i+1
        end.
        for_i. i.#used do.
            index =. i{used
            meta =. index{PickMeta
            station =. 0{meta
            radius =. solution distance 0.0+station{StationCoordinates
            lines =. lines,<'RES ',(station{::StationCodes),' dist=',(1 decimal radius),' tt=',(4 decimal radius%Velocity),' obs=',(time_text 1{meta),' corr=',(4 decimal station{TimeCorrections),' res=',4 decimal i{errors
        end.
        lines =. lines,<'ELLIPSE smaj=',(1 decimal 0{ellipse),' smin=',(1 decimal 1{ellipse),' az=',(1 decimal 2{ellipse),' erz=',(1 decimal 3{ellipse),' ert=',4 decimal 4{ellipse
        lines =. lines,<'SHIFT dh=',(1 decimal dh),' dz=',1 decimal dz
        lines =. lines,<'GAP ',(1 decimal gap),' DMIN ',(1 decimal nearest),' QUALITY ',grade
        for_jack. jacks do.
            'station change' =. >jack
            lines =. lines,<'JACK ',(station{::StationCodes),' dx=',(1 decimal 0{change),' dy=',(1 decimal 1{change),' dz=',(1 decimal 2{change),' shift=',1 decimal 3{change
        end.
        'station change' =. maximum{::jacks
        lines =. lines,<'JACKKNIFE max=',(1 decimal 3{change),' station=',station{::StationCodes
        depths =. depths,2{solution
        all_rms =. all_rms,error
        category =. 'ABC'i.grade
        grades =. (1+category{grades)category}grades
    end.
    'count velocity intercept error' =. travel_regression ''
    lines =. lines,<'FIT n=',(integer count),' velocity=',(1 decimal velocity),' intercept=',(4 decimal intercept),' rms=',4 decimal error
    for_i. i.#Clusters do.
        'members center span' =. i{::Clusters
        if. 1<#members do.
            lines =. lines,<'CLUSTER ',(integer i+1),' events=',(','join integer&.>members+1),' x=',(1 decimal 0{center),' y=',(1 decimal 1{center),' z=',(1 decimal 2{center),' span=',3 decimal span
        end.
    end.
    lines =. lines,<'ADDED'
    for_index. Added do.
        meta =. index{PickMeta
        station =. 0{meta
        lines =. lines,<(station{::StationCodes),' sample=',(integer 1{meta),' event=',(integer index{PickEvents),' res=',4 decimal index{FinalResiduals
    end.
    rejected =. +/9&{::&>Candidates
    unassociated =. +/PickStates=0
    depths =. /:~depths
    lines =. lines,<'SUMMARY picks=',(integer #PickMeta),' candidates=',(integer #Candidates),' events=',(integer #Events),' rejected=',(integer rejected),' unassociated=',integer unassociated
    lines =. lines,<'DEPTH min=',(1 decimal {.depths),' median=',(1 decimal median depths),' max=',1 decimal {:depths
    lines =. lines,<'QUALITY A=',(integer 0{grades),' B=',(integer 1{grades),' C=',(integer 2{grades),' mean_rms=',4 decimal (ordered_sum all_rms)%#Events
    lines
)
picks_lines =: 3 : 0
    lines =. <'station,sample,time_s,duration,snr,amplitude,clipped,event,status,residual'
    states =. ;:'unassociated used dropped added rejected'
    for_i. i.#PickMeta do.
        meta =. i{PickMeta
        state =. i{PickStates
        residual =. '-'
        if. state e.1 3 do.
            residual =. 4 decimal i{FinalResiduals
        end.
        fields =. (<(0{meta){::StationCodes),(<integer 1{meta),(<time_text 1{meta),(<integer 2{meta),(<2 decimal i{PickRatios),(<integer 3{meta),(<yes_no 4{meta),(<integer i{PickEvents),(state{states),<residual
        lines =. lines,<','join fields
    end.
    lines
)
catalog_lines =: 3 : 0
    lines =. <'event,origin_time,x,y,depth,rms,stations,gap,dmin,smaj,smin,azimuth,erz,ml,md,quality,cluster'
    for_event. Events do.
        'number used first final obs start_rms quality records has_ml ml md mlc cluster' =. >event
        solution =. 0{::final
        'ellipse gap nearest grade dh dz jacks maximum' =. quality
        ml_text =. '-'
        if. has_ml do.
            ml_text =. 2 decimal ml
        end.
        fields =. (<integer number),(<3 decimal 3{solution),(<1 decimal 0{solution),(<1 decimal 1{solution),(<1 decimal 2{solution),(<4 decimal 3{::final),(<integer #used),(<1 decimal gap),(<1 decimal nearest),(<1 decimal 0{ellipse),(<1 decimal 1{ellipse),(<1 decimal 2{ellipse),(<1 decimal 3{ellipse),(<ml_text),(<2 decimal md),(<grade),<integer cluster
        lines =. lines,<','join fields
    end.
    lines
)
empty_grid =: 3 : 0
    'width height' =. y
    (height,width)$' '
)
chart_lines =: 3 : 0
    frame =. '+',((1{$y)$'-'),'+'
    lines =. <frame
    for_row. y do.
        lines =. lines,<'|',row,'|'
    end.
    lines,<frame
)
timeline_lines =: 3 : 0
    'duration width low high height' =. Timeline
    canvas =. empty_grid width,height
    for_event. Events do.
        event =. >event
        if. -.8{::event do.
            continue.
        end.
        solution =. 0{::3{::event
        origin =. 3 scaled 3{solution
        h =. 2 scaled 9{::event
        if. (origin<0)+.(origin>:1000*duration)+.h<100*low do.
            continue.
        end.
        column =. (origin*width)intdiv 1000*duration
        level =. (((h-100*low)*height)intdiv (100*(high-low)))<.height-1
        for_k. i.level+1 do.
            row =. (height-1)-k
            if. k=level do.
                canvas =. 'o'(<row,column)}canvas
            elseif. ' '=(<row,column){canvas do.
                canvas =. '|'(<row,column)}canvas
            end.
        end.
    end.
    (<'TIMELINE t=0..',(integer duration),' ML=',(integer low),'..',integer high),chart_lines canvas
)
magnitude_lines =: 3 : 0
    lines =. 0$a:
    all_local =. i.0
    relation_x =. i.0
    relation_y =. i.0
    for_event. Events do.
        'number used first final obs start_rms quality records has_ml ml md mlc cluster' =. >event
        available =. +/1&{::&>records
        ml_text =. '-'
        if. has_ml do.
            ml_text =. 2 decimal ml
            all_local =. all_local,ml
            relation_x =. relation_x,md
            relation_y =. relation_y,ml
        end.
        lines =. lines,<'EVENT ',(integer number),' ML=',ml_text,' n=',(integer available),' MD=',2 decimal md
        for_i. i.#records do.
            record =. i{::records
            'radius local_value duration_value' =. 0{::record
            meta =. (i{used){PickMeta
            station =. 0{meta
            prefix =. (station{::StationCodes),' r=',(3 decimal radius),' amp=',(integer 3{meta),' '
            if. 1{::record do.
                prefix =. prefix,'ml=',(2 decimal local_value),' res=',2 decimal local_value-ml
            else.
                prefix =. prefix,'clipped'
            end.
            lines =. lines,<prefix,' dur=',(integer 2{meta),' md=',2 decimal duration_value
        end.
    end.
    lines =. lines,<'CORRECTED'
    for_event. Events do.
        event =. >event
        mlc_text =. '-'
        if. 8{::event do.
            mlc_text =. 2 decimal 11{::event
        end.
        lines =. lines,<'EVENT ',(integer 0{::event),' MLC=',mlc_text
    end.
    'counts low high completeness nb b sigma a' =. frequency_statistics all_local
    lines =. lines,<'FMD'
    for_value. low+i.1+high-low do.
        cumulative =. +/(value-low)}.counts
        lines =. lines,<'M=',(class_text value),' N=',(integer (value-low){counts),' CUM=',integer cumulative
    end.
    xm =. (ordered_sum relation_x)%#relation_x
    ym =. (ordered_sum relation_y)%#relation_y
    xx =. 0.0
    xy =. 0.0
    yy =. 0.0
    for_i. i.#relation_x do.
        dx =. (i{relation_x)-xm
        dy =. (i{relation_y)-ym
        xx =. xx+dx*dx
        xy =. xy+dx*dy
        yy =. yy+dy*dy
    end.
    slope =. xy%xx
    lines =. lines,<'MC ',class_text completeness
    lines =. lines,<'BVALUE ',(3 decimal b),' SIGMA ',(3 decimal sigma),' N ',integer nb
    lines =. lines,<'AVALUE ',3 decimal a
    lines =. lines,<'MLMD n=',(integer #relation_x),' slope=',(3 decimal slope),' intercept=',(3 decimal ym-slope*xm),' r=',(3 decimal xy%%:xx*yy),' mean_diff=',3 decimal ym-xm
    lines,timeline_lines ''
)
residual_rms =: 3 : '%:(ordered_sum y*y)%#y'
station_lines =: 3 : 0
    lines =. 0$a:
    for_station. i.#StationCodes do.
        code =. station{::StationCodes
        coordinates =. station{StationCoordinates
        statistics =. station{WaveStatistics
        states =. PickStates#~station=0{"1 PickMeta
        counts =. (+/states=1),(+/states=2),(+/states=3),(+/states=4),+/states=0
        before_values =. station{::BeforeByStation
        after_values =. station{::AfterByStation
        before =. '-'
        after =. '-'
        if. #before_values do.
            before =. 4 decimal residual_rms before_values
            after =. 4 decimal residual_rms after_values
        end.
        lines =. lines,<'STATION ',code,' x=',(integer 0{coordinates),' y=',(integer 1{coordinates),' elevation=',integer 2{coordinates
        lines =. lines,<'SAMPLES start=',(integer station{StationStarts),' count=',(integer #station{::Samples),' mean=',(integer 0{statistics),' noise=',(1 decimal (1{statistics)%2.0),' peak=',(integer 2{statistics),' clipped=',integer 3{statistics
        lines =. lines,<'TRIGGERS total=',(integer 4{statistics),' short=',(integer 5{statistics),' picks=',integer 6{statistics
        lines =. lines,<'PICKS used=',(integer 0{counts),' dropped=',(integer 1{counts),' added=',(integer 2{counts),' rejected=',(integer 3{counts),' unassociated=',integer 4{counts
        lines =. lines,<'RESIDUALS n=',(integer #before_values),' rms=',before,' correction=',(4 decimal station{TimeCorrections),' after=',after
        lines =. lines,<'MAGNITUDES n=',(integer #station{::MagnitudeByStation),' correction=',2 decimal station{MagnitudeCorrections
    end.
    lines
)
event_symbol =: 3 : 0
    if. -.8{::y do.
        '?' return.
    end.
    h =. 2 scaled 9{::y
    if. h<100 do.
        '.'
    elseif. h<200 do.
        'o'
    elseif. h<300 do.
        'O'
    else.
        '@'
    end.
)
position_text =: 3 : 0
    if. #y do.
        ','join integer&.>y
    else.
        'outside'
    end.
)
plotted_positions =: 3 : 0
    solution =. 0{::3{::y
    'east north depth' =. 1&scaled&>3{.solution
    'left right bottom top' =. MapArea
    'width height' =. MapSize
    'depth_limit section_height' =. Section
    map_position =. i.0
    ew_position =. i.0
    ns_position =. i.0
    x_valid =. (east>:10*left)*.east<10*right
    y_valid =. (north>:10*bottom)*.north<10*top
    if. x_valid*.y_valid do.
        column =. ((east-10*left)*width)intdiv (10*(right-left))
        row =. (height-1)-((north-10*bottom)*height)intdiv (10*(top-bottom))
        map_position =. column,row
    end.
    if. x_valid*.depth<10*depth_limit do.
        column =. ((east-10*left)*width)intdiv (10*(right-left))
        row =. (depth*section_height)intdiv 10*depth_limit
        ew_position =. column,row
    end.
    if. y_valid*.depth<10*depth_limit do.
        column =. ((north-10*bottom)*width)intdiv (10*(top-bottom))
        row =. (depth*section_height)intdiv 10*depth_limit
        ns_position =. column,row
    end.
    (<map_position),(<ew_position),<ns_position
)
station_position =: 3 : 0
    'east north elevation' =. y{StationCoordinates
    'left right bottom top' =. MapArea
    'width height' =. MapSize
    if. (east<left)+.(east>:right)+.(north<bottom)+.north>:top do.
        i.0 return.
    end.
    column =. ((east-left)*width)intdiv (right-left)
    row =. (height-1)-((north-bottom)*height)intdiv (top-bottom)
    column,row
)
place_point =: 4 : 0
    'position mark' =. x
    result =. y
    if. #position do.
        'column row' =. position
        current =. (<row,column){result
        priorities =. ' ?.oO@^'
        if. (priorities i.mark)>priorities i.current do.
            result =. mark (<row,column)}result
        end.
    end.
    result
)
map_lines =: 3 : 0
    'left right bottom top' =. MapArea
    'width height' =. MapSize
    'depth_limit section_height' =. Section
    canvases =. (<empty_grid width,height),(<empty_grid width,section_height),<empty_grid width,section_height
    positions =. 0$a:
    station_positions =. 0$a:
    for_event. Events do.
        event =. >event
        points =. plotted_positions event
        positions =. positions,<points
        mark =. event_symbol event
        for_i. i.3 do.
            canvas =. ((i{points),<mark)place_point i{::canvases
            canvases =. (<canvas)i}canvases
        end.
    end.
    for_station. i.#StationCodes do.
        point =. station_position station
        station_positions =. station_positions,<point
        canvas =. ((<point),<'^')place_point 0{::canvases
        canvases =. (<canvas)0}canvases
    end.
    titles =. (<'MAP x=',(integer left),'..',(integer right),' y=',(integer bottom),'..',integer top), (<'SECTION EW x=',(integer left),'..',(integer right),' z=0..',integer depth_limit),<'SECTION NS y=',(integer bottom),'..',(integer top),' z=0..',integer depth_limit
    lines =. 0$a:
    for_i. i.3 do.
        lines =. lines,(i{titles),chart_lines i{::canvases
    end.
    lines =. lines,<'LEGEND ^ station . ML<1 o ML<2 O ML<3 @ ML>=3 ? no ML'
    for_station. i.#StationCodes do.
        lines =. lines,<'STATION ',(station{::StationCodes),' map=',position_text station{::station_positions
    end.
    for_i. i.#Events do.
        points =. i{::positions
        mark =. event_symbol i{::Events
        lines =. lines,<'EVENT ',(integer i+1),' ',mark,' map=',(position_text 0{::points),' ew=',(position_text 1{::points),' ns=',position_text 2{::points
    end.
    lines
)
save =: 4 : 0
    ((LF join y),LF)1!:2 <'output/',x
)
run =: 3 : 0
    'StationCodes StationCoordinates StationStarts Samples Params' =: read_inputs ''
    AssociationWindow =: {.8{::Params
    MinimumStations =: {.9{::Params
    Velocity =: 0.0+{.10{::Params
    GridRanges =: >11 12 13{Params
    ResidualLimit =: 0.0+{.14{::Params
    QualityA =: 0.0+15{::Params
    QualityB =: 0.0+16{::Params
    ClusterLimits =: 0.0+17{::Params
    LocalMagnitude =: 0.0+18{::Params
    DurationMagnitude =: 0.0+19{::Params
    MapArea =: 20{::Params
    MapSize =: 21{::Params
    Section =: 22{::Params
    Timeline =: 23{::Params
    collect_picks ''
    locate_candidates ''
    relocate_events ''
    compute_magnitudes ''
    cluster_events ''
    reassociate ''
    'picks.csv'save picks_lines ''
    'locations.txt'save location_lines ''
    'catalog.csv'save catalog_lines ''
    'magnitudes.txt'save magnitude_lines ''
    'stations.txt'save station_lines ''
    'map.txt'save map_lines ''
    i.0
)
run ''
