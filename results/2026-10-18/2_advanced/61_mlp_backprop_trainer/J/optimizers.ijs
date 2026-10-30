optimizer_initial =: 3 : 0
    zero =. y$0.0
    (<zero),(<zero),(<zero),(<1.0),<1.0
)
optimizer_rate =: 4 : 0
    rate =. 3{::x
    for_index. i.<.(y-1)%RateStep do. rate =. rate*RateGamma end.
    rate
)
optimizer_update =: 3 : 0
    'theta gradient state run rate' =. y
    'velocity first second power1 power2' =. state
    kind =. 2{::run
    extra =. 5{::run
    if. kind-:'SGD' do.
        theta =. theta-rate*gradient
    elseif. kind-:'MOMENTUM' do.
        velocity =. ((0{extra)*velocity)+gradient
        theta =. theta-rate*velocity
    else.
        'beta1 beta2 epsilon' =. extra
        power1 =. power1*beta1
        power2 =. power2*beta2
        first =. (beta1*first)+(1-beta1)*gradient
        second =. (beta2*second)+((1-beta2)*gradient)*gradient
        corrected_first =. first%(1-power1)
        corrected_second =. second%(1-power2)
        theta =. theta-(rate*corrected_first)%((%:corrected_second)+epsilon)
    end.
    updated =. (<velocity),(<first),(<second),(<power1),<power2
    (<theta),<updated
)
