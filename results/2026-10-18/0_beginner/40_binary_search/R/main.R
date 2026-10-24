numbers <- c(3,8,11,15,19,24,27,31,36,42,47,53,58,64,70,77)
for (target in c(42,3,77,31,50,1)) {
    lo <- 0
    hi <- length(numbers)-1
    found <- -1
    probes <- numeric(0)
    while (lo <= hi) {
        mid <- (lo+hi) %/% 2
        probes <- c(probes,mid)
        if (numbers[mid+1] == target) {
            found <- mid
            break
        } else if (numbers[mid+1] < target) {
            lo <- mid+1
        } else {
            hi <- mid-1
        }
    }
    result <- if (found >= 0) sprintf("index %d",found) else "not found"
    cat(sprintf("%d: probes %s -> %s\n",target,paste(probes,collapse=" "),result))
}
