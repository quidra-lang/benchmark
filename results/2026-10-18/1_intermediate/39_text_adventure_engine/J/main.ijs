LF =: 10{a.
Upper =: 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
Directions =: ;:'north south east west up down'
Initials =: 'nsewud'
Verbs =: ;:'go look examine take drop put inventory open close unlock lock use light extinguish wait score save restore verbose brief'
Aliases =: 'go walk run';'look l';'examine x inspect read';'take get grab';'drop discard';'put insert place';'inventory inv i';'open';'close shut';'unlock';'lock';'use apply';'light ignite';'extinguish douse snuff';'wait z';'score';'save';'restore load';'verbose';'brief'
Actions =: 0 3 4 5 7 8 9 10 11 12 13 14
NoArguments =: 1 6 14 15 16 17 18 19
ContainerNames =: ;:'open closed locked'
Player =: _2
Nowhere =: _1
number =: 3 : ',''0'' 8!:2 y'
words =: 3 : 0
    parts =. <;._1 ' ',y
    parts#~0<#&>parts
)
lower =: 3 : 'a.{~(a.i.y)+32*y e.Upper'
command_words =: 3 : '(words lower y)-.;:''the a an'''
join =: 4 : 0
    result =. ''
    for_i. i.#y do.
        if. i do. result =. result,x end.
        result =. result,i{::y
    end.
    result
)
emit =: 3 : 'Output =: Output,<y'
fail =: 3 : 0
    Error =: y
    throw.
)
direction =: 3 : 0
    found =. Directions i.<y
    if. (found=6)*.1=#y do. found =. Initials i.{.y end.
    found
)
verb =: 3 : 0
    for_i. i.#Verbs do.
        if. (<y)e.words i{::Aliases do. i return. end.
    end.
    _1
)
is_all =: 3 : '(,<''all'')-:y'
inside =: 3 : 'RoomCount+y'
exit_at =: 3 : '(6*Room)+y'
name =: 3 : 'y{::Names'

build_world =: 3 : 0
    RoomIds =: ItemIds =: 0$a:
    for_line. y do.
        w =. >line
        if. 'ROOM'-:0{::w do. RoomIds =: RoomIds,1{w end.
        if. 'ITEM'-:0{::w do. ItemIds =: ItemIds,1{w end.
    end.
    ItemIds =: (/:s:ItemIds){ItemIds
    RoomCount =: #RoomIds
    ItemCount =: #ItemIds
    RoomNames =: RoomCount#<''
    RoomDark =: RoomCount#0
    Descriptions =: RoomCount#<0$a:
    Names =: ItemCount#<''
    Nouns =: NameWords =: Details =: ItemCount#<0$a:
    Weights =: Points =: Lights =: Capacities =: Fixed =: ItemCount#0
    Keys =: ItemCount#_1
    Places =: ItemCount#Nowhere
    States =: Lit =: Fuel =: ItemCount#0
    Destinations =: ExitKeys =: (6*RoomCount)#_1
    ExitLocked =: (6*RoomCount)#0
    Rules =: 0 5$a:
    Flags =: 0$a:
    Bonus =: Moves =: Darkness =: Ended =: 0
    for_line. y do.
        w =. >line
        select. 0{::w
        case. 'ROOM' do.
            room =. RoomIds i.1{w
            dark =. 'DARK'-:2{::w
            RoomDark =: dark room}RoomDark
            RoomNames =: (<' ' join (2+dark)}.w) room}RoomNames
        case. 'DESC' do.
            room =. RoomIds i.1{w
            Descriptions =: (<(room{::Descriptions),<' ' join 2}.w) room}Descriptions
        case. 'EXIT' do.
            at =. (6*(RoomIds i.1{w))+direction 2{::w
            Destinations =: (RoomIds i.3{w) at}Destinations
            if. 4<#w do.
                ExitKeys =: (ItemIds i.5{w) at}ExitKeys
                ExitLocked =: 1 at}ExitLocked
            end.
        case. 'ITEM' do.
            item =. ItemIds i.1{w
            place =. RoomIds i.2{w
            if. 'PLAYER'-:2{::w do. place =. Player end.
            if. 'NOWHERE'-:2{::w do. place =. Nowhere end.
            Places =: place item}Places
            Weights =: (0".3{::w) item}Weights
            at =. 4
            if. 'TREASURE'-:at{::w do.
                Points =: (0".(at+1){::w) item}Points
                at =. at+2
            end.
            if. 'LIGHT'-:at{::w do.
                Lights =: 1 item}Lights
                Fuel =: (0".(at+1){::w) item}Fuel
                at =. at+2
            end.
            if. 'CONTAINER'-:at{::w do.
                Capacities =: (0".(at+1){::w) item}Capacities
                at =. at+2
                if. 'CLOSED'-:at{::w do.
                    States =: 1 item}States
                    at =. at+1
                end.
                if. 'LOCKED'-:at{::w do.
                    Keys =: (ItemIds i.(at+1){w) item}Keys
                    States =: 2 item}States
                    at =. at+2
                end.
            end.
            if. 'FIXED'-:at{::w do.
                Fixed =: 1 item}Fixed
                at =. at+1
            end.
            Names =: (<' ' join at}.w) item}Names
            NameWords =: (<at}.w) item}NameWords
            Nouns =: (<,item{ItemIds) item}Nouns
        case. 'INSIDE' do.
            Places =: (inside ItemIds i.2{w) (ItemIds i.1{w)}Places
        case. 'ALIAS' do.
            item =. ItemIds i.1{w
            Nouns =: (<~.(item{::Nouns),2{w) item}Nouns
        case. 'DETAIL' do.
            item =. ItemIds i.1{w
            Details =: (<(item{::Details),<' ' join 2}.w) item}Details
        case. 'RULE';'ENTER' do.
            if. 'RULE'-:0{::w do.
                trigger =. 1,(ItemIds i.1{w),ItemIds i.2{w
                at =. 3
            else.
                trigger =. 0,(RoomIds i.1{w),_1
                at =. 2
            end.
            condition =. _1
            flag =. ''
            if. (at{w)e.;:'IF UNLESS' do.
                condition =. 'IF'-:at{::w
                flag =. (at+1){::w
                at =. at+2
            end.
            Rules =: Rules,(<trigger),(<condition),(<flag),(at{w),<(at+1)}.w
        case. 'TROPHY' do. Trophy =: RoomIds i.1{w
        case. 'START' do. Room =: RoomIds i.1{w
        case. 'MAXWEIGHT' do. MaxWeight =: 0".1{::w
        end.
    end.
    Visited =: 1 Room}RoomCount#0
    Vocabulary =: ~.(;Nouns),;NameWords
    It =: _1
    Previous =: ''
    Verbose =: 0
    Saved =: 0$a:
)

snapshot =: 3 : 0
    (<Room),(<Places),(<States),(<Destinations),(<ExitKeys),(<ExitLocked),(<Lit),(<Fuel),(<Flags),(<Bonus),(<Moves),(<Visited),(<Darkness),<Ended
)
restore_state =: 3 : 0
    'Room Places States Destinations ExitKeys ExitLocked Lit Fuel Flags Bonus Moves Visited Darkness Ended' =: y
)
direct =: 3 : 'I.Places=y'
reachable =: 4 : 0
    place =. y{Places
    while. place>:RoomCount do.
        container =. place-RoomCount
        if. 0~:container{States do. 0 return. end.
        place =. container{Places
    end.
    place=x
)
carried =: 3 : 'Player reachable y'
room_item =: 3 : 'Room reachable y'
nearby =: 3 : '(carried"0 i.ItemCount)+.room_item"0 i.ItemCount'
is_lit =: 3 : '(-.Room{RoomDark)+.+./Lit*.nearby '''''
visible =: 3 : '(carried"0 i.ItemCount)+.(is_lit '''')*.room_item"0 i.ItemCount'
total_weight =: 3 : '(y{Weights)+place_weight inside y'
place_weight =: 3 : '+/total_weight"0 direct y'
within =: 4 : 0
    place =. x{Places
    while. place>:RoomCount do.
        if. place=inside y do. 1 return. end.
        place =. (place-RoomCount){Places
    end.
    0
)
stored =: 3 : 0
    place =. y{Places
    while. place>:RoomCount do. place =. (place-RoomCount){Places end.
    place=Trophy
)
treasures =: 3 : 0
    at =. stored"0 i.ItemCount
    mask =. Points>0
    (+/Points*at),(+/mask*.at),+/mask
)
score =: 3 : 'Bonus+0{treasures '''''
display_name =: 3 : 0
    annotations =. 0$a:
    if. y{Capacities do. annotations =. annotations,(y{States){ContainerNames end.
    if. y{Lit do. annotations =. annotations,<'lit' end.
    result =. name y
    if. #annotations do. result =. result,' (',(', ' join annotations),')' end.
    result
)
item_tree =: 4 : 0
    for_item. direct y do.
        emit ((2*x)#' '),display_name item
        if. (item{Capacities)*.0=item{States do. (x+1) item_tree inside item end.
    end.
)
describe =: 3 : 0
    if. -.is_lit '' do. emit 'It is pitch dark.' return. end.
    emit Room{::RoomNames
    if. y do. Output =: Output,Room{::Descriptions end.
    exits =. 0$a:
    for_d. i.6 do.
        at =. exit_at d
        if. _1~:at{Destinations do.
            text =. d{::Directions
            if. at{ExitLocked do. text =. text,' (locked)' end.
            exits =. exits,<text
        end.
    end.
    if. #exits do. emit 'Exits: ',', ' join exits
    else. emit 'Exits: none' end.
    if. #direct Room do.
        emit 'You see:'
        1 item_tree Room
    end.
)
resolve =: 3 : 0
    seen =. visible ''
    if. (,<'it')-:y do.
        if. It=_1 do. fail 'I don''t know what "it" refers to.' end.
        if. -.It{seen do. fail 'You can''t see any such thing.' end.
        It return.
    end.
    for_word. y do.
        if. -.word e.Vocabulary do. fail 'I don''t know the word "',(>word),'".' end.
    end.
    matches =. i.0
    for_item. I.seen do.
        if. (({:y)e.item{::Nouns)*.*./(}:y)e.item{::NameWords do. matches =. matches,item end.
    end.
    if. 0=#matches do. fail 'You can''t see any such thing.' end.
    if. 1<#matches do. fail 'Which do you mean: ',(', ' join matches{Names),'?' end.
    It =: {.matches
    It
)

run_rules =: 3 : 0
    executed =. messages =. 0
    for_rule. Rules do.
        'trigger condition flag effect args' =. rule
        if. -.trigger-:y do. continue. end.
        if. condition~:_1 do.
            if. condition~:(<flag)e.Flags do. continue. end.
        end.
        executed =. executed+1
        select. effect
        case. 'MESSAGE' do. emit ' ' join args [ messages =. 1
        case. 'OPEN' do.
            at =. (6*(RoomIds i.0{args))+direction 1{::args
            Destinations =: (RoomIds i.2{args) at}Destinations
            ExitKeys =: _1 at}ExitKeys
            ExitLocked =: 0 at}ExitLocked
        case. 'REMOVE' do. Places =: Nowhere (ItemIds i.0{args)}Places
        case. 'ADD' do. Places =: (RoomIds i.1{args) (ItemIds i.0{args)}Places
        case. 'SET' do. Flags =: ~.Flags,0{args
        case. 'CLEAR' do. Flags =: Flags-.0{args
        case. 'POINTS' do. Bonus =: Bonus+0".0{::args
        end.
    end.
    executed,messages
)
pass_turn =: 3 : 0
    Moves =: Moves+1
    near =. nearby ''
    for_item. I.Lit do.
        Fuel =: ((item{Fuel)-1) item}Fuel
        if. 0=item{Fuel do.
            Lit =: 0 item}Lit
            if. item{near do. emit 'The ',(name item),' goes out.' end.
        end.
    end.
    lit =. is_lit ''
    if. y*.-.lit do. emit 'It is now pitch dark.'
    elseif. (-.y)*.lit do. describe 1 end.
    if. lit do. Darkness =: 0 else. Darkness =: Darkness+1 end.
    if. Darkness=2 do. emit 'You hear something moving in the dark.' end.
    if. Darkness=3 do. Ended =: 2 end.
    'points count total' =. treasures ''
    if. (Ended=0)*.(total>0)*.count=total do. Ended =: 1 end.
    if. Ended do.
        if. Ended=2 do. emit '*** You have died ***'
        else. emit '*** You have won ***' end.
        emit 'You scored ',(number points+Bonus),' points in ',(number Moves),' moves.'
    end.
)

require_container =: 3 : 0
    if. 0=y{Capacities do. fail 'The ',(name y),' is not a container.' end.
    if. 0~:y{States do. fail 'The ',(name y),' is closed.' end.
)
put_item =: 4 : 0
    if. y within x do. 'The ',(name y),' is inside the ',(name x),'.' return. end.
    if. (x{Places)=inside y do. 'The ',(name x),' is already in the ',(name y),'.' return. end.
    weight =. place_weight inside y
    if. -.x within y do. weight =. weight+total_weight x end.
    if. weight>y{Capacities do. 'The ',(name x),' doesn''t fit in the ',(name y),'.' return. end.
    Places =: (inside y) x}Places
    ''
)
take_items =: 4 : 0
    if. -.is_lit '' do. fail 'It is pitch dark.' end.
    container =. _1
    source =. Room
    if. #y do.
        container =. resolve y
        require_container container
        source =. inside container
    end.
    if. is_all x do.
        candidates =. I.(Places=source)*.-.Fixed
        if. 0=#candidates do.
            if. container=_1 do. fail 'There is nothing here to take.'
            else. fail 'There is nothing in the ',(name container),' to take.' end.
        end.
        taken =. 0
        for_item. candidates do.
            if. (-.carried item)*.MaxWeight<(place_weight Player)+total_weight item do.
                emit (name item),': You can''t carry any more.'
            else.
                Places =: Player item}Places
                emit (name item),': Taken.'
                taken =. 1
            end.
        end.
        taken return.
    end.
    item =. resolve x
    if. (container~:_1)*.source~:item{Places do. fail 'The ',(name item),' is not in the ',(name container),'.' end.
    if. Player=item{Places do. fail 'You already have the ',(name item),'.' end.
    if. item{Fixed do. fail 'The ',(name item),' is fixed in place.' end.
    if. (-.carried item)*.MaxWeight<(place_weight Player)+total_weight item do. fail 'You can''t carry any more.' end.
    Places =: Player item}Places
    emit 'Taken.'
    1
)
drop_items =: 3 : 0
    if. is_all y do.
        candidates =. direct Player
        if. 0=#candidates do. fail 'You are empty-handed.' end.
        for_item. candidates do.
            Places =: Room item}Places
            emit (name item),': Dropped.'
        end.
    else.
        item =. resolve y
        if. -.carried item do. fail 'You aren''t carrying the ',(name item),'.' end.
        Places =: Room item}Places
        emit 'Dropped.'
    end.
    1
)
put_items =: 4 : 0
    item =. _1
    if. -.is_all x do. item =. resolve x end.
    container =. resolve y
    if. item~:_1 do.
        if. -.carried item do. fail 'You aren''t carrying the ',(name item),'.' end.
        if. item=container do. fail 'You can''t put the ',(name item),' inside itself.' end.
    end.
    require_container container
    if. item~:_1 do.
        reason =. item put_item container
        if. #reason do. fail reason end.
        emit 'You put the ',(name item),' in the ',(name container),'.'
        1 return.
    end.
    candidates =. (direct Player)-.container
    if. 0=#candidates do. fail 'You have nothing to put in the ',(name container),'.' end.
    moved =. 0
    for_item. candidates do.
        reason =. item put_item container
        if. 0=#reason do. reason =. 'Done.' [ moved =. 1 end.
        emit (name item),': ',reason
    end.
    moved
)
key_check =: 4 : 0
    if. #y do.
        item =. resolve y
        if. -.carried item do. fail 'You aren''t carrying the ',(name item),'.' end.
        if. item~:x do. fail 'The ',(name item),' doesn''t fit.' end.
    else.
        if. -.carried x do. fail 'You don''t have the right key.' end.
        emit '(with the ',(name x),')'
    end.
)
change_lock =: 4 : 0
    'target phrase' =. y
    locking =. x
    status =. locking{::'not locked';'already locked'
    d =. 6
    if. 1=#target do. d =. direction 0{::target end.
    if. d<6 do.
        at =. exit_at d
        destination =. at{Destinations
        if. destination=_1 do. fail 'There is no exit ',(d{::Directions),'.' end.
        key =. at{ExitKeys
        if. key=_1 do. fail 'The way ',(d{::Directions),' has no lock.' end.
        if. locking=at{ExitLocked do. fail 'The way ',(d{::Directions),' is ',status,'.' end.
        key key_check phrase
        ExitLocked =: locking at}ExitLocked
        opposite =. (6*destination)+d+1-2*2|d
        if. (Room=opposite{Destinations)*.key=opposite{ExitKeys do.
            ExitLocked =: locking opposite}ExitLocked
        end.
    else.
        item =. resolve target
        if. (0=item{Capacities)+._1=item{Keys do. fail 'The ',(name item),' has no lock.' end.
        if. locking=2=item{States do. fail 'The ',(name item),' is ',status,'.' end.
        if. locking*.0=item{States do. fail 'You must close the ',(name item),' first.' end.
        (item{Keys) key_check phrase
        States =: (1+locking) item}States
    end.
    emit locking{::'Unlocked.';'Locked.'
    1
)
examine =: 3 : 0
    if. #y{::Details do. Output =: Output,y{::Details
    else. emit 'You see nothing special about the ',(name y),'.' end.
    if. y{Lights do.
        emit 'It is ',((y{Lit){::'unlit';'lit'),' (fuel ',(number y{Fuel),').'
    end.
    if. y{Capacities do.
        select. y{States
        case. 2 do. emit 'It is locked.'
        case. 1 do. emit 'It is closed.'
        case. 0 do.
            if. #direct inside y do.
                emit 'It contains:'
                1 item_tree inside y
            else. emit 'It is empty.' end.
        end.
    end.
    if. y{Points do. emit 'It is a treasure worth ',(number y{Points),' points.' end.
    emit 'It weighs ',(number total_weight y),'.'
)

perform =: 4 : 0
    'first second d' =. y
    kind =. x
    select. kind
    case. 0 do.
        at =. exit_at d
        destination =. at{Destinations
        if. destination=_1 do. fail 'You can''t go that way.' end.
        if. at{ExitLocked do. fail 'The way ',(d{::Directions),' is locked.' end.
        Room =: destination
        Baseline =: is_lit ''
        describe Verbose+.-.Room{Visited
        Visited =: 1 Room}Visited
        run_rules 0,Room,_1
    case. 1 do. describe 1
    case. 2 do. examine resolve first
    case. 3 do. first take_items second return.
    case. 4 do. drop_items first return.
    case. 5 do. first put_items second return.
    case. 6 do.
        if. 0=#direct Player do. emit 'You are empty-handed.'
        else.
            emit 'You are carrying:'
            1 item_tree Player
            emit 'Total weight: ',(number place_weight Player),'/',number MaxWeight
        end.
    case. 7 do.
        item =. resolve first
        if. 0=item{Capacities do. fail 'You can''t open the ',(name item),'.' end.
        if. 0=item{States do. fail 'The ',(name item),' is already open.' end.
        if. 2=item{States do. fail 'The ',(name item),' is locked.' end.
        States =: 0 item}States
        children =. direct inside item
        if. #children do. emit 'Opening the ',(name item),' reveals ',(', ' join children{Names),'.'
        else. emit 'Opened.' end.
    case. 8 do.
        item =. resolve first
        if. 0=item{Capacities do. fail 'You can''t close the ',(name item),'.' end.
        if. 0~:item{States do. fail 'The ',(name item),' is already closed.' end.
        States =: 1 item}States
        emit 'Closed.'
    case. 9;10 do. (kind=10) change_lock (<first),<second return.
    case. 11 do.
        a =. resolve first
        b =. resolve second
        if. -.carried a do. fail 'You aren''t carrying the ',(name a),'.' end.
        'executed messages' =. run_rules 1,a,b
        if. 0=executed do. fail 'Nothing happens.' end.
        if. -.messages do. emit 'Done.' end.
    case. 12;13 do.
        item =. resolve first
        lighting =. kind=12
        if. -.item{Lights do. fail 'You can''t ',(kind{::Verbs),' the ',(name item),'.' end.
        if. lighting=item{Lit do.
            fail 'The ',(name item),' is ',(lighting{::'not lit';'already lit'),'.'
        end.
        if. lighting*.0=item{Fuel do. fail 'The ',(name item),' has no fuel.' end.
        Lit =: lighting item}Lit
        emit 'The ',(name item),' is now ',(lighting{::'out';'lit'),'.'
    case. 14 do. emit 'Time passes.'
    case. 15 do.
        'points count total' =. treasures ''
        emit 'You have scored ',(number points+Bonus),' points (treasure ',(number points),', bonus ',(number Bonus),') in ',(number Moves),' moves.'
        emit 'Treasures stored: ',(number count),' of ',(number total),'.'
    case. 16 do.
        Saved =: snapshot ''
        emit 'Game saved.'
    case. 17 do.
        if. 0=#Saved do. fail 'There is no saved game.' end.
        restore_state Saved
        emit 'Game restored.'
        describe 1
    case. 18 do.
        Verbose =: 1
        emit 'Verbose mode.'
    case. 19 do.
        Verbose =: 0
        emit 'Brief mode.'
    end.
    1
)
interpret =: 3 : 0
    w =. command_words y
    if. 0=#w do. fail 'I beg your pardon?' end.
    if. 6>direction 0{::w do. w =. (<'go'),w end.
    kind =. verb 0{::w
    if. kind=_1 do. fail 'I don''t know the verb "',(0{::w),'".' end.
    if. Ended*.kind~:17 do. fail 'The game is over.' end.
    first =. }.w
    second =. 0$a:
    d =. 6
    if. (kind=1)*.0<#first do.
        if. -.'at'-:0{::first do. fail 'I don''t understand that.' end.
        kind =. 2
        first =. }.first
    end.
    if. kind e.NoArguments do.
        if. #first do. fail 'I don''t understand that.' end.
    else.
        if. 0=#first do.
            if. kind=0 do. fail 'Which way do you want to go?'
            else. fail 'What do you want to ',(kind{::Verbs),'?' end.
        end.
        if. kind=0 do.
            if. 1=#first do. d =. direction 0{::first end.
            if. d=6 do. fail 'I don''t understand that.' end.
        else.
            prepositions =. 0$a:
            select. kind
            case. 5 do. prepositions =. ;:'in into'
            case. 11 do. prepositions =. ;:'on with'
            case. 9;10 do. prepositions =. ,<'with'
            case. 3 do. prepositions =. ,<'from'
            end.
            positions =. I.first e.prepositions
            if. #positions do.
                at =. {.positions
                if. (at=0)+.at=(#first)-1 do. fail 'I don''t understand that.' end.
                second =. (at+1)}.first
                first =. at{.first
            elseif. kind e.5 11 do. fail 'I don''t understand that.' end.
        end.
    end.
    Baseline =: is_lit ''
    success =. kind perform (<first),(<second),<d
    if. success*.kind e.Actions do. pass_turn Baseline end.
)
process =: 3 : 0
    w =. command_words y
    repeat =. 0
    if. #w do. repeat =. (0{w)e.;:'again g' end.
    if. repeat do.
        if. 1<#w do. fail 'I don''t understand that.' end.
        if. 0=#Previous do. fail 'There is nothing to repeat.' end.
        interpret Previous
    else.
        Previous =: y
        interpret y
    end.
)
write_rows =: 3 : 0
    for_row. y do. ((>row),LF) 1!:2[4 end.
)
main =: 3 : 0
    definitions =. 0$a:
    while. 1 do.
        line =. 1!:1[3
        if. 'BEGIN'-:line do. break. end.
        definitions =. definitions,<words line
    end.
    build_world definitions
    Output =: 0$a:
    describe 1
    write_rows Output
    while. 1 do.
        line =. 1!:1[3
        if. 'QUIT'-:line do. break. end.
        Output =: <'> ',line
        try. process line
        catcht. emit Error end.
        write_rows Output
    end.
    ('Final score: ',(number score ''),' points in ',(number Moves),' moves.',LF) 1!:2[4
)
main ''
2!:55[0
