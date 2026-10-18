bases <- strsplit("ACGT", "")[[1]]
iupac <- c(
  A = "A", C = "C", G = "G", T = "T", R = "AG",
  Y = "CT", W = "AT", S = "CG", K = "GT", M = "AC",
  B = "CGT", D = "AGT", H = "ACT", V = "ACG", N = "ACGT"
)
symbols <- setNames(names(iupac), unname(iupac))

groups <- c(
  A = "GCT GCC GCA GCG", C = "TGT TGC", D = "GAT GAC",
  E = "GAA GAG", F = "TTT TTC", G = "GGT GGC GGA GGG",
  H = "CAT CAC", I = "ATT ATC ATA", K = "AAA AAG",
  L = "TTA TTG CTT CTC CTA CTG", M = "ATG", N = "AAT AAC",
  P = "CCT CCC CCA CCG", Q = "CAA CAG",
  R = "CGT CGC CGA CGG AGA AGG", S = "TCT TCC TCA TCG AGT AGC",
  T = "ACT ACC ACA ACG", V = "GTT GTC GTA GTG", W = "TGG",
  Y = "TAT TAC", "*" = "TAA TAG TGA"
)
genetic_code <- character()
for (amino in names(groups)) {
  for (codon in strsplit(groups[[amino]], " ", fixed = TRUE)[[1]]) {
    genetic_code[codon] <- amino
  }
}
amino_mass <- setNames(
  c(71079, 103139, 115089, 129116, 147177, 57052, 137141,
    113160, 128174, 113160, 131193, 114104, 97117, 128131,
    156188, 87078, 101105, 99133, 186213, 163176),
  strsplit("ACDEFGHIKLMNPQRSTVWY", "")[[1]]
)
base_mass <- setNames(c(331222, 307197, 347221, 322208), bases)

enzymes <- list(
  EcoRI = c("GAATTC", 1), BamHI = c("GGATCC", 1),
  HindIII = c("AAGCTT", 1), PstI = c("CTGCAG", 5),
  SmaI = c("CCCGGG", 3), KpnI = c("GGTACC", 5),
  XbaI = c("TCTAGA", 1), NotI = c("GCGGCCGC", 2),
  EcoRV = c("GATATC", 3), HaeIII = c("GGCC", 2),
  AluI = c("AGCT", 2), TaqI = c("TCGA", 1),
  Sau3AI = c("GATC", 0), HincII = c("GTYRAC", 3),
  AvaI = c("CYCGRG", 1)
)
arity <- list(
  SEQ = c(2, 2), SLICE = c(4, 4), JOIN = c(3, 9),
  MUTATE = c(3, 3), DEL = c(1, 1), LIST = c(0, 0),
  REVCOMP = c(1, 1), COMPLEMENT = c(1, 1), REVERSE = c(1, 1),
  TRANSCRIBE = c(1, 1), TRANSLATE = c(2, 2), CODONS = c(2, 2),
  PROTEIN = c(2, 2), ORFS = c(2, 2), GC = c(1, 1),
  GCWINDOW = c(3, 3), SKEW = c(1, 1), KMERS = c(3, 3),
  FIND = c(2, 2), RESTRICT = c(2, 7), PALINDROMES = c(3, 3),
  REPEATS = c(4, 4), HAMMING = c(2, 2), ALIGN = c(6, 6),
  CONSENSUS = c(2, 10), TM = c(1, 1), MASS = c(1, 1),
  PRIMER = c(1, 1), FOLD = c(2, 2), ASSEMBLE = c(4, 10),
  PACK = c(1, 1), UNPACK = c(3, 3)
)

registry <- new.env(parent = emptyenv(), hash = TRUE)
output <- character()

chars <- function(text) strsplit(text, "", fixed = TRUE)[[1]]
emit <- function(...) {
  parts <- unlist(list(...), use.names = FALSE)
  output <<- c(output, paste(as.character(parts), collapse = " "))
}
emit_list <- function(label, values) {
  emit(label, if (length(values)) values else "none")
}
fail <- function(reason) stop(reason, call. = FALSE)
registered <- function(name) exists(name, envir = registry, inherits = FALSE)
sequence_of <- function(name) get(name, envir = registry, inherits = FALSE)

complement <- function(sequence) {
  chartr("ACGTRYWSKMBVDHN", "TGCAYRWSMKVBHDN", sequence)
}
reverse_text <- function(sequence) paste(rev(chars(sequence)), collapse = "")
revcomp <- function(sequence) reverse_text(complement(sequence))
gc <- function(sequence) sum(chars(sequence) %in% c("G", "C"))

fixed_text <- function(value, places) {
  scale <- 10^places
  paste0(
    sprintf("%.0f", floor(value / scale)),
    ".",
    sprintf(paste0("%0", places, "d"), as.integer(value %% scale))
  )
}
pct <- function(count, length) fixed_text(floor(10000 * count / length), 2)
transition <- function(a, b) a != b && paste0(a, b) %in% c("AG", "GA", "CT", "TC")
frequency_order <- function(counts) {
  names(counts)[order(-as.numeric(counts), names(counts))]
}
codons <- function(sequence, frame) {
  strand <- if (frame > 0) sequence else revcomp(sequence)
  offset <- abs(frame)
  n <- nchar(strand)
  if (offset + 2 > n) return(character())
  positions <- seq.int(offset, n - 2, by = 3)
  substring(strand, positions, positions + 2)
}
occurrences <- function(sequence, motif) {
  n <- nchar(sequence)
  width <- nchar(motif)
  if (width > n) return(integer())
  characters <- chars(sequence)
  pattern <- chars(motif)
  positions <- integer()
  for (start in seq_len(n - width + 1)) {
    matched <- TRUE
    for (i in seq_len(width)) {
      if (!(characters[start + i - 1] %in% chars(iupac[[pattern[i]]]))) {
        matched <- FALSE
        break
      }
    }
    if (matched) positions <- c(positions, start)
  }
  positions
}
repeat_count <- function(sequence, start, width) {
  unit <- substr(sequence, start, start + width - 1)
  n <- nchar(sequence)
  count <- 0
  while (start + (count + 1) * width - 1 <= n &&
         substr(sequence, start + count * width,
                start + (count + 1) * width - 1) == unit) {
    count <- count + 1
  }
  count
}
primitive <- function(unit) {
  n <- nchar(unit)
  if (n == 1) return(TRUE)
  for (width in seq_len(n - 1)) {
    if (n %% width == 0 &&
        paste(rep(substr(unit, 1, width), n / width), collapse = "") == unit)
      return(FALSE)
  }
  TRUE
}
longest_palindrome <- function(sequence) {
  n <- nchar(sequence)
  if (n < 2) return(0)
  best <- 0
  for (center in seq_len(n - 1)) {
    left <- center
    right <- center + 1
    while (left >= 1 && right <= n &&
           revcomp(substr(sequence, left, left)) == substr(sequence, right, right)) {
      best <- max(best, right - left + 1)
      left <- left - 1
      right <- right + 1
    }
  }
  best
}
temperature <- function(sequence) {
  n <- nchar(sequence)
  amount <- gc(sequence)
  if (n < 14) return(10 * (2 * (n - amount) + 4 * amount))
  floor((649 * n + 410 * amount - 6724) / n)
}
strand_mass <- function(sequence) {
  sum(base_mass[chars(sequence)]) - (nchar(sequence) - 1) * 18015
}

number_arg <- function(text, minimum, maximum, nonzero = FALSE) {
  if (!grepl("^-?[0-9]{1,6}$", text)) fail(paste("invalid number", text))
  value <- as.numeric(text)
  if (value < minimum || value > maximum || (nonzero && value == 0))
    fail(paste("invalid number", text))
  value
}

kinds_for <- function(command, count) {
  result <- switch(
    command,
    SEQ = c("new", "sequence"),
    SLICE = c("name", "position", "position", "new"),
    JOIN = c("new", rep("name", count - 1)),
    MUTATE = c("name", "position", "base"),
    TRANSLATE = c("name", "frame"),
    CODONS = c("name", "frame"),
    PROTEIN = c("name", "frame"),
    ORFS = c("name", "orf"),
    GCWINDOW = c("name", "window", "window"),
    KMERS = c("name", "kmer", "limit"),
    FIND = c("name", "motif"),
    RESTRICT = c("name", rep("enzyme", count - 1)),
    PALINDROMES = c("name", "palwidth", "palwidth"),
    REPEATS = c("name", "repeatwidth", "repeatwidth", "repeatcount"),
    ALIGN = c("name", "name", "mode", "score", "mismatch", "gap"),
    FOLD = c("name", "loop"),
    ASSEMBLE = c("new", "overlap", rep("name", count - 2)),
    UNPACK = c("new", "unpacklength", "hex")
  )
  if (is.null(result)) rep("name", count) else result
}

validate <- function(command, arguments) {
  if (!(command %in% names(arity))) fail(paste("unknown command", command))
  limits <- arity[[command]]
  if (length(arguments) < limits[1] || length(arguments) > limits[2])
    fail("wrong argument count")
  values <- as.list(arguments)
  seen_enzymes <- character()
  kinds <- kinds_for(command, length(arguments))
  for (i in seq_along(values)) {
    kind <- kinds[i]
    text <- arguments[i]
    if (kind %in% c("position", "frame", "orf", "window", "kmer", "limit",
                    "palwidth", "repeatwidth", "repeatcount", "score", "mismatch",
                    "gap", "loop", "overlap", "unpacklength")) {
      bounds <- switch(
        kind,
        position = c(1, nchar(sequence_of(arguments[1]))),
        frame = c(-3, 3),
        orf = c(1, 200),
        window = c(1, 500),
        kmer = c(1, 12),
        limit = c(1, 100),
        palwidth = c(2, 20),
        repeatwidth = c(1, 6),
        repeatcount = c(2, 50),
        score = c(1, 20),
        mismatch = c(-20, 0),
        gap = c(-20, -1),
        loop = c(0, 10),
        overlap = c(1, 100),
        unpacklength = c(1, 500)
      )
      values[[i]] <- number_arg(text, bounds[1], bounds[2], kind == "frame")
    } else if (kind == "name") {
      if (!registered(text)) fail(paste("unknown sequence", text))
    } else if (kind == "new") {
      if (!grepl("^[a-z][a-z0-9]{0,9}$", text)) fail(paste("invalid name", text))
    } else if (kind == "sequence") {
      for (position in seq_along(chars(text))) {
        base <- chars(text)[position]
        if (!(base %in% bases)) fail(paste("invalid base", base, "at", position))
      }
    } else if (kind == "base") {
      if (nchar(text) != 1 || !(text %in% bases)) fail(paste("invalid base", text))
    } else if (kind == "motif") {
      if (nchar(text) < 1 || nchar(text) > 30 || any(!(chars(text) %in% names(iupac))))
        fail(paste("invalid motif", text))
    } else if (kind == "enzyme") {
      if (!(text %in% names(enzymes))) fail(paste("unknown enzyme", text))
      if (text %in% seen_enzymes) fail(paste("duplicate enzyme", text))
      seen_enzymes <- c(seen_enzymes, text)
    } else if (kind == "mode") {
      if (!(text %in% c("GLOBAL", "LOCAL"))) fail(paste("invalid mode", text))
    } else if (kind == "hex") {
      length_expected <- 2 * ceiling(values[[2]] / 4)
      if (nchar(text) != length_expected || !grepl("^[0-9A-F]+$", text))
        fail("invalid hex")
    }
  }
  values
}

store <- function(name, sequence) {
  if (nchar(sequence) > 500) fail("too long")
  label <- if (registered(name)) "replaced" else "stored"
  assign(name, sequence, envir = registry)
  paste(label, name, nchar(sequence), "nt")
}

translation <- function(command, name, frame) {
  triplets <- codons(sequence_of(name), frame)
  protein <- paste(unname(genetic_code[triplets]), collapse = "")
  if (command == "TRANSLATE") {
    emit(if (nchar(protein)) protein else "none")
  } else if (command == "CODONS") {
    counts <- table(triplets)
    if (!length(counts)) {
      emit("none")
    } else {
      for (codon in frequency_order(counts))
        emit(codon, genetic_code[[codon]], counts[[codon]])
    }
  } else {
    protein <- strsplit(protein, "*", fixed = TRUE)[[1]][1]
    if (is.na(protein) || nchar(protein) == 0) fail("empty protein")
    letters <- chars(protein)
    counts <- table(letters)
    mass <- sum(amino_mass[letters]) + 18015
    charge <- sum(letters %in% c("K", "R")) - sum(letters %in% c("D", "E"))
    emit(protein)
    emit("length", nchar(protein), "mass", fixed_text(mass, 3),
         "charge", if (charge > 0) paste0("+", charge) else charge)
    emit(paste0(frequency_order(counts), "=", counts[frequency_order(counts)]))
  }
}

orfs <- function(sequence, minimum) {
  results <- list()
  n <- nchar(sequence)
  for (frame in c(1, 2, 3, -1, -2, -3)) {
    triplets <- codons(sequence, frame)
    start <- NA_integer_
    for (position in seq_along(triplets)) {
      codon <- triplets[position]
      if (is.na(start)) {
        if (codon == "ATG") start <- position
      } else if (genetic_code[[codon]] == "*") {
        if (position - start >= minimum) {
          left <- abs(frame) - 1 + 3 * (start - 1)
          right <- abs(frame) - 1 + 3 * position
          if (frame < 0) {
            old_left <- left
            left <- n - right
            right <- n - old_left
          }
          translated <- paste(unname(genetic_code[triplets[start:(position - 1)]]),
                              collapse = "")
          results[[length(results) + 1]] <- list(left + 1, right, frame, translated)
        }
        start <- NA_integer_
      }
    }
  }
  if (!length(results)) {
    emit("none")
    return(invisible(NULL))
  }
  left <- vapply(results, function(x) x[[1]], numeric(1))
  right <- vapply(results, function(x) x[[2]], numeric(1))
  frame <- vapply(results, function(x) x[[3]], numeric(1))
  protein <- vapply(results, function(x) x[[4]], character(1))
  for (i in order(left, right, frame, protein)) {
    row <- results[[i]]
    emit(sprintf("%+d", row[[3]]), row[[1]], row[[2]], nchar(row[[4]]), row[[4]])
  }
}

restrict_sites <- function(sequence, selected) {
  combined <- integer()
  n <- nchar(sequence)
  for (enzyme in selected) {
    definition <- enzymes[[enzyme]]
    positions <- occurrences(sequence, definition[1]) + as.numeric(definition[2]) - 1
    positions <- positions[positions >= 1 & positions < n]
    emit_list(enzyme, positions)
    combined <- union(combined, positions)
  }
  endpoints <- c(0, sort(combined), n)
  fragments <- character()
  sizes <- integer()
  for (i in seq_len(length(endpoints) - 1)) {
    left <- endpoints[i] + 1
    right <- endpoints[i + 1]
    fragments <- c(fragments, paste0(left, "-", right))
    sizes <- c(sizes, right - left + 1)
  }
  emit_list("fragments", fragments)
  emit_list("sizes", sort(sizes, decreasing = TRUE))
}

repeats <- function(sequence, minimum, maximum, count) {
  if (minimum > maximum) fail("invalid range")
  results <- list()
  n <- nchar(sequence)
  for (width in minimum:maximum) {
    position <- 1
    while (position + width - 1 <= n) {
      unit <- substr(sequence, position, position + width - 1)
      repeated <- repeat_count(sequence, position, width)
      if (primitive(unit) && repeated >= count) {
        results[[length(results) + 1]] <- list(position, width, repeated, unit)
        position <- position + repeated * width
      } else {
        position <- position + 1
      }
    }
  }
  if (!length(results)) {
    emit("none")
    return(invisible(NULL))
  }
  positions <- vapply(results, function(x) x[[1]], numeric(1))
  widths <- vapply(results, function(x) x[[2]], numeric(1))
  repeated <- vapply(results, function(x) x[[3]], numeric(1))
  units <- vapply(results, function(x) x[[4]], character(1))
  for (i in order(positions, widths, repeated, units)) {
    row <- results[[i]]
    emit(paste0(row[[1]], "-", row[[1]] + row[[2]] * row[[3]] - 1),
         paste0(row[[4]], "x", row[[3]]))
  }
}

align <- function(a, b, mode, match_score, mismatch, gap) {
  left <- chars(a)
  right <- chars(b)
  m <- length(left)
  n <- length(right)
  table <- matrix(0, nrow = m + 1, ncol = n + 1)
  local <- mode == "LOCAL"
  if (!local) {
    for (i in 0:m) table[i + 1, 1] <- i * gap
    for (j in 0:n) table[1, j + 1] <- j * gap
  }
  best <- 0
  end_i <- 0
  end_j <- 0
  for (i in seq_len(m)) {
    for (j in seq_len(n)) {
      diagonal <- table[i, j] + (if (left[i] == right[j]) match_score else mismatch)
      value <- max(diagonal, table[i, j + 1] + gap, table[i + 1, j] + gap)
      table[i + 1, j + 1] <- if (local) max(0, value) else value
      if (local && table[i + 1, j + 1] > best) {
        best <- table[i + 1, j + 1]
        end_i <- i
        end_j <- j
      }
    }
  }
  if (!local) {
    end_i <- m
    end_j <- n
    best <- table[m + 1, n + 1]
  }
  if (local && best == 0) {
    emit("score", 0)
    return(invisible(NULL))
  }
  i <- end_i
  j <- end_j
  row_a <- character()
  row_b <- character()
  while ((local && table[i + 1, j + 1] != 0) ||
         (!local && (i != 0 || j != 0))) {
    if (i > 0 && j > 0 &&
        table[i + 1, j + 1] ==
        table[i, j] + (if (left[i] == right[j]) match_score else mismatch)) {
      row_a <- c(row_a, left[i])
      row_b <- c(row_b, right[j])
      i <- i - 1
      j <- j - 1
    } else if (i > 0 && table[i + 1, j + 1] == table[i, j + 1] + gap) {
      row_a <- c(row_a, left[i])
      row_b <- c(row_b, "-")
      i <- i - 1
    } else {
      row_a <- c(row_a, "-")
      row_b <- c(row_b, right[j])
      j <- j - 1
    }
  }
  row_a <- rev(row_a)
  row_b <- rev(row_b)
  marks <- ifelse(row_a == "-" | row_b == "-", "-",
                  ifelse(row_a == row_b, "|", "*"))
  emit("score", best, "a", paste0(i + 1, "-", end_i),
       "b", paste0(j + 1, "-", end_j),
       "identity", paste0(sum(marks == "|"), "/", length(marks)),
       "gaps", sum(marks == "-"))
  emit(paste(row_a, collapse = ""))
  emit(paste(marks, collapse = ""))
  emit(paste(row_b, collapse = ""))
}

consensus <- function(sequences) {
  lengths <- nchar(sequences)
  if (any(lengths != lengths[1])) fail("length mismatch")
  matrix_counts <- matrix(0, nrow = 4, ncol = lengths[1])
  chosen <- character()
  ambiguous <- character()
  for (position in seq_len(lengths[1])) {
    column <- substring(sequences, position, position)
    counts <- vapply(bases, function(base) sum(column == base), numeric(1))
    matrix_counts[, position] <- counts
    tied <- bases[counts == max(counts)]
    chosen <- c(chosen, tied[1])
    ambiguous <- c(ambiguous, unname(symbols[[paste(tied, collapse = "")]]))
  }
  for (i in seq_along(bases)) emit(bases[i], matrix_counts[i, ])
  emit("consensus", paste(chosen, collapse = ""))
  emit("iupac", paste(ambiguous, collapse = ""))
}

primer <- function(sequence) {
  n <- nchar(sequence)
  amount <- gc(sequence)
  tm <- temperature(sequence)
  clamp <- gc(substr(sequence, max(1, n - 4), n))
  longest <- max(rle(chars(sequence))$lengths)
  repeated <- 0
  if (n >= 2) {
    for (position in seq_len(n - 1)) {
      if (substr(sequence, position, position) != substr(sequence, position + 1, position + 1))
        repeated <- max(repeated, repeat_count(sequence, position, 2))
    }
  }
  selfcomp <- longest_palindrome(sequence)
  labels <- c("length", "gc", "tm", "clamp", "run", "repeat", "selfcomp")
  values <- list(n, pct(amount, n), fixed_text(tm, 1),
                 clamp, longest, repeated, selfcomp)
  passed <- c(
    n >= 18 && n <= 25,
    40 * n <= 100 * amount && 100 * amount <= 60 * n,
    tm >= 520 && tm <= 620,
    clamp >= 1 && clamp <= 3,
    longest <= 4,
    repeated <= 4,
    selfcomp <= 6
  )
  for (i in seq_along(labels)) emit(labels[i], values[[i]], if (passed[i]) "OK" else "FAIL")
  if (all(passed)) emit("PASS") else emit("FAIL", labels[!passed])
}

fold <- function(sequence, loop) {
  n <- nchar(sequence)
  if (n > 100) fail("too long")
  table <- matrix(0, n, n)
  characters <- chars(sequence)
  value <- function(i, j) if (i > j) 0 else table[i, j]
  pairing <- function(i, j) paste0(characters[i], characters[j]) %in%
    c("AT", "TA", "CG", "GC", "GT", "TG")
  if (n >= 2) {
    for (width in 2:n) {
      for (i in seq_len(n - width + 1)) {
        j <- i + width - 1
        best <- value(i, j - 1)
        if (i <= j - loop - 1) {
          for (k in i:(j - loop - 1)) {
            if (pairing(k, j))
              best <- max(best, value(i, k - 1) + 1 + value(k + 1, j - 1))
          }
        }
        table[i, j] <- best
      }
    }
  }
  structure <- rep(".", n)
  pending <- list(c(1, n))
  while (length(pending)) {
    entry <- pending[[length(pending)]]
    pending <- pending[-length(pending)]
    i <- entry[1]
    j <- entry[2]
    if (i > j || value(i, j) == 0) next
    if (value(i, j) == value(i, j - 1)) {
      pending[[length(pending) + 1]] <- c(i, j - 1)
      next
    }
    if (i <= j - loop - 1) {
      for (k in i:(j - loop - 1)) {
        if (pairing(k, j) &&
            value(i, k - 1) + 1 + value(k + 1, j - 1) == value(i, j)) {
          structure[k] <- "("
          structure[j] <- ")"
          pending[[length(pending) + 1]] <- c(i, k - 1)
          pending[[length(pending) + 1]] <- c(k + 1, j - 1)
          break
        }
      }
    }
  }
  emit(paste(structure, collapse = ""))
  emit("pairs", table[1, n])
}

assemble <- function(name, minimum, sequences) {
  unique <- unique(sequences)
  fragments <- unique[!vapply(unique, function(part)
    any(unique != part & vapply(unique, function(other)
      grepl(part, other, fixed = TRUE), logical(1))), logical(1))]
  while (length(fragments) >= 2) {
    best <- 0
    chosen <- NULL
    for (i in seq_along(fragments)) {
      for (j in seq_along(fragments)) {
        if (i == j) next
        x <- fragments[i]
        y <- fragments[j]
        overlap <- 0
        max_width <- min(nchar(x), nchar(y)) - 1
        if (max_width > 0) {
          for (width in seq.int(max_width, 1)) {
            if (substr(x, nchar(x) - width + 1, nchar(x)) == substr(y, 1, width)) {
              overlap <- width
              break
            }
          }
        }
        if (is.null(chosen) || overlap > best) {
          best <- overlap
          chosen <- c(i, j)
        }
      }
    }
    if (best < minimum) break
    i <- chosen[1]
    j <- chosen[2]
    merged <- paste0(fragments[i], substr(fragments[j], best + 1, nchar(fragments[j])))
    next_fragments <- character()
    for (k in seq_along(fragments)) {
      if (k == i) {
        next_fragments <- c(next_fragments, merged)
      } else if (k != j && !grepl(fragments[k], merged, fixed = TRUE)) {
        next_fragments <- c(next_fragments, fragments[k])
      }
    }
    fragments <- next_fragments
  }
  longest <- fragments[which.max(nchar(fragments))]
  registration <- store(name, longest)
  emit("contigs", length(fragments))
  for (fragment in fragments) emit(nchar(fragment), fragment)
  emit(registration)
}

run_command <- function(command, a) {
  if (command == "SEQ") {
    emit(store(a[[1]], a[[2]]))
    return(invisible(NULL))
  }
  if (command == "UNPACK") {
    encoded <- a[[3]]
    count <- a[[2]]
    bytes <- strtoi(substring(encoded, seq.int(1, nchar(encoded), by = 2),
                             seq.int(2, nchar(encoded), by = 2)), base = 16L)
    codes <- integer()
    for (byte in bytes)
      codes <- c(codes, floor(byte / 64), floor(byte / 16) %% 4,
                 floor(byte / 4) %% 4, byte %% 4)
    if (any(tail(codes, length(codes) - count) != 0)) fail("invalid padding")
    emit(store(a[[1]], paste(bases[head(codes, count) + 1], collapse = "")))
    return(invisible(NULL))
  }
  if (command == "JOIN") {
    parts <- vapply(a[-1], sequence_of, character(1))
    emit(store(a[[1]], paste(parts, collapse = "")))
    return(invisible(NULL))
  }
  if (command == "ASSEMBLE") {
    sequences <- vapply(a[-c(1, 2)], sequence_of, character(1))
    assemble(a[[1]], a[[2]], sequences)
    return(invisible(NULL))
  }
  if (command == "LIST") {
    names <- sort(ls(registry))
    if (!length(names)) {
      emit("no sequences")
    } else {
      for (name in names) emit(name, nchar(sequence_of(name)), "nt")
    }
    return(invisible(NULL))
  }
  name <- a[[1]]
  sequence <- sequence_of(name)
  n <- nchar(sequence)
  if (command == "SLICE") {
    start <- a[[2]]
    end <- a[[3]]
    part <- if (start <= end) {
      substr(sequence, start, end)
    } else {
      revcomp(substr(sequence, end, start))
    }
    emit(store(a[[4]], part))
  } else if (command == "MUTATE") {
    position <- a[[2]]
    base <- a[[3]]
    old <- substr(sequence, position, position)
    if (old == base) fail("no change")
    assign(name, paste0(substr(sequence, 1, position - 1), base,
                        substr(sequence, position + 1, n)), envir = registry)
    emit(name, paste0(old, position, base),
         if (transition(old, base)) "transition" else "transversion")
  } else if (command == "DEL") {
    rm(list = name, envir = registry)
    emit("deleted", name)
  } else if (command %in% c("REVCOMP", "COMPLEMENT", "REVERSE", "TRANSCRIBE")) {
    value <- switch(
      command,
      REVCOMP = revcomp(sequence),
      COMPLEMENT = complement(sequence),
      REVERSE = reverse_text(sequence),
      TRANSCRIBE = chartr("T", "U", sequence)
    )
    emit(value)
  } else if (command %in% c("TRANSLATE", "CODONS", "PROTEIN")) {
    translation(command, name, a[[2]])
  } else if (command == "ORFS") {
    orfs(sequence, a[[2]])
  } else if (command == "GC") {
    counts <- vapply(bases, function(base) sum(chars(sequence) == base), numeric(1))
    emit(paste0(bases, "=", counts), paste0("GC=", pct(gc(sequence), n), "%"))
  } else if (command == "GCWINDOW") {
    width <- a[[2]]
    step <- a[[3]]
    if (width > n) fail("window too large")
    for (position in seq.int(1, n - width + 1, by = step))
      emit(paste0(position, "-", position + width - 1),
           paste0(pct(gc(substr(sequence, position, position + width - 1)), width), "%"))
  } else if (command == "SKEW") {
    values <- c(0, cumsum(as.integer(chars(sequence) == "G") -
                           as.integer(chars(sequence) == "C")))
    for (label in c("min", "max")) {
      extreme <- if (label == "min") min(values) else max(values)
      emit(label, extreme, "at", which(values == extreme) - 1)
    }
  } else if (command == "KMERS") {
    width <- a[[2]]
    limit <- a[[3]]
    if (width > n) fail("k too large")
    words <- substring(sequence, seq_len(n - width + 1),
                       seq_len(n - width + 1) + width - 1)
    counts <- table(words)
    emit(n - width + 1, "windows", length(counts), "distinct")
    for (word in head(frequency_order(counts), limit)) emit(word, counts[[word]])
  } else if (command == "FIND") {
    emit_list("forward", occurrences(sequence, a[[2]]))
    emit_list("reverse", occurrences(sequence, revcomp(a[[2]])))
  } else if (command == "RESTRICT") {
    restrict_sites(sequence, unlist(a[-1], use.names = FALSE))
  } else if (command == "PALINDROMES") {
    minimum <- a[[2]]
    maximum <- a[[3]]
    if (minimum > maximum) fail("invalid range")
    found <- FALSE
    for (position in seq_len(n)) {
      largest <- min(maximum, n - position + 1)
      if (minimum > largest) next
      for (width in minimum:largest) {
        part <- substr(sequence, position, position + width - 1)
        if (part == revcomp(part)) {
          emit(position, width, part)
          found <- TRUE
        }
      }
    }
    if (!found) emit("none")
  } else if (command == "REPEATS") {
    repeats(sequence, a[[2]], a[[3]], a[[4]])
  } else if (command == "HAMMING") {
    other <- sequence_of(a[[2]])
    if (nchar(other) != n) fail("length mismatch")
    mismatch <- chars(sequence) != chars(other)
    converted <- vapply(seq_len(n), function(i)
      transition(substr(sequence, i, i), substr(other, i, i)), logical(1))
    distance <- sum(mismatch)
    changes <- sum(converted)
    emit("distance", distance, "transitions", changes, "transversions", distance - changes)
  } else if (command == "ALIGN") {
    align(sequence, sequence_of(a[[2]]), a[[3]], a[[4]], a[[5]], a[[6]])
  } else if (command == "CONSENSUS") {
    consensus(vapply(a, sequence_of, character(1)))
  } else if (command == "TM") {
    emit("Tm", fixed_text(temperature(sequence), 1), if (n < 14) "wallace" else "gc")
  } else if (command == "MASS") {
    single <- strand_mass(sequence)
    emit("ss", fixed_text(single, 3),
         "ds", fixed_text(single + strand_mass(revcomp(sequence)), 3))
  } else if (command == "PRIMER") {
    primer(sequence)
  } else if (command == "FOLD") {
    fold(sequence, a[[2]])
  } else if (command == "PACK") {
    codes <- match(chars(sequence), bases) - 1
    padded <- c(codes, rep(0, (-n) %% 4))
    hex <- character()
    for (i in seq.int(1, length(padded), by = 4)) {
      byte <- 64 * padded[i] + 16 * padded[i + 1] + 4 * padded[i + 2] + padded[i + 3]
      hex <- c(hex, sprintf("%02X", byte))
    }
    emit(n, paste(hex, collapse = ""))
  }
}

lines <- readLines(file("stdin"), warn = FALSE)
count <- as.integer(lines[1])
for (i in seq_len(count)) {
  words <- strsplit(lines[i + 1], " ", fixed = TRUE)[[1]]
  command <- words[1]
  arguments <- words[-1]
  tryCatch({
    values <- validate(command, arguments)
    run_command(command, values)
  }, error = function(e) {
    reason <- conditionMessage(e)
    if (startsWith(reason, "unknown command ") ||
        startsWith(reason, "wrong argument count") ||
        startsWith(reason, "invalid number ") ||
        startsWith(reason, "unknown sequence ") ||
        startsWith(reason, "invalid name ") ||
        startsWith(reason, "invalid base ") ||
        startsWith(reason, "invalid motif ") ||
        startsWith(reason, "unknown enzyme ") ||
        startsWith(reason, "duplicate enzyme ") ||
        startsWith(reason, "invalid mode ") ||
        reason %in% c("invalid hex", "invalid padding", "too long", "no change",
                       "empty protein", "invalid range", "length mismatch",
                       "window too large", "k too large")) {
      emit("ERROR", reason)
    } else {
      stop(e)
    }
  })
}
cat(paste0(paste(output, collapse = "\n"), "\n"))
