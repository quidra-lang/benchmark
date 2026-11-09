junction_record =: 3 : 0
    'node offset tokens' =. y
    phases =. 0$a:
    cycle =. 0
    for_box. tokens do.
        'duration token' =. ':' split >box
        duration =. num duration
        greens =. 0$a:
        if. -.token-:'-' do. greens =. ',' split token end.
        phases =. phases,<'duration token greens' record (<duration),(<token),<greens
        cycle =. cycle+duration
    end.
    'node offset phases cycle incoming' record (<node),(<offset),(<phases),(<cycle),<0$0
)
is_green =: 4 : 0
    segment =. x
    junction =. ('junction' seg segment){::Junctions
    phases =. 'phases' get_key junction
    if. 0=#phases do. 1 return. end.
    tau =. ('cycle' get_key junction)|((y-1)+'offset' get_key junction)
    for_box. phases do.
        phase =. >box
        duration =. 'duration' get_key phase
        if. tau<duration do. (<'id' seg segment)e.'greens' get_key phase return. end.
        tau =. tau-duration
    end.
)
plan_lines =: 3 : 0
    node =. 'node' get_key y
    phases =. 'phases' get_key y
    if. 0=#phases do. <'JUNCTION ',node,' unsignalized' return. end.
    lines =. <text_line (<'JUNCTION'),(<node),(<'signal cycle'),(<'cycle' get_key y),(<'offset'),<'offset' get_key y
    first =. 0
    for_index. i.#phases do.
        phase =. index{::phases
        last =. (first+'duration' get_key phase)-1
        lines =. lines,<text_line (<'  PHASE'),(<index+1),(<range_text first,last),<'token' get_key phase
        first =. last+1
    end.
    lines
)
