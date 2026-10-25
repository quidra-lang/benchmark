LF =: 10{a.
Kinds =: ;:'SEG LAZY FEN RFEN SPARSE SQRT PERSIST GRID'
Ops =: ;:'SUM MIN MAX GCD'
Labels =: ;:'sum min max gcd'
Have =: 7#0
Contents =: 7#<i.0
GridHave =: 0
Error =: ''
number =: 3 : ',''0'' 8!:2 y'
join =: 4 : 0
    result =. ''
    for_i. i.#y do.
        if. i do. result =. result,x end.
        result =. result,i{::y
    end.
    result
)
numbers =: 3 : ''' '' join number&.><"0 y'
emit =: 3 : 'Output =: Output,<y'
fail =: 3 : 0
    Error =: y
    throw.
)
interval =: 4 : 'x+i.1+y-x'
lowbit =: 3 : 'y (17 b.) -y'
level =: 3 : '<:# #:y'
statistics =: 3 : '(+/y),(<./y),(>./y),+./|y'
stats_text =: 3 : '''sum='',(number 0{y),'' min='',(number 1{y),'' max='',number 2{y'
merge_stats =: 4 : '((0{x)+0{y),((1{x)<.1{y),(2{x)>.2{y'
check_index =: 3 : 0
    if. (y<0)+.y>:N do. fail 'BAD INDEX ',number y end.
)
check_range =: 3 : 0
    'l r' =. y
    check_index l
    check_index r
    if. l>r do. fail 'BAD RANGE ',numbers y end.
)
check_structure =: 3 : 0
    if. y=7 do. present =. GridHave else. present =. y{Have end.
    if. -.present do. fail 'NOT BUILT ',y{::Kinds end.
)
check_version =: 3 : 0
    if. (y<0)+.y>:#PRoots do. fail 'BAD VERSION ',number y end.
)
check_cell =: 3 : 0
    if. +./(y<0)+.y>:GH,GW do. fail 'BAD CELL ',numbers y end.
)

shape_walk =: 3 : 0
    'v l r' =. y
    Lo =: l v}Lo
    Hi =: r v}Hi
    Valid =: 1 v}Valid
    if. l<r do.
        middle =. <.(l+r)%2
        shape_walk (2*v),l,middle
        shape_walk (1+2*v),(middle+1),r
    end.
)
make_shape =: 3 : 0
    N =: #A
    Lo =: Hi =: Valid =: (4*N)#0
    shape_walk 1 0,(N-1)
    Nodes =: I.Valid
)
change_contents =: 3 : 0
    'kind l r value assignment' =. y
    indices =. l interval r
    data =. kind{::Contents
    if. assignment do.
        data =. value indices}data
        A =: value indices}A
    else.
        data =. (value+indices{data) indices}data
        A =: (value+indices{A) indices}A
    end.
    Contents =: (<data) kind}Contents
)
seg_combine =: 3 : 0
    select. SegOp
    case. 0 do. +/y
    case. 1 do. <./y
    case. 2 do. >./y
    case. 3 do. +./|y
    end.
)
seg_build =: 3 : 0
    'l r' =. (y{Lo),y{Hi
    if. l=r do.
        value =. l{A
        if. SegOp=3 do. value =. |value end.
    else.
        left =. seg_build 2*y
        right =. seg_build 1+2*y
        value =. seg_combine left,right
    end.
    Seg =: value y}Seg
    value
)
seg_query_walk =: 3 : 0
    Visits =: Visits+1
    'l r' =. (y{Lo),y{Hi
    if. (QL<:l)*.r<:QR do. y{Seg return. end.
    middle =. <.(l+r)%2
    if. QR<:middle do. seg_query_walk 2*y return. end.
    if. QL>middle do. seg_query_walk 1+2*y return. end.
    left =. seg_query_walk 2*y
    right =. seg_query_walk 1+2*y
    seg_combine left,right
)
seg_update_walk =: 3 : 0
    Visits =: Visits+1
    'l r' =. (y{Lo),y{Hi
    if. l=r do.
        value =. UpdateValue
        if. SegOp=3 do. value =. |value end.
    else.
        child =. (2*y)+(UpdateIndex><.(l+r)%2)
        seg_update_walk child
        value =. seg_combine ((2*y)+i.2){Seg
    end.
    Seg =: value y}Seg
)
lazy_pull =: 3 : 0
    left =. (2*y){Lazy
    right =. (1+2*y){Lazy
    Lazy =: (left merge_stats right) y}Lazy
)
lazy_build =: 3 : 0
    if. (y{Lo)=y{Hi do.
        Lazy =: (3#(y{Lo){A) y}Lazy
    else.
        lazy_build 2*y
        lazy_build 1+2*y
        lazy_pull y
    end.
)
lazy_apply =: 3 : 0
    'v value assignment' =. y
    'l r' =. (v{Lo),v{Hi
    change =. (value*1+r-l),value,value
    if. assignment do.
        Lazy =: change v}Lazy
        if. l<r do.
            Assigned =: 1 v}Assigned
            Assign =: value v}Assign
            Add =: 0 v}Add
        end.
    else.
        Lazy =: (change+v{Lazy) v}Lazy
        if. l<r do. Add =: (value+v{Add) v}Add end.
    end.
)
lazy_push =: 3 : 0
    if. (-.y{Assigned)*.0=y{Add do. i.0 return. end.
    Pushes =: Pushes+1
    for_child. (2*y)+i.2 do.
        if. y{Assigned do. lazy_apply child,(y{Assign),1 end.
        if. 0~:y{Add do. lazy_apply child,(y{Add),0 end.
    end.
    Assigned =: 0 y}Assigned
    Add =: 0 y}Add
)
lazy_update_walk =: 3 : 0
    Visits =: Visits+1
    'l r' =. (y{Lo),y{Hi
    if. (QL<:l)*.r<:QR do.
        Covered =: Covered+1
        lazy_apply y,UpdateValue,Assigning
        i.0 return.
    end.
    lazy_push y
    middle =. <.(l+r)%2
    if. QL<:middle do. lazy_update_walk 2*y end.
    if. QR>middle do. lazy_update_walk 1+2*y end.
    lazy_pull y
)
lazy_query_walk =: 3 : 0
    Visits =: Visits+1
    'l r' =. (y{Lo),y{Hi
    if. (QL<:l)*.r<:QR do. y{Lazy return. end.
    lazy_push y
    middle =. <.(l+r)%2
    if. QR<:middle do. lazy_query_walk 2*y return. end.
    if. QL>middle do. lazy_query_walk 1+2*y return. end.
    left =. lazy_query_walk 2*y
    right =. lazy_query_walk 1+2*y
    left merge_stats right
)

fen_build =: 3 : 0
    tree =. 0,y
    for_p. 1+i.#y do.
        parent =. p+lowbit p
        if. parent<#tree do. tree =. ((p{tree)+parent{tree) parent}tree end.
    end.
    tree
)
fen_add =: 4 : 0
    tree =. x
    'p value' =. y
    while. p<#tree do.
        tree =. (value+p{tree) p}tree
        Visits =: Visits+1
        p =. p+lowbit p
    end.
    tree
)
fen_prefix =: 4 : 0
    value =. 0
    p =. y
    while. p>0 do.
        value =. value+p{x
        Visits =: Visits+1
        p =. p-lowbit p
    end.
    value
)
fen_lower =: 3 : 0
    step =. 2^level N
    position =. 0
    rest =. y
    while. step>:1 do.
        next =. position+step
        if. next<:N do.
            Visits =: Visits+1
            if. (next{Fen)<rest do.
                rest =. rest-next{Fen
                position =. next
            end.
        end.
        step =. <.step%2
    end.
    if. position=N do. 'none' else. number position end.
)
rfen_prefix =: 3 : 0
    first =. R1 fen_prefix y
    second =. R2 fen_prefix y
    (y*first)-second
)
sparse_build =: 3 : 0
    SparseMin =: SparseMax =: <i.N
    width =. 2
    while. width<:N do.
        indices =. i.1+N-width
        half =. <.width%2
        previous =. _1{::SparseMin
        a =. indices{previous
        b =. (indices+half){previous
        SparseMin =: SparseMin,<a+((b{A)<a{A)*(b-a)
        previous =. _1{::SparseMax
        a =. indices{previous
        b =. (indices+half){previous
        SparseMax =: SparseMax,<a+((b{A)>a{A)*(b-a)
        width =. 2*width
    end.
)
sparse_query =: 3 : 0
    'l r' =. y
    t =. level 1+r-l
    last =. 1+r-2^t
    data =. 4{::Contents
    'a b' =. (l,last){t{::SparseMin
    if. (b{data)<a{data do. a =. b end.
    'z b' =. (l,last){t{::SparseMax
    if. (b{data)>z{data do. z =. b end.
    (a{data),a,(z{data),z,t
)
sqrt_split =: 3 : 0
    'l r' =. y
    'left right' =. <.y%Block
    whole =. i.0
    if. left=right do. cells =. l interval r
    else.
        cells =. (l interval <: (left+1)*Block),((right*Block) interval r)
        whole =. (left+1) interval right-1
    end.
    cells;<whole
)
sqrt_add =: 3 : 0
    'l r value' =. y
    'cells whole' =. sqrt_split l,r
    for_i. cells do.
        t =. <.i%Block
        Raw =: (value+i{Raw) i}Raw
        BlockSum =: (value+t{BlockSum) t}BlockSum
    end.
    for_t. whole do.
        Tag =: (value+t{Tag) t}Tag
        BlockSum =: ((value*Block)+t{BlockSum) t}BlockSum
    end.
    (#whole),#cells
)
sqrt_query =: 3 : 0
    'cells whole' =. sqrt_split y
    value =. +/(cells{Raw)+(<.cells%Block){Tag
    value =. value++/whole{BlockSum
    value,(#whole),#cells
)

pool_build =: 3 : 0
    'l r' =. y
    if. l=r do. row =. _1 _1,l{BuildValues
    else.
        middle =. <.(l+r)%2
        left =. pool_build l,middle
        right =. pool_build (middle+1),r
        row =. left,right,(2{left{Pool)+2{right{Pool
    end.
    index =. #Pool
    Pool =: Pool,row
    index
)
pool_fork =: 3 : 0
    'root l r index value addition' =. y
    'left right old' =. root{Pool
    if. l=r do.
        if. addition do. value =. value+old end.
        row =. _1 _1,value
    else.
        middle =. <.(l+r)%2
        if. index<:middle do. left =. pool_fork left,l,middle,index,value,addition
        else. right =. pool_fork right,(middle+1),r,index,value,addition end.
        row =. left,right,(2{left{Pool)+2{right{Pool
    end.
    created =. #Pool
    Pool =: Pool,row
    created
)
persistent_build =: 3 : 0
    BuildValues =: A
    Pool =: 0 3$0
    PRoots =: ,pool_build 0,N-1
    PPos =: Pool
    Domain =: /:~ ~.A
    BuildValues =: (#Domain)#0
    Pool =: 0 3$0
    VRoots =: ,pool_build 0,(#Domain)-1
    for_value. A do.
        root =. pool_fork (_1{VRoots),0,((#Domain)-1),(Domain i.value),1 1
        VRoots =: VRoots,root
    end.
    PValue =: Pool
)
pool_query =: 3 : 0
    'root l r' =. y
    Visits =: Visits+1
    if. (QL<:l)*.r<:QR do. 2{root{Pool return. end.
    middle =. <.(l+r)%2
    'left right value' =. root{Pool
    if. QR<:middle do. pool_query left,l,middle return. end.
    if. QL>middle do. pool_query right,(middle+1),r return. end.
    a =. pool_query left,l,middle
    b =. pool_query right,(middle+1),r
    a+b
)
persistent_kth =: 3 : 0
    'l r k' =. y
    upper =. (r+1){VRoots
    lower =. l{VRoots
    l =. 0
    r =. (#Domain)-1
    Visits =: 1
    while. l<r do.
        middle =. <.(l+r)%2
        a =. 0{upper{PValue
        b =. 0{lower{PValue
        count =. (2{a{PValue)-2{b{PValue
        if. k<:count do.
            upper =. a [ lower =. b [ r =. middle
        else.
            k =. k-count
            upper =. 1{upper{PValue
            lower =. 1{lower{PValue
            l =. middle+1
        end.
        Visits =: Visits+1
    end.
    l{Domain
)
grid_add =: 3 : 0
    'i j value' =. y
    p =. i+1
    while. p<:GH do.
        q =. j+1
        while. q<:GW do.
            cell =. <p,q
            Grid =: (value+cell{Grid) cell}Grid
            Visits =: Visits+1
            q =. q+lowbit q
        end.
        p =. p+lowbit p
    end.
)
grid_prefix =: 3 : 0
    'p j' =. y
    value =. 0
    while. p>0 do.
        q =. j
        while. q>0 do.
            value =. value+(<p,q){Grid
            Visits =: Visits+1
            q =. q-lowbit q
        end.
        p =. p-lowbit p
    end.
    value
)
mo_change =: 4 : 0
    rank =. y{MoRanks
    Frequency =: (x+rank{Frequency) rank}Frequency
    Moves =: Moves+1
)
mo =: 3 : 0
    block =. <.%:N
    blocks =. <.(0{"1 y)%block
    direction =. (1-2*2|blocks)*1{"1 y
    order =. /:blocks,.direction,.i.#y
    MoRanks =: (~.A)i.A
    Frequency =: (#~.A)#0
    answers =. (#y)#0
    left =. 0
    right =. _1
    Moves =: 0
    for_index. order do.
        'l r' =. index{y
        while. left>l do.
            left =. left-1
            1 mo_change left
        end.
        while. right<r do.
            right =. right+1
            1 mo_change right
        end.
        while. left<l do.
            _1 mo_change left
            left =. left+1
        end.
        while. right>r do.
            _1 mo_change right
            right =. right-1
        end.
        answers =. (+/Frequency>0) index}answers
    end.
    emit 'MO queries=',(number #y),' block=',(number block),' moves=',number Moves
    emit 'ORDER ',numbers 1+order
    for_i. i.#y do. emit 'ANSWER ',(number i+1),' ',(numbers i{y),' distinct=',number i{answers end.
)

build_structure =: 3 : 0
    Have =: 1 y}Have
    Contents =: (<A) y}Contents
    select. y
    case. 0 do.
        Seg =: (4*N)#0
        value =. seg_build 1
        'SEG BUILD ',(SegOp{::Ops),' nodes=',(number #Nodes),' maxnode=',(number >./Nodes),' root=',number value
    case. 1 do.
        Lazy =: ((4*N),3)$0
        Assigned =: Assign =: Add =: (4*N)#0
        lazy_build 1
        'LAZY BUILD nodes=',(number #Nodes),' ',stats_text 1{Lazy
    case. 2 do.
        Fen =: fen_build A
        'FEN BUILD n=',(number N),' total=',number +/A
    case. 3 do.
        differences =. A-0,}:A
        R1 =: fen_build differences
        R2 =: fen_build differences*i.N
        'RFEN BUILD n=',(number N),' total=',number +/A
    case. 4 do.
        sparse_build ''
        'SPARSE BUILD levels=',(number #SparseMin),' entries=',number +/#&>SparseMin
    case. 5 do.
        Raw =: A
        groups =. <.(i.N)%Block
        Tag =: (#~.groups)#0
        BlockSum =: groups +//. A
        'SQRT BUILD block=',(number Block),' blocks=',number #Tag
    case. 6 do.
        persistent_build ''
        'PERSIST BUILD nodes=',(number #PPos),' distinct=',(number #Domain),' valuenodes=',number #PValue
    end.
)
query_description =: 4 : 0
    'l r version' =. y
    QL =: l [ QR =: r
    Visits =: Pushes =: 0
    indices =. ,0
    select. x
    case. 0 do.
        answers =. ,seg_query_walk 1
        indices =. ,SegOp
        text =. (SegOp{::Labels),'=',(number {.answers),' visited=',number Visits
    case. 1 do.
        answers =. lazy_query_walk 1
        indices =. i.3
        text =. (stats_text answers),' visited=',(number Visits),' pushes=',number Pushes
    case. 2 do.
        first =. Fen fen_prefix QR+1
        second =. Fen fen_prefix QL
        answers =. ,first-second
        text =. 'sum=',(number {.answers),' visited=',number Visits
    case. 3 do.
        first =. rfen_prefix QR+1
        second =. rfen_prefix QL
        answers =. ,first-second
        text =. 'sum=',(number {.answers),' visited=',number Visits
    case. 4 do.
        values =. sparse_query QL,QR
        answers =. 0 2{values
        indices =. 1 2
        text =. 'min=',(number 0{values),' minpos=',(number 1{values),' max=',(number 2{values),' maxpos=',(number 3{values),' level=',number 4{values
    case. 5 do.
        values =. sqrt_query QL,QR
        answers =. ,0{values
        text =. 'sum=',(number 0{values),' whole=',(number 1{values),' cells=',number 2{values
    case. 6 do.
        if. version<0 do. version =. <:#PRoots end.
        Pool =: PPos
        answers =. ,pool_query (version{PRoots),0,N-1
        text =. 'sum=',(number {.answers),' visited=',number Visits
    end.
    text;indices;answers;<version
)
check_report =: 3 : 0
    direct =. statistics ((0{y) interval 1{y){A
    emit 'CHECK ',(numbers y),' ',(stats_text direct),' gcd=',number 3{direct
    ok =. 0
    different =. 0
    for_kind. I.Have do.
        'text indices answers version' =. kind query_description y,_1
        if. answers-:indices{direct do.
            verdict =. 'OK'
            ok =. ok+1
        else.
            verdict =. 'DIFF'
            different =. different+1
        end.
        if. kind=6 do. text =. 'version=',(number version),' ',text end.
        emit (kind{::Kinds),' ',verdict,' ',text
    end.
    emit 'RESULT ok=',(number ok),' diff=',number different
)
dump_structure =: 3 : 0
    select. y
    case. 0 do.
        emit 'SEG DUMP ',(SegOp{::Ops),' nodes=',number #Nodes
        for_v. Nodes do. emit 'NODE ',numbers v,(v{Lo),(v{Hi),v{Seg end.
    case. 1 do.
        emit 'LAZY DUMP nodes=',number #Nodes
        for_v. Nodes do.
            assignment =. '-'
            if. v{Assigned do. assignment =. number v{Assign end.
            emit 'NODE ',(numbers v,(v{Lo),v{Hi),' ',(stats_text v{Lazy),' assign=',assignment,' add=',number v{Add
        end.
    case. 2 do.
        emit 'FEN DUMP n=',number N
        emit 'T ',numbers }.Fen
    case. 3 do.
        emit 'RFEN DUMP n=',number N
        emit 'B1 ',numbers }.R1
        emit 'B2 ',numbers }.R2
    case. 4 do.
        emit 'SPARSE DUMP levels=',number #SparseMin
        for_t. i.#SparseMin do.
            emit 'MIN ',(number t),' ',numbers t{::SparseMin
            emit 'MAX ',(number t),' ',numbers t{::SparseMax
        end.
    case. 5 do.
        emit 'SQRT DUMP block=',(number Block),' blocks=',number #Tag
        for_t. i.#Tag do.
            first =. t*Block
            last =. <:(N<.(t+1)*Block)
            emit 'BLOCK ',(numbers t,first,last),' add=',(number t{Tag),' sum=',(number t{BlockSum),' ',numbers (first interval last){Raw
        end.
    case. 7 do.
        emit 'GRID DUMP rows=',(number GH),' cols=',number GW
        for_p. 1+i.GH do. emit 'ROW ',(number p),' ',numbers }.p{Grid end.
    end.
)
execute =: 3 : 0
    Output =: 0$a:
    words =. <;._1 ' ',y
    command =. 0{::words
    select. command
    case. 'LOAD' do.
        removed =. +/Have
        A =: Original =: 0".&>}.words
        Have =: 7#0
        Contents =: 7#<i.0
        make_shape ''
        emit 'LOAD n=',(number N),' removed=',number removed
        Output return.
    case. 'RESET' do.
        A =: Original
        for_kind. I.Have do. build_structure kind end.
        emit 'RESET rebuilt=',number +/Have
        Output return.
    case. 'ARRAY';'CHECK' do.
        range =. 0".&>}.words
        check_range range
        if. command-:'ARRAY' do.
            emit 'ARRAY ',(numbers range),' ',numbers ((0{range) interval 1{range){A
        else. check_report range end.
        Output return.
    case. 'MO' do.
        values =. 0".&>}.words
        ranges =. ((<.(#values)%2),2)$values
        for_range. ranges do. check_range range end.
        mo ranges
        Output return.
    end.
    kind =. Kinds i.<command
    action =. 1{::words
    if. action-:'BUILD' do.
        if. kind=0 do.
            operation =. 2{::words
            index =. Ops i.<operation
            if. index=#Ops do. fail 'BAD OP ',operation end.
            SegOp =: index
        elseif. kind=5 do.
            block =. <.%:N
            if. 3=#words do. block =. 0".2{::words end.
            if. block>N do. fail 'BAD BLOCK ',number block end.
            Block =: block
        elseif. kind=7 do.
            args =. 0".&>2}.words
            'h w' =. 2{.args
            values =. 2}.args
            if. (#values)~:h*w do. fail 'BAD COUNT ',numbers (#values),h*w end.
            GH =: h [ GW =: w
            G =: (h,w)$values
            Grid =: ((h+1),w+1)$0
            GridHave =: 1
            Visits =: 0
            for_i. i.h do.
                for_j. i.w do. grid_add i,j,(<i,j){G end.
            end.
            emit 'GRID BUILD rows=',(number h),' cols=',(number w),' total=',number +/values
            Output return.
        end.
        emit build_structure kind
        Output return.
    end.
    check_structure kind
    if. action-:'DUMP' do.
        dump_structure kind
        Output return.
    end.
    args =. 0".&>2}.words
    prefix =. command,' ',action
    if. #args do. prefix =. prefix,' ',numbers args end.
    Visits =: Pushes =: Covered =: 0
    select. kind
    case. 0 do.
        if. action-:'QUERY' do.
            check_range args
            emit prefix,' ',0{::kind query_description args,_1
        else.
            'UpdateIndex UpdateValue' =: args
            check_index UpdateIndex
            seg_update_walk 1
            change_contents kind,UpdateIndex,UpdateIndex,UpdateValue,1
            emit prefix,' root=',(number 1{Seg),' visited=',number Visits
        end.
    case. 1 do.
        check_range 2{.args
        if. action-:'QUERY' do.
            emit prefix,' ',0{::kind query_description args,_1
        else.
            'QL QR UpdateValue' =: args
            Assigning =: action-:'ASSIGN'
            lazy_update_walk 1
            change_contents kind,args,Assigning
            emit prefix,' visited=',(number Visits),' covered=',(number Covered),' pushes=',number Pushes
        end.
    case. 2 do.
        if. action-:'LOWER' do.
            negative =. I.0>kind{::Contents
            if. #negative do. fail 'NEGATIVE ',number {.negative end.
            index =. fen_lower {.args
            emit prefix,' index=',index,' visited=',number Visits
        elseif. action-:'RANGE' do.
            check_range args
            emit prefix,' ',0{::kind query_description args,_1
        else.
            index =. {.args
            check_index index
            if. action-:'ADD' do.
                value =. 1{args
                Fen =: Fen fen_add (index+1),value
                change_contents kind,index,index,value,0
                emit prefix,' visited=',number Visits
            else.
                value =. Fen fen_prefix index+1
                emit prefix,' sum=',(number value),' visited=',number Visits
            end.
        end.
    case. 3 do.
        check_range 2{.args
        if. action-:'SUM' do.
            emit prefix,' ',0{::kind query_description args,_1
        else.
            'l r value' =. args
            R1 =: R1 fen_add (l+1),value
            R1 =: R1 fen_add (r+2),-value
            R2 =: R2 fen_add (l+1),value*l
            R2 =: R2 fen_add (r+2),-value*(r+1)
            change_contents kind,args,0
            emit prefix,' visited=',number Visits
        end.
    case. 4 do.
        check_range args
        emit prefix,' ',0{::kind query_description args,_1
    case. 5 do.
        check_range 2{.args
        if. action-:'SUM' do.
            emit prefix,' ',0{::kind query_description args,_1
        else.
            counts =. sqrt_add args
            change_contents kind,args,0
            emit prefix,' whole=',(number 0{counts),' cells=',number 1{counts
        end.
    case. 6 do.
        if. action-:'NODES' do.
            emit prefix,' versions=',(number #PRoots),' position=',(number #PPos),' value=',number #PValue
        elseif. action-:'KTH' do.
            'l r k' =. args
            check_range l,r
            if. (k<1)+.k>1+r-l do. fail 'BAD K ',number k end.
            value =. persistent_kth args
            emit prefix,' value=',(number value),' visited=',number Visits
        else.
            version =. {.args
            check_version version
            if. action-:'QUERY' do.
                check_range }.args
                emit prefix,' ',0{::kind query_description (}.args),version
            else.
                'index value' =. }.args
                check_index index
                Pool =: PPos
                before =. #Pool
                root =. pool_fork (version{PRoots),0,(N-1),index,value,0
                PPos =: Pool
                new_version =. #PRoots
                PRoots =: PRoots,root
                emit prefix,' version=',(number new_version),' created=',number (#Pool)-before
            end.
        end.
    case. 7 do.
        check_cell 2{.args
        if. action-:'ADD' do.
            'i j value' =. args
            cell =. <i,j
            G =: (value+cell{G) cell}G
            grid_add args
            emit prefix,' visited=',number Visits
        else.
            check_cell 2}.args
            'i1 j1 i2 j2' =. args
            if. (i1>i2)+.j1>j2 do. fail 'BAD RECT ',numbers args end.
            first =. grid_prefix (i2+1),j2+1
            second =. grid_prefix i1,j2+1
            third =. grid_prefix (i2+1),j1
            fourth =. grid_prefix i1,j1
            value =. first-second
            value =. value-third
            value =. value+fourth
            emit prefix,' sum=',(number value),' visited=',number Visits
        end.
    end.
    Output
)
main =: 3 : 0
    count =. 0".1!:1[3
    A =: Original =: ,0".1!:1[3
    make_shape ''
    commands =. 0".1!:1[3
    for_command. i.commands do.
        line =. 1!:1[3
        try. rows =. execute line
        catcht. rows =. <'ERROR ',Error end.
        for_row. rows do. ((>row),LF) 1!:2[4 end.
    end.
)
main ''
2!:55[0
