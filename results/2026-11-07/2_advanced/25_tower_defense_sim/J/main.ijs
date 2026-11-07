ScriptPath =: >{:4!:3''
SourceDirectory =: (1+>./_1,I.ScriptPath e.'/\'){.ScriptPath
Digits =: '0123456789'
div =: 4 : '_1 x:<.(x:x)%x:y'
num =: 3 : '10#.Digits i.y'
number =: 3 : 0
    if. y=0 do. '0' return. end.
    text =. ''
    while. y>0 do. text =. ((10|y){Digits),text
        y =. y div 10 end.
    text
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
join =: 4 : 0
    text =. ''
    for_index. i.#y do.
        if. index do. text =. text,x end.
        value =. index{::y
        if. 2~:3!:0 value do. value =. number value end.
        text =. text,value
    end.
    text
)
format =: 4 : 0
    parts =. '|'split x
    text =. 0{::parts
    for_index. i.#y do.
        value =. index{::y
        if. 2~:3!:0 value do. value =. number value end.
        text =. text,value,(index+1){::parts
    end.
    text
)
read_lines =: 3 : '<;._2 (1!:1 <''input/'',y)'
write_lines =: 4 : 0
    text =. ''
    for_line. y do. text =. text,(>line),LF end.
    text 1!:2 <'output/',x
)
load SourceDirectory,'grid_map.ijs'
load SourceDirectory,'pathing.ijs'
load SourceDirectory,'combat.ijs'
load SourceDirectory,'enemies.ijs'
load SourceDirectory,'towers.ijs'
add_field =: 4 : 0
    'index amount' =. x
    (<amount+index{::y)index}y
)
one_decimal =: 4 : 0
    if. y=0 do. '-' return. end.
    rounded =. ((20*x)+y)div 2*y
    (number rounded div 10),'.',number 10|rounded
)
digit =: 3 : 0
    if. y=0 do. '.' elseif. y<10 do. y{Digits else. '*' end.
)
ruled =: 3 : 0
    lines =. <'  ',Digits{~10|i.Width
    for_row. i.Height do. lines =. lines,<((10|row){Digits),' ',row{y end.
    lines
)
record =: 3 : 0
    Events =: Events,<(number Tick),' ',y
    i.0
)
read_parameters =: 3 : 0
    fields =. 0$a:
    for_line. read_lines 'params.txt' do. fields =. fields,<' 'split >line end.
    InitialGold =: num 1{::0{::fields
    InitialLives =: num 1{::1{::fields
    'InterestRate InterestCap' =: num&>}.2{::fields
    SellRate =: num 1{::3{::fields
    'ScheduleStart ScheduleInterval' =: num&>}.4{::fields
    EarlyRate =: num 1{::5{::fields
    SnapshotTicks =: num&>}.6{::fields
    Actions =: 0$a:
    for_line. read_lines 'actions.txt' do.
        row =. ' 'split >line
        Actions =: Actions,<(<num 0{::row),(1{row),<2}.row
    end.
    i.0
)
standing_towers =: 3 : 0
    indices =. 0$0
    for_index. i.#Towers do. if. tower_standing index{::Towers do. indices =. indices,index end. end.
    indices
)
tower_cells =: 3 : 0
    cells =. (Width*Height)$0
    for_index. standing_towers'' do. cells =. 1 (grid_index 2{::index{::Towers)}cells end.
    cells
)
tower_at =: 3 : 0
    for_index. standing_towers'' do. if. y-:2{::index{::Towers do. index return. end. end.
    _1
)
standing_tower =: 3 : 0
    index =. (num y)-1
    if. (index<0)+.index>:#Towers do. _1 return. end.
    if. tower_standing index{::Towers do. index else. _1 end.
)
living_enemies =: 3 : 'I.10{"1 Enemies'
ground_enemies =: 3 : 0
    indices =. 0$0
    for_index. living_enemies'' do.
        if. -.enemy_flying index{Enemies do. indices =. indices,index end.
    end.
    indices
)
build_refusal =: 3 : 0
    'name cell' =. y
    kind =. TowerNames i.<name
    if. kind=#TowerNames do. 'type' return. end.
    if. -.grid_inside cell do. 'bounds' return. end.
    if. -.grid_buildable cell do. 'terrain' return. end.
    if. (tower_at cell)>:0 do. 'tower' return. end.
    cost =. 0{0{3{::kind{::TowerTypes
    if. Gold<cost do. 'gold' return. end.
    walkers =. ground_enemies''
    for_index. walkers do.
        enemy =. index{Enemies
        if. (cell-:11 12{enemy)+.cell-:13 14{enemy do. 'enemy' return. end.
    end.
    occupied =. 1 (grid_index cell)}tower_cells''
    trial =. distance_field occupied
    for_spawn. Spawns do. if. (trial field_at spawn)<0 do. 'blocked' return. end. end.
    for_index. walkers do. if. (trial field_at 13 14{index{Enemies)<0 do. 'blocked' return. end. end.
    ''
)
update_field =: 3 : 0
    before =. Field
    Field =: distance_field tower_cells''
    for_index. i.#Spawns do.
        cell =. index{Spawns
        old =. before field_at cell
        new =. Field field_at cell
        if. old~:new do. record 'REPATH | | |'format (index+1);old;new end.
    end.
    i.0
)
perform_action =: 3 : 0
    'tick command arguments' =. y
    if. command-:'BUILD' do.
        'name x_text y_text' =. arguments
        cell =. (num x_text),num y_text
        reason =. build_refusal (<name),<cell
        if. #reason do. record 'BUILD_REFUSED | | | |'format name;x_text;y_text;reason
            0 return. end.
        kind =. TowerNames i.<name
        cost =. 0{0{3{::kind{::TowerTypes
        Towers =: Towers,<new_tower (<1+#Towers),(<kind),(<cell),<Tick
        Gold =: Gold-cost
        Spent =: Spent+cost
        record 'BUILD T| | | | cost | gold |'format (#Towers);name;(0{cell);(1{cell);cost;Gold
        update_field''
        1 return.
    end.
    if. command-:'CALL' do.
        if. Active>:0 do. record 'CALL_REFUSED active'
            0 return. end.
        bonus =. (NextStart-Tick)*EarlyRate
        Gold =: Gold+bonus
        Income =: (bonus+3{Income)3}Income
        NextStart =: Tick
        record 'CALL | bonus | gold |'format (1+#Records);bonus;Gold
        1 return.
    end.
    text =. 0{::arguments
    index =. standing_tower text
    reason =. ''
    if. index<0 do. reason =. 'notower'
    else.
        tower =. index{::Towers
        if. command-:'UPGRADE' do.
            level =. 3{::tower
            levels =. 3{::(1{::tower){::TowerTypes
            if. level=#levels do. reason =. 'maxlevel'
            else.
                cost =. 0{level{levels
                if. Gold<cost do. reason =. 'gold'
                else.
                    Gold =: Gold-cost
                    Spent =: Spent+cost
                    tower =. (3,1)add_field tower
                    tower =. (6,cost)add_field tower
                    Towers =: (<tower)index}Towers
                    record 'UPGRADE T| level | cost | gold |'format text;(level+1);cost;Gold
                    1 return.
                end.
            end.
        elseif. command-:'SELL' do.
            rate =. SellRate
            if. Tick=7{::tower do. rate =. 100 end.
            refund =. ((6{::tower)*rate)div 100
            tower =. (<Tick)8}tower
            Towers =: (<tower)index}Towers
            Gold =: Gold+refund
            Income =: (refund+4{Income)4}Income
            record 'SELL T| refund | gold |'format text;refund;Gold
            update_field''
            1 return.
        else.
            mode =. 1{::arguments
            if. -.(<mode)e.TargetModes do. reason =. 'mode'
            else.
                tower =. (<mode)4}tower
                Towers =: (<tower)index}Towers
                record 'TARGET T| |'format text;mode
                1 return.
            end.
        end.
    end.
    record '|_REFUSED T| |'format command;text;reason
    0
)
new_wave_record =: 3 : 0
    groups =. 1{::y
    (<1+#Records),(<Tick),(<0),(<''),(<((#groups)$0)),(<0),(<0),(<0),(<0),(<0),(<0),(<0),(<0),(<0),(<0),<(#Towers)$0
)
add_enemy =: 3 : 0
    Enemies =: Enemies,y
    wave =. Active{::Records
    wave =. 5 1 add_field wave
    Records =: (<wave)Active}Records
    kind =. 1{y
    EnemyTypes =: (<11 1 add_field kind{::EnemyTypes)kind}EnemyTypes
    i.0
)
spawn_enemies =: 3 : 0
    if. Tick=NextStart do.
        plan =. (#Records){::Waves
        Records =: Records,<new_wave_record plan
        Active =: (#Records)-1
        NextStart =: 0
        record 'WAVE_START | enemies |'format (#Records);wave_enemy_count plan
    end.
    if. Active<0 do. i.0 return. end.
    plan =. Active{::Waves
    groups =. 1{::plan
    for_index. i.#groups do.
        wave =. Active{::Records
        group =. index{groups
        released =. index{4{::wave
        if. released=2{group do. continue. end.
        if. Tick~:group group_tick (1{::wave),released do. continue. end.
        releases =. (released+1)index}4{::wave
        wave =. (<releases)4}wave
        Records =: (<wave)Active}Records
        kind =. 0{group
        spawn =. ((1{group)-1){Spawns
        enemy =. new_enemy (1+#Enemies),kind,5{group
        if. enemy_flying enemy do. enemy =. (cell_center spawn)16 17}enemy
        else. enemy =. spawn 11 12}enemy
            enemy =. (Field next_cell spawn)13 14}enemy end.
        add_enemy enemy
        record 'SPAWN E| | | hp |'format (0{enemy);(0{::kind{::EnemyTypes);(1{group);4{enemy
    end.
    wave =. Active{::Records
    wave =. (<(6{::wave)>.#living_enemies'')6}wave
    Records =: (<wave)Active}Records
    i.0
)
credit_damage =: 3 : 0
    'tower_index enemy_index damage' =. y
    tower =. (13,damage)add_field tower_index{::Towers
    Towers =: (<tower)tower_index}Towers
    kind =. 1{enemy_index{Enemies
    EnemyTypes =: (<(14,damage)add_field kind{::EnemyTypes)kind}EnemyTypes
    wave =. Active{::Records
    amounts =. 15{::wave
    amounts =. (#Towers){.amounts
    amounts =. (damage+tower_index{amounts)tower_index}amounts
    wave =. (<amounts)15}wave
    Records =: (<wave)Active}Records
    i.0
)
kill_enemy =: 3 : 0
    'enemy_index tower_index' =. y
    enemy =. enemy_index{Enemies
    enemy =. 0 10}enemy
    Enemies =: enemy enemy_index}Enemies
    cell =. grid_index enemy_occupied enemy
    KillCounts =: (1+cell{KillCounts)cell}KillCounts
    kind_index =. 1{enemy
    kind =. kind_index{::EnemyTypes
    bounty =. 6{::kind
    tower =. 12 1 add_field tower_index{::Towers
    Towers =: (<tower)tower_index}Towers
    EnemyTypes =: (<12 1 add_field kind)kind_index}EnemyTypes
    wave =. 7 1 add_field Active{::Records
    wave =. (10,bounty)add_field wave
    Records =: (<wave)Active}Records
    Gold =: Gold+bounty
    Income =: (bounty+0{Income)0}Income
    record 'KILL E| | T| bounty | gold |'format (0{enemy);(0{::kind);(tower_index+1);bounty;Gold
    for_child. i.10{::kind do.
        child =. (1+#Enemies)split_enemy enemy
        add_enemy child
        record 'SPAWN E| | E| hp |'format (0{child);(0{::(1{child){::EnemyTypes);(0{enemy);4{child
    end.
    i.0
)
leak_enemy =: 3 : 0
    enemy =. y{Enemies
    enemy =. 0 10}enemy
    Enemies =: enemy y}Enemies
    kind_index =. 1{enemy
    kind =. kind_index{::EnemyTypes
    lost =. Lives<.7{::kind
    Lives =: Lives-lost
    EnemyTypes =: (<13 1 add_field kind)kind_index}EnemyTypes
    wave =. 8 1 add_field Active{::Records
    wave =. (9,lost)add_field wave
    Records =: (<wave)Active}Records
    record 'LEAK E| | lives |'format (0{enemy);(0{::kind);Lives
    if. Lives=0 do.
        record 'DEFEAT'
        Outcome =: 'defeat'
        close_wave 'lost'
        Active =: _1
    end.
    i.0
)
close_wave =: 3 : 0
    wave =. Active{::Records
    wave =. (<Tick)2}wave
    wave =. (<y)3}wave
    wave =. (<Gold)13}wave
    wave =. (<Lives)14}wave
    Records =: (<wave)Active}Records
    i.0
)
move_enemy =: 3 : 0
    enemy =. y{Enemies
    if. (8{enemy)>0 do.
        source =. (9{enemy)-1
        damage =. (4{enemy)<.7{enemy
        enemy =. ((4{enemy)-damage)4}enemy
        enemy =. (effect_advance 7 8 9{enemy)7 8 9}enemy
        Enemies =: enemy y}Enemies
        credit_damage source,y,damage
        if. (4{enemy)=0 do. kill_enemy y,source
            i.0 return. end.
    end.
    kind =. (1{enemy){::EnemyTypes
    enemy =. ((3{enemy)<.(4{enemy)+8{::kind)4}enemy
    speed =. enemy_speed enemy
    if. (6{enemy)>0 do.
        effect =. effect_advance (5 6{enemy),0
        enemy =. (2{.effect)5 6}enemy
    end.
    arrived =. 0
    if. enemy_flying enemy do.
        'point arrived' =. speed advance_point (16 17{enemy),:cell_center Exit
        enemy =. point 16 17}enemy
    else.
        if. grid_water enemy_occupied enemy do. speed =. speed div 2 end.
        while. speed>0 do.
            rest =. 100-15{enemy
            if. speed<rest do. enemy =. (speed+15{enemy)15}enemy
                speed =. 0
            else.
                speed =. speed-rest
                cell =. 13 14{enemy
                enemy =. cell 11 12}enemy
                enemy =. 0 15}enemy
                if. cell-:Exit do. arrived =. 1
                    break. end.
                enemy =. (Field next_cell cell)13 14}enemy
            end.
        end.
    end.
    Enemies =: enemy y}Enemies
    if. arrived do. leak_enemy y end.
    i.0
)
fire_towers =: 3 : 0
    for_index. standing_towers'' do.
        tower =. index{::Towers
        if. Tick<5{::tower do. continue. end.
        target =. select_target tower
        if. target<0 do. continue. end.
        stats =. tower_stats tower
        ProjectileCount =: ProjectileCount+1
        targets =. 2{::(1{::tower){::TowerTypes
        projectile =. (<ProjectileCount),(<index+1),(<target+1),(<tower_center tower),(<enemy_position target{Enemies),(<targets),<"0 (2 4 5 6 7 8 9){stats
        Projectiles =: Projectiles,<projectile
        tower =. 9 1 add_field tower
        tower =. (<Tick+3{stats)5}tower
        Towers =: (<tower)index}Towers
        record 'SHOT T| E|'format (index+1);target+1
    end.
    i.0
)
impact =: 3 : 0
    tower_index =. (1{::y)-1
    target =. (2{::y)-1
    victims =. 0$0
    splash =. 8{::y
    if. splash=0 do.
        if. (<target,10){Enemies do. victims =. ,target end.
    else.
        aim =. 4{::y
        targets =. 5{::y
        for_index. living_enemies'' do.
            enemy =. index{Enemies
            if. targets can_aim enemy do.
                if. ((enemy_position enemy)squared_distance aim)<:*:splash do. victims =. victims,index end.
            end.
        end.
    end.
    if. 0=#victims do. Towers =: (<11 1 add_field tower_index{::Towers)tower_index}Towers end.
    for_index. victims do.
        Towers =: (<10 1 add_field tower_index{::Towers)tower_index}Towers
        enemy =. index{Enemies
        armor =. 4{::(1{enemy){::EnemyTypes
        damage =. damage_dealt (4{enemy),(6{::y),armor
        enemy =. ((4{enemy)-damage)4}enemy
        Enemies =: enemy index}Enemies
        credit_damage tower_index,index,damage
        if. (4{enemy)=0 do. kill_enemy index,tower_index
            continue. end.
        if. (9{::y)>0 do.
            effect =. ((9{::y),(10{::y),0)effect_receive (5 6{enemy),0
            enemy =. (2{.effect)5 6}enemy
        end.
        if. (11{::y)>0 do.
            effect =. ((11{::y),(12{::y),tower_index+1)effect_receive 7 8 9{enemy
            enemy =. effect 7 8 9}enemy
        end.
        Enemies =: enemy index}Enemies
    end.
    i.0
)
move_projectiles =: 3 : 0
    flying =. 0$a:
    for_projectile. Projectiles do.
        projectile =. >projectile
        target =. ((2{::projectile)-1){Enemies
        if. 10{target do. projectile =. (<enemy_position target)4}projectile end.
        'projectile arrived' =. projectile_fly projectile
        if. arrived do. impact projectile
        else. flying =. flying,<projectile end.
    end.
    Projectiles =: flying
    i.0
)
check_wave_end =: 3 : 0
    if. Active<0 do. i.0 return. end.
    if. #living_enemies'' do. i.0 return. end.
    wave =. Active{::Records
    plan =. Active{::Waves
    if. -.(4{::wave)-:2{"1 (1{::plan)do. i.0 return. end.
    reward =. 0{::plan
    Gold =: Gold+reward
    interest =. InterestCap<.(Gold*InterestRate)div 100
    Gold =: Gold+interest
    Income =: (reward+1{Income)1}Income
    Income =: (interest+2{Income)2}Income
    wave =. (<reward)11}wave
    wave =. (<interest)12}wave
    Records =: (<wave)Active}Records
    record 'WAVE_END | reward | interest | gold |'format (Active+1);reward;interest;Gold
    if. (Active+1)=#Waves do.
        record 'VICTORY'
        Outcome =: 'victory'
    else. NextStart =: Tick+ScheduleInterval end.
    close_wave 'cleared'
    Active =: _1
    i.0
)
map_picture =: 3 : 0
    rows =. ,Grid
    for_spawn. Spawns do.
        for_cell. Field field_path spawn do.
            if. (cell{,Grid)e.'.~' do. rows =. '+'cell}rows end.
        end.
    end.
    for_index. standing_towers'' do.
        tower =. index{::Towers
        symbol =. {.1{::(1{::tower){::TowerTypes
        rows =. symbol (grid_index 2{::tower)}rows
    end.
    occupants =. (Width*Height)$0
    for_index. living_enemies'' do.
        enemy =. index{Enemies
        cell =. grid_index enemy_occupied enemy
        count =. 1+cell{occupants
        occupants =. count cell}occupants
        symbol =. '*'
        if. count=1 do. symbol =. {.1{::(1{enemy){::EnemyTypes end.
        rows =. symbol cell}rows
    end.
    (Height,Width)$rows
)
analysis_picture =: 3 : 0
    rows =. ''
    for_index. i.Width*Height do.
        cell =. cell_of_index index
        terrain =. index{,Grid
        tower_index =. tower_at cell
        symbol =. '.'
        if. y=1 do.
            if. terrain e.'#E' do. symbol =. terrain
            elseif. tower_index>:0 do. symbol =. {.1{::(1{::tower_index{::Towers){::TowerTypes
            elseif. (index{Field)<0 do. symbol =. '?'
            else. symbol =. (Field field_direction cell){'^>v<' end.
        elseif. y=2 do.
            if. terrain='#' do. symbol =. '#'
            elseif. tower_index>:0 do. symbol =. {.1{::(1{::tower_index{::Towers){::TowerTypes
            else.
                count =. 0
                for_other. standing_towers'' do. count =. count+(other{::Towers)tower_in_range cell_center cell end.
                symbol =. digit count
            end.
        else.
            count =. index{KillCounts
            if. count>0 do. symbol =. digit count
            elseif. terrain='#' do. symbol =. '#' end.
        end.
        rows =. rows,symbol
    end.
    (Height,Width)$rows
)
snapshot_block =: 3 : 0
    next =. '-'
    if. (Active<0)*.0=#Outcome do. next =. number NextStart end.
    lines =. <'| | wave | next | gold | lives |'format y;Tick;(#Records);next;Gold;Lives
    lines =. lines,ruled map_picture''
    for_index. i.#Spawns do. lines =. lines,<'PATH | length |'format (index+1);Field field_at index{Spawns end.
    for_index. standing_towers'' do.
        tower =. index{::Towers
        cell =. 2{::tower
        lines =. lines,<'T| | | | level | mode | ready |'format (index+1);(0{::(1{::tower){::TowerTypes);(0{cell);(1{cell);(3{::tower);(4{::tower);5{::tower
    end.
    for_index. living_enemies'' do.
        enemy =. index{Enemies
        point =. enemy_position enemy
        lines =. lines,<'E| | | | hp |/| slow | | burn | |'format (index+1);(0{::(1{enemy){::EnemyTypes);(0{point);(1{point);(4{enemy);(3{enemy);(5{enemy);(6{enemy);(7{enemy);8{enemy
    end.
    for_projectile. Projectiles do.
        projectile =. >projectile
        point =. 3{::projectile
        lines =. lines,<'P| T| E| | |'format (0{::projectile);(1{::projectile);(2{::projectile);(0{point);1{point
    end.
    lines
)
wave_lines =: 3 : 0
    header =. 'wave,start,end,status,spawned,peak,kills,leaks,lives_lost,bounty,reward,interest,gold,lives'
    for_index. i.#Towers do. header =. header,',T',number index+1 end.
    lines =. <header
    for_wave. Records do.
        wave =. >wave
        fields =. (0 1 2 3 5 6 7 8 9 10 11 12 13 14){wave
        damage =. (#Towers){.15{::wave
        lines =. lines,<','join fields,<"0 damage
    end.
    lines
)
summary_lines =: 3 : 0
    cleared =. perfect =. spawned =. killed =. leaked =. total_damage =. 0
    for_wave. Records do.
        wave =. >wave
        if. 'cleared'-:3{::wave do.
            cleared =. cleared+1
            perfect =. perfect+0=8{::wave
        end.
    end.
    for_kind. EnemyTypes do.
        kind =. >kind
        spawned =. spawned+11{::kind
        killed =. killed+12{::kind
        leaked =. leaked+13{::kind
    end.
    best =. _1
    best_damage =. 0
    for_index. i.#Towers do.
        damage =. 13{::index{::Towers
        total_damage =. total_damage+damage
        if. (best<0)+.damage>best_damage do. best =. index
            best_damage =. damage end.
    end.
    unused =. (#Actions)-(Done+Refused)
    score =. (10*killed)+(100*Lives)+(50*perfect)+Gold
    lines =. (<'outcome ',Outcome),<'ticks ',number Tick
    lines =. lines,<'waves |/| perfect |'format cleared;(#Waves);perfect
    lines =. lines,<'lives |/|'format Lives;InitialLives
    lines =. lines,<'gold ',number Gold
    lines =. lines,<'enemies spawned | killed | leaked |'format spawned;killed;leaked
    lines =. lines,<'income bounty | reward | interest | early | refund |'format <"0 Income
    lines =. lines,<'spent ',number Spent
    lines =. lines,<'damage ',number total_damage
    lines =. lines,<'actions total | done | refused | unused |'format (#Actions);Done;Refused;unused
    lines =. lines,<'score ',number score
    mvp =. 'mvp -'
    if. best>:0 do. mvp =. 'mvp T| damage |'format (best+1);best_damage end.
    lines =. lines,<mvp
    for_kind. EnemyTypes do.
        kind =. >kind
        lines =. lines,<'ENEMY | spawned | killed | leaked | damage |'format (0{::kind);(11{::kind);(12{::kind);(13{::kind);14{::kind
    end.
    for_index. i.#Towers do.
        tower =. index{::Towers
        cell =. 2{::tower
        state =. 'active'
        if. -.tower_standing tower do. state =. 'sold ',number 8{::tower end.
        damage =. 13{::tower
        per_shot =. damage one_decimal 9{::tower
        share =. (100*damage)one_decimal total_damage
        lines =. lines,<'TOWER T| | | | level | mode | | shots | hits | fizzles | kills | damage | per_shot | share | invested |'format (index+1);(0{::(1{::tower){::TowerTypes);(0{cell);(1{cell);(3{::tower);(4{::tower);state;(9{::tower);(10{::tower);(11{::tower);(12{::tower);damage;per_shot;share;6{::tower
    end.
    lines
)
main =: 3 : 0
    read_map''
    parse_tower_types''
    parse_waves''
    read_parameters''
    Tick =: Spent =: Done =: Refused =: ProjectileCount =: 0
    Gold =: InitialGold
    Lives =: InitialLives
    Income =: 5$0
    Towers =: Projectiles =: Records =: Events =: Snapshots =: 0$a:
    Enemies =: 0 18$0
    KillCounts =: (Width*Height)$0
    Active =: _1
    NextStart =: ScheduleStart
    Outcome =: ''
    Field =: distance_field (Width*Height)$0
    action_index =. 0
    while. 1 do.
        Tick =: Tick+1
        while. action_index<#Actions do.
            action =. action_index{::Actions
            if. Tick~:0{::action do. break. end.
            if. perform_action action do. Done =: Done+1 else. Refused =: Refused+1 end.
            action_index =. action_index+1
        end.
        spawn_enemies''
        for_index. living_enemies'' do.
            move_enemy index
            if. #Outcome do. break. end.
        end.
        if. #Outcome do. break. end.
        fire_towers''
        move_projectiles''
        check_wave_end''
        if. Tick e.SnapshotTicks do. Snapshots =: Snapshots,snapshot_block 'SNAPSHOT' end.
        if. #Outcome do. break. end.
    end.
    Snapshots =: Snapshots,snapshot_block 'FINAL'
    titles =. 'FLOW';'COVERAGE';'KILLS'
    for_mode. 1 2 3 do.
        Snapshots =: Snapshots,(mode-1){titles
        Snapshots =: Snapshots,ruled analysis_picture mode
    end.
    1!:5 ::0: <'output'
    'events.txt'write_lines Events
    'waves.csv'write_lines wave_lines''
    'snapshots.txt'write_lines Snapshots
    'summary.txt'write_lines summary_lines''
    i.0
)
main''
