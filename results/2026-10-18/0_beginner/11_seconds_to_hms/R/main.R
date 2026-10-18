for (seconds in c(0, 59, 3725, 45296, 86400, 312047)) {
    hours <- seconds %/% 3600
    minutes <- (seconds %% 3600) %/% 60
    cat(sprintf("%d seconds = %02d:%02d:%02d\n", seconds, hours, minutes, seconds %% 60))
}
