local_clock =: 3 : 0
    Lamport =: (1+y{Lamport)y}Lamport
    VectorsState =: (1+(<y,y){VectorsState)(<y,y)}VectorsState
    0
)
receive_clock =: 4 : 0
    Lamport =: (1+(x{Lamport)>.4{y{Events)x}Lamport
    vector =. (x{VectorsState)>.y{EventVectors
    vector =. (1+x{vector)x}vector
    VectorsState =: vector x}VectorsState
    0
)
less_equal =: 4 : '*./x<:y'
before =: 4 : '(-.x-:y)*.x less_equal y'
relation =: 4 : 0
    if. x before y do. '->'
    elseif. y before x do. '<-'
    else. '||'
    end.
)
broadcast_deliverable =: 4 : 0
    'received source' =. y
    if. (source{x)~:1+source{received do. 0 return. end.
    *./(x<:received)+.(i.#x)=source
)
missing_indices =: 4 : 0
    'received source' =. y
    I.x>received+(i.#x)=source
)
vector_text =: 3 : ''',''join integer&.>y'
