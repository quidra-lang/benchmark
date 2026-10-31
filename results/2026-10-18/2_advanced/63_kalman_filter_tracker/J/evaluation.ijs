integer =: 3 : 0
    text =. ,":y
    '-'(I.text='_')}text
)
parse_number =: 3 : '". ''_''(I.y=''-'')}y'
real =: 3 : 0
    if. 0=#,y do. ,'-' return. end.
    text =. ,0j4":y
    if. (0=0".text)*.'_'={.text do. text =. }.text end.
    '-'(I.text='_')}text
)
join =: 4 : 0
    text =. ''
    for_i. i.#y do.
        if. i do. text =. text,x end.
        text =. text,i{::y
    end.
    text
)
render_value =: 3 : 0
    if. 2=3!:0 y do. ,y else. integer y end.
)
emit =: 3 : ''' ''join render_value&.>y'
formatted =: 3 : ''' ''join real&.>y'
squared_distance =: 4 : 0
    'dx dy' =. (2{.x)-2{.y
    (dx*dx)+dy*dy
)
distance =: 4 : '%:x squared_distance y'
ospa =: 3 : 0
    'first second cutoff' =. y
    if. ((#first)=0)*.(#second)=0 do. 0.0 return. end.
    if. ((#first)=0)+.(#second)=0 do. cutoff return. end.
    smaller =. first
    larger =. second
    if. (#first)>#second do. smaller =. second [ larger =. first end.
    costs =. ((#smaller),#larger)$0.0
    for_i. i.#smaller do.
        for_j. i.#larger do.
            clipped =. cutoff<.(i{smaller)distance j{larger
            costs =. (clipped*clipped)(<i,j)}costs
        end.
    end.
    total =. 0.0
    for_pair. minimum_matching costs do. total =. total+(<pair){costs end.
    %:(total+(cutoff*cutoff)*((#larger)-#smaller))%#larger
)
continuity =: 3 : 0
    covered =. groups =. swaps =. 0
    previous_label =. delay =. _1
    previous_covered =. 0
    for_i. i.#y do.
        label =. i{y
        if. label<0 do. previous_covered =. 0 else.
            covered =. covered+1
            if. delay<0 do. delay =. i end.
            if. -.previous_covered do. groups =. groups+1 end.
            if. (previous_label>:0)*.previous_label~:label do. swaps =. swaps+1 end.
            previous_label =. label
            previous_covered =. 1
        end.
    end.
    covered,(0>.groups-1),swaps,delay
)
