load 'dataset.ijs'
load 'selection.ijs'
load 'kernels.ijs'
load 'loess.ijs'
load 'spline.ijs'
join =: 4 : 0
    result =. ''
    for_index. i.#y do.
        if. index do.
            result =. result,x
        end.
        result =. result,index{::y
    end.
    result
)
text =: 3 : 0
    if. 2=3!:0 y do.
        y return.
    end.
    result =. ":y
    '-'(I.result='_')}result
)
real =: 3 : 0
    result =. 0j4":y
    result =. result#~result~:' '
    if. result-:'_0.0000' do.
        result =. '0.0000'
    end.
    '-'(I.result='_')}result
)
real2 =: 3 : 0
    result =. 0j2":y
    result =. result#~result~:' '
    if. result-:'_0.00' do.
        result =. '0.00'
    end.
    '-'(I.result='_')}result
)
maybe_real =: 4 : 0
    if. x do.
        real y
    else.
        'NA'
    end.
)
position_text =: 3 : 0
    sign =. ''
    if. y<0 do.
        sign =. '-'
    end.
    magnitude =. |y
    fraction =. text 100|magnitude
    sign,(text <.magnitude%100),'.',((2-#fraction)#'0'),fraction
)
reals =: 3 : ''' ''join real&.>y'
line =: 3 : ''' ''join text&.>y'
m_name =: 0&{::
m_positions =: 1&{::
m_numbers =: 2&{::
m_values =: 3&{::
m_fitted =: 4&{::
m_leverage =: 5&{::
m_has_edf =: 6&{::
m_edf =: 7&{::
m_extra =: 8&{::
pava =: 4 : 0
    blocks =. 0 4$0
    for_index. i.#y do.
        blocks =. blocks,index,index,(index{y),1
        while. 1<#blocks do.
            a =. _2{blocks
            b =. {:blocks
            left =. (2{a)*3{b
            right =. (2{b)*3{a
            violates =. left>right
            if. x-:'decreasing' do.
                violates =. left<right
            end.
            if. -.violates do.
                break.
            end.
            merged =. (0{a),(1{b),((2{a)+2{b),((3{a)+3{b)
            blocks =. (_2}.blocks),merged
        end.
    end.
    fitted =. (#y)$0.0
    for_block. blocks do.
        'first last sum count' =. block
        selected =. first+i.1+last-first
        fitted =. (sum%100*count)selected}fitted
    end.
    (<fitted),<blocks
)
fit_model =: 3 : 0
    'method parameter points mode robust diagnostics' =. y
    positions =. 0{"1 points
    numbers =. 1{"1 points
    values =. numbers%100
    count =. #points
    fitted =. i.0
    leverage =. i.0
    has_edf =. 1
    edf =. 0.0
    extras =. i.0
    if. method-:'linear' do.
        x =. positions%100
        xbar =. (ordered_sum x)%count
        ybar =. (ordered_sum values)%count
        sxx =. 0.0
        sxy =. 0.0
        for_index. i.count do.
            dx =. (index{x)-xbar
            sxx =. sxx+dx*dx
            sxy =. sxy+dx*((index{values)-ybar)
        end.
        slope =. sxy%sxx
        intercept =. ybar-slope*xbar
        fitted =. intercept+slope*x
        leverage =. (1%count)+(*:x-xbar)%sxx
        edf =. 2.0
        extras =. xbar,sxx,slope,intercept
    elseif. ('running_mean'-:method)+.'running_median'-:method do.
        half =. <.((num parameter)-1)%2
        windows =. 0 2$0
        for_index. i.count do.
            radius =. half<.index<.(count-1)-index
            selected =. (index-radius)+i.1+2*radius
            sample =. selected{numbers
            windows =. windows,(index-radius),index+radius
            value =. (+/sample)%100*#sample
            if. method-:'running_median' do.
                value =. (radius{/:~sample)%100
            end.
            fitted =. fitted,value
            leverage =. leverage,1%#sample
        end.
        has_edf =. method-:'running_mean'
        edf =. ordered_sum leverage
        extras =. windows
    elseif. method-:'isotonic' do.
        direction =. mode
        rss_increasing =. 0.0
        rss_decreasing =. 0.0
        if. mode-:'auto' do.
            increasing =. 'increasing'pava numbers
            decreasing =. 'decreasing'pava numbers
            rss_increasing =. values residual_square 0{::increasing
            rss_decreasing =. values residual_square 0{::decreasing
            direction =. 'increasing'
            fit =. increasing
            if. rss_decreasing<rss_increasing do.
                direction =. 'decreasing'
                fit =. decreasing
            end.
        else.
            fit =. mode pava numbers
        end.
        'fitted blocks' =. fit
        edf =. 0.0+#blocks
        extras =. (<direction),(<mode),(<blocks),(<rss_increasing),<rss_decreasing
    elseif. ((3{.method)-:'nw_')+.(3{.method)-:'ll_' do.
        extras =. kernel_fit (<positions),(<values),(<hundredths parameter),(<3}.method),(<(3{.method)-:'ll_'),<diagnostics
        fitted =. 5{::extras
        leverage =. 6{::extras
        has_edf =. 7{::extras
        edf =. 8{::extras
    elseif. 'loess'-:5{.method do.
        iterations =. 0
        if. robust do.
            iterations =. RobustIterations
        end.
        extras =. loess_fit (<positions),(<values),(<hundredths parameter),(<num 5}.method),(<iterations),<diagnostics
        fitted =. 5{::extras
        leverage =. 6{::extras
        edf =. 7{::extras
    else.
        extras =. spline_fit (<positions),(<values),(<num parameter),<diagnostics
        fitted =. 7{::extras
        leverage =. 10{::extras
        edf =. 11{::extras
    end.
    (<method),(<positions),(<numbers),(<values),(<fitted),(<leverage),(<has_edf),(<edf),<extras
)
model_evaluate =: 4 : 0
    'position need_weights' =. y
    name =. m_name x
    positions =. m_positions x
    count =. #positions
    extra =. m_extra x
    weights =. i.0
    if. name-:'linear' do.
        'xbar sxx slope intercept' =. extra
        estimate =. intercept+slope*position%100
        if. need_weights do.
            weights =. (1%count)+(((position%100)-xbar)*((positions%100)-xbar))%sxx
        end.
    elseif. ('running_mean'-:name)+.'running_median'-:name do.
        distance =. |positions-position
        nearest =. distance i.<./distance
        estimate =. nearest{m_fitted x
        if. need_weights do.
            'first last' =. nearest{extra
            selected =. first+i.1+last-first
            weights =. (1%#selected)selected}count$0.0
        end.
    elseif. name-:'isotonic' do.
        selected =. 0>.(_1++/positions<:position)
        estimate =. selected{m_fitted x
    elseif. ((3{.name)-:'nw_')+.(3{.name)-:'ll_' do.
        extra kernel_evaluate position return.
    elseif. 'loess'-:5{.name do.
        'estimate ignored weights' =. extra loess_local position
    else.
        estimate =. extra spline_estimate position
        if. need_weights do.
            weights =. extra spline_weights position
        end.
    end.
    (<1),(<estimate),<weights
)
validation =: 3 : 0
    'method parameter points direction folds' =. y
    predictions =. (#points)$0.0
    defined =. (#points)$0
    for_group. i.folds do.
        training =. ((group~:folds|i.#points)#i.#points){points
        model =. fit_model (<method),(<parameter),(<training),(<direction),(<0),<0
        for_index. group+folds*i.>.((#points)-group)%folds do.
            'valid estimate weights' =. model model_evaluate ((<index,0){points),0
            predictions =. estimate index}predictions
            defined =. valid index}defined
        end.
    end.
    ((1{"1 points)%100)cross_validation_score (<predictions),<defined
)
parameters =: 3 : 0
    if. 'running_'-:8{.y do.
        Windows
    elseif. ((3{.y)-:'nw_')+.(3{.y)-:'ll_' do.
        Bandwidths
    elseif. 'loess'-:5{.y do.
        Spans
    elseif. y-:'spline' do.
        Lambdas
    else.
        0$a:
    end.
)
e_name =: 0&{::
e_parameter =: 1&{::
e_model =: 2&{::
e_loo =: 3&{::
e_kfold =: 4&{::
e_candidates =: 5&{::
e_gcv =: 6&{::
e_grid =: 7&{::
e_stats =: 8&{::
select_models =: 4 : 0
    points =. x
    mode =. y
    observed =. (1{"1 points)%100
    entries =. 0$a:
    for_box. Methods do.
        name =. >box
        candidates =. 0$a:
        scores =. i.0
        valid_scores =. i.0
        for_parameter_box. parameters name do.
            parameter =. >parameter_box
            candidate =. fit_model (<name),(<parameter),(<points),(<mode),(<0),<1
            if. name-:'spline' do.
                valid =. 1
                score =. observed generalized_score (<m_fitted candidate),<m_edf candidate
            else.
                'valid score' =. validation (<name),(<parameter),(<points),(<mode),<#points
            end.
            candidates =. candidates,<(<parameter),(<valid),(<score),(<m_has_edf candidate),(<m_edf candidate),<0
            scores =. scores,score
            valid_scores =. valid_scores,valid
        end.
        best =. _1
        parameter =. '-'
        if. name-:'isotonic' do.
            parameter =. mode
        end.
        if. #candidates do.
            best =. scores choose_candidate valid_scores
            candidate =. best{::candidates
            parameter =. 0{::candidate
            candidate =. (<1)5}candidate
            candidates =. (<candidate)best}candidates
        end.
        model =. fit_model (<name),(<parameter),(<points),(<mode),(<1),<1
        direction =. mode
        if. name-:'isotonic' do.
            direction =. 0{::m_extra model
            parameter =. direction
        end.
        if. (best>:0)*.-.name-:'spline' do.
            loo =. best{scores
        else.
            'valid loo' =. validation (<name),(<parameter),(<points),(<direction),<#points
        end.
        kfold =. validation (<name),(<parameter),(<points),(<direction),<Folds
        gcv =. 0.0
        if. name-:'spline' do.
            gcv =. best{scores
        end.
        entries =. entries,<(<name),(<parameter),(<model),(<loo),(<kfold),(<candidates),(<gcv),(<0$a:),<0$a:
    end.
    entries
)
quantiles =: 3 : 0
    ordered =. /:~y
    result =. i.0
    for_k. i.5 do.
        numerator =. ((#ordered)-1)*k
        index =. <.numerator%4
        remainder =. 4|numerator
        value =. index{ordered
        if. remainder do.
            value =. value+(remainder%4)*((index+1){ordered)-index{ordered
        end.
        result =. result,value
    end.
    result
)
diagnostics =: 4 : 0
    entry =. x
    linear_rss =. y
    model =. e_model entry
    observed =. m_values model
    residuals =. observed-m_fitted model
    count =. #observed
    rss =. ordered_sum *:residuals
    mean =. (ordered_sum observed)%count
    tss =. ordered_sum *:observed-mean
    has_edf =. m_has_edf model
    edf =. m_edf model
    df =. 0.0
    rse =. 0.0
    has_nonlinear =. 0
    nonlinear =. 0.0
    if. has_edf do.
        df =. count-edf
        rse =. %:rss%df
        has_nonlinear =. (-.'linear'-:e_name entry)*.edf>2
        if. has_nonlinear do.
            nonlinear =. ((linear_rss-rss)%(edf-2))%(rss%df)
        end.
    end.
    centered =. residuals-(ordered_sum residuals)%count
    denominator =. ordered_sum *:centered
    acf =. i.0
    for_lag. 1+i.5 do.
        sum =. 0.0
        for_index. i.count-lag do.
            sum =. sum+(index{centered)*(index+lag){centered
        end.
        acf =. acf,sum%denominator
    end.
    dw =. 0.0
    for_index. 1+i.count-1 do.
        difference =. (index{residuals)-(index-1){residuals
        dw =. dw+difference*difference
    end.
    largest =. (|residuals)i.>./|residuals
    signs =. *residuals#~residuals~:0
    positive =. +/signs>0
    negative =. +/signs<0
    runs =. 1++/(}.signs)~:}:signs
    nonzero =. positive+negative
    product =. 2*positive*negative
    runs_mean =. 1+product%nonzero
    variance =. (product*(product-nonzero))%((nonzero*nonzero)*(nonzero-1))
    defined_values =. i.0
    for_estimate_box. e_grid entry do.
        'valid estimate weights' =. >estimate_box
        if. valid do.
            defined_values =. defined_values,estimate
        end.
    end.
    differences =. (}.defined_values)-}:defined_values
    differences =. differences#~differences~:0
    turning =. +/(*(}.differences))~:*}:differences
    (<residuals),(<rss),(<has_edf),(<edf),(<df),(<rse),(<1-rss%tss),(<has_nonlinear),(<nonlinear),(<acf),(<dw%rss),(<runs),(<positive),(<negative),(<(runs-runs_mean)%%:variance),(<largest),(<quantiles residuals),<turning
)
random_index =: 3 : 0
    BootstrapState =: 2147483647|48271x*BootstrapState
    y|BootstrapState
)
a_points =: 0&{::
a_grid =: 1&{::
a_entries =: 2&{::
a_ranking =: 3&{::
a_agreements =: 4&{::
a_slope =: 5&{::
a_outlier =: 6&{::
a_bands =: 7&{::
a_summaries =: 8&{::
analyze =: 4 : 0
    points =. x
    positions =. 0{"1 points
    count =. #points
    grid =. ({.positions)+<.((i.GridPoints)*({:positions)-{.positions)%(GridPoints-1)
    entries =. points select_models y
    linear_rss =. (m_values e_model 0{::entries)residual_square m_fitted e_model 0{::entries
    scores =. i.0
    for_index. i.#entries do.
        entry =. index{::entries
        estimates =. 0$a:
        for_position. grid do.
            estimates =. estimates,<(e_model entry)model_evaluate position,0
        end.
        entry =. (<estimates)7}entry
        entry =. (<entry diagnostics linear_rss)8}entry
        entries =. (<entry)index}entries
        scores =. scores,e_loo entry
    end.
    ranking =. /:scores
    agreements =. 0$a:
    best =. e_grid ({.ranking){::entries
    for_entry_box. entries do.
        own =. e_grid >entry_box
        used =. 0
        sum =. 0.0
        maximum =. _1.0
        at =. 0
        for_index. i.#grid do.
            a =. index{::own
            b =. index{::best
            if. (0{::a)*.0{::b do.
                delta =. |(1{::a)-1{::b
                used =. used+1
                sum =. sum+delta*delta
                if. delta>maximum do.
                    maximum =. delta
                    at =. index
                end.
            end.
        end.
        agreements =. agreements,<used,(%:sum%used),maximum,at{grid
    end.
    spline_index =. Methods i.<'spline'
    spline_entry =. spline_index{::entries
    spline_values =. 1&{::&>e_grid spline_entry
    slopes =. i.0
    for_index. 1+i.(#grid)-2 do.
        slope =. ((index+1){spline_values)-(index-1){spline_values
        slope =. slope%(((index+1){grid)-(index-1){grid)%100
        slopes =. slopes,slope
    end.
    maximum =. slopes i.>./slopes
    minimum =. slopes i.<./slopes
    slope =. (maximum{slopes),((maximum+1){grid),(minimum{slopes),(minimum+1){grid
    outlier_method =. _1
    for_index. ranking do.
        if. -.((e_name index{::entries)-:'isotonic')+.((e_name index{::entries)-:'running_median') do.
            outlier_method =. index
            break.
        end.
    end.
    entry =. outlier_method{::entries
    model =. e_model entry
    stats =. e_stats entry
    standardized =. count$0.0
    defined =. count$0
    cooks =. count$0.0
    outliers =. i.0
    influential =. i.0
    for_index. i.count do.
        leverage =. index{m_leverage model
        if. leverage<1 do.
            value =. (index{0{::stats)%((5{::stats)*%:1-leverage)
            standardized =. value index}standardized
            defined =. 1 index}defined
            distance =. ((value*value)*leverage)%((1-leverage)*m_edf model)
            cooks =. distance index}cooks
            influential =. influential,index
            if. (|value)>Threshold do.
                outliers =. outliers,index
            end.
        end.
    end.
    outliers =. (/:-(|outliers{standardized)){outliers
    influential =. (/:-(influential{cooks)){influential
    influential =. (3<.#influential){.influential
    outlier =. (<outlier_method),(<standardized),(<defined),(<cooks),(<outliers),<influential
    bands =. 0$a:
    summaries =. 0$a:
    for_method_box. BandMethods do.
        index =. Methods i.method_box
        entry =. index{::entries
        model =. e_model entry
        stats =. e_stats entry
        rse =. 5{::stats
        rows =. 0 5$0.0
        se_sum =. 0.0
        used =. 0
        covered =. 0
        for_position. grid do.
            'valid value weights' =. model model_evaluate position,1
            row =. 5$0.0
            if. valid do.
                se =. rse*%:ordered_sum *:weights
                row =. 1,value,se,(value-BandZ*se),value+BandZ*se
                used =. used+1
                se_sum =. se_sum+se
            end.
            rows =. rows,row
        end.
        for_index. i.count do.
            'valid value weights' =. model model_evaluate (index{positions),1
            se =. rse*%:ordered_sum *:weights
            if. (|index{0{::stats)<:BandZ*%:(rse*rse)+se*se do.
                covered =. covered+1
            end.
        end.
        bands =. bands,<rows
        summaries =. summaries,<(se_sum%used),covered
    end.
    spline_model =. m_extra e_model spline_entry
    fitted =. m_fitted e_model spline_entry
    residuals =. 0{::e_stats spline_entry
    centered =. residuals-(ordered_sum residuals)%count
    estimates =. 0$a:
    for_position. grid do.
        estimates =. estimates,<i.0
    end.
    for_repetition. i.Bootstrap do.
        response =. i.0
        for_index. i.count do.
            response =. response,(index{fitted)+(random_index count){centered
        end.
        fit =. spline_model spline_fit_values response
        for_index. i.#grid do.
            value =. spline_model spline_evaluate_fit (fit),<index{grid
            estimates =. (<(index{::estimates),value)index}estimates
        end.
    end.
    rows =. 0 5$0.0
    for_index. i.#grid do.
        values =. index{::estimates
        mean =. (ordered_sum values)%Bootstrap
        se =. %:(ordered_sum *:values-mean)%(Bootstrap-1)
        ordered =. /:~values
        rows =. rows,1,(index{spline_values),se,(Trim{ordered),((Bootstrap-Trim)-1){ordered
    end.
    bands =. bands,<rows
    (<points),(<grid),(<entries),(<ranking),(<agreements),(<slope),(<outlier),(<bands),<summaries
)
diagnostic_block =: 4 : 0
    name =. x
    analysis =. y
    points =. a_points analysis
    entries =. a_entries analysis
    positions =. 0{"1 points
    numbers =. 1{"1 points
    lines =. ,<'series ',name,' n ',(text #points),' x ',(position_text {.positions),' ',(position_text {:positions),' y ',(position_text <./numbers),' ',position_text >./numbers
    for_box. entries do.
        entry =. >box
        model =. e_model entry
        stats =. e_stats entry
        'residuals rss has_edf edf df rse r2 has_nonlinear nonlinear acf dw runs positive negative runs_z largest quartiles turning' =. stats
        first =. 'method ',(e_name entry),' parameter ',(e_parameter entry),' loo ',real e_loo entry
        if. 'spline'-:e_name entry do.
            first =. first,' gcv ',real e_gcv entry
        end.
        lines =. lines,<first
        lines =. lines,<'  rss ',(real rss),' edf ',(has_edf maybe_real edf),' df ',(has_edf maybe_real df),' rse ',(has_edf maybe_real rse),' r2 ',(real r2),' f_nonlinear ',has_nonlinear maybe_real nonlinear
        lines =. lines,<'  acf ',(reals acf),' dw ',real dw
        lines =. lines,<'  runs ',(text runs),' positive ',(text positive),' negative ',(text negative),' z ',real runs_z
        lines =. lines,<'  max_residual ',(real largest{residuals),' at ',(position_text largest{positions),' turning ',text turning
        lines =. lines,<'  quantiles ',reals quartiles
        if. 'loess'-:5{.e_name entry do.
            extra =. m_extra model
            for_record. 8{::extra do.
                'iteration scale zeros change' =. record
                lines =. lines,<'  robust ',(text iteration),' scale ',(real scale),' zero_weight ',(text zeros),' max_change ',real change
            end.
            zeros =. I.0=4{::extra
            value =. 'none'
            if. #zeros do.
                value =. ' 'join position_text&.>zeros{positions
            end.
            lines =. lines,<'  zero_weight_points ',value
        end.
    end.
    ranking =. a_ranking analysis
    lines =. lines,<'ranking'
    for_rank. i.#ranking do.
        entry =. (rank{ranking){::entries
        'valid score' =. e_kfold entry
        lines =. lines,<'  ',(text rank+1),' ',(e_name entry),' ',(real e_loo entry),' kfold ',valid maybe_real score
    end.
    lines =. lines,<'agreement with ',({.ranking){::Methods
    for_index. i.#Methods do.
        if. index~:{.ranking do.
            'count rms maximum at' =. index{::a_agreements analysis
            lines =. lines,<'  ',(index{::Methods),' points ',(text count),' rms ',(real rms),' max ',(real maximum),' at ',position_text at
        end.
    end.
    'maximum at_max minimum at_min' =. a_slope analysis
    lines =. lines,<'slope spline max ',(real maximum),' at ',(position_text at_max),' min ',(real minimum),' at ',position_text at_min
    'method standardized defined cooks outliers influential' =. a_outlier analysis
    entry =. method{::entries
    model =. e_model entry
    residuals =. 0{::e_stats entry
    lines =. lines,<'outliers method ',(e_name entry),' threshold ',real2 Threshold
    for_index. outliers do.
        lines =. lines,<'  x ',(position_text index{positions),' y ',(position_text index{numbers),' fit ',(real index{m_fitted model),' residual ',(real index{residuals),' standardized ',real index{standardized
    end.
    if. 0=#outliers do.
        lines =. lines,<'  none'
    end.
    lines =. lines,<'influence method ',e_name entry
    for_index. influential do.
        lines =. lines,<'  x ',(position_text index{positions),' lev ',(real index{m_leverage model),' cook ',real index{cooks
    end.
    lines =. lines,<'bands'
    for_index. i.#BandMethods do.
        'mean covered' =. index{::a_summaries analysis
        lines =. lines,<'  ',(index{::BandMethods),' mean_se ',(real mean),' coverage ',(text covered),' of ',text #points
    end.
    lines
)
isotonic_block =: 4 : 0
    entry =. (Methods i.<'isotonic'){::a_entries y
    model =. e_model entry
    'direction mode blocks rss_increasing rss_decreasing' =. m_extra model
    first =. 'series ',x,' direction ',direction,' mode ',mode
    if. mode-:'auto' do.
        first =. first,' rss_increasing ',(real rss_increasing),' rss_decreasing ',real rss_decreasing
    end.
    lines =. (<first),<'blocks ',(text #blocks),' rss ',(real 1{::e_stats entry),' loo ',real e_loo entry
    positions =. m_positions model
    for_index. i.#blocks do.
        'first last sum count' =. index{blocks
        lines =. lines,<'block ',(text index+1),' x ',(position_text first{positions),' ',(position_text last{positions),' count ',(text count),' value ',real sum%100*count
    end.
    lines
)
framed =: 3 : 0
    border =. '+',((#0{y)#'-'),'+'
    lines =. ,<border
    for_row. y do.
        lines =. lines,<'|',row,'|'
    end.
    lines,<border
)
clamp_row =: 3 : '0>.(PlotHeight-1)<.<.y'
plot_block =: 4 : 0
    name =. x
    analysis =. y
    points =. a_points analysis
    entries =. a_entries analysis
    positions =. 0{"1 points
    numbers =. 1{"1 points
    xa =. {.positions
    xb =. {:positions
    ya =. <./numbers
    yb =. >./numbers
    columns =. (PlotWidth-1)<.<.(PlotWidth*(positions-xa))%(xb-xa)
    grid =. (PlotHeight,PlotWidth)$' '
    for_index. i.#points do.
        row =. (PlotHeight-1)<.<.(PlotHeight*(yb-index{numbers))%(yb-ya)
        grid =. '.'(<row,index{columns)}grid
    end.
    legend =. 'legend . data'
    for_index. i.#PlotMethods do.
        method =. index{::PlotMethods
        digit =. {.text index+1
        legend =. legend,' ',(text index+1),' ',method
        model =. e_model (Methods i.<method){::entries
        for_column. i.PlotWidth do.
            position =. xa+<.(((2*column)+1)*(xb-xa))%(2*PlotWidth)
            'valid estimate weights' =. model model_evaluate position,0
            if. valid do.
                pi =. (PlotHeight*((yb%100)-estimate))%((yb%100)-ya%100)
                row =. clamp_row pi
                old =. (<row,column){grid
                value =. '*'
                if. old e.' .',digit do.
                    value =. digit
                end.
                grid =. value (<row,column)}grid
            end.
        end.
    end.
    lines =. (<'plot ',name,' size ',(text PlotWidth),'x',(text PlotHeight),' x ',(position_text xa),' ',(position_text xb),' y ',(position_text ya),' ',position_text yb),<legend
    lines =. lines,framed grid
    cells =. ,grid
    lines =. lines,<'cells data ',(text +/cells='.'),' curve ',(text +/cells e.'123456789'),' overlap ',text +/cells='*'
    best =. {.a_ranking analysis
    entry =. best{::entries
    residuals =. 0{::e_stats entry
    limit =. >./|residuals
    grid =. (PlotHeight,PlotWidth)$' '
    grid =. (PlotWidth#'-')(<.-:PlotHeight)}grid
    for_index. i.#points do.
        row =. clamp_row PlotHeight*(limit-index{residuals)%(2*limit)
        grid =. 'o'(<row,index{columns)}grid
    end.
    lines =. lines,(<''),<'residuals ',name,' method ',(e_name entry),' limit ',real limit
    lines =. lines,framed grid
    'method standardized defined cooks outliers influential' =. a_outlier analysis
    lines =. lines,(<''),<'histogram ',name,' method ',method{::Methods
    counts =. 14$0
    for_index. I.defined do.
        value =. index{standardized
        bucket =. 1+<.(value+3)%0.5
        if. value<_3 do.
            bucket =. 0
        elseif. value>:3 do.
            bucket =. 13
        end.
        counts =. (1+bucket{counts)bucket}counts
    end.
    for_index. i.14 do.
        lower =. '-inf'
        upper =. 'inf'
        if. index>0 do.
            lower =. real2 _3+0.5*(index-1)
        end.
        if. index<13 do.
            upper =. real2 _3+0.5*index
        end.
        lines =. lines,<lower,' ',upper,' ',(text index{counts),' |',(index{counts)#'#'
    end.
    lines
)
join_blocks =: 3 : 0
    result =. 0$a:
    for_index. i.#y do.
        if. index do.
            result =. result,<''
        end.
        result =. result,index{::y
    end.
    result
)
write_lines =: 4 : 0
    content =. ''
    for_row. y do.
        content =. content,(>row),LF
    end.
    content 1!:2 <'output/',x
)
run =: 3 : 0
    'names series requests' =. read_dataset 0
    Methods =: 'linear';'running_mean';'running_median'
    for_prefix. 'nw_';'ll_' do.
        for_kernel. Kernels do.
            Methods =: Methods,<(>prefix),>kernel
        end.
    end.
    for_degree. Degrees do.
        Methods =: Methods,<'loess',>degree
    end.
    Methods =: Methods,('spline';'isotonic')
    BootstrapState =: Seed
    analyses =. 0$a:
    for_index. i.#names do.
        analyses =. analyses,<(index{::series)analyze index{::IsotonicModes
    end.
    selection_output =. ,<'series,method,parameter,score,edf,selected'
    fits_output =. ,<'series,x,',','join Methods
    predictions_output =. fits_output
    bands_output =. ,<'series,method,x,fit,se,lower,upper'
    diagnostic_blocks =. 0$a:
    isotonic_blocks =. 0$a:
    for_index. i.#names do.
        name =. index{::names
        analysis =. index{::analyses
        entries =. a_entries analysis
        grid =. a_grid analysis
        for_entry_box. entries do.
            entry =. >entry_box
            for_candidate_box. e_candidates entry do.
                'parameter valid score has_edf edf selected' =. >candidate_box
                fields =. (<name),(<e_name entry),(<parameter),(<valid maybe_real score),(<has_edf maybe_real edf),<text selected
                selection_output =. selection_output,<','join fields
            end.
        end.
        for_point. i.#grid do.
            fields =. (<name),<position_text point{grid
            for_entry_box. entries do.
                'valid estimate weights' =. point{::e_grid >entry_box
                fields =. fields,<valid maybe_real estimate
            end.
            fits_output =. fits_output,<','join fields
        end.
        band_methods =. BandMethods,<'spline_bootstrap'
        for_method. i.#band_methods do.
            rows =. method{::a_bands analysis
            for_point. i.#grid do.
                'valid fit se lower upper' =. point{rows
                fields =. (<name),(<method{::band_methods),(<position_text point{grid),(<valid maybe_real fit),(<valid maybe_real se),(<valid maybe_real lower),<valid maybe_real upper
                bands_output =. bands_output,<','join fields
            end.
        end.
        diagnostic_blocks =. diagnostic_blocks,<name diagnostic_block analysis
        isotonic_blocks =. isotonic_blocks,<name isotonic_block analysis
    end.
    for_request_box. requests do.
        'name position' =. >request_box
        analysis =. (names i.<name){::analyses
        fields =. (<name),<position_text position
        for_entry_box. a_entries analysis do.
            'valid estimate weights' =. (e_model >entry_box)model_evaluate position,0
            fields =. fields,<valid maybe_real estimate
        end.
        predictions_output =. predictions_output,<','join fields
    end.
    plot_blocks =. 0$a:
    for_name_box. PlotSeries do.
        name =. >name_box
        analysis =. (names i.<name){::analyses
        plot_blocks =. plot_blocks,<name plot_block analysis
    end.
    try.
        1!:5 <'output'
    catch.
    end.
    'selection.csv'write_lines selection_output
    'fits.csv'write_lines fits_output
    'predictions.csv'write_lines predictions_output
    'bands.csv'write_lines bands_output
    'diagnostics.txt'write_lines join_blocks diagnostic_blocks
    'isotonic.txt'write_lines join_blocks isotonic_blocks
    'plots.txt'write_lines join_blocks plot_blocks
    i.0 0
)
run 0
