capability_indices =: 4 : 0
    lsl =. 'lsl' get_key Settings
    usl =. 'usl' get_key Settings
    potential =. (real usl-lsl)%(6.0*y)
    upper =. (usl-x)%(3.0*y)
    lower =. (x-lsl)%(3.0*y)
    potential,upper,lower,upper<.lower
)
confidence_interval =: 4 : 0
    first =. 1.0%(9.0*real y)
    second =. (x*x)%(2.0*real y-1)
    delta =. ('ci_z' get_key Settings)*%:first+second
    (x-delta),x+delta
)
capability_verdict =: 3 : 0
    if. y>:!.0 1.33 do. 'capable'
    elseif. y>:!.0 1.0 do. 'marginal'
    else. 'incapable' end.
)
histogram_rows =: 3 : 0
    width =. 'histogram_bin' get_key Settings
    low =. width*((<./y)<.'lsl' get_key Settings) div width
    high =. width+width*((>./y)>.'usl' get_key Settings) div width
    frequencies =. ((high-low) div width)$0
    for_value. y do.
        index =. (value-low) div width
        frequencies =. (1+index{frequencies) index}frequencies
    end.
    top =. >./frequencies
    bins =. 0$a:
    for_index. i.#frequencies do.
        lower =. low+index*width
        upper =. lower+width-1
        frequency =. index{frequencies
        length =. ((50*frequency)+top-1) div top
        marks =. 0$a:
        for_namebox. ' ' split 'lsl target usl' do.
            point =. (>namebox) get_key Settings
            if. (point>:lower)*.point<:upper do. marks =. marks,namebox end.
        end.
        bins =. bins,<'lower upper frequency length marks' record (<lower),(<upper),(<frequency),(<length),<marks
    end.
    bins
)
capability =: 3 : 0
    values =. 0$0
    for_box. y do. values =. values,'values' get_key >box end.
    count =. #values
    mean =. (real +/values)%real count
    rbar =. (real +/'range' subgroup_totals y)%real #y
    sbar =. (real_sum 'sd' subgroup_totals y)%real #y
    within =. rbar%'d2' get_key Constants
    sbarsigma =. sbar%'c4' get_key Constants
    differences =. values-mean
    squares =. real_sum differences*differences
    overall =. %:squares%real count-1
    cp =. mean capability_indices within
    pp =. mean capability_indices overall
    offset =. mean-'target' get_key Settings
    width =. real ('usl' get_key Settings)-'lsl' get_key Settings
    cpm =. width%(6.0*%:(overall*overall)+offset*offset)
    cpkci =. (3{cp) confidence_interval count
    ppkci =. (3{pp) confidence_interval count
    below =. +/values<'lsl' get_key Settings
    above =. +/values>'usl' get_key Settings
    ppm =. (real 1000000*below+above)%real count
    result =. 'count mean sigma_within sigma_sbar sigma_overall' record (<count),(<mean),(<within),(<sbarsigma),<overall
    updates =. 'cp cpu cpl cpk pp ppu ppl ppk' record <"0 cp,pp
    for_row. updates do. result =. row put_key result end.
    updates =. 'cpm cpk_ci ppk_ci below above ppm verdict bins' record (<cpm),(<cpkci),(<ppkci),(<below),(<above),(<ppm),(<capability_verdict 3{cp),<histogram_rows values
    for_row. updates do. result =. row put_key result end.
    result
)
