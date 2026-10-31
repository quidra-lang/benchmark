sequential_sum =: 3 : 0
    total =. 0.0
    for_value. y do. total =. total+value end.
    total
)
mean =: 3 : '(+/y)%100*#y'
doubled_median =: 3 : 0
    ordered =. /:~y
    count =. #ordered
    first =. ((count+1)div 2)-1
    second =. ((count+2)div 2)-1
    (first{ordered)+second{ordered
)
median =: 3 : '(doubled_median y)%200'
trim_count =: 3 : 'y div 10'
trimmed_mean =: 3 : 0
    trim =. trim_count #y
    count =. (#y)-2*trim
    (+/count{.trim}./:~y)%100*count
)
deviations =: 3 : '(y%100)-mean y'
sd =: 3 : 0
    differences =. deviations y
    %:(sequential_sum differences*differences)%<:#y
)
central_moments =: 3 : 0
    second =. third =. fourth =. 0.0
    for_value. deviations y do.
        square =. value*value
        cube =. square*value
        second =. second+square
        third =. third+cube
        fourth =. fourth+cube*value
    end.
    (second,third,fourth)%#y
)
mad =: 3 : '(doubled_median |(2*y)-doubled_median y)%400'
quantile_numerator =: 4 : 0
    ordered =. /:~y
    position =. (<:#ordered)*x
    index =. position div 100
    fraction =. position-100*index
    base =. 100*index{ordered
    if. fraction=0 do. base return. end.
    base+fraction*((index+1){ordered)-index{ordered
)
winsorized =: 3 : 0
    ordered =. /:~y
    trim =. trim_count #y
    low =. trim{ordered
    high =. (((#y)-1)-trim){ordered
    high<.low>.y
)
mean_difference =: 4 : '(((#y)*+/x)-(#x)*+/y)%((100*#x)*#y)'
median_ratio =: 4 : '(doubled_median x)%doubled_median y'
hodges_lehmann =: 4 : '(doubled_median ,x-/y)%200'
pooled_sd =: 4 : 0
    first =. sd x
    second =. sd y
    squares =. (((<:#x)*first)*first)+((<:#y)*second)*second
    %:squares%((#x)+#y)-2
)
cohen_d =: 4 : '(x mean_difference y)%x pooled_sd y'
correlation =: 4 : 0
    first =. deviations x
    second =. deviations y
    products =. sequential_sum first*second
    squares =. (sequential_sum first*first)*sequential_sum second*second
    products%%:squares
)
resample_indices =: 3 : 0
    indices =. 0$0
    for_index. i.y do. indices =. indices,draw_below y end.
    indices
)
ordinary_indices =: 4 : 0
    result =. (0,x)$0
    for_replicate. i.y do. result =. result,resample_indices x end.
    result
)
balanced_indices =: 4 : 0
    indices =. shuffle ,(y,x)$i.x
    (y,x)$indices
)
without =: 4 : '(x~:i.#y)#y'
mean_and_se =: 3 : 0
    average =. (sequential_sum y)%#y
    differences =. y-average
    average,%:(sequential_sum differences*differences)%<:#y
)
phi =: 3 : 0
    if. y<0 do. 1-phi -y return. end.
    eta =. 1%1+0.2316419*y
    psi =. eta*(0.319381530+eta*(_0.356563782+eta*(1.781477937+eta*(_1.821255978+eta*1.330274429))))
    1-(0.3989422804014327*^(-(y*y)%2))*psi
)
phi_inverse =: 3 : 0
    if. y>0.5 do. -phi_inverse 1-y return. end.
    eta =. %:_2*^.y
    numerator =. 2.515517+eta*(0.802853+eta*0.010328)
    denominator =. 1+eta*(1.432788+eta*(0.189269+eta*0.001308))
    -(eta-numerator%denominator)
)
group_statistics =: 3 : '(mean y),(median y),(trimmed_mean y),sd y'
pair_statistics =: 4 : '(x mean_difference y),(x median_ratio y),(x hodges_lehmann y),x cohen_d y'
