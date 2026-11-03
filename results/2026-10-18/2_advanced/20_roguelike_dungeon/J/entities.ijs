read_monster_types =: 3 : 0
    MonsterNames =: MonsterTraits =: 0$a:
    MonsterSymbols =: ''
    MonsterValues =: 0 11$0
    for_line. read_lines 'monsters.txt' do.
        fields =. words >line
        MonsterNames =: MonsterNames,0{fields
        MonsterSymbols =: MonsterSymbols,1{::fields
        MonsterTraits =: MonsterTraits,11{fields
        values =. (num 2{::fields),(num 3{::fields),num 4{::fields
        values =. values,parse_dice 5{::fields
        values =. values,(num 6{::fields),(num 7{::fields),parse_dice 8{::fields
        values =. values,(num 9{::fields),num 10{::fields
        MonsterValues =: MonsterValues,values
    end.
    i.0
)
read_item_types =: 3 : 0
    ItemNames =: ItemCategories =: ItemEffects =: 0$a:
    ItemValues =: 0 9$0
    for_line. read_lines 'items.txt' do.
        fields =. words >line
        category =. 0{::fields
        effect =. ''
        values =. (num 2{::fields),(num 3{::fields),(num 4{::fields),1 1 0 0 0 0
        if. category-:'weapon' do.
            values =. (parse_dice 5{::fields)3 4}values
            values =. (num 6{::fields)5}values
        elseif. category-:'armor' do. values =. (num 5{::fields)6}values
        elseif. category-:'potion' do.
            effect =. 5{::fields
            if. effect-:'heal' do. values =. (parse_dice 6{::fields)3 4}values
            elseif. effect-:'poison' do. values =. (num 6{::fields)7}values end.
        elseif. category-:'scroll' do. effect =. 5{::fields
        elseif. category-:'food' do. values =. (num 5{::fields)8}values
        elseif. category-:'gold' do. values =. (parse_dice 5{::fields)3 4}values end.
        ItemNames =: ItemNames,1{fields
        ItemCategories =: ItemCategories,<category
        ItemEffects =: ItemEffects,<effect
        ItemValues =: ItemValues,values
    end.
    AmuletType =: #ItemNames
    ItemNames =: ItemNames,<'amulet'
    ItemCategories =: ItemCategories,<'amulet'
    ItemEffects =: ItemEffects,<''
    ItemValues =: ItemValues,0 0 0 1 1 0 0 0 0
    i.0
)
new_item =: 3 : 0
    identifier =. #ItemData
    ItemData =: ItemData,y
    identifier
)
item_category =: 3 : '((<y,0){ItemData){::ItemCategories'
item_symbol =: 3 : 0
    categories =. 'weapon';'armor';'potion';'scroll';'food';'gold';'amulet'
    (categories i.<item_category y){')[!?%$"'
)
item_name =: 3 : 0
    row =. y{ItemData
    name =. (0{row){::ItemNames
    name =. ' ' (I.name='_')}name
    category =. item_category y
    if. (<category)e.'weapon';'armor' do.
        '+',(number 4{row),' ',name
    elseif. category-:'gold' do. (number 3{row),' gold'
    else. name end.
)
item_reference =: 3 : 0
    if. 'gold'-:item_category y do. item_name y
    else. 'the ',item_name y end.
)
monster_at =: 3 : 0
    for_index. i.#Monsters do.
        row =. index{Monsters
        if. (8{row)*.y-:1 2{row do. index return. end.
    end.
    _1
)
item_at =: 3 : 0
    for_identifier. Floor do.
        if. y-:1 2{identifier{ItemData do. identifier return. end.
    end.
    _1
)
set_monster =: 4 : 'Monsters =: x (<y)}Monsters'
set_item =: 4 : 'ItemData =: x (<y)}ItemData'
