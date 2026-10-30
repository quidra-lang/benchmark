load 'bitstream.ijs'
load 'reed_solomon.ijs'
load 'matrix.ijs'
load 'masking.ijs'
load 'render.ijs'

Levels =: ;:'L M Q H'
Modes =: ;:'NUMERIC ALPHANUMERIC BYTE'
Indicators =: 1 2 4
ErrorKinds =: ;:'level mode version mask text charset capacity'
intdiv =: 4 : '<.(x:x)%x:y'
integer =: 3 : 0
    text =. ":y
    '-'(I.text='_')}text
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
numbers =: 3 : ''' ''join integer&.>y'
read_lines =: 3 : '<;._2 (1!:1 <y)'
split_words =: 3 : '<;._1 '' '',y'
save =: 4 : 0
    content =. ''
    if. #y do.
        content =. (LF join y),LF
    end.
    content 1!:2 <'output/',x
)
count_width =: 4 : 0
    widths =. 10 9 8
    if. y=10 do.
        widths =. 12 11 16
    end.
    (Modes i.<x){widths
)
data_width =: 4 : 0
    select. x
    case. 'NUMERIC' do. (10*y intdiv 3)+(3|y){0 4 7
    case. 'ALPHANUMERIC' do. (11*y intdiv 2)+6*2|y
    case. 'BYTE' do. 8*y
    end.
)
encodable =: 4 : 0
    select. x
    case. 'NUMERIC' do. *./y e.'0123456789'
    case. 'ALPHANUMERIC' do. *./y e.Alphanumeric
    case. 'BYTE' do. *./(codes>:32)*.126>:codes=.a.i.y
    end.
)
segment_width =: 4 : 0
    'text version' =. y
    4+(x count_width version)+x data_width #text
)
groups =: 4 : 0
    step =. (Modes i.<x){3 2 1
    result =. 0$a:
    start =. 0
    while. start<#y do.
        characters =. (step<.(#y)-start){.start}.y
        if. x-:'NUMERIC' do.
            value =. 10#.('0123456789'i.characters)
            width =. (#characters){0 4 7 10
        elseif. x-:'ALPHANUMERIC' do.
            values =. Alphanumeric i.characters
            value =. {.values
            width =. 6
            if. 2=#values do.
                value =. (45*{.values)+{:values
                width =. 11
            end.
        else.
            value =. a.i.{.characters
            width =. 8
        end.
        result =. result,<value;width;characters
        start =. start+step
    end.
    result
)
mixed_segments =: 4 : 0
    version =. x
    text =. y
    n =. #text
    invalid =. (0,n+1)$0
    for_mode. Modes do.
        invalid =. invalid,0,+/\ -. (>mode)&encodable"0 text
    end.
    costs =. (n+1)$0
    starts =. (n+1)$0
    choices =. (n+1)$0
    for_finish. 1+i.n do.
        best =. _1
        for_start. i.finish do.
            for_mu. i.3 do.
                row =. mu{invalid
                if. (finish{row)~:start{row do.
                    continue.
                end.
                mode =. mu{::Modes
                cost =. (start{costs)+4+(mode count_width version)+mode data_width finish-start
                if. (best=_1)+.cost<best do.
                    best =. cost
                    starts =. start finish}starts
                    choices =. mu finish}choices
                end.
            end.
        end.
        costs =. best finish}costs
    end.
    segments =. 0$a:
    finish =. n
    while. finish do.
        start =. finish{starts
        mode =. (finish{choices){::Modes
        part =. (finish-start){.start}.text
        segments =. (<mode;part),segments
        finish =. start
    end.
    (<segments),<{:costs
)
split_segments =: 4 : 0
    if. x-:'MIXED' do.
        y mixed_segments ReqText return.
    end.
    segments =. ,<x;ReqText
    (<segments),<x segment_width ReqText;y
)
assemble_bits =: 4 : 0
    bits =. i.0
    lines =. 0$a:
    for_segment. y do.
        'mode text' =. >segment
        indicator =. (Modes i.<mode){Indicators
        width =. mode count_width x
        bits =. bits,(4 write_bits indicator),width write_bits #text
        line =. 'segment ',mode,' indicator ',(4 binary_text indicator),' count ',(integer #text),' ',width binary_text #text
        lines =. lines,<line
        for_group. mode groups text do.
            'value group_width characters' =. >group
            bits =. bits,group_width write_bits value
            lines =. lines,<'group ',(integer value),' ',(group_width binary_text value),' "',characters,'"'
        end.
    end.
    (<bits),<lines
)
pad_bits =: 4 : 0
    terminator =. 4<.x-#y
    bits =. y,terminator$0
    zero_fill =. 8|-#bits
    bits =. bits,zero_fill$0
    pad_count =. (x-#bits)intdiv 8
    bits =. bits,from_codewords pad_count$236 17
    (<bits),<terminator,zero_fill,pad_count
)
make_layout =: 3 : 0
    'degree first_count first_size second_count second_size' =. y
    lengths =. (first_count$first_size),second_count$second_size
    placement =. 0 2$0
    for_position. i.>./lengths do.
        for_block. i.#lengths do.
            if. position<block{lengths do.
                placement =. placement,block,position
            end.
        end.
    end.
    for_offset. i.degree do.
        for_block. i.#lengths do.
            placement =. placement,block,(block{lengths)+offset
        end.
    end.
    data =. +/lengths
    total =. data+degree*#lengths
    (<degree),(<lengths),(<placement),(<data),(<total),<8*data
)
layout =: 4 : '((4*x-1)+Levels i.<y){::Tables'
read_inputs =: 3 : 0
    Requests =: 0$a:
    for_line. read_lines 'input/requests.txt' do.
        line =. >line
        colon =. line i.':'
        Requests =: Requests,<(split_words colon{.line),< (colon+1)}.line
    end.
    params =. read_lines 'input/params.txt'
    QuietZone =: ".1{::split_words 0{::params
    Scale =: ".1{::split_words 1{::params
    Tables =: 0$a:
    Alignments =: 10$<i.0
    for_line. read_lines 'input/tables.txt' do.
        fields =. split_words >line
        version =. ".1{::fields
        if. 'block'-:0{::fields do.
            values =. ".' 'join 3}.fields
            Tables =: Tables,<make_layout values
        else.
            values =. i.0
            if. 2<#fields do.
                values =. ".' 'join 2}.fields
            end.
            Alignments =: (<values)(version-1)}Alignments
        end.
    end.
    Geometries =: 0$a:
    for_version. 1+i.10 do.
        Geometries =: Geometries,<version function_matrix (version-1){::Alignments
    end.
    Damage =: 0$a:
    for_line. read_lines 'input/damage.txt' do.
        Damage =: Damage,<split_words >line
    end.
    Scans =: 0$a:
    lines =. read_lines 'input/scans.txt'
    index =. 0
    while. index<#lines do.
        name =. 1{::split_words index{::lines
        n =. # (index+1){::lines
        symbol =. ;('#'&=&.>)(n{.(index+1)}.lines)
        Scans =: Scans,<( <name),(<n),<symbol
        index =. index+1+n
    end.
)
prepare_request =: 3 : 0
    'ReqId level mode version mask ReqText' =: y
    levels =. Levels
    for_candidate. Levels do.
        levels =. levels,< (>candidate),'+'
    end.
    if. -.(<level)e.levels do.
        'level ',level return.
    end.
    if. -.(<mode)e.Modes,;:'AUTO MIXED' do.
        'mode ',mode return.
    end.
    versions =. (<'AUTO'),integer&.>1+i.10
    if. -.(<version)e.versions do.
        'version ',version return.
    end.
    if. -.(<mask)e.(<'AUTO'),<"0 '01234567' do.
        'mask ',mask return.
    end.
    if. 0=#ReqText do.
        'text' return.
    end.
    if. (<mode)e.2{.Modes do.
        for_i. i.#ReqText do.
            if. -.mode encodable i{ReqText do.
                'charset position ',integer i return.
            end.
        end.
    end.
    ReqMode =: mode
    if. mode-:'AUTO' do.
        for_candidate. Modes do.
            if. (>candidate)encodable ReqText do.
                ReqMode =: >candidate
                break.
            end.
        end.
    end.
    ReqSplits =: ( <ReqMode split_segments 1),<ReqMode split_segments 10
    base =. ,{.level
    candidates =. 1+i.10
    if. -.version-:'AUTO' do.
        candidates =. ,".version
    end.
    ReqVersion =: 0
    for_v. candidates do.
        split =. (v=10){::ReqSplits
        bits =. 1{::split
        capacity =. 5{::v layout base
        if. bits<:capacity do.
            ReqVersion =: v
            break.
        end.
    end.
    if. ReqVersion=0 do.
        'capacity bits ',(integer bits),' capacity ',integer capacity return.
    end.
    'ReqSegments ReqBitCount' =: (ReqVersion=10){::ReqSplits
    ReqLevel =: base
    if. '+'={:level do.
        for_candidate. (Levels i.<base)}.Levels do.
            if. ReqBitCount<:5{::ReqVersion layout >candidate do.
                ReqLevel =: >candidate
            end.
        end.
    end.
    ReqBoosted =: -.ReqLevel-:base
    ReqMaskToken =: mask
    ''
)
encode_request =: 3 : 0
    Geometry =: (ReqVersion-1){::Geometries
    'SymbolSize BaseSymbol Areas Order' =: Geometry
    BlockLayout =: ReqVersion layout ReqLevel
    'Degree Lengths Placement DataCount Total Capacity' =: BlockLayout
    'RawBits BitTrace' =: ReqVersion assemble_bits ReqSegments
    'PaddedBits Padding' =: Capacity pad_bits RawBits
    data =. to_codewords PaddedBits
    Blocks =: 0$a:
    start =. 0
    for_length. Lengths do.
        words =. length{.start}.data
        Blocks =: Blocks,<words,Degree parity words
        start =. start+length
    end.
    Codewords =: i.0
    for_pair. Placement do.
        'block position' =. pair
        Codewords =: Codewords,position{block{::Blocks
    end.
    bits =. from_codewords Codewords
    unmasked =. bits ((#bits){.Order)}BaseSymbol
    candidates =. 0$a:
    Penalties =: 0 4$0
    for_mask. i.8 do.
        symbol =. (Geometry;mask)apply_mask unmasked
        information =. ReqLevel format_information mask
        for_positions. format_positions SymbolSize do.
            symbol =. ((>positions);information)write_value symbol
        end.
        candidates =. candidates,<symbol
        Penalties =: Penalties,SymbolSize penalties symbol
    end.
    if. ReqMaskToken-:'AUTO' do.
        scores =. +/"1 Penalties
        ChosenMask =: scores i.<./scores
    else.
        ChosenMask =: ".ReqMaskToken
    end.
    Symbol =: ChosenMask{::candidates
    DarkCount =: +/Symbol
)

rotate =: 4 : ',|."1 |:(x,x)$y'
transpose =: 4 : ',|:(x,x)$y'
finder_rotation =: 4 : 0
    n =. x
    corners =. 4 2$(n-7),(n-7),(n-7),0,0,0,0,n-7
    scores =. i.0
    for_corner. corners do.
        'left top' =. corner
        score =. 0
        for_yy. i.7 do.
            for_xx. i.7 do.
                expected =. 2~:>./|(xx-3),yy-3
                position =. (left+xx)+n*top+yy
                score =. score+expected=position{y
            end.
        end.
        scores =. scores,score
    end.
    scores i.<./scores
)
hamming =: 4 : '+/32 write_bits x xor y'
nearest_format =: 3 : 0
    best =. 16
    result =. 0 0
    for_level. i.4 do.
        for_mask. i.8 do.
            value =. (level{::Levels)format_information mask
            distance =. value hamming y
            if. distance<best do.
                best =. distance
                result =. level,mask
            end.
        end.
    end.
    best,result
)
nearest_version =: 3 : 0
    best =. 19
    result =. 7
    for_version. 7+i.34 do.
        distance =. (version_information version)hamming y
        if. distance<best do.
            best =. distance
            result =. version
        end.
    end.
    best,result
)
read_segment =: 4 : 0
    'mode count' =. x
    text =. ''
    while. count do.
        if. mode-:'NUMERIC' do.
            group_size =. 3<.count
            width =. group_size{0 4 7 10
            value =. width read_bits y
            if. value>:10^group_size do.
                (<0),<'' return.
            end.
            text =. text,(-group_size){.(group_size$'0'),integer value
        elseif. mode-:'ALPHANUMERIC' do.
            group_size =. 2<.count
            width =. 6
            limit =. 45
            if. group_size=2 do.
                width =. 11
                limit =. 2025
            end.
            value =. width read_bits y
            if. value>:limit do.
                (<0),<'' return.
            end.
            if. group_size=2 do.
                text =. text,Alphanumeric{~value intdiv 45
            end.
            text =. text,Alphanumeric{~45|value
        else.
            group_size =. 1
            value =. 8 read_bits y
            if. (value<32)+.value>126 do.
                (<0),<'' return.
            end.
            text =. text,value{a.
        end.
        count =. count-group_size
    end.
    (<1),<text
)
parse_data =: 4 : 0
    version =. x
    bits =. y
    ReadPosition =: 0
    end =. 0
    text =. ''
    lines =. 0$a:
    while. 4<:(#bits)-ReadPosition do.
        indicator =. 4 read_bits bits
        if. indicator=0 do.
            break.
        end.
        mu =. Indicators i.indicator
        if. mu=3 do.
            lines =. lines,<'parse failed indicator ',4 binary_text indicator
            (<0),(<''),<lines return.
        end.
        mode =. mu{::Modes
        width =. mode count_width version
        if. width>(#bits)-ReadPosition do.
            lines =. lines,<'parse failed length ',mode
            (<0),(<''),<lines return.
        end.
        count =. width read_bits bits
        if. (mode data_width count)>(#bits)-ReadPosition do.
            lines =. lines,<'parse failed length ',mode
            (<0),(<''),<lines return.
        end.
        'success segment' =. (mode;count)read_segment bits
        if. -.success do.
            lines =. lines,<'parse failed value ',mode
            (<0),(<''),<lines return.
        end.
        text =. text,segment
        lines =. lines,<'segment ',mode,' ',integer count
        end =. ReadPosition
    end.
    'expected padding' =. (#bits)pad_bits end{.bits
    label =. 'bad'
    if. expected-:bits do.
        label =. 'ok'
    end.
    lines =. lines,(<'padding ',label),<'text "',text,'"'
    (<1),(<text),<lines
)
attempt =: 4 : 0
    n =. x
    symbol =. y
    version =. (n-17)intdiv 4
    lines =. 0$a:
    stats =. 4$0
    positions =. format_positions n
    first =. (0{::positions)read_value symbol
    second =. (1{::positions)read_value symbol
    'd1 l1 m1' =. nearest_format first
    'd2 l2 m2' =. nearest_format second
    prefix =. 'format ',(15 binary_text first),' ',(15 binary_text second),' distance ',(integer d1),' ',integer d2
    if. 3<d1<.d2 do.
        lines =. lines,<prefix,' unreadable'
        (<0),(<''),(<lines),<stats return.
    end.
    level =. l1{::Levels
    mask =. m1
    if. d2<d1 do.
        level =. l2{::Levels
        mask =. m2
    end.
    lines =. lines,<prefix,' level ',level,' mask ',integer mask
    if. version>:7 do.
        positions =. version_positions n
        first =. (0{::positions)read_value symbol
        second =. (1{::positions)read_value symbol
        'd1 v1' =. nearest_version first
        'd2 v2' =. nearest_version second
        prefix =. 'version ',(18 binary_text first),' ',(18 binary_text second),' distance ',(integer d1),' ',integer d2
        if. 3<d1<.d2 do.
            lines =. lines,<prefix,' unreadable'
            (<0),(<''),(<lines),<stats return.
        end.
        decoded =. v1
        if. d2<d1 do.
            decoded =. v2
        end.
        lines =. lines,<prefix,' decoded ',integer decoded
        if. decoded~:version do.
            (<0),(<''),(<lines),<stats return.
        end.
    end.
    geometry =. (version-1){::Geometries
    order =. 3{::geometry
    'degree lengths placement data_count total capacity' =. version layout level
    unmasked =. (geometry;mask)apply_mask symbol
    words =. to_codewords ((8*total){.order){unmasked
    blocks =. 0$a:
    for_length. lengths do.
        blocks =. blocks,<(length+degree)$0
    end.
    for_i. i.#placement do.
        'block position' =. i{placement
        received =. block{::blocks
        received =. (i{words)position}received
        blocks =. (<received)block}blocks
    end.
    data =. i.0
    failed =. 0
    for_block. i.#blocks do.
        'syndrome corrected positions success' =. degree correct block{::blocks
        prefix =. 'block ',(integer block),' syndromes ',hexadecimal syndrome
        if. -.success do.
            status =. 2
            lines =. lines,<prefix,' failed'
            failed =. 1
        elseif. #positions do.
            status =. 1
            lines =. lines,<prefix,' corrected ',numbers positions
        else.
            status =. 0
            lines =. lines,<prefix,' ok'
        end.
        stats =. ((status{stats)+1)status}stats
        stats =. ((3{stats)+#positions)3}stats
        data =. data,(block{lengths){.corrected
    end.
    if. failed do.
        (<0),(<''),(<lines),<stats return.
    end.
    'success text parsed' =. version parse_data from_codewords data
    (<success),(<text),(<lines,parsed),<stats
)
decode =: 4 : 0
    rotations =. x finder_rotation y
    oriented =. y
    for_i. i.rotations do.
        oriented =. x rotate oriented
    end.
    result =. x attempt oriented
    mirrored =. 'no'
    if. -.0{::result do.
        other =. x attempt x transpose oriented
        if. 0{::other do.
            result =. other
            mirrored =. 'yes'
        end.
    end.
    header =. 'orientation rotations ',(integer rotations),' mirrored ',mirrored
    result =. (<(<header),2{::result)2}result
    result
)
read_image =: 3 : 0
    lines =. read_lines y
    'width height' =. ".1{::lines
    pixels =. ;('1'&=&.>)height{.2}.lines
    dark =. I.pixels
    left =. <./width|dark
    right =. >./width|dark
    top =. <./dark intdiv width
    run =. 0
    while. (left+run)<width do.
        if. -.((left+run)+width*top){pixels do.
            break.
        end.
        run =. run+1
    end.
    unit =. run intdiv 7
    n =. (1+right-left)intdiv unit
    symbol =. i.0
    for_yy. i.n do.
        for_xx. i.n do.
            position =. (left+unit*xx)+width*top+unit*yy
            symbol =. symbol,position{pixels
        end.
    end.
    well =. 1
    for_yy. i.height do.
        for_xx. i.width do.
            expected =. 0
            if. (xx>:left)*.(xx<left+unit*n)*.(yy>:top)*.yy<top+unit*n do.
                position =. ((xx-left)intdiv unit)+n*(yy-top)intdiv unit
                expected =. position{symbol
            end.
            well =. well*.expected=(xx+width*yy){pixels
        end.
    end.
    label =. well{::'bad';'ok'
    line =. 'image ',(integer width),' ',(integer height),' quiet ',(integer left intdiv unit),' scale ',(integer unit),' size ',(integer n),' ',label
    (<n),(<symbol),<line
)

codes_lines =: 3 : 0
    line =. 'symbol version ',(integer ReqVersion),' level ',ReqLevel,' mask ',(integer ChosenMask),' size ',integer SymbolSize
    lines =. ,<line
    descriptions =. 0$a:
    for_segment. ReqSegments do.
        'mode text' =. >segment
        descriptions =. descriptions,<mode,':',integer #text
    end.
    lines =. lines,<'segments ',(integer #ReqSegments),' ',' 'join descriptions
    alternatives =. 0$a:
    for_mode. Modes do.
        mode =. >mode
        value =. '-'
        if. mode encodable ReqText do.
            value =. integer mode segment_width ReqText;ReqVersion
        end.
        alternatives =. alternatives,<mode,' ',value
    end.
    mixed =. 1{::ReqVersion mixed_segments ReqText
    alternatives =. alternatives,<'MIXED ',integer mixed
    lines =. lines,<'bits data ',(integer ReqBitCount),' capacity ',(integer Capacity),' alternatives ',' 'join alternatives
    fits =. 0$a:
    for_level. Levels do.
        fitting =. '-'
        for_version. 1+i.10 do.
            bits =. 1{::(version=10){::ReqSplits
            if. bits<:5{::version layout >level do.
                fitting =. integer version
                break.
            end.
        end.
        fits =. fits,< (>level),' ',fitting
    end.
    lines =. lines,<'fits ',' 'join fits
    remainder =. (#Order)-8*Total
    lines =. lines,<'modules function ',(integer (SymbolSize*SymbolSize)-#Order),' data ',(integer #Order),' remainder ',(integer remainder),' dark ',integer DarkCount
    information =. ReqLevel format_information ChosenMask
    version_text =. 'none'
    if. ReqVersion>:7 do.
        version_text =. 18 binary_text version_information ReqVersion
    end.
    lines =. lines,<'format ',(15 binary_text information),' version ',version_text
    for_mask. i.8 do.
        'n1 n2 n3 n4' =. mask{Penalties
        lines =. lines,<'penalty ',(integer mask),' n1 ',(integer n1),' n2 ',(integer n2),' n3 ',(integer n3),' n4 ',(integer n4),' total ',integer n1+n2+n3+n4
    end.
    lines,SymbolSize symbol_lines Symbol
)
codeword_lines =: 3 : 0
    line =. 'request ',ReqId,' version ',(integer ReqVersion),' level ',ReqLevel,' blocks ',(integer #Lengths),' data ',(integer DataCount),' ec_per_block ',(integer Degree),' total ',integer Total
    lines =. ,<line
    for_block. i.#Blocks do.
        length =. block{Lengths
        words =. block{::Blocks
        lines =. lines,<'block ',(integer block),' data ',hexadecimal length{.words
        lines =. lines,<'block ',(integer block),' ec ',hexadecimal length}.words
    end.
    lines,<'interleaved ',hexadecimal Codewords
)
bitstream_lines =: 3 : 0
    line =. 'request ',ReqId,' version ',(integer ReqVersion),' bits ',(integer ReqBitCount),' capacity ',integer Capacity
    lines =. (<line),BitTrace
    'terminator zero_fill pad_count' =. Padding
    lines,<'terminator ',(integer terminator),' zero_fill ',(integer zero_fill),' pad_bytes ',integer pad_count
)
damaged_symbol =: 3 : 0
    symbol =. Symbol
    for_operation. y do.
        operation =. >operation
        kind =. 1{::operation
        if. kind-:'flip' do.
            'xx yy' =. ".' 'join 2}.operation
            position =. xx+SymbolSize*yy
            symbol =. (-.position{symbol)position}symbol
        elseif. kind-:'fill' do.
            'left top width height' =. ".' 'join 4{.2}.operation
            color =. 'dark'-:6{::operation
            for_yy. top+i.height do.
                positions =. (left+i.width)+SymbolSize*yy
                symbol =. color positions}symbol
            end.
        end.
    end.
    counts =. 5$0
    damaged_words =. (#Lengths)$<i.0
    changed =. I.symbol~:Symbol
    for_position. changed do.
        area =. position{Areas
        if. area=0 do.
            index =. Order i.position
            if. index<8*Total do.
                category =. 3
                'block word' =. (index intdiv 8){Placement
                words =. ~.(block{::damaged_words),word
                damaged_words =. (<words)block}damaged_words
            else.
                category =. 4
            end.
        else.
            category =. area-1
        end.
        counts =. ((category{counts)+1)category}counts
    end.
    for_operation. y do.
        kind =. 1{::>operation
        if. kind-:'rotate' do.
            symbol =. SymbolSize rotate symbol
        elseif. kind-:'mirror' do.
            symbol =. SymbolSize transpose symbol
        end.
    end.
    names =. ;:'function format version data remainder'
    details =. 0$a:
    for_i. i.5 do.
        details =. details,<(i{::names),' ',integer i{counts
    end.
    lines =. <'check damaged operations ',integer #y
    lines =. lines,<'damage changed ',(integer #changed),' ',' 'join details
    errors =. #&>damaged_words
    lines =. lines,<'errors ',(numbers errors),' limit ',integer Degree intdiv 2
    (<symbol),<lines
)
tolerance =: 3 : 0
    color =. y
    for_side. 1+i.SymbolSize do.
        symbol =. Symbol
        start =. (SymbolSize-side)intdiv 2
        for_yy. start+i.side do.
            positions =. (start+i.side)+SymbolSize*yy
            symbol =. color positions}symbol
        end.
        result =. SymbolSize decode symbol
        if. (-.0{::result)+.-.ReqText-:1{::result do.
            side-1 return.
        end.
    end.
    SymbolSize
)
record_check =: 3 : 0
    if. -.0{::y do.
        result =. 2
    elseif. ReqText-:1{::y do.
        result =. 0
    else.
        result =. 1
    end.
    CheckCounts =: ((result{CheckCounts)+1)result}CheckCounts
    BlockCounts =: BlockCounts+3{::y
    result{::'ok';'mismatch';'failed'
)
check_lines =: 3 : 0
    filename =. 'qr_',ReqId,'.pbm'
    filename save (SymbolSize,QuietZone,Scale)pbm_lines Symbol
    'n image image_line' =. read_image 'output/',filename
    lines =. (<'request ',ReqId),(<image_line),<'check clean'
    result =. n decode image
    lines =. lines,(2{::result),<'result ',record_check result
    operations =. 0$a:
    for_operation. Damage do.
        if. ReqId-:0{::>operation do.
            operations =. operations,operation
        end.
    end.
    if. #operations do.
        'symbol detail' =. damaged_symbol operations
        lines =. lines,detail
        result =. SymbolSize decode symbol
        lines =. lines,(2{::result),<'result ',record_check result
    end.
    light =. tolerance 0
    dark =. tolerance 1
    lines,<'tolerance light ',(integer light),' dark ',integer dark
)
capacity_lines =: 3 : 0
    lines =. 0$a:
    for_version. 1+i.10 do.
        'n symbol areas order' =. (version-1){::Geometries
        total =. 4{::version layout 'L'
        centers =. (version-1){::Alignments
        alignment =. 'none'
        if. #centers do.
            alignment =. numbers centers
        end.
        line =. 'version ',(integer version),' size ',(integer n),' data_modules ',(integer #order),' codewords ',(integer total)
        line =. line,' remainder ',(integer (#order)-8*total),' alignment ',alignment
        lines =. lines,<line
        for_level. Levels do.
            level =. >level
            'degree lengths placement data total capacity' =. version layout level
            maxima =. i.0
            for_mode. Modes do.
                mode =. >mode
                count =. 0
                while. (4+(mode count_width version)+mode data_width count+1)<:capacity do.
                    count =. count+1
                end.
                maxima =. maxima,count
            end.
            'numeric alphanumeric byte' =. maxima
            line =. 'level ',level,' blocks ',(integer #lengths),' data ',(integer data),' ec_per_block ',(integer degree),' numeric '
            line =. line,(integer numeric),' alphanumeric ',(integer alphanumeric),' byte ',integer byte
            lines =. lines,<line
        end.
    end.
    lines
)
paired_counts =: 4 : 0
    parts =. 0$a:
    for_i. i.#x do.
        parts =. parts,<(i{::x),' ',integer i{y
    end.
    ' 'join parts
)
summary_lines =: 3 : 0
    lines =. <'requests ',(integer #Requests),' encoded ',(integer EncodedCount),' errors ',integer +/ErrorCounts
    lines =. lines,<'error_kinds ',ErrorKinds paired_counts ErrorCounts
    lines =. lines,<'modes ',(Modes,<'MIXED')paired_counts ModeCounts
    lines =. lines,<'levels ',(Levels paired_counts LevelCounts),' boosted ',integer BoostedCount
    lines =. lines,<'versions ',numbers VersionCounts
    lines =. lines,<'masks ',numbers MaskCounts
    lines =. lines,<'segments ',(integer SegmentCount),' data_codewords ',(integer DataTotal),' ec_codewords ',integer ECTotal
    lines =. lines,<'modules ',(integer ModuleTotal),' dark ',integer DarkTotal
    lines =. lines,<'checks ',(integer +/CheckCounts),' ',(;:'ok mismatch failed')paired_counts CheckCounts
    lines =. lines,<'blocks ',((;:'ok corrected failed')paired_counts 3{.BlockCounts),' codewords ',integer 3{BlockCounts
    lines =. lines,<'scans ',(integer +/ScanCounts),' decoded ',(integer 0{ScanCounts),' failed ',integer 1{ScanCounts
    lines
)
run =: 3 : 0
    read_inputs ''
    gf_initialize ''
    try.
        1!:5 <'output'
    catch.
    end.
    ErrorCounts =: 7$0
    ModeCounts =: 4$0
    LevelCounts =: 4$0
    VersionCounts =: 10$0
    MaskCounts =: 8$0
    CheckCounts =: 3$0
    BlockCounts =: 4$0
    ScanCounts =: 2$0
    EncodedCount =: 0
    BoostedCount =: 0
    SegmentCount =: 0
    DataTotal =: 0
    ECTotal =: 0
    ModuleTotal =: 0
    DarkTotal =: 0
    codes =. 0$a:
    codewords =. 0$a:
    bitstream =. 0$a:
    selfcheck =. 0$a:
    scans =. 0$a:
    for_request. Requests do.
        error =. prepare_request >request
        codes =. codes,<'request ',ReqId
        if. #error do.
            codes =. codes,<'error ',error
            kind =. ErrorKinds i.{.split_words error
            ErrorCounts =: ((kind{ErrorCounts)+1)kind}ErrorCounts
            continue.
        end.
        encode_request ''
        codes =. codes,codes_lines ''
        codewords =. codewords,codeword_lines ''
        bitstream =. bitstream,bitstream_lines ''
        selfcheck =. selfcheck,check_lines ''
        EncodedCount =: EncodedCount+1
        index =. (Modes,<'MIXED')i.<ReqMode
        ModeCounts =: ((index{ModeCounts)+1)index}ModeCounts
        index =. Levels i.<ReqLevel
        LevelCounts =: ((index{LevelCounts)+1)index}LevelCounts
        BoostedCount =: BoostedCount+ReqBoosted
        VersionCounts =: (( (ReqVersion-1){VersionCounts)+1)(ReqVersion-1)}VersionCounts
        MaskCounts =: ((ChosenMask{MaskCounts)+1)ChosenMask}MaskCounts
        SegmentCount =: SegmentCount+#ReqSegments
        DataTotal =: DataTotal+DataCount
        ECTotal =: ECTotal+Degree*#Lengths
        ModuleTotal =: ModuleTotal+SymbolSize*SymbolSize
        DarkTotal =: DarkTotal+DarkCount
    end.
    for_scan. Scans do.
        'name n symbol' =. >scan
        scans =. scans,<'scan ',name,' size ',integer n
        result =. n decode symbol
        scans =. scans,2{::result
        label =. 'failed'
        index =. 1
        if. 0{::result do.
            label =. 'decoded'
            index =. 0
        end.
        ScanCounts =: ((index{ScanCounts)+1)index}ScanCounts
        scans =. scans,<'result ',label
    end.
    'codes.txt' save codes
    'codewords.txt' save codewords
    'bitstream.txt' save bitstream
    'selfcheck.txt' save selfcheck
    'scans.txt' save scans
    'capacity.txt' save capacity_lines ''
    'summary.txt' save summary_lines ''
)
run ''
