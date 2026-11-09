read_lines =: 3 : '<;._2 (1!:1 <''input/'',y)'
hundredths =: 3 : 0
    parts =. '.' split y
    whole =. 100*num 0{::parts
    if. 1=#parts do. whole return. end.
    whole+num 2{.(1{::parts),'00'
)
load_dataset =: 3 : 0
    GroupNames =: Groups =: 0$a:
    for_line. }.read_lines 'samples.csv' do.
        fields =. ',' split >line
        name =. 0{::fields
        index =. GroupNames i.<name
        if. index=#Groups do.
            GroupNames =: GroupNames,<name
            Groups =: Groups,<0$0
        end.
        values =. (index{::Groups),hundredths 1{::fields
        Groups =: (<values) index}Groups
    end.
    Before =: After =: 0$0
    for_line. }.read_lines 'paired.csv' do.
        fields =. ',' split >line
        Before =: Before,hundredths 1{::fields
        After =: After,hundredths 2{::fields
    end.
    Differences =: After-Before
    settings =. 0$a:
    PairIndices =: 0 2$0
    for_line. read_lines 'params.txt' do.
        fields =. ' ' split >line
        if. 'compare'-:0{::fields do. PairIndices =: PairIndices,GroupNames i.}.fields
        else. settings =. settings,<num&>}.fields end.
    end.
    Seed =: {.0{::settings
    Bootstrap =: {.1{::settings
    Permutations =: {.2{::settings
    Confidence =: {.3{::settings
    Pilot =: {.4{::settings
    'PowerSims PowerPerms' =: 5{::settings
    Bins =: {.6{::settings
    GroupCount =: #Groups
    Sizes =: #&>Groups
    i.0
)
