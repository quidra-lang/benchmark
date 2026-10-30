network_layout =: 3 : 0
    layers =. 0$a:
    weight_mask =. i.0
    previous =. ImageWidth*ImageHeight
    position =. weights =. 0
    for_definition. y do.
        'outputs activation kind' =. >definition
        size =. previous*outputs
        layer =. (<previous),(<outputs),(<activation),(<kind),(<position),<position+size
        layers =. layers,<layer
        weight_mask =. weight_mask,(size$1),outputs$0
        position =. position+size+outputs
        weights =. weights+size
        previous =. outputs
    end.
    (<layers),(<weight_mask),(<position),<weights
)
network_forward =: 3 : 0
    'layout theta image' =. y
    layers =. 0{::layout
    activations =. <3{::image
    preactivations =. 0$a:
    for_index. i.#layers do.
        layer =. index{::layers
        z =. layer_pre_activation (<theta),(<layer),<index{::activations
        preactivations =. preactivations,<z
        if. index=(#layers)-1 do.
            'scores loss errors' =. layer_output (<2{::layer),(<z),<1{::image
            activations =. activations,<scores
        else.
            activations =. activations,<(2{::layer)layer_activation z
        end.
    end.
    (<activations),(<preactivations),(<scores),(<loss),<errors
)
network_gradient =: 3 : 0
    'layout theta image want_input' =. y
    cache =. network_forward (<layout),(<theta),<image
    activations =. 0{::cache
    preactivations =. 1{::cache
    layers =. 0{::layout
    deltas =. (#layers)$<i.0
    deltas =. (<4{::cache)((#layers)-1)}deltas
    for_index. |.i.(#layers)-1 do.
        nextlayer =. (index+1){::layers
        propagated =. layer_backward (<theta),(<nextlayer),<(index+1){::deltas
        layer =. index{::layers
        derivative =. (2{::layer)layer_derivative (<index{::preactivations),<(index+1){::activations
        deltas =. (<propagated*derivative)index}deltas
    end.
    gradient =. (2{::layout)$0.0
    for_index. i.#layers do.
        layer =. index{::layers
        'inputs outputs kind role position bias_start' =. layer
        errors =. index{::deltas
        previous =. index{::activations
        for_j. i.outputs do.
            for_i. i.inputs do.
                gradient =. ((j{errors)*i{previous)position}gradient
                position =. position+1
            end.
        end.
        gradient =. errors(bias_start+i.outputs)}gradient
    end.
    input_gradient =. i.0
    if. want_input do. input_gradient =. layer_backward (<theta),(<0{::layers),<0{::deltas end.
    (<gradient),(<cache),<input_gradient
)
network_mean_gradient =: 3 : 0
    'layout theta images' =. y
    gradient =. (2{::layout)$0.0
    loss =. 0.0
    for_item. images do.
        image =. >item
        'component cache input_gradient' =. network_gradient (<layout),(<theta),(<image),<0
        gradient =. gradient+component
        loss =. loss+3{::cache
    end.
    (<gradient%#images),<loss%#images
)
network_evaluate =: 3 : 0
    'layout theta images' =. y
    outcomes =. 0$a:
    total =. 0.0
    correct =. 0
    for_item. images do.
        image =. >item
        cache =. network_forward (<layout),(<theta),<image
        scores =. 2{::cache
        prediction =. {.best_two scores
        hidden =. }.}:0{::cache
        outcome =. (<0{::image),(<1{::image),(<prediction),(<prediction{scores),(<scores),(<3{::cache),<hidden
        outcomes =. outcomes,<outcome
        total =. total+3{::cache
        correct =. correct+prediction=1{::image
    end.
    (<outcomes),(<total%#images),<correct
)
