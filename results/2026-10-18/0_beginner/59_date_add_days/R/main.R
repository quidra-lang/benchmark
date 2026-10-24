days_in_month <- function(year,month) {
    leap <- year %% 400 == 0 || (year %% 4 == 0 && year %% 100 != 0)
    if (month == 2 && leap) 29 else c(31,28,31,30,31,30,31,31,30,31,30,31)[month]
}
dates <- c("1999-12-25","2000-02-27","2021-02-20","2023-11-15","2026-10-17")
additions <- c(10,3,14,120,1500)
for (i in seq_along(dates)) {
    parts <- as.integer(strsplit(dates[i],"-",fixed=TRUE)[[1]])
    year <- parts[1]
    month <- parts[2]
    day <- parts[3]
    for (step in seq_len(additions[i])) {
        day <- day+1
        if (day > days_in_month(year,month)) {
            day <- 1
            month <- month+1
            if (month > 12) {
                month <- 1
                year <- year+1
            }
        }
    }
    cat(sprintf("%s + %d days = %04d-%02d-%02d\n",dates[i],additions[i],year,month,day))
}
