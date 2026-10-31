finish_trigger =: 4 : 0
    ending =. x
    'beginning peak_ratio station start sw minimum noise amplitude_window clip_level' =. y
    TriggerCount =: TriggerCount+1
    duration =. ending-beginning
    if. duration<minimum do.
        ShortCount =: ShortCount+1
        i.0 return.
    end.
    position =. beginning
    while. (position-1)>:(beginning-sw)+1 do.
        if. ((position-1){PickEnergy)<noise do.
            break.
        end.
        position =. position-1
    end.
    last =. (#PickSamples)<.position+amplitude_window
    amplitude =. 0x
    clipped =. 0
    for_j. position+i.last-position do.
        amplitude =. amplitude>.|j{PickCentered
        clipped =. clipped+.(|j{PickSamples)>:clip_level
    end.
    DetectedMeta =: DetectedMeta,station,(start+position),duration,amplitude,clipped
    DetectedRatios =: DetectedRatios,peak_ratio
    i.0
)
detect_station =: 4 : 0
    'station start params' =. x
    samples =. x:y
    count =. #samples
    mean =. (+/samples)intdiv count
    centered =. samples-mean
    energy =. centered*centered
    prefix =. 0x,+/\energy
    sw =. {.0{::params
    lw =. {.1{::params
    'on_num on_den' =. 2{::params
    'off_num off_den' =. 3{::params
    minimum =. {.4{::params
    noise =. {.5{::params
    amplitude_window =. {.6{::params
    clip_level =. {.7{::params
    PickSamples =: samples
    PickCentered =: centered
    PickEnergy =: energy
    DetectedMeta =: 0 5$0x
    DetectedRatios =: i.0
    TriggerCount =: 0
    ShortCount =: 0
    on =. 0
    beginning =. 0
    peak_ratio =. 0.0
    first_index =. sw+lw-1
    for_i. first_index+i.count-first_index do.
        sta_begin =. (i-sw)+1
        lta_begin =. ((i-sw)-lw)+1
        sta =. ((i+1){prefix)-sta_begin{prefix
        lta =. (sta_begin{prefix)-lta_begin{prefix
        if. -.on do.
            if. (sta*lw*on_den)>:on_num*lta*sw do.
                on =. 1
                beginning =. i
                peak_ratio =. (0.0+sta*lw)%0.0+lta*sw
            end.
        elseif. (sta*lw*off_den)<off_num*lta*sw do.
            args =. (<beginning),(<peak_ratio),(<station),(<start),(<sw),(<minimum),(<noise),(<amplitude_window),<clip_level
            i finish_trigger args
            on =. 0
        else.
            peak_ratio =. peak_ratio>.(0.0+sta*lw)%0.0+lta*sw
        end.
    end.
    if. on do.
        args =. (<beginning),(<peak_ratio),(<station),(<start),(<sw),(<minimum),(<noise),(<amplitude_window),<clip_level
        count finish_trigger args
    end.
    ordered =. /:~|centered
    middle =. count intdiv 2
    noise_twice =. 2*middle{ordered
    if. 0=2|count do.
        noise_twice =. ((middle-1){ordered)+middle{ordered
    end.
    statistics =. mean,noise_twice,(>./|centered),(+/ (|samples)>:clip_level),TriggerCount,ShortCount,#DetectedMeta
    (<DetectedMeta),(<DetectedRatios),<statistics
)
