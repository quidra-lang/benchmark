load 'signal_io.ijs'
load 'report.ijs'
load 'filters.ijs'
load 'detector.ijs'
load 'hrv.ijs'
Labels =: ;:'N V A'
Methods =: ;:'threshold searchback'
PeakClasses =: ;:'qrs searchback twave refractory noise'
pad =: 4 : '((0>.x-#y)#'' ''),y'
csv =: 3 : ''',''join text&.>y'
thresholds =: 3 : 0
    integrated =. (1{y)+((0{y)-1{y)intdiv 4
    band =. (3{y)+((2{y)-3{y)intdiv 4
    integrated,band,(integrated intdiv 2),band intdiv 2
)
register_peak =: 3 : 0
    if. #Registered do.
        elapsed =. (<y,0){Peaks
        elapsed =. elapsed-(<({:Registered),0){Peaks
        Intervals =: Intervals,elapsed
        if. 8<#Intervals do.
            Intervals =: }.Intervals
        end.
        RA1 =: (+/Intervals)intdiv #Intervals
        if. ((92*RA1)<:100*elapsed)*.(100*elapsed)<:116*RA1 do.
            RA2 =: RA1
        end.
    end.
    Registered =: Registered,y
    0
)
update_levels =: 4 : 0
    peak =. y{Peaks
    if. x=1 do.
        values =. ((2 3{peak)+7*1 3{Levels)intdiv 8
        Levels =: values 1 3}Levels
    else.
        factor =. 7
        if. x=2 do.
            factor =. 3
        end.
        values =. ((2 3{peak)+factor*0 2{Levels)intdiv factor+1
        Levels =: values 0 2}Levels
    end.
    0
)
search_back =: 3 : 0
    while. 1 do.
        last =. 0
        if. #Registered do.
            last =. (<({:Registered),0){Peaks
        end.
        if. (y-last)<:(RA2*SearchbackPercent)intdiv 100 do.
            break.
        end.
        current =. thresholds Levels
        chosen =. _1
        best =. _1
        for_index. i.#Peaks do.
            'moment position peak_i peak_f slope thr_i thr_f category' =. index{Peaks
            if. (category=4)*.(moment>last)*.(moment<y)*.(peak_i>2{current)*.peak_f>3{current do.
                if. peak_i>best do.
                    chosen =. index
                    best =. peak_i
                end.
            end.
        end.
        if. chosen<0 do.
            break.
        end.
        2 update_levels chosen
        Peaks =: 1 (<chosen,7)}Peaks
        register_peak chosen
    end.
    0
)
detect =: 3 : 0
    InitialLevels =: initial_levels Signals
    Levels =: InitialLevels
    Registered =: i.0
    Intervals =: i.0
    RA1 =: 200
    RA2 =: 200
    for_index. i.#Peaks do.
        moment =. (<index,0){Peaks
        search_back moment
        current =. thresholds Levels
        Peaks =: (0{current)(<index,5)}Peaks
        Peaks =: (1{current)(<index,6)}Peaks
        peak =. index{Peaks
        last =. _1
        if. #Registered do.
            last =. {:Registered
        end.
        category =. 4
        update =. 1
        register =. 0
        if. last>:0 do.
            if. (moment-(<last,0){Peaks)<Refractory do.
                category =. 3
                update =. _1
            end.
        end.
        if. category~:3 do.
            if. ((2{peak)>0{current)*.(3{peak)>1{current do.
                twave =. 0
                if. last>:0 do.
                    twave =. ((moment-(<last,0){Peaks)<Twave)*.(2*4{peak)<(<last,4){Peaks
                end.
                if. twave do.
                    category =. 2
                    update =. 1
                else.
                    category =. 0
                    update =. 0
                    register =. 1
                end.
            end.
        end.
        Peaks =: category (<index,7)}Peaks
        if. update>:0 do.
            update update_levels index
        end.
        if. register do.
            register_peak index
        end.
    end.
    search_back #Samples
    0
)
build_beats =: 3 : 0
    Beats =: 0 9$0x
    for_peak_index. Registered do.
        peak =. peak_index{Peaks
        number =. 1+#Beats
        sample =. 0>.(1{peak)-21
        rr =. _1
        hr =. _1
        if. number>1 do.
            rr =. 5*sample-(<((#Beats)-1),1){Beats
            hr =. 6000000 rdiv rr
        end.
        width =. (1{"1 Signals)width_ms 1{peak
        label =. 0
        if. number>:10 do.
            previous =. (number-9)+i.8
            preceding =. +/2{"1 previous{Beats
            if. (800*rr)<PrematurePercent*preceding do.
                label =. 2
                if. width>WidthMs do.
                    label =. 1
                end.
            end.
        end.
        method =. 1=7{peak
        Beats =: Beats,number,sample,rr,hr,width,label,method,_1,0
    end.
    0
)
match_annotations =: 3 : 0
    for_index. i.#Beats do.
        sample =. (<index,1){Beats
        chosen =. _1
        distance =. 0
        for_reference. i.#Annotations do.
            delta =. |((<reference,0){Annotations)-sample
            if. ((<reference,2){Annotations)<0 do.
                if. delta<:MatchMs intdiv 5 do.
                    if. (chosen<0)+.delta<distance do.
                        chosen =. reference
                        distance =. delta
                    end.
                end.
            end.
        end.
        if. chosen>:0 do.
            Beats =: chosen (<index,7)}Beats
            Beats =: (5*sample-(<chosen,0){Annotations)(<index,8)}Beats
            Annotations =: index (<chosen,2)}Annotations
        end.
    end.
    0
)
make_segments =: 3 : 0
    width =. SegmentMs intdiv 5
    Segments =: 0$a:
    for_start. width*i.((#Samples)+width-1)intdiv width do.
        stop =. (#Samples)<.start+width
        selected_refs =. Annotations#~((0{"1 Annotations)>:start)*.(0{"1 Annotations)<stop
        selected_beats =. Beats#~((1{"1 Beats)>:start)*.(1{"1 Beats)<stop
        selected_peaks =. Peaks#~((0{"1 Peaks)>:start)*.(0{"1 Peaks)<stop
        refs =. #selected_refs
        tp =. +/0<:2{"1 selected_refs
        fp =. +/0>7{"1 selected_beats
        noise =. +/4=7{"1 selected_peaks
        rr =. 2{"1 selected_beats
        rr =. rr#~rr>:0
        segment =. (<5*start),(<5*stop),(<refs),(<tp),(<fp),(<refs-tp),(<noise),(<#selected_beats),<rr
        Segments =: Segments,<segment
    end.
    0
)
variability_inputs =: 3 : 0
    RR =: }.2{"1 Beats
    NN =: i.0x
    NNPairs =: 0 2$0x
    selected =. (#Beats)$0
    for_index. 2+i.(#Beats)-2 do.
        previous =. (index-1){Beats
        current =. index{Beats
        if. ((5{previous)=0)*.((5{current)=0)*.(5*|(2{current)-2{previous)<:2{previous do.
            NN =: NN,2{current
            selected =. 1 index}selected
            if. (index-1){selected do.
                NNPairs =: NNPairs,(2{previous),2{current
            end.
        end.
    end.
    'Stats Histogram' =: statistics (<RR),(<NN),<NNPairs
    0
)
beat_csv =: 3 : 0
    result =. <'beat,sample,time_ms,rr_ms,hr_bpm,width_ms,label,method,ref_sample,ref_label'
    for_beat. Beats do.
        'number sample rr hr width label method annotation offset' =. beat
        ref_sample =. '-'
        ref_label =. '-'
        if. annotation>:0 do.
            ref_sample =. text (<annotation,0){Annotations
            ref_label =. ((<annotation,1){Annotations){::Labels
        end.
        heart_rate =. '-'
        if. hr>:0 do.
            heart_rate =. two hr
        end.
        values =. (<text number),(<text sample),(<text 5*sample),(<missing rr),(<heart_rate),(<text width),(<label{::Labels),(<method{::Methods),(<ref_sample),<ref_label
        result =. result,<','join values
    end.
    result
)
peak_csv =: 3 : 0
    result =. <'peak,sample,r_sample,peak_i,peak_f,slope,thr_i,thr_f,class'
    for_index. i.#Peaks do.
        peak =. index{Peaks
        values =. (text&.>(index+1),7{.peak),<(7{peak){::PeakClasses
        result =. result,<','join values
    end.
    result
)
ordered_lines =: 3 : 0
    'keys lines' =. y
    (/:keys){lines
)
matching_csv =: 3 : 0
    keys =. 0 2$0x
    lines =. 0$a:
    for_reference. Annotations do.
        'sample label index' =. reference
        if. index<0 do.
            values =. (<text sample),(<label{::Labels),;:'- - - - FN -'
        else.
            beat =. index{Beats
            agree =. 'no'
            if. label=5{beat do.
                agree =. 'yes'
            end.
            values =. (<text sample),(<label{::Labels),(<text 0{beat),(<text 1{beat),(<(5{beat){::Labels),(<text 8{beat),(<'TP'),<agree
        end.
        keys =. keys,sample,0
        lines =. lines,<','join values
    end.
    for_beat. Beats do.
        if. 0>7{beat do.
            values =. (<'-'),(<'-'),(<text 0{beat),(<text 1{beat),(<(5{beat){::Labels),;:'- FP -'
            keys =. keys,(1{beat),1
            lines =. lines,<','join values
        end.
    end.
    (<'ref_sample,ref_label,beat,beat_sample,beat_label,offset_ms,status,agree'),ordered_lines (<keys),<lines
)
excerpt =: 3 : 0
    result =. <'sample,ecg,lowpass,bandpass,derivative,squared,integrated'
    for_index. i.ExcerptMs intdiv 5 do.
        values =. index,(index{Samples),index{Signals
        result =. result,<csv values
    end.
    result
)
level_line =: 4 : 0
    x,' spki=',(text 0{y),' npki=',(text 1{y),' spkf=',(text 2{y),' npkf=',text 3{y
)
performance =: 3 : 0
    types =. +/(1{"1 Annotations)=/i.3
    detected =. +/(5{"1 Beats)=/i.3
    class_counts =. +/(7{"1 Peaks)=/i.5
    confusion =. 3 4$0
    extras =. 3$0
    method_total =. 2$0
    method_tp =. 2$0
    offsets =. i.0x
    keys =. 0 2$0x
    errors =. 0$a:
    tp =. 0
    fp =. 0
    for_reference. Annotations do.
        'sample label index' =. reference
        if. index>:0 do.
            tp =. tp+1
            location =. label,(<index,5){Beats
        else.
            location =. label,3
            keys =. keys,sample,1
            errors =. errors,<'false_negative sample=',(text sample),' time_ms=',(text 5*sample),' label=',label{::Labels
        end.
        confusion =. (1+(<location){confusion)(<location)}confusion
    end.
    for_beat. Beats do.
        'number sample rr hr width label method annotation offset' =. beat
        method_total =. (1+method{method_total)method}method_total
        if. annotation>:0 do.
            method_tp =. (1+method{method_tp)method}method_tp
            offsets =. offsets,offset
        else.
            fp =. fp+1
            extras =. (1+label{extras)label}extras
            keys =. keys,sample,0
            errors =. errors,<'false_positive beat=',(text number),' sample=',(text sample),' time_ms=',(text 5*sample),' label=',label{::Labels
        end.
    end.
    fn =. (#Annotations)-tp
    class_items =. 0$a:
    for_index. i.5 do.
        class_items =. class_items,<(index{::PeakClasses),'=',text index{class_counts
    end.
    result =. (<'DETECTOR'),(<'samples ',text #Samples),(<'duration_ms ',text 5*#Samples),<'peaks ',(text #Peaks),' ',' 'join class_items
    result =. result,<'initial_levels'level_line InitialLevels
    result =. result,<'final_levels'level_line Levels
    current =. thresholds Levels
    result =. result,<'final_thresholds thr_i=',(text 0{current),' thr_f=',text 1{current
    result =. result,<'final_rr_averages rravg1_ms=',(text 5*RA1),' rravg2_ms=',text 5*RA2
    result =. result,(<'MATCHING'),<'tolerance_ms ',text MatchMs
    result =. result,<'references ',(text #Annotations),' N=',(text 0{types),' V=',(text 1{types),' A=',text 2{types
    result =. result,<'detections ',(text #Beats),' N=',(text 0{detected),' V=',(text 1{detected),' A=',text 2{detected
    result =. result,(<'true_positives ',text tp),(<'false_positives ',text fp),<'false_negatives ',text fn
    result =. result,(<'sensitivity ',tp ratio #Annotations),(<'positive_predictivity ',tp ratio #Beats),<'detection_error_rate ',(fp+fn)ratio #Annotations
    result =. result,<'by_method threshold=',(text 0{method_tp),'/',(text 0{method_total),' searchback=',(text 1{method_tp),'/',text 1{method_total
    if. #offsets do.
        result =. result,<'offset_ms mean=',(two (100*+/offsets)rdiv #offsets),' mean_abs=',(two (100*+/|offsets)rdiv #offsets),' max_abs=',text >./|offsets
    else.
        result =. result,<'offset_ms none'
    end.
    result =. result,(<'CONFUSION'),<'ref  ',(6 pad 'N'),(6 pad 'V'),(6 pad 'A'),'  miss'
    for_label. i.3 do.
        row =. (label{::Labels),'    '
        for_value. label{confusion do.
            row =. row,6 pad text value
        end.
        result =. result,<row
    end.
    row =. 'extra'
    for_value. extras do.
        row =. row,6 pad text value
    end.
    result =. result,<row
    for_label. 1 2 do.
        prefix =. 'veb'
        if. label=2 do.
            prefix =. 'sveb'
        end.
        correct =. (<label,label){confusion
        result =. result,<prefix,'_sensitivity ',correct ratio label{types
        result =. result,<prefix,'_positive_predictivity ',correct ratio label{detected
    end.
    result =. result,<'SEGMENTS segment_ms=',(text SegmentMs),' segments=',text #Segments
    for_box. Segments do.
        'start stop refs tp fp fn noise count rr' =. >box
        result =. result,<(6 pad text start),'-',(6 pad text stop),' refs=',(text refs),' tp=',(text tp),' fp=',(text fp),' fn=',(text fn),' noise_peaks=',text noise
    end.
    result =. result,<'ERRORS count=',text #errors
    result,ordered_lines (<keys),<errors
)
event_lines =: 3 : 0
    result =. 0$a:
    for_index. 1+i.(#Beats)-1 do.
        rr =. (<index,2){Beats
        if. rr>PauseMs do.
            result =. result,<'pause beats=',(text index),'-',(text index+1),' rr_ms=',(text rr),' start_ms=',text 5*(<(index-1),1){Beats
        end.
    end.
    for_kind. 0 1 do.
        selected =. i.0
        for_index. 1+i.(#Beats)-1 do.
            rr =. (<index,2){Beats
            if. ((kind=0)*.rr>BradyMs)+.((kind=1)*.rr<TachyMs) do.
                selected =. selected,index+1
            end.
        end.
        name =. kind{::'bradycardia';'tachycardia'
        for_span. consecutive_ranges selected do.
            'first last' =. span
            count =. (last-first)+1
            if. count>:3 do.
                intervals =. 2{"1 ((first-1)+i.count){Beats
                mean =. two (6000000*count)rdiv +/intervals
                start =. 5*(<(first-2),1){Beats
                result =. result,<name,' beats=',(text first-1),'-',(text last),' intervals=',(text count),' mean_hr=',mean,' start_ms=',text start
            end.
        end.
    end.
    ventricular =. 1+I.1=5{"1 Beats
    for_interval. 2 3 do.
        chains =. 0$a:
        for_number. ventricular do.
            linked =. 0
            last =. (#chains)-1
            if. last>:0 do.
                chain =. last{::chains
                if. number=interval+{:chain do.
                    between =. ({:chain)+i.interval-1
                    between =. between+1
                    linked =. *./0=5{"1 (between-1){Beats
                end.
            end.
            if. linked do.
                chains =. (<chain,number)last}chains
            else.
                chains =. chains,<,number
            end.
        end.
        name =. 'bigeminy'
        if. interval=3 do.
            name =. 'trigeminy'
        end.
        for_box. chains do.
            chain =. >box
            if. 3<:#chain do.
                result =. result,<name,' beats=',(text {.chain),'-',(text {:chain),' cycles=',(text #chain),' start_ms=',text 5*(<(({.chain)-1),1){Beats
            end.
        end.
    end.
    result
)
variability =: 3 : 0
    result =. (<'RR'),(<'beats ',text #Beats),(<'intervals ',text #RR),<'mean_rr_ms ',maybe_two 0{Stats
    if. #RR do.
        shortest =. 2{Stats
        longest =. 3{Stats
        result =. result,(<'min_rr_ms ',(text shortest{RR),' beat=',text shortest+2),(<'max_rr_ms ',(text longest{RR),' beat=',text longest+2),<'mean_hr_bpm ',two 1{Stats
    else.
        result =. result,<'min_rr_ms none'
        result =. result,<'max_rr_ms none'
        result =. result,<'mean_hr_bpm none'
    end.
    result =. result,(<'NN'),(<'intervals ',text #NN),(<'mean_nn_ms ',maybe_two 4{Stats),<'sdnn_ms ',maybe_two 5{Stats
    result =. result,(<'differences ',text #NNPairs),(<'rmssd_ms ',maybe_two 6{Stats),(<'sdsd_ms ',maybe_two 7{Stats),<'nn50 ',text 8{Stats
    if. 0>9{Stats do.
        result =. result,<'pnn50 none'
    else.
        result =. result,<'pnn50 ',(two 9{Stats),'%'
    end.
    result =. result,(<'sd1_ms ',maybe_two 10{Stats),(<'sd2_ms ',maybe_two 11{Stats),<'HISTOGRAM bin_ms=7.8125 bins=',(text #Histogram),' max=',text 12{Stats
    for_bucket. Histogram do.
        'number count' =. bucket
        result =. result,<(10 pad four 78125*number),' ',(10 pad four 78125*number+1),' ',(3 pad text count),' |',count#'#'
    end.
    if. #NN do.
        result =. result,<'triangular_index ',((#NN)fraction 12{Stats),' ',two 13{Stats
    else.
        result =. result,<'triangular_index none'
    end.
    premature =. Beats#~0~:5{"1 Beats
    counts =. +/(5{"1 premature)=/1 2
    result =. result,<'PREMATURE count=',(text #premature),' V=',(text 0{counts),' A=',text 1{counts
    for_beat. premature do.
        'number sample rr hr width label method annotation offset' =. beat
        preceding =. +/2{"1 ((number-9)+i.8){Beats
        next_rr =. _1
        compensation =. '-'
        if. number<#Beats do.
            next_rr =. (<number,2){Beats
            total =. rr+next_rr
            if. (10*|(4*total)-preceding)<:preceding do.
                compensation =. 'full'
            elseif. (4*total)<preceding do.
                compensation =. 'partial'
            else.
                compensation =. 'long'
            end.
        end.
        reference =. '-'
        if. annotation>:0 do.
            reference =. ((<annotation,1){Annotations){::Labels
        end.
        mean =. two (100*preceding)rdiv 8
        prematurity =. two (80000*rr)rdiv preceding
        result =. result,<'beat=',(text number),' sample=',(text sample),' label=',(label{::Labels),' rr_ms=',(text rr),' next_rr_ms=',(missing next_rr),' mean_ms=',mean,' prematurity=',prematurity,'% compensation=',compensation,' width_ms=',(text width),' ref=',reference
    end.
    keys =. 0 2$0x
    runs =. 0$a:
    for_label. 1 2 do.
        indices =. 1+I.label=5{"1 Beats
        for_span. consecutive_ranges indices do.
            'first last' =. span
            count =. (last-first)+1
            kind =. 'run'
            if. count=1 do.
                kind =. 'isolated'
            elseif. count=2 do.
                kind =. 'couplet'
            end.
            keys =. keys,first,0
            runs =. runs,<(label{::Labels),' ',kind,' beats=',(text first),'-',(text last),' length=',(text count),' start_ms=',text 5*(<(first-1),1){Beats
        end.
    end.
    result =. result,<'RUNS count=',text #runs
    result =. result,ordered_lines (<keys),<runs
    events =. event_lines 0
    result =. result,(<'EVENTS count=',text #events),events
    result =. result,<'TREND segment_ms=',(text SegmentMs),' segments=',text #Segments
    for_box. Segments do.
        'start stop refs tp fp fn noise count rr' =. >box
        prefix =. (6 pad text start),'-',(6 pad text stop),' beats=',(text count),' '
        if. 0=#rr do.
            result =. result,<prefix,'mean_hr=none min_hr=none max_hr=none |'
        else.
            mean =. (6000000*#rr)rdiv +/rr
            low =. two 6000000 rdiv >./rr
            high =. two 6000000 rdiv <./rr
            result =. result,<prefix,'mean_hr=',(two mean),' min_hr=',low,' max_hr=',high,' |',(mean rdiv 500)#'#'
        end.
    end.
    result
)
scale =: 3 : 0
    'value top bottom rows' =. y
    if. top>bottom do.
        ((top-value)*(rows-1))rdiv top-bottom
    else.
        0
    end.
)
axis =: 3 : 0
    'columns period offset' =. y
    cells =. columns#'-'
    if. period>0 do.
        cells =. '+'(I.0=period|offset+i.columns)}cells
    end.
    '       +',cells,'+'
)
chart_labels =: 3 : 0
    'heading columns values' =. y
    result =. (6 pad heading),'  '
    for_index. i.#columns do.
        gap =. (8+index{columns)-#result
        result =. result,((0>.gap)#' '),index{::values
    end.
    while. ' '={:result do.
        result =. }:result
    end.
    result
)
waveform =: 3 : 0
    'upper lower height' =. y
    top =. >./upper
    bottom =. <./lower
    zero =. _1
    if. (bottom<:0)*.top>:0 do.
        zero =. scale 0,top,bottom,height
    end.
    result =. 0$a:
    for_row. i.height do.
        label =. ''
        if. row=0 do.
            label =. text top
        elseif. row=height-1 do.
            label =. text bottom
        elseif. row=zero do.
            label =. '0'
        end.
        cells =. ''
        for_column. i.#upper do.
            high_row =. scale (column{upper),top,bottom,height
            low_row =. scale (column{lower),top,bottom,height
            if. (high_row<:row)*.row<:low_row do.
                cells =. cells,'#'
            elseif. row=zero do.
                cells =. cells,'-'
            else.
                cells =. cells,' '
            end.
        end.
        result =. result,<(6 pad label),' |',cells,'|'
    end.
    result
)
charts =: 3 : 0
    height =. ChartRows
    result =. 0$a:
    if. #RR do.
        low =. <./RR
        high =. >./RR
        result =. result,<'TACHOGRAM intervals=',(text #RR),' min_ms=',(text low),' max_ms=',(text high),' rows=',text height
        for_row. i.height do.
            label =. ''
            if. row=0 do.
                label =. text high
            elseif. row=height-1 do.
                label =. text low
            end.
            cells =. ''
            for_value. RR do.
                cells =. cells,((row=scale value,high,low,height){' *')
            end.
            result =. result,<(6 pad label),' |',cells,'|'
        end.
        result =. result,<axis (#RR),10,2
        columns =. I.0=10|2+i.#RR
        values =. text&.>columns+2
        result =. result,<chart_labels (<'beat'),(<columns),<values
        labels =. ;(}.5{"1 Beats){Labels
        result =. result,<' label |',labels,'|'
        size =. PoincareSize
        grid =. (size,size)$0
        for_index. i.(#RR)-1 do.
            column =. 0
            if. high>low do.
                column =. (((index{RR)-low)*(size-1))rdiv high-low
            end.
            row =. scale ((index+1){RR),high,low,size
            grid =. (1+(<row,column){grid)(<row,column)}grid
        end.
        result =. result,<'POINCARE points=',(text (#RR)-1),' size=',(text size),' min_ms=',(text low),' max_ms=',text high
        for_row. i.size do.
            label =. ''
            if. row=0 do.
                label =. text high
            elseif. row=size-1 do.
                label =. text low
            end.
            cells =. ''
            for_count. row{grid do.
                if. count=0 do.
                    cells =. cells,'.'
                elseif. count<10 do.
                    cells =. cells,text count
                else.
                    cells =. cells,'#'
                end.
            end.
            result =. result,<(6 pad label),' |',cells,'|'
        end.
        result =. result,<axis size,0,0
        line =. '        ',text low
        high_text =. text high
        gap =. ((8+size)-#high_text)-#line
        result =. result,<line,((0>.gap)#' '),high_text
    else.
        result =. result,(<'TACHOGRAM intervals=0'),<'POINCARE points=0'
    end.
    for_label. i.3 do.
        mask =. ((5{"1 Beats)=label)*.((1{"1 Beats)>:60)*.(1{"1 Beats)<:(#Samples)-100
        chosen =. Beats#~mask
        name =. label{::Labels
        if. 0=#chosen do.
            result =. result,<'TEMPLATE ',name,' beats=0'
            continue.
        end.
        baselines =. i.0x
        for_beat. chosen do.
            sample =. 1{beat
            baselines =. baselines,+/((sample-60)+i.10){Samples
        end.
        averaged =. i.0x
        for_offset. _60+i.160 do.
            total =. 0x
            for_index. i.#chosen do.
                sample =. (<index,1){chosen
                total =. total+((10*(sample+offset){Samples)-index{baselines)
            end.
            averaged =. averaged,total rdiv 10*#chosen
        end.
        low =. <./averaged
        high =. >./averaged
        minimum =. (averaged i.low)-60
        maximum =. (averaged i.high)-60
        result =. result,<'TEMPLATE ',name,' beats=',(text #chosen),' max_uv=',(text high),' max_ms=',(text 5*maximum),' min_uv=',(text low),' min_ms=',(text 5*minimum),' rows=',text height
        pairs =. 80 2$averaged
        upper =. >./"1 pairs
        lower =. <./"1 pairs
        result =. result,waveform (<upper),(<lower),<height
        result =. result,<axis 80,10,0
        columns =. 10*i.8
        values =. text&.>(10*columns)-300
        result =. result,<chart_labels (<'ms'),(<columns),<values
    end.
    result
)
rhythm_strip =: 3 : 0
    start =. StripStartMs intdiv 5
    count =. StripMs intdiv 5
    columns =. count intdiv 10
    selected =. (start+i.count){Samples
    bins =. (columns,10)$selected
    upper =. >./"1 bins
    lower =. <./"1 bins
    result =. <'RHYTHM start_ms=',(text StripStartMs),' end_ms=',(text StripStartMs+StripMs),' columns=',(text columns),' rows=',(text StripRows),' max_uv=',(text >./upper),' min_uv=',text <./lower
    result =. result,waveform (<upper),(<lower),<StripRows
    result =. result,<axis columns,20,0
    positions =. 20*i.(columns+19)intdiv 20
    values =. text&.>(StripStartMs+50*positions)intdiv 1000
    result =. result,<chart_labels (<'s'),(<positions),<values
    beat_marks =. columns#' '
    ref_marks =. columns#' '
    for_beat. Beats do.
        sample =. 1{beat
        if. (sample>:start)*.sample<start+count do.
            column =. (sample-start)intdiv 10
            beat_marks =. ((5{beat){'NVA')column}beat_marks
        end.
    end.
    for_reference. Annotations do.
        sample =. 0{reference
        if. (sample>:start)*.sample<start+count do.
            column =. (sample-start)intdiv 10
            ref_marks =. ((1{reference){'NVA')column}ref_marks
        end.
    end.
    result,(<' beats |',beat_marks,'|'),<'  refs |',ref_marks,'|'
)
run =: 3 : 0
    Samples =: read_ecg 0
    Annotations =: read_annotations 0
    'Refractory Twave SearchbackPercent PrematurePercent WidthMs MatchMs PauseMs BradyMs TachyMs ExcerptMs SegmentMs StripStartMs StripMs StripRows ChartRows PoincareSize' =: read_params 0
    Refractory =: Refractory intdiv 5
    Twave =: Twave intdiv 5
    Signals =: filter_ecg Samples
    Peaks =: find_peaks Signals
    detect 0
    build_beats 0
    match_annotations 0
    make_segments 0
    variability_inputs 0
    try.
        1!:5 <'output'
    catch.
    end.
    'beats.csv'save_lines beat_csv 0
    'peaks.csv'save_lines peak_csv 0
    'matching.csv'save_lines matching_csv 0
    'signals_excerpt.csv'save_lines excerpt 0
    'performance.txt'save_lines performance 0
    'hrv.txt'save_lines variability 0
    'charts.txt'save_lines charts 0
    'rhythm_strip.txt'save_lines rhythm_strip 0
    0
)
run 0
