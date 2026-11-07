split =: 4 : '<;._1 x,y'
join =: 4 : 0
    result =. ''
    for_i. i.#y do.
        if. i do.
            result =. result,x
        end.
        result =. result,i{::y
    end.
    result
)
num =: 3 : 'x: 0".y'
decimal =: 3 : '0".y'
intdiv =: 4 : '<.(x: x)%x: y'
text =: 3 : 0
    if. 2=3!:0 y do.
        y return.
    end.
    value =. ":y
    '-'(I.value='_')}value
)
line =: 3 : ''' ''join text&.>y'
load 'series_io.ijs'
load 'decomposition.ijs'
load 'smoothing.ijs'
load 'autoregression.ijs'
load 'evaluation.ijs'
reals =: 3 : ''' ''join real_text&.>y'
rmse =: 3 : '%:(total *:y)%#y'
m_name =: 0&{::
m_series =: 1&{::
m_season =: 2&{::
m_slope =: 3&{::
m_intercept =: 4&{::
m_residuals =: 5&{::
m_seasonal =: 6&{::
m_parameters =: 7&{::
m_states =: 8&{::
m_kind =: 9&{::
m_differenced =: 10&{::
m_offset =: 11&{::
m_average =: 12&{::
m_order =: 13&{::
m_variances =: 14&{::
m_sigma2 =: 15&{::
m_aic =: 16&{::
m_coefficients =: 17&{::
m_correlations =: 18&{::
m_partial =: 19&{::
sm_method =: 3 : '(<y)e.''ses'';''holt'';''damped'';''hw_add'';''hw_mult'''
decomposition_prediction =: 4 : 0
    base =. (m_intercept x)+(m_slope x)*(y+1)
    seasonal =. ((m_season x)|y){m_seasonal x
    if. 'decomp_add'-:m_name x do.
        base+seasonal
    else.
        base*seasonal
    end.
)
fit_ar =: 3 : 0
    model =. y
    values =. m_series model
    candidates =. 0$a:
    spreads =. i.0
    for_kind. i.4 do.
        'transformed offset' =. ar_difference (<values),(<Season),<kind
        'average spread correlations' =. transformed autocorrelation 0
        candidates =. candidates,<(<transformed),<offset
        spreads =. spreads,spread
    end.
    selected =. spreads i.<./spreads
    'transformed offset' =. selected{::candidates
    'average spread correlations' =. transformed autocorrelation MaxLag
    'coefficients partial variances' =. durbin_levinson correlations
    aic =. i.0
    for_order. i.MaxAR+1 do.
        aic =. aic,((#transformed)*^.spread*order{variances)+2*order
    end.
    order =. aic i.<./aic
    fitted =. order{::coefficients
    errors =. ar_residuals (<transformed),(<average),<fitted
    model =. (<errors)5}model
    model =. (<selected)9}model
    model =. (<transformed)10}model
    model =. (<offset)11}model
    model =. (<average)12}model
    model =. (<order)13}model
    model =. (<spreads)14}model
    model =. (<spread*order{variances)15}model
    model =. (<aic)16}model
    model =. (<fitted)17}model
    model =. (<correlations)18}model
    (<partial)19}model
)
fit_method =: 4 : 0
    name =. x
    values =. y
    model =. (<name),(<values),(<Season),(<0.0),(<0.0),(<i.0),(<i.0),(<0.0 0.0 0.0 1.0),(<0$a:),(<0),(<i.0),(<0),(<0.0),(<0),(<i.0),(<0.0),(<i.0),(<i.0),(<i.0),<i.0
    if. (<name)e.'naive';'snaive';'drift' do.
        offset =. 1
        slope =. 0.0
        if. name-:'snaive' do.
            offset =. Season
        end.
        if. name-:'drift' do.
            slope =. (({:values)-{.values)%<:#values
        end.
        errors =. i.0
        for_t. offset+i.(#values)-offset do.
            errors =. errors,((t{values)-(t-offset){values)-slope
        end.
        model =. (<slope)3}model
        model =. (<errors)5}model
    elseif. sm_method name do.
        betas =. Beta
        if. name-:'ses' do.
            betas =. ,0.0
        end.
        thirds =. ,0.0
        if. name-:'damped' do.
            thirds =. Phi
        elseif. (<name)e.'hw_add';'hw_mult' do.
            thirds =. Gamma
        end.
        found =. 0
        best =. 0.0
        for_alpha. Alpha do.
            for_beta. betas do.
                for_third. thirds do.
                    gamma =. 0.0
                    phi =. 1.0
                    if. name-:'damped' do.
                        phi =. third
                    elseif. (<name)e.'hw_add';'hw_mult' do.
                        gamma =. third
                    end.
                    parameters =. alpha,beta,gamma,phi
                    'errors states' =. recurse (<name),(<values),(<Season),<parameters
                    value =. total *:errors
                    if. (-.found)+.value<best do.
                        found =. 1
                        best =. value
                        model =. (<errors)5}model
                        model =. (<parameters)7}model
                        model =. (<states)8}model
                    end.
                end.
            end.
        end.
    elseif. (<name)e.'decomp_add';'decomp_mult' do.
        components =. Season decompose values
        indices =. d_multiplicative components
        if. name-:'decomp_add' do.
            indices =. d_additive components
        end.
        adjusted =. i.0
        for_t. i.#values do.
            index =. (Season|t){indices
            if. name-:'decomp_add' do.
                value =. (t{values)-index
            else.
                value =. (t{values)%index
            end.
            adjusted =. adjusted,value
        end.
        'intercept slope' =. least_squares_line adjusted
        model =. (<slope)3}model
        model =. (<intercept)4}model
        model =. (<indices)6}model
        errors =. i.0
        for_t. i.#values do.
            errors =. errors,(t{values)-model decomposition_prediction t
        end.
        model =. (<errors)5}model
    else.
        model =. fit_ar model
    end.
    model
)
forecast_one =: 3 : 0
    'model origin steps' =. y
    name =. m_name model
    values =. m_series model
    season =. m_season model
    if. name-:'naive' do.
        steps$(origin-1){values return.
    end.
    if. name-:'snaive' do.
        ((origin-season)+(season|i.steps)){values return.
    end.
    if. name-:'drift' do.
        slope =. (((origin-1){values)-{.values)%(origin-1)
        ((origin-1){values)+(1+i.steps)*slope return.
    end.
    if. sm_method name do.
        state =. origin{::m_states model
        sm_forecast (<name),(<state),(<m_parameters model),(<origin),(<steps),<season return.
    end.
    if. (<name)e.'decomp_add';'decomp_mult' do.
        result =. i.0
        for_t. origin+i.steps do.
            result =. result,model decomposition_prediction t
        end.
        result return.
    end.
    ar_forecast (<values),(<m_differenced model),(<m_offset model),(<m_kind model),(<m_average model),(<m_coefficients model),(<origin),(<steps),<season
)
forecast_members =: 3 : 0
    'members origin steps' =. y
    predictions =. (0,steps)$0.0
    for_model. members do.
        predictions =. predictions,forecast_one model,(<origin),<steps
    end.
    result =. i.0
    for_step. i.steps do.
        result =. result,(total step{"1 predictions)%#members
    end.
    result
)
cv_counts =: 0&{::
cv_sigma =: 1&{::
cv_mae =: 2&{::
cv_rmse =: 3&{::
cross_validate =: 3 : 0
    members =. y
    values =. m_series 0{::members
    counts =. Horizon$0
    squared =. absolute =. Horizon$0.0
    for_origin. CVStart+i.(#values)-CVStart do.
        steps =. Horizon<.(#values)-origin
        predictions =. forecast_members (<members),(<origin),<steps
        for_step. i.steps do.
            error =. ((origin+step){values)-step{predictions
            counts =. (>:(step{counts))step}counts
            squared =. ((step{squared)+error*error)step}squared
            absolute =. ((step{absolute)+|error)step}absolute
        end.
    end.
    sigma =. %:squared%counts
    mae =. absolute%counts
    value =. %:(total Holdout{.squared)%+/Holdout{.counts
    (<counts),(<sigma),(<mae),<value
)
interval_rows =: 3 : 0
    'predicted sigma multipliers' =. y
    result =. 0 5$0.0
    for_i. i.#predicted do.
        value =. i{predicted
        error =. i{sigma
        multiplier =. i{multipliers
        low80 =. value-(0{IntervalZ)*error
        high80 =. value+(0{IntervalZ)*error
        low95 =. value-(1{IntervalZ)*error
        high95 =. value+(1{IntervalZ)*error
        result =. result,multiplier*value,low80,high80,low95,high95
    end.
    result
)
get_members =: 3 : 0
    if. y=11 do.
        MemberModels
    else.
        ,y{Models
    end.
)
prepare_series =: 3 : 0
    SeriesIndex =: y
    SeriesName =: y{::SeriesNames
    Periods =: y{::SeriesPeriods
    Raw =: y{::SeriesRaw
    Values =: 0.0+Raw
    Missing =: Raw<0
    left =. 0
    while. left< <:#Raw do.
        right =. left+1
        while. (right{Raw)<0 do.
            right =. right+1
        end.
        for_t. (left+1)+i.right-left+1 do.
            value =. (left{Raw)+(((right{Raw)-left{Raw)*(t-left))%(right-left)
            Values =: value t}Values
        end.
        left =. right
    end.
    Components =: Season decompose Values
    defined =. d_defined Components
    residuals =. defined{d_residual_add Components
    average =. mean residuals
    deviation =. %:sample_variance residuals
    CurrentEvents =: I.EventSeries e.<SeriesName
    PastKinds =: (#Values)$<''
    for_event. CurrentEvents do.
        time =. Periods i.event{EventPeriods
        if. time<#Periods do.
            PastKinds =: (event{EventKinds)time}PastKinds
        end.
    end.
    LiftKinds =: ~.PastKinds#~-.PastKinds e.<''
    LiftValues =: i.0
    LiftCounts =: i.0
    for_kind. LiftKinds do.
        times =. I.PastKinds e.kind
        values =. i.0
        for_t. times do.
            value =. (t{Values)%((t{d_trend Components)+(Season|t){d_additive Components)
            values =. values,value
        end.
        LiftValues =: LiftValues,mean values
        LiftCounts =: LiftCounts,#times
    end.
    Outliers =: (#Values)$0
    Scores =: (#Values)$0.0
    for_t. defined do.
        if. (t{Missing)+.-.(t{PastKinds)e.<'' do.
            continue.
        end.
        residual =. t{d_residual_add Components
        if. (|residual-average)>OutlierZ*deviation do.
            Outliers =: 1 t}Outliers
            Scores =: ((residual-average)%deviation)t}Scores
        end.
    end.
    Corrected =: Values
    times =. I.Outliers+.-.PastKinds e.<''
    for_t. times do.
        Corrected =: ((t{d_trend Components)+(Season|t){d_additive Components)t}Corrected
    end.
    variance_r =. sample_variance residuals
    variance_t =. sample_variance (defined{d_trend Components)+residuals
    variance_s =. sample_variance ((Season|defined){d_additive Components)+residuals
    StrengthTrend =: 0>.1-variance_r%variance_t
    StrengthSeasonal =: 0>.1-variance_r%variance_s
    Future =: 0$a:
    last =. >{:Periods
    for_i. i.Horizon do.
        last =. next_month last
        Future =: Future,<last end.
    TrainingCount =: (#Values)-Holdout
    Training =: TrainingCount{.Corrected
    Actual =: TrainingCount}.Values
    policy_index =. (0&{::&.>Inventories)i.<SeriesName
    Policy =: policy_index{::Inventories
    i.0
)
fit_models =: 3 : 0
    Models =: CVs =: 0$a:
    for_name. Methods do.
        model =. (>name)fit_method Training
        Models =: Models,<model
        CVs =: CVs,<cross_validate ,<model
    end.
    cv_values =. cv_rmse&>CVs
    selected =. ComboCount{./:cv_values
    MemberIndices =: (i.11)#~(i.11)e.selected
    MemberModels =: MemberIndices{Models
    CVs =: CVs,<cross_validate MemberModels
    scale =. Season seasonal_scale Training
    Measures =: HoldoutRows =: 0$a:
    for_index. i.12 do.
        predictions =. forecast_members (<get_members index),(<TrainingCount),<Holdout
        cv =. index{::CVs
        rows =. interval_rows (<predictions),(<cv_sigma cv),<Holdout$1.0
        base =. accuracy (<Actual),(<predictions),<scale
        cover80 =. cover95 =. 0
        winkler80 =. winkler95 =. 0.0
        for_step. i.Holdout do.
            row =. step{rows
            observed =. step{Actual
            cover80 =. cover80+((1{row)<:observed)*.observed<:2{row
            cover95 =. cover95+((3{row)<:observed)*.observed<:4{row
            winkler80 =. winkler80+winkler observed,(1{row),(2{row),10.0
            winkler95 =. winkler95+winkler observed,(3{row),(4{row),40.0
        end.
        measure =. (<"0 base),(<0.0),(<cv_rmse cv),(<cover80),(<cover95),(<winkler80%Holdout),(<winkler95%Holdout),<0
        Measures =: Measures,<measure
        HoldoutRows =: HoldoutRows,<rows
    end.
    naive_mae =. 1{::0{::Measures
    for_index. i.12 do.
        measure =. index{::Measures
        fva =. (100.0*(naive_mae-1{::measure))%naive_mae
        measure =. (<fva)6}measure
        Measures =: (<measure)index}Measures
    end.
    ranked =. rank_models Measures
    for_rank. i.12 do.
        index =. rank{ranked
        measure =. index{::Measures
        measure =. (<rank+1)12}measure
        Measures =: (<measure)index}Measures
    end.
    BestIndex =: {.ranked
    BestName =: BestIndex{::ModelNames
    final_indices =. ,BestIndex
    if. BestIndex=11 do.
        final_indices =. MemberIndices
    end.
    FinalFits =: 0$a:
    for_index. final_indices do.
        FinalFits =: FinalFits,< (index{::Methods)fit_method Corrected
    end.
    FinalCV =: cross_validate FinalFits
    predictions =. forecast_members (<FinalFits),(<#Values),<Horizon
    multipliers =. Horizon$1.0
    for_step. i.Horizon do.
        period =. step{Future
        event_ids =. CurrentEvents#~(CurrentEvents{EventPeriods)e.period
        if. #event_ids do.
            kind =. ({.event_ids){EventKinds
            index =. LiftKinds i.kind
            multipliers =. (index{LiftValues)step}multipliers
        end.
    end.
    FutureRows =: interval_rows (<predictions),(<cv_sigma FinalCV),<multipliers
    Demands =: 0{"1 FutureRows
    i.0
)
inventory_lines =: 3 : 0
    'policy_name initial lead review service' =. Policy
    protection =. lead+review
    errors =. i.0
    for_origin. CVStart+i.(((1+#Values)-protection)-CVStart) do.
        predicted =. forecast_members (<FinalFits),(<origin),<protection
        cumulative =. 0.0
        for_i. i.protection do.
            cumulative =. cumulative+(((origin+i){Corrected)-i{predicted)
        end.
        errors =. errors,cumulative
    end.
    safety =. service*rmse errors
    reviews =. review*i.1+<.(Horizon-protection)%review
    ending =. ({:reviews)+protection
    receipts =. (Horizon+lead)$0
    on_hand =. initial+0.0
    outstanding =. orders =. ordered =. short =. 0
    stocks =. i.0
    lines =. (<line 'series';SeriesName;'method';BestName),<line 'policy';'on_hand';initial;'lead_time';lead;'review';review;'service';(real_text service);'safety_stock';real_text safety
    for_step. i.ending do.
        receipt =. step{receipts
        on_hand =. on_hand+receipt
        outstanding =. outstanding-receipt
        period =. step{::Future
        if. step e.reviews do.
            position =. on_hand+outstanding
            target =. (total protection{.step}.Demands)+safety
            quantity =. 0>.>.target-position
            lines =. lines,<line 'review';period;'position';(real_text position);'target';(real_text target);'order';quantity
            if. quantity>0 do.
                orders =. orders+1
                ordered =. ordered+quantity
                outstanding =. outstanding+quantity
                receipts =. quantity(step+lead)}receipts
            end.
        end.
        on_hand =. on_hand-step{Demands
        status =. 'ok'
        if. on_hand<0.0 do.
            status =. 'short'
            short =. short+1
        elseif. on_hand<safety do.
            status =. 'low'
        end.
        stocks =. stocks,on_hand
        lines =. lines,<line 'period';period;'demand';(real_text step{Demands);'receipt';receipt;'on_hand';(real_text on_hand);'status';status
    end.
    lines =. lines,<line 'summary';'orders';orders;'ordered';ordered;'short_periods';short;'lowest';(real_text <./stocks);'average';real_text mean stocks
    years =. /:~~.(4&{.&.>Periods),4&{.&.>Future
    previous_count =. 0
    previous_total =. 0.0
    for_year. years do.
        actual_indices =. I.year=4&{.&.>Periods
        future_indices =. I.year=4&{.&.>Future
        actual_sum =. total actual_indices{Values
        forecast_sum =. total future_indices{Demands
        combined =. actual_sum+forecast_sum
        count =. (#actual_indices)+#future_indices
        growth =. 'NA'
        if. (count=12)*.previous_count=12 do.
            growth =. real_text (100.0*(combined-previous_total))%previous_total
        end.
        lines =. lines,<line 'year';(>year);'actual_months';(#actual_indices);'actual';(real_text actual_sum);'forecast_months';(#future_indices);'forecast';(real_text forecast_sum);'total';(real_text combined);'growth';growth
        previous_count =. count
        previous_total =. combined
    end.
    lines
)
model_lines =: 3 : 0
    name =. m_name y
    errors =. m_residuals y
    common =. line 'rmse';(real_text rmse errors);'residuals';#errors
    if. (<name)e.'naive';'snaive' do.
        ,<name,' ',common return.
    end.
    if. name-:'drift' do.
        ,<name,' slope ',(real_text m_slope y),' ',common return.
    end.
    if. sm_method name do.
        parameters =. m_parameters y
        keys =. ,<'alpha'
        indices =. ,0
        if. -.name-:'ses' do.
            keys =. keys,<'beta'
            indices =. indices,1
        end.
        if. name-:'damped' do.
            keys =. keys,<'phi'
            indices =. indices,3
        elseif. (<name)e.'hw_add';'hw_mult' do.
            keys =. keys,<'gamma'
            indices =. indices,2
        end.
        value =. name
        for_i. i.#keys do.
            value =. value,' ',(i{::keys),' ',real_text (i{indices){parameters
        end.
        'level slope seasonal' =. >{:m_states y
        value =. value,' ',common,' level ',real_text level
        if. -.name-:'ses' do.
            value =. value,' slope ',real_text slope
        end.
        lines =. ,<value
        if. (<name)e.'hw_add';'hw_mult' do.
            positions =. Season|(#m_series y)+i.Season
            lines =. lines,<name,' seasonal ',reals positions{seasonal
        end.
        lines return.
    end.
    if. (<name)e.'decomp_add';'decomp_mult' do.
        value =. name,' intercept ',(real_text m_intercept y),' slope ',(real_text m_slope y),' ',common
        (<value),<name,' seasonal ',reals m_seasonal y return.
    end.
    variance =. 'ar variance'
    for_i. i.4 do.
        variance =. variance,' ',(i{::DifferenceNames),' ',real_text i{m_variances y
    end.
    description =. line 'ar';'difference';((m_kind y){::DifferenceNames);'n';(#m_differenced y);'mean';(real_text m_average y);'order';(m_order y);'sigma2';(real_text m_sigma2 y)
    coefficients =. 'none'
    if. #m_coefficients y do.
        coefficients =. reals m_coefficients y
    end.
    (<variance),(<description,' ',common),(< 'ar aic ',reals m_aic y),< 'ar coefficients ',coefficients
)
left_pad =: 4 : '((0>.x-#y)#'' ''),y'
correlation_bar =: 3 : 0
    'value band' =. y
    width =. <.0.5+20.0*|value
    threshold =. <.0.5+20.0*band
    cells =. 41$' '
    cells =. ':'(20-threshold),(20+threshold)}cells
    cells =. '|'20}cells
    if. value>0.0 do.
        cells =. '#' (21+i.width)}cells
    elseif. value<0.0 do.
        cells =. '#' ((20-width)+i.width)}cells
    end.
    cells
)
forecast_chart =: 3 : 0
    'row low high actual' =. y
    columns =. <.0.5+60.0*(row-low)%high-low
    cells =. 61$' '
    cells =. '-'((3{columns)+i.1+(4{columns)-3{columns)}cells
    cells =. '='((1{columns)+i.1+(2{columns)-1{columns)}cells
    cells =. 'o'(0{columns)}cells
    if. #actual do.
        column =. <.0.5+60.0*(actual-low)%high-low
        cells =. '*'column}cells
    end.
    cells
)
seasonal_profile =: 4 : 0
    width =. <.0.5+30.0*(|y-1.0)%x
    cells =. '|'30}61$' '
    if. y>1.0 do.
        cells =. '#' (31+i.width)}cells
    elseif. y<1.0 do.
        cells =. '#' ((30-width)+i.width)}cells
    end.
    cells
)
diagnostics_lines =: 3 : 0
    name =. m_name y
    errors =. m_residuals y
    count =. #errors
    average =. mean errors
    centered =. errors-average
    squares =. total *:centered
    m2 =. squares%count
    m3 =. (total centered^3)%count
    m4 =. (total centered^4)%count
    skewness =. m3%m2*%:m2
    kurtosis =. (m4%m2*m2)-3.0
    sd =. %:squares%count-1
    dw =. (total *:(}.errors)-}:errors)%total *:errors
    jb =. (count%6.0)*(*:skewness)+(*:kurtosis)%4.0
    header =. line 'residuals';name;'n';count;'mean';(real_text average);'sd';(real_text sd);'dw';(real_text dw);'skewness';(real_text skewness);'kurtosis';(real_text kurtosis);'jb';real_text jb
    value =. 'ljung_box ',name
    for_test. errors ljung_box LjungLags do.
        'lag q probability' =. >test
        value =. value,' ',line 'lag';lag;'q';(real_text q);'p';real_text probability
    end.
    (<header),<value
)
append_reports =: 3 : 0
    defined =. d_defined Components
    for_t. i.#Values do.
        position =. Season|t
        flag =. 'ok'
        if. t{Outliers do.
            flag =. 'outlier'
        end.
        if. t{Missing do.
            flag =. 'missing'
        end.
        if. #t{::PastKinds do.
            flag =. t{::PastKinds
        end.
        trend =. residual_add =. residual_mult =. 'NA'
        if. t e.defined do.
            trend =. real_text t{d_trend Components
            residual_add =. real_text t{d_residual_add Components
            residual_mult =. real_text t{d_residual_mult Components
        end.
        fields =. (<SeriesName),(t{Periods),(<real_text t{Values),(<real_text t{Corrected),(<trend),(<real_text position{d_additive Components),(<residual_add),(<real_text position{d_multiplicative Components),(<residual_mult),<flag
        DecompositionLines =: DecompositionLines,<','join fields
    end.
    FittedLines =: FittedLines,<line 'series';SeriesName
    FittedLines =: FittedLines,<line 'data';'observations';(#Values);'train';TrainingCount;'holdout';Holdout;'missing';(+/Missing);'outliers';(+/Outliers);'events';+/0<#&>PastKinds
    for_i. i.#LiftKinds do.
        FittedLines =: FittedLines,<line 'event';(i{::LiftKinds);'occurrences';(i{LiftCounts);'lift';real_text i{LiftValues
    end.
    for_t. I.Outliers do.
        FittedLines =: FittedLines,<line 'outlier';(t{::Periods);'value';(real_text t{Values);'expected';(real_text t{Corrected);'score';real_text t{Scores
    end.
    FittedLines =: FittedLines,<line 'strength';'trend';(real_text StrengthTrend);'seasonal';real_text StrengthSeasonal
    for_model. Models do.
        FittedLines =: FittedLines,model_lines >model
    end.
    FittedLines =: FittedLines,< 'combo members ',' 'join MemberIndices{Methods
    FittedLines =: FittedLines,<line 'best';BestName;'rmse';real_text 2{::BestIndex{::Measures
    for_model. FinalFits do.
        FittedLines =: FittedLines,('final ',])&.>model_lines >model
    end.
    for_method. i.12 do.
        name =. method{::ModelNames
        rows =. method{::HoldoutRows
        for_i. i.Holdout do.
            index =. TrainingCount+i
            fields =. (<SeriesName),(< 'holdout'),(<name),(index{Periods),(<text index{Raw),real_text&.>i{rows
            ForecastLines =: ForecastLines,<','join fields
        end.
        measure =. method{::Measures
        fields =. (<SeriesName),<name
        for_i. i.13 do.
            value =. i{::measure
            if. i e.8 9 12 do.
                fields =. fields,<text value
            else.
                fields =. fields,<real_text value
            end.
        end.
        AccuracyLines =: AccuracyLines,<','join fields
        cv =. method{::CVs
        for_step. i.Horizon do.
            fields =. (<SeriesName),(<name),(<text step+1),(<text step{cv_counts cv),(<real_text step{cv_mae cv),<real_text step{cv_sigma cv
            CVLines =: CVLines,<','join fields
        end.
    end.
    for_i. i.Horizon do.
        fields =. (<SeriesName),(< 'future'),(<BestName),(i{Future),(< 'NA'),real_text&.>i{FutureRows
        ForecastLines =: ForecastLines,<','join fields
    end.
    ar_model =. 10{::Models
    band =. 2.0%%:#m_differenced ar_model
    CorrelationLines =: CorrelationLines,<line 'series';SeriesName;'difference';((m_kind ar_model){::DifferenceNames);'n';(#m_differenced ar_model);'band';real_text band
    for_group. i.2 do.
        label =. 'acf'
        values =. m_correlations ar_model
        if. group do.
            label =. 'pacf'
            values =. m_partial ar_model
        end.
        for_lag. 1+i.(#values)-1 do.
            value =. lag{values
            significant =. ''
            if. (|value)>band do.
                significant =. ' *'
            end.
            CorrelationLines =: CorrelationLines,<label,' ',(2 left_pad text lag),' ',(7 left_pad real_text value),' [',(correlation_bar value,band),']',significant
        end.
    end.
    for_model. Models do.
        CorrelationLines =: CorrelationLines,diagnostics_lines >model
    end.
    rows =. (BestIndex{::HoldoutRows),FutureRows
    periods =. (TrainingCount}.Periods),Future
    low =. <./(3{"1 rows),Actual
    high =. >./(4{"1 rows),Actual
    ChartLines =: ChartLines,<line 'chart';SeriesName;'method';BestName
    ChartLines =: ChartLines,<line 'scale';'low';(real_text low);'high';real_text high
    for_i. i.#rows do.
        observed =. i.0
        if. i<Holdout do.
            observed =. i{Actual
        end.
        ChartLines =: ChartLines,< (i{::periods),' |',(forecast_chart (<i{rows),(<low),(<high),<observed),'|'
    end.
    peak =. >./|1.0-d_multiplicative Components
    ChartLines =: ChartLines,<line 'profile';'peak';real_text peak
    for_i. i.Season do.
        value =. i{d_multiplicative Components
        ChartLines =: ChartLines,< 'season ',(2 left_pad text i+1),' ',(real_text value),' [',(peak seasonal_profile value),']'
    end.
    PlanLines =: PlanLines,inventory_lines 0
    i.0
)
run =: 3 : 0
    Methods =: 'naive';'snaive';'drift';'ses';'holt';'damped';'hw_add';'hw_mult';'decomp_add';'decomp_mult';'ar'
    ModelNames =: Methods,<'combo'
    DifferenceNames =: 'none';'first';'seasonal';'both'
    read_inputs 0
    DecompositionLines =: ,<'series,period,value,cleaned,trend,seasonal_add,residual_add,seasonal_mult,residual_mult,flag'
    FittedLines =: CorrelationLines =: ChartLines =: PlanLines =: 0$a:
    ForecastLines =: ,<'series,stage,method,period,actual,forecast,lo80,hi80,lo95,hi95'
    AccuracyLines =: ,<'series,method,me,mae,rmse,mape,smape,mase,fva,cv_rmse,cover80,cover95,winkler80,winkler95,rank'
    CVLines =: ,<'series,method,step,origins,mae,rmse'
    for_series. i.#SeriesNames do.
        prepare_series series
        fit_models 0
        append_reports 0
    end.
    try. 1!:5 <'output' catch. end.
    'decomposition.csv'write_lines DecompositionLines
    'models.txt'write_lines FittedLines
    'forecasts.csv'write_lines ForecastLines
    'accuracy.csv'write_lines AccuracyLines
    'cv.csv'write_lines CVLines
    'correlogram.txt'write_lines CorrelationLines
    'chart.txt'write_lines ChartLines
    'plan.txt'write_lines PlanLines
)
run 0
