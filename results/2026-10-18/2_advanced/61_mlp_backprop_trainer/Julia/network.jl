function layout_for(architecture)
    previous,index = architecture.width*architecture.height,1
    layers,mask = NamedTuple[],Bool[]
    for definition in architecture.layers
        outputs = definition.units
        weights = outputs*previous
        push!(
            layers,
            (
                inputs=previous,
                outputs=outputs,
                activation=definition.activation,
                kind=definition.kind,
                weight_start=index,
                weight_end=index+weights-1,
                bias_start=index+weights,
                bias_end=index+weights+outputs-1
            )
        )
        append!(mask,vcat(fill(true,weights),fill(false,outputs)))
        index += weights+outputs
        previous = outputs
    end
    (layers=layers,is_weight=mask,parameters=index-1,weight_count=count(mask))
end
function layer_values(theta,layer)
    weights = [theta[layer.weight_start+(j-1)*layer.inputs+i-1] for j in 1:layer.outputs,i in 1:layer.inputs]
    weights,theta[layer.bias_start:layer.bias_end]
end
function forward(layout,theta,image)
    activations = [image.vector]
    preactivations,weights = Vector{Float64}[],Matrix{Float64}[]
    scores,loss,delta = Float64[],0.0,Float64[]
    for (l,layer) in enumerate(layout.layers)
        w,b = layer_values(theta,layer)
        push!(weights,w)
        z = weighted_pre_activation(w,b,activations[end])
        push!(preactivations,z)
        if l==length(layout.layers)
            scores,loss,delta = output_scores(layer.activation,z,image.label)
            push!(activations,scores)
        else
            push!(activations,[hidden_activation(layer.activation,value) for value in z])
        end
    end
    (z=preactivations,a=activations,weights=weights,scores=scores,loss=loss,output_delta=delta)
end
function gradient(layout,theta,image,include_input=false)
    cache = forward(layout,theta,image)
    layers = layout.layers
    deltas = [Float64[] for _ in layers]
    deltas[end] = cache.output_delta
    for l in length(layers)-1:-1:1
        propagated = backward_sum(cache.weights[l+1],deltas[l+1])
        deltas[l] = [value*hidden_derivative(
            layers[l].activation,
            cache.z[l][j],
            cache.a[l+1][j]
        ) for (j,value) in enumerate(propagated)]
    end
    grad = zeros(layout.parameters)
    for (l,layer) in enumerate(layers)
        destination = layer.weight_start
        for j in 1:layer.outputs,i in 1:layer.inputs
            grad[destination] = deltas[l][j]*cache.a[l][i]
            destination += 1
        end
        grad[layer.bias_start:layer.bias_end] = deltas[l]
    end
    (
        gradient=grad,
        cache=cache,
        input_gradient=include_input ? backward_sum(cache.weights[1],deltas[1]) : Float64[]
    )
end
function average_gradient(layout,theta,images)
    result,loss = zeros(layout.parameters),0.0
    for image in images
        evaluated = gradient(layout,theta,image)
        loss += evaluated.cache.loss
        for (i,value) in enumerate(evaluated.gradient)
            result[i] += value
        end
    end
    result./length(images),loss/length(images)
end
function evaluate_network(layout,theta,images)
    outcomes,loss,correct = NamedTuple[],0.0,0
    for image in images
        cache = forward(layout,theta,image)
        predicted = argmax(cache.scores)-1
        push!(
            outcomes,
            (
                id=image.id,
                label=image.label,
                predicted=predicted,
                confidence=cache.scores[predicted+1],
                scores=cache.scores,
                loss=cache.loss,
                hidden=cache.a[2:end-1]
            )
        )
        loss += cache.loss
        correct += predicted==image.label
    end
    (loss=loss/length(images),correct=correct,outcomes=outcomes)
end
