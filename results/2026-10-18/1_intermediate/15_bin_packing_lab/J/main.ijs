LF =: 10{a.
Capacity =: 0
Sizes =: i.0
METHODS =: ;:'NEXTFIT FIRSTFIT BESTFIT WORSTFIT ALMOSTWORST HARMONIC KBOUNDED FFD BFD WFD'
LETTERS =: 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
split =: 4 : '<;._1 x,y'
number =: 3 : 0
    ,'0' 8!:2 y
)
join =: 4 : 0
    result =. ''
    for_i. i.#y do.
        if. i do. result =. result,x end.
        result =. result,i{::y
    end.
    result
)
emit =: 3 : 0
    parts =. 0$a:
    for_part. y do.
        value =. >part
        if. 2~:3!:0 value do. value =. number value end.
        parts =. parts,<value
    end.
    ((' ' join parts),LF) 1!:2 4
    i.0
)
fail =: 3 : 'emit (<''ERROR''),y'
tag =: 4 : 'x,''='',number y'
floor_ratio =: 4 : '<.(x:x)%x:y'
ceil_ratio =: 4 : '>. (x:x)%x:y'
item_text =: 4 : '(number y+1),'':'',number y{x'
item_list =: 4 : 0
    if. 0=#y do. '-' return. end.
    parts =. 0$a:
    for_item. y do. parts =. parts,<x item_text item end.
    ' ' join parts
)
bin_line =: 3 : 0
    'label capacity items suffix sizes' =. y
    load =. +/items{sizes
    text =. 'BIN';label;('load=',(number load),'/',number capacity);'items=',sizes item_list items
    if. #suffix do. text =. text,<suffix end.
    emit text
)
pack =: 4 : 0
    'capacity sizes' =. x
    'method parameter' =. y
    bins =. 0$a:
    loads =. classes =. active =. i.0
    current =. parameter$_1
    steps =. 0 6$0
    inspections =. closes =. 0
    order =. i.#sizes
    if. (<method)e.;:'FFD BFD WFD' do. order =. \:sizes end.
    for_item. order do.
        size =. item{sizes
        chosen =. closed =. _1
        class =. inspected =. 0
        select. method
        case. 'NEXTFIT' do.
            if. #bins do.
                inspected =. 1
                if. size<:capacity-{:loads do. chosen =. (#bins)-1 end.
            end.
        case. 'HARMONIC' do.
            class =. parameter<.capacity floor_ratio size
            candidate =. (class-1){current
            if. candidate>:0 do.
                inspected =. 1
                if. size<:capacity-candidate{loads do. chosen =. candidate end.
            end.
        case. 'FIRSTFIT';'FFD';'KBOUNDED' do.
            candidates =. i.#bins
            if. method-:'KBOUNDED' do. candidates =. active end.
            for_b. candidates do.
                inspected =. inspected+1
                if. size<:capacity-b{loads do. chosen =. b
                    break.
                end.
            end.
        case. do.
            inspected =. #bins
            fitting =. I.size<:capacity-loads
            if. #fitting do.
                if. (<method)e.;:'BESTFIT BFD' do.
                    chosen =. ((fitting{loads)i.>./fitting{loads){fitting
                else.
                    fitting =. (/:fitting{loads){fitting
                    rank =. 0
                    if. method-:'ALMOSTWORST' do. rank =. 1<.(#fitting)-1 end.
                    chosen =. rank{fitting
                end.
            end.
        end.
        new =. chosen=_1
        if. new do.
            if. method-:'KBOUNDED' do.
                if. parameter=#active do.
                    closed =. ((active{loads)i.>./active{loads){active
                    active =. active-.closed
                    closes =. closes+1
                end.
            end.
            chosen =. #bins
            bins =. bins,<i.0
            loads =. loads,0
            classes =. classes,class
            if. method-:'KBOUNDED' do. active =. active,chosen end.
            if. method-:'HARMONIC' do. current =. chosen (class-1)}current end.
        end.
        bins =. (<(chosen{::bins),item) chosen}bins
        loads =. (size+chosen{loads) chosen}loads
        inspections =. inspections+inspected
        steps =. steps,1 6$item,chosen,inspected,new,closed,class
    end.
    bins;loads;inspections;classes;closes;steps
)
method_name =: 3 : 0
    'method parameter' =. y
    if. (<method)e.;:'HARMONIC KBOUNDED' do. method,' k=',number parameter
    else. method end.
)
show_pack =: 4 : 0
    'method parameter trace' =. x
    'bins loads inspections classes closes steps' =. y
    name =. method_name method;parameter
    if. trace do. name =. 'TRACE ',name end.
    line =. name;('bins' tag #bins);('inspections' tag inspections);'waste' tag ((#bins)*Capacity)-+/Sizes
    if. method-:'KBOUNDED' do. line =. line,<'closes' tag closes end.
    emit line
    if. trace do.
        for_i. i.#steps do.
            'item bin inspected new closed class' =. i{steps
            line =. 'STEP';(i+1);('item=',Sizes item_text item);('bin' tag bin+1);'inspected' tag inspected
            if. new do. line =. line,<'new' end.
            if. closed>:0 do. line =. line,<'closed' tag closed+1 end.
            if. method-:'HARMONIC' do. line =. line,<'class' tag class end.
            emit line
        end.
    else.
        for_i. i.#bins do.
            suffix =. ''
            if. method-:'HARMONIC' do. suffix =. 'class' tag i{classes end.
            bin_line (i+1);Capacity;(i{::bins);suffix;Sizes
        end.
    end.
    i.0
)
bounds =: 3 : 0
    rows =. 0 5$0
    for_alpha. /:~ ~.0,Sizes#~(2*Sizes)<:Capacity do.
        j1 =. Sizes#~Sizes>Capacity-alpha
        j2 =. Sizes#~((2*Sizes)>Capacity)*.Sizes<:Capacity-alpha
        j3 =. Sizes#~((2*Sizes)<:Capacity)*.Sizes>:alpha
        excess =. (+/j3)-(((#j2)*Capacity)-+/j2)
        value =. (#j1)+(#j2)+(0>.excess) ceil_ratio Capacity
        rows =. rows,1 5$alpha,(#j1),(#j2),(#j3),value
    end.
    ((+/Sizes) ceil_ratio Capacity);(>./4{"1 rows);rows
)
reduce_bins =: 4 : 0
    'method parameter' =. x
    'bins loads inspections classes closes steps' =. y
    before =. #bins
    eliminations =. 0$a:
    while. 1 do.
        success =. 0
        for_source. /:loads do.
            trial =. loads
            moves =. 0 2$0
            items =. source{::bins
            items =. (/:(-items{Sizes),.items){items
            for_item. items do.
                fitting =. (I.(item{Sizes)<:Capacity-trial)-.source
                if. 0=#fitting do. break. end.
                destination =. ((fitting{trial)i.>./fitting{trial){fitting
                trial =. ((item{Sizes)+destination{trial) destination}trial
                moves =. moves,1 2$item,destination
            end.
            if. (#moves)~:#items do. continue. end.
            descriptions =. 0$a:
            for_move. moves do.
                'item destination' =. move
                bins =. (<(destination{::bins),item) destination}bins
                descriptions =. descriptions,<(Sizes item_text item),'->',number destination+1
            end.
            eliminations =. eliminations,<('bin' tag source+1);('load' tag source{loads);'moves=',' ' join descriptions
            keep =. (i.#bins)-.source
            bins =. keep{bins
            loads =. keep{trial
            classes =. keep{classes
            success =. 1
            break.
        end.
        if. -.success do. break. end.
    end.
    emit 'REDUCE';(method_name method;parameter);('before' tag before);('after' tag #bins);'eliminated' tag before-#bins
    for_line. eliminations do. emit (<'ELIMINATE'),>line end.
    for_i. i.#bins do.
        suffix =. ''
        if. method-:'HARMONIC' do. suffix =. 'class' tag i{classes end.
        bin_line (i+1);Capacity;(i{::bins);suffix;Sizes
    end.
    i.0
)
visit =: 3 : 0
    'position bins loads' =. y
    if. -.SearchStatus-:'complete' do. i.0 return. end.
    if. Nodes=SearchLimit do. SearchStatus =: 'limit'
        i.0 return.
    end.
    Nodes =: Nodes+1
    count =. #bins
    free =. (count*Capacity)-+/loads
    extra =. 0>.(position{Remaining)-free
    if. (count+extra ceil_ratio Capacity)>:BestCount do. i.0 return. end.
    if. position=#Order do.
        BestBins =: bins
        BestCount =: count
        emit 'IMPROVE';('bins' tag count);'nodes' tag Nodes
        if. count=Lower do. SearchStatus =: 'bound' end.
        i.0 return.
    end.
    item =. position{Order
    size =. item{Sizes
    seen =. i.0
    for_b. i.count do.
        load =. b{loads
        if. load e.seen do. continue. end.
        seen =. seen,load
        if. size>Capacity-load do. continue. end.
        nextbins =. (<(b{::bins),item) b}bins
        nextloads =. (load+size) b}loads
        visit (position+1);nextbins;nextloads
        if. -.SearchStatus-:'complete' do. i.0 return. end.
    end.
    if. (count+1)<BestCount do.
        visit (position+1);(bins,<,item);loads,size
    end.
    i.0
)
exact =: 3 : 0
    SearchLimit =: y
    'bins loads inspections classes closes steps' =. (Capacity;Sizes) pack 'FFD';0
    BestBins =: bins
    BestCount =: #bins
    'l1 l2 rows' =. bounds ''
    Lower =: l2
    Nodes =: 0
    SearchStatus =: 'bound'
    emit 'EXACT';('ffd' tag BestCount);'L2' tag Lower
    if. BestCount~:Lower do.
        SearchStatus =: 'complete'
        Order =: \:Sizes
        Remaining =: (|.+/\|.Order{Sizes),0
        visit 0;(0$a:);i.0
    end.
    emit 'RESULT';('bins' tag BestCount);('nodes' tag Nodes);'status=',SearchStatus
    for_i. i.#BestBins do. bin_line (i+1);Capacity;(i{::BestBins);'';Sizes end.
    i.0
)
cover =: 3 : 0
    emit 'COVER';('total' tag +/Sizes);'upper' tag (+/Sizes) floor_ratio Capacity
    for_method. ;:'DNF BIGSMALL' do.
        method =. >method
        remaining =. i.#Sizes
        if. method-:'BIGSMALL' do. remaining =. \:Sizes end.
        bins =. 0$a:
        rest =. i.0
        while. #remaining do.
            items =. ,{.remaining
            remaining =. }.remaining
            load =. +/items{Sizes
            while. (load<Capacity)*.0<#remaining do.
                if. method-:'DNF' do. item =. {.remaining
                    remaining =. }.remaining
                else. item =. {:remaining
                    remaining =. }:remaining end.
                items =. items,item
                load =. load+item{Sizes
            end.
            if. load>:Capacity do. bins =. bins,<items
            else. rest =. items end.
        end.
        emit method;('covered' tag #bins);'rest' tag +/rest{Sizes
        for_i. i.#bins do. bin_line (i+1);Capacity;(i{::bins);'';Sizes end.
        if. #rest do. emit 'REST';'items=',Sizes item_list rest end.
    end.
    i.0
)
machines =: 3 : 0
    for_i. i.#y do.
        items =. i{::y
        emit 'MACHINE';(i+1);('load' tag +/items{Sizes);'items=',Sizes item_list items
    end.
    i.0
)
multifit =: 3 : 0
    total =. +/Sizes
    largest =. >./Sizes
    lo =. largest>.total ceil_ratio y
    hi =. largest>.(2*total) ceil_ratio y
    emit 'MULTIFIT';('m' tag y);('lower' tag lo);'upper' tag hi
    while. lo<hi do.
        mid =. (lo+hi) floor_ratio 2
        result =. (mid;Sizes) pack 'FFD';0
        count =. #0{::result
        outcome =. 'fail'
        if. count<:y do. outcome =. 'ok' end.
        emit 'TRY';('cap' tag mid);('bins' tag count);outcome
        if. count<:y do. hi =. mid else. lo =. mid+1 end.
    end.
    'bins loads inspections classes closes steps' =. (hi;Sizes) pack 'FFD';0
    emit 'RESULT';('cap' tag hi);'makespan' tag >./loads
    machines bins,(y-#bins)$<i.0
    bins =. y$<i.0
    loads =. y$0
    for_item. \:Sizes do.
        b =. loads i.<./loads
        bins =. (<(b{::bins),item) b}bins
        loads =. ((item{Sizes)+b{loads) b}loads
    end.
    emit 'LPT';'makespan' tag >./loads
    machines bins
    i.0
)
patterns =: 4 : 0
    if. 1=#x do. 1 1$y floor_ratio {.x return. end.
    result =. (0,#x)$0
    for_count. |.i.1+y floor_ratio {.x do.
        tails =. (}.x) patterns y-count*{.x
        for_tail. tails do. result =. result,(1,#x)$count,tail end.
    end.
    result
)
cutstock =: 3 : 0
    length =. 0".0{::y
    if. length=0 do. fail <'BAD CAPACITY' return. end.
    pieces =. 0 2$0
    for_i. i.<:#y do.
        'size demand' =. 0".>':' split (i+1){::y
        if. (size=0)+.(size>length)+.demand=0 do. fail 'BAD PIECE';i+1 return. end.
        if. size e.0{"1 pieces do. fail 'DUPLICATE PIECE';i+1 return. end.
        pieces =. pieces,1 2$size,demand
    end.
    pieces =. (\:0{"1 pieces){pieces
    lengths =. 0{"1 pieces
    demands =. 1{"1 pieces
    table =. lengths patterns length
    trims =. length-table +/ . * lengths
    emit 'CUTSTOCK';('L' tag length);('pieces' tag #pieces);'patterns' tag #table
    for_i. i.#table do.
        row =. i{table
        parts =. 0$a:
        for_j. I.row>0 do. parts =. parts,<(number j{row),'x',number j{lengths end.
        emit 'PATTERN';(i+1);('+' join parts);'rest' tag i{trims
    end.
    remaining =. demands
    used =. (#table)$0
    while. +/remaining do.
        useful =. +/"1 table<."1 remaining
        p =. useful i.>./useful
        used =. (1+p{used) p}used
        remaining =. 0>.remaining-p{table
    end.
    cut =. used +/ . * table
    total =. +/demands*lengths
    bars =. +/used
    for_i. I.used>0 do. emit 'USE';(i+1);'bars' tag i{used end.
    for_i. i.#pieces do. emit 'PIECE';(i{lengths);('demand' tag i{demands);'cut' tag i{cut end.
    emit 'TOTAL';('bars' tag bars);('trim' tag +/used*trims);('surplus' tag (+/cut)-+/demands);'waste' tag (bars*length)-total
    result =. (length;demands#lengths) pack 'FIRSTFIT';0
    count =. #0{::result
    emit 'FFD';('bars' tag count);'waste' tag (count*length)-total
    emit 'LOWER';'bars' tag total ceil_ratio length
    i.0
)
draw =: 4 : 0
    'width height' =. x
    cells =. (width*height)$'.'
    for_row. y do.
        'id px py w h extra' =. row
        indices =. ,((py+i.h)*width)+/px+i.w
        cells =. (id{LETTERS) indices}cells
    end.
    for_row. |.(height,width)$cells do. emit <row end.
    i.0
)
place_line =: 3 : 0
    'id px py w h rotated' =. y
    line =. 'PLACE';(,id{LETTERS);('x' tag px);('y' tag py);('w' tag w);'h' tag h
    if. rotated do. line =. line,<'rotated' end.
    emit line
)
shelf =: 3 : 0
    width =. 0".0{::y
    if. width=0 do. fail <'BAD CAPACITY' return. end.
    rectangles =. 0 2$0
    for_i. i.<:#y do.
        'w h' =. 0".>'x' split (i+1){::y
        if. (w=0)+.(h=0)+.w>width do. fail 'BAD RECT';i+1 return. end.
        rectangles =. rectangles,1 2$w,h
    end.
    area =. +/*/"1 rectangles
    order =. /:(-1{"1 rectangles),.(-0{"1 rectangles),.i.#rectangles
    emit 'SHELF';('W' tag width);('rects' tag #rectangles);'area' tag area
    for_method. ;:'NFDH FFDH BFDH' do.
        method =. >method
        shelves =. 0 3$0
        positions =. 0 6$0
        height =. 0
        for_id. order do.
            'w h' =. id{rectangles
            fitting =. I.w<:width-2{"1 shelves
            chosen =. _1
            if. #fitting do.
                select. method
                case. 'NFDH' do.
                    if. ((#shelves)-1)e.fitting do. chosen =. (#shelves)-1 end.
                case. 'FFDH' do. chosen =. {.fitting
                case. 'BFDH' do.
                    loads =. fitting{2{"1 shelves
                    chosen =. (loads i.>./loads){fitting
                end.
            end.
            if. chosen=_1 do.
                chosen =. #shelves
                shelves =. shelves,1 3$height,h,0
                height =. height+h
            end.
            'py sh px' =. chosen{shelves
            positions =. positions,1 6$id,px,py,w,h,chosen
            shelves =. (py,sh,px+w) chosen}shelves
        end.
        emit method;('height' tag height);('shelves' tag #shelves);'util' tag (100*area) floor_ratio width*height
        for_level. i.#shelves do.
            'py h used' =. level{shelves
            parts =. 0$a:
            for_row. positions#~level=5{"1 positions do.
                parts =. parts,<((0{row){LETTERS),'@',number 1{row
            end.
            emit 'LEVEL';(level+1);('y' tag py);('h' tag h);('used' tag used);'items=',' ' join parts
        end.
        (width,height) draw positions
    end.
    columns =. width$0
    positions =. 0 6$0
    for_id. order do.
        'w h' =. id{rectangles
        heights =. i.0
        for_px. i.1+width-w do. heights =. heights,>./(px+i.w){columns end.
        px =. heights i.<./heights
        py =. px{heights
        columns =. (py+h) (px+i.w)}columns
        positions =. positions,1 6$id,px,py,w,h,0
    end.
    height =. >./columns
    emit 'SKYLINE';('height' tag height);'util' tag (100*area) floor_ratio width*height
    for_row. positions do. place_line row end.
    (width,height) draw positions
    i.0
)
fits =: 4 : 0
    'w h rotate' =. x
    'fw fh' =. y
    ((w<:fw)*.h<:fh)+.rotate*.(h<:fw)*.w<:fh
)
guillotine =: 3 : 0
    'width height' =. 0".>2{.y
    mode =. 2{::y
    rule =. 3{::y
    rotate =. mode-:'ROTATE'
    if. (width=0)+.height=0 do. fail <'BAD CAPACITY' return. end.
    rectangles =. 0 2$0
    for_i. i.(#y)-4 do.
        'w h' =. 0".>'x' split (i+4){::y
        if. (w=0)+.(h=0)+.-.(w,h,rotate) fits width,height do. fail 'BAD RECT';i+1 return. end.
        rectangles =. rectangles,1 2$w,h
    end.
    areas =. */"1 rectangles
    free_lists =. placements =. 0$a:
    rotated_count =. 0
    for_id. \:areas do.
        'w h' =. id{rectangles
        sheet =. selected =. _1
        best_area =. _
        for_s. i.#free_lists do.
            free =. s{::free_lists
            for_f. i.#free do.
                'px py fw fh' =. f{free
                if. -. (w,h,rotate) fits fw,fh do. continue. end.
                if. (fw*fh)<best_area do.
                    sheet =. s
                    selected =. f
                    best_area =. fw*fh
                end.
                if. rule-:'FIRST' do. break. end.
            end.
            if. (rule-:'FIRST')*.sheet>:0 do. break. end.
        end.
        if. sheet=_1 do.
            sheet =. #free_lists
            selected =. 0
            free_lists =. free_lists,<1 4$0,0,width,height
            placements =. placements,<0 6$0
        end.
        free =. sheet{::free_lists
        'px py fw fh' =. selected{free
        rotated =. -. (w<:fw)*.h<:fh
        pw =. w
        ph =. h
        if. rotated do. pw =. h
            ph =. w end.
        rotated_count =. rotated_count+rotated
        rows =. (sheet{::placements),1 6$id,px,py,pw,ph,rotated
        placements =. (<rows) sheet}placements
        free =. ((i.#free)-.selected){free
        rw =. fw-pw
        rh =. fh-ph
        if. rw<:rh do.
            top =. px,(py+ph),fw,rh
            right =. (px+pw),py,rw,ph
        else.
            top =. px,(py+ph),pw,rh
            right =. (px+pw),py,rw,fh
        end.
        if. */2}.top do. free =. free,top end.
        if. */2}.right do. free =. free,right end.
        free_lists =. (<free) sheet}free_lists
    end.
    util =. (100*+/areas) floor_ratio (#free_lists)*width*height
    emit 'GUILLOTINE';('W' tag width);('H' tag height);('mode=',mode);('rule=',rule);('rects' tag #rectangles);('sheets' tag #free_lists);('rotated' tag rotated_count);'util' tag util
    for_s. i.#free_lists do.
        rows =. s{::placements
        emit 'SHEET';(s+1);('placed' tag #rows);'area' tag +/(3{"1 rows)*4{"1 rows
        for_row. rows do. place_line row end.
        free =. s{::free_lists
        if. 0=#free do. emit 'FREE';'none'
        else.
            parts =. 0$a:
            for_rect. free do.
                'px py fw fh' =. rect
                parts =. parts,<(number px),',',(number py),',',(number fw),'x',number fh
            end.
            emit (<'FREE'),parts
        end.
        (width,height) draw rows
    end.
    i.0
)
execute =: 3 : 0
    fields =. ' ' split y
    command =. 0{::fields
    args =. }.fields
    select. command
    case. 'ITEMS' do.
        values =. 0".>args
        capacity =. {.values
        sizes =. }.values
        if. capacity=0 do. fail <'BAD CAPACITY' return. end.
        invalid =. I.(sizes=0)+.sizes>capacity
        if. #invalid do. fail 'BAD ITEM';1+{.invalid return. end.
        Capacity =: capacity
        Sizes =: sizes
        emit 'ITEMS';('count' tag #Sizes);('capacity' tag Capacity);'total' tag +/Sizes
        i.0 return.
    case. 'RANDOM' do.
        'count capacity seed' =. 0".>args
        if. (count=0)+.count>40 do. fail <'BAD COUNT' return. end.
        if. capacity=0 do. fail <'BAD CAPACITY' return. end.
        if. (seed=0)+.seed>:2147483647 do. fail <'BAD SEED' return. end.
        sizes =. i.0
        for_i. i.count do.
            seed =. 2147483647|48271x*seed
            sizes =. sizes,1+capacity|seed
        end.
        Capacity =: capacity
        Sizes =: sizes
        emit 'RANDOM';('count' tag count);('capacity' tag capacity);'total' tag +/sizes
        emit (<'SIZES'),<"0 sizes
        i.0 return.
    case. 'CUTSTOCK' do. cutstock args return.
    case. 'SHELF' do. shelf args return.
    case. 'GUILLOTINE' do. guillotine args return.
    end.
    if. Capacity=0 do. fail <'NO ITEMS' return. end.
    if. (<command)e.METHODS,;:'TRACE REDUCE' do.
        method =. command
        rest =. args
        if. (<command)e.;:'TRACE REDUCE' do. method =. 0{::args
            rest =. }.args end.
        parameter =. 0
        if. #rest do. parameter =. 0".0{::rest end.
        if. ((<method)e.;:'HARMONIC KBOUNDED')*.parameter=0 do. fail <'BAD PARAMETER' return. end.
        result =. (Capacity;Sizes) pack method;parameter
        if. command-:'REDUCE' do. (method;parameter) reduce_bins result
        else. (method;parameter;command-:'TRACE') show_pack result end.
        i.0 return.
    end.
    select. command
    case. 'BOUNDS' do.
        'l1 l2 rows' =. bounds ''
        emit 'BOUNDS';('total' tag +/Sizes);('L1' tag l1);'L2' tag l2
        for_row. rows do.
            'alpha j1 j2 j3 bound' =. row
            emit 'ALPHA';alpha;('j1' tag j1);('j2' tag j2);('j3' tag j3);'bound' tag bound
        end.
    case. 'COMPARE' do.
        parameter =. 0".0{::args
        if. parameter=0 do. fail <'BAD PARAMETER' return. end.
        'l1 l2 rows' =. bounds ''
        emit 'COMPARE';('k' tag parameter);('L1' tag l1);'L2' tag l2
        names =. /:~METHODS
        results =. 0$a:
        counts =. i.0
        for_method. names do.
            result =. (Capacity;Sizes) pack (>method);parameter
            results =. results,<result
            counts =. counts,#0{::result
        end.
        for_i. /:counts do.
            'bins loads inspections classes closes steps' =. i{::results
            emit (i{::names);('bins' tag #bins);('gap' tag (#bins)-l2);('waste' tag ((#bins)*Capacity)-+/Sizes);'inspections' tag inspections
        end.
    case. 'EXACT' do.
        limit =. 0".0{::args
        if. limit=0 do. fail <'BAD PARAMETER' return. end.
        if. 20<#Sizes do. fail <'TOO MANY ITEMS' return. end.
        exact limit
    case. 'CHECK' do.
        assignment =. 0".>args
        if. ((#assignment)~:#Sizes)+.0 e.assignment do. fail <'BAD ASSIGNMENT' return. end.
        labels =. /:~ ~.assignment
        bins =. 0$a:
        loads =. i.0
        for_label. labels do.
            items =. I.assignment=label
            bins =. bins,<items
            loads =. loads,+/items{Sizes
        end.
        over =. +/loads>Capacity
        'l1 l2 rows' =. bounds ''
        status =. 'valid'
        if. over do. status =. 'invalid' end.
        emit 'CHECK';('bins' tag #labels);('over' tag over);('L2' tag l2);'status=',status
        for_i. i.#bins do.
            suffix =. ''
            if. (i{loads)>Capacity do. suffix =. 'OVER' end.
            bin_line (i{labels);Capacity;(i{::bins);suffix;Sizes
        end.
    case. 'COVER' do. cover ''
    case. 'MULTIFIT' do.
        count =. 0".0{::args
        if. count=0 do. fail <'BAD PARAMETER' return. end.
        multifit count
    end.
    i.0
)
main =: 3 : 0
    lines =. <;._2 (1!:1 3),LF
    for_line. (0".0{::lines){.}.lines do. execute >line end.
    i.0
)
main ''
