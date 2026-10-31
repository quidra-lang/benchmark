load 'mesh.ijs'
load 'materials.ijs'
load 'transient.ijs'
load 'steady.ijs'
load 'report.ijs'
verdict =: 3 : 'y{::;:''failed ok'''
yes =: 3 : 'y{::;:''no yes'''
cell_text =: 3 : 'words coordinates y'
read_boundary =: 3 : 0
    Segments =: Sources =: 0$a:
    for_row. read_lines 'boundary.txt' do.
        fields =. split_words >row
        if. 'segment'-:0{::fields do.
            kind =. 5{::fields
            h =. theta =. 0.0
            if. 'fixed'-:kind do. theta =. 0.0+".6{::fields
            elseif. 'convective'-:kind do.
                h =. 0.0+".6{::fields
                theta =. 0.0+".7{::fields
            end.
            faces =. (2{::fields)segment_faces ".&>3 4{fields
            segment =. (1{fields),(2{fields),(5{fields),(<faces),(<h),<theta
            Segments =: Segments,<segment
        else.
            cells =. source_cells ".&>2 3 4 5{fields
            power =. 0.0+".6{::fields
            times =. ".&>7}.fields
            intervals =. (_2[\times)
            source =. (1{fields),(<cells),(<power),(<intervals),<power%#cells
            Sources =: Sources,<source
        end.
    end.
    0
)
read_parameters =: 3 : 0
    Probes =: Runs =: 0$a:
    for_row. read_lines 'params.txt' do.
        fields =. split_words >row
        select. 0{::fields
        case. 'initial' do. Initial =: 0.0+".1{::fields
        case. 'end_time' do. EndTime =: ".1{::fields
        case. 'snapshots' do. SnapshotTimes =: ".&>}.fields
        case. 'probe_every' do. ProbeEvery =: ".1{::fields
        case. 'probe' do.
            probe =. (1{fields),<cell_number ".&>2 3{fields
            Probes =: Probes,<probe
        case. 'run' do.
            step =. ".3{::fields
            definition =. (1{fields),(2{fields),(<step),<step%1000.0
            Runs =: Runs,<definition
        case. 'reference' do. ReferenceName =: 1{::fields
        case. 'tolerance' do. Tolerance =: 0.0+".1{::fields
        case. 'max_iterations' do. MaxIterations =: ".1{::fields
        case. 'omega' do. Omega =: 0.0+".1{::fields
        case. 'bands' do. Bands =: 0.0+".&>}.fields
        case. 'alarm' do. Alarm =: 0.0+".1{::fields
        case. 'limit' do. Limit =: 0.0+".1{::fields
        end.
    end.
    0
)
source_operating =: 4 : 0
    for_interval. 3{::x do.
        if. ((0{interval)<:y)*.y<1{interval do. 1 return. end.
    end.
    0
)
source_terms =: 3 : 0
    field =. CellCount$0.0
    powers =. i.0
    for_source. Sources do.
        source =. >source
        if. (y<0)+.source source_operating y do.
            powers =. powers,2{::source
            for_p. 1{::source do. field =. ((p{field)+4{::source)p}field end.
        end.
    end.
    (<field),<ordered_sum powers
)
build_system =: 3 : 0
    CellMaterial =: MaterialCodes i.Codes
    MaterialCells =: 0$a:
    for_i. i.#MaterialCodes do. MaterialCells =: MaterialCells,<I.i=CellMaterial end.
    Capacity =: i.0
    for_p. i.CellCount do.
        Capacity =: Capacity,((p{CellMaterial){MaterialValues)heat_capacity Dx,Thickness
    end.
    FaceG =: Theta =: (CellCount,4)$0.0
    BoundaryFaces =: (CellCount,4)$0
    for_p. i.CellCount do.
        first =. 0{(p{CellMaterial){MaterialValues
        for_direction. i.4 do.
            neighbor =. (<p,direction){Neighbors
            if. neighbor>:0 do.
                second =. 0{(neighbor{CellMaterial){MaterialValues
                FaceG =: ((first,second)interior_conductance Thickness)(<p,direction)}FaceG
            end.
        end.
    end.
    for_segment. Segments do.
        'name edge kind faces h theta' =. >segment
        for_face. faces do.
            'p direction' =. face
            k =. 0{(p{CellMaterial){MaterialValues
            if. 'fixed'-:kind do.
                FaceG =: (k fixed_conductance Thickness)(<p,direction)}FaceG
            elseif. 'convective'-:kind do.
                FaceG =: (k convective_conductance h,Dx,Thickness)(<p,direction)}FaceG
            end.
            BoundaryFaces =: (-.'insulated'-:kind)(<p,direction)}BoundaryFaces
            Theta =: theta (<p,direction)}Theta
        end.
    end.
    Diagonal =: ordered_sum"1 FaceG
    Beta =: i.0
    for_p. i.CellCount do.
        terms =. i.0
        for_direction. i.4 do.
            if. (<p,direction){BoundaryFaces do. terms =. terms,((<p,direction){FaceG)*(<p,direction){Theta end.
        end.
        Beta =: Beta,ordered_sum terms
    end.
    DtMax =: <./Capacity%Diagonal
    'SourceAll TotalPower' =: source_terms _1
    0
)
hottest =: 3 : '{.I.y=>./y'
field_summary =: 4 : 0
    p =. hottest y
    x,' max ',(2 real_text p{y),' at ',(cell_text p),' min ',(2 real_text <./y),' mean ',2 real_text (ordered_sum y)%CellCount
)
stored_heat =: 4 : 'ordered_sum (x{Capacity)*((x{y)-Initial)'
segment_flow =: 4 : 0
    if. 'insulated'-:2{::x do. 0.0 return. end.
    terms =. i.0
    for_face. 3{::x do.
        'p direction' =. face
        terms =. terms,((<p,direction){FaceG)*((5{::x)-p{y)
    end.
    ordered_sum terms
)
run_status =: 3 : 0
    'name method step dt' =. y
    times =. EndTime,ProbeEvery,SnapshotTimes
    for_source. Sources do. times =. times,,3{::>source end.
    if. +./0~:step|times do. 'step' return. end.
    if. ('ftcs'-:method)*.dt>DtMax do. 'unstable' else. 'accepted' end.
)
step_energy =: 4 : 0
    'segment definition' =. x
    'previous updated intermediate' =. y
    'name edge kind faces h theta' =. segment
    'run_name method step dt' =. definition
    if. 'insulated'-:kind do. 0.0 return. end.
    terms =. i.0
    for_face. faces do.
        'p direction' =. face
        temperature =. p{previous
        if. -.'ftcs'-:method do.
            if. (<edge)e.;:'left right' do. temperature =. p{intermediate
            elseif. 'backward_euler'-:method do. temperature =. p{updated
            else. temperature =. ((p{previous)+p{updated)%2.0
            end.
        end.
        terms =. terms,((<p,direction){FaceG)*(theta-temperature)
    end.
    dt*ordered_sum terms
)
observe =: 4 : 0
    result =. x
    'now field' =. y
    point =. hottest field
    temperature =. point{field
    peak =. 8{::result
    if. 0=#peak do. peak =. (<temperature),(<now),<point
    elseif. temperature>0{::peak do. peak =. (<temperature),(<now),<point
    end.
    result =. (<peak)8}result
    if. temperature>:Alarm do.
        if. 0=#9{::result do. result =. (<now,point)9}result end.
        if. now>0 do. result =. (<(10{::result)+2{::0{::result)10}result end.
    end.
    if. 0=ProbeEvery|now do.
        readings =. i.0
        for_probe. Probes do. readings =. readings,(1{::>probe){field end.
        sample =. (<now),<readings
        result =. (<(7{::result),<sample)7}result
    end.
    if. now e.SnapshotTimes do.
        snapshot =. (<now),(<field),(<(i.CellCount)stored_heat field),(<ordered_sum 4{::result),<5{::result
        result =. (<(6{::result),<snapshot)6}result
    end.
    result
)
simulate_run =: 3 : 0
    definition =. y
    'name method step dt' =. definition
    state =. run_status definition
    result =. (<definition),(<state),(<0),(<i.0),(<i.0),(<0.0),(<0$a:),(<0$a:),(<0$a:),(<i.0),(<0),(<0.0),(<0.0),<0
    if. -.'accepted'-:state do. result return. end.
    steps =. EndTime floor_div step
    result =. (<steps)2}result
    result =. (<(#Segments)$0.0)4}result
    field =. CellCount#Initial
    result =. result observe (<0),<field
    for_iteration. i.steps do.
        'source power' =. source_terms iteration*step
        'updated intermediate' =. ((<method),<dt)advance (<field),<source
        energy =. 4{::result
        for_i. i.#Segments do.
            addition =. ((<i{::Segments),<definition)step_energy (<field),(<updated),<intermediate
            energy =. ((i{energy)+addition)i}energy
        end.
        result =. (<energy)4}result
        result =. (<(5{::result)+dt*power)5}result
        field =. updated
        result =. result observe (<(iteration+1)*step),<field
    end.
    stored =. (i.CellCount)stored_heat field
    boundary =. ordered_sum 4{::result
    generated =. 5{::result
    balanced =. (|(stored-boundary)-generated)<:0.000001*((|stored)+(|boundary)+|generated)
    result =. (<field)3}result
    result =. (<stored)11}result
    result =. (<boundary)12}result
    (<balanced)13}result
)
solve_steady =: 3 : 0
    RHS =: Beta+SourceAll
    vectors =. RHS,:Beta
    for_source. Sources do.
        cells =. 1{::>source
        vector =. CellCount$0.0
        vector =. (1.0%#cells)cells}vector
        vectors =. vectors,vector
    end.
    fields =. band_solve vectors
    Solution =: 0{fields
    Base =: 1{fields
    Responses =: 2}.fields
    jacobi =. iterate (<Initial),(<Tolerance),(<MaxIterations),(<'jacobi'),<1.0
    changes =. 2{::jacobi
    Rho =: %:({:changes)%_3{changes
    OmegaOpt =: 2.0%(1.0+%:1.0-Rho*Rho)
    iterations =. <jacobi
    for_method. ;:'gauss_seidel sor sor_estimated' do.
        method =. >method
        omega =. Omega
        if. 'sor_estimated'-:method do. omega =. OmegaOpt end.
        iterations =. iterations,<iterate (<Initial),(<Tolerance),(<MaxIterations),(<method),<omega
    end.
    IterativeResults =: 0$a:
    for_iteration. iterations do.
        iteration =. >iteration
        changes =. 2{::iteration
        rate =. %:({:changes)%_3{changes
        milestones =. 0$a:
        for_factor. 1000 100 10 1 do.
            found =. I.changes<Tolerance*factor
            milestone =. 'never'
            if. #found do. milestone =. integer 1+{.found end.
            milestones =. milestones,<milestone
        end.
        field =. 1{::iteration
        error =. >./|field-Solution
        residual =. RHS maximum_residual field
        IterativeResults =: IterativeResults,<iteration,(<rate),(<milestones),(<error),<residual
    end.
    0
)
duty_ratio =: 3 : 0
    duration =. 0
    for_interval. 3{::y do.
        duration =. duration+((1{interval)<.EndTime)-((0{interval)<.EndTime)
    end.
    duration%EndTime
)
steady_state_lines =: 3 : 0
    lines =. (<'steady'field_summary Solution),temperature_lines Solution
    for_i. i.#MaterialCodes do.
        cells =. i{::MaterialCells
        values =. cells{Solution
        lines =. lines,<'material ',(i{MaterialCodes),' ',(i{::MaterialNames),' cells ',(integer #cells),' min ',(2 real_text <./values),' max ',(2 real_text >./values),' mean ',2 real_text (ordered_sum values)%#values
    end.
    duties =. duty_ratio&>Sources
    for_i. i.#Sources do.
        'name cells power intervals weight' =. i{::Sources
        values =. cells{Solution
        lines =. lines,<'source ',name,' power ',(4 real_text power),' duty ',(4 real_text i{duties),' mean ',(2 real_text (ordered_sum values)%#cells),' max ',2 real_text >./values
    end.
    for_source. Sources do.
        'name cells power intervals weight' =. >source
        for_i. i.#Sources do.
            coefficient =. (ordered_sum cells{i{Responses)%#cells
            lines =. lines,<'influence ',name,' ',(0{::i{::Sources),' ',4 real_text coefficient
        end.
    end.
    superposed =. duty_field =. Base
    for_p. i.CellCount do.
        value =. average =. p{Base
        for_i. i.#Sources do.
            power =. 2{::i{::Sources
            response =. (<i,p){Responses
            value =. value+power*response
            average =. average+((i{duties)*power)*response
        end.
        superposed =. value p}superposed
        duty_field =. average p}duty_field
    end.
    lines =. lines,<'superposition ',verdict 0.000001>:>./|superposed-Solution
    for_i. i.#Sources do.
        name =. 0{::i{::Sources
        for_segment. Segments do.
            segment =. >segment
            terms =. i.0
            if. -.'insulated'-:2{::segment do.
                for_face. 3{::segment do.
                    'p direction' =. face
                    terms =. terms,((<p,direction){FaceG)*(<i,p){Responses
                end.
            end.
            lines =. lines,<'path ',name,' ',(0{::segment),' ',4 real_text ordered_sum terms
        end.
    end.
    lines =. lines,<'duty_steady'field_summary duty_field
    for_i. i.#Sources do.
        name =. 0{::i{::Sources
        power =. 2{::i{::Sources
        response =. i{Responses
        values =. (Limit-(Solution-power*response))%response
        point =. {.I.values=<./values
        lines =. lines,<'headroom ',name,' max_power ',(4 real_text point{values),' at ',cell_text point
    end.
    material_count =. #MaterialCodes
    faces_count =. (material_count,material_count)$0
    forward =. backward =. (material_count,material_count)$0.0
    gradient =. _1.0
    gradient_cells =. 0 0
    for_p. i.CellCount do.
        for_direction. 1 3 do.
            q =. (<p,direction){Neighbors
            if. q>:0 do.
                current_gradient =. (|(p{Solution)-q{Solution)%Dx
                if. current_gradient>gradient do. gradient =. current_gradient
                    gradient_cells =. p,q
                end.
                a =. p{CellMaterial
                b =. q{CellMaterial
                if. a~:b do.
                    flow =. ((<p,direction){FaceG)*((p{Solution)-q{Solution)
                    if. a>b do. temporary =. a
                        a =. b
                        b =. temporary
                        flow =. -flow
                    end.
                    faces_count =. (1+(<a,b){faces_count)(<a,b)}faces_count
                    if. flow>0.0 do. forward =. (flow+(<a,b){forward)(<a,b)}forward
                    elseif. flow<0.0 do. backward =. ((|flow)+(<a,b){backward)(<a,b)}backward
                    end.
                end.
            end.
        end.
    end.
    for_a. i.material_count do.
        for_b. (a+1)+i.material_count-(a+1) do.
            count =. (<a,b){faces_count
            if. count do.
                lines =. lines,<'interface ',(a{MaterialCodes),' ',(b{MaterialCodes),' faces ',(integer count),' forward ',(4 real_text (<a,b){forward),' backward ',4 real_text (<a,b){backward
            end.
        end.
    end.
    flows =. i.0
    for_segment. Segments do.
        segment =. >segment
        flow =. segment segment_flow Solution
        flows =. flows,flow
        lines =. lines,<'segment ',(0{::segment),' ',(1{::segment),' ',(2{::segment),' flow ',4 real_text flow
    end.
    balanced =. (|(ordered_sum flows)+TotalPower)<:0.000001*((ordered_sum |flows)+TotalPower)
    lines =. lines,(<'sources ',4 real_text TotalPower),(<'balance ',verdict balanced),<'max_gradient ',(2 real_text gradient),' between ',(cell_text 0{gradient_cells),' and ',cell_text 1{gradient_cells
    for_iteration. IterativeResults do.
        'method field changes converged omega rate milestones error residual' =. >iteration
        prefix =. 'solver ',method
        if. (<method)e.;:'sor sor_estimated' do. prefix =. prefix,' omega ',4 real_text omega end.
        lines =. lines,<prefix,' iterations ',(integer #changes),' converged ',(yes converged),' rate ',(6 real_text rate),' milestones ',' 'join milestones
    end.
    lines
)
rejected_line =: 4 : 0
    result =. y
    'name method step dt' =. 0{::result
    state =. 1{::result
    line =. 'run ',name,' ',method,' dt ',(time_text step),' rejected ',state
    if. x*.'unstable'-:state do. line =. line,' max_dt ',4 real_text DtMax end.
    line
)
snapshot_lines =: 3 : 0
    lines =. 0$a:
    for_result. Results do.
        result =. >result
        'name method step dt' =. 0{::result
        if. -.'accepted'-:1{::result do. lines =. lines,<1 rejected_line result
        else.
            for_snapshot. 6{::result do.
                'now field stored boundary generated' =. >snapshot
                prefix =. 'run ',name,' ',method,' dt ',(time_text step),' time ',time_text now
                lines =. lines,(<prefix field_summary field),temperature_lines field
            end.
        end.
    end.
    lines
)
probe_lines =: 3 : 0
    lines =. <'run,time,probe,temperature'
    for_result. Results do.
        result =. >result
        if. 'accepted'-:1{::result do.
            name =. 0{::0{::result
            for_sample. 7{::result do.
                'now values' =. >sample
                for_i. i.#Probes do.
                    lines =. lines,<name,',',(time_text now),',',(0{::i{::Probes),',',3 real_text i{values
                end.
            end.
        end.
    end.
    lines
)
comparison_lines =: 3 : 0
    lines =. <'ftcs_max_dt ',4 real_text DtMax
    reference =. ReferenceIndex{::Results
    for_index. i.#Results do.
        result =. index{::Results
        'name method step dt' =. 0{::result
        if. -.'accepted'-:1{::result do. lines =. lines,<0 rejected_line result
        else.
            'temperature peak_time peak_cell' =. 8{::result
            alarm =. 'never'
            if. #9{::result do.
                'alarm_time alarm_cell' =. 9{::result
                alarm =. (time_text alarm_time),' at ',cell_text alarm_cell
            end.
            lines =. lines,<'run ',name,' ',method,' dt ',(time_text step),' steps ',(integer 2{::result),' peak ',(2 real_text temperature),' time ',(time_text peak_time),' at ',(cell_text peak_cell),' alarm ',alarm,' above ',time_text 10{::result
            lines =. lines,<'energy ',name,' stored ',(2 real_text 11{::result),' boundary ',(2 real_text 12{::result),' source ',(2 real_text 5{::result),' balance ',verdict 13{::result
            for_snapshot. 6{::result do.
                'now field stored boundary generated' =. >snapshot
                lines =. lines,<'energy_at ',name,' time ',(time_text now),' stored ',(2 real_text stored),' boundary ',(2 real_text boundary),' source ',2 real_text generated
            end.
            for_i. i.#MaterialCodes do.
                value =. (i{::MaterialCells)stored_heat 3{::result
                lines =. lines,<'energy_material ',name,' ',(i{MaterialCodes),' ',2 real_text value
            end.
            for_i. i.#Segments do.
                lines =. lines,<'energy_segment ',name,' ',(0{::i{::Segments),' ',2 real_text i{4{::result
            end.
            samples =. 7{::result
            for_i. i.#Probes do.
                first_sample =. 0{::samples
                low =. high =. i{1{::first_sample
                low_time =. high_time =. 0{::first_sample
                for_sample. }.samples do.
                    'now values' =. >sample
                    if. (i{values)>high do. high =. i{values
                        high_time =. now
                    end.
                    if. (i{values)<low do. low =. i{values
                        low_time =. now
                    end.
                end.
                lines =. lines,<'probe_summary ',name,' ',(0{::i{::Probes),' max ',(3 real_text high),' time ',(time_text high_time),' min ',(3 real_text low),' time ',time_text low_time
            end.
            if. index~:ReferenceIndex do.
                for_i. i.#SnapshotTimes do.
                    snapshot =. i{::6{::result
                    other =. i{::6{::reference
                    errors =. |(1{::snapshot)-1{::other
                    squares =. errors*errors
                    rms =. %:(ordered_sum squares)%CellCount
                    lines =. lines,<'compare ',name,' ',ReferenceName,' time ',(time_text i{SnapshotTimes),' max_diff ',(6 real_text >./errors),' rms_diff ',6 real_text rms
                end.
            end.
            difference =. >./|(3{::result)-Solution
            lines =. lines,<'final ',name,' steady_max_diff ',6 real_text difference
        end.
    end.
    lines =. lines,<'steady direct max_residual ',6 real_text RHS maximum_residual Solution
    for_iteration. IterativeResults do.
        'method field changes converged omega rate milestones error residual' =. >iteration
        lines =. lines,<'steady ',method,' iterations ',(integer #changes),' max_diff ',(6 real_text error),' max_residual ',6 real_text residual
    end.
    lines =. lines,(<'jacobi_spectral_radius ',(6 real_text Rho),' squared ',6 real_text Rho*Rho),<'omega_estimated ',4 real_text OmegaOpt
    lines
)
isotherm_output =: 3 : 0
    'counts grid' =. Bands isotherm_lines Solution
    lines =. (<'isotherms steady counts ',words counts),grid
    reference =. ReferenceIndex{::Results
    for_snapshot. 6{::reference do.
        'now field stored boundary generated' =. >snapshot
        'counts grid' =. Bands isotherm_lines field
        lines =. lines,(<'isotherms ',ReferenceName,' time ',(time_text now),' counts ',words counts),grid
    end.
    lines
)
run =: 3 : 0
    'Width Height Dx Thickness Codes Neighbors' =: read_plate ''
    CellCount =: Width*Height
    'MaterialCodes MaterialNames MaterialValues' =: read_materials ''
    read_boundary ''
    read_parameters ''
    build_system ''
    solve_steady ''
    Results =: simulate_run&.>Runs
    ReferenceIndex =: _1
    for_i. i.#Results do.
        if. ReferenceName-:0{::0{::i{::Results do. ReferenceIndex =: i end.
    end.
    'snapshots.txt'write_lines snapshot_lines ''
    'probes.csv'write_lines probe_lines ''
    'steady_state.txt'write_lines steady_state_lines ''
    'solver_comparison.txt'write_lines comparison_lines ''
    'isotherms.txt'write_lines isotherm_output ''
    0
)
run ''
