state_pattern =: 4 : '(y{::SlotCells){x'
state_assign =: 4 : 0
    'letters words' =. x
    'slot word' =. y
    cells =. slot{::SlotCells
    filled =. cells#~'.'=cells{letters
    letters =. (word{::WordNames)cells}letters
    words =. word slot}words
    (<letters),(<words),<filled
)
state_candidates =: 4 : 0
    'letters words minimum' =. y
    (letters state_pattern x)candidates (<minimum),<words#~words>:0
)
search =: 3 : 0
    chosen =. _1
    chosenwords =. 0$0
    for_slot. i.SlotCount do.
        if. _1~:slot{StateWords do. continue. end.
        words =. slot state_candidates (<StateLetters),(<StateWords),<AttemptMinimum
        if. (chosen=_1)+.(#words)<#chosenwords do. chosen =. slot
            chosenwords =. words end.
    end.
    if. chosen=_1 do. 1 return. end.
    if. 0=#chosenwords do.
        DeadEnds =: DeadEnds+1
        Failures =: (1+chosen{Failures)chosen}Failures
        0 return.
    end.
    for_word. chosenwords do.
        if. Nodes=AttemptBudget do. 2 return. end.
        Nodes =: Nodes+1
        'letters words filled' =. ((<StateLetters),<StateWords)state_assign chosen,word
        StateLetters =: letters
        StateWords =: words
        Sequence =: Sequence,chosen
        wiped =. _1
        for_other. chosen{::SlotCrossings do.
            if. _1=other{StateWords do.
                available =. other state_candidates (<StateLetters),(<StateWords),<AttemptMinimum
                if. 0=#available do. wiped =. other break. end.
            end.
        end.
        if. Nodes<:10 do.
            mark =. ''
            if. wiped~:_1 do. mark =. '!' end.
            Trace =: Trace,< (chosen{::SlotLabels),'=',(word{::WordNames),mark
        end.
        if. wiped~:_1 do.
            Prunes =: Prunes+1
            Failures =: (1+wiped{Failures)wiped}Failures
            result =. 0
        else.
            if. (#Sequence)>MaxDepth do.
                MaxDepth =: #Sequence
                BestLetters =: StateLetters
                BestWords =: StateWords
            end.
            result =. search ''
        end.
        if. result~:0 do. result return. end.
        StateLetters =: '.' filled}StateLetters
        StateWords =: _1 chosen}StateWords
        Sequence =: }:Sequence
        Backtracks =: Backtracks+1
    end.
    0
)
run_attempt =: 4 : 0
    'StateLetters StateWords' =: x
    'AttemptMinimum AttemptBudget' =: y
    BestLetters =: StateLetters
    BestWords =: StateWords
    Nodes =: Backtracks =: Prunes =: DeadEnds =: MaxDepth =: 0
    Sequence =: 0$0
    Failures =: SlotCount$0
    Trace =: 0$a:
    result =. search ''
    outcome =. result{::'unfillable';'filled';'budget'
    letters =. StateLetters
    words =. StateWords
    if. result~:1 do. letters =. BestLetters
        words =. BestWords end.
    (<outcome),(<AttemptMinimum),(<AttemptBudget),(<Nodes),(<Backtracks),(<Prunes),(<DeadEnds),(<MaxDepth),(<Sequence),(<Failures),(<Trace),(<letters),<words
)
