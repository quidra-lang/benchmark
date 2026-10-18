small_words <- function(number) {
    units <- strsplit("zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen"," ")[[1]]
    tens <- strsplit("zero ten twenty thirty forty fifty sixty seventy eighty ninety"," ")[[1]]
    parts <- character(0)
    hundreds <- number %/% 100
    remainder <- number %% 100
    if (hundreds > 0) parts <- c(parts,paste(units[hundreds+1],"hundred"))
    if (remainder >= 20) {
        phrase <- tens[remainder %/% 10+1]
        if (remainder %% 10 > 0) phrase <- paste0(phrase,"-",units[remainder %% 10+1])
        parts <- c(parts,phrase)
    } else if (remainder > 0) parts <- c(parts,units[remainder+1])
    paste(parts,collapse=" ")
}
number_words <- function(number) {
    if (number == 0) return("zero")
    parts <- character(0)
    thousands <- number %/% 1000
    remainder <- number %% 1000
    if (thousands > 0) parts <- c(parts,paste(small_words(thousands),"thousand"))
    if (remainder > 0) parts <- c(parts,small_words(remainder))
    paste(parts,collapse=" ")
}
for (number in c(0,13,40,100,568,71000,300019,999999)) cat(sprintf("%d: %s\n",number,number_words(number)))
