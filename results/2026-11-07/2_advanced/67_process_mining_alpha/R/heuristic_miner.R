dependency <- function(counts,a,b) q(
    count_at(counts,a,b)-count_at(counts,b,a),
    count_at(counts,a,b)+count_at(counts,b,a)+1
)
loop_measure <- function(n) q(n,n+1)
split_measure <- function(counts,a,b,c) q(
    count_at(counts,b,c)+count_at(counts,c,b),
    count_at(counts,a,b)+count_at(counts,a,c)+1
)
join_measure <- function(counts,a,b,c) q(
    count_at(counts,b,c)+count_at(counts,c,b),
    count_at(counts,b,a)+count_at(counts,c,a)+1
)
