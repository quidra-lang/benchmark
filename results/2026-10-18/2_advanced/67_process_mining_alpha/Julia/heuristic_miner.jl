dependency(counts,a,b) = (count_at(counts,a,b)-count_at(counts,b,a))//(count_at(counts,a,b)+count_at(
    counts,
    b,
    a
)+1)
loop_measure(n) = n//(n+1)
split_measure(
    counts,
    a,
    b,
    c
) = (count_at(counts,b,c)+count_at(counts,c,b))//(count_at(counts,a,b)+count_at(counts,a,c)+1)
join_measure(
    counts,
    a,
    b,
    c
) = (count_at(counts,b,c)+count_at(counts,c,b))//(count_at(counts,b,a)+count_at(counts,c,a)+1)
