caesar <- function(message, shift) {
    indices <- (seq_along(letters) - 1 + shift) %% 26 + 1
    alphabet <- paste0(c(LETTERS, letters), collapse = "")
    shifted <- paste0(c(LETTERS[indices], letters[indices]), collapse = "")
    chartr(alphabet, shifted, message)
}
ciphertext <- caesar("Zoe, meet Max by the Old Bridge at six!", 3)
cat(ciphertext, "\n", caesar(ciphertext, -3), "\n", sep = "")
