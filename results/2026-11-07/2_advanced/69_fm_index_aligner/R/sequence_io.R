COMPLEMENT <- setNames(strsplit("TGCAN","",fixed=TRUE)[[1L]],strsplit("ACGTN","",fixed=TRUE)[[1L]])
reverse_complement <- function(sequence) unname(COMPLEMENT[rev(sequence)])
read_inputs <- function() {
  references <- list()
  name <- ""
  parts <- character()
  masked <- 0L
  for (line in readLines("input/reference.fasta")) {
    if (startsWith(line,">")) {
      if (name != "") references[[length(references)+1L]] <- list(name=name,bases=parts,masked=masked)
      name <- strsplit(substring(line,2L)," ",fixed=TRUE)[[1L]][1L]
      parts <- character()
      masked <- 0L
    } else {
      characters <- strsplit(line,"",fixed=TRUE)[[1L]]
      masked <- masked+sum(characters %in% c("a","c","g","t"))
      parts <- c(parts,toupper(characters))
    }
  }
  references[[length(references)+1L]] <- list(name=name,bases=parts,masked=masked)
  lines <- readLines("input/reads.fastq")
  reads <- lapply(
      seq.int(1L,length(lines),4L),
      function(i) list(
          name=substring(lines[i],2L),
          bases=strsplit(lines[i+1L],"",fixed=TRUE)[[1L]],
          quality=strsplit(lines[i+3L],"",fixed=TRUE)[[1L]]
      )
  )
  params <- list()
  for (line in readLines("input/params.txt")) {
    fields <- strsplit(line," ",fixed=TRUE)[[1L]]
    params[[fields[1L]]] <- as.integer(fields[-1L])
  }
  list(references=references,reads=reads,params=params)
}
