rdiv =: 4 : '((2*x)+y) div 2*y'
sat =: 3 : '_32768>.32767<.y'
clipped_result =: 3 : '''samples clipped'' record (<sat y),<+/(y<_32768)+.y>32767'
peak =: 3 : '>./|y'
signal_record =: 3 : '''name rate samples origin ingredients'' record y'
read_signals =: 3 : 0
    lines =. read_lines 'signals.txt'
    signals =. 0$a:
    index =. 0
    while. index<#lines do.
        header =. ' ' split index{::lines
        name =. 1{::header
        rate =. num 2{::header
        count =. num 3{::header
        index =. index+1
        samples =. 0$0
        while. (#samples)<count do.
            samples =. samples,signed_num&>' ' split index{::lines
            index =. index+1
        end.
        signals =. signals,<signal_record (<name),(<rate),(<samples),(<'input'),<0$a:
    end.
    signals
)
format_signal =: 3 : 0
    samples =. 'samples' get_key y
    lines =. <'SIGNAL ',('name' get_key y),' ',(number 'rate' get_key y),' ',number #samples
    for_first. 16*i.1+(<:#samples) div 16 do.
        count =. 16<.(#samples)-first
        lines =. lines,<' ' join number&.><"0 count{.first}.samples
    end.
    lines
)
impulse =: 3 : 0
    'count position amplitude' =. y
    amplitude position}(count$0)
)
step_signal =: 3 : 0
    'count position amplitude' =. y
    (position$0),(count-position)$amplitude
)
noise =: 3 : 0
    'count state' =. y
    samples =. 0$0
    for_index. i.count do.
        state =. 2147483647|48271*state
        samples =. samples,(65536|state)-32768
    end.
    samples
)
