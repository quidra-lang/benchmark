ScriptPath =: >{:4!:3''
SourceDirectory =: (1+>./_1,I.ScriptPath e.'/\'){.ScriptPath
load SourceDirectory,'report.ijs'
load SourceDirectory,'data_io.ijs'
load SourceDirectory,'models.ijs'
load SourceDirectory,'integrator.ijs'
load SourceDirectory,'fitting.ijs'

sum_real =: 3 : 0
    total =. 0.0
    for_value. y do. total =. total+value end.
    total
)
sum_int =: 3 : '+/y'
peak =: 3 : 'y i.>./y'
squared_errors =: 3 : 0
    'series coefficient observations' =. y
    total =. 0.0
    for_i. i.#series do.
        difference =. (coefficient*i{series)-i{observations
        total =. total+difference*difference
    end.
    total
)
rmse =: 4 : '%:x%y'
rmse_all =: 3 : 'y rmse Days'
fit_line =: 3 : 'FitLines =: FitLines,<emit y'
rep_line =: 3 : 'ReproductionLines =: ReproductionLines,<emit y'
multipliers_for =: 4 : 0
    index =. 0
    multipliers =. i.0
    for_day. 1+i.y do.
        while. (index+1)<#x do.
            if. ((<(index+1),0){x)>day do. break. end.
            index =. index+1
        end.
        multipliers =. multipliers,(<index,1){x
    end.
    multipliers
)
prepare =: 3 : 0
    Days =: #Cases
    Groups =: #Populations
    Population =: +/Populations
    CaseTotal =: +/Cases
    DeathTotal =: +/Deaths
    Fatality =: (sum_real Populations*Fatalities)%Population
    'e infectious' =. InitialEI
    InitialState =: ((Population-e)-infectious),e,infectious,0.0,0.0,0.0
    SIRInitial =: ((Population-e)-infectious),(e+infectious),0.0,0.0
    AgeInitial =: i.0
    for_population. Populations do.
        eg =. (e*population)%Population
        ig =. (infectious*population)%Population
        AgeInitial =: AgeInitial,((population-eg)-ig),eg,ig,0.0,0.0,0.0
    end.
    AgeInflows =: 5+6*i.Groups
    Multipliers =: Interventions multipliers_for Days
    WeekRanges =: 0 2$0
    for_start. 7*i.>.(Days%7) do. WeekRanges =: WeekRanges,start,(Days-1)<.start+6 end.
    CacheKeys =: 0 2$0.0
    CacheValues =: 0$a:
    FitLines =: ReproductionLines =: 0$a:
    i.0 0
)
seird_states =: 3 : 0
    'beta gamma sigma multipliers initial' =. y
    parameters =. Population,sigma,Fatality,beta,gamma
    rates =. parameters&seird_rates
    rates simulate (<initial),(<multipliers),<,5
)
default_states =: 3 : 0
    'beta gamma' =. y
    seird_states (<beta),(<gamma),(<Sigma),(<Multipliers),<InitialState
)
incidence_for =: 3 : 0
    index =. ((<"1 CacheKeys)i.!.0<y)
    if. index<#CacheKeys do. index{::CacheValues return. end.
    states =. default_states y
    incidence =. 5{"1 states
    CacheKeys =: CacheKeys,y
    CacheValues =: CacheValues,<incidence
    incidence
)
error_value =: 3 : 0
    'beta gamma rho' =. y
    incidence =. incidence_for beta,gamma
    squared_errors (<incidence),(<rho),<Cases
)
beta_error =: 4 : 'error_value y,x'
rho_error =: 4 : 'error_value x,y'
nm_error =: 4 : 'error_value y,x'
golden_records =: 3 : 0
    'round name result value records' =. y
    for_i. i.#records do.
        'a b c d fc fd' =. i{records
        fit_line 'golden';round;name;i;'a';(six a);'b';(six b);'c';(six c);'d';(six d);'rmse';(fixed rmse_all fc);fixed rmse_all fd
    end.
    fit_line 'golden_result';round;name;(six result);'sse';one value
)
fit_model =: 3 : 0
    'bmin bmax' =. BetaRange
    'rmin rmax' =. RhoRange
    betas =. i.0
    rhos =. i.0
    for_i. i.BetaCount do. betas =. betas,bmin+((bmax-bmin)*i)%(BetaCount-1) end.
    for_j. i.RhoCount do. rhos =. rhos,rmin+((rmax-rmin)*j)%(RhoCount-1) end.
    DeltaBeta =: (bmax-bmin)%(BetaCount-1)
    DeltaRho =: (rmax-rmin)%(RhoCount-1)
    fit_line 'data days';Days;'cases';CaseTotal;'deaths';DeathTotal;'population';Population;'fatality';six Fatality
    fit_line 'grid gamma';(fixed Gamma0);'rho';4 formatted rhos
    SSEGrid =: _
    for_beta. betas do.
        errors =. i.0
        for_rho. rhos do.
            value =. error_value beta,Gamma0,rho
            errors =. errors,rmse_all value
            if. value<SSEGrid do.
                SSEGrid =: value
                BetaGrid =: beta
                RhoGrid =: rho
            end.
        end.
        fit_line 'grid beta';(fixed beta);'rmse';2 formatted errors
    end.
    fit_line 'grid_best beta';(fixed BetaGrid);'rho';(fixed RhoGrid);'sse';(one SSEGrid);'rmse';fixed rmse_all SSEGrid
    beta =. BetaGrid
    rho =. RhoGrid
    for_round. 1+i.CoordinateRounds do.
        objective =. (Gamma0,rho)&beta_error
        'result value records' =. objective golden (<beta-DeltaBeta),(<beta+DeltaBeta),<GoldenIterations
        golden_records (<round),(<'beta'),(<result),(<value),<records
        beta =. result
        objective =. (beta,Gamma0)&rho_error
        'result value records' =. objective golden (<rho-DeltaRho),(<rho+DeltaRho),<GoldenIterations
        golden_records (<round),(<'rho'),(<result),(<value),<records
        rho =. result
        SSEGolden =: value
    end.
    BetaGolden =: beta
    RhoHat =: rho
    'db dg' =. SimplexStep
    'alpha chi psi omega' =. NMFactors
    objective =. rho&nm_error
    arguments =. (<beta),(<Gamma0),(<db),(<dg),(<alpha),(<chi),(<psi),(<omega),<NMIterations
    'initial records final' =. objective nelder_mead arguments
    for_vertex. initial do.
        'serial beta gamma value' =. vertex
        fit_line 'simplex';serial;'beta';(six beta);'gamma';(six gamma);'rmse';fixed rmse_all value
    end.
    for_i. i.#records do.
        'operation vertex' =. i{::records
        'serial beta gamma value' =. vertex
        fit_line 'nelder_mead';(i+1);operation;'beta';(six beta);'gamma';(six gamma);'rmse';fixed rmse_all value
    end.
    for_i. i.3 do.
        'serial beta gamma value' =. i{final
        fit_line 'final_simplex';(i+1);'beta';(six beta);'gamma';(six gamma);'rmse';fixed rmse_all value
    end.
    best =. 0{final
    BetaHat =: 1{best
    GammaHat =: 2{best
    SSENM =: 3{best
    R0 =: BetaHat%GammaHat
    mean =. CaseTotal%Days
    SST =. sum_real (Cases-mean)*(Cases-mean)
    fit_line 'fitted beta';(six BetaHat);'gamma';(six GammaHat);'rho';(six RhoHat);'sigma';(six Sigma);'r0';fixed R0
    fit_line 'sse grid';(one SSEGrid);'golden';(one SSEGolden);'nelder_mead';(one SSENM);'rmse';(fixed rmse_all SSENM);'r2';fixed 1-SSENM%SST
    names =. 'grid';'golden';'nelder_mead'
    values =. (BetaGrid,Gamma0,RhoGrid,SSEGrid),(BetaGolden,Gamma0,RhoHat,SSEGolden),:BetaHat,GammaHat,RhoHat,SSENM
    for_i. i.3 do.
        'beta gamma rho value' =. i{values
        fit_line 'stage';(i{::names);'beta';(six beta);'gamma';(six gamma);'rho';(six rho);'r0';(fixed beta%gamma);'rmse';fixed rmse_all value
    end.
    i.0 0
)
slice =: 4 : 0
    'first last' =. x
    (first+i.1+last-first){y
)
death_analysis =: 3 : 0
    numerator =. sum_real ModelDeaths*Deaths
    denominator =. sum_real ModelDeaths*ModelDeaths
    scale =. numerator%denominator
    error =. squared_errors (<ModelDeaths),(<1.0),<Deaths
    fit_line 'deaths observed';DeathTotal;'model';(one (<(Days-1),4){States);'rmse';(fixed rmse_all error);'scale';(fixed scale);'implied_fatality';(six Fatality*scale);'cfr';fixed DeathTotal%CaseTotal
    correlations =. i.0
    for_lag. i.DeathLag+1 do.
        observed =. (i.Days-lag){Cases
        deaths =. (lag+i.Days-lag){Deaths
        a =. +/observed*deaths
        b =. +/observed*observed
        yy =. +/deaths*deaths
        correlation =. a%%:(0.0+b)*(0.0+yy)
        correlations =. correlations,correlation
        cfr =. (+/deaths)%+/observed
        fit_line 'death_lag';lag;'correlation';(fixed correlation);'cfr';fixed cfr
    end.
    fit_line 'death_best_lag';peak correlations
)
fitted_diagnostics =: 3 : 0
    States =: default_states BetaHat,GammaHat
    Incidence =: 5{"1 States
    Reported =: RhoHat*Incidence
    Residuals =: Cases-Reported
    ModelDeaths =: Rt =: Averages =: CumulativeReported =: i.0
    CumulativeCases =: i.0
    cumulative_observed =. 0
    cumulative_reported =. 0.0
    runs =. 1
    positive =. 0
    u =. difference_sum =. 0.0
    for_d. i.Days do.
        if. d=0 do. previous =. InitialState else. previous =. (d-1){States end.
        residual =. d{Residuals
        ModelDeaths =: ModelDeaths,((<d,4){States)-4{previous
        Rt =: Rt,((R0*d{Multipliers)*0{previous)%Population
        start =. 0>.d-6
        average =. (+/(start,d)slice Cases)%(7<.d+1)
        Averages =: Averages,average
        cumulative_observed =. cumulative_observed+d{Cases
        cumulative_reported =. cumulative_reported+d{Reported
        CumulativeCases =: CumulativeCases,cumulative_observed
        CumulativeReported =: CumulativeReported,cumulative_reported
        u =. u+residual*residual
        positive =. positive+residual>0
        if. d>0 do.
            difference =. residual-(d-1){Residuals
            difference_sum =. difference_sum+difference*difference
            if. (residual>0)~:0<(d-1){Residuals do. runs =. runs+1 end.
        end.
    end.
    ReportedTotal =: cumulative_reported
    largest =. peak |Residuals
    fit_line 'residuals sum';(one sum_real Residuals);'mae';(one (sum_real |Residuals)%Days);'max';(one largest{Residuals);'day';(largest+1);'positive';positive;'runs';runs;'durbin_watson';fixed difference_sum%u
    correlations =. i.0
    for_lag. 1+i.7 do.
        total =. 0.0
        for_d. i.Days-lag do. total =. total+(d{Residuals)*(d+lag){Residuals end.
        correlations =. correlations,total%u
    end.
    fit_line 'autocorrelation';4 formatted correlations
    outliers =. 0
    for_d. i.Days do.
        z =. (d{Residuals)%%:d{Reported
        if. (|z)>OutlierThreshold do.
            fit_line 'outlier';(d+1);'observed';(d{Cases);'fitted';(one d{Reported);'z';fixed z
            outliers =. outliers+1
        end.
    end.
    fit_line 'outliers';outliers
    factors =. i.0
    for_weekday. i.7 do.
        indices =. I.weekday=7|i.Days
        observed =. +/indices{Cases
        fitted =. sum_real indices{Reported
        factor =. observed%fitted
        factors =. factors,factor
        fit_line 'weekday';(weekday+1);'observed';observed;'fitted';(one fitted);'factor';fixed factor
    end.
    adjusted =. Reported*(7|i.Days){factors
    error =. squared_errors (<adjusted),(<1.0),<Cases
    fit_line 'weekday_adjusted rmse';fixed rmse_all error
    infections =. sum_real Incidence
    fit_line 'burden infections';(one infections);'ascertainment';(fixed CaseTotal%infections);'deaths_per_infection';six DeathTotal%infections
    death_analysis ''
    previous =. 0
    for_week. i.#WeekRanges do.
        'first last' =. week{WeekRanges
        observed =. +/(first,last)slice Cases
        fitted =. sum_real (first,last)slice Reported
        deaths =. +/(first,last)slice Deaths
        modeldeaths =. sum_real (first,last)slice ModelDeaths
        growth =. '-'
        if. week>0 do. growth =. fixed observed%previous end.
        fit_line 'weekly';(week+1);'days';(first+1);(last+1);'observed';observed;'fitted';(one fitted);'deaths_observed';deaths;'deaths_model';(one modeldeaths);'growth';growth
        previous =. observed
    end.
    i.0 0
)
profiles =: 3 : 0
    fitted =. BetaHat,GammaHat,RhoHat
    names =. 'beta';'gamma';'rho'
    variance =. SSENM%(Days-3)
    StandardErrors =: i.0
    for_index. i.3 do.
        value =. index{fitted
        errors =. i.0
        for_offset. _5+i.11 do.
            point =. value*(1+offset%100)
            parameters =. point index}fitted
            error =. error_value parameters
            errors =. errors,error
            fit_line 'profile';(index{::names);offset;'value';(six point);'rmse';fixed rmse_all error
        end.
        h =. value%100
        curvature =. (((6{errors)-2*5{errors)+4{errors)%(h*h)
        standard_error =. %:(2*variance)%curvature
        StandardErrors =: StandardErrors,standard_error
        fit_line 'profile_se';(index{::names);six standard_error
    end.
    i.0 0
)
limited_beta_error =: 4 : 0
    'gamma rho multipliers observations' =. x
    states =. seird_states (<y),(<gamma),(<Sigma),(<multipliers),<InitialState
    squared_errors (<5{"1 states),(<rho),<observations
)
rho_series_error =: 4 : 0
    'incidence observations' =. x
    squared_errors (<incidence),(<y),<observations
)
backtest =: 3 : 0
    number =. Days-Holdout
    observations =. number{.Cases
    multipliers =. number{.Multipliers
    context =. (<GammaHat),(<RhoHat),(<multipliers),<observations
    objective =. context&limited_beta_error
    'beta value records' =. objective golden (<BetaHat-DeltaBeta),(<BetaHat+DeltaBeta),<GoldenIterations
    fullincidence =. incidence_for beta,GammaHat
    context =. (<number{.fullincidence),<observations
    objective =. context&rho_series_error
    'rho value records' =. objective golden (<RhoHat-DeltaRho),(<RhoHat+DeltaRho),<GoldenIterations
    forecasts =. rho*number}.fullincidence
    actual =. number}.Cases
    error =. squared_errors (<forecasts),(<1.0),<actual
    fullerror =. squared_errors (<number}.Reported),(<1.0),<actual
    fit_line 'backtest train_days';number;'beta';(six beta);'rho';(six rho);'train_rmse';(fixed value rmse number);'test_rmse';(fixed error rmse Holdout);'full_fit_test_rmse';fixed fullerror rmse Holdout
    for_i. i.Holdout do.
        fit_line 'backtest_day';(number+i+1);'observed';(i{actual);'forecast';(one i{forecasts);'error';one (i{actual)-i{forecasts
    end.
    i.0 0
)
effect_error =: 4 : 0
    'interventions index' =. x
    changed =. y(<index,1)}interventions
    multipliers =. changed multipliers_for Days
    states =. seird_states (<BetaHat),(<GammaHat),(<Sigma),(<multipliers),<InitialState
    squared_errors (<5{"1 states),(<RhoHat),<Cases
)
estimate_effects =: 3 : 0
    estimated =. Interventions
    after =. SSENM
    for_index. 1+i.(#Interventions)-1 do.
        'day given' =. index{Interventions
        context =. (<estimated),<index
        objective =. context&effect_error
        'value after records' =. objective golden (<given-EffectWidth),(<given+EffectWidth),<GoldenIterations
        estimated =. value(<index,1)}estimated
        fit_line 'effect';(index+1);'day';day;'given';(fixed given);'estimated';(six value);'sse';one after
    end.
    fit_line 'effect_sse before';(one SSENM);'after';(one after);'rmse';fixed rmse_all after
    i.0 0
)
sensitivity =: 3 : 0
    names =. 'beta';'gamma';'sigma';'rho'
    for_index. i.4 do.
        for_factor. 0.9 1.1 do.
            parameters =. BetaHat,GammaHat,Sigma,RhoHat
            parameters =. (factor*index{parameters)index}parameters
            'beta gamma sigma rho' =. parameters
            states =. seird_states (<beta),(<gamma),(<sigma),(<Multipliers),<InitialState
            incidence =. 5{"1 states
            day =. peak incidence
            error =. squared_errors (<incidence),(<rho),<Cases
            attack =. (Population-(<(Days-1),0){states)%Population
            fit_line 'sensitivity';(index{::names);(2 format_real factor);'r0';(fixed beta%gamma);'rmse';(fixed rmse_all error);'peak_day';(day+1);'peak';(one rho*day{incidence);'attack';fixed attack
        end.
    end.
    i.0 0
)
power_method =: 3 : 0
    vector =. (#y)$1%#y
    for_iteration. i.200 do.
        product =. i.0
        for_row. y do.
            total =. 0.0
            for_h. i.#vector do. total =. total+(h{row)*h{vector end.
            product =. product,total
        end.
        eigenvalue =. sum_real product
        vector =. product%eigenvalue
    end.
    (<eigenvalue),<vector
)
age_states_for =: 3 : 0
    'contacts multipliers initial' =. y
    parameters =. (<Populations),(<Fatalities),(<Sigma),(<BetaHat),(<GammaHat),<contacts
    rates =. parameters&age_rates
    rates simulate (<initial),(<multipliers),<AgeInflows
)
next_generation =: 3 : 0
    matrix =. (Groups,Groups)$0.0
    for_g. i.Groups do.
        for_h. i.Groups do.
            value =. ((R0*(<g,h){y)*g{Populations)%h{Populations
            matrix =. value(<g,h)}matrix
        end.
    end.
    matrix
)
age_line =: 3 : 'AgeLines =: AgeLines,<emit y'
analyze_age =: 3 : 0
    total =. 0.0
    for_g. i.Groups do. total =. total+(g{Populations)*sum_real g{Contacts end.
    Kbar =: total%Population
    NormalizedContacts =: Contacts%Kbar
    matrix =. next_generation NormalizedContacts
    'reproduction eigenvector' =. power_method matrix
    AgeLines =: 0$a:
    for_g. i.Groups do. age_line 'ngm';(g{::GroupNames);4 formatted g{matrix end.
    age_line 'r0_age';(fixed reproduction);'ratio';(fixed reproduction%R0);'kbar';(fixed Kbar);'eigenvector';4 formatted eigenvector
    final =. Groups$1.0
    for_iteration. i.100 do.
        changed =. i.0
        for_g. i.Groups do.
            pressure =. 0.0
            for_h. i.Groups do. pressure =. pressure+(R0*(<g,h){NormalizedContacts)*h{final end.
            changed =. changed,1-^-pressure
        end.
        final =. changed
    end.
    longstates =. age_states_for (<NormalizedContacts),(<730$1.0),<AgeInitial
    last =. {:longstates
    simulated =. i.0
    for_g. i.Groups do.
        value =. ((g{Populations)-(6*g){last)%g{Populations
        simulated =. simulated,value
        age_line 'final_size_age';(g{::GroupNames);'equation';(fixed g{final);'simulated';fixed value
    end.
    overall =. (sum_real Populations*final)%Population
    simulatedtotal =. (sum_real Populations*simulated)%Population
    age_line 'final_size_age total equation';(fixed overall);'simulated';fixed simulatedtotal
    AgeStates =: age_states_for (<NormalizedContacts),(<Multipliers),<AgeInitial
    AgeIncidence =: i.0
    for_state. AgeStates do. AgeIncidence =: AgeIncidence,sum_real AgeInflows{state end.
    for_d. 7*i.>.(Days%7) do.
        if. d=0 do. previous =. AgeInitial else. previous =. (d-1){AgeStates end.
        current =. (Groups,Groups)$0.0
        for_g. i.Groups do.
            for_h. i.Groups do.
                value =. ((((d{Multipliers)*R0)*(<g,h){NormalizedContacts)*(6*g){previous)%h{Populations
                current =. value(<g,h)}current
            end.
        end.
        reproduction =. 0{::power_method current
        age_line 'age_rt';(d+1);(fixed reproduction);'homogeneous';fixed d{Rt
    end.
    for_week. i.#WeekRanges do.
        'first last' =. week{WeekRanges
        totals =. i.0
        for_g. i.Groups do.
            series =. (5+6*g){"1 AgeStates
            totals =. totals,sum_real (first,last)slice series
        end.
        age_line 'age_weekly';(week+1);'days';(first+1);(last+1);1 formatted totals
    end.
    infections =. i.0
    for_g. i.Groups do. infections =. infections,sum_real (5+6*g){"1 AgeStates end.
    infectiontotal =. sum_real infections
    last =. {:AgeStates
    for_g. i.Groups do.
        series =. (5+6*g){"1 AgeStates
        day =. peak series
        attack =. ((g{Populations)-(6*g){last)%g{Populations
        age_line 'age';(g{::GroupNames);'attack';(fixed attack);'infections';(one g{infections);'share';(fixed (g{infections)%infectiontotal);'deaths';(one (4+6*g){last);'peak_day';(day+1);'peak';one day{series
    end.
    for_change. ContactChanges do.
        'name target factor' =. >change
        targetnumber =. GroupNames i.<target
        contacts =. NormalizedContacts
        for_g. i.Groups do.
            tau_g =. 1.0
            if. g=targetnumber do. tau_g =. factor end.
            for_h. i.Groups do.
                tau_h =. 1.0
                if. h=targetnumber do. tau_h =. factor end.
                value =. (((<g,h){NormalizedContacts)*tau_g)*tau_h
                contacts =. value(<g,h)}contacts
            end.
        end.
        reproduction =. 0{::power_method next_generation contacts
        states =. age_states_for (<contacts),(<Multipliers),<AgeInitial
        infections =. 0.0
        for_state. states do. infections =. infections+sum_real AgeInflows{state end.
        last =. {:states
        deaths =. attack =. 0.0
        for_g. i.Groups do.
            deaths =. deaths+(4+6*g){last
            attack =. attack+(g{Populations)-(6*g){last
        end.
        age_line 'contact_change';name;'group';target;'factor';(fixed factor);'r0_age';(fixed reproduction);'infections';(one infections);'deaths';(one deaths);'attack';fixed attack%Population
    end.
    i.0 0
)
sir_incidence =: 3 : 0
    parameters =. Population,y,GammaHat
    rates =. parameters&sir_rates
    states =. rates simulate (<SIRInitial),(<Multipliers),<,3
    3{"1 states
)
sir_error =: 4 : 0
    incidence =. sir_incidence y
    squared_errors (<incidence),(<x),<Cases
)
compare_models =: 3 : 0
    names =. 'sir';'seir';'age'
    series =. (<sir_incidence BetaHat),(<Incidence),<AgeIncidence
    for_index. i.3 do.
        incidence =. index{::series
        numerator =. sum_real Cases*incidence
        denominator =. sum_real incidence*incidence
        rho =. numerator%denominator
        error =. squared_errors (<incidence),(<RhoHat),<Cases
        optimal =. squared_errors (<incidence),(<rho),<Cases
        fit_line 'model';(index{::names);'rmse';(fixed rmse_all error);'peak_day';(1+peak incidence);'rho_opt';(six rho);'rmse_opt';fixed rmse_all optimal
    end.
    objective =. RhoHat&sir_error
    'beta error records' =. objective golden (<0{BetaRange),(<1{BetaRange),<GoldenIterations
    fit_line 'model sir_fit beta';(six beta);'rmse';(fixed rmse_all error);'peak_day';1+peak sir_incidence beta
    i.0 0
)
final_size =: 3 : 0
    if. y<:1 do. 0.0 return. end.
    lo =. 1-1%y
    hi =. 1.0
    for_iteration. i.20 do.
        mid =. (lo+hi)%2
        g =. (1-mid)-^((-y)*mid)
        if. g>0 do. lo =. mid else. hi =. mid end.
    end.
    (lo+hi)%2
)
generation_interval =: 3 : 0
    parameters =. Sigma,GammaHat
    rates =. parameters&generation_rates
    states =. rates simulate (<1.0 0.0 0.0),(<GenerationDays$1.0),<,2
    amounts =. 2{"1 states
    coverage =. sum_real amounts
    weights =. amounts%coverage
    mean =. sum_real ((i.GenerationDays)+0.5)*weights
    rep_line 'generation mean';(fixed mean);'theory';(fixed (1%Sigma)+1%GammaHat);'coverage';fixed coverage
    for_i. i.GenerationDays do. rep_line 'generation_weight';(i+1);six i{weights end.
    pressures =. i.0
    for_d. i.Days do.
        total =. 0.0
        for_lag. 1+i.GenerationDays<.d do. total =. total+((lag-1){weights)*(d-lag){Cases end.
        pressures =. pressures,total
    end.
    EmpiricalRt =: Days$_1.0
    for_d. (GenerationDays+6)+i.0>.Days-(GenerationDays+6) do.
        observed =. +/((d-6),d)slice Cases
        pressure =. sum_real ((d-6),d)slice pressures
        EmpiricalRt =: (observed%pressure)d}EmpiricalRt
    end.
    i.0 0
)
epidemic_peaks =: 3 : 0
    day =. peak Incidence
    infectious =. 2{"1 States
    infectiousday =. peak infectious
    rep_line 'peak model day';(day+1);'incidence';(one day{Incidence);'reported';(one day{Reported);'infectious_day';(infectiousday+1);'infectious';one infectiousday{infectious
    observedday =. peak Cases
    averageday =. peak Averages
    rep_line 'peak observed day';(observedday+1);'cases';(observedday{Cases);'average7_day';(averageday+1);'average7';2 format_real averageday{Averages
    i.0 0
)
periods_and_milestones =: 3 : 0
    for_index. i.#Interventions do.
        'day multiplier' =. index{Interventions
        first =. (<.day)-1
        last =. Days-1
        if. (index+1)<#Interventions do. last =. ((<(index+1),0){Interventions)-2 end.
        residuals =. (first,last)slice Residuals
        error =. sum_real residuals*residuals
        number =. 1+last-first
        observed =. +/(first,last)slice Cases
        fitted =. sum_real (first,last)slice Reported
        bias =. (sum_real residuals)%number
        rep_line 'period';(index+1);'days';(first+1);(last+1);'multiplier';(fixed multiplier);'rt_start';(fixed first{Rt);'rt_end';(fixed last{Rt);'observed';observed;'fitted';(one fitted);'rmse';(fixed error rmse number);'bias';one bias
    end.
    for_target. Milestones do.
        observed =. fitted =. 'never'
        indices =. I.CumulativeCases>:target
        if. #indices do. observed =. integer 1+{.indices end.
        indices =. I.CumulativeReported>:target
        if. #indices do. fitted =. integer 1+{.indices end.
        rep_line 'milestone';target;'observed';observed;'fitted';fitted
    end.
    i.0 0
)
counterfactual_series =: 3 : 0
    multipliers =. y multipliers_for Days
    states =. seird_states (<BetaHat),(<GammaHat),(<Sigma),(<multipliers),<InitialState
    RhoHat*5{"1 states
)
counterfactuals =: 3 : 0
    reported =. counterfactual_series 1{.Interventions
    total =. sum_real reported
    day =. peak reported
    rep_line 'counterfactual none reported';(one total);'peak_day';(day+1);'peak';(one day{reported);'averted';one total-ReportedTotal
    for_index. 1+i.(#Interventions)-1 do.
        changed =. (index~:i.#Interventions)#Interventions
        total =. sum_real counterfactual_series changed
        rep_line 'counterfactual without';(index+1);'reported';(one total);'averted';one total-ReportedTotal
    end.
    for_index. 1+i.(#Interventions)-1 do.
        for_shift. _7 7 do.
            day =. shift+(<index,0){Interventions
            changed =. day(<index,0)}Interventions
            total =. sum_real counterfactual_series changed
            rep_line 'timing';(index+1);'shift';shift;'reported';(one total);'change';one total-ReportedTotal
        end.
    end.
    i.0 0
)
analyze_reproduction =: 3 : 0
    rep_line 'r0';(fixed R0);'herd_immunity';fixed 1-1%R0
    longstates =. seird_states (<BetaHat),(<GammaHat),(<Sigma),(<730$1.0),<InitialState
    simulated =. (Population-(<729,0){longstates)%Population
    rep_line 'final_size equation';(fixed final_size R0);'simulated';fixed simulated
    generation_interval ''
    epidemic_peaks ''
    periods_and_milestones ''
    counterfactuals ''
    for_d. 1+i.Days-1 do.
        if. ((d{Rt)<1)~:((d-1){Rt)<1 do.
            direction =. ((d{Rt)<1){::'up';'down'
            rep_line 'rt_cross day';(d+1);direction
        end.
    end.
    for_d. i.Days do.
        empirical =. '-'
        if. d>:GenerationDays+6 do. empirical =. fixed d{EmpiricalRt end.
        rep_line 'rt';(d+1);'model';(fixed d{Rt);'empirical';empirical
    end.
    ReproductionLines =: ReproductionLines,AgeLines
    i.0 0
)
scenario_projections =: 3 : 0
    ScenarioRows =: <'scenario,day,incidence,reported'
    for_index. i.#ScenarioDefs do.
        'name multiplier' =. index{::ScenarioDefs
        future =. Horizon$multiplier
        states =. seird_states (<BetaHat),(<GammaHat),(<Sigma),(<future),<{:States
        incidence =. 5{"1 states
        reported =. RhoHat*incidence
        total =. sum_real reported
        below =. _1
        above =. 0
        for_j. i.Horizon do.
            value =. j{reported
            fields =. (<name),(<integer Days+j+1),(<one j{incidence),<one value
            ScenarioRows =: ScenarioRows,<','join fields
            if. (value<Threshold)*.below=_1 do. below =. Days+j+1 end.
            above =. above+value>:Threshold
        end.
        if. index=0 do. baseline =. total end.
        belowtext =. 'never'
        if. below>:0 do. belowtext =. integer below end.
        day =. peak reported
        reproduction =. ((R0*multiplier)*(<(Days-1),0){States)%Population
        attack =. (Population-(<(Horizon-1),0){states)%Population
        rep_line 'scenario';name;'multiplier';(fixed multiplier);'rt';(fixed reproduction);'reported';(one total);'peak_day';(Days+day+1);'peak';(one day{reported);'attack';(fixed attack);'final_size';(fixed final_size R0*multiplier);'averted';(one baseline-total);'below';belowtext;'days_above';above
        beta_low =. BetaHat-2*0{StandardErrors
        beta_high =. BetaHat+2*0{StandardErrors
        fullmultipliers =. Multipliers,future
        band =. i.0
        for_beta. beta_low,beta_high do.
            full =. seird_states (<beta),(<GammaHat),(<Sigma),(<fullmultipliers),<InitialState
            value =. sum_real RhoHat*Days}.5{"1 full
            band =. band,value
        end.
        rep_line 'scenario_band';name;'beta_low';(six beta_low);'reported_low';(one 0{band);'beta_high';(six beta_high);'reported_high';one 1{band
        agefuture =. age_states_for (<NormalizedContacts),(<future),<{:AgeStates
        last =. {:agefuture
        attacks =. i.0
        deaths =. 0.0
        for_g. i.Groups do.
            attacks =. attacks,((g{Populations)-(6*g){last)%g{Populations
            deaths =. deaths+(4+6*g){last
        end.
        rep_line 'scenario_age';name;'attack';(4 formatted attacks);'deaths';one deaths
    end.
    i.0 0
)
trajectories =: 3 : 0
    lines =. <'day,S,E,I,R,D,incidence,reported,observed,average7,cumulative_observed,cumulative_reported'
    for_d. i.Days do.
        fields =. <integer d+1
        fields =. fields,(1&format_real)&.>d{States
        fields =. fields,(<one d{Reported),(<integer d{Cases),(<2 format_real d{Averages),(<integer d{CumulativeCases),<one d{CumulativeReported
        lines =. lines,<','join fields
    end.
    lines
)
main =: 3 : 0
    read_inputs ''
    prepare ''
    fit_model ''
    fitted_diagnostics ''
    profiles ''
    backtest ''
    estimate_effects ''
    sensitivity ''
    analyze_age ''
    compare_models ''
    analyze_reproduction ''
    scenario_projections ''
    'fit.txt'write_lines FitLines
    'trajectories.csv'write_lines trajectories ''
    'scenarios.csv'write_lines ScenarioRows
    'reproduction.txt'write_lines ReproductionLines
    'curve_plot.txt'write_lines Cases plot_curve Reported
    i.0 0
)
main ''
