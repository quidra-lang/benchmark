function transition_matrix(model,t)
    f = identity_matrix(model=="CV" ? 4 : 6)
    f[1,3] = f[2,4] = t
    if model=="CA"
        f[1,5] = f[2,6] = t*t/2
        f[3,5] = f[4,6] = t
    end
    f
end
function process_noise(model,t,q)
    if model=="CV"
        entries = ((1,1,q*t*t*t/3),(1,3,q*t*t/2),(3,3,q*t))
        result = zeros(4,4)
    else
        entries = (
            (1,1,q*t*t*t*t*t/20),
            (1,3,q*t*t*t*t/8),
            (1,5,q*t*t*t/6),
            (3,3,q*t*t*t/3),
            (3,5,q*t*t/2),
            (5,5,q*t)
        )
        result = zeros(6,6)
    end
    for axis in 0:1,(row,column,value) in entries
        result[row+axis,column+axis] = result[column+axis,row+axis] = value
    end
    result
end
mutable struct KalmanFilter
    model::String
    q::Float64
    x::Vector{Float64}
    p::Matrix{Float64}
    h::Matrix{Float64}
    r::Matrix{Float64}
    f::Matrix{Float64}
    xp::Vector{Float64}
    pp::Matrix{Float64}
end
function KalmanFilter(model,q,sigma,velocity_variance,acceleration_variance,measurement)
    n = model=="CV" ? 4 : 6
    variances = [sigma*sigma,sigma*sigma,velocity_variance,velocity_variance]
    n==6 && append!(variances,[acceleration_variance,acceleration_variance])
    h = zeros(2,n)
    h[1,1] = h[2,2] = 1
    KalmanFilter(
        model,
        q,
        [measurement;zeros(n-2)],
        diagonal_matrix(variances),
        h,
        diagonal_matrix([sigma*sigma,sigma*sigma]),
        zeros(0,0),
        Float64[],
        zeros(0,0)
    )
end
function predict!(filter,t)
    filter.f = transition_matrix(filter.model,t)
    filter.x = matrix_vector(filter.f,filter.x)
    filter.p = matrix_product(
        matrix_product(filter.f,filter.p),
        transpose(filter.f)
    )+process_noise(filter.model,t,filter.q)
    filter.xp,filter.pp = filter.x,filter.p
end
function innovation(filter,measurement)
    residual = measurement-matrix_vector(filter.h,filter.x)
    covariance = matrix_product(matrix_product(filter.h,filter.p),transpose(filter.h))+filter.r
    precision = matrix_inverse(covariance)
    (residual=residual,covariance=covariance,precision=precision,distance2=quadratic2(residual,precision))
end
function update!(filter,measurement,info=innovation(filter,measurement))
    gain = matrix_product(matrix_product(filter.p,transpose(filter.h)),info.precision)
    correction = identity_matrix(length(filter.x))-matrix_product(gain,filter.h)
    filter.x = filter.x+matrix_vector(gain,info.residual)
    filter.p = matrix_product(
        matrix_product(correction,filter.p),
        transpose(correction)
    )+matrix_product(matrix_product(gain,filter.r),transpose(gain))
    likelihood = -log(2*pi)-log(determinant2(info.covariance))/2-info.distance2/2
    (distance2=info.distance2,likelihood=likelihood,covariance=info.covariance)
end
filter_snapshot(filter) = (x=filter.x,p=filter.p,xp=filter.xp,pp=filter.pp,f=filter.f)
function smooth(history)
    states = Vector{Float64}[Float64[] for _ in history]
    states[end] = history[end].x
    for index in length(history)-1:-1:1
        current,following = history[index],history[index+1]
        gain = matrix_product(matrix_product(current.p,transpose(following.f)),matrix_inverse(following.pp))
        states[index] = current.x+matrix_vector(gain,states[index+1]-following.xp)
    end
    states
end
