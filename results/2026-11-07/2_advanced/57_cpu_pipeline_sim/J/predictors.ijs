initialize_predictor =: 4 : 0
    'BtbSize RasDepth' =: x
    BtbPC =: BtbSize$_1
    BtbTarget =: BtbSize$_1
    ReturnStack =: i.0
    'PredictorName Scheme Parameters' =: y
    History =: 0
    Table =: LocalTable =: GlobalTable =: Chooser =: i.0
    if. (<Scheme)e.;:'ONEBIT TWOBIT GSHARE' do.
        Table =: ({.Parameters)#-.'ONEBIT'-:Scheme
    elseif. 'TOURNAMENT'-:Scheme do.
        LocalTable =: (0{Parameters)#1
        GlobalTable =: (1{Parameters)#1
        Chooser =: (3{Parameters)#1
    end.
    0
)
btb_lookup =: 3 : 0
    index =. BtbSize|y floor_div 4
    if. y=index{BtbPC do. index{BtbTarget else. _1 end.
)
btb_insert =: 4 : 0
    index =. BtbSize|x floor_div 4
    BtbPC =: x index}BtbPC
    BtbTarget =: y index}BtbTarget
    0
)
ras_push =: 3 : 0
    if. RasDepth do.
        if. RasDepth=#ReturnStack do. ReturnStack =: }.ReturnStack end.
        ReturnStack =: ReturnStack,y
    end.
    0
)
ras_pop =: 3 : 0
    if. 0=#ReturnStack do. _1 return. end.
    result =. {:ReturnStack
    ReturnStack =: }:ReturnStack
    result
)
updated_counter =: 4 : '0>.3<.x+_1+2*y'
xor =: 4 : '2#.((32#2)#:x)~:(32#2)#:y'
predict_direction =: 4 : 0
    index =. x floor_div 4
    select. Scheme
    case. 'STATIC_NT';'PERFECT' do. 0
    case. 'BTFN' do. y<x
    case. 'ONEBIT' do. 1=((#Table)|index){Table
    case. 'TWOBIT' do. 2<:((#Table)|index){Table
    case. 'GSHARE' do. 2<:((#Table)|index xor History){Table
    case. 'TOURNAMENT' do.
        if. 2<:((#Chooser)|index){Chooser do.
            2<:((#GlobalTable)|index xor History){GlobalTable
        else.
            2<:((#LocalTable)|index){LocalTable
        end.
    end.
)
update_direction =: 4 : 0
    index =. x floor_div 4
    if. (<Scheme)e.;:'STATIC_NT BTFN PERFECT' do. 0 return. end.
    if. 'TOURNAMENT'-:Scheme do.
        li =. (#LocalTable)|index
        gi =. (#GlobalTable)|index xor History
        ci =. (#Chooser)|index
        lp =. 2<:li{LocalTable
        gp =. 2<:gi{GlobalTable
        if. lp~:gp do.
            Chooser =: ((ci{Chooser)updated_counter gp=y)ci}Chooser
        end.
        LocalTable =: ((li{LocalTable)updated_counter y)li}LocalTable
        GlobalTable =: ((gi{GlobalTable)updated_counter y)gi}GlobalTable
        History =: (2^2{Parameters)|y+2*History
    else.
        if. 'GSHARE'-:Scheme do. index =. index xor History end.
        index =. (#Table)|index
        counter =. (index{Table)updated_counter y
        if. 'ONEBIT'-:Scheme do. counter =. y end.
        Table =: counter index}Table
        if. 'GSHARE'-:Scheme do. History =: (2^1{Parameters)|y+2*History end.
    end.
    0
)
storage_bits =: 3 : 0
    select. Scheme
    case. 'ONEBIT' do. 0{Parameters
    case. 'TWOBIT' do. 2*0{Parameters
    case. 'GSHARE' do. (2*0{Parameters)+1{Parameters
    case. 'TOURNAMENT' do. (2*+/0 1 3{Parameters)+2{Parameters
    case. do. 0
    end.
)
