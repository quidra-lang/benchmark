parse_number =: 3 : '". ''_''(I.y=''-'')}y'
split_words =: 3 : '<;._1 '' '',y'
read_inputs =: 3 : 0
    Cases =: Deaths =: i.0
    for_line. }. <;._2 (1!:1 <'input/cases.csv') do.
        fields =. <;._1 ',',>line
        Cases =: Cases,parse_number 1{::fields
        Deaths =: Deaths,parse_number 2{::fields
    end.
    GroupNames =: 0$a:
    Populations =: i.0
    Fatalities =: i.0
    contacts =. 0$a:
    for_line. <;._2 (1!:1 <'input/population.txt') do.
        fields =. split_words >line
        if. (0{::fields)-:'group' do.
            GroupNames =: GroupNames,<1{::fields
            Populations =: Populations,parse_number 2{::fields
            Fatalities =: Fatalities,0.0+parse_number 3{::fields
        else. contacts =. contacts,<0.0+parse_number&>}.fields end.
    end.
    Contacts =: >contacts
    Interventions =: 0 2$0.0
    for_line. <;._2 (1!:1 <'input/interventions.txt') do.
        Interventions =: Interventions,0.0+parse_number&>split_words >line
    end.
    ScenarioDefs =: ContactChanges =: 0$a:
    for_line. <;._2 (1!:1 <'input/params.txt') do.
        fields =. split_words >line
        select. 0{::fields
        case. 'sigma' do. Sigma =: 0.0+parse_number 1{::fields
        case. 'gamma' do. Gamma0 =: 0.0+parse_number 1{::fields
        case. 'initial' do. InitialEI =: 0.0+parse_number&>}.fields
        case. 'beta_grid' do.
            BetaRange =: 0.0+parse_number&>1 2{fields
            BetaCount =: parse_number 3{::fields
        case. 'rho_grid' do.
            RhoRange =: 0.0+parse_number&>1 2{fields
            RhoCount =: parse_number 3{::fields
        case. 'golden' do. 'GoldenIterations CoordinateRounds' =: parse_number&>}.fields
        case. 'simplex' do. SimplexStep =: 0.0+parse_number&>}.fields
        case. 'nelder_mead' do.
            NMFactors =: 0.0+parse_number&>1 2 3 4{fields
            NMIterations =: parse_number 5{::fields
        case. 'holdout' do. Holdout =: parse_number 1{::fields
        case. 'effect_width' do. EffectWidth =: 0.0+parse_number 1{::fields
        case. 'outlier' do. OutlierThreshold =: 0.0+parse_number 1{::fields
        case. 'death_lag' do. DeathLag =: parse_number 1{::fields
        case. 'milestones' do. Milestones =: parse_number&>}.fields
        case. 'generation' do. GenerationDays =: parse_number 1{::fields
        case. 'horizon' do. Horizon =: parse_number 1{::fields
        case. 'threshold' do. Threshold =: 0.0+parse_number 1{::fields
        case. 'scenario' do.
            ScenarioDefs =: ScenarioDefs,<(<1{::fields),<0.0+parse_number 2{::fields
        case. 'contact_change' do.
            ContactChanges =: ContactChanges,<(<1{::fields),(<2{::fields),<0.0+parse_number 3{::fields
        end.
    end.
    i.0 0
)
write_lines =: 4 : 0
    text =. ''
    for_line. y do. text =. text,(>line),LF end.
    text 1!:2 <'output/',x
    i.0 0
)
