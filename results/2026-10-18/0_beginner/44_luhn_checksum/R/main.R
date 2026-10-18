numbers <- c("688126340316","0128469655154","92181914514156","177332430060552","7982377590420309","9884593615513906")
for (number in numbers) {
    digits <- rev(utf8ToInt(number)-48L)
    total <- 0
    for (position in seq_along(digits)) {
        value <- digits[position]
        if (position %% 2 == 0) { value <- value*2; if (value > 9) value <- value-9 }
        total <- total+value
    }
    if (total %% 10 == 0) {
        cat(sprintf("%s: valid\n",number))
    } else {
        expected <- (-(total-digits[1])) %% 10
        cat(sprintf("%s: invalid (expected check digit %d)\n",number,expected))
    }
}
