read_lines =: 3 : '<;._2 (1!:1 <''input/'',y)'
decimal =: 3 : 0
    normalized =. '_' (I.y='-')}y
    0".normalized
)
setting =: 3 : '(SettingNames i.<y){::SettingValues'
integer_setting =: 3 : 'num 0{::setting y'
read_dataset =: 3 : 0
    lines =. read_lines 'data.csv'
    FeatureNames =: 2}.','split 0{::lines
    FeatureCount =: #FeatureNames
    Ids =: Labels =: 0$a:
    Raw =: (0,FeatureCount)$0.0
    for_line. }.lines do.
        fields =. ','split >line
        Ids =: Ids,0{fields
        Labels =: Labels,1{fields
        Raw =: Raw,decimal&>2}.fields
    end.
    Count =: #Ids
    unique =. ~.Labels
    Classes =: (ascii_order unique){unique
    ClassCount =: #Classes
    Targets =: Classes i.Labels
    SettingNames =: SettingValues =: 0$a:
    for_line. read_lines 'params.txt' do.
        fields =. ' 'split >line
        SettingNames =: SettingNames,{.fields
        SettingValues =: SettingValues,<}.fields
    end.
    DistanceName =: 0{::setting 'DISTANCE'
    Standardize =: 0{::setting 'STANDARDIZE'
    Linkages =: setting 'LINKAGES'
    CutHeights =: decimal&>setting 'CUT_HEIGHTS'
    CutCounts =: num&>setting 'CUT_K'
    inconsistency =. setting 'INCONSISTENCY'
    InconsistencyDepthText =: 0{::inconsistency
    InconsistencyDepth =: 120
    if. 3>:#InconsistencyDepthText do. InconsistencyDepth =: 120<.num InconsistencyDepthText end.
    InconsistencyCount =: num 1{::inconsistency
    GapMaxK =: integer_setting 'GAP_MAX_K'
    ListSize =: integer_setting 'LIST_SIZE'
    Width =: integer_setting 'DENDROGRAM_WIDTH'
    CompareLinkage =: 0{::setting 'COMPARE_LINKAGE'
    'Replicates Percent Seed' =: num&>setting 'SUBSAMPLES'
    RefineIterations =: integer_setting 'REFINE_ITERATIONS'
    i.0
)
write_lines =: 4 : 0
    text =. ''
    for_line. y do. text =. text,(>line),LF end.
    text 1!:2 <'output/',x
)
