TargetModes =: ;:'FIRST LAST STRONGEST WEAKEST CLOSEST'
parse_tower_types =: 3 : 0
    TowerNames =: TowerTypes =: 0$a:
    lines =. read_lines 'towers.txt'
    index =. 0
    while. index<#lines do.
        fields =. ' 'split index{::lines
        count =. num 4{::fields
        index =. index+1
        levels =. 0 10$0
        for_level. i.count do.
            levels =. levels,num&>}. ' 'split index{::lines
            index =. index+1
        end.
        TowerNames =: TowerNames,1{fields
        TowerTypes =: TowerTypes,<(1 2 3{fields),<levels
    end.
    i.0
)
new_tower =: 3 : 0
    'number kind cell tick' =. y
    cost =. 0{0{3{::kind{::TowerTypes
    (<number),(<kind),(<cell),(<1),(<'FIRST'),(<tick),(<cost),(<tick),(<0),(<0),(<0),(<0),(<0),<0
)
tower_stats =: 3 : '((3{::y)-1){3{::(1{::y){::TowerTypes'
tower_standing =: 3 : '0=8{::y'
tower_center =: 3 : 'cell_center 2{::y'
can_aim =: 4 : '(x-:''both'')+.x-:2{::(1{y){::EnemyTypes'
tower_in_range =: 4 : '((tower_center x)squared_distance y)<:*:1{tower_stats x'
target_key =: 4 : 0
    mode =. 4{::x
    if. mode-:'FIRST' do. enemy_remaining y
    elseif. mode-:'LAST' do. -enemy_remaining y
    elseif. mode-:'STRONGEST' do. -4{y
    elseif. mode-:'WEAKEST' do. 4{y
    else. (tower_center x)squared_distance enemy_position y end.
)
select_target =: 3 : 0
    best =. _1
    best_key =. 0
    targets =. 2{::(1{::y){::TowerTypes
    for_index. I.10{"1 Enemies do.
        enemy =. index{Enemies
        if. -.targets can_aim enemy do. continue. end.
        if. -.y tower_in_range enemy_position enemy do. continue. end.
        key =. y target_key enemy
        if. (best<0)+.key<best_key do. best =. index
            best_key =. key end.
    end.
    best
)
