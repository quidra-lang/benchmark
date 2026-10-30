load 'tiles.ijs'
load 'decomposition.ijs'
load 'yaku.ijs'
load 'scoring.ijs'
load 'shanten.ijs'

WaitOrder =: ;:'ryanmen kanchan penchan shanpon tanki single thirteen'
WinOrder =: ;:'dealer_ron dealer_tsumo nondealer_ron nondealer_tsumo'
intdiv =: 4 : '<.(x:x)%x:y'
integer =: 3 : 0
    text =. ,":y
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
split_words =: 3 : '<;._1 '' '',y'
split_commas =: 3 : '<;._1 '','',y'
read_records =: 3 : 0
    records =. 0$a:
    for_line. <;._2 (1!:1 <'input/',y) do.
        words =. split_words >line
        values =. 0$a:
        for_word. }.words do.
            word =. >word
            values =. values,<(1+word i.'=')}.word
        end.
        records =. records,<(0{words),<values
    end.
    records
)
read_inputs =: 3 : 0
    RuleNames =: 0$a:
    RuleValues =: 0$a:
    for_record. read_records 'rules.txt' do.
        'name fields' =. >record
        values =. i.0
        for_i. i.5 do.
            values =. values,'yes'-:i{::fields
        end.
        values =. values,".5{::fields
        RuleNames =: RuleNames,<name
        RuleValues =: RuleValues,<values
    end.
    Situations =: read_records 'hands.txt'
    WaitingHands =: read_records 'waits.txt'
)
set_situation =: 4 : 0
    Label =: x
    'RuleName hand melds win by seat from round flags dora ura discards honba sticks' =. y
    RuleIndex =: RuleNames i.<RuleName
    Rule =: RuleIndex{::RuleValues
    HandTiles =: 0 parse_tiles hand
    WinTiles =: 0 parse_tiles win
    DoraTiles =: 0 parse_tiles dora
    UraTiles =: 1 parse_tiles ura
    DiscardTiles =: 1 parse_tiles discards
    MeldTypes =: ''
    MeldTiles =: 0$a:
    MeldBlocks =: 0$a:
    if. -.(,melds)-:,'-' do.
        for_text. split_commas melds do.
            text =. >text
            tiles =. 0 parse_tiles }.text
            block =. i.0
            if. -.invalid_tiles tiles do.
                block =. /:~0{"1 tiles
            end.
            MeldTypes =: MeldTypes,{.text
            MeldTiles =: MeldTiles,<tiles
            MeldBlocks =: MeldBlocks,<block
        end.
    end.
    Tsumo =: by-:'tsumo'
    Seat =: Winds i.{.seat
    Discarder =: Winds i.{.from
    Round =: Winds i.{.round
    SeatTile =: 27+Seat
    RoundTile =: 27+Round
    Flags =: 0$a:
    if. -.(,flags)-:,'-' do.
        Flags =: split_commas flags
    end.
    Closed =: *./MeldTypes='A'
    Riichi =: +./Flags e.;:'riichi double_riichi'
    KanCount =: +/MeldTypes e.'KA'
    Honba =: ".honba
    Sticks =: ".sticks
)
prepare_counts =: 3 : 0
    WinningTile =: (<0,0){WinTiles
    HandCounts =: tile_counts HandTiles
    ConcealedCounts =: tile_counts HandTiles,WinTiles
    MeldCounts =: 34$0
    AllTiles =: HandTiles,WinTiles
    for_tiles. MeldTiles do.
        MeldCounts =: MeldCounts+tile_counts >tiles
        AllTiles =: AllTiles,>tiles
    end.
    AllCounts =: tile_counts AllTiles
)
copy_error =: 3 : 0
    reds =. 3$0
    for_tile. y do.
        'kind red' =. tile
        if. red do.
            suit =. kind intdiv 9
            reds =. ((suit{reds)+1)suit}reds
        end.
    end.
    if. (-.1{Rule)*.+./reds do.
        'red five not allowed' return.
    end.
    counts =. tile_counts y
    too_many =. I.counts>:5
    if. #too_many do.
        'too many copies of ',tile_name {.too_many return.
    end.
    too_many =. I.reds>:2
    if. #too_many do.
        'too many copies of 0',({.too_many){'mps' return.
    end.
    ''
)
valid_meld =: 4 : 0
    if. x='C' do.
        if. 3~:#y do.
            0 return.
        end.
        first =. {.y
        (first<27)*.((9|first)<:6)*.y-:first+i.3
    elseif. x e.'PKA' do.
        size =. 4
        if. x='P' do.
            size =. 3
        end.
        (size=#y)*.1=#~.y
    else.
        0
    end.
)
validate_situation =: 3 : 0
    parsed =. (<HandTiles),(<WinTiles),(<DoraTiles),(<UraTiles),(<DiscardTiles),MeldTiles
    if. +./invalid_tiles&>parsed do.
        'bad tile notation' return.
    end.
    if. 1~:#WinTiles do.
        'bad tile notation' return.
    end.
    if. 5<:#MeldTypes do.
        'bad meld' return.
    end.
    for_i. i.#MeldTypes do.
        if. -.(i{MeldTypes)valid_meld i{::MeldBlocks do.
            'bad meld' return.
        end.
    end.
    if. (#HandTiles)~:13-3*#MeldTypes do.
        'wrong tile count' return.
    end.
    prepare_counts ''
    error =. copy_error AllTiles,DoraTiles,UraTiles,DiscardTiles
    if. #error do.
        error return.
    end.
    if. (Tsumo*.Discarder~:4)+.((-.Tsumo)*.(Discarder=4)+.Discarder=Seat) do.
        'invalid discarder' return.
    end.
    conditions =. Closed,((Closed)*.-.(<'riichi')e.Flags)
    conditions =. conditions,(Riichi*.-.(<'rinshan')e.Flags),(Tsumo*.-.(<'rinshan')e.Flags)
    conditions =. conditions,((-.Tsumo)*.-.(<'chankan')e.Flags),(Tsumo*.KanCount>:1),-.Tsumo
    special =. Tsumo*.(0=#MeldTypes)*.1=#Flags
    conditions =. conditions,(special*.Seat=0),special*.Seat~:0
    for_i. i.#FlagNames do.
        if. ((i{FlagNames)e.Flags)*.-.i{conditions do.
            'invalid flag ',i{::FlagNames return.
        end.
    end.
    if. (#DoraTiles)~:1+KanCount do.
        'invalid dora indicators' return.
    end.
    if. (Riichi*.(#UraTiles)~:#DoraTiles)+.((-.Riichi)*.0<#UraTiles) do.
        'invalid ura indicators' return.
    end.
    if. Riichi*.Sticks=0 do.
        'invalid sticks' return.
    end.
    if. -.(#MeldTypes)winning_form ConcealedCounts do.
        'not a winning hand' return.
    end.
    ''
)
make_candidates =: 3 : 0
    result =. 0$a:
    forms =. 0$a:
    for_decomposition. (#MeldTypes)standard_decompositions ConcealedCounts do.
        'pair sets' =. >decomposition
        blocks =. (<2$pair),sets
        choices =. 0$a:
        for_block. blocks do.
            if. WinningTile e.>block do.
                if. -.block e.choices do.
                    choices =. choices,block
                end.
            end.
        end.
        for_chosen. choices do.
            chosen =. >chosen
            parts =. ,<'standard'
            marked =. 0
            for_block. blocks do.
                block =. >block
                notation =. block_notation block
                if. (-.marked)*.block-:chosen do.
                    notation =. notation,'*'
                    marked =. 1
                end.
                parts =. parts,<notation
            end.
            for_i. i.#MeldTypes do.
                parts =. parts,<(i{MeldTypes),block_notation i{::MeldBlocks
            end.
            form =. ' 'join parts
            descriptor =. (<'standard'),(<chosen),(<WinningTile),<HandCounts
            wait =. wait_shape descriptor
            candidate =. (<'standard'),(<pair),(<sets),(<chosen),(<form),<wait
            result =. result,<candidate
            forms =. forms,<form
        end.
    end.
    if. 0=#MeldTypes do.
        if. seven_pairs ConcealedCounts do.
            parts =. ,<'chiitoitsu'
            for_kind. I.ConcealedCounts>0 do.
                notation =. block_notation 2$kind
                if. kind=WinningTile do.
                    notation =. notation,'*'
                end.
                parts =. parts,<notation
            end.
            form =. ' 'join parts
            candidate =. (<'chiitoitsu'),(<_1),(<0$a:),(<i.0),(<form),<'tanki'
            result =. result,<candidate
            forms =. forms,<form
        end.
        if. thirteen_orphans ConcealedCounts do.
            parts =. ,<'kokushi'
            for_kind. Yaochuu do.
                notation =. block_notation (kind{ConcealedCounts)$kind
                if. kind=WinningTile do.
                    notation =. notation,'*'
                end.
                parts =. parts,<notation
            end.
            form =. ' 'join parts
            descriptor =. (<'kokushi'),(<i.0),(<WinningTile),<HandCounts
            candidate =. (<'kokushi'),(<_1),(<0$a:),(<i.0),(<form),<wait_shape descriptor
            result =. result,<candidate
            forms =. forms,<form
        end.
    end.
    (/:forms){result
)
block_facts =: 3 : 0
    sets =. 2{::y
    chosen =. 3{::y
    triplets =. 0$a:
    sequences =. i.0
    concealed_sequences =. 0$a:
    for_block. sets do.
        block =. >block
        if. ({.block)={:block do.
            concealed =. Tsumo+.-.block-:chosen
            triplets =. triplets,<( <block),(<concealed),<0
        else.
            sequences =. sequences,{.block
            concealed_sequences =. concealed_sequences,<block
        end.
    end.
    for_i. i.#MeldTypes do.
        block =. i{::MeldBlocks
        kind =. i{MeldTypes
        if. kind='C' do.
            sequences =. sequences,{.block
        else.
            triplets =. triplets,<( <block),(<kind='A'),<kind e.'KA'
        end.
    end.
    (<triplets),(<sequences),<concealed_sequences
)
yakuman_names =: 4 : 0
    'candidate triplets' =. y
    kinds =. x
    form =. 0{::candidate
    pair =. 1{::candidate
    wait =. 5{::candidate
    names =. Flags#~Flags e.;:'tenhou chiihou'
    if. *./honor kinds do.
        names =. names,<'tsuuiisou'
    end.
    if. *./terminal kinds do.
        names =. names,<'chinroutou'
    end.
    if. *./kinds e.Green do.
        names =. names,<'ryuuiisou'
    end.
    suits =. ~.kinds intdiv 9
    if. (0=#MeldTypes)*.(1=#suits)*.-.+./honor kinds do.
        start =. 9*{.suits
        counts =. 9{.start}.AllCounts
        if. ((0{counts)>:3)*.((8{counts)>:3)*.*./0<7{.1}.counts do.
            if. 3 1 1 1 1 1 1 1 3-:9{.start}.HandCounts do.
                names =. names,<'junsei_chuuren'
            else.
                names =. names,<'chuuren'
            end.
        end.
    end.
    if. form-:'kokushi' do.
        if. wait-:'thirteen' do.
            names =. names,<'kokushi_13'
        else.
            names =. names,<'kokushi'
        end.
    end.
    if. form-:'standard' do.
        concealed =. 0
        kans =. 0
        triplet_kinds =. i.0
        for_triplet. triplets do.
            'block hidden kan' =. >triplet
            concealed =. concealed+hidden
            kans =. kans+kan
            triplet_kinds =. triplet_kinds,{.block
        end.
        if. concealed=4 do.
            if. wait-:'tanki' do.
                names =. names,<'suuankou_tanki'
            else.
                names =. names,<'suuankou'
            end.
        end.
        if. 3=+/31 32 33 e.triplet_kinds do.
            names =. names,<'daisangen'
        end.
        winds =. +/27 28 29 30 e.triplet_kinds
        if. winds=4 do.
            names =. names,<'daisuushii'
        elseif. (winds=3)*.pair e.27 28 29 30 do.
            names =. names,<'shousuushii'
        end.
        if. kans=4 do.
            names =. names,<'suukantsu'
        end.
    end.
    names
)

ordinary_names =: 4 : 0
    kinds =. x
    'candidate triplets sequences concealed_sequences' =. y
    form =. 0{::candidate
    pair =. 1{::candidate
    sets =. 2{::candidate
    wait =. 5{::candidate
    names =. Flags#~Flags e.7{.FlagNames
    if. Closed*.Tsumo do.
        names =. names,<'menzen_tsumo'
    end.
    if. (*./-.yaochuu kinds)*.(Closed+.0{Rule) do.
        names =. names,<'tanyao'
    end.
    if. *./yaochuu kinds do.
        names =. names,<'honroutou'
    end.
    number_suits =. ~.(kinds#~kinds<27)intdiv 9
    honors =. +./honor kinds
    if. 1=#number_suits do.
        if. honors do.
            names =. names,<'honitsu'
        else.
            names =. names,<'chinitsu'
        end.
    end.
    if. form-:'chiitoitsu' do.
        names =. names,<'chiitoitsu'
    end.
    if. -.form-:'standard' do.
        names return.
    end.
    yakuhai_pair =. (pair>:31)+.pair e.SeatTile,RoundTile
    if. Closed*.(0=#MeldTypes)*.(4=#concealed_sequences)*.(-.yakuhai_pair)*.wait-:'ryanmen' do.
        names =. names,<'pinfu'
    end.
    repeated =. i.0
    for_sequence. ~.concealed_sequences do.
        repeated =. repeated,+/sequence-:"0 concealed_sequences
    end.
    ryanpeikou =. Closed*.(4=#concealed_sequences)*.2=+/repeated intdiv 2
    if. ryanpeikou do.
        names =. names,<'ryanpeikou'
    elseif. Closed*.+./repeated>:2 do.
        names =. names,<'iipeikou'
    end.
    triplet_kinds =. i.0
    concealed =. 0
    kans =. 0
    for_triplet. triplets do.
        'block hidden kan' =. >triplet
        triplet_kinds =. triplet_kinds,{.block
        concealed =. concealed+hidden
        kans =. kans+kan
    end.
    yakuhai_kinds =. 31 32 33,SeatTile,RoundTile
    yakuhai_names =. ;:'haku hatsu chun jikaze bakaze'
    for_i. i.5 do.
        if. (i{yakuhai_kinds)e.triplet_kinds do.
            names =. names,i{yakuhai_names
        end.
    end.
    if. 4=#triplets do.
        names =. names,<'toitoi'
    end.
    if. concealed=3 do.
        names =. names,<'sanankou'
    end.
    for_start. i.7 do.
        if. *./(start+0 9 18)e.sequences do.
            names =. names,<'sanshoku_doujun'
            break.
        end.
    end.
    for_number. i.9 do.
        if. *./(number+0 9 18)e.triplet_kinds do.
            names =. names,<'sanshoku_doukou'
            break.
        end.
    end.
    for_suit. i.3 do.
        if. *./((9*suit)+0 3 6)e.sequences do.
            names =. names,<'ittsu'
            break.
        end.
    end.
    blocks =. (<2$pair),sets,MeldBlocks
    all_outside =. 1
    for_block. blocks do.
        all_outside =. all_outside*.+./yaochuu >block
    end.
    if. (0<#sequences)*.all_outside do.
        if. honors do.
            names =. names,<'chanta'
        else.
            names =. names,<'junchan'
        end.
    end.
    if. kans=3 do.
        names =. names,<'sankantsu'
    end.
    if. (2=+/31 32 33 e.triplet_kinds)*.pair>:31 do.
        names =. names,<'shousangen'
    end.
    ~.names
)
evaluate_candidate =: 3 : 0
    candidate =. y
    'form pair sets chosen form_text wait' =. candidate
    kinds =. I.AllCounts>0
    'triplets sequences concealed_sequences' =. block_facts candidate
    names =. kinds yakuman_names(<candidate),<triplets
    yakuman =. (2{Rule)yakuman_yaku names
    multiplier =. 0
    han =. 0
    fu =. 0
    fu_total =. 0
    base =. 0
    dora =. 0
    aka =. 0
    ura =. 0
    category =. 0
    ordinary =. 0$a:
    fu_items =. 0$a:
    if. #yakuman do.
        for_item. yakuman do.
            multiplier =. multiplier+1{::>item
        end.
        base =. 8000*multiplier
        category =. 6
    else.
        descriptor =. (<candidate),(<triplets),(<sequences),<concealed_sequences
        names =. kinds ordinary_names descriptor
        ordinary =. Closed ordinary_yaku names
        for_kind. 0{"1 DoraTiles do.
            dora =. dora+AllCounts{~next_dora kind
        end.
        for_kind. 0{"1 UraTiles do.
            ura =. ura+AllCounts{~next_dora kind
        end.
        aka =. +/1{"1 AllTiles
        descriptor =. (<form),(<pair),(<triplets),(<wait),(<Closed),(<Tsumo),(<SeatTile),(<RoundTile),< (<'pinfu')e.names
        'fu_items fu_total fu' =. fu_breakdown descriptor
        if. #ordinary do.
            for_item. ordinary do.
                han =. han+1{::>item
            end.
            han =. han+dora+aka+ura
            'category base' =. Rule score_limit han,fu
        end.
    end.
    evaluation =. (<ordinary),(<yakuman),(<fu_items),(<multiplier),(<han),(<fu),(<fu_total)
    evaluation =. evaluation,(<base),(<dora),(<aka),(<ura),<category
    candidate,evaluation
)
evaluate_candidates =: 3 : 'evaluate_candidate&.>make_candidates y'
best_candidate =: 3 : 0
    best =. _1
    best_key =. i.0
    for_i. i.#y do.
        candidate =. i{::y
        base =. 13{::candidate
        if. base<1 do.
            continue.
        end.
        yakuman =. 0<#7{::candidate
        han =. 10{::candidate
        fu =. 11{::candidate
        if. yakuman do.
            han =. 0
            fu =. 0
        end.
        key =. (-base),(-yakuman),(-han),-fu
        if. best=_1 do.
            best =. i
            best_key =. key
        elseif. 0={./:key,:best_key do.
            if. -.key-:best_key do.
                best =. i
                best_key =. key
            end.
        end.
    end.
    if. best=_1 do.
        0$a:
    else.
        best{::y
    end.
)
names_of =: 3 : 0
    names =. 0$a:
    for_item. y do.
        names =. names,0{>item
    end.
    names
)
candidate_line =: 3 : 0
    ordinary =. 6{::y
    yakuman =. 7{::y
    if. #yakuman do.
        evaluation =. 'yakuman ',(integer 9{::y),' base ',(integer 13{::y),' yaku ',','join names_of yakuman
    elseif. 0=#ordinary do.
        evaluation =. 'no_yaku'
    else.
        evaluation =. 'han ',(integer 10{::y),' fu ',(integer 11{::y),' base ',integer 13{::y
        evaluation =. evaluation,' yaku ',','join names_of ordinary
    end.
    'CANDIDATE ',(4{::y),' = ',(5{::y),' ',evaluation
)
winning_lines =: 3 : 0
    ordinary =. 6{::y
    yakuman =. 7{::y
    lines =. (<'FORM ',4{::y),<'WAIT ',5{::y
    if. #yakuman do.
        for_item. yakuman do.
            'name multiplier' =. >item
            lines =. lines,<'YAKUMAN ',name,' ',integer multiplier
        end.
        lines =. lines,<'SCORE yakuman ',(integer 9{::y),' base ',integer 13{::y
    else.
        for_item. ordinary do.
            'name han' =. >item
            lines =. lines,<'YAKU ',name,' ',integer han
        end.
        line =. 'DORA dora ',(integer 14{::y),' aka ',(integer 15{::y),' ura ',integer 16{::y
        lines =. lines,<line
        for_item. 8{::y do.
            'name amount' =. >item
            lines =. lines,<'FU ',name,' ',integer amount
        end.
        lines =. lines,<'FU total ',(integer 12{::y),' ',integer 11{::y
        line =. 'SCORE han ',(integer 10{::y),' fu ',(integer 11{::y),' limit ',(17{::y){::Categories
        lines =. lines,<line,' base ',integer 13{::y
    end.
    'ron dealer other points' =. payments (13{::y),(Seat=0),Tsumo
    if. -.Tsumo do.
        line =. 'PAY ron ',integer ron
    elseif. Seat=0 do.
        line =. 'PAY tsumo all ',integer other
    else.
        line =. 'PAY tsumo dealer ',(integer dealer),' nondealer ',integer other
    end.
    lines =. lines,<line
    honba =. Honba*5{Rule
    sticks =. 1000*Sticks
    gain =. points+honba+sticks
    lines =. lines,<'BONUS honba ',(integer honba),' sticks ',integer sticks
    lines =. lines,<'TOTAL points ',(integer points),' gain ',integer gain
    delta =. 4$0
    if. -.Tsumo do.
        delta =. (-(ron+honba))Discarder}delta
    else.
        for_wind. (i.4)-.Seat do.
            amount =. other
            if. wind=0 do.
                amount =. dealer
            end.
            delta =. (-(amount+honba intdiv 3))wind}delta
        end.
    end.
    delta =. gain Seat}delta
    parts =. 0$a:
    for_wind. i.4 do.
        value =. wind{delta
        text =. integer value
        if. value>0 do.
            text =. '+',text
        end.
        parts =. parts,<(wind{Winds),' ',text
    end.
    lines =. lines,<'DELTA ',' 'join parts
    (<lines),<points
)

initialize_reports =: 3 : 0
    ScoreTotals =: 5$0
    WinCounts =: 4$0
    WaitCounts =: 7$0
    HanObserved =: i.0
    FuObserved =: i.0
    LimitCounts =: 7$0
    AllYakuNames =: YakuNames,YakumanNames
    YakuCounts =: (#AllYakuNames)$0
    RuleCounts =: ((#RuleNames),3)$0
    MaximumPoints =: 0
    MaximumHand =: '-'
    Summary =: ,<'hand,han,fu,points,yaku'
)
record_win =: 4 : 0
    points =. x
    candidate =. y
    ScoreTotals =: (1+0{ScoreTotals)0}ScoreTotals
    ScoreTotals =: ((4{ScoreTotals)+points)4}ScoreTotals
    RuleCounts =: (1+(<RuleIndex,1){RuleCounts)(<RuleIndex,1)}RuleCounts
    RuleCounts =: (points+(<RuleIndex,2){RuleCounts)(<RuleIndex,2)}RuleCounts
    group =. (2*Seat~:0)+Tsumo
    WinCounts =: ((group{WinCounts)+1)group}WinCounts
    wait =. WaitOrder i.5{candidate
    WaitCounts =: ((wait{WaitCounts)+1)wait}WaitCounts
    category =. 17{::candidate
    LimitCounts =: ((category{LimitCounts)+1)category}LimitCounts
    yakuman =. 7{::candidate
    if. #yakuman do.
        names =. names_of yakuman
        han =. 'Y',integer 9{::candidate
        fu =. '-'
    else.
        names =. names_of 6{::candidate
        han =. integer 10{::candidate
        fu =. integer 11{::candidate
        HanObserved =: HanObserved,10{::candidate
        FuObserved =: FuObserved,11{::candidate
    end.
    for_name. names do.
        index =. AllYakuNames i.name
        YakuCounts =: ((index{YakuCounts)+1)index}YakuCounts
    end.
    line =. Label,',',han,',',fu,',',(integer points),',',';'join names
    Summary =: Summary,<line
    if. points>MaximumPoints do.
        MaximumPoints =: points
        MaximumHand =: Label
    end.
)
paired_counts =: 4 : 0
    parts =. 0$a:
    for_i. i.#x do.
        parts =. parts,<(i{::x),' ',integer i{y
    end.
    ' 'join parts
)
score_statistics =: 3 : 0
    line =. 'STATS hands ',(integer #Situations),' wins ',(integer 0{ScoreTotals),' furiten ',integer 1{ScoreTotals
    lines =. <line,' no_yaku ',(integer 2{ScoreTotals),' errors ',integer 3{ScoreTotals
    lines =. lines,<'WINS ',WinOrder paired_counts WinCounts
    lines =. lines,<'WAIT_COUNT ',WaitOrder paired_counts WaitCounts
    for_han. /:~~.HanObserved do.
        lines =. lines,<'HAN_COUNT ',(integer han),' ',integer +/han=HanObserved
    end.
    for_fu. /:~~.FuObserved do.
        lines =. lines,<'FU_COUNT ',(integer fu),' ',integer +/fu=FuObserved
    end.
    for_i. i.#Categories do.
        lines =. lines,<'LIMIT ',(i{::Categories),' ',integer i{LimitCounts
    end.
    for_i. I.YakuCounts>0 do.
        lines =. lines,<'YAKU_COUNT ',(i{::AllYakuNames),' ',integer i{YakuCounts
    end.
    lines =. lines,<'POINTS total ',(integer 4{ScoreTotals),' max ',(integer MaximumPoints),' hand ',MaximumHand
    for_i. i.#RuleNames do.
        'hands wins points' =. i{RuleCounts
        line =. 'RULE ',(i{::RuleNames),' hands ',(integer hands),' wins ',(integer wins),' points ',integer points
        lines =. lines,<line
    end.
    lines
)
score_situations =: 3 : 0
    lines =. 0$a:
    for_record. Situations do.
        'label fields' =. >record
        label set_situation fields
        position =. <RuleIndex,0
        RuleCounts =: (1+position{RuleCounts)position}RuleCounts
        lines =. lines,<'HAND ',label
        error =. validate_situation ''
        if. #error do.
            ScoreTotals =: (1+3{ScoreTotals)3}ScoreTotals
            lines =. lines,<'ERROR ',error
            Summary =: Summary,<label,',-,-,0,ERROR'
            continue.
        end.
        descriptor =. (<HandCounts),(<MeldCounts),<#MeldTypes
        waiting =. waiting_tiles descriptor
        lines =. lines,<'WAITS ',' 'join tile_name&.>waiting
        evaluated =. evaluate_candidates ''
        lines =. lines,candidate_line&.>evaluated
        if. (-.Tsumo)*.+./(0{"1 DiscardTiles)e.waiting do.
            ScoreTotals =: (1+1{ScoreTotals)1}ScoreTotals
            lines =. lines,<'RESULT furiten'
            Summary =: Summary,<label,',-,-,0,FURITEN'
            continue.
        end.
        best =. best_candidate evaluated
        if. 0=#best do.
            ScoreTotals =: (1+2{ScoreTotals)2}ScoreTotals
            lines =. lines,<'RESULT no_yaku'
            Summary =: Summary,<label,',-,-,0,NO_YAKU'
            continue.
        end.
        'report points' =. winning_lines best
        lines =. lines,report
        points record_win best
    end.
    lines,score_statistics ''
)
prepare_waiting =: 4 : 0
    WaitLabel =: x
    WaitFields =: y
    Rule =: (RuleNames i.0{y){::RuleValues
    WaitHandTiles =: 0 parse_tiles 1{::y
    WaitDoraTiles =: 0 parse_tiles 5{::y
    WaitDiscardTiles =: 1 parse_tiles 6{::y
    WaitVisibleTiles =: 1 parse_tiles 7{::y
    parsed =. (<WaitHandTiles),(<WaitDoraTiles),(<WaitDiscardTiles),<WaitVisibleTiles
    if. +./invalid_tiles&>parsed do.
        'bad tile notation' return.
    end.
    if. 13~:#WaitHandTiles do.
        'wrong tile count' return.
    end.
    observed =. WaitHandTiles,WaitDoraTiles,WaitDiscardTiles,WaitVisibleTiles
    error =. copy_error observed
    if. #error do.
        error return.
    end.
    WaitHandCounts =: tile_counts WaitHandTiles
    WaitKnownCounts =: tile_counts observed
    ''
)
acceptance =: 3 : 0
    current =. y
    result =. 0 2$0
    for_kind. i.34 do.
        if. 4<:kind{WaitHandCounts do.
            continue.
        end.
        counts =. ((kind{WaitHandCounts)+1)kind}WaitHandCounts
        if. current><./shanten_numbers counts do.
            result =. result,kind,4-kind{WaitKnownCounts
        end.
    end.
    result
)
hypothetical =: 3 : 0
    'winning tsumo' =. y
    seat =. 2{::WaitFields
    from =. 'E'
    if. tsumo do.
        from =. '-'
    elseif. (,seat)-:,'E' do.
        from =. 'S'
    end.
    flags =. '-'
    if. 'yes'-:4{::WaitFields do.
        flags =. 'riichi'
    end.
    by =. tsumo{::'ron';'tsumo'
    fields =. (0 1{WaitFields),(<'-'),(<tile_name winning),(<by),(2{WaitFields),(<from),(3{WaitFields),<flags
    fields =. fields,(5{WaitFields),(<'-'),(6{WaitFields),(<'0'),<'0'
    WaitLabel set_situation fields
    prepare_counts ''
)
tenpai_lines =: 4 : 0
    accepted =. x
    furiten =. y
    lines =. 0$a:
    best_kinds =. 2$_1
    best_points =. 2$_1
    for_entry. accepted do.
        'kind remaining' =. entry
        values =. 0$a:
        for_method. i.2 do.
            if. (method=0)*.furiten do.
                values =. values,<'furiten'
                continue.
            end.
            hypothetical kind,method
            best =. best_candidate evaluate_candidates ''
            if. 0=#best do.
                values =. values,<'no_yaku'
                continue.
            end.
            points =. 3{payments (13{::best),(Seat=0),method
            values =. values,<integer points
            if. points>method{best_points do.
                best_points =. points method}best_points
                best_kinds =. kind method}best_kinds
            end.
        end.
        line =. 'WAIT ',(tile_name kind),' left ',(integer remaining),' ron ',(0{::values),' tsumo ',1{::values
        lines =. lines,<line
    end.
    choices =. 0$a:
    for_method. i.2 do.
        text =. 'none'
        if. _1~:method{best_kinds do.
            text =. (tile_name method{best_kinds),' ',integer method{best_points
        end.
        choices =. choices,<text
    end.
    lines,<'BEST ron ',(0{::choices),' tsumo ',1{::choices
)
analyze_waiting =: 3 : 0
    lines =. 0$a:
    totals =. 3$0
    histogram =. 7$0
    for_record. WaitingHands do.
        'label fields' =. >record
        lines =. lines,<'HAND ',label
        error =. label prepare_waiting fields
        if. #error do.
            totals =. (1+0{totals)0}totals
            lines =. lines,<'ERROR ',error
            continue.
        end.
        'standard seven orphans' =. shanten_numbers WaitHandCounts
        current =. <./standard,seven,orphans
        histogram =. ((current{histogram)+1)current}histogram
        line =. 'SHANTEN standard ',(integer standard),' chiitoitsu ',(integer seven),' kokushi ',integer orphans
        lines =. lines,<line
        accepted =. acceptance current
        total =. +/1{"1 accepted
        if. current~:0 do.
            line =. 'ACCEPT kinds ',(integer #accepted),' tiles ',integer total
            for_entry. accepted do.
                'kind remaining' =. entry
                line =. line,' ',(tile_name kind),':',integer remaining
            end.
            lines =. lines,<line
            continue.
        end.
        totals =. (1+1{totals)1}totals
        furiten =. +./(0{"1 accepted)e.0{"1 WaitDiscardTiles
        totals =. ((2{totals)+furiten)2}totals
        label =. furiten{::'no';'yes'
        line =. 'TENPAI kinds ',(integer #accepted),' tiles ',(integer total),' furiten ',label
        lines =. lines,(<line),accepted tenpai_lines furiten
    end.
    line =. 'STATS hands ',(integer #WaitingHands),' errors ',(integer 0{totals),' tenpai ',integer 1{totals
    lines =. lines,<line,' furiten ',integer 2{totals
    for_k. i.7 do.
        lines =. lines,<'SHANTEN_COUNT ',(integer k),' ',integer k{histogram
    end.
    lines
)
write_lines =: 4 : 0
    ((LF join y),LF)1!:2 <'output/',x
)
run =: 3 : 0
    read_inputs ''
    initialize_reports ''
    scores =. score_situations ''
    waits =. analyze_waiting ''
    try.
        1!:5 <'output'
    catch.
    end.
    'scores.txt'write_lines scores
    'waits.txt'write_lines waits
    'summary.csv'write_lines Summary
)
run ''
