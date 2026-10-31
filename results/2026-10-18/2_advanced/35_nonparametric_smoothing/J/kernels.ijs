kernel_evaluate =: 4 : 0
    'positions values bandwidth kernel local_linear' =. 5{.x
    used =. I.(|positions-y)<bandwidth
    weights =. (#positions)$0.0
    minimum =. 1+local_linear
    if. (#used)<minimum do.
        (<0),(<0.0),<weights return.
    end.
    x0 =. y%100
    h =. bandwidth%100
    kappa =. ('epanechnikov';'biweight';'triweight')i.<kernel
    kappa =. kappa{0.75 0.9375 1.09375
    kernels =. i.0
    differences =. i.0
    for_index. used do.
        delta =. ((index{positions)%100)-x0
        u =. delta%h
        t =. 1-u*u
        weight =. kappa*t
        if. -.kernel-:'epanechnikov' do.
            weight =. weight*t
        end.
        if. kernel-:'triweight' do.
            weight =. weight*t
        end.
        kernels =. kernels,weight
        differences =. differences,delta
    end.
    s0 =. 0.0
    s1 =. 0.0
    s2 =. 0.0
    t0 =. 0.0
    t1 =. 0.0
    for_offset. i.#used do.
        index =. offset{used
        k =. offset{kernels
        d =. offset{differences
        s0 =. s0+k
        s1 =. s1+k*d
        s2 =. s2+(k*d)*d
        t0 =. t0+k*index{values
        t1 =. t1+(k*d)*index{values
    end.
    if. local_linear do.
        determinant =. (s0*s2)-s1*s1
        estimate =. ((s2*t0)-s1*t1)%determinant
        for_offset. i.#used do.
            index =. offset{used
            weight =. ((offset{kernels)*(s2-s1*offset{differences))%determinant
            weights =. weight index}weights
        end.
    else.
        estimate =. t0%s0
        weights =. (kernels%s0)used}weights
    end.
    (<1),(<estimate),<weights
)
kernel_fit =: 3 : 0
    'positions values bandwidth kernel local_linear diagnostics' =. y
    model =. (<positions),(<values),(<bandwidth),(<kernel),<local_linear
    fitted =. i.0
    leverage =. i.0
    defined =. 1
    if. diagnostics do.
        for_index. i.#positions do.
            'valid estimate weights' =. model kernel_evaluate index{positions
            fitted =. fitted,estimate
            if. valid do.
                leverage =. leverage,index{weights
            else.
                defined =. 0
            end.
        end.
    end.
    model,(<fitted),(<leverage),(<defined),<ordered_sum leverage
)
