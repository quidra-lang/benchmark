parse_waves =: 3 : 0
    EnemyNames =: EnemyTypes =: Waves =: 0$a:
    for_line. read_lines 'waves.txt' do.
        fields =. ' 'split >line
        command =. 0{::fields
        if. command-:'enemy' do.
            split_into =. _1
            if. -.('-'-:10{::fields)do. split_into =. EnemyNames i.10{fields end.
            kind =. (1 2 3{fields),(num&.>4 5 6 7 8 9{fields),(<split_into),(<num 11{::fields),(<0),(<0),(<0),<0
            EnemyNames =: EnemyNames,1{fields
            EnemyTypes =: EnemyTypes,<kind
        elseif. command-:'wave' do. Waves =: Waves,<(<num 1{::fields),<0 6$0
        else.
            wave =. _1{::Waves
            group =. (EnemyNames i.1{fields),num&>2 3 4 5 6{fields
            groups =. (1{::wave),group
            wave =. (<groups)1}wave
            Waves =: (<wave)(_1)}Waves
        end.
    end.
    i.0
)
new_enemy =: 3 : 0
    'number kind multiplier' =. y
    hp =. ((3{::kind{::EnemyTypes)*multiplier)div 100
    number,kind,multiplier,hp,hp,0 0 0 0 0 1 0 0 0 0 0 0 0
)
enemy_flying =: 3 : '''air''-:2{::(1{y){::EnemyTypes'
enemy_position =: 3 : 0
    if. enemy_flying y do. 16 17{y
    else. (100*11 12{y)+((13 14{y)-11 12{y)*15{y end.
)
enemy_occupied =: 3 : 0
    if. enemy_flying y do. ((50+16{y)div 100),(50+17{y)div 100
    elseif. (15{y)<50 do. 11 12{y
    else. 13 14{y end.
)
enemy_remaining =: 3 : 0
    if. enemy_flying y do. isqrt (16 17{y)squared_distance cell_center Exit
    else. (100*Field field_at 13 14{y)+100-15{y end.
)
enemy_speed =: 3 : 0
    speed =. 5{::(1{y){::EnemyTypes
    if. (6{y)>0 do. (speed*(100-5{y))div 100 else. speed end.
)
split_enemy =: 4 : 0
    child =. new_enemy x,(9{::(1{y){::EnemyTypes),2{y
    (11 12 13 14 15 16 17{y)11 12 13 14 15 16 17}child
)
group_tick =: 4 : 0
    'start released' =. y
    start+(3{x)+released*4{x
)
wave_enemy_count =: 3 : '+/2{"1 (1{::y)'
