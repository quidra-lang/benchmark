read_season =: 3 : 0
    TeamIds =: TeamNames =: 0$a:
    for_line. }.read_lines 'teams.csv' do.
        'id name' =. ',' split >line
        TeamIds =: TeamIds,<id
        TeamNames =: TeamNames,<name
    end.
    TeamCount =: #TeamIds
    Matches =: 0 5$0
    for_line. }.read_lines 'matches.csv' do.
        'round home away homescore awayscore' =. ',' split >line
        Matches =: Matches,(num round),(TeamIds i.<home),(TeamIds i.<away),(num homescore),num awayscore
    end.
    Matches =: (/:0{"1 Matches){Matches
    FinalRound =: >./0{"1 Matches
    SettingNames =: SettingValues =: 0$a:
    for_line. read_lines 'params.txt' do.
        fields =. ' ' split >line
        SettingNames =: SettingNames,{.fields
        SettingValues =: SettingValues,<}.fields
    end.
    WinPoints =: integer_setting 'WIN_POINTS'
    DrawPoints =: integer_setting 'DRAW_POINTS'
    FormLength =: integer_setting 'FORM_LENGTH'
    CloseMargin =: integer_setting 'CLOSE_MARGIN'
    Exponent =: 0".0{::setting 'PYTHAGOREAN_EXPONENT'
    EloK =: integer_setting 'ELO_K'
    EloHome =: integer_setting 'ELO_HOME'
    EloInitial =: integer_setting 'ELO_INITIAL'
    GridK =: num&>setting 'ELO_GRID_K'
    GridHome =: num&>setting 'ELO_GRID_HOME'
    BtIterations =: integer_setting 'BT_ITERATIONS'
    OdIterations =: integer_setting 'OD_ITERATIONS'
    LinkIterations =: integer_setting 'LINK_ITERATIONS'
    HoldoutRound =: integer_setting 'HOLDOUT_ROUND'
    UpsetLimit =: integer_setting 'UPSETS'
    BinCount =: integer_setting 'CALIBRATION_BINS'
    Simulations =: integer_setting 'SIMULATIONS'
    SimState =: integer_setting 'SIM_SEED'
    TopPositions =: integer_setting 'TOP_POSITIONS'
    BottomPositions =: integer_setting 'BOTTOM_POSITIONS'
    i.0
)
setting =: 3 : '(SettingNames i.<y){::SettingValues'
integer_setting =: 3 : 'num 0{::setting y'
match_result =: 3 : 0
    'round home away first second' =. y
    if. first>second do. 2 elseif. first=second do. 1 else. 0 end.
)
matches_before =: 3 : 'Matches#~(0{"1 Matches)<y'
