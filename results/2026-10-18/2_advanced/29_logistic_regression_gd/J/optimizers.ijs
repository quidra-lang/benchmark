rng_draw =: 3 : '2147483647|48271*y'
shuffle =: 3 : 0
    'sequence state' =. y
    for_size. |.2+i.(#sequence)-1 do.
        state =. rng_draw state
        index =. size|state
        held =. (size-1){sequence
        sequence =. (index{sequence)(size-1)}sequence
        sequence =. held index}sequence
    end.
    (<sequence),<state
)
move =: 3 : 0
    'weights direction rate' =. y
    weights-rate*direction
)
cp_iteration =: 0&{::
cp_weights =: 1&{::
final_weights =: 3 : 'cp_weights >{:y'
gradient_descent =: 3 : 0
    'vectors targets lambda rate iterations' =. y
    weights =. ({:$vectors)$0.0
    checkpoints =. ,<(<0),<weights
    for_t. 1+i.iterations do.
        direction =. gradient (<weights),(<vectors),(<targets),<lambda
        weights =. move (<weights),(<direction),<rate
        if. 0=100|t do.
            checkpoints =. checkpoints,<(<t),<weights
        end.
    end.
    checkpoints
)
stochastic_gradient_descent =: 3 : 0
    'vectors targets lambda rate batch_size epochs state' =. y
    order =. i.#vectors
    weights =. ({:$vectors)$0.0
    checkpoints =. ,<(<0),<weights
    for_epoch. 1+i.epochs do.
        'order state' =. shuffle (<order),<state
        for_start. batch_size*i.((#order)+batch_size-1)intdiv batch_size do.
            batch =. (batch_size<.(#order)-start){.start}.order
            direction =. gradient (<weights),(<batch{vectors),(<batch{targets),<lambda
            weights =. move (<weights),(<direction),<rate
        end.
        checkpoints =. checkpoints,<(<epoch),<weights
    end.
    checkpoints
)
cholesky =: 3 : 0
    size =. #y
    lower =. (size,size)$0.0
    for_j. i.size do.
        for_i. j+i.size-j do.
            total =. 0.0
            for_k. i.j do.
                total =. total+((<i,k){lower)*(<j,k){lower
            end.
            remainder =. ((<i,j){y)-total
            if. i=j do.
                value =. %:remainder
            else.
                value =. remainder%(<j,j){lower
            end.
            lower =. value(<i,j)}lower
        end.
    end.
    lower
)
solve =: 4 : 0
    size =. #x
    middle =. solution =. size$0.0
    for_i. i.size do.
        total =. 0.0
        for_k. i.i do.
            total =. total+((<i,k){x)*k{middle
        end.
        middle =. (((i{y)-total)%(<i,i){x)i}middle
    end.
    for_i. |.i.size do.
        total =. 0.0
        for_k. (i+1)+i.size-i+1 do.
            total =. total+((<k,i){x)*k{solution
        end.
        solution =. (((i{middle)-total)%(<i,i){x)i}solution
    end.
    solution
)
newton_direction =: 3 : 0
    'weights vectors targets lambda' =. y
    direction =. gradient y
    step =. (cholesky hessian (<weights),(<vectors),<lambda)solve direction
    (<direction),<step
)
newton_method =: 3 : 0
    'vectors targets lambda' =. y
    weights =. ({:$vectors)$0.0
    checkpoints =. ,<(<0),<weights
    for_t. 1+i.10 do.
        'direction step' =. newton_direction (<weights),(<vectors),(<targets),<lambda
        weights =. weights-step
        checkpoints =. checkpoints,<(<t),<weights
    end.
    checkpoints
)
