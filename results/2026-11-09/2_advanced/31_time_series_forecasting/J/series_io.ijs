read_rows =: 3 : 0
    result =. 0$a:
    for_line. }.<;._2 (1!:1 <'input/',y) do.
        result =. result,<','split >line
    end.
    result
)
read_inputs =: 3 : 0
    SeriesNames =: SeriesPeriods =: SeriesRaw =: 0$a:
    for_row. read_rows 'series.csv' do.
        'name period value' =. >row
        index =. SeriesNames i.<name
        if. index=#SeriesNames do.
            SeriesNames =: SeriesNames,<name
            SeriesPeriods =: SeriesPeriods,<0$a:
            SeriesRaw =: SeriesRaw,<i.0
        end.
        raw =. _1
        if. -.value-:'NA' do.
            raw =. num value
        end.
        SeriesPeriods =: (<(index{::SeriesPeriods),<period)index}SeriesPeriods
        SeriesRaw =: (<(index{::SeriesRaw),raw)index}SeriesRaw
    end.
    EventSeries =: EventPeriods =: EventKinds =: 0$a:
    for_row. read_rows 'events.csv' do.
        'name period kind' =. >row
        EventSeries =: EventSeries,<name
        EventPeriods =: EventPeriods,<period
        EventKinds =: EventKinds,<kind
    end.
    Inventories =: 0$a:
    for_row. read_rows 'inventory.csv' do.
        fields =. >row
        policy =. (0{fields),(<num 1{::fields),(<num 2{::fields),(<num 3{::fields),<decimal 4{::fields
        Inventories =: Inventories,<policy
    end.
    rows =. 0$a:
    for_line. <;._2 (1!:1 <'input/params.txt') do.
        rows =. rows,<' 'split >line
    end.
    Season =: num 1{::0{::rows
    Holdout =: num 1{::1{::rows
    Horizon =: num 1{::2{::rows
    CVStart =: num 1{::3{::rows
    ComboCount =: num 1{::4{::rows
    Alpha =: decimal&>}.5{::rows
    Beta =: decimal&>}.6{::rows
    Gamma =: decimal&>}.7{::rows
    Phi =: decimal&>}.8{::rows
    MaxAR =: num 1{::9{::rows
    MaxLag =: num 1{::10{::rows
    LjungLags =: num&>}.11{::rows
    OutlierZ =: decimal 1{::12{::rows
    IntervalZ =: decimal&>}.13{::rows
    i.0
)
pad_zero =: 4 : 0
    value =. ":y
    ((0>.x-#value)#'0'),value
)
next_month =: 3 : 0
    'year month' =. num&>'-'split y
    year =. year+month intdiv 12
    month =. 1+12|month
    (4 pad_zero year),'-',2 pad_zero month
)
real_text =: 3 : 0
    value =. 0j4":y
    value =. value#~value~:' '
    if. value-:'_0.0000' do.
        '0.0000' return.
    end.
    '-'(I.value='_')}value
)
write_lines =: 4 : 0
    value =. ''
    for_line. y do.
        value =. value,(>line),LF
    end.
    value 1!:2 <'output/',x
)
