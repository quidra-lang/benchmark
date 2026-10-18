counts <- integer(26)
for (code in utf8ToInt(tolower("Peter Piper picked a peck of pickled peppers!"))) {
    if (code >= 97 && code <= 122) counts[code-96] <- counts[code-96] + 1L
}
for (i in 1:26) if (counts[i] > 0) cat(sprintf("%s: %d\n", letters[i], counts[i]))
