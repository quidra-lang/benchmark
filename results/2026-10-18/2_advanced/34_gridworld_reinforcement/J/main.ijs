load 'environment.ijs'
load 'dynamic_programming.ijs'
load 'td_learning.ijs'
load 'monte_carlo.ijs'
load 'report.ijs'
Methods =: 'mc';'sarsa';'q_learning';'expected_sarsa';'dyna_q'
PolicyNames =: ('value_iteration';'policy_iteration'),Methods
EndingNames =: 'goal';'pit';'timeout';'loop';'limit'
agreement =: 4 : '+/x=y'
ending_counts =: 3 : '(+/0=y),(+/1=y),+/2=y'
read_settings =: 3 : 0
    rows =. 0$a:
    for_row. read_lines y do.
        rows =. rows,<num&> }.' 'split >row
    end.
    Gamma =: {.0{::rows
    StepReward =: {.1{::rows
    'SlipTotal FloorSlip IceSlip' =: 2{::rows
    Theta =: {.3{::rows
    GammaSweep =: 4{::rows
    SlipSweep =: (_1,2)$5{::rows
    Episodes =: {.6{::rows
    StepLimit =: {.7{::rows
    BlockSize =: {.8{::rows
    Alpha =: (_1,2)$9{::rows
    Epsilon =: (_1,2)$10{::rows
    PlanningSteps =: {.11{::rows
    Seed =: {.12{::rows
    Rollouts =: {.13{::rows
    RolloutSeed =: {.14{::rows
    0
)
schedule_value =: 4 : 0
    index =. {:I.(0{"1 x)<:y
    (<index,1){x
)
l_name =: 0&{::
l_q =: 1&{::
l_visits =: 2&{::
l_episodes =: 3&{::
l_last =: 4&{::
l_blocks =: 5&{::
l_policy =: 6&{::
l_state_visits =: 7&{::
learn_method =: 4 : 0
    name =. y
    values =. ((#States),4)$0x
    visits =. ((#States),4)$0
    dyna =. new_dyna_model #States
    averages =. new_mc_totals #States
    episodes =. 0 3$0x
    blocks =. 0 8$0x
    cells =. ,Start
    rng_seed Seed
    for_number. 1+i.Episodes do.
        alpha =. Alpha schedule_value number
        epsilon =. Epsilon schedule_value number
        state =. StartState
        cells =. ,Start
        history =. 0 3$0x
        episode_return =. 0
        steps =. 0
        ending =. 2
        action =. 0
        if. name-:'sarsa' do.
            action =. epsilon choose_action state{values
        end.
        while. steps<StepLimit do.
            if. -.name-:'sarsa' do.
                action =. epsilon choose_action state{values
            end.
            'cell reward' =. x environment_step state,action
            target =. cell{StateIndex
            coordinate =. <state,action
            visits =. (1+coordinate{visits)coordinate}visits
            episode_return =. episode_return+reward
            steps =. steps+1
            cells =. cells,cell
            if. name-:'mc' do.
                history =. history,state,action,reward
            else.
                future =. 0x
                next_action =. action
                if. target>:0 do.
                    if. name-:'sarsa' do.
                        next_action =. epsilon choose_action target{values
                        future =. (<target,next_action){values
                    elseif. name-:'expected_sarsa' do.
                        future =. epsilon next_expected target{values
                    else.
                        future =. next_maximum target{values
                    end.
                end.
                backup =. td_target reward,(target<0),future,Gamma
                values =. values td_update state,action,backup,alpha
                if. name-:'sarsa' do.
                    action =. next_action
                end.
                if. name-:'dyna_q' do.
                    dyna =. dyna record_model (>coordinate),reward,target
                    values =. dyna planning_updates (<values),(<Gamma),(<alpha),<PlanningSteps
                end.
            end.
            if. target<0 do.
                ending =. ending_code cell
                break.
            end.
            state =. target
        end.
        if. name-:'mc' do.
            'values averages' =. averages first_visit_update (<values),(<history),<Gamma
        end.
        episodes =. episodes,episode_return,steps,ending
        if. 0=BlockSize|number do.
            selected =. (number-BlockSize)+i.BlockSize
            recent =. selected{episodes
            agree =. OptimalPolicy agreement first_max"1 values
            error =. (+/|(>./"1 values)-OptimalValues)intdiv #States
            coverage =. +/0<+/"1 visits
            counts =. ending_counts 2{"1 recent
            blocks =. blocks,(+/0{"1 recent),(+/1{"1 recent),counts,agree,error,coverage
        end.
    end.
    policy =. first_max"1 values
    state_visits =. +/"1 visits
    (<name),(<values),(<visits),(<episodes),(<cells),(<blocks),(<policy),<state_visits
)
nominal_path =: 4 : 0
    'policy origin limit' =. y
    cells =. ,origin
    seen =. 1 origin}(#Kinds)$0
    ending =. 4
    while. (<:#cells)<limit do.
        state =. ({:cells){StateIndex
        target =. (<state,state{policy){e_moves x
        repeated =. target{seen
        cells =. cells,target
        seen =. 1 target}seen
        if. is_terminal target do.
            ending =. ending_code target
            break.
        elseif. repeated do.
            ending =. 3
            break.
        end.
    end.
    (<ending),<cells
)
distances =: 3 : 0
    result =. 0 Start}(#Kinds)$_1
    frontier =. ,Start
    level =. 0
    while. #frontier do.
        level =. level+1
        following =. i.0
        for_cell. frontier do.
            state =. cell{StateIndex
            for_action. i.4 do.
                for_transition. >(<state,action){e_transitions y do.
                    target =. {.transition
                    if. 0>target{result do.
                        result =. level target}result
                        if. -.is_terminal target do.
                            following =. following,target
                        end.
                    end.
                end.
            end.
        end.
        frontier =. following
    end.
    result
)
absorption =: 4 : 0
    goal =. (#States)$0x
    pit =. (#States)$0x
    expected =. (#States)$0x
    for_tick. i.StepLimit do.
        next_goal =. i.0
        next_pit =. i.0
        next_expected =. i.0
        for_state. i.#States do.
            g =. 0x
            p =. 0x
            e =. 0x
            for_transition. >(<state,state{y){e_transitions x do.
                'cell weight' =. transition
                target =. cell{StateIndex
                if. target>:0 do.
                    g =. g+weight*target{goal
                    p =. p+weight*target{pit
                    e =. e+weight*target{expected
                elseif. 'G'=cell{Kinds do.
                    g =. g+weight*100000000
                else.
                    p =. p+weight*100000000
                end.
            end.
            next_goal =. next_goal,g intdiv e_denominator x
            next_pit =. next_pit,p intdiv e_denominator x
            next_expected =. next_expected,100000000+e intdiv e_denominator x
        end.
        goal =. next_goal
        pit =. next_pit
        expected =. next_expected
    end.
    g =. StartState{goal
    p =. StartState{pit
    g,p,(100000000-(g+p)),StartState{expected
)
behaviour_value =: 4 : 0
    'policy epsilon' =. y
    values =. (#States)$0x
    sweeps =. 0
    delta =. Theta+1
    while. delta>Theta do.
        sweeps =. sweeps+1
        delta =. 0
        for_state. i.#States do.
            backups =. x action_values (<values),(<Gamma),<state
            weights =. epsilon+4*(1000-epsilon)*(i.4)=state{policy
            value =. (+/weights*backups)intdiv 4000
            delta =. delta>.|value-state{values
            values =. value state}values
        end.
    end.
    (StartState{values),sweeps
)
perform_rollouts =: 4 : 0
    rng_seed RolloutSeed
    records =. 0 4$0x
    terminal_counts =. (#Terminals)$0
    for_tick. i.Rollouts do.
        state =. StartState
        rewards =. i.0
        ending =. 2
        while. (#rewards)<StepLimit do.
            'cell reward' =. x environment_step state,state{y
            rewards =. rewards,reward
            state =. cell{StateIndex
            if. state<0 do.
                ending =. ending_code cell
                index =. cell{TerminalIndex
                terminal_counts =. (1+index{terminal_counts)index}terminal_counts
                break.
            end.
        end.
        records =. records,(+/rewards),(Gamma discounted_return rewards),(#rewards),ending
    end.
    (<records),<terminal_counts
)
p_values =: 0&{::
p_sweeps =: 1&{::
p_agree =: 2&{::
p_optimal =: 3&{::
p_gap =: 4&{::
p_gap_state =: 5&{::
p_changed =: 6&{::
p_improved_start =: 7&{::
p_improved_agree =: 8&{::
p_absorption =: 9&{::
p_rollouts =: 10&{::
evaluate_policy =: 4 : 0
    policy =. y
    'values sweeps' =. x evaluate_policy_value (<policy),(<(#States)$0x),(<Gamma),<Theta
    gaps =. OptimalValues-values
    gap_state =. first_max gaps
    optimal =. 0
    for_state. i.#States do.
        optimal =. optimal+(state{policy)e.state{::OptimalActions
    end.
    improved =. x greedy_policy (<values),<Gamma
    'second ignored' =. x evaluate_policy_value (<improved),(<(#States)$0x),(<Gamma),<Theta
    changed =. +/improved~:policy
    (<values),(<sweeps),(<policy agreement OptimalPolicy),(<optimal),(<gap_state{gaps),(<gap_state),(<changed),(<StartState{second),(<improved agreement OptimalPolicy),(<x absorption policy),<x perform_rollouts policy
)
sensitivity =: 4 : 0
    'values changes' =. x value_iteration y,Theta
    policy =. x greedy_policy (<values),<y
    'ending cells' =. x nominal_path (<policy),(<Start),<StepLimit
    'iterations ',(text #changes),' value_start ',(fixed StartState{values),' path ',(ending{::EndingNames),' steps ',(text <:#cells),' last ',(cell_text {:cells),' differences ',text +/policy~:OptimalPolicy
)
run =: 3 : 0
    read_world 'input/world.txt'
    read_settings 'input/params.txt'
    world_model =. new_environment StepReward,SlipTotal,FloorSlip,IceSlip
    n =. #States
    'optimal_values changes' =. world_model value_iteration Gamma,Theta
    OptimalValues =: optimal_values
    optimal_q =. (n,4)$0x
    optimal_actions =. 0$a:
    for_state. i.n do.
        row =. world_model action_values (<optimal_values),(<Gamma),<state
        optimal_q =. row state}optimal_q
        optimal_actions =. optimal_actions,<I.row=>./row
    end.
    OptimalActions =: optimal_actions
    OptimalPolicy =: first_max"1 optimal_q
    'in_place_values in_place_sweeps' =. world_model in_place_iteration Gamma,Theta
    'pi_policy pi_values pi_rounds' =. world_model policy_iteration Gamma,Theta
    learners =. 0$a:
    policies =. (<OptimalPolicy),<pi_policy
    for_method. Methods do.
        learner =. world_model learn_method >method
        learners =. learners,<learner
        policies =. policies,<l_policy learner
    end.
    evaluations =. 0$a:
    for_policy. policies do.
        evaluations =. evaluations,<world_model evaluate_policy >policy
    end.
    distance =. distances world_model
    reachable =. +/0<:States{distance
    world_lines =. ,<'world rows ',(text Rows),' cols ',(text Cols),' states ',(text n),' walls ',(text +/'#'=Kinds),' floor ',(text +/Kinds e.'.S'),' ice ',(text +/'~'=Kinds),' goals ',(text +/'G'=Kinds),' pits ',text +/'P'=Kinds
    world_lines =. world_lines,<'start ',(cell_text Start),' reachable ',text reachable
    for_index. i.#Terminals do.
        cell =. index{Terminals
        steps =. '-'
        if. (cell{distance)>:0 do.
            steps =. text cell{distance
        end.
        world_lines =. world_lines,<'terminal ',(cell_text cell),' ',((ending_code cell){::EndingNames),' reward ',(text index{Rewards),' distance ',steps
    end.
    iteration_lines =. ,<'value_iteration gamma ',(text Gamma),' theta ',(fixed Theta),' iterations ',text #changes
    for_index. i.#changes do.
        iteration_lines =. iteration_lines,<'iteration ',(text index+1),' max_change ',fixed index{changes
    end.
    tie_lines =. 0$a:
    for_state. i.n do.
        actions =. state{::optimal_actions
        if. 1<#actions do.
            tie_lines =. tie_lines,<'tie ',(state_text state),' ',actions{'NESW'
        end.
    end.
    symmetry =. 0 0 0
    mirror =. 0 3 2 1
    for_state. i.n do.
        cell =. state{States
        column =. Cols|cell
        other_column =. (Cols-1)-column
        other =. (((cell intdiv Cols)*Cols)+other_column){StateIndex
        if. (column<other_column)*.other>:0 do.
            symmetry =. symmetry+1,((state{optimal_values)=other{optimal_values),((other{OptimalPolicy)=(state{OptimalPolicy){mirror)
        end.
    end.
    ties_lines =. (<'ties ',text #tie_lines),tie_lines,<'symmetry pairs ',(text 0{symmetry),' equal_values ',(text 1{symmetry),' mirrored_actions ',text 2{symmetry
    round_lines =. ,<'policy_iteration rounds ',text #pi_rounds
    for_index. i.#pi_rounds do.
        'sweeps changed value' =. index{pi_rounds
        round_lines =. round_lines,<'round ',(text index+1),' sweeps ',(text sweeps),' changed ',(text changed),' value_start ',fixed value
    end.
    differences =. |pi_values-optimal_values
    worst =. first_max differences
    comparison_lines =. ,<'comparison policy_differences ',(text +/pi_policy~:OptimalPolicy),' max_value_difference ',(fixed worst{differences),' at ',state_text worst
    backups =. ((+/0{"1 pi_rounds)*n)+4*n*#pi_rounds
    comparison_lines =. comparison_lines,<'backups value_iteration ',(text 4*n*#changes),' in_place_iterations ',(text in_place_sweeps),' in_place ',(text 4*n*in_place_sweeps),' policy_iteration ',text backups
    gamma_lines =. ,<'gamma_sweep'
    for_gamma. GammaSweep do.
        gamma_lines =. gamma_lines,<'gamma ',(text gamma),' ',world_model sensitivity gamma
    end.
    slip_lines =. ,<'slip_sweep'
    for_slip. SlipSweep do.
        varied =. new_environment StepReward,SlipTotal,slip
        slip_lines =. slip_lines,<'slip ',(text 0{slip),' ',(text 1{slip),' ',varied sensitivity Gamma
    end.
    value_parts =. (<world_lines),(<iteration_lines),(<(<'optimal_values'),value_grid optimal_values),(<(<'optimal_action_counts'),''world_grid text&.>#&>optimal_actions),(<ties_lines),(<round_lines),(<(<'policy_iteration_values'),value_grid pi_values),(<comparison_lines),(<gamma_lines),<slip_lines
    policy_parts =. 0$a:
    for_index. i.#policies do.
        policy =. index{::policies
        'ending cells' =. world_model nominal_path (<policy),(<Start),<StepLimit
        lines =. (<index{::PolicyNames),policy_grid policy
        lines =. lines,<'path ',(ending{::EndingNames),' steps ',(text <:#cells),' ',cells_text cells
        action_counts =. +/"1 (i.4)=/policy
        risk =. 0
        symbols =. 0$a:
        for_state. i.n do.
            transitions =. >(<state,state{policy){e_transitions world_model
            risk =. risk+(+./'P'=(0{"1 transitions){Kinds)
            'basin_ending basin_cells' =. world_model nominal_path (<policy),(<state{States),<StepLimit
            symbol =. '*'
            if. basin_ending<2 do.
                symbol =. ,(({:basin_cells){TerminalIndex){'abcdefghijklmnopqrstuvwxyz'
            end.
            symbols =. symbols,<symbol
        end.
        lines =. lines,<'actions N ',(text 0{action_counts),' E ',(text 1{action_counts),' S ',(text 2{action_counts),' W ',(text 3{action_counts),' risk ',text risk
        lines =. lines,(<'basins'),''world_grid symbols
        if. index>:2 do.
            state_visits =. l_state_visits (index-2){::learners
            digits =. 0$a:
            for_visits. state_visits do.
                digit =. '0'
                if. visits>0 do.
                    digit =. text #text visits
                end.
                digits =. digits,<digit
            end.
            lines =. lines,(<'visits'),''world_grid digits
        end.
        policy_parts =. policy_parts,<lines
    end.
    q_output =. (<'method,row,col,action,value,visits'),q_rows (<'value_iteration'),(<optimal_q),(<0 0$0),<1
    curve_output =. ,<'method,block,mean_return,mean_steps,goals,pits,timeouts,agree,value_error,coverage'
    for_box. learners do.
        learner =. >box
        q_output =. q_output,q_rows (<l_name learner),(<l_q learner),(<l_visits learner),<0
        blocks =. l_blocks learner
        for_index. i.#blocks do.
            'sum steps goals pits timeouts agree error coverage' =. index{blocks
            fields =. (<l_name learner),(<index+1),(<sum average BlockSize),(<steps average BlockSize),(<goals),(<pits),(<timeouts),(<agree),(<fixed error),<coverage
            curve_output =. curve_output,<','join text&.>fields
        end.
    end.
    evaluation_parts =. ,<,<'summary states ',(text n),' start ',(cell_text Start),' rollouts ',(text Rollouts),' step_limit ',text StepLimit
    policy_value_lines =. 'policies';'policy agree optimal_actions value_start sweeps max_gap at'
    improvement_lines =. 'improvement';'policy changed value_start agree'
    absorption_lines =. 'absorption';'policy p_goal p_pit p_timeout expected_steps'
    rollout_lines =. 'rollouts';'policy mean_return mean_discounted mean_steps goals pits timeouts min median max'
    terminal_lines =. (<'terminals'),<'policy ',cells_text Terminals
    agreement_lines =. (<'agreement'),<'policy ',' 'join PolicyNames
    for_index. i.#evaluations do.
        evaluation =. index{::evaluations
        name =. index{::PolicyNames
        fields =. (<name),(<p_agree evaluation),(<p_optimal evaluation),(<fixed StartState{p_values evaluation),(<p_sweeps evaluation),(<fixed p_gap evaluation),<state_text p_gap_state evaluation
        policy_value_lines =. policy_value_lines,<line fields
        fields =. (<name),(<p_changed evaluation),(<fixed p_improved_start evaluation),<p_improved_agree evaluation
        improvement_lines =. improvement_lines,<line fields
        absorption_lines =. absorption_lines,<name,' ',' 'join fixed&.>(p_absorption evaluation)intdiv 10000
        'draws terminal_counts' =. p_rollouts evaluation
        returns =. /:~0{"1 draws
        counts =. ending_counts 3{"1 draws
        fields =. (<name),(<(+/0{"1 draws)average Rollouts),(<fixed (+/1{"1 draws)intdiv Rollouts),(<(+/2{"1 draws)average Rollouts),(<0{counts),(<1{counts),(<2{counts),(<{.returns),(<((((Rollouts+1)intdiv 2)-1){returns)),<{:returns
        rollout_lines =. rollout_lines,<line fields
        terminal_lines =. terminal_lines,<name,' ',' 'join text&.>terminal_counts
        counts =. i.0
        for_other. policies do.
            counts =. counts,(index{::policies)agreement >other
        end.
        agreement_lines =. agreement_lines,<name,' ',' 'join text&.>counts
    end.
    evaluation_parts =. evaluation_parts,(<policy_value_lines),(<improvement_lines),<absorption_lines
    behaviour_lines =. 'behaviour';'method epsilon value_start sweeps'
    error_lines =. 'q_errors';'method mean_abs max_abs at unvisited tied'
    action_error_lines =. 'q_action_errors';'method N E S W'
    final_epsilon =. Epsilon schedule_value Episodes
    for_box. learners do.
        learner =. >box
        name =. l_name learner
        'value sweeps' =. world_model behaviour_value (<l_policy learner),<final_epsilon
        behaviour_lines =. behaviour_lines,<line (<name),(<final_epsilon),(<fixed value),<sweeps
        values =. l_q learner
        visits =. l_visits learner
        best =. >./"1 values
        errors =. |best-optimal_values
        worst =. first_max errors
        unvisited =. +/0=l_state_visits learner
        ties =. +/1<+/"1 values=best
        fields =. (<name),(<fixed (+/errors)intdiv n),(<fixed worst{errors),(<state_text worst),(<unvisited),<ties
        error_lines =. error_lines,<line fields
        fields =. ,<name
        for_action. i.4 do.
            selected =. I.0<action{"1 visits
            field =. '-'
            if. #selected do.
                differences =. |(<selected;action){values-optimal_q
                field =. fixed (+/,differences)intdiv #selected
            end.
            fields =. fields,<field
        end.
        action_error_lines =. action_error_lines,<line fields
    end.
    evaluation_parts =. evaluation_parts,(<behaviour_lines),(<error_lines),(<action_error_lines),(<rollout_lines),(<terminal_lines),<agreement_lines
    training_lines =. 'training';'method steps goals pits timeouts best_block best_mean last_mean reach'
    visited_lines =. ,<'visited'
    last_lines =. ,<'last_episodes'
    phase_lines =. ,<'phases'
    optimal_draws =. 0{::p_rollouts 0{::evaluations
    optimal_total =. +/0{"1 optimal_draws
    phase_starts =. /:~ ~.(0{"1 Alpha),0{"1 Epsilon
    for_box. learners do.
        learner =. >box
        name =. l_name learner
        episodes =. l_episodes learner
        counts =. ending_counts 2{"1 episodes
        block_totals =. 0{"1 l_blocks learner
        best =. first_max block_totals
        reached =. I.(10*Rollouts*block_totals)>:9*BlockSize*optimal_total
        reach =. '-'
        if. #reached do.
            reach =. text 1+{.reached
        end.
        fields =. (<name),(<+/1{"1 episodes),(<0{counts),(<1{counts),(<2{counts),(<best+1),(<(best{block_totals)average BlockSize),(<({:block_totals)average BlockSize),<reach
        training_lines =. training_lines,<line fields
        state_visits =. l_state_visits learner
        order =. /:-state_visits
        fields =. ,<name
        for_state. 3{.order do.
            fields =. fields,<(state_text state),':',text state{state_visits
        end.
        visited_lines =. visited_lines,<line fields
        'sum steps ending' =. {:episodes
        last_lines =. last_lines,<name,' return ',(text sum),' steps ',(text steps),' end ',(ending{::EndingNames),' ',cells_text l_last learner
        for_index. i.#phase_starts do.
            first =. index{phase_starts
            last =. Episodes
            if. (index+1)<#phase_starts do.
                last =. ((index+1){phase_starts)-1
            end.
            count =. 1+last-first
            recent =. ((first-1)+i.count){episodes
            phase_lines =. phase_lines,<name,' ',(text first),'-',(text last),' alpha ',(text Alpha schedule_value first),' epsilon ',(text Epsilon schedule_value first),' mean_return ',((+/0{"1 recent)average count),' mean_steps ',((+/1{"1 recent)average count),' goals ',text +/0=2{"1 recent
        end.
    end.
    evaluation_parts =. evaluation_parts,(<training_lines),(<visited_lines),(<last_lines),<phase_lines
    try.
        1!:5 <'output'
    catch.
    end.
    'values.txt'write_lines join_parts value_parts
    'policies.txt'write_lines join_parts policy_parts
    'q_tables.csv'write_lines q_output
    'learning_curves.csv'write_lines curve_output
    'evaluation.txt'write_lines join_parts evaluation_parts
    i.0 0
)
run 0
