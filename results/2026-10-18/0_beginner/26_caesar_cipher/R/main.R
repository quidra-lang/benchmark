caesar <- function(message, shift) {
    codes <- utf8ToInt(message)
    for (i in seq_along(codes)) {
        code <- codes[i]
        if (code >= 65 && code <= 90) {
            codes[i] <- 65 + (code-65+shift) %% 26
        } else if (code >= 97 && code <= 122) {
            codes[i] <- 97 + (code-97+shift) %% 26
        }
    }
    intToUtf8(codes)
}
ciphertext <- caesar("Zoe, meet Max by the Old Bridge at six!", 3)
cat(ciphertext, "\n", caesar(ciphertext, -3), "\n", sep = "")
