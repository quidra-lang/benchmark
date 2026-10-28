nonreceive_event <- function(process,index) {
  process$lamport <- process$lamport+1L
  process$vector[index] <- process$vector[index]+1L
}
receive_event <- function(process,index,sender) {
  process$lamport <- max(process$lamport,sender$lamport)+1L
  process$vector <- pmax(process$vector,sender$vector)
  process$vector[index] <- process$vector[index]+1L
}
less_equal <- function(a,b) all(a <= b)
happens_before <- function(a,b) any(a != b) && less_equal(a,b)
relation <- function(a,b) if (happens_before(a,b)) "->" else if (happens_before(b,a)) "<-" else "||"
broadcast_deliverable <- function(stamp,received,source) all(vapply(
    seq_along(stamp),
    function(k) if (k == source) stamp[k] == received[k]+1L else stamp[k] <= received[k],
    logical(1)
))
missing_indices <- function(
    stamp,
    received,
    source
) which(stamp > received+as.integer(seq_along(stamp) == source))
vector_text <- function(vector) paste(vector,collapse=",")
