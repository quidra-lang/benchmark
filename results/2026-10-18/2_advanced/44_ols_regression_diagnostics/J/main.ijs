load 'dataframe.ijs'
load 'formula.ijs'
load 'qr_solver.ijs'
load 'inference.ijs'
load 'diagnostics.ijs'
integer =: 3 : 0
    text =. ":<.y
    '-'(I.text='_')}text
)
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
optional_four =: 4 : 0
    if. y do.
        four x
    else.
        'NA'
    end.
)
table_lines =: 3 : 0
    'header rows marks' =. y
    all =. (<header),rows
    widths =. #&>header
    for_box. rows do.
        row =. >box
        for_column. i.#row do.
            widths =. ((column{widths)>.#column{::row)column}widths
        end.
    end.
    lines =. 0$a:
    for_index. i.#all do.
        row =. index{::all
        line =. (0{::row),(((0{widths)-#0{::row)#' ')
        for_column. 1+i.(#row)-1 do.
            value =. column{::row
            line =. line,'  ',(((column{widths)-#value)#' '),value
        end.
        if. index>0 do.
            if. (index-1)<#marks do.
                mark =. (index-1){::marks
                if. #mark do.
                    line =. line,' ',mark
                end.
            end.
        end.
        while. #line do.
            if. ' '~:{:line do.
                break.
            end.
            line =. }:line
        end.
        lines =. lines,<line
    end.
    lines
)
table_plain =: 3 : 'table_lines y,<0$a:'
data_summary =: 3 : 0
    data =. y
    numeric =. I.-.df_categorical data
    rows =. 0$a:
    source =. df_rows data
    columns =. df_columns data
    for_column. numeric do.
        cells =. column{"1 source
        values =. decimal&>cells#~cells~:< 'NA'
        mean =. (ordered_sum values)%#values
        variance =. 0.0
        for_value. values do.
            variance =. variance+(value-mean)*(value-mean)
        end.
        fields =. (column{columns),(<integer #values),(<integer (#source)-#values),(<four mean),(<four %:variance%(#values)-1),(<four <./values),<four >./values
        rows =. rows,<fields
    end.
    lines =. (<'Data: ',(integer #source),' rows, ',(integer #columns),' columns'),(<''),<'Numeric columns:'
    lines =. lines,table_plain (<;:'column n missing Mean SD Min Max'),<rows
    lines =. lines,(<''),<'Categorical columns:'
    for_column. I.df_categorical data do.
        cells =. column{"1 source
        present =. cells#~cells~:< 'NA'
        labels =. /:~~.present
        fields =. 0$a:
        for_label. labels do.
            fields =. fields,<(>label),' ',integer +/label=present
        end.
        lines =. lines,<(column{::columns),': ',(integer #present),' values, ',(integer (#source)-#present),' missing, ',(integer #labels),' levels: ',', 'join fields
    end.
    lines =. lines,(<''),<'Correlations (pairwise complete observations):'
    rows =. 0$a:
    for_a. numeric do.
        fields =. a{columns
        for_b. numeric do.
            a_cells =. a{"1 source
            b_cells =. b{"1 source
            mask =. (a_cells~:< 'NA')*.b_cells~:< 'NA'
            xs =. decimal&>mask#a_cells
            ys =. decimal&>mask#b_cells
            mean_x =. (ordered_sum xs)%#xs
            mean_y =. (ordered_sum ys)%#ys
            cross =. 0.0
            square_x =. 0.0
            square_y =. 0.0
            for_index. i.#xs do.
                x =. (index{xs)-mean_x
                z =. (index{ys)-mean_y
                cross =. cross+x*z
                square_x =. square_x+x*x
                square_y =. square_y+z*z
            end.
            fields =. fields,<four cross%%:square_x*square_y
        end.
        rows =. rows,<fields
    end.
    header =. (<'column'),numeric{columns
    lines,(table_plain (<header),<rows),<''
)
information_criteria =: 3 : 0
    n =. f_n y
    log_weights =. ordered_sum ^.f_weights y
    value =. ((^.2.0*3.141592653589793)+1.0)-^.n
    value =. value+^.f_rss y
    likelihood =. 0.5*(log_weights-n*value)
    aic =. (_2.0*likelihood)+2.0*((f_rank y)+1)
    bic =. (_2.0*likelihood)+(^.n)*((f_rank y)+1)
    likelihood,aic,bic
)
residual_quantile =: 4 : 0
    position =. ((#x)-1)*y
    index =. <.position
    if. (index+1)<#x do.
        (index{x)+(position-index)*(((index+1){x)-index{x)
    else.
        index{x
    end.
)
s_df =: 0&{::
s_sigma =: 1&{::
s_weight_sum =: 2&{::
s_tss =: 3&{::
s_r_squared =: 4&{::
s_adjusted =: 5&{::
s_f =: 6&{::
s_probability =: 7&{::
s_ll =: 8&{::
s_aic =: 9&{::
s_bic =: 10&{::
s_press =: 11&{::
s_predicted =: 12&{::
s_quantiles =: 13&{::
s_critical =: 14&{::
model_statistics =: 3 : 0
    'fitted confidence' =. y
    n =. f_n fitted
    rank =. f_rank fitted
    degrees =. n-rank
    sigma =. %:(f_rss fitted)%degrees
    weights =. f_weights fitted
    response =. f_response fitted
    weight_sum =. ordered_sum weights
    mean =. (ordered_sum weights*response)%weight_sum
    tss =. 0.0
    press =. 0.0
    for_i. i.n do.
        difference =. (i{response)-mean
        tss =. tss+((i{weights)*difference)*difference
        value =. (i{f_weighted_residual fitted)%(1.0-i{f_leverage fitted)
        press =. press+value*value
    end.
    r_squared =. 1.0-(f_rss fitted)%tss
    adjusted =. 1.0-((1.0-r_squared)*(n-1))%degrees
    statistic =. ((tss-f_rss fitted)%(rank-1))%((f_rss fitted)%degrees)
    'likelihood aic bic' =. information_criteria fitted
    residuals =. /:~f_weighted_residual fitted
    quantiles =. i.0
    for_proportion. 0.0 0.25 0.5 0.75 1.0 do.
        quantiles =. quantiles,residuals residual_quantile proportion
    end.
    probability =. f_pvalue statistic,(rank-1),degrees
    critical =. confidence t_quantile degrees
    (<degrees),(<sigma),(<weight_sum),(<tss),(<r_squared),(<adjusted),(<statistic),(<probability),(<likelihood),(<aic),(<bic),(<press),(<1.0-press%tss),(<quantiles),<critical
)
coefficient_inference =: 3 : 0
    'fitted stats' =. y
    omega =. i.0
    for_i. i.f_n fitted do.
        h =. i{f_leverage fitted
        value =. i{f_weighted_residual fitted
        omega =. omega,(value*value)%((1.0-h)*(1.0-h))
    end.
    result =. 0 10$0.0
    for_column. i.f_p fitted do.
        k =. (f_accepted fitted)i.column
        if. k=f_rank fitted do.
            result =. result,0 0 0 0 _1 0 0 0 0 _1.0
            continue.
        end.
        estimate =. column{f_beta fitted
        standard_error =. (s_sigma stats)*%:k{f_variance fitted
        t =. estimate%standard_error
        half =. (s_critical stats)*standard_error
        robust_variance =. 0.0
        for_i. i.f_n fitted do.
            g =. (<i,k){f_g fitted
            robust_variance =. robust_variance+((i{omega)*g)*g
        end.
        robust_error =. %:robust_variance
        robust_t =. estimate%robust_error
        result =. result,1.0,estimate,standard_error,t,(t t_pvalue s_df stats),(estimate-half),(estimate+half),robust_error,robust_t,robust_t t_pvalue s_df stats
    end.
    result
)
fit_subset =: 3 : 0
    'design terms tolerance' =. y
    matrix =. subset_matrix (<d_matrix design),(<d_columns design),<terms
    qr_fit (<matrix),(<d_response design),(<d_weights design),<tolerance
)
t_index =: 0&{::
t_name =: 1&{::
t_df =: 2&{::
t_ss =: 3&{::
t_rss =: 4&{::
t_ms =: 5&{::
t_f =: 6&{::
t_probability =: 7&{::
sequential_anova =: 3 : 0
    'design fitted' =. y
    terms =. model_terms d_model design
    columns =. d_columns design
    residual_df =. (f_n fitted)-f_rank fitted
    result =. 0$a:
    for_index. i.#terms do.
        degrees =. 0
        squares =. 0.0
        for_k. i.f_rank fitted do.
            column =. k{f_accepted fitted
            if. index=column_term column{::columns do.
                degrees =. degrees+1
                value =. k{f_effects fitted
                squares =. squares+value*value
            end.
        end.
        if. degrees>0 do.
            mean_square =. squares%degrees
            statistic =. mean_square%((f_rss fitted)%residual_df)
            probability =. f_pvalue statistic,degrees,residual_df
            result =. result,<(<index),(<t_name index{::terms),(<degrees),(<squares),(<0.0),(<mean_square),(<statistic),<probability
        end.
    end.
    result
)
marginal_tests =: 3 : 0
    'design fitted terms tolerance' =. y
    residual_df =. (f_n fitted)-f_rank fitted
    result =. 0$a:
    for_index. (model_terms d_model design)removable terms do.
        reduced =. fit_subset (<design),(<terms-.index),<tolerance
        degrees =. (f_rank fitted)-f_rank reduced
        squares =. (f_rss reduced)-f_rss fitted
        statistic =. 0.0
        probability =. _1.0
        if. degrees>0 do.
            statistic =. (squares%degrees)%((f_rss fitted)%residual_df)
            probability =. f_pvalue statistic,degrees,residual_df
        end.
        name =. t_name index{::model_terms d_model design
        result =. result,<(<index),(<name),(<degrees),(<squares),(<f_rss reduced),(<0.0),(<statistic),<probability
    end.
    result
)
variance_inflation =: 3 : 0
    'design fitted stats params' =. y
    result =. 0$a:
    accepted =. f_accepted fitted
    weights =. f_weights fitted
    for_column. }.accepted do.
        response =. column{"1 f_matrix fitted
        matrix =. (accepted-.column){"1 f_matrix fitted
        auxiliary =. qr_fit (<matrix),(<response),(<weights),<0{params
        mean =. (ordered_sum weights*response)%s_weight_sum stats
        tss =. 0.0
        for_i. i.f_n fitted do.
            difference =. (i{response)-mean
            tss =. tss+((i{weights)*difference)*difference
        end.
        r_squared =. 1.0-(f_rss auxiliary)%tss
        vif =. 1.0%(1.0-r_squared)
        name =. column_name column{::d_columns design
        result =. result,<(<name),(<vif),<vif>7{params
    end.
    result
)
reset_test =: 3 : 0
    'fitted tolerance' =. y
    values =. f_fitted fitted
    matrix =. ((f_accepted fitted){"1 f_matrix fitted),.(values*values),.(values*values)*values
    augmented =. qr_fit (<matrix),(<f_response fitted),(<f_weights fitted),<tolerance
    added =. (f_rank augmented)-f_rank fitted
    residual_df =. (f_n fitted)-f_rank augmented
    statistic =. (((f_rss fitted)-f_rss augmented)%added)%((f_rss augmented)%residual_df)
    statistic,added,residual_df,f_pvalue statistic,added,residual_df
)
d_dw_label =: 0&{::
d_bp_label =: 1&{::
d_jb_label =: 2&{::
d_outlier =: 3&{::
d_unadjusted =: 4&{::
d_bonferroni =: 5&{::
d_counts =: 6&{::
d_largest_cooks =: 7&{::
d_largest_dfbetas =: 8&{::
diagnostic_decisions =: 3 : 0
    'design fitted diagnostic params' =. y
    dw_label =. 'no autocorrelation'
    if. (a_dw diagnostic)<8{params do.
        dw_label =. 'positive autocorrelation'
    elseif. (a_dw diagnostic)>4.0-8{params do.
        dw_label =. 'negative autocorrelation'
    end.
    bp_label =. 'homoscedastic'
    if. (2{a_bp diagnostic)<9{params do.
        bp_label =. 'heteroscedastic'
    end.
    jb_label =. 'normal'
    if. (1{a_jb diagnostic)<10{params do.
        jb_label =. 'non-normal'
    end.
    rows =. a_rows diagnostic
    outlier =. 0
    counts =. 5$0
    cooks =. i.0
    for_i. i.f_n fitted do.
        row =. i{::rows
        if. (|r_studentized row)>|r_studentized outlier{::rows do.
            outlier =. i
        end.
        flags =. r_flags row
        for_flag. i.4 do.
            if. (flag{'HOCF')e.flags do.
                counts =. (1+flag{counts)flag}counts
            end.
        end.
        if. -.flags-:'-' do.
            counts =. (1+4{counts)4}counts
        end.
        cooks =. cooks,r_cooks row
    end.
    order =. /:(-cooks),.i.#rows
    largest_cooks =. (3<.#rows){.order
    largest_dfbetas =. 0$a:
    for_k. i.f_rank fitted do.
        index =. 0
        for_i. 1+i.(f_n fitted)-1 do.
            if. (|k{r_dfbetas i{::rows)>|k{r_dfbetas index{::rows do.
                index =. i
            end.
        end.
        column =. k{f_accepted fitted
        fields =. (<column_name column{::d_columns design),(<integer index{d_row_numbers design),<four k{r_dfbetas index{::rows
        largest_dfbetas =. largest_dfbetas,<fields
    end.
    unadjusted =. (r_studentized outlier{::rows)t_pvalue ((f_n fitted)-f_rank fitted)-1
    bonferroni =. 1.0<.(f_n fitted)*unadjusted
    (<dw_label),(<bp_label),(<jb_label),(<outlier),(<unadjusted),(<bonferroni),(<counts),(<largest_cooks),<largest_dfbetas
)
prediction_report =: 3 : 0
    'model_number design fitted stats prediction_data' =. y
    lines =. 0$a:
    predicted_count =. 0
    actual_count =. 0
    covered_count =. 0
    squared_errors =. 0.0
    for_row_number. i.#prediction_data do.
        record =. row_number{prediction_data
        fields =. (<integer model_number),<integer row_number+1
        if. -.predictable (<d_model design),(<d_levels design),<record do.
            fields =. fields,9$<'NA'
        else.
            predicted_count =. predicted_count+1
            values =. (d_columns design)design_values record
            predicted =. 0.0
            variance =. 0.0
            for_column. f_accepted fitted do.
                predicted =. predicted+(column{values)*column{f_beta fitted
            end.
            for_k. i.f_rank fitted do.
                sum =. 0.0
                for_m. i.f_rank fitted do.
                    column =. m{f_accepted fitted
                    sum =. sum+(column{values)*(<m,k){f_inverse fitted
                end.
                variance =. variance+sum*sum
            end.
            standard_error =. (s_sigma stats)*%:variance
            confidence_width =. (s_critical stats)*standard_error
            prediction_width =. (s_critical stats)*%:((s_sigma stats)*s_sigma stats)+standard_error*standard_error
            lower =. predicted-prediction_width
            upper =. predicted+prediction_width
            output =. predicted,standard_error,(predicted-confidence_width),(predicted+confidence_width),lower,upper
            fields =. fields,four&.>output
            actual_text =. (model_response_column d_model design){::record
            if. actual_text-:'NA' do.
                fields =. fields,3$<'NA'
            else.
                actual =. decimal actual_text
                actual_count =. actual_count+1
                difference =. actual-predicted
                squared_errors =. squared_errors+difference*difference
                covered =. (lower<:actual)*.actual<:upper
                covered_count =. covered_count+covered
                covered_text =. covered{::'no';'yes'
                fields =. fields,(<four actual),(<four difference),<covered_text
            end.
        end.
        lines =. lines,<','join fields
    end.
    rmse =. 0.0
    if. actual_count>0 do.
        rmse =. %:squared_errors%actual_count
    end.
    (<lines),<predicted_count,actual_count,rmse,covered_count
)
b_number =: 0&{::
b_design =: 1&{::
b_fit =: 2&{::
b_stats =: 3&{::
b_coefficients =: 4&{::
b_anova =: 5&{::
b_marginal =: 6&{::
b_vif =: 7&{::
b_diagnostics =: 8&{::
b_decisions =: 9&{::
b_reset =: 10&{::
b_predictions =: 11&{::
analyze_model =: 3 : 0
    'model_number design params prediction_data' =. y
    fitted =. qr_fit (<d_matrix design),(<d_response design),(<d_weights design),<0{params
    stats =. model_statistics (<fitted),<2{params
    diagnostic =. calculate_diagnostics (<fitted),<params
    predictions =. prediction_report (<model_number),(<design),(<fitted),(<stats),<prediction_data
    coefficients =. coefficient_inference (<fitted),<stats
    anova =. sequential_anova (<design),<fitted
    terms =. i.#model_terms d_model design
    marginal =. marginal_tests (<design),(<fitted),(<terms),<0{params
    vif =. variance_inflation (<design),(<fitted),(<stats),<params
    decisions =. diagnostic_decisions (<design),(<fitted),(<diagnostic),<params
    reset =. reset_test (<fitted),<0{params
    (<model_number),(<design),(<fitted),(<stats),(<coefficients),(<anova),(<marginal),(<vif),(<diagnostic),(<decisions),(<reset),<predictions
)
coefficient_tables =: 3 : 0
    'report confidence' =. y
    columns =. d_columns b_design report
    coefficients =. b_coefficients report
    rows =. 0$a:
    marks =. 0$a:
    for_index. i.#columns do.
        value =. index{coefficients
        defined =. 0{value
        fields =. (<column_name index{::columns),(<(1{value)optional_four defined),(<(2{value)optional_four defined),(<(3{value)optional_four defined),<probability 4{value
        rows =. rows,<fields
        marks =. marks,<significance 4{value
    end.
    header =. 'term';'Estimate';'Std. Error';'t value';'Pr(>|t|)'
    ordinary =. table_lines (<header),(<rows),<marks
    rows =. 0$a:
    for_index. i.#columns do.
        value =. index{coefficients
        fields =. (<column_name index{::columns),(<(5{value)optional_four 0{value),<(6{value)optional_four 0{value
        rows =. rows,<fields
    end.
    intervals =. <'Confidence intervals (level ',(four confidence),', t ',(four s_critical b_stats report),'):'
    intervals =. intervals,table_plain (<;:'term Lower Upper'),<rows
    rows =. 0$a:
    marks =. 0$a:
    for_index. i.#columns do.
        value =. index{coefficients
        defined =. 0{value
        fields =. (<column_name index{::columns),(<(7{value)optional_four defined),(<(8{value)optional_four defined),<probability 9{value
        rows =. rows,<fields
        marks =. marks,<significance 9{value
    end.
    header =. 'term';'Std. Error';'t value';'Pr(>|t|)'
    robust =. table_lines (<header),(<rows),<marks
    (<ordinary),(<intervals),<robust
)
anova_tables =: 3 : 0
    rows =. 0$a:
    marks =. 0$a:
    for_box. b_anova y do.
        entry =. >box
        fields =. (<t_name entry),(<integer t_df entry),(<four t_ss entry),(<four t_ms entry),(<four t_f entry),<probability t_probability entry
        rows =. rows,<fields
        marks =. marks,<significance t_probability entry
    end.
    degrees =. s_df b_stats y
    rss =. f_rss b_fit y
    rows =. rows,<(<'Residuals'),(<integer degrees),(<four rss),<four rss%degrees
    marks =. marks,<''
    header =. 'term';'Df';'Sum Sq';'Mean Sq';'F value';'Pr(>F)'
    sequential =. table_lines (<header),(<rows),<marks
    rows =. 0$a:
    marks =. 0$a:
    for_box. b_marginal y do.
        entry =. >box
        fields =. (<t_name entry),(<integer t_df entry),(<four t_ss entry),(<four t_rss entry),(<(t_f entry)optional_four (t_df entry)>0),<probability t_probability entry
        rows =. rows,<fields
        marks =. marks,<significance t_probability entry
    end.
    header =. 'term';'Df';'Sum Sq';'RSS';'F value';'Pr(>F)'
    (<sequential),<table_lines (<header),(<rows),<marks
)
diagnostic_summary =: 3 : 0
    design =. b_design y
    fitted =. b_fit y
    diagnostic =. b_diagnostics y
    decisions =. b_decisions y
    rows =. a_rows diagnostic
    'bp bp_degrees bp_probability' =. a_bp diagnostic
    'jb jb_probability skewness kurtosis' =. a_jb diagnostic
    'reset reset_degrees reset_df reset_probability' =. b_reset y
    outlier =. d_outlier decisions
    counts =. d_counts decisions
    lines =. <'Diagnostics:'
    lines =. lines,<'Durbin-Watson: ',(four a_dw diagnostic),' (',(d_dw_label decisions),')'
    lines =. lines,<'Breusch-Pagan: ',(four bp),' on ',(integer bp_degrees),' DF, p-value: ',(probability bp_probability),' (',(d_bp_label decisions),')'
    lines =. lines,<'Jarque-Bera: ',(four jb),' on 2 DF, p-value: ',(probability jb_probability),', skewness ',(four skewness),', kurtosis ',(four kurtosis),' (',(d_jb_label decisions),')'
    lines =. lines,<'RESET (powers 2 and 3): F ',(four reset),' on ',(integer reset_degrees),' and ',(integer reset_df),' DF, p-value: ',probability reset_probability
    lines =. lines,<'Outlier test: row ',(integer outlier{d_row_numbers design),', studentized ',(four r_studentized outlier{::rows),', unadjusted p-value: ',(probability d_unadjusted decisions),', Bonferroni p-value: ',probability d_bonferroni decisions
    lines =. lines,<'Flagged rows: leverage ',(integer 0{counts),', outlier ',(integer 1{counts),', cooks ',(integer 2{counts),', dffits ',(integer 3{counts),', any ',integer 4{counts
    lines =. lines,<'Largest Cook''s distances:'
    for_index. d_largest_cooks decisions do.
        row =. index{::rows
        lines =. lines,<'row ',(integer index{d_row_numbers design),': cooks_d ',(four r_cooks row),', leverage ',(four index{f_leverage fitted),', studentized ',(four r_studentized row),', flags ',r_flags row
    end.
    lines =. lines,<'Largest absolute DFBETAS:'
    lines,table_plain (<;:'column row DFBETAS'),<d_largest_dfbetas decisions
)
model_summary =: 3 : 0
    'report total_rows confidence' =. y
    design =. b_design report
    model =. d_model design
    fitted =. b_fit report
    stats =. b_stats report
    aliases =. 0$a:
    for_column. f_aliases fitted do.
        aliases =. aliases,<column_name column{::d_columns design
    end.
    if. #aliases do.
        alias_text =. ', 'join aliases
    else.
        alias_text =. 'none'
    end.
    terms =. t_name&.>model_terms model
    q =. s_quantiles stats
    'ordinary intervals robust' =. coefficient_tables (<report),<confidence
    'sequential marginal' =. anova_tables report
    weight =. model_weight model
    if. 0=#weight do.
        weight =. 'none'
    end.
    lines =. <'Model ',(integer b_number report),': ',model_original model
    lines =. lines,<'Terms: ',', 'join terms
    lines =. lines,<'Weights: ',weight
    lines =. lines,<'Observations: ',(integer f_n fitted),' used, ',(integer total_rows-f_n fitted),' dropped'
    lines =. lines,<'Columns: ',(integer f_p fitted),', rank ',(integer f_rank fitted),', aliased: ',alias_text
    lines =. lines,(<''),<'Residuals: Min ',(four 0{q),', 1Q ',(four 1{q),', Median ',(four 2{q),', 3Q ',(four 3{q),', Max ',four 4{q
    lines =. lines,(<''),(<'Coefficients:'),ordinary
    lines =. lines,(<'---'),(<'Signif. codes: 0 ''***'' 0.001 ''**'' 0.01 ''*'' 0.05 ''.'' 0.1 '' '' 1'),<''
    lines =. lines,<'Residual standard error: ',(four s_sigma stats),' on ',(integer s_df stats),' degrees of freedom'
    lines =. lines,<'Multiple R-squared: ',(four s_r_squared stats),', Adjusted R-squared: ',four s_adjusted stats
    lines =. lines,<'F-statistic: ',(four s_f stats),' on ',(integer (f_rank fitted)-1),' and ',(integer s_df stats),' DF, p-value: ',probability s_probability stats
    lines =. lines,<'Log-likelihood: ',(four s_ll stats),', AIC: ',(four s_aic stats),', BIC: ',four s_bic stats
    lines =. lines,<'PRESS: ',(four s_press stats),', Predicted R-squared: ',four s_predicted stats
    lines =. lines,(<''),intervals,(<''),(<'Robust standard errors (HC3):'),robust
    lines =. lines,(<''),(<'Analysis of variance (sequential):'),sequential,(<''),(<'Marginal F tests (drop one term):'),marginal
    lines =. lines,(<''),<'Variance inflation factors:'
    rows =. 0$a:
    marks =. 0$a:
    for_box. b_vif report do.
        'name value high' =. >box
        rows =. rows,<(<name),<four value
        mark =. ''
        if. high do.
            mark =. 'high'
        end.
        marks =. marks,<mark
    end.
    lines =. lines,table_lines (<;:'column VIF'),(<rows),<marks
    lines,(<''),diagnostic_summary report
)
summary_report =: 3 : 0
    'data reports params' =. y
    lines =. data_summary data
    for_index. i.#reports do.
        if. index do.
            lines =. lines,<''
        end.
        report =. index{::reports
        lines =. lines,model_summary (<report),(<#df_rows data),<2{params
    end.
    lines =. lines,(<''),<'Model comparison:'
    rows =. 0$a:
    for_box. reports do.
        report =. >box
        fitted =. b_fit report
        stats =. b_stats report
        fields =. (<integer b_number report),(<integer f_n fitted),(<integer f_rank fitted),(<four s_sigma stats),(<four s_r_squared stats),(<four s_adjusted stats),(<four s_predicted stats),(<four s_aic stats),<four s_bic stats
        rows =. rows,<fields
    end.
    header =. 'model';'n';'rank';'sigma';'R-squared';'Adj. R-squared';'Pred. R-squared';'AIC';'BIC'
    lines =. lines,table_plain (<header),<rows
    lines =. lines,(<''),<'Prediction check:'
    for_box. reports do.
        report =. >box
        'predicted actual rmse covered' =. 1{::b_predictions report
        lines =. lines,<'model ',(integer b_number report),': ',(integer predicted),' predicted, ',(integer actual),' with actual values, RMSE ',(rmse optional_four actual>0),', inside prediction interval ',integer covered
    end.
    lines
)
diagnostics_csv =: 3 : 0
    lines =. <'model,row,fitted,residual,leverage,studentized,cooks_d,dffits,flags'
    for_box. y do.
        report =. >box
        fitted =. b_fit report
        rows =. a_rows b_diagnostics report
        for_index. i.#rows do.
            row =. index{::rows
            fields =. (<integer b_number report),<integer index{d_row_numbers b_design report
            values =. (index{f_fitted fitted),(index{f_residual fitted),(index{f_leverage fitted),(r_studentized row),(r_cooks row),r_dffits row
            fields =. fields,(four&.>values),<r_flags row
            lines =. lines,<','join fields
        end.
    end.
    lines
)
backward_selection =: 3 : 0
    'report params' =. y
    design =. b_design report
    model =. d_model design
    terms =. i.#model_terms model
    fitted =. b_fit report
    alpha =. 1{params
    lines =. <'Backward elimination (model 1, alpha ',(four alpha),', rows ',(integer #d_rows design),')'
    step =. 1
    while. 1 do.
        criteria =. information_criteria fitted
        degrees =. (f_n fitted)-f_rank fitted
        lines =. lines,<'Step ',(integer step),': ',(model format_model terms),' (RSS ',(four f_rss fitted),', df ',(integer degrees),', AIC ',(four 1{criteria),')'
        if. 0=#terms do.
            lines =. lines,<'  stop: no removable terms'
            break.
        end.
        results =. marginal_tests (<design),(<fitted),(<terms),<0{params
        largest =. 0{::results
        for_box. results do.
            result =. >box
            lines =. lines,<'  - ',(t_name result),': F ',(four t_f result),' on ',(integer t_df result),' and ',(integer degrees),' DF, p-value ',probability t_probability result
            if. (t_probability result)>t_probability largest do.
                largest =. result
            end.
        end.
        if. (t_probability largest)<:alpha do.
            lines =. lines,<'  stop: largest p-value ',(probability t_probability largest),' is not above ',four alpha
            break.
        end.
        lines =. lines,<'  remove ',t_name largest
        terms =. terms-.t_index largest
        fitted =. fit_subset (<design),(<terms),<0{params
        step =. step+1
    end.
    lines,<'Final model: ',model format_model terms
)
forward_selection =: 3 : 0
    'report params' =. y
    design =. b_design report
    model =. d_model design
    terms =. i.0
    lines =. <'Forward selection by AIC (model 1, rows ',(integer #d_rows design),')'
    step =. 1
    while. 1 do.
        fitted =. fit_subset (<design),(<terms),<0{params
        criteria =. information_criteria fitted
        lines =. lines,<'Step ',(integer step),': ',(model format_model terms),' (AIC ',(four 1{criteria),')'
        available =. (model_terms model)candidates terms
        if. 0=#available do.
            lines =. lines,<'  stop: no candidate terms remain'
            break.
        end.
        best_index =. _1
        best_aic =. 0.0
        best_terms =. i.0
        for_index. available do.
            candidate_terms =. /:~terms,index
            candidate =. fit_subset (<design),(<candidate_terms),<0{params
            candidate_aic =. 1{information_criteria candidate
            lines =. lines,<'  + ',(t_name index{::model_terms model),': AIC ',four candidate_aic
            if. (best_index<0)+.candidate_aic<best_aic do.
                best_index =. index
                best_aic =. candidate_aic
                best_terms =. candidate_terms
            end.
        end.
        if. best_aic>:1{criteria do.
            lines =. lines,<'  stop: no candidate lowers the AIC'
            break.
        end.
        lines =. lines,<'  add ',t_name best_index{::model_terms model
        terms =. best_terms
        step =. step+1
    end.
    lines,<'Final model: ',model format_model terms
)
best_subsets =: 3 : 0
    'report params' =. y
    design =. b_design report
    model =. d_model design
    count =. #model_terms model
    subsets =. 0$a:
    keys =. 0 2$0.0
    for_mask. i.2^count do.
        terms =. (i.count)#~2|<.mask%2^i.count
        if. -.(model_terms model)hierarchical terms do.
            continue.
        end.
        fitted =. fit_subset (<design),(<terms),<0{params
        'likelihood aic bic' =. information_criteria fitted
        subsets =. subsets,<(<bic),(<mask),(<aic),(<f_rank fitted),<terms
        keys =. keys,bic,mask
    end.
    order =. /:keys
    lines =. <'Best subsets by BIC (model 1, rows ',(integer #d_rows design),', subsets ',(integer #subsets),')'
    limit =. (#subsets)<.<.11{params
    for_position. i.limit do.
        'bic mask aic rank terms' =. (position{order){::subsets
        lines =. lines,<(integer position+1),'. BIC ',(four bic),', AIC ',(four aic),', rank ',(integer rank),': ',model format_model terms
    end.
    lines
)
selection_report =: 3 : 0
    (backward_selection y),(<''),(forward_selection y),(<''),best_subsets y
)
plot_grid =: 3 : 0
    'horizontal vertical lo hi width height limit' =. y
    grid =. (height,width)$0
    for_index. i.#horizontal do.
        x =. index{horizontal
        column =. (width-1)<.<.((x-lo)%(hi-lo))*width
        row =. <.((limit-index{vertical)%(2.0*limit))*height
        row =. 0>.((height-1)<.row)
        grid =. (1+(<row,column){grid)(<row,column)}grid
    end.
    grid
)
plot_frame =: 3 : 0
    width =. 1{$y
    border =. '+',(width#'-'),'+'
    lines =. <border
    for_index. i.#y do.
        empty =. '.'
        if. index=<.(#y)%2 do.
            empty =. '-'
        end.
        cells =. ''
        for_count. index{y do.
            if. count>:10 do.
                cells =. cells,'*'
            elseif. count>0 do.
                cells =. cells,integer count
            else.
                cells =. cells,empty
            end.
        end.
        lines =. lines,<'|',cells,'|'
    end.
    lines,<border
)
residual_plot =: 3 : 0
    'report params' =. y
    width =. <.12{params
    height =. <.13{params
    limit =. 14{params
    fitted =. b_fit report
    studentized =. r_studentized&>a_rows b_diagnostics report
    lo =. <./f_fitted fitted
    hi =. >./f_fitted fitted
    grid =. plot_grid (<f_fitted fitted),(<studentized),(<lo),(<hi),(<width),(<height),<limit
    lines =. <'Model ',(integer b_number report),': studentized residuals vs fitted values'
    lines =. lines,<'fitted ',(four lo),' to ',(four hi),', studentized ',(four -limit),' to ',four limit
    lines =. lines,plot_frame grid
    above =. +/studentized>2.0
    below =. +/studentized<_2.0
    outside =. +/(|studentized)>limit
    lines =. lines,<'points: ',(integer f_n fitted),', above +2: ',(integer above),', below -2: ',(integer below),', outside range: ',integer outside
    lines =. lines,<'Histogram of studentized residuals:'
    counts =. +/"1 grid
    maximum =. >./counts
    for_index. i.height do.
        count =. index{counts
        lower =. limit-((2.0*limit)*(index+1))%height
        upper =. limit-((2.0*limit)*index)%height
        length =. <.(((count*40)+maximum)-1)%maximum
        line =. (four lower),' to ',(four upper),': ',integer count
        if. length do.
            line =. line,' ',length#'#'
        end.
        lines =. lines,<line
    end.
    hi =. >./f_leverage fitted
    lines =. lines,<'Model ',(integer b_number report),': studentized residuals vs leverage'
    lines =. lines,<'leverage 0.0000 to ',(four hi),', studentized ',(four -limit),' to ',four limit
    grid =. plot_grid (<f_leverage fitted),(<studentized),(<0.0),(<hi),(<width),(<height),<limit
    lines,plot_frame grid
)
aligned_rows =: 4 : 0
    columns =. y
    original_columns =. df_columns x
    rows =. (0,#columns)$a:
    for_original. df_rows x do.
        row =. 0$a:
        for_name. columns do.
            index =. original_columns i.name
            if. index=#original_columns do.
                row =. row,<'NA'
            else.
                row =. row,index{original
            end.
        end.
        rows =. rows,row
    end.
    rows
)
save_lines =: 4 : 0
    contents =. ''
    for_line. y do.
        contents =. contents,(>line),LF
    end.
    contents 1!:2 <'output/',x
)
run =: 3 : 0
    data =. (i.0)read_csv 'input/data.csv'
    prediction_frame =. data read_csv 'input/predict.csv'
    prediction_data =. prediction_frame aligned_rows df_columns data
    params =. read_params 0
    reports =. 0$a:
    models =. read_lines 'input/model.txt'
    for_index. i.#models do.
        model =. (df_columns data)parse_model index{::models
        design =. make_design (<model),<data
        reports =. reports,<analyze_model (<index+1),(<design),(<params),<prediction_data
    end.
    predictions =. <'model,row,fit,se_fit,conf_lower,conf_upper,pred_lower,pred_upper,actual,error,covered'
    plots =. 0$a:
    for_index. i.#reports do.
        report =. index{::reports
        predictions =. predictions,0{::b_predictions report
        if. index do.
            plots =. plots,<''
        end.
        plots =. plots,residual_plot (<report),<params
    end.
    'summary.txt' save_lines summary_report (<data),(<reports),<params
    'diagnostics.csv' save_lines diagnostics_csv reports
    'selection.txt' save_lines selection_report (<0{::reports),<params
    'predictions.csv' save_lines predictions
    'residual_plot.txt' save_lines plots
)
run 0
