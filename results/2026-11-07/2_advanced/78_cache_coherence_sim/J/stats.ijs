Transactions =: ;:'BusRd BusRdX BusUpgr BusWr WB'
Services =: ;:'l1 upgrade through cache l2 memory'
MissKinds =: ;:'compulsory capacity conflict coherence'
SnoopCounters =: ;:'invalidations_sent invalidations_received supplied back_invalidations'
empty_counters =: 3 : '32$0'
initialize_counters =: 3 : 'CoreCounters =: (NumberCores,32)$0'
counter_add =: 4 : 0
    'index amount' =. y
    position =. <x,index
    CoreCounters =: (amount+position{CoreCounters)position}CoreCounters
)
total_counters =: 3 : 0
    total =. +/y
    (>./31{"1 y)31}total
)
fraction =: 4 : 0
    factor =. x+.y
    (integer x intdiv factor),'/',integer y intdiv factor
)
decimal =: 4 : 0
    value =. (y+200*x)intdiv 2*y
    (integer value intdiv 100),'.',_2{.'00',integer 100|value
)
core_string =: 3 : 0
    if. 0=#y do.
        '-' return.
    end.
    ;integer&.>/:~y
)
mask_cores =: 3 : 'I.0~:2|y intdiv 2^i.NumberCores'
paired_counts =: 4 : 0
    parts =. 0$a:
    for_i. i.#x do.
        parts =. parts,<(i{::x),' ',integer i{y
    end.
    ' 'join parts
)
range_counts =: 4 : 0
    parts =. 0$a:
    for_i. i.#x do.
        parts =. parts,<(i{::x),':',integer i{y
    end.
    ' 'join parts
)
six_lines =: 4 : 0
    lines =. <x,' ',(;:'accesses reads writes hits misses fences')paired_counts 6{.y
    names =. MissKinds,;:'true_sharing false_sharing'
    lines =. lines,<x,' misses ',names paired_counts 6{.10}.y
    lines =. lines,<x,' service ',Services paired_counts 6{.16}.y
    lines =. lines,<x,' bus ',Transactions paired_counts 5{.22}.y
    lines =. lines,<x,' snoop ',SnoopCounters paired_counts 4{.27}.y
    latency =. 6{y
    accesses =. 0{y
    line =. x,' time latency ',(integer latency),' amat ',(latency fraction accesses),' ',latency decimal accesses
    line =. line,' fence_stall ',(integer 7{y),' finish ',integer 31{y
    lines,<line
)
