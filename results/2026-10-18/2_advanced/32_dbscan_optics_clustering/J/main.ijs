split =: 4 : '<;._1 x,y'
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
num =: 3 : 'x: 0".y'
intdiv =: 4 : '<.(x: x)%x: y'
text =: 3 : 0
    if. 2=3!:0 y do.
        y return.
    end.
    result =. ":y
    '-'(I.result='_')}result
)
line =: 3 : ''' ''join text&.>y'
joined =: 3 : ''' ''join text&.>y'
load 'dataset.ijs'
load 'grid_index.ijs'
load 'dbscan.ijs'
load 'optics.ijs'
load 'report.ijs'
label_char =: 3 : 0
    if. y<0 do.
        '.' return.
    end.
    if. y<52 do.
        y{'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'
    else.
        '#'
    end.
)
value_text =: 3 : 0
    if. y=INF do.
        '-'
    else.
        text y
    end.
)
optional =: 3 : 0
    if. y<0 do.
        '-'
    else.
        text y
    end.
)
root =: 3 : 0
    if. y=INF do.
        '-'
    else.
        root_text y
    end.
)
check =: 3 : 'y{::''mismatch'';''ok'''
condition =: 3 : 'y{::''fail'';''ok'''
integer_root =: 3 : 0
    low =. 0x
    high =. y+1
    while. 1<high-low do.
        middle =. (low+high)intdiv 2
        if. middle<:y intdiv middle do.
            low =. middle
        else.
            high =. middle
        end.
    end.
    low
)
suggested =: 3 : 0
    radius =. integer_root y
    if. y>radius*radius do.
        radius =. radius+1
    end.
    1>.radius
)
c_source =: 0&{::
c_order =: 1&{::
c_values =: 2&{::
c_knee =: 3&{::
c_cross =: 4&{::
c_eps =: 5&{::
make_curve =: 3 : 0
    order =. /:(-y),.i.#y
    values =. order{y
    crosses =. |((<:#y)*values-{.values)-(({:values)-{.values)*i.#y
    cross =. >./crosses
    knee =. crosses i.cross
    (<y),(<order),(<values),(<knee),(<cross),<suggested knee{values
)
s_name =: 0&{::
s_kind =: 1&{::
s_radius =: 2&{::
s_labels =: 3&{::
s_core =: 4&{::
s_count =: 5&{::
s_members =: 6&{::
s_noise =: 7&{::
s_core_count =: 8&{::
s_border =: 9&{::
make_setting =: 3 : 0
    'name kind radius labels core' =. y
    count =. 1+>./labels
    members =. 0$a:
    for_label. i.count do.
        members =. members,<I.labels=label
    end.
    noise =. +/labels=_1
    core_count =. +/(labels>:0)*.core
    (<name),(<kind),(<radius),(<labels),(<core),(<count),(<members),(<noise),(<core_count),<((#labels)-noise)-core_count
)
extract =: 3 : 0
    limit =. y*y
    labels =. N$_1
    cluster =. _1
    for_point. Ordering do.
        if. limit<point{Reach do.
            if. limit>:point{Core do.
                cluster =. cluster+1
                labels =. cluster point}labels
            end.
        else.
            labels =. cluster point}labels
        end.
    end.
    (<labels),<Core<:limit
)
neighborhoods =: 3 : 0
    3{::(GridRadii i.y){::Grids
)
db_settings =: 3 : 'Settings#~(s_kind&.>Settings)e.<''dbscan'''
extract_settings =: 3 : 'Settings#~(s_kind&.>Settings)e.<''extract'''
xle =: 4 : 0
    if. y=INF do.
        1 return.
    end.
    if. x=INF do.
        0 return.
    end.
    (XiBeta*x)<:XiAlpha*y
)
region_end =: 3 : 0
    'start steep reverse' =. y
    finish =. start
    flat =. 0
    for_position. start+i.N-start do.
        if. position{steep do.
            finish =. position
            flat =. 0
        elseif. position{reverse do.
            break.
        else.
            flat =. flat+1
            if. flat>MinPts do.
                break.
            end.
        end.
    end.
    finish
)
compute_xi =: 3 : 0
    XiAlpha =: *:XiV-XiU
    XiBeta =: *:XiV
    steep_up =. steep_down =. up =. down =. i.0
    for_i. i.N do.
        first =. i{Positions
        second =. (i+1){Positions
        defined =. (first~:INF)+.second~:INF
        steep_up =. steep_up,defined*.first xle second
        steep_down =. steep_down,defined*.second xle first
        up =. up,first<second
        down =. down,first>second
    end.
    areas =. 0$a:
    clusters =. 0 2$0
    down_areas =. 0 3$0
    index =. 0
    mib =. 0
    for_start. i.N do.
        if. (start<index)+.-.((start{steep_up)+.start{steep_down) do.
            continue.
        end.
        mib =. mib>.>./((index+i.1+start-index){Positions)
        if. mib=INF do.
            down_areas =. 0 3$0
        else.
            retained =. 0 3$0
            for_area. down_areas do.
                if. mib xle ({.area){Positions do.
                    area =. ((2{area)>.mib)2}area
                    retained =. retained,area
                end.
            end.
            down_areas =. retained
        end.
        if. start{steep_down do.
            finish =. region_end (<start),(<steep_down),<up
            areas =. areas,< 'down';start;finish
            down_areas =. down_areas,start,finish,0
            index =. finish+1
            mib =. index{Positions
        else.
            finish =. region_end (<start),(<steep_up),<down
            areas =. areas,< 'up';start;finish
            index =. finish+1
            mib =. index{Positions
            candidates =. 0 2$0
            for_area. down_areas do.
                'first down_end high' =. area
                last =. finish
                if. -.high xle (last+1){Positions do.
                    continue.
                end.
                top =. first{Positions
                if. ((last+1){Positions)xle top do.
                    while. (first<down_end)*.((first+1){Positions)>(last+1){Positions do.
                        first =. first+1
                    end.
                elseif. top xle (last+1){Positions do.
                    while. (last>start)*.((last-1){Positions)>top do.
                        last =. last-1
                    end.
                end.
                if. ((1+last-first)>:XiMinSize)*.(first<:down_end)*.last>:start do.
                    candidates =. candidates,first,last
                end.
            end.
            clusters =. clusters,|.candidates
        end.
    end.
    labels =. N$_1
    cluster_labels =. (#clusters)$_1
    parents =. (#clusters)$_1
    walls =. 0 3$0
    next_label =. 0
    for_number. i.#clusters do.
        'first last' =. number{clusters
        positions =. first+i.1+last-first
        if. *./_1=positions{labels do.
            labels =. next_label positions}labels
            cluster_labels =. next_label number}cluster_labels
            next_label =. next_label+1
        end.
        valley =. <./(first+1+i.last-first){Positions
        walls =. walls,(first{Positions),((last+1){Positions),valley
        best =. _1
        best_size =. 0
        for_other. i.#clusters do.
            'a b' =. other{clusters
            size =. 1+b-a
            own_size =. 1+last-first
            if. (other~:number)*.(a<:first)*.(b>:last)*.((size>own_size)+.(size=own_size)*.other>number) do.
                if. (best<0)+.size<best_size do.
                    best =. other
                    best_size =. size
                end.
            end.
        end.
        parents =. best number}parents
    end.
    (<areas),(<clusters),(<labels),(<cluster_labels),(<parents),<walls
)
turn =: 3 : 0
    'origin first second' =. y
    a =. first-origin
    b =. second-origin
    ((0{a)*1{b)-(1{a)*0{b
)
hull_half =: 3 : 0
    chain =. i.0
    for_point. y do.
        while. 2<:#chain do.
            area =. turn (<(_2{chain){Points),(<(_1{chain){Points),<point{Points
            if. area>0 do.
                break.
            end.
            chain =. }:chain
        end.
        chain =. chain,point
    end.
    chain
)
convex_hull =: 3 : 0
    ordered =. y /:y{Points
    if. 2>:#ordered do.
        ordered return.
    end.
    (}:hull_half ordered),}:hull_half |.ordered
)
cluster_lines =: 4 : 0
    setting =. x
    label =. y
    members =. label{::s_members setting
    size =. #members
    core_count =. +/members{s_core setting
    coordinates =. members{Points
    'sx sy' =. +/coordinates
    scores =. +/"1 *:(size*coordinates)-"1 sx,sy
    medoid =. (scores i.<./scores){members
    'xmin ymin' =. <./coordinates
    'xmax ymax' =. >./coordinates
    area =. (1+xmax-xmin)*1+ymax-ymin
    hull =. convex_hull members
    doubled =. diameter =. 0
    for_position. i.#hull do.
        first =. (position{hull){Points
        second =. (((#hull)|position+1){hull){Points
        doubled =. doubled+((0{first)*1{second)-(0{second)*1{first
        for_other. hull do.
            diameter =. diameter>.first squared_distance other{Points
        end.
    end.
    doubled =. |doubled
    half =. (text doubled intdiv 2),'.',(2|doubled){'05'
    first_line =. line 'cluster';label;(label_char label);'size';size;'core';core_count;'border';(size-core_count);'centroid';(sx fraction_text size);(sy fraction_text size);'medoid';medoid{Ids
    second_line =. line ' ';'bbox';xmin;ymin;xmax;ymax;'area';area;'density';size fraction_text area
    third_line =. line ' ';'hull';(#hull);'hull_area';half;'diameter_sq';diameter;'diameter';root diameter
    (<first_line),(<second_line),<third_line
)
pair_count =: 3 : '(y*y-1)intdiv 2'
pair_sum =: 3 : 0
    result =. 0
    for_label. ~.y do.
        result =. result+pair_count +/y=label
    end.
    result
)
adjusted_rand =: 4 : 0
    same =. 0
    for_first. ~.x do.
        for_second. ~.y do.
            same =. same+pair_count +/(x=first)*.y=second
        end.
    end.
    a =. pair_sum x
    b =. pair_sum y
    total =. pair_count #x
    numerator =. 2*(total*same)-a*b
    denominator =. (total*(a+b))-2*a*b
    if. denominator=0 do.
        1 ari_text 1
    else.
        numerator ari_text denominator
    end.
)
labels_lines =: 3 : 0
    result =. ,<'id,',','join s_name&.>Settings
    for_point. i.N do.
        fields =. ,<text point{Ids
        for_setting. Settings do.
            fields =. fields,<text point{s_labels >setting
        end.
        result =. result,<','join fields
    end.
    result
)
optics_lines =: 3 : 0
    result =. ,<'order,id,core_sq,reach_sq,reach,predecessor'
    for_position. i.N do.
        point =. position{Ordering
        prior =. point{Predecessor
        predecessor_id =. '-'
        if. prior>:0 do.
            predecessor_id =. text prior{Ids
        end.
        fields =. (<text position+1),(<text point{Ids),(<value_text point{Core),(<value_text point{Reach),(<root point{Reach),<predecessor_id
        result =. result,<','join fields
    end.
    result
)
kdist_lines =: 3 : 0
    result =. (<line 'k_distance';'k';(MinPts-1);'points';N),<'rank id kdist_sq kdist'
    for_rank. i.N do.
        value =. rank{c_values Curve
        result =. result,<line (rank+1);((rank{c_order Curve){Ids);value;root value
    end.
    knee =. c_knee Curve
    value =. knee{c_values Curve
    result =. result,(<''),(<line 'knee';'rank';(knee+1);'id';((knee{c_order Curve){Ids);'kdist_sq';value;'kdist';(root value);'cross';c_cross Curve),(<line 'suggested_eps';c_eps Curve),(<''),<'knee_table'
    for_rank. i.#Curves do.
        row =. rank{::Curves
        knee =. c_knee row
        result =. result,<line 'k';(rank+1);'rank';(knee+1);'id';((knee{c_order row){Ids);'kdist_sq';(knee{c_values row);'eps';c_eps row
    end.
    result =. result,(<''),<'core_check'
    for_box. db_settings 0 do.
        setting =. >box
        radius =. s_radius setting
        core =. +/Kdist<:radius*radius
        grid_core =. +/s_core setting
        result =. result,<line 'eps';radius;'core';core;'non_core';(N-core);'grid_core';grid_core;check core=grid_core
    end.
    defined =. I.Core~:INF
    consistent =. *./(defined{Core)=defined{Kdist
    result,<line 'optics';'max_eps';MaxEps;'core';(#defined);check consistent
)
grid_lines =: 3 : 0
    result =. ,<'grid'
    for_box. Grids do.
        'radius cells members neighbors candidates busiest pairs brute_pairs consistent sizes counts' =. >box
        'gx gy' =. busiest{::cells
        size =. #busiest{::members
        result =. result,<line 'eps';radius;'cells';(#cells);'busiest';gx;gy;size;'candidates';candidates;'pairs';pairs;'brute_pairs';brute_pairs;check consistent
        occupancy =. 0$a:
        for_i. i.#sizes do.
            occupancy =. occupancy,<(text i{sizes),':',text i{counts
        end.
        result =. result,<'  occupancy ',' 'join occupancy
    end.
    result
)
check_lines =: 3 : 0
    labels =. s_labels y
    core =. s_core y
    neighbors =. neighborhoods s_radius y
    linked =. supported =. separated =. 1
    isolated =. 0
    ambiguous =. 0$a:
    for_point. i.N do.
        row =. point{::neighbors
        label =. point{labels
        core_labels =. labels{~row#~row{core
        if. point{core do.
            linked =. linked*.*./core_labels=label
        elseif. label>:0 do.
            supported =. supported*.label e.core_labels
            others =. /:~~.core_labels-.label
            if. #others do.
                ambiguous =. ambiguous,<line ' ';(point{Ids);'cluster';label;'also';joined others
            end.
        else.
            separated =. separated*.0=#core_labels
            isolated =. isolated+1=#row
        end.
    end.
    (<line 'check';(condition linked);(condition supported);condition separated),(<line 'isolated';isolated),(<line 'ambiguous';#ambiguous),ambiguous
)
setting_lines =: 3 : 0
    result =. ,<line 'setting';(s_name y);'eps';(s_radius y);'clusters';(s_count y);'noise';(s_noise y);'core';(s_core_count y);'border';s_border y
    for_label. i.s_count y do.
        result =. result,y cluster_lines label
    end.
    if. 'dbscan'-:s_kind y do.
        result =. result,check_lines y
    end.
    result
)
hierarchy_lines =: 3 : 0
    values =. db_settings 0
    values =. values /:s_radius&>values
    result =. ,<'hierarchy'
    for_pair. i.(#values)-1 do.
        smaller =. pair{::values
        larger =. (pair+1){::values
        sources =. (s_count larger)$<i.0
        members =. s_members smaller
        for_cluster. i.s_count smaller do.
            group =. cluster{::members
            first_core =. {.group#~group{s_core smaller
            destination =. first_core{s_labels larger
            sources =. (<(destination{::sources),cluster)destination}sources
        end.
        result =. result,<(s_name smaller),' -> ',s_name larger
        for_label. i.s_count larger do.
            group =. label{::sources
            clusters =. '-'
            if. #group do.
                clusters =. joined group
            end.
            result =. result,<line ' ';label;'<-';clusters
        end.
    end.
    result
)
comparison_lines =: 3 : 0
    result =. ,<'optics_vs_dbscan'
    for_box. extract_settings 0 do.
        extracted =. >box
        references =. (db_settings 0)#~(s_radius&>db_settings 0)=s_radius extracted
        if. 0=#references do.
            continue.
        end.
        original =. 0{::references
        first =. s_labels extracted
        second =. s_labels original
        pairs =. ~.(I.s_core extracted){first,.second
        same =. ((#pairs)=#~.0{"1 pairs)*.(#pairs)=#~.1{"1 pairs
        border =. +/(first=_1)*.second>:0
        moved =. '-'
        if. same do.
            changes =. 0
            for_point. I.first>:0 do.
                corresponding =. 1{((0{"1 pairs)i.point{first){pairs
                changes =. changes+corresponding~:point{second
            end.
            moved =. text changes
        end.
        partition =. 'different'
        if. same do.
            partition =. 'same'
        end.
        result =. result,<line (s_name extracted);(s_name original);'core_partition';partition;'border_as_noise';border;'moved';moved
    end.
    result
)
optics_summary =: 3 : 0
    starts =. I.INF=Ordering{Reach
    sizes =. (}.starts,N)-starts
    ,<line 'optics';'max_eps';MaxEps;'core';(+/Core~:INF);'components';(#sizes);'singletons';(+/sizes=1);'largest';>./sizes
)
sweep_lines =: 3 : 0
    result =. (<line 'sweep';'max_eps';MaxEps),<'eps clusters noise largest'
    counts =. i.0
    for_radius. 1+i.MaxEps do.
        'labels core' =. extract radius
        clusters =. 1+>./labels
        sizes =. i.0
        for_label. i.clusters do.
            sizes =. sizes,+/labels=label
        end.
        counts =. counts,clusters
        largest =. 0
        if. #sizes do.
            largest =. >./sizes
        end.
        result =. result,<line radius;clusters;(+/labels=_1);largest
    end.
    first =. 0
    best_start =. best_end =. _1
    for_radius. i.MaxEps do.
        if. radius<MaxEps-1 do.
            if. ((radius+1){counts)=first{counts do.
                continue.
            end.
        end.
        if. ((first{counts)>:2)*.((best_start<0)+.(radius-first)>best_end-best_start) do.
            best_start =. first
            best_end =. radius
        end.
        first =. radius+1
    end.
    if. best_start<0 do.
        result,<'stable -'
    else.
        result,<line 'stable';'clusters';(best_start{counts);'eps';(best_start+1);(best_end+1);'length';1+best_end-best_start
    end.
)
xi_lines =: 3 : 0
    'areas clusters labels cluster_labels parents walls' =. Xi
    result =. ,<line 'xi';XiText;'min_size';XiMinSize;'steep_areas';#areas
    for_area. areas do.
        result =. result,<line >area
    end.
    result =. result,<line 'xi_clusters';#clusters
    for_number. i.#clusters do.
        'first last' =. number{clusters
        'left right valley' =. number{walls
        result =. result,<line number;'start';(first+1);'end';(last+1);'size';(1+last-first);'label';(optional number{cluster_labels);'parent';(optional number{parents);'walls';(root left);(root right);'valley';root valley
    end.
    result
)
outlier_lines =: 3 : 0
    core_points =. I.s_core Knee
    rows =. 0 3$0
    for_point. I._1=s_labels Knee do.
        nearest =. _1
        best =. INF
        for_other. core_points do.
            distance =. (point{Points)squared_distance other{Points
            if. distance<best do.
                nearest =. other
                best =. distance
            end.
        end.
        rows =. rows,best,point,nearest
    end.
    rows =. rows /:(-0{"1 rows),.1{"1 rows
    result =. ,<line 'outliers';(s_name Knee);'count';#rows
    for_row. rows do.
        'distance point nearest' =. row
        result =. result,<line (point{Ids);'nearest_core';(nearest{Ids);'cluster';(nearest{s_labels Knee);'dist_sq';distance;'dist';root distance
    end.
    result
)
gap_lines =: 3 : 0
    result =. ,<'gaps ',s_name Knee
    members =. s_members Knee
    for_first. i.s_count Knee do.
        for_second. (first+1)+i.((s_count Knee)-(first+1)) do.
            best =. INF
            a =. b =. _1
            for_point. first{::members do.
                for_other. second{::members do.
                    distance =. (point{Points)squared_distance other{Points
                    if. distance<best do.
                        best =. distance
                        a =. point
                        b =. other
                    end.
                end.
            end.
            result =. result,<line first;second;'dist_sq';best;'dist';(root best);'between';(a{Ids);b{Ids
        end.
    end.
    result
)
contingency_lines =: 3 : 0
    table =. ((1+s_count Knee),(1+s_count XiSetting))$0
    for_point. i.N do.
        position =. (1+point{s_labels Knee),1+point{s_labels XiSetting
        table =. (>:(<position){table)(<position)}table
    end.
    result =. (<'contingency ',(s_name Knee),' xi'),<'columns ',joined _1+i.1+s_count XiSetting
    for_row. i.1+s_count Knee do.
        result =. result,<line (row-1);joined row{table
    end.
    for_column. i.s_count XiSetting do.
        values =. (column+1){"1 }.table
        shared =. >./values
        matched =. values i.shared
        union =. ((#matched{::s_members Knee)+#column{::s_members XiSetting)-shared
        result =. result,<line 'match';column;matched;'shared';shared;'jaccard';shared fraction_text union
    end.
    result
)
ari_lines =: 3 : 0
    result =. ,<'ari'
    for_first. i.#Settings do.
        for_second. (first+1)+i.((#Settings)-(first+1)) do.
            a =. first{::Settings
            b =. second{::Settings
            result =. result,<line (s_name a);(s_name b);(s_labels a)adjusted_rand s_labels b
        end.
    end.
    result
)
clusters_lines =: 3 : 0
    header =. (<line 'points';N;'min_pts';MinPts),<'settings ',' 'join s_name&.>Settings
    parts =. (<header),<grid_lines 0
    for_setting. Settings do.
        parts =. parts,<setting_lines >setting
    end.
    parts =. parts,(<hierarchy_lines 0),(<comparison_lines 0),(<optics_summary 0),(<sweep_lines 0),(<xi_lines 0),(<outlier_lines 0),(<gap_lines 0),(<contingency_lines 0),<ari_lines 0
    result =. 0$a:
    for_i. i.#parts do.
        if. i do.
            result =. result,<''
        end.
        result =. result,i{::parts
    end.
    result
)
cell_members =: 3 : 'I.(MapColumns={.y)*.MapRows={:y'
cluster_map =: 3 : 0
    labels =. s_labels y
    rows =. 0$a:
    for_row. i.MapHeight do.
        characters =. ''
        for_column. i.MapWidth do.
            members =. cell_members column,row
            clusters =. ~.(members{labels)-._1
            character =. ' '
            if. #members do.
                character =. '.'
                if. 1=#clusters do.
                    character =. label_char {.clusters
                elseif. 1<#clusters do.
                    character =. '*'
                end.
            end.
            characters =. characters,character
        end.
        rows =. rows,<characters
    end.
    rows
)
kind_map =: 3 : 0
    rows =. 0$a:
    for_row. i.MapHeight do.
        characters =. ''
        for_column. i.MapWidth do.
            members =. cell_members column,row
            character =. ' '
            if. #members do.
                character =. '.'
                if. +./(members{s_labels Knee)>:0 do.
                    character =. '+'
                end.
                if. +./members{s_core Knee do.
                    character =. '#'
                end.
            end.
            characters =. characters,character
        end.
        rows =. rows,<characters
    end.
    rows
)
kdist_plot =: 3 : 0
    heights =. i.0
    knee_column =. 0
    values =. c_values Curve
    for_column. i.KWidth do.
        first =. (column*N)intdiv KWidth
        last =. ((column+1)*N)intdiv KWidth
        heights =. heights,integer_root ((KHeight*KHeight)*first{values)intdiv {.values
        if. (first<:c_knee Curve)*.(c_knee Curve)<last do.
            knee_column =. column
        end.
    end.
    rows =. 0$a:
    for_row. i.KHeight do.
        characters =. ''
        for_column. i.KWidth do.
            character =. ' '
            if. (KHeight-row)<:column{heights do.
                character =. '#'
            elseif. column=knee_column do.
                character =. ':'
            end.
            characters =. characters,character
        end.
        rows =. rows,<characters
    end.
    (<rows),<knee_column
)
left_pad =: 4 : '((0>.x-#y)#'' ''),y'
reachability_lines =: 3 : 0
    top =. >./Reach-.INF
    columns =. (extract_settings 0),<XiSetting
    result =. ,<line 'reachability';'width';PlotWidth;'max_reach';(root top);'columns';' 'join s_name&.>columns
    for_position. i.N do.
        point =. position{Ordering
        reach =. point{Reach
        if. reach=INF do.
            bar =. PlotWidth#'-'
        else.
            bar =. (integer_root ((PlotWidth*PlotWidth)*reach)intdiv top)#'#'
        end.
        characters =. ''
        for_setting. columns do.
            characters =. characters,label_char point{s_labels >setting
        end.
        result =. result,<(4 left_pad text position+1),' ',(5 left_pad text point{Ids),' ',(7 left_pad root reach),' ',characters,' |',bar
    end.
    result
)
maps_lines =: 3 : 0
    result =. 0$a:
    for_box. Settings do.
        setting =. >box
        result =. result,<line 'map';(s_name setting);'clusters';(s_count setting);'noise';s_noise setting
        result =. result,MapWidth framed cluster_map setting
        legend =. 0$a:
        for_label. i.s_count setting do.
            legend =. legend,<(label_char label),'=',text #label{::s_members setting
        end.
        value =. '-'
        if. #legend do.
            value =. ' 'join legend
        end.
        result =. result,(<'legend ',value),<''
    end.
    result =. result,<'kinds ',s_name Knee
    result =. result,(MapWidth framed kind_map 0),<''
    'rows knee_column' =. kdist_plot 0
    result =. result,<line 'kdist_plot';'k';(MinPts-1);'max';(root {.c_values Curve);'knee_column';knee_column+1
    result =. result,(KWidth framed rows),<''
    result,reachability_lines 0
)
run =: 3 : 0
    point_rows =. read_points 0
    Ids =: 0{"1 point_rows
    Points =: 1 2{"1 point_rows
    N =: #Points
    read_params 0
    neighbor_rows =. 0$a:
    for_point. i.N do.
        values =. i.0
        for_other. (i.N)-.point do.
            values =. values,(point{Points)squared_distance other{Points
        end.
        neighbor_rows =. neighbor_rows,</:~values
    end.
    Curves =: 0$a:
    for_rank. i.2*MinPts do.
        values =. rank {&> neighbor_rows
        Curves =: Curves,<make_curve values
    end.
    Curve =: (MinPts-2){::Curves
    Kdist =: (MinPts-2){&>neighbor_rows
    GridRadii =: /:~~.Eps,(c_eps Curve),MaxEps
    Grids =: 0$a:
    for_radius. GridRadii do.
        'cells members neighbors candidates busiest' =. Points grid_neighborhoods radius
        brute =. Points brute_counts radius
        sizes =. #&>members
        occupancy_sizes =. /:~~.sizes
        occupancy_counts =. i.0
        for_size. occupancy_sizes do.
            occupancy_counts =. occupancy_counts,+/sizes=size
        end.
        pairs =. ((+/#&>neighbors)-N)intdiv 2
        brute_pairs =. ((+/brute)-N)intdiv 2
        consistent =. *./brute=#&>neighbors
        summary =. (<radius),(<cells),(<members),(<neighbors),(<candidates),(<busiest),(<pairs),(<brute_pairs),(<consistent),(<occupancy_sizes),<occupancy_counts
        Grids =: Grids,<summary
    end.
    Settings =: 0$a:
    for_radius. Eps do.
        'labels core' =. (neighborhoods radius)dbscan MinPts
        setting =. make_setting (<'db',text radius),(< 'dbscan'),(<radius),(<labels),<core
        Settings =: Settings,<setting
    end.
    radius =. c_eps Curve
    'labels core' =. (neighborhoods radius)dbscan MinPts
    Knee =: make_setting (<'knee',text radius),(< 'dbscan'),(<radius),(<labels),<core
    Settings =: Settings,<Knee
    neighbors =. neighborhoods MaxEps
    Core =: core_distances (<Points),(<neighbors),<MinPts
    'Ordering Reach Predecessor' =: optics_ordering (<Points),(<neighbors),<Core
    for_radius. ExtractEps do.
        'labels core' =. extract radius
        Settings =: Settings,<make_setting (<'op',text radius),(< 'extract'),(<radius),(<labels),<core
    end.
    Positions =: (Ordering{Reach),INF
    Xi =: compute_xi 0
    labels =. N$_1
    labels =. (2{::Xi)Ordering}labels
    XiSetting =: make_setting (<'xi'),(< 'xi'),(<MaxEps),(<labels),<Core~:INF
    Settings =: Settings,<XiSetting
    'xmin ymin' =. <./Points
    'xmax ymax' =. >./Points
    MapColumns =: (((0{"1 Points)-xmin)*MapWidth)intdiv 1+xmax-xmin
    MapRows =: ((ymax-1{"1 Points)*MapHeight)intdiv 1+ymax-ymin
    try. 1!:5 <'output' catch. end.
    'labels.csv'write_lines labels_lines 0
    'optics_order.csv'write_lines optics_lines 0
    'kdist.txt'write_lines kdist_lines 0
    'clusters.txt'write_lines clusters_lines 0
    'maps.txt'write_lines maps_lines 0
)
run 0
