Base.@kwdef mutable struct SMOModel
    points::Vector{NTuple{2,Float64}}
    labels::Vector{Int}
    kernel::SVMKernel
    matrix::Matrix{Float64}
    C::Float64
    tolerance::Float64
    eps::Float64
    max_passes::Int
    alpha::Vector{Float64}
    b::Float64 = 0.0
    errors::Vector{Float64}
    full_passes::Int = 0
    nonbound_passes::Int = 0
    examined::Int = 0
    steps::Int = 0
    choices::Vector{Int} = zeros(Int,3)
    clipping::Vector{Int} = zeros(Int,3)
    records::Vector{NamedTuple} = NamedTuple[]
    converged::Bool = false
end
passes(model) = model.full_passes+model.nonbound_passes
nonbound(model,i) = 0<model.alpha[i]<model.C
snap(model,value) = value<0.00000001 ? 0.0 : value>model.C-0.00000001 ? model.C : value
function take_step!(model,first,second)
    first==second && return false
    alpha1,alpha2 = model.alpha[first],model.alpha[second]
    y1,y2 = model.labels[first],model.labels[second]
    e1,e2 = model.errors[first],model.errors[second]
    lo,hi = y1!=y2 ? (max(0.0,alpha2-alpha1),min(model.C,model.C+alpha2-alpha1)) : (
        max(0.0,alpha2+alpha1-model.C),
        min(model.C,alpha2+alpha1)
    )
    lo==hi && return false
    k11,k12,k22 = model.matrix[first,first],model.matrix[first,second],model.matrix[second,second]
    eta = k11+k22-2k12
    eta<=0 && return false
    a2 = alpha2+y2*(e1-e2)/eta
    clipping = 1
    if a2<lo
        a2,clipping = lo,2
    elseif a2>hi
        a2,clipping = hi,3
    end
    a2 = snap(model,a2)
    abs(a2-alpha2)<model.eps*(a2+alpha2+model.eps) && return false
    a1 = snap(model,alpha1+y1*y2*(alpha2-a2))
    t1,t2 = y1*(a1-alpha1),y2*(a2-alpha2)
    b1,b2 = e1+t1*k11+t2*k12+model.b,e2+t1*k12+t2*k22+model.b
    threshold = 0<a1<model.C ? b1 : 0<a2<model.C ? b2 : (b1+b2)/2
    delta = threshold-model.b
    for i in eachindex(model.points)
        model.errors[i] = model.errors[i]+(t1*model.matrix[first,i]+t2*model.matrix[second,i]-delta)
    end
    0<a1<model.C && (model.errors[first]=0.0)
    0<a2<model.C && (model.errors[second]=0.0)
    model.alpha[first],model.alpha[second],model.b = a1,a2,threshold
    model.steps += 1
    model.clipping[clipping] += 1
    true
end
function examine!(model,second)
    model.examined += 1
    residual = model.errors[second]*model.labels[second]
    ((residual<-model.tolerance && model.alpha[second]<model.C) || (residual>model.tolerance && model.alpha[second]>0)) || return 0
    partner,largest = 0,-1.0
    for i in eachindex(model.points)
        if i!=second && nonbound(model,i)
            difference = abs(model.errors[i]-model.errors[second])
            if difference>largest
                largest,partner = difference,i
            end
        end
    end
    if partner!=0 && take_step!(model,partner,second)
        model.choices[1] += 1
        return 1
    end
    for first in eachindex(model.points)
        if nonbound(model,first) && take_step!(model,first,second)
            model.choices[2] += 1
            return 1
        end
    end
    for first in eachindex(model.points)
        if take_step!(model,first,second)
            model.choices[3] += 1
            return 1
        end
    end
    0
end
function train_model(points,labels,kernel,matrix,C,settings)
    model = SMOModel(
        points=points,
        labels=labels,
        kernel=kernel,
        matrix=matrix,
        C=C,
        tolerance=settings["tolerance"],
        eps=settings["eps"],
        max_passes=settings["max_passes"],
        alpha=zeros(length(points)),
        errors=-Float64.(labels)
    )
    examine_all = true
    while true
        examined_before,changed = model.examined,0
        for i in eachindex(points)
            (examine_all || nonbound(model,i)) && (changed+=examine!(model,i))
        end
        if examine_all
            model.full_passes += 1
        else
            model.nonbound_passes += 1
        end
        push!(
            model.records,
            (
                full=examine_all,
                examined=model.examined-examined_before,
                changed=changed,
                alpha=examine_all ? copy(model.alpha) : Float64[]
            )
        )
        if examine_all && changed==0
            model.converged = true
            break
        end
        passes(model)==model.max_passes && break
        if examine_all
            examine_all = false
        elseif changed==0
            examine_all = true
        end
    end
    model
end
function decision(model,point)
    total = 0.0
    for (i,alpha) in enumerate(model.alpha)
        alpha>0 && (total+=alpha*model.labels[i]*kernel_value(model.kernel,model.points[i],point))
    end
    total-model.b
end
function training_decisions(model)
    values = Float64[]
    for i in eachindex(model.points)
        total = 0.0
        for (j,alpha) in enumerate(model.alpha)
            alpha>0 && (total+=alpha*model.labels[j]*model.matrix[i,j])
        end
        push!(values,total-model.b)
    end
    values
end
