ScriptPath =: >{:4!:3''
SourceDirectory =: (1+>./_1,I.ScriptPath e.'/\'){.ScriptPath
Digits =: '0123456789'
div =: 4 : '_1 x:<.(x:x)%x:y'
num =: 3 : '10#.Digits i.y'
number =: 3 : 0
    prefix =. ''
    if. y<0 do. prefix =. '-'
        y =. -y end.
    text =. ''
    while. y>0 do.
        text =. ((10|y){Digits),text
        y =. y div 10
    end.
    if. #text do. prefix,text else. '0' end.
)
split =: 4 : 0
    parts =. 0$a:
    while. 1 do.
        position =. y i.x
        parts =. parts,<position{.y
        if. position=#y do. parts return. end.
        y =. (position+1)}.y
    end.
)
words =: 3 : 0
    parts =. ' ' split y
    parts#~0<#&>parts
)
join =: 4 : 0
    text =. ''
    for_index. i.#y do.
        if. index do. text =. text,x end.
        text =. text,index{::y
    end.
    text
)
format =: 4 : 0
    parts =. '|' split x
    text =. 0{::parts
    for_index. i.#y do.
        value =. index{::y
        if. 2~:3!:0 value do. value =. number value end.
        text =. text,value,(index+1){::parts
    end.
    text
)
decimal_one =: 3 : 0
    'numerator denominator' =. y
    if. denominator=0 do. '-' return. end.
    rounded =. ((20*numerator)+denominator)div 2*denominator
    (number rounded div 10),'.',(10|rounded){Digits
)
read_lines =: 3 : '<;._2 (1!:1 <''input/'',y)'
load SourceDirectory,'minstd.ijs'
load SourceDirectory,'combat.ijs'
load SourceDirectory,'entities.ijs'
load SourceDirectory,'fov.ijs'
load SourceDirectory,'dungeon_gen.ijs'
read_config =: 3 : 0
    ConfigKeys =: ConfigValues =: 0$a:
    for_line. read_lines 'config.txt' do.
        fields =. words >line
        ConfigKeys =: ConfigKeys,{.fields
        ConfigValues =: ConfigValues,<}.fields
    end.
    'GenerationState GameState' =: num&> config 'seed'
    'MapWidth MapHeight' =: num&> config 'map'
    'MinimumSize MaximumSplit' =: num&> config 'bsp'
    'RoomMinimum RoomMaximum' =: num&> config 'room'
    LevelCount =: num 0{::config 'levels'
    'MonsterBase MonsterStep' =: num&> config 'monsters'
    'ItemBase ItemStep' =: num&> config 'items'
    'SleepChance WakeChance' =: num&> config 'sleep'
    Radius =: num 0{::config 'fov'
    'InitialHp Regeneration' =: num&> config 'player'
    HitDie =: parse_dice 0{::config 'hitdie'
    'InitialFood MaximumFood HungryThreshold WeakThreshold' =: num&> config 'food'
    PackLimit =: num 0{::config 'pack'
    StartNames =: config 'start'
    XpThresholds =: num&> config 'xp'
    Checkpoints =: num&> config 'checkpoints'
    i.0
)
config =: 3 : '(ConfigKeys i.<y){::ConfigValues'
read_commands =: 3 : 0
    Commands =: 0$a:
    for_line. read_lines 'commands.txt' do.
        fields =. words >line
        name =. 0{::fields
        argument =. ''
        count =. 1
        if. name-:'wait' do.
            if. (#fields)=2 do. count =. num 1{::fields end.
        else.
            if. (#fields)>1 do. argument =. 1{::fields end.
            if. (#fields)=3 do. count =. num 2{::fields end.
        end.
        for_repeat. i.count do. Commands =: Commands,<(<name),<argument end.
    end.
    i.0
)
save_level =: 3 : 0
    index =. Depth-1
    TerrainLevels =: (<Terrain)index}TerrainLevels
    MemoryLevels =: (<Memory)index}MemoryLevels
    RoomLevels =: (<Rooms)index}RoomLevels
    MonsterLevels =: (<Monsters)index}MonsterLevels
    FloorLevels =: (<Floor)index}FloorLevels
    i.0
)
load_level =: 3 : 0
    index =. Depth-1
    Terrain =: index{::TerrainLevels
    Memory =: index{::MemoryLevels
    Rooms =: index{::RoomLevels
    Monsters =: index{::MonsterLevels
    Floor =: index{::FloorLevels
    i.0
)
build_levels =: 3 : 0
    TerrainLevels =: MemoryLevels =: RoomLevels =: MonsterLevels =: FloorLevels =: ArrivalLevels =: LevelCount$a:
    Created =: Placed =: LevelKills =: LevelPicked =: LevelCount$0
    ItemData =: 0 5$0
    RngMode =: 0
    for_depth. 1+i.LevelCount do.
        Depth =: depth
        generate_terrain ''
        Floor =: 0$0
        Monsters =: 0 9$0
        if. depth<LevelCount do. Terrain =: '>' (cell_index Target)}Terrain
        else. Floor =: Floor,new_item AmuletType,Target,0 0 end.
        candidates =. I.((0{"1 MonsterValues)<:depth)*.(1{"1 MonsterValues)>:depth
        weights =. 2{"1 candidates{MonsterValues
        count =. MonsterBase+MonsterStep*depth-1
        for_number. i.count do.
            kind =. (weighted_select weights){candidates
            while. 1 do.
                'room column row' =. draw_room_cell ''
                point =. column,row
                if. (room~:ArrivalRoom)*.('.'=(cell_index point){Terrain)*._1=monster_at point do. break. end.
            end.
            hp =. roll_dice 3 4{kind{MonsterValues
            asleep =. (100|draw '')<SleepChance
            Monsters =: Monsters,kind,column,row,hp,hp,asleep,0 0 1
        end.
        Created =: count (depth-1)}Created
        candidates =. I.((0{"1 ItemValues)<:depth)*.(1{"1 ItemValues)>:depth
        weights =. 2{"1 candidates{ItemValues
        count =. ItemBase+ItemStep*depth-1
        for_number. i.count do.
            kind =. (weighted_select weights){candidates
            while. 1 do.
                'room column row' =. draw_room_cell ''
                point =. column,row
                if. ('.'=(cell_index point){Terrain)*._1=item_at point do. break. end.
            end.
            amount =. 0
            if. 'gold'-:kind{::ItemCategories do. amount =. roll_dice 3 4{kind{ItemValues end.
            Floor =: Floor,new_item kind,column,row,amount,0
        end.
        Placed =: (#Floor)(depth-1)}Placed
        ArrivalLevels =: (<Arrival)(depth-1)}ArrivalLevels
        save_level ''
    end.
    RngMode =: 1
    i.0
)
initialize_player =: 3 : 0
    Depth =: 1
    load_level ''
    Position =: 0{::ArrivalLevels
    Hp =: MaximumHp =: InitialHp
    Food =: InitialFood
    PlayerLevel =: 1
    Xp =: Gold =: Poison =: 0
    Pack =: 0$0
    Weapon =: Armor =: _1
    for_name. StartNames do.
        kind =. ItemNames i.name
        identifier =. new_item kind,Position,0 0
        Pack =: Pack,identifier
        if. ('weapon'-:kind{::ItemCategories)*.Weapon=_1 do. Weapon =: identifier end.
        if. ('armor'-:kind{::ItemCategories)*.Armor=_1 do. Armor =: identifier end.
    end.
    Turn =: 1
    Succeeded =: Failed =: Unused =: Moves =: PoisonDamage =: StarvationDamage =: 0
    Usage =: 6$0
    Kills =: (#MonsterNames)$0
    PlayerAttacks =: MonsterAttacks =: 4$0
    Messages =: Maps =: 0$a:
    Result =: Cause =: ''
    i.0
)
say =: 3 : 0
    stamp =. number Turn
    Messages =: Messages,<((0>.4-#stamp)$'0'),stamp,' ',y
    i.0
)
hunger =: 3 : 0
    if. Food>HungryThreshold do. 'normal'
    elseif. Food>WeakThreshold do. 'hungry'
    elseif. Food>0 do. 'weak'
    else. 'starving' end.
)
player_defense =: 3 : 0
    if. Armor=_1 do. 10
    else. row =. Armor{ItemData
        10+(6{(0{row){ItemValues)+4{row end.
)
die =: 3 : 0
    say 'You die.'
    Result =: 'died'
    Cause =: y
    i.0
)
update_view =: 3 : 0
    Visible =: field_of_view ''
    for_index. I.Visible do.
        point =. (MapWidth|index),index div MapWidth
        identifier =. item_at point
        symbol =. index{Terrain
        if. identifier>:0 do. symbol =. item_symbol identifier end.
        Memory =: symbol index}Memory
    end.
    for_index. i.#Monsters do.
        row =. index{Monsters
        if. -.8{row do. continue. end.
        seen =. (cell_index 1 2{row){Visible
        if. seen*.-.7{row do. say 'You see the ',((0{row){::MonsterNames),'.' end.
        seen set_monster index,7
    end.
    i.0
)
gain_xp =: 3 : 0
    Xp =: Xp+y
    while. PlayerLevel<:#XpThresholds do.
        if. Xp<(PlayerLevel-1){XpThresholds do. break. end.
        PlayerLevel =: PlayerLevel+1
        increase =. roll_dice HitDie
        MaximumHp =: MaximumHp+increase
        Hp =: Hp+increase
        say 'Welcome to level ',(number PlayerLevel),'.'
    end.
    i.0
)
player_attack =: 3 : 0
    0 set_monster y,5
    row =. y{Monsters
    kind =. 0{row
    values =. kind{MonsterValues
    name =. kind{::MonsterNames
    tohit =. PlayerLevel
    bonus =. 0
    dice =. 1 2
    if. Weapon>:0 do.
        weapon =. Weapon{ItemData
        weaponvalues =. (0{weapon){ItemValues
        bonus =. 4{weapon
        tohit =. tohit+bonus+5{weaponvalues
        dice =. 3 4{weaponvalues
    end.
    if. (<hunger '')e.'weak';'starving' do. tohit =. tohit-2 end.
    attack =. resolve_attack tohit,(6{values),dice,bonus
    PlayerAttacks =: PlayerAttacks record_attack attack
    'outcome damage' =. attack
    if. outcome=0 do. say 'You miss the ',name,'.' return. end.
    adjective =. ' for '
    if. outcome=2 do. adjective =. ' hard for ' end.
    say 'You hit the ',name,adjective,(number damage),'.'
    remaining =. (3{row)-damage
    remaining set_monster y,3
    if. remaining<:0 do.
        say 'You kill the ',name,'.'
        0 set_monster y,8
        LevelKills =: (1+(Depth-1){LevelKills)(Depth-1)}LevelKills
        Kills =: (1+kind{Kills)kind}Kills
        gain_xp 10{values
    end.
    i.0
)
monster_attack =: 3 : 0
    kind =. (<y,0){Monsters
    values =. kind{MonsterValues
    name =. kind{::MonsterNames
    attack =. resolve_attack (5{values),(player_defense ''),(7 8{values),0
    MonsterAttacks =: MonsterAttacks record_attack attack
    'outcome damage' =. attack
    if. outcome=0 do. say 'The ',name,' misses you.' return. end.
    adjective =. ' hits you for '
    if. outcome=2 do. adjective =. ' hits you hard for ' end.
    say 'The ',name,adjective,(number damage),'.'
    Hp =: Hp-damage
    if. Hp<:0 do. die 'killed_by ',name
    elseif. 'P'e.kind{::MonsterTraits do.
        Poison =: Poison+5
        say 'You are poisoned.'
    end.
    i.0
)
move_player =: 3 : 0
    target =. Position+y
    if. -.passable target do.
        say 'You bump into a wall.'
        0 return.
    end.
    if. -.Position can_move y do.
        say 'You cannot move diagonally through a door.'
        0 return.
    end.
    monster =. monster_at target
    if. monster>:0 do. player_attack monster
        1 return. end.
    Position =: target
    Moves =: Moves+1
    identifier =. item_at Position
    if. identifier>:0 do. say 'You see ',(item_reference identifier),' here.'
    elseif. '>'=(cell_index Position){Terrain do. say 'There is a staircase down here.' end.
    1
)
pickup =: 3 : 0
    identifier =. item_at Position
    if. identifier=_1 do.
        say 'There is nothing here.'
        0 return.
    end.
    category =. item_category identifier
    if. category-:'gold' do.
        Gold =: Gold+(<identifier,3){ItemData
        say 'You pick up ',(item_name identifier),'.'
    elseif. category-:'amulet' do.
        say 'You pick up the amulet.'
        say 'You win!'
        Result =: 'won'
        Cause =: 'amulet'
    elseif. (#Pack)>:PackLimit do.
        say 'Your pack is full.'
        0 return.
    else.
        Pack =: Pack,identifier
        say 'You pick up the ',(item_name identifier),' (',(number #Pack),').'
    end.
    Floor =: Floor#~Floor~:identifier
    LevelPicked =: (1+(Depth-1){LevelPicked)(Depth-1)}LevelPicked
    Usage =: (1+0{Usage)0}Usage
    1
)
use_item =: 4 : 0
    if. y>#Pack do.
        say 'You do not have that item.'
        0 return.
    end.
    identifier =. (y-1){Pack
    category =. item_category identifier
    names =. 'quaff';'read';'wield';'wear';'eat'
    categories =. 'potion';'scroll';'weapon';'armor';'food'
    if. -.category-:(names i.<x){::categories do.
        say 'You cannot ',x,' that.'
        0 return.
    end.
    if. x-:'wield' do.
        if. Weapon=identifier do.
            say 'You are already wielding that.'
            0 return.
        end.
        Weapon =: identifier
        Usage =: (1+4{Usage)4}Usage
        say 'You are now wielding the ',(item_name identifier),'.'
        1 return.
    elseif. x-:'wear' do.
        if. Armor=identifier do.
            say 'You are already wearing that.'
            0 return.
        end.
        Armor =: identifier
        Usage =: (1+5{Usage)5}Usage
        say 'You are now wearing the ',(item_name identifier),'.'
        1 return.
    end.
    Pack =: ((y-1){.Pack),y}.Pack
    kind =. (<identifier,0){ItemData
    values =. kind{ItemValues
    effect =. kind{::ItemEffects
    if. x-:'eat' do.
        Usage =: (1+3{Usage)3}Usage
        Food =: MaximumFood<.Food+8{values
        say 'You eat the ',(item_name identifier),'.'
        1 return.
    elseif. x-:'quaff' do.
        Usage =: (1+1{Usage)1}Usage
        say 'You quaff the ',(item_name identifier),'.'
        if. effect-:'heal' do.
            Hp =: Hp+roll_dice 3 4{values
            if. Hp>MaximumHp do. MaximumHp =: MaximumHp+1
                Hp =: MaximumHp end.
            Poison =: 0
            say 'You feel better.'
        elseif. effect-:'poison' do.
            Poison =: Poison+7{values
            say 'You feel very sick.'
        else.
            say 'You feel more experienced.'
            if. PlayerLevel<:#XpThresholds do. gain_xp ((PlayerLevel-1){XpThresholds)-Xp end.
        end.
        1 return.
    end.
    Usage =: (1+2{Usage)2}Usage
    say 'You read the ',(item_name identifier),'.'
    if. effect-:'mapping' do.
        cells =. I.(Terrain~:' ')*.Memory=' '
        Memory =: (cells{Terrain)cells}Memory
        say 'A map forms in your mind.'
    elseif. effect-:'teleport' do.
        while. 1 do.
            'room column row' =. draw_room_cell ''
            target =. column,row
            if. (-.target-:Position)*._1=monster_at target do. Position =: target break. end.
        end.
        say 'You are teleported.'
    elseif. effect-:'enchant_weapon' do.
        if. Weapon>:0 do.
            say 'Your ',(item_name Weapon),' glows blue.'
            (1+(<Weapon,4){ItemData)set_item Weapon,4
        else. say 'Your hands twitch.' end.
    elseif. effect-:'enchant_armor' do.
        if. Armor>:0 do.
            say 'Your ',(item_name Armor),' glows silver.'
            (1+(<Armor,4){ItemData)set_item Armor,4
        else. say 'Your skin tingles.' end.
    end.
    1
)
execute_command =: 3 : 0
    'name argument' =. y
    if. name-:'move' do. move_player (DirectionNames i.<argument){Directions
    elseif. name-:'wait' do. 1
    elseif. name-:'pickup' do. pickup ''
    elseif. name-:'descend' do.
        if. '>'~:(cell_index Position){Terrain do.
            say 'There are no stairs here.'
            0 return.
        end.
        save_level ''
        Depth =: Depth+1
        load_level ''
        Position =: (Depth-1){::ArrivalLevels
        say 'You descend to depth ',(number Depth),'.'
        1
    else. name use_item num argument end.
)
can_attack =: 3 : 0
    point =. 1 2{y{Monsters
    direction =. Position-point
    if. 1~:>./|direction do. 0 return. end.
    point can_move direction
)
wander_monster =: 3 : 0
    direction =. (8|draw ''){Directions
    point =. 1 2{y{Monsters
    if. -.point can_move direction do. i.0 return. end.
    target =. point+direction
    if. target-:Position do. monster_attack y
    elseif. _1=monster_at target do.
        (0{target)set_monster y,1
        (1{target)set_monster y,2
    end.
    i.0
)
chase_monster =: 3 : 0
    if. can_attack y do. monster_attack y return. end.
    point =. 1 2{y{Monsters
    here =. (cell_index point){Distance
    found =. 0
    bestdistance =. 0
    best =. point
    for_direction. Directions do.
        if. -.point can_move direction do. continue. end.
        target =. point+direction
        value =. (cell_index target){Distance
        if. value<0 do. continue. end.
        if. (here>:0)*.value>:here do. continue. end.
        if. (target-:Position)+.(monster_at target)>:0 do. continue. end.
        if. (-.found)+.value<bestdistance do.
            found =. 1
            best =. target
            bestdistance =. value
        end.
    end.
    if. found do.
        (0{best)set_monster y,1
        (1{best)set_monster y,2
    end.
    i.0
)
monsters_act =: 3 : 0
    Distance =: distance_map ''
    for_index. i.#Monsters do.
        row =. index{Monsters
        if. -.8{row do. continue. end.
        kind =. 0{row
        traits =. kind{::MonsterTraits
        ((6{row)+(<kind,9){MonsterValues)set_monster index,6
        while. ((<index,6){Monsters)>:2 do.
            (((<index,6){Monsters)-2)set_monster index,6
            row =. index{Monsters
            sees =. (cell_index 1 2{row){Visible
            if. 5{row do.
                if. sees do.
                    if. (100|draw '')<WakeChance do.
                        0 set_monster index,5
                        say 'The ',(kind{::MonsterNames),' wakes up.'
                    end.
                end.
            elseif. 'S'e.traits do.
                if. can_attack index do. monster_attack index end.
            elseif. 'E'e.traits do.
                if. 0=2|draw '' do. wander_monster index
                elseif. sees do. chase_monster index
                else. wander_monster index end.
            elseif. sees do. chase_monster index
            else. wander_monster index end.
            if. #Result do. i.0 return. end.
        end.
    end.
    i.0
)
end_turn =: 3 : 0
    for_index. i.#Monsters do.
        row =. index{Monsters
        if. -.8{row do. continue. end.
        kind =. 0{row
        if. ('R'e.kind{::MonsterTraits)*.(3{row)<4{row do.
            (1+3{row)set_monster index,3
        end.
    end.
    if. Poison>0 do.
        Hp =: Hp-1
        PoisonDamage =: PoisonDamage+1
        if. Hp<:0 do. die 'poison' return. end.
        Poison =: Poison-1
        if. Poison=0 do. say 'You feel less sick.' end.
    end.
    if. Food=0 do.
        Hp =: Hp-1
        StarvationDamage =: StarvationDamage+1
        if. Hp<:0 do. die 'starvation' return. end.
    else.
        before =. hunger ''
        Food =: Food-1
        after =. hunger ''
        if. -.before-:after do.
            if. after-:'hungry' do. say 'You are getting hungry.'
            elseif. after-:'weak' do. say 'You feel weak from hunger.'
            else. say 'You are starving.' end.
        end.
    end.
    if. (0=Regeneration|Turn)*.(Poison=0)*.(Food>0)*.Hp<MaximumHp do. Hp =: Hp+1 end.
    i.0
)
exploration =: 4 : 0
    nonrock =. x~:' '
    (+/nonrock*.y~:' '),+/nonrock
)
map_rows =: 4 : 0
    'terrain memory monsters floor' =. y
    cells =. memory
    if. x do.
        for_index. I.Visible do.
            point =. (MapWidth|index),index div MapWidth
            if. point-:Position do. symbol =. '@'
            else.
                monster =. monster_at point
                identifier =. item_at point
                if. monster>:0 do. symbol =. ((<monster,0){Monsters){MonsterSymbols
                elseif. identifier>:0 do. symbol =. item_symbol identifier
                else. symbol =. index{terrain end.
            end.
            cells =. symbol index}cells
        end.
    end.
    border =. '+',(MapWidth$'-'),'+'
    lines =. <border
    for_row. i.MapHeight do. lines =. lines,<'|',(MapWidth{.(row*MapWidth)}.cells),'|' end.
    lines,<border
)
current_map =: 3 : '1 map_rows (<Terrain),(<Memory),(<Monsters),<Floor'
status_line =: 3 : 0
    'STATUS hp |/| level | xp | defense | gold | food | | poison |' format (<Hp),(<MaximumHp),(<PlayerLevel),(<Xp),(<player_defense ''),(<Gold),(<Food),(<hunger ''),<Poison
)
attack_line =: 4 : 0
    'count hits criticals damage' =. y
    '| | hits | criticals | damage | accuracy |' format (<x),(<count),(<hits),(<criticals),(<damage),<decimal_one (100*hits),count
)
stats_lines =: 3 : 0
    lines =. <'result ',Result
    lines =. lines,<'cause ',Cause
    lines =. lines,<'turns ',number Succeeded
    lines =. lines,<'depth ',number Depth
    lines =. lines,<'level ',number PlayerLevel
    lines =. lines,<'xp ',number Xp
    lines =. lines,<'hp |/|' format (<Hp),<MaximumHp
    lines =. lines,<'defense ',number player_defense ''
    lines =. lines,<'gold ',number Gold
    lines =. lines,<'food | |' format (<Food),<hunger ''
    lines =. lines,<'poison ',number Poison
    weapon =. armor =. '-'
    if. Weapon>:0 do. weapon =. item_name Weapon end.
    if. Armor>:0 do. armor =. item_name Armor end.
    lines =. lines,(<'weapon ',weapon),<'armor ',armor
    lines =. lines,<'commands | executed | failed | unused |' format (<#Commands),(<Succeeded),(<Failed),<Unused
    lines =. lines,<'moves ',number Moves
    lines =. lines,(<'player_attacks' attack_line PlayerAttacks),<'monster_attacks' attack_line MonsterAttacks
    lines =. lines,<'poison_damage | starvation_damage |' format (<PoisonDamage),<StarvationDamage
    lines =. lines,<'picked | quaffed | read | eaten | wielded | worn |' format <"0 Usage
    lines =. lines,<'kills ',number +/Kills
    for_kind. I.Kills>0 do. lines =. lines,<'KILL | |' format (kind{MonsterNames),<kind{Kills end.
    for_index. i.LevelCount do.
        'explored total' =. (index{::TerrainLevels)exploration index{::MemoryLevels
        lines =. lines,<'LEVEL | rooms | explored |/| | monsters |/| items |/|' format (<index+1),(<#index{::RoomLevels),(<explored),(<total),(<decimal_one (100*explored),total),(<index{LevelKills),(<index{Created),(<index{LevelPicked),<index{Placed
    end.
    for_index. i.#Pack do.
        identifier =. index{Pack
        tag =. ''
        if. identifier=Weapon do. tag =. ' (wielded)'
        elseif. identifier=Armor do. tag =. ' (worn)' end.
        lines =. lines,<'INVENTORY | ||' format (<index+1),(<item_name identifier),<tag
    end.
    lines
)
write_lines =: 4 : 0
    text =. ''
    if. #y do. text =. (LF join y),LF end.
    text 1!:2 <'output/',x
    i.0
)
main =: 3 : 0
    read_config ''
    read_monster_types ''
    read_item_types ''
    read_commands ''
    build_levels ''
    initialize_player ''
    update_view ''
    for_command. Commands do.
        if. #Result do. Unused =: Unused+1 continue. end.
        if. -.execute_command >command do. Failed =: Failed+1 continue. end.
        Succeeded =: Succeeded+1
        if. #Result do. continue. end.
        update_view ''
        monsters_act ''
        if. #Result do. continue. end.
        end_turn ''
        if. #Result do. continue. end.
        if. Turn e.Checkpoints do.
            Maps =: Maps,<'CHECKPOINT turn | depth |' format (<Turn),<Depth
            Maps =: Maps,(current_map ''),<status_line ''
        end.
        Turn =: Turn+1
    end.
    if. 0=#Result do. Result =: 'alive'
        Cause =: 'commands_exhausted' end.
    save_level ''
    Maps =: Maps,<'FINAL turn | depth |' format (<Succeeded),<Depth
    for_index. i.Depth do.
        terrain =. index{::TerrainLevels
        memory =. index{::MemoryLevels
        'explored total' =. terrain exploration memory
        Maps =: Maps,<'LEVEL | explored |/|' format (<index+1),(<explored),<total
        rows =. (index=Depth-1)map_rows (<terrain),(<memory),(index{MonsterLevels),index{FloorLevels
        Maps =: Maps,rows
    end.
    Maps =: Maps,<status_line ''
    1!:5 ::0: <'output'
    'messages.txt' write_lines Messages
    'maps.txt' write_lines Maps
    'stats.txt' write_lines stats_lines ''
    i.0
)
main ''
