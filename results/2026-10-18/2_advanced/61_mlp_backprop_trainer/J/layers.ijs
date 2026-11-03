layer_activation =: 4 : 0
    if. x-:'TANH' do. 1-2%1+^2*y
    elseif. x-:'SIGMOID' do. 1%1+^-y
    else. 0.0>.y end.
)
layer_derivative =: 4 : 0
    'preactivation activation' =. y
    if. x-:'TANH' do. 1-activation*activation
    elseif. x-:'SIGMOID' do. activation*(1-activation)
    else. 0.0+preactivation>0 end.
)
layer_pre_activation =: 3 : 0
    'theta layer activation' =. y
    'inputs outputs kind role weight_start bias_start' =. layer
    result =. outputs$0.0
    position =. weight_start
    for_j. i.outputs do.
        total =. 0.0
        for_i. i.inputs do.
            total =. total+(position{theta)*i{activation
            position =. position+1
        end.
        result =. (total+(bias_start+j){theta)j}result
    end.
    result
)
layer_backward =: 3 : 0
    'theta layer errors' =. y
    'inputs outputs kind role weight_start bias_start' =. layer
    result =. inputs$0.0
    for_i. i.inputs do.
        total =. 0.0
        for_j. i.outputs do.
            position =. (weight_start+j*inputs)+i
            total =. total+(position{theta)*j{errors
        end.
        result =. total i}result
    end.
    result
)
layer_output =: 3 : 0
    'kind z label' =. y
    size =. #z
    target =. 0.0+label=i.size
    if. kind-:'SOFTMAX' do.
        maximum =. >./z
        exponentials =. ^z-maximum
        total =. 0.0
        for_value. exponentials do. total =. total+value end.
        scores =. exponentials%total
        errors =. scores-target
        loss =. (^.total)-((label{z)-maximum)
    else.
        scores =. 1%1+^-z
        residual =. scores-target
        errors =. (((2*residual)*scores)*(1-scores))%size
        total =. 0.0
        for_value. residual do. total =. total+value*value end.
        loss =. total%size
    end.
    (<scores),(<loss),<errors
)
