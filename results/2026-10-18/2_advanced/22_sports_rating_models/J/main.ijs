ScriptPath =: >{:4!:3''
SourceDirectory =: (1+>./_1,I.ScriptPath e.'/\'){.ScriptPath
Digits =: '0123456789'
RatingModels =: 'elo';'colley';'massey';'bt';'od';'winpct'
ComparisonModels =: 'standings';'elo';'colley';'massey';'bt';'od';'winpct';'rpi';'pythag'
PredictionModels =: 'base';'elo';'colley';'massey';'bt';'od';'winpct';'ensemble'
LinkModels =: 'colley';'massey';'od';'winpct'
div =: 4 : '_1 x:<.(x:x)%x:y'
num =: 3 : '10#.Digits i.y'
number =: 3 : 0
    prefix =. ''
    if. y<0 do. prefix =. '-'
        y =. -y end.
    text =. ''
    while. y>0 do. text =. ((10|y){Digits),text
        y =. y div 10 end.
    if. #text do. prefix,text else. '0' end.
)
split =: 4 : 0
    parts =. 0$a:
    while. 1 do.
        position =. y i.x
        parts =. parts,<position{.y
        if. position=#y do. parts return. end.
        y =. (position+1)}.y
    end.
)
join =: 4 : 0
    text =. ''
    for_index. i.#y do.
        if. index do. text =. text,x end.
        value =. index{::y
        if. 2~:3!:0 value do. value =. number value end.
        text =. text,value
    end.
    text
)
format =: 4 : 0
    parts =. '|' split x
    text =. 0{::parts
    for_index. i.#y do.
        value =. index{::y
        if. 2~:3!:0 value do. value =. number value end.
        text =. text,value,(index+1){::parts
    end.
    text
)
sequential_sum =: 3 : 0
    total =. 0.0
    for_value. y do. total =. total+value end.
    total
)
mean =: 3 : '(sequential_sum y)%#y'
read_lines =: 3 : '<;._2 (1!:1 <''input/'',y)'
load SourceDirectory,'report.ijs'
load SourceDirectory,'season.ijs'
load SourceDirectory,'elo.ijs'
load SourceDirectory,'linear_models.ijs'
load SourceDirectory,'iterative_models.ijs'
load SourceDirectory,'evaluation.ijs'
team_records =: 3 : 0
    records =. (TeamCount,8)$0
    for_match. y do.
        'round home away first second' =. match
        for_side. 0 1 do.
            if. side=0 do. team =. home
                scored =. first
                conceded =. second
            else. team =. away
                scored =. second
                conceded =. first end.
            row =. team{records
            row =. (1+0{row)0}row
            row =. (scored+4{row)4}row
            row =. (conceded+5{row)5}row
            if. scored>conceded do. row =. (1+1{row)1}row
                row =. (WinPoints+6{row)6}row
            elseif. scored=conceded do. row =. (1+2{row)2}row
                row =. (DrawPoints+6{row)6}row
            else. row =. (1+3{row)3}row end.
            row =. ((4{row)-5{row)7}row
            records =. row team}records
        end.
    end.
    records
)
standings =: 3 : 0
    records =. team_records y
    points =. 6{"1 records
    headpoints =. headdiff =. TeamCount$0
    for_value. ~.points do.
        members =. I.points=value
        inner =. 0 5$0
        for_match. y do.
            if. ((1{match)e.members)*.(2{match)e.members do. inner =. inner,match end.
        end.
        table =. team_records inner
        headpoints =. (6{"1 members{table)members}headpoints
        headdiff =. (7{"1 members{table)members}headdiff
    end.
    order =. /:(-points),.(-headpoints),.(-headdiff),.(-7{"1 records),.(-4{"1 records),.i.TeamCount
    positions =. 1+/:order
    (<records),(<headpoints),(<headdiff),(<order),<positions
)
percentages =: 3 : 0
    pairs =. 0 2$0
    for_row. y do. pairs =. pairs,reduced_fraction ((2*1{row)+2{row),2*0{row end.
    pairs
)
fit_models =: 3 : 0
    elo =. (EloK,EloHome,EloInitial)run_elo y
    colley =. colley_ratings y
    'massey home' =. massey_ratings y
    'bt theta' =. bradley_terry y
    'offense defense od' =. offense_defense y
    wp =. percentages team_records y
    (<elo),(<colley),(<massey),(<home),(<bt),(<theta),(<offense),(<defense),(<od),<wp
)
feature =: 4 : 0
    'fit match' =. y
    home =. 1{match
    away =. 2{match
    if. x=0 do. values =. 1{::fit
    elseif. x=1 do. values =. 2{::fit
    elseif. x=2 do. values =. ^.8{::fit
    else. wp =. 9{::fit
        (frac_real home{wp)-frac_real away{wp return. end.
    (home{values)-away{values
)
competition_ranks =: 3 : 0
    result =. 0$0
    for_value. y do.
        rank =. 1
        for_other. y do. rank =. rank+0<other frac_compare value end.
        result =. result,rank
    end.
    result
)
comparison_real =: 4 : '(x decimal_value y),.(#y)$1'
build_appearances =: 3 : 0
    Appearances =: TeamCount$<0 6$0
    for_index. i.#Matches do.
        match =. index{Matches
        'round home away first second' =. match
        result =. match_result match
        Appearances =: (<(home{::Appearances),index,away,first,second,1,result)home}Appearances
        Appearances =: (<(away{::Appearances),index,home,second,first,0,2-result)away}Appearances
    end.
    i.0
)
standings_lines =: 3 : 0
    lines =. <'pos,team,name,played,won,drawn,lost,scored,conceded,diff,points,home,away,form,streak,close,longest_win,longest_unbeaten,winpct,sos,sos2,rpi,pythag,luck'
    'records headpoints headdiff order positions' =. FinalTable
    wp =. 9{::FinalFit
    for_team. order do.
        record =. team{records
        items =. team{::Appearances
        home =. items#~4{"1 items
        away =. items#~-.4{"1 items
        close =. items#~CloseMargin>:|(2{"1 items)-3{"1 items
        form =. (5{"1 (-FormLength){.items){'LDW'
        lastresult =. 5{({:items)
        length =. 0
        for_index. |.i.#items do.
            if. lastresult~:(<index,5){items do. break. end.
            length =. length+1
        end.
        streak =. (lastresult{'LDW'),number length
        fields =. (<team{positions),(team{TeamIds),(team{TeamNames),<"0 (0 1 2 3 4 5 7 6){record
        fields =. fields,(<record_text home),(<record_text away),(<form),(<streak),(<record_text close)
        fields =. fields,(<(<team,0){WinStreaks),(<(<team,0){UnbeatenStreaks),(<fraction_text team{wp)
        fields =. fields,(<fixed_fraction team{Sos),(<fixed_fraction team{Sos2),(<fixed_fraction team{Rpi),(<fixed team{Pythag),<fixed team{Luck
        lines =. lines,<',' join fields
    end.
    lines
)
ratings_lines =: 3 : 0
    'elo colley massey home bt theta offense defense od wp' =. FinalFit
    totals =. TeamCount$0
    for_ranks. ModelRanks do. totals =. totals+>ranks end.
    order =. /:totals,.i.TeamCount
    lines =. <'team,elo,elo_rank,colley,colley_rank,massey,massey_rank,bt,bt_rank,offense,defense,od,od_rank,winpct,winpct_rank,consensus,best_rank,worst_rank'
    for_team. order do.
        ranks =. 0$0
        for_model. ModelRanks do. ranks =. ranks,team{>model end.
        fields =. (team{TeamIds),(<2 fixed team{0{::elo),(<0{ranks),(<fixed team{colley),(<1{ranks),(<fixed team{massey),(<2{ranks)
        fields =. fields,(<fixed team{bt),(<3{ranks),(<2 fixed team{offense),(<fixed team{defense),(<2 fixed team{od),(<4{ranks)
        fields =. fields,(<fixed_fraction team{wp),(<5{ranks),(<team{totals),(< <./ranks),< >./ranks
        lines =. lines,<',' join fields
    end.
    lines
)
history_lines =: 3 : 0
    lines =. <'round,team,elo,change,elo_rank,points,position'
    previous =. TeamCount$EloInitial+0.0
    snapshots =. 3{::0{::FinalFit
    for_index. i.FinalRound do.
        ratings =. index{::snapshots
        ranks =. competition_ranks 2 comparison_real ratings
        table =. index{::RoundTables
        records =. 0{::table
        positions =. 4{::table
        for_team. i.TeamCount do.
            fields =. (<index+1),(team{TeamIds),(<2 fixed team{ratings),(<2 fixed (team{ratings)-team{previous),(<team{ranks),(<(<team,6){records),<team{positions
            lines =. lines,<',' join fields
        end.
        previous =. ratings
    end.
    lines
)
summary_lines =: 3 : 0
    results =. 0$0
    for_match. Matches do. results =. results,match_result match end.
    lines =. <'season teams | matches | rounds |' format (<TeamCount),(<#Matches),<FinalRound
    rate =. reduced_fraction (+/results),2*#Matches
    lines =. lines,<'home won | drawn | lost | rate |' format (<+/results=2),(<+/results=1),(<+/results=0),<fraction_real_text rate
    lines =. lines,<'massey_home_advantage ',fixed 3{::FinalFit
    lines,<'bt_home_factor ',fixed 5{::FinalFit
)
upset_lines =: 3 : 0
    expected =. 1{::0{::FinalFit
    changes =. 2{::0{::FinalFit
    candidates =. 0 3$0.0
    for_index. i.#Matches do.
        match =. index{Matches
        margin =. (3{match)-4{match
        if. margin=0 do. continue. end.
        probability =. index{expected
        if. margin<0 do. probability =. 1-probability end.
        candidates =. candidates,index,probability,|index{changes
    end.
    order =. /:(4 decimal_value 1{"1 candidates),.0{"1 candidates
    candidates =. (UpsetLimit<.#candidates){.order{candidates
    lines =. <'upsets top ',number UpsetLimit
    for_candidate. candidates do.
        'index probability gain' =. candidate
        match =. index{Matches
        'round home away first second' =. match
        if. first>second do. winner =. home
            loser =. away
            side =. 'home'
            score =. first,second
        else. winner =. away
            loser =. home
            side =. 'away'
            score =. second,first end.
        lines =. lines,<'round | | beat | |-| | expected | gain |' format (<round),(winner{TeamIds),(loser{TeamIds),(<0{score),(<1{score),(<side),(<fixed probability),<2 fixed gain
    end.
    lines
)
tiebreak_lines =: 3 : 0
    'records headpoints headdiff order positions' =. FinalTable
    points =. 6{"1 records
    lines =. <'tiebreaks'
    for_value. ~.order{points do.
        group =. order#~value=order{points
        if. (#group)<2 do. continue. end.
        lines =. lines,<'points | order | h2h_points | h2h_diff |' format (<value),(< ' ' join group{TeamIds),(< ' ' join <"0 group{headpoints),< ' ' join <"0 group{headdiff
    end.
    if. (#lines)=1 do. lines =. lines,<'none' end.
    lines
)
leader_lines =: 3 : 0
    previous =. _1
    count =. 0
    lines =. <'leaders'
    for_index. i.#RoundTables do.
        table =. index{::RoundTables
        leader =. {.3{::table
        if. leader~:previous do.
            lines =. lines,<'round | | points |' format (<index+1),(leader{TeamIds),<(<leader,6){0{::table
            count =. count+1
        end.
        previous =. leader
    end.
    lines,<'lead_changes ',number count-1
)
streak_lines =: 3 : 0
    lines =. 0$a:
    for_kind. i.2 do.
        if. kind=0 do. streaks =. WinStreaks
            label =. 'longest_win_streak'
        else. streaks =. UnbeatenStreaks
            label =. 'longest_unbeaten_streak' end.
        longest =. >./0{"1 streaks
        for_team. I.longest=0{"1 streaks do.
            'length first last' =. team{streaks
            lines =. lines,<'| | length | rounds |-|' format (<label),(team{TeamIds),(<length),(<first),<last
        end.
    end.
    lines
)
crosstable_lines =: 3 : 0
    top =. TopPositions{.3{::FinalTable
    lines =. (<'crosstable top ',number TopPositions),<'team ',' ' join top{TeamIds
    for_first. top do.
        row =. first{TeamIds
        for_second. top do.
            if. first=second do. row =. row,<'-'
            else.
                items =. first{::Appearances
                row =. row,<record_text items#~second=1{"1 items
            end.
        end.
        lines =. lines,<' ' join row
    end.
    lines
)
trajectory_lines =: 3 : 0
    snapshots =. 3{::0{::FinalFit
    lines =. <'trajectories'
    for_team. i.TeamCount do.
        ratings =. 0$0.0
        positions =. 0$0
        for_index. i.FinalRound do.
            ratings =. ratings,team{index{::snapshots
            positions =. positions,team{4{::index{::RoundTables
        end.
        rounded =. 2 decimal_value ratings
        peak =. rounded i.>./rounded
        low =. rounded i.<./rounded
        best =. positions i.<./positions
        worst =. positions i.>./positions
        lines =. lines,<'| elo_peak | round | elo_low | round | best_position | round | worst_position | round |' format (team{TeamIds),(<2 fixed peak{ratings),(<peak+1),(<2 fixed low{ratings),(<low+1),(<best{positions),(<best+1),(<worst{positions),<worst+1
    end.
    lines
)
correlation_lines =: 3 : 0
    title =. 'kendall'
    if. y do. title =. 'spearman' end.
    lines =. (<title),<'model ',' ' join ComparisonModels
    for_first. i.9 do.
        row =. first{ComparisonModels
        for_second. i.9 do.
            if. y do. value =. (first{::Comparisons)spearman_rho second{::Comparisons
            else. value =. (first{::Comparisons)kendall_tau second{::Comparisons end.
            row =. row,<fraction_text value
        end.
        lines =. lines,<' ' join row
    end.
    lines
)
similarity_lines =: 3 : 0
    most =. least =. (0{::Comparisons)kendall_tau 1{::Comparisons
    mostpair =. leastpair =. 0 1
    for_first. i.9 do.
        for_second. (first+1)+i.9-first+1 do.
            value =. (first{::Comparisons)kendall_tau second{::Comparisons
            if. (value frac_compare most)>0 do. most =. value
                mostpair =. first,second end.
            if. (value frac_compare least)<0 do. least =. value
                leastpair =. first,second end.
        end.
    end.
    lines =. <'most_similar | | tau |' format ((0{mostpair){ComparisonModels),((1{mostpair){ComparisonModels),<fraction_real_text most
    lines,<'least_similar | | tau |' format ((0{leastpair){ComparisonModels),((1{leastpair){ComparisonModels),<fraction_real_text least
)
join_parts =: 3 : 0
    lines =. 0$a:
    for_part. y do.
        if. #lines do. lines =. lines,<'' end.
        lines =. lines,>part
    end.
    lines
)
season_lines =: 3 : 0
    parts =. (<summary_lines ''),(<upset_lines ''),(<tiebreak_lines ''),(<leader_lines ''),(<streak_lines ''),(<crosstable_lines ''),(<trajectory_lines ''),(<correlation_lines 0),(<correlation_lines 1),<similarity_lines ''
    join_parts parts
)
longest_streak =: 4 : 0
    best =. 0 0 0
    length =. start =. 0
    for_index. i.#y do.
        row =. index{y
        if. -.(5{row)e.x do. length =. 0 continue. end.
        if. length=0 do. start =. index end.
        length =. length+1
        if. length>0{best do.
            first =. (<(0{start{y),0){Matches
            last =. (<(0{row),0){Matches
            best =. length,first,last
        end.
    end.
    best
)
record_text =: 3 : 0
    results =. 5{"1 y
    (number +/results=2),'-',(number +/results=1),'-',number +/results=0
)
opponent_average =: 4 : 0
    total =. 0 1
    for_item. x{::Appearances do. total =. total frac_add (1{item){y end.
    total frac_divide #x{::Appearances
)
compute_analysis =: 3 : 0
    build_appearances ''
    FinalTable =: standings Matches
    FinalFit =: fit_models Matches
    RoundTables =: 0$a:
    for_round. 1+i.FinalRound do. RoundTables =: RoundTables,<standings matches_before round+1 end.
    WinStreaks =: UnbeatenStreaks =: 0 3$0
    Sos =: Sos2 =: Rpi =: 0 2$0
    wp =. 9{::FinalFit
    for_team. i.TeamCount do.
        WinStreaks =: WinStreaks,2 longest_streak team{::Appearances
        UnbeatenStreaks =: UnbeatenStreaks,1 2 longest_streak team{::Appearances
        Sos =: Sos,team opponent_average wp
    end.
    for_team. i.TeamCount do. Sos2 =: Sos2,team opponent_average Sos end.
    Pythag =: Luck =: 0$0.0
    records =. 0{::FinalTable
    for_team. i.TeamCount do.
        total =. ((team{wp)frac_add 2 frac_times team{Sos)frac_add team{Sos2
        Rpi =: Rpi,total frac_divide 4
        row =. team{records
        probability =. 1%1+((5{row)%4{row)^Exponent
        Pythag =: Pythag,probability
        Luck =: Luck,(frac_real team{wp)-probability
    end.
    Comparisons =: <(-(4{::FinalTable)),.TeamCount$1
    Comparisons =: Comparisons,<2 comparison_real 0{::0{::FinalFit
    Comparisons =: Comparisons,<4 comparison_real 1{::FinalFit
    Comparisons =: Comparisons,<4 comparison_real 2{::FinalFit
    Comparisons =: Comparisons,<4 comparison_real 4{::FinalFit
    Comparisons =: Comparisons,<2 comparison_real 8{::FinalFit
    Comparisons =: Comparisons,(<wp),(<Rpi),<4 comparison_real Pythag
    ModelRanks =: 0$a:
    for_model. 1+i.6 do. ModelRanks =: ModelRanks,<competition_ranks model{::Comparisons end.
    i.0
)
validation_round =: 3 : 0
    training =. matches_before y
    fit =. fit_models training
    results =. 0$0.0
    for_match. training do. results =. results,(match_result match)%2 end.
    base =. mean results
    links =. 0 2$0.0
    for_model. i.4 do.
        features =. 0$0.0
        for_match. training do. features =. features,model feature (<fit),<match end.
        links =. links,features fit_link results
    end.
    found =. I.(0{"1 Matches)=y
    predictions =. 0$a:
    for_index. found do.
        match =. index{Matches
        home =. 1{match
        away =. 2{match
        probabilities =. 8$0.0
        probabilities =. base 0}probabilities
        ratings =. 0{::0{::fit
        probabilities =. (expected_score (home{ratings),(away{ratings),EloHome)1}probabilities
        locations =. 2 3 5 6
        for_model. i.4 do.
            'alpha beta' =. model{links
            probability =. sigma alpha+beta*model feature (<fit),<match
            probabilities =. probability (model{locations)}probabilities
        end.
        strengths =. 4{::fit
        theta =. 5{::fit
        homevalue =. theta*home{strengths
        probabilities =. (homevalue%homevalue+away{strengths)4}probabilities
        probabilities =. ((sequential_sum 1 2 3 4 5 6{probabilities)%6)7}probabilities
        losses =. briers =. 0$0.0
        correct =. 0$0
        result =. match_result match
        for_probability. probabilities do.
            losses =. losses,probability log_loss result
            briers =. briers,probability brier_score result
            correct =. correct,probability correctness result
        end.
        massey =. 2{::fit
        predicted =. ((home{massey)-away{massey)+3{::fit
        error =. ((3{match)-4{match)-predicted
        predictions =. predictions,<(<index),(<probabilities),(<losses),(<briers),(<correct),<error
    end.
    (<y),(<#training),(<fit),(<base),(<links),<predictions
)
compute_validation =: 3 : 0
    ValidationRounds =: Predictions =: 0$a:
    for_round. HoldoutRound+i.1+FinalRound-HoldoutRound do.
        validation =. validation_round round
        ValidationRounds =: ValidationRounds,<validation
        Predictions =: Predictions,5{::validation
    end.
    Losses =: Briers =: Skills =: 0$0.0
    Accuracies =: 0 2$0
    for_model. i.8 do.
        losses =. briers =. 0$0.0
        doubled =. 0
        for_prediction. Predictions do.
            prediction =. >prediction
            losses =. losses,model{2{::prediction
            briers =. briers,model{3{::prediction
            doubled =. doubled+model{4{::prediction
        end.
        Losses =: Losses,mean losses
        Briers =: Briers,mean briers
        Accuracies =: Accuracies,reduced_fraction doubled,2*#Predictions
    end.
    Skills =: 1-Briers%0{Briers
    LossRanking =: /:(4 decimal_value Losses),.i.8
    BrierRanking =: /:(4 decimal_value Briers),.i.8
    AccuracyRanking =: /:(-frac_real"1 Accuracies),.i.8
    i.0
)
simulate_projection =: 3 : 0
    currentmatches =. matches_before HoldoutRound
    CurrentTable =: standings currentmatches
    CurrentRatings =: 0{::(EloK,EloHome,EloInitial)run_elo currentmatches
    Remaining =: Matches#~(0{"1 Matches)>:HoldoutRound
    probabilities =. 0$0.0
    for_match. Remaining do. probabilities =. probabilities,expected_score ((1{match){CurrentRatings),((2{match){CurrentRatings),EloHome end.
    TotalPoints =: Titles =: Tops =: Bottoms =: TeamCount$0
    positions =. 4{::CurrentTable
    currentpoints =. 6{"1 0{::CurrentTable
    for_simulation. i.Simulations do.
        points =. currentpoints
        for_index. i.#Remaining do.
            SimState =: 2147483647|48271*SimState
            uniform =. SimState%2147483647
            match =. index{Remaining
            if. uniform<index{probabilities do. winner =. 1{match
            else. winner =. 2{match end.
            points =. (WinPoints+winner{points)winner}points
        end.
        order =. /:(-points),.positions
        for_place. i.TeamCount do.
            team =. place{order
            TotalPoints =: ((team{TotalPoints)+team{points)team}TotalPoints
            Titles =: ((team{Titles)+place=0)team}Titles
            Tops =: ((team{Tops)+(place+1)<:TopPositions)team}Tops
            Bottoms =: ((team{Bottoms)+(place+1)>:1+TeamCount-BottomPositions)team}Bottoms
        end.
    end.
    ProjectedOrder =: /:(-TotalPoints),.positions
    ProjectedRanks =: 1+/:ProjectedOrder
    ProjectionTau =: ((-ProjectedRanks),.TeamCount$1)kendall_tau (-(4{::FinalTable)),.TeamCount$1
    i.0
)
prediction_lines =: 3 : 0
    lines =. <'round,home,away,home_score,away_score,result,base,elo,colley,massey,bt,od,winpct,ensemble'
    for_prediction. Predictions do.
        'index probabilities losses briers correct error' =. >prediction
        match =. index{Matches
        'round home away first second' =. match
        result =. (match_result match){'ADH'
        fields =. (<round),(home{TeamIds),(away{TeamIds),(<first),(<second),<,result
        fields =. fields,fixed&.><"0 probabilities
        lines =. lines,<',' join fields
    end.
    lines
)
link_lines =: 3 : 0
    lines =. <'links'
    for_validation. ValidationRounds do.
        'round training fit base links predictions' =. >validation
        line =. 'round | train | base | bt_home |' format (<round),(<training),(<fixed base),<fixed 5{::fit
        for_model. i.4 do.
            'alpha beta' =. model{links
            line =. line,' ',(model{::LinkModels),' ',(fixed alpha),' ',fixed beta
        end.
        lines =. lines,<line
    end.
    lines
)
score_lines =: 3 : 0
    lines =. 'scores';'model log_loss brier skill accuracy'
    for_model. i.8 do.
        lines =. lines,<'| | | | |' format (model{PredictionModels),(<fixed model{Losses),(<fixed model{Briers),(<fixed model{Skills),<fraction_real_text model{Accuracies
    end.
    lines =. lines,<'ranking_log_loss ',' ' join LossRanking{PredictionModels
    lines =. lines,<'ranking_brier ',' ' join BrierRanking{PredictionModels
    lines,<'ranking_accuracy ',' ' join AccuracyRanking{PredictionModels
)
paired_lines =: 3 : 0
    reference =. {.LossRanking
    lines =. <'paired_log_loss reference ',reference{::PredictionModels
    for_model. i.8 do.
        if. model=reference do. continue. end.
        differences =. 0$0.0
        for_prediction. Predictions do.
            losses =. 2{::>prediction
            differences =. differences,(model{losses)-reference{losses
        end.
        average =. mean differences
        total =. 0.0
        for_difference. differences do. total =. total+(difference-average)*(difference-average) end.
        deviation =. %:total%(#differences)-1
        statistic =. average%(deviation%%:#differences)
        lines =. lines,<'| mean_diff | sd | t |' format (model{PredictionModels),(<fixed average),(<fixed deviation),<2 fixed statistic
    end.
    lines
)
margin_lines =: 3 : 0
    errors =. 0$0.0
    for_prediction. Predictions do. errors =. errors,5{::>prediction end.
    <'massey_margin mae | rmse | bias |' format (<fixed mean |errors),(<fixed %:mean *:errors),<fixed mean errors
)
round_loss_lines =: 3 : 0
    lines =. (<'round_log_loss'),<'round ',' ' join PredictionModels
    for_validation. ValidationRounds do.
        'round training fit base links predictions' =. >validation
        fields =. <round
        for_model. i.8 do.
            values =. 0$0.0
            for_prediction. predictions do. values =. values,model{2{::>prediction end.
            fields =. fields,<fixed mean values
        end.
        lines =. lines,<' ' join fields
    end.
    lines
)
calibration_lines =: 3 : 0
    lines =. <'calibration bins ',number BinCount
    for_model. i.8 do.
        for_bin. i.BinCount do.
            values =. 0$0.0
            doubled =. 0
            for_prediction. Predictions do.
                prediction =. >prediction
                probability =. model{1{::prediction
                selected =. (BinCount-1)<.<.BinCount*probability
                if. selected=bin do.
                    values =. values,probability
                    match =. (0{::prediction){Matches
                    doubled =. doubled+match_result match
                end.
            end.
            predicted =. observed =. '-'
            if. #values do. predicted =. fixed mean values
                observed =. fraction_text reduced_fraction doubled,2*#values end.
            lines =. lines,<'| bin | count | predicted | observed |' format (model{PredictionModels),(<bin+1),(<#values),(<predicted),<observed
        end.
    end.
    lines
)
grid_lines =: 3 : 0
    header =. <'k'
    for_home. GridHome do. header =. header,<'h',number home end.
    lines =. (<'elo_grid'),<' ' join header
    havebest =. 0
    bestk =. besthome =. bestloss =. 0
    for_coefficient. GridK do.
        row =. <coefficient
        for_home. GridHome do.
            run =. (coefficient,home,EloInitial)run_elo Matches
            expected =. 1{::run
            values =. 0$0.0
            for_index. I.(0{"1 Matches)>:HoldoutRound do.
                values =. values,(index{expected)log_loss match_result index{Matches
            end.
            loss =. mean values
            row =. row,<fixed loss
            if. (-.havebest)+.(4 decimal_value loss)<4 decimal_value bestloss do.
                havebest =. 1
                bestk =. coefficient
                besthome =. home
                bestloss =. loss
            end.
        end.
        lines =. lines,<' ' join row
    end.
    lines,<'best k | home | log_loss |' format (<bestk),(<besthome),<fixed bestloss
)
evaluation_lines =: 3 : 0
    range =. <'holdout rounds |-| matches |' format (<HoldoutRound),(<FinalRound),<#Predictions
    agreement =. <'projection simulations | kendall |' format (<Simulations),<fraction_real_text ProjectionTau
    parts =. (<range),(<link_lines ''),(<score_lines ''),(<paired_lines ''),(<margin_lines ''),(<round_loss_lines ''),(<calibration_lines ''),(<grid_lines ''),<agreement
    join_parts parts
)
projection_lines =: 3 : 0
    lines =. <'projected,team,points_now,position_now,remaining_opponent_elo,expected_points,title,top,bottom,final_points,final_position'
    currentrecords =. 0{::CurrentTable
    currentpositions =. 4{::CurrentTable
    finalrecords =. 0{::FinalTable
    finalpositions =. 4{::FinalTable
    for_team. ProjectedOrder do.
        opponents =. 0$0.0
        for_match. Remaining do.
            if. team=1{match do. opponents =. opponents,(2{match){CurrentRatings
            elseif. team=2{match do. opponents =. opponents,(1{match){CurrentRatings end.
        end.
        fields =. (<team{ProjectedRanks),(team{TeamIds),(<(<team,6){currentrecords),(<team{currentpositions),<2 fixed mean opponents
        fields =. fields,(<fixed_fraction (team{TotalPoints),Simulations),(<fixed_fraction (team{Titles),Simulations),(<fixed_fraction (team{Tops),Simulations),(<fixed_fraction (team{Bottoms),Simulations)
        fields =. fields,(<(<team,6){finalrecords),<team{finalpositions
        lines =. lines,<',' join fields
    end.
    lines
)
main =: 3 : 0
    read_season ''
    compute_analysis ''
    compute_validation ''
    simulate_projection ''
    1!:5 ::0: <'output'
    'standings.csv' write_lines standings_lines ''
    'ratings.csv' write_lines ratings_lines ''
    'history.csv' write_lines history_lines ''
    'season.txt' write_lines season_lines ''
    'predictions.csv' write_lines prediction_lines ''
    'evaluation.txt' write_lines evaluation_lines ''
    'projection.csv' write_lines projection_lines ''
    i.0
)
main ''
