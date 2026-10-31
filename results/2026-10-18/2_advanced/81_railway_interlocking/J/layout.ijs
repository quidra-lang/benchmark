read_layout =: 3 : 0
    lines =. read_lines 'input/layout.txt'
    SectionNames =: 0$a:
    SectionLengths =: i.0
    SectionRows =: i.0
    SectionFirst =: i.0
    SectionLast =: i.0
    for_line. lines do.
        fields =. split_words >line
        if. 'SECTION'-:0{::fields do.
            SectionNames =: SectionNames,1{fields
            'length row first last' =. ".' 'join 2}.fields
            SectionLengths =: SectionLengths,length
            SectionRows =: SectionRows,row
            SectionFirst =: SectionFirst,first
            SectionLast =: SectionLast,last
        end.
    end.
    count =. #SectionNames
    EndKinds =: (count,2)$_1
    EndValues =: (count,2)$_1
    SignalAt =: (count,2)$_1
    SectionFailed =: count$0
    Occupants =: count$<i.0
    SectionOccupiedSeconds =: count$0
    SectionLockedSeconds =: count$0
    SectionTrains =: count$<i.0
    PointNames =: 0$a:
    PointSide =: i.0
    PointCommon =: i.0
    PointNormal =: i.0
    PointReverse =: i.0
    PointRows =: i.0
    PointColumns =: i.0
    SignalNames =: 0$a:
    SignalSections =: i.0
    SignalDirections =: i.0
    SignalRows =: i.0
    SignalColumns =: i.0
    BufferNames =: 0$a:
    BufferSections =: i.0
    BufferEnds =: i.0
    BufferRows =: i.0
    BufferColumns =: i.0
    BoundaryNames =: 0$a:
    BoundarySections =: i.0
    BoundaryEnds =: i.0
    Labels =: 0$a:
    for_line. lines do.
        fields =. split_words >line
        kind =. 0{::fields
        select. kind
        case. 'JOINT' do.
            first =. SectionNames i.1{fields
            second =. SectionNames i.2{fields
            EndKinds =: 0(<first,1)}EndKinds
            EndKinds =: 0(<second,0)}EndKinds
            EndValues =: second(<first,1)}EndValues
            EndValues =: first(<second,0)}EndValues
        case. 'POINT' do.
            point =. #PointNames
            PointNames =: PointNames,1{fields
            side =. 'R'={.2{::fields
            common =. SectionNames i.3{fields
            normal =. SectionNames i.4{fields
            reverse =. SectionNames i.5{fields
            PointSide =: PointSide,side
            PointCommon =: PointCommon,common
            PointNormal =: PointNormal,normal
            PointReverse =: PointReverse,reverse
            PointRows =: PointRows,".6{::fields
            PointColumns =: PointColumns,".7{::fields
            EndKinds =: 1(<common,side)}EndKinds
            EndValues =: point(<common,side)}EndValues
            for_section. normal,reverse do.
                position =. <section,1-side
                EndKinds =: 1 position}EndKinds
                EndValues =: point position}EndValues
            end.
        case. 'SIGNAL' do.
            signal =. #SignalNames
            SignalNames =: SignalNames,1{fields
            section =. SectionNames i.2{fields
            direction =. 'DOWN'-:3{::fields
            SignalSections =: SignalSections,section
            SignalDirections =: SignalDirections,direction
            SignalRows =: SignalRows,".4{::fields
            SignalColumns =: SignalColumns,".5{::fields
            SignalAt =: signal(<section,direction)}SignalAt
        case. 'BUFFER';'BOUNDARY' do.
            section =. SectionNames i.2{fields
            side =. 'R'={.3{::fields
            position =. <section,side
            if. kind-:'BUFFER' do.
                index =. #BufferNames
                BufferNames =: BufferNames,1{fields
                BufferSections =: BufferSections,section
                BufferEnds =: BufferEnds,side
                BufferRows =: BufferRows,".4{::fields
                BufferColumns =: BufferColumns,".5{::fields
                EndKinds =: 2 position}EndKinds
            else.
                index =. #BoundaryNames
                BoundaryNames =: BoundaryNames,1{fields
                BoundarySections =: BoundarySections,section
                BoundaryEnds =: BoundaryEnds,side
                EndKinds =: 3 position}EndKinds
            end.
            EndValues =: index position}EndValues
        case. 'LABEL' do.
            Labels =: Labels,<(<".1{::fields),(<".2{::fields),3{fields
        end.
    end.
    count =. #PointNames
    PointPositions =: count$0
    PointMoving =: count$0
    PointFailed =: count$0
    PointTargets =: count$_1
    PointCompletions =: count$_1
    PointThrows =: count$0
    PointLockedSeconds =: count$0
    PointMovingSeconds =: count$0
    SignalAspects =: (#SignalNames)$0
    SignalSeconds =: ((#SignalNames),3)$0
    SignalPasses =: (#SignalNames)$0
    rows =. SectionRows,PointRows,SignalRows,BufferRows
    columns =. SectionLast,PointColumns,SignalColumns,BufferColumns
    for_label. Labels do.
        'row column text' =. >label
        rows =. rows,row
        columns =. columns,(column+#text)-1
    end.
    DiagramHeight =: 1+>./rows
    DiagramWidth =: 1+>./columns
)
point_detected =: 3 : '-.(y{PointMoving)+.y{PointFailed'
beyond =: 4 : 0
    position =. <x,1-y
    kind =. position{EndKinds
    value =. position{EndValues
    if. kind~:1 do.
        kind,value return.
    end.
    point =. value
    branch =. point{PointNormal
    if. point{PointPositions do.
        branch =. point{PointReverse
    end.
    if. (point{PointMoving)+.((x~:point{PointCommon)*.x~:branch) do.
        4 _1
    elseif. x=point{PointCommon do.
        0,branch
    else.
        0,point{PointCommon
    end.
)
