gain =: 3 : 0
    'samples numerator denominator' =. y
    clipped_result (samples*numerator) rdiv denominator
)
mix =: 3 : 0
    'tracks weights denominator' =. y
    values =. 0$0
    for_index. i.>./#&>tracks do.
        total =. 0
        for_trackindex. i.#tracks do.
            track =. trackindex{::tracks
            if. index<#track do. total =. total+(trackindex{weights)*index{track end.
        end.
        values =. values,total rdiv denominator
    end.
    clipped_result values
)
delay_signal =: 4 : '(y$0),x'
echo =: 3 : 0
    'samples delay numerator denominator tail' =. y
    output =. samples,tail$0
    clips =. 0
    for_index. delay+i.0>.(#output)-delay do.
        value =. (index{output)+((numerator*(index-delay){output) rdiv denominator)
        clips =. clips+(value<_32768)+.value>32767
        output =. (sat value) index}output
    end.
    'samples clipped' record (<output),<clips
)
resampled_length =: 3 : 0
    'length oldrate newrate' =. y
    1+((length-1)*newrate) div oldrate
)
resample =: 3 : 0
    'samples oldrate newrate' =. y
    output =. 0$0
    for_index. i.resampled_length (#samples),oldrate,newrate do.
        numerator =. index*oldrate
        position =. numerator div newrate
        remainder =. newrate|numerator
        value =. position{samples
        if. remainder>0 do. value =. value+(((((position+1){samples)-value)*remainder) rdiv newrate) end.
        output =. output,value
    end.
    output
)
fade =: 3 : 0
    'samples fadein fadeout' =. y
    length =. #samples
    for_index. i.fadein do. samples =. (((index{samples)*index) rdiv fadein) index}samples end.
    for_index. (length-fadeout)+i.fadeout do. samples =. (((index{samples)*((length-1)-index)) rdiv fadeout) index}samples end.
    samples
)
