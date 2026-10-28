for (module in c("bitio","lzw","lz77","huffman","arith_coder")) source(paste0(module,".R"))
METHODS <- c("STORE","LZW","LZ77","LZH","ARITH")
STATUSES <- c("ok","repaired","checksum","error","unsupported","truncated","bad_header")
MODULUS <- 65521
fmt <- function(pattern,...) {
  arguments <- lapply(list(...),function(value) if (is.numeric(value)) sprintf("%.0f",value) else value)
  do.call(sprintf,c(list(pattern),arguments))
}
read_inputs <- function() {
  lines <- strsplit(readLines("input/manifest.txt")," ",fixed=TRUE)
  values <- vapply(lines[seq_len(3L)],function(line) as.integer(line[2L]),integer(1))
  files <- lapply(lines[-seq_len(3L)],function(line) {
    path <- file.path("input/files",line[2L])
    list(name=line[2L],data=as.numeric(readBin(path,"raw",n=file.info(path)$size)))
  })
  hex <- paste(readLines("input/archive.hex"),collapse="")
  positions <- seq.int(1L,nchar(hex),2L)
  supplied <- as.numeric(strtoi(substring(hex,positions,positions+1L),base=16L))
  list(params=list(b=values[1L],k=values[2L],m=values[3L]),files=files,supplied=supplied)
}
ratio <- function(compressed,original) if (original == 0) "-" else sprintf(
    "%.0f",
    (1000*compressed) %/% original
)
method_name <- function(method) if (method < 5L) METHODS[method+1L] else paste0("#",method)
hexadecimal <- function(value,width) {
  digits <- strsplit("0123456789abcdef","",fixed=TRUE)[[1L]]
  result <- character(width)
  for (i in rev(seq_len(width))) {
    result[i] <- digits[value %% 16+1L]
    value <- value %/% 16
  }
  paste(result,collapse="")
}
adler32 <- function(data) {
  a <- 1
  b <- 0
  for (value in data) {
    a <- (a+value) %% MODULUS
    b <- (b+a) %% MODULUS
  }
  65536*b+a
}
modular_power <- function(value,exponent,modulus) {
  result <- 1
  while (exponent > 0) {
    if (exponent %% 2 == 1) result <- (result*value) %% modulus
    value <- (value*value) %% modulus
    exponent <- exponent %/% 2
  }
  result
}
repair_byte <- function(data,stored,computed) {
  da <- (stored %% 65536-computed %% 65536) %% MODULUS
  db <- (stored %/% 65536-computed %/% 65536) %% MODULUS
  delta <- if (1 <= da && da <= 255) da else if (MODULUS-255 <= da && da < MODULUS) da-MODULUS else 0
  if (!delta) return(NULL)
  inverse <- modular_power(delta %% MODULUS,MODULUS-2,MODULUS)
  distance <- (db*inverse) %% MODULUS
  if (distance < 1 || distance > length(data)) return(NULL)
  position <- length(data)-distance
  before <- data[position+1L]
  after <- before+delta
  if (after < 0 || after > 255) return(NULL)
  data[position+1L] <- after
  if (adler32(data) != stored) return(NULL)
  list(data=data,repair=c(position,before,after))
}
encode_lz77 <- function(tokens,b,k) {
  writer <- bit_writer()
  for (token in tokens) {
    write_bits(writer,token[1L],1L)
    if (token[1L] == 0L) write_bits(writer,token[2L],8L) else {
      write_bits(writer,token[2L]-1L,b)
      write_bits(writer,token[3L]-3L,k)
    }
  }
  finish(writer)
}
decode_lz77 <- function(payload,original,b,k) {
  reader <- bit_reader(payload)
  output <- byte_buffer()
  while (output$n < original) {
    if (read_bits(reader,1L,output$n) == 0L) append_bytes(output,read_bits(reader,8L,output$n)) else {
      distance <- read_bits(reader,b,output$n)+1L
      matched <- read_bits(reader,k,output$n)+3L
      copy_match(output,distance,matched,original)
    }
  }
  buffer_data(output)
}
fixed_lengths <- function(n) {
  width <- bits(n-1L)
  shorter <- 2^width-n
  ifelse(seq_len(n)-1L < shorter,width-1L,width)
}
write_code_table <- function(writer,lengths) {
  s <- 1L
  while (s <= length(lengths)) {
    if (lengths[s] > 0L) {
      write_bits(writer,lengths[s],4L)
      s <- s+1L
    } else {
      run <- 1L
      while (run < 256L && s+run <= length(lengths) && lengths[s+run] == 0L) run <- run+1L
      write_bits(writer,0L,4L)
      write_bits(writer,run-1L,8L)
      s <- s+run
    }
  }
}
read_code_table <- function(reader,n,position) {
  lengths <- integer()
  while (length(lengths) < n) {
    value <- read_bits(reader,4L,position)
    if (value > 0L) lengths <- c(lengths,value) else {
      run <- read_bits(reader,8L,position)+1L
      if (length(lengths)+run > n) decode_error("bad_table",position)
      lengths <- c(lengths,integer(run))
    }
  }
  positive <- lengths[lengths > 0L]
  valid <- if (length(positive) == 1L) positive[1L] == 1L else !length(positive) || sum(2^(15L-positive)) == 2^15
  if (!valid) decode_error("bad_table",position)
  lengths
}
huffman_table <- function(lengths) {
  codes <- canonical_codes(lengths)
  symbols <- new.env(hash=TRUE,parent=emptyenv())
  for (s in which(lengths > 0L)) assign(paste(lengths[s],codes[s],sep=","),s-1L,symbols)
  list(symbols=symbols,maximum=max(lengths),empty=!any(lengths > 0L))
}
read_symbol <- function(reader,table,position) {
  if (table$empty) decode_error("bad_code",position)
  code <- 0L
  for (width in seq_len(table$maximum)) {
    code <- 2L*code+read_bits(reader,1L,position)
    key <- paste(width,code,sep=",")
    if (exists(key,table$symbols,inherits=FALSE)) return(get(key,table$symbols,inherits=FALSE))
  }
  decode_error("bad_code",position)
}
write_lzh_tokens <- function(writer,tokens,p,q) {
  pc <- canonical_codes(p)
  qc <- canonical_codes(q)
  for (token in tokens) {
    if (token[1L] == 0L) write_bits(writer,pc[token[2L]+1L],p[token[2L]+1L]) else {
      symbol <- 256L+token[3L]-3L
      write_bits(writer,pc[symbol+1L],p[symbol+1L])
      offset <- token[2L]-1L
      slot <- bits(offset)
      write_bits(writer,qc[slot+1L],q[slot+1L])
      if (slot >= 2L) write_bits(writer,offset-2^(slot-1L),slot-1L)
    }
  }
}
encode_lzh <- function(tokens,params) {
  p <- numeric(256L+2^params$k)
  q <- numeric(params$b+1L)
  for (token in tokens) {
    if (token[1L] == 0L) p[token[2L]+1L] <- p[token[2L]+1L]+1L else {
      s <- 256L+token[3L]-3L+1L
      p[s] <- p[s]+1L
      slot <- bits(token[2L]-1L)+1L
      q[slot] <- q[slot]+1L
    }
  }
  lp <- limited_lengths(p,params$m)
  lq <- limited_lengths(q,params$m)
  fixed <- bit_writer()
  dynamic <- bit_writer()
  write_bits(fixed,0L,1L)
  write_lzh_tokens(fixed,tokens,fixed_lengths(length(p)),fixed_lengths(length(q)))
  fixed_bits <- fixed$count-1L
  write_bits(dynamic,1L,1L)
  write_code_table(dynamic,lp$lengths)
  write_code_table(dynamic,lq$lengths)
  table_bits <- dynamic$count-1L
  write_lzh_tokens(dynamic,tokens,lp$lengths,lq$lengths)
  code_bits <- dynamic$count-1L-table_bits
  use_fixed <- fixed_bits <= table_bits+code_bits
  list(payload=finish(if (use_fixed) fixed else dynamic),stats=list(mode=if (use_fixed) "fixed" else "dynamic",
    fixed_bits=fixed_bits,table_bits=table_bits,code_bits=code_bits,halvings=lp$halvings+lq$halvings,
    litlen_used=sum(lp$lengths > 0L),litlen_max=max(lp$lengths),offset_used=sum(lq$lengths > 0L),
    offset_max=max(lq$lengths),slots=q))
}
decode_lzh <- function(payload,original,b,k) {
  reader <- bit_reader(payload)
  if (read_bits(reader,1L) == 1L) {
    p <- read_code_table(reader,256L+2^k,0L)
    q <- read_code_table(reader,b+1L,0L)
  } else {
    p <- fixed_lengths(256L+2^k)
    q <- fixed_lengths(b+1L)
  }
  pt <- huffman_table(p)
  qt <- huffman_table(q)
  output <- byte_buffer()
  while (output$n < original) {
    symbol <- read_symbol(reader,pt,output$n)
    if (symbol < 256L) append_bytes(output,symbol) else {
      matched <- symbol-253L
      slot <- read_symbol(reader,qt,output$n)
      offset <- if (slot >= 2L) 2^(slot-1L)+read_bits(reader,slot-1L,output$n) else slot
      copy_match(output,offset+1L,matched,original)
    }
  }
  buffer_data(output)
}
decode_payload <- function(method,payload,original,b,k) {
  if (method == 0L) {
    if (length(payload) < original) decode_error("end_of_data",length(payload))
    return(payload[seq_len(original)])
  }
  if (method == 1L) return(decode_lzw(payload,original))
  if (method == 2L) return(decode_lz77(payload,original,b,k))
  if (method == 3L) return(decode_lzh(payload,original,b,k))
  decode_arith(payload,original)
}
encode_file <- function(name,data,params) {
  tokens <- tokenize(data,params$b,params$k)
  zw <- encode_lzw(data)
  zh <- encode_lzh(tokens,params)
  arithmetic <- encode_arith(data)
  payloads <- list(data,zw$payload,encode_lz77(tokens,params$b,params$k),zh$payload,arithmetic$payload)
  best <- which.min(lengths(payloads))
  matches <- Filter(function(t) t[1L] == 1L,tokens)
  matched <- vapply(matches,`[`,numeric(1),3L)
  distances <- vapply(matches,`[`,numeric(1),2L)
  z_stats <- list(tokens=length(tokens),literals=length(tokens)-length(matches),matches=length(matches),
    matched=sum(matched),longest=if (length(matches)) max(matched) else 0L,
    farthest=if (length(matches)) max(distances) else 0L)
  list(
      name=name,
      data=data,
      payloads=payloads,
      best=best,
      payload=payloads[[best]],
      lzw=zw$stats,
      lz77=z_stats,
      lzh=zh$stats,
      arith=arithmetic$stats
  )
}
big_endian <- function(value,n) (value %/% (256^(rev(seq_len(n)-1L)))) %% 256
build_archive <- function(encodings,params) {
  archive <- byte_buffer()
  append_bytes(archive,c(as.numeric(charToRaw("TXAR")),params$b,params$k,big_endian(length(encodings),2L)))
  for (encoding in encodings) {
    name <- as.numeric(charToRaw(encoding$name))
    header <- c(length(name),name,encoding$best-1L,big_endian(length(encoding$data),4L),
      big_endian(length(encoding$payload),4L),big_endian(adler32(encoding$data),4L))
    append_bytes(archive,c(header,sum(header) %% 256,encoding$payload))
  }
  buffer_data(archive)
}
read_big_endian <- function(bytes,start,n) {
  result <- 0
  for (i in seq.int(start,start+n-1L)) result <- 256*result+bytes[i]
  result
}
parse_archive <- function(archive) {
  n <- length(archive)
  result <- list(size=n,b=0L,k=0L,declared=0L,entries=list(),error=NULL,stopped=FALSE,trailing=0L)
  if (n < 8L || !identical(archive[seq_len(4L)],as.numeric(charToRaw("TXAR")))) {
    result$error <- "bad_magic"
    return(result)
  }
  result$b <- archive[5L]
  result$k <- archive[6L]
  if (!(6 <= result$b && result$b <= 12 && 2 <= result$k && result$k <= 5)) {
    result$error <- "bad_params"
    return(result)
  }
  result$declared <- read_big_endian(archive,7L,2L)
  position <- 8L
  for (number in seq_len(result$declared)) {
    entry <- list(number=number,offset=position,status="",valid=FALSE,name="",method=0L,original=0,
      compressed=0,checksum=0,start=0,stop=0,data=NULL,error=NULL,repair=NULL,computed=0)
    if (position >= n || position+15L+archive[position+1L] > n) {
      entry$status <- "truncated"
      result$entries[[length(result$entries)+1L]] <- entry
      result$stopped <- TRUE
      break
    }
    m <- archive[position+1L]
    name <- if (m) archive[seq.int(position+2L,position+1L+m)] else numeric()
    cursor <- position+1L+m
    entry$method <- archive[cursor+1L]
    entry$original <- read_big_endian(archive,cursor+2L,4L)
    entry$compressed <- read_big_endian(archive,cursor+6L,4L)
    entry$checksum <- read_big_endian(archive,cursor+10L,4L)
    entry$start <- position+15L+m
    entry$stop <- entry$start+entry$compressed
    valid_name <- m >= 1L && m <= 32L && all(name %in% as.numeric(charToRaw("abcdefghijklmnopqrstuvwxyz0123456789._-")))
    valid_check <- sum(archive[seq.int(position+1L,entry$start-1L)]) %% 256 == archive[entry$start]
    entry$valid <- valid_name && valid_check
    if (!entry$valid) {
      entry$status <- "bad_header"
      position <- entry$stop
      result$entries[[length(result$entries)+1L]] <- entry
      if (position > n) {
        result$stopped <- TRUE
        break
      }
      next
    }
    entry$name <- rawToChar(as.raw(name))
    if (entry$stop > n) {
      entry$status <- "truncated"
      result$entries[[length(result$entries)+1L]] <- entry
      result$stopped <- TRUE
      break
    }
    if (entry$method >= 5L) entry$status <- "unsupported" else {
      payload <- if (entry$compressed) archive[seq.int(entry$start+1L,entry$stop)] else numeric()
      decoded <- tryCatch(list(data=decode_payload(entry$method,payload,entry$original,result$b,result$k)),
        decode_error=function(error) list(error=error))
      if (!is.null(decoded$error)) {
        entry$status <- "error"
        entry$error <- decoded$error
      } else {
        entry$data <- decoded$data
        entry$computed <- adler32(entry$data)
        if (entry$computed == entry$checksum) entry$status <- "ok" else {
          repair <- repair_byte(entry$data,entry$checksum,entry$computed)
          if (is.null(repair)) entry$status <- "checksum" else {
            entry$data <- repair$data
            entry$repair <- repair$repair
            entry$status <- "repaired"
          }
        }
      }
    }
    result$entries[[length(result$entries)+1L]] <- entry
    position <- entry$stop
  }
  if (!result$stopped) result$trailing <- n-position
  result
}
intact <- function(parsed) Filter(function(e) e$status %in% c("ok","repaired"),parsed$entries)
verify_archive <- function(archive,originals) {
  parsed <- parse_archive(archive)
  verified <- sum(vapply(seq_along(parsed$entries),function(i) parsed$entries[[i]]$status == "ok" &&
    identical(parsed$entries[[i]]$data,originals[[i]]),logical(1)))
  c(length(parsed$entries),verified)
}
sizes_report <- function(encodings,params,archive,examined,verified) {
  lines <- fmt(
      "params offset_bits %s length_bits %s window %s lookahead %s max_code_length %s",
      params$b,
      params$k,
      2^params$b,
      2^params$k+2L,
      params$m
  )
  totals <- chosen <- numeric(5L)
  original_total <- best_total <- 0
  for (e in encodings) {
    original <- length(e$data)
    original_total <- original_total+original
    chosen[e$best] <- chosen[e$best]+1L
    best_total <- best_total+length(e$payload)
    fields <- fmt("file %s original %s",e$name,original)
    for (k in seq_len(5L)) {
      compressed <- length(e$payloads[[k]])
      totals[k] <- totals[k]+compressed
      fields <- c(fields,fmt("%s %s %s",METHODS[k],compressed,ratio(compressed,original)))
    }
    lines <- c(lines,paste(c(fields,paste("best",METHODS[e$best])),collapse=" "))
  }
  fields <- c(fmt("total original %s",original_total),vapply(seq_len(5L),function(k)
    fmt(
        "%s %s %s",
        METHODS[k],
        totals[k],
        ratio(totals[k],original_total)
    ),character(1)),fmt("best %s %s",best_total,ratio(best_total,original_total)))
  c(lines,paste(fields,collapse=" "),paste("chosen",paste(paste(METHODS,chosen),collapse=" ")),
    fmt(
        "archive bytes %s entries %s ratio %s",
        length(archive),
        length(encodings),
        ratio(length(archive),original_total)
    ),
    fmt("verify entries %s ok %s",examined,verified))
}
analysis_report <- function(encodings) {
  lines <- character()
  for (e in encodings) {
    zw <- e$lzw
    z <- e$lz77
    zh <- e$lzh
    ar <- e$arith
    lines <- c(lines,fmt("lzw %s codes %s clears %s widths %s longest %s",e$name,zw$codes,zw$clears,paste(zw$widths,collapse=" "),zw$longest),
      fmt(
          "lz77 %s tokens %s literals %s matches %s matched %s longest %s farthest %s",
          e$name,
          z$tokens,
          z$literals,
          z$matches,
          z$matched,
          z$longest,
          z$farthest
      ),
      fmt("lzh %s mode %s fixed_bits %s table_bits %s code_bits %s halvings %s litlen_used %s litlen_max %s offset_used %s offset_max %s",
        e$name,zh$mode,zh$fixed_bits,zh$table_bits,zh$code_bits,zh$halvings,zh$litlen_used,zh$litlen_max,zh$offset_used,zh$offset_max),
      paste("slots",e$name,paste(zh$slots,collapse=" ")),fmt(
          "arith %s bits %s contexts %s rescales %s",
          e$name,
          ar$bits,
          ar$contexts,
          ar$rescales
      ))
  }
  lines
}
listing_report <- function(parsed) {
  if (!is.null(parsed$error)) return(fmt("archive bytes %s error %s",parsed$size,parsed$error))
  lines <- fmt(
      "archive bytes %s offset_bits %s length_bits %s entries %s",
      parsed$size,
      parsed$b,
      parsed$k,
      parsed$declared
  )
  totals <- matrix(0,5L,3L)
  listed <- 0L
  for (e in parsed$entries) {
    prefix <- fmt("entry %s offset %s",e$number,e$offset)
    if (!e$valid) {
      lines <- c(lines,paste(prefix,if (e$status == "bad_header") "bad_header" else "truncated header"))
      next
    }
    listed <- listed+1L
    lines <- c(lines,fmt("%s method %s original %s compressed %s ratio %s adler %s name %s",prefix,method_name(e$method),
      e$original,e$compressed,ratio(e$compressed,e$original),hexadecimal(e$checksum,8L),e$name))
    if (e$method < 5L) totals[e$method+1L,] <- totals[e$method+1L,]+c(1L,e$original,e$compressed)
  }
  for (k in seq_len(5L)) lines <- c(lines,fmt("method %s entries %s original %s compressed %s ratio %s",
    METHODS[k],totals[k,1L],totals[k,2L],totals[k,3L],ratio(totals[k,3L],totals[k,2L])))
  c(
      lines,
      fmt(
          "end listed %s of %s stop %s trailing %s",
          listed,
          parsed$declared,
          if (parsed$stopped) "truncated" else "complete",
          parsed$trailing
      )
  )
}
entry_test_line <- function(e,archive_size) {
  prefix <- fmt("entry %s offset %s",e$number,e$offset)
  if (!e$valid) return(paste(
      prefix,
      "status",
      if (e$status == "bad_header") "bad_header" else "truncated header"
  ))
  line <- fmt("%s name %s method %s status %s",prefix,e$name,method_name(e$method),e$status)
  if (e$status == "repaired") line <- paste(
      line,
      fmt("byte %s from %s to %s",e$repair[1L],e$repair[2L],e$repair[3L])
  )
  else if (e$status == "checksum") line <- paste(
      line,
      fmt("stored %s computed %s",hexadecimal(e$checksum,8L),hexadecimal(e$computed,8L))
  )
  else if (e$status == "error") line <- paste(line,fmt("%s at %s",e$error$kind,e$error$position))
  else if (e$status == "truncated") line <- paste(
      line,
      fmt("payload have %s need %s",archive_size-e$start,e$compressed)
  )
  line
}
test_report <- function(parsed,salvaged,archive,verified) {
  if (!is.null(parsed$error)) lines <- paste("archive error",parsed$error) else {
    lines <- vapply(parsed$entries,entry_test_line,character(1),archive_size=parsed$size)
    counts <- vapply(
        STATUSES,
        function(status) sum(vapply(parsed$entries,function(e) e$status == status,logical(1))),
        numeric(1)
    )
    summary <- fmt("summary entries %s checked %s",parsed$declared,length(parsed$entries))
    summary <- paste(
        summary,
        paste(paste(STATUSES,counts),collapse=" "),
        fmt("missing %s trailing %s",parsed$declared-length(parsed$entries),parsed$trailing)
    )
    lines <- c(lines,summary)
  }
  entries <- intact(parsed)
  for (i in seq_along(entries)) {
    e <- entries[[i]]
    encoding <- salvaged[[i]]
    lines <- c(
        lines,
        fmt(
            "salvage %s method %s compressed %s was %s %s",
            e$name,
            METHODS[encoding$best],
            length(encoding$payload),
            method_name(e$method),
            e$compressed
        )
    )
  }
  total <- sum(vapply(salvaged,function(e) length(e$data),numeric(1)))
  c(
      lines,
      fmt(
          "salvaged entries %s bytes %s original %s verified %s",
          length(salvaged),
          length(archive),
          total,
          verified
      )
  )
}
text_lines <- function(data) {
  if (!length(data)) return(character())
  text <- rawToChar(as.raw(data))
  starts <- c(1L,which(data == 10L)+1L)
  ends <- which(data == 10L)-1L
  vapply(
      seq_along(ends),
      function(i) if (ends[i] < starts[i]) "" else substr(text,starts[i],ends[i]),
      character(1)
  )
}
extraction_report <- function(entries) {
  lines <- character()
  for (e in entries) {
    contents <- text_lines(e$data)
    words <- sum(vapply(strsplit(contents," ",fixed=TRUE),function(parts) sum(nzchar(parts)),numeric(1)))
    longest <- if (length(contents)) max(nchar(contents,type="bytes")) else 0L
    lines <- c(
        lines,
        fmt(
            "file %s bytes %s lines %s words %s longest %s",
            e$name,
            length(e$data),
            length(contents),
            words,
            longest
        ),
        contents
    )
  }
  lines
}
edit_list <- function(old,new) {
  a <- length(old)
  b <- length(new)
  below <- current <- integer(b+1L)
  deletions <- vector("list",a)
  for (i in rev(seq_len(a))) {
    decisions <- raw((b+7L) %/% 8L)
    right <- 0L
    for (j in rev(seq_len(b))) {
      if (old[i] == new[j]) value <- below[j+1L]+1L else if (below[j] >= right) {
        value <- below[j]
        byte <- (j-1L) %/% 8L+1L
        decisions[byte] <- as.raw(bitwOr(as.integer(decisions[byte]),bitwShiftL(1L,(j-1L) %% 8L)))
      } else value <- right
      current[j] <- value
      right <- value
    }
    deletions[[i]] <- decisions
    temporary <- below
    below <- current
    current <- temporary
  }
  edits <- list()
  i <- j <- 1L
  while (i <= a || j <= b) {
    if (i <= a && j <= b && old[i] == new[j]) {
      i <- i+1L
      j <- j+1L
    } else if (j > b || (i <= a && bitwAnd(
        as.integer(deletions[[i]][(j-1L) %/% 8L+1L]),
        bitwShiftL(1L,(j-1L) %% 8L)
    ) != 0L)) {
      edits[[length(edits)+1L]] <- list(sign="-",number=i,text=old[i])
      i <- i+1L
    } else {
      edits[[length(edits)+1L]] <- list(sign="+",number=j,text=new[j])
      j <- j+1L
    }
  }
  edits
}
comparison_report <- function(entries,files) {
  manifest <- setNames(lapply(files,`[[`,"data"),vapply(files,`[[`,character(1),"name"))
  seen <- character()
  lines <- character()
  for (e in entries) {
    seen <- c(seen,e$name)
    if (!(e$name %in% names(manifest))) {
      lines <- c(lines,paste("archive_only",e$name))
      next
    }
    old <- text_lines(e$data)
    new <- text_lines(manifest[[e$name]])
    if (identical(old,new)) {
      lines <- c(lines,fmt("same %s lines %s",e$name,length(old)))
      next
    }
    first_difference <- 1L
    while (first_difference <= min(
        length(old),
        length(new)
    ) && old[first_difference] == new[first_difference]) first_difference <- first_difference+1L
    edits <- edit_list(old,new)
    removed <- sum(vapply(edits,function(edit) edit$sign == "-",logical(1)))
    lines <- c(lines,fmt("differs %s first_line %s archive_lines %s manifest_lines %s removed %s added %s",e$name,first_difference,
      length(old),length(new),removed,length(edits)-removed),vapply(
          edits,
          function(edit) paste0(edit$sign,edit$number,":",edit$text),
          character(1)
      ))
  }
  for (file in files) if (!(file$name %in% seen)) lines <- c(lines,paste("new",file$name))
  lines
}
write_lines <- function(name,lines) writeLines(lines,file.path("output",name),useBytes=TRUE)
write_hex <- function(name,archive) {
  lines <- vapply(
      seq.int(1L,length(archive),32L),
      function(i) paste(
          sprintf("%02x",as.integer(archive[seq.int(i,min(i+31L,length(archive)))])),
          collapse=""
      ),
      character(1)
  )
  write_lines(name,lines)
}
main <- function() {
  inputs <- read_inputs()
  params <- inputs$params
  files <- inputs$files
  encodings <- lapply(files,function(file) encode_file(file$name,file$data,params))
  created <- build_archive(encodings,params)
  verification <- verify_archive(created,lapply(files,`[[`,"data"))
  parsed <- parse_archive(inputs$supplied)
  salvage_params <- if (is.null(parsed$error)) list(b=parsed$b,k=parsed$k,m=params$m) else params
  entries <- intact(parsed)
  salvaged <- lapply(entries,function(e) encode_file(e$name,e$data,salvage_params))
  archive <- build_archive(salvaged,salvage_params)
  salvage_verified <- verify_archive(archive,lapply(salvaged,`[[`,"data"))[2L]
  dir.create("output",showWarnings=FALSE)
  write_lines("sizes.txt",sizes_report(encodings,params,created,verification[1L],verification[2L]))
  write_lines("analysis.txt",analysis_report(encodings))
  write_hex("archive.hex",created)
  write_lines("listing.txt",listing_report(parsed))
  write_lines("test_report.txt",test_report(parsed,salvaged,archive,salvage_verified))
  write_lines("extracted.txt",extraction_report(entries))
  write_lines("compare.txt",comparison_report(entries,files))
  write_hex("salvaged.hex",archive)
}
main()
