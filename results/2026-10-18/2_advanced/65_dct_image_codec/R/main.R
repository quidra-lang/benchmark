source("entropy.R")
source("image_io.R")
source("color.R")
source("dct.R")
source("bitstream.R")

COMPONENT_NAMES <- c("Y","Cb","Cr")
words <- function(...) paste(...,collapse=" ")
standard_components <- function(h,v) {
  list(
      list(identifier=1L,h=as.integer(h),v=as.integer(v),tq=0L,td=0L,ta=0L),
      list(identifier=2L,h=1L,v=1L,tq=1L,td=1L,ta=1L),
      list(identifier=3L,h=1L,v=1L,tq=1L,td=1L,ta=1L)
  )
}
make_layout <- function(width,height,components,restart_interval) {
  factors <- lapply(components,function(c) as.integer(c(c$h,c$v)))
  hmax <- max(vapply(components,function(c) c$h,integer(1)))
  vmax <- max(vapply(components,function(c) c$v,integer(1)))
  mx <- (width+8L*hmax-1L) %/% (8L*hmax)
  my <- (height+8L*vmax-1L) %/% (8L*vmax)
  mcus <- mx*my
  blocks <- list()
  for (mcu in 0:(mcus-1L)) for (k in seq_along(components)) {
    component <- components[[k]]
    for (v in 0:(component$v-1L)) for (h in 0:(component$h-1L)) blocks[[length(blocks)+1L]] <- list(
        mcu=mcu,
        component=k,
        bx=component$h*(mcu %% mx)+h,
        by=component$v*(mcu %/% mx)+v
    )
  }
  step <- if (restart_interval == 0L) mcus else restart_interval
  intervals <- lapply(seq.int(0L,mcus-1L,step),function(first) c(first,min(step,mcus-first)))
  list(
      width=width,
      height=height,
      components=components,
      restart_interval=restart_interval,
      factors=factors,
      hmax=hmax,
      vmax=vmax,
      mx=mx,
      my=my,
      mcus=mcus,
      blocks_per_mcu=sum(vapply(components,function(c) c$h*c$v,integer(1))),
      blocks=blocks,
      intervals=intervals
  )
}
interval_blocks <- function(layout,interval) {
  first <- layout$intervals[[interval]][1L]
  n <- layout$intervals[[interval]][2L]
  seq.int(first*layout$blocks_per_mcu+1L,(first+n)*layout$blocks_per_mcu)
}
word <- function(value) c(value %/% 256L,value %% 256L)
read_word <- function(data,offset) 256L*data[offset+1L]+data[offset+2L]
segment <- function(marker,contents) c(255L,marker,word(length(contents)+2L),contents)
read_symbol <- function(reader,table) {
  code <- 0L
  for (code_length in seq_len(16L)) {
    code <- 2L*code+read_bit(reader)
    key <- table_key(code_length,code)
    if (exists(key,table$decode,inherits=FALSE)) return(get(key,table$decode,inherits=FALSE))
  }
  codec_error("code")
}
decode_block <- function(reader,k,component,tables,predictors) {
  coefficients <- numeric(64L)
  n <- read_symbol(reader,tables[[table_key(0L,component$td)]])
  predictors$values[k] <- predictors$values[k]+amplitude(read_bits(reader,n),n)
  coefficients[1L] <- predictors$values[k]
  index <- 1L
  while (index <= 63L) {
    symbol <- read_symbol(reader,tables[[table_key(1L,component$ta)]])
    if (symbol == 0L) break
    run <- symbol %/% 16L
    n <- symbol %% 16L
    index <- index+run
    if (index > 63L) codec_error("index")
    if (n > 0L) coefficients[index+1L] <- amplitude(read_bits(reader,n),n)
    index <- index+1L
  }
  coefficients
}
prepare <- function(codec,image,quality,sampling,restart_interval) {
  h <- if (sampling == "444") 1L else 2L
  v <- if (sampling == "420") 2L else 1L
  layout <- make_layout(dim(image)[2L],dim(image)[1L],standard_components(h,v),restart_interval)
  planes <- component_planes(split_planes(image),layout$factors,layout$mx,layout$my)
  quantization <- quantization_tables(codec$basic,quality)
  coefficients <- lapply(layout$blocks,function(block) {
    pixels <- planes[[block$component]][
        seq.int(8L*block$by+1L,8L*block$by+8L),
        seq.int(8L*block$bx+1L,8L*block$bx+8L),
        drop=FALSE
    ]
    transformed <- forward_dct(pixels,codec$transform)
    zigzag(quantize(transformed,quantization[[as.character(layout$components[[block$component]]$tq)]]))
  })
  list(layout=layout,planes=planes,quantization=quantization,coefficients=coefficients)
}
build_symbols <- function(prepared) {
  layout <- prepared$layout
  frequencies <- setNames(
      lapply(TABLE_KEYS,function(unused) integer(256L)),
      vapply(TABLE_KEYS,function(key) table_key(key[1L],key[2L]),character(1))
  )
  blocks <- list()
  differences <- numeric()
  for (interval in seq_along(layout$intervals)) {
    predictors <- numeric(3L)
    for (number in interval_blocks(layout,interval)) {
      block <- layout$blocks[[number]]
      component <- layout$components[[block$component]]
      sequence <- prepared$coefficients[[number]]
      difference <- sequence[1L]-predictors[block$component]
      predictors[block$component] <- sequence[1L]
      differences <- c(differences,difference)
      extra <- extra_bits(difference)
      symbols <- list(list(table=table_key(0L,component$td),value=extra[2L],extra=extra[1L],width=extra[2L]))
      ac_table <- table_key(1L,component$ta)
      run <- 0L
      for (value in sequence[-1L]) {
        if (value == 0) {
          run <- run+1L
          next
        }
        while (run >= 16L) {
          symbols[[length(symbols)+1L]] <- list(table=ac_table,value=240L,extra=0L,width=0L)
          run <- run-16L
        }
        extra <- extra_bits(value)
        symbols[[length(symbols)+1L]] <- list(
            table=ac_table,
            value=16L*run+extra[2L],
            extra=extra[1L],
            width=extra[2L]
        )
        run <- 0L
      }
      if (run > 0L) symbols[[length(symbols)+1L]] <- list(table=ac_table,value=0L,extra=0L,width=0L)
      for (symbol in symbols) frequencies[[symbol$table]][symbol$value+1L] <- frequencies[[symbol$table]][symbol$value+1L]+1L
      blocks[[length(blocks)+1L]] <- symbols
    }
  }
  list(blocks=blocks,differences=differences,frequencies=frequencies)
}
header_bytes <- function(layout,quantization,tables) {
  header <- c(255L,216L)
  contents <- integer()
  for (id in 0:1) contents <- c(contents,id,zigzag(quantization[[as.character(id)]]))
  header <- c(header,segment(219L,contents))
  contents <- c(8L,word(layout$height),word(layout$width),3L)
  for (component in layout$components) contents <- c(
      contents,
      component$identifier,
      16L*component$h+component$v,
      component$tq
  )
  header <- c(header,segment(192L,contents))
  contents <- integer()
  for (key in TABLE_KEYS) {
    table <- tables[[table_key(key[1L],key[2L])]]
    contents <- c(contents,16L*key[1L]+key[2L],table$counts,table$symbols)
  }
  header <- c(header,segment(196L,contents))
  if (layout$restart_interval > 0L) header <- c(header,segment(221L,word(layout$restart_interval)))
  contents <- 3L
  for (component in layout$components) contents <- c(
      contents,
      component$identifier,
      16L*component$td+component$ta
  )
  c(header,segment(218L,c(contents,0L,63L,0L)))
}
encode_prepared <- function(codec,prepared,mode) {
  symbols <- build_symbols(prepared)
  tables <- if (mode == "standard") codec$standard else lapply(symbols$frequencies,optimized_table)
  header <- header_bytes(prepared$layout,prepared$quantization,tables)
  writer <- new_bit_writer()
  block_bits <- integer(length(prepared$coefficients))
  intervals <- list()
  for (interval in seq_along(prepared$layout$intervals)) {
    bounds <- prepared$layout$intervals[[interval]]
    if (interval > 1L) restart(writer,interval-2L)
    start <- length(writer$data)
    for (number in interval_blocks(prepared$layout,interval)) for (symbol in symbols$blocks[[number]]) {
      code <- tables[[symbol$table]]$codes[[as.character(symbol$value)]]
      write_bits(writer,code[2L],code[1L])
      write_bits(writer,symbol$extra,symbol$width)
      block_bits[number] <- block_bits[number]+code[1L]+symbol$width
    }
    pad_bits(writer)
    intervals[[interval]] <- c(bounds,length(header)+start,length(writer$data)-start)
  }
  c(
      prepared,
      list(
          tables=tables,
          frequencies=symbols$frequencies,
          differences=symbols$differences,
          block_bits=block_bits,
          intervals=intervals,
          data=as.integer(c(header,writer$data,255L,217L)),
          header_bytes=length(header),
          scan_bytes=length(writer$data),
          padding_bits=writer$padding_bits,
          stuffed_bytes=writer$stuffed_bytes
      )
  )
}
encode <- function(codec,image,q,sampling,mode,restart) encode_prepared(
    codec,
    prepare(codec,image,q,sampling,restart),
    mode
)
parse_header <- function(data) {
  position <- 2L
  segments <- list(list(0L,"SOI",0L))
  quantization <- tables <- list()
  restart_interval <- width <- height <- 0L
  components <- list()
  names <- c("192"="SOF0","196"="DHT","219"="DQT","221"="DRI","218"="SOS","254"="COM")
  repeat {
    marker <- data[position+2L]
    segment_length <- read_word(data,position+2L)
    contents <- if (segment_length > 2L) data[seq.int(position+5L,position+segment_length+2L)] else integer()
    name <- if (marker >= 224L && marker <= 239L) paste0("APP",marker-224L) else names[[as.character(marker)]]
    segments[[length(segments)+1L]] <- list(position,name,segment_length)
    position <- position+segment_length+2L
    if (marker == 219L) {
      for (offset in seq.int(
          0L,
          length(contents)-1L,
          65L
      )) quantization[[as.character(contents[offset+1L])]] <- unzigzag(contents[seq.int(
          offset+2L,
          offset+65L
      )])
    } else if (marker == 196L) {
      offset <- 0L
      while (offset < length(contents)) {
        class <- contents[offset+1L] %/% 16L
        id <- contents[offset+1L] %% 16L
        counts <- contents[seq.int(offset+2L,offset+17L)]
        n <- sum(counts)
        symbols <- if (n) contents[seq.int(offset+18L,offset+17L+n)] else integer()
        tables[[table_key(class,id)]] <- new_huffman(counts,symbols)
        offset <- offset+17L+n
      }
    } else if (marker == 192L) {
      height <- read_word(contents,1L)
      width <- read_word(contents,3L)
      for (index in 0:2) {
        offset <- 6L+3L*index
        components[[index+1L]] <- list(
            identifier=contents[offset+1L],
            h=as.integer(contents[offset+2L] %/% 16L),
            v=as.integer(contents[offset+2L] %% 16L),
            tq=contents[offset+3L],
            td=0L,
            ta=0L
        )
      }
    } else if (marker == 221L) restart_interval <- read_word(contents,0L) else if (marker == 218L) {
      for (index in 1:3) {
        components[[index]]$td <- contents[2L*index+1L] %/% 16L
        components[[index]]$ta <- contents[2L*index+1L] %% 16L
      }
      break
    }
  }
  segments[[length(segments)+1L]] <- list(length(data)-2L,"EOI",0L)
  list(
      layout=make_layout(width,height,components,restart_interval),
      quantization=quantization,
      tables=tables,
      segments=segments,
      scan_start=position,
      scan_bytes=length(data)-2L-position
  )
}
decode_intervals <- function(data,parsed) {
  layout <- parsed$layout
  coefficients <- lapply(layout$blocks,function(unused) numeric(64L))
  states <- lapply(layout$intervals,function(unused) list(state="lost"))
  reader <- new_bit_reader(data,parsed$scan_start)
  interval <- 1L
  while (interval <= length(layout$intervals)) {
    predictors <- list2env(list(values=numeric(3L)),parent=emptyenv())
    pending <- list()
    current_mcu <- layout$intervals[[interval]][1L]
    failure <- tryCatch({
      for (number in interval_blocks(layout,interval)) {
        block <- layout$blocks[[number]]
        current_mcu <- block$mcu
        pending[[length(pending)+1L]] <- decode_block(
            reader,
            block$component,
            layout$components[[block$component]],
            parsed$tables,
            predictors
        )
      }
      discard_bits(reader)
      expected <- if (interval < length(layout$intervals)) 208L+(interval-1L) %% 8L else 217L
      if (data[reader$position+1L] != 255L || data[reader$position+2L] != expected) codec_error("sync")
      NULL
    },jpeg_decode_error=function(error) error)
    if (is.null(failure)) {
      numbers <- interval_blocks(layout,interval)
      for (i in seq_along(numbers)) coefficients[[numbers[i]]] <- pending[[i]]
      states[[interval]] <- list(state="ok")
      reader$position <- reader$position+2L
      interval <- interval+1L
    } else {
      offset <- reader$position
      discard_bits(reader)
      resync <- find_resync(data,offset)
      states[[interval]] <- list(
          state="damaged",
          kind=failure$kind,
          mcu=current_mcu,
          offset=offset,
          resync=resync
      )
      marker <- data[resync+2L]
      if (marker == 217L) break
      interval <- interval+1L+(marker-208L-(interval-1L)) %% 8L
      reader$position <- resync+2L
    }
  }
  list(coefficients=coefficients,states=states)
}
reconstruct_component <- function(codec,layout,k,coefficients,quantization,keep=64L) {
  component <- layout$components[[k]]
  plane <- matrix(128,8L*component$v*layout$my,8L*component$h*layout$mx)
  for (number in seq_along(layout$blocks)) {
    block <- layout$blocks[[number]]
    if (block$component != k) next
    pixels <- inverse_dct(
        dequantize(coefficients[[number]],quantization[[as.character(component$tq)]],keep),
        codec$transform
    )
    plane[seq.int(8L*block$by+1L,8L*block$by+8L),seq.int(8L*block$bx+1L,8L*block$bx+8L)] <- pixels
  }
  plane
}
decode <- function(codec,data) {
  parsed <- parse_header(data)
  result <- decode_intervals(data,parsed)
  planes <- lapply(
      1:3,
      function(k) reconstruct_component(codec,parsed$layout,k,result$coefficients,parsed$quantization)
  )
  expanded <- upsample(planes,parsed$layout$factors,parsed$layout$width,parsed$layout$height)
  c(parsed,result,list(planes=planes,expanded=expanded,image=combine_rgb(expanded)))
}
repair <- function(codec,decoded) {
  source <- decoded$layout
  first <- source$components[[1L]]
  layout <- make_layout(
      source$width,
      source$height,
      standard_components(first$h,first$v),
      source$restart_interval
  )
  quantization <- list(
      "0"=decoded$quantization[[as.character(first$tq)]],
      "1"=decoded$quantization[[as.character(source$components[[2L]]$tq)]]
  )
  encode_prepared(
      codec,
      list(layout=layout,planes=NULL,quantization=quantization,coefficients=decoded$coefficients),
      "optimized"
  )
}
plane_values <- function(plane) as.vector(t(plane))
image_values <- function(image) unlist(
    lapply(
        seq_len(dim(image)[1L]),
        function(y) unlist(lapply(seq_len(dim(image)[2L]),function(x) image[y,x,]),use.names=FALSE)
    ),
    use.names=FALSE
)
psnr_from_error <- function(error,n) if (error == 0) "inf" else sprintf(
    "%.2f",
    10*log10(65025*as.numeric(n)/error)
)
psnr <- function(first,second) {
  differences <- first-second
  psnr_from_error(sum(differences*differences),length(first))
}
image_psnr <- function(a,b) psnr(image_values(a),image_values(b))
quality_metrics <- function(original,original_planes,decoded) {
  metrics <- vapply(
      1:3,
      function(k) psnr(plane_values(original_planes[[k]]),plane_values(decoded$expanded[[k]])),
      character(1)
  )
  differences <- abs(image_values(original)-image_values(decoded$image))
  list(
      metrics=c(metrics,psnr_from_error(sum(differences*differences),length(differences))),
      maximum=max(differences)
  )
}
integer_gcd <- function(a,b) {
  while (b != 0L) {
    remainder <- a %% b
    a <- b
    b <- remainder
  }
  a
}
bits_per_pixel <- function(n,width,height) {
  numerator <- 8L*n
  denominator <- width*height
  divisor <- integer_gcd(numerator,denominator)
  paste0(numerator %/% divisor,"/",denominator %/% divisor)
}
block_statistics <- function(encoded,decoded) {
  lines <- words("blocks",length(encoded$layout$blocks))
  errors <- numeric()
  for (number in seq_along(encoded$layout$blocks)) {
    block <- encoded$layout$blocks[[number]]
    sequence <- encoded$coefficients[[number]]
    original <- encoded$planes[[block$component]]
    restored <- decoded$planes[[block$component]]
    error <- 0
    for (y in seq.int(8L*block$by+1L,8L*block$by+8L)) for (x in seq.int(8L*block$bx+1L,8L*block$bx+8L)) {
      difference <- original[y,x]-restored[y,x]
      error <- error+difference*difference
    }
    errors <- c(errors,error)
    indices <- which(sequence != 0)
    last <- if (length(indices)) tail(indices,1L)-1L else 0L
    lines <- c(
        lines,
        words(
            "block",
            number-1L,
            COMPONENT_NAMES[block$component],
            block$bx,
            block$by,
            "dc",
            sequence[1L],
            "diff",
            encoded$differences[number],
            "nonzero",
            sum(sequence[-1L] != 0),
            "last",
            last,
            "bits",
            encoded$block_bits[number],
            "sse",
            sprintf("%.0f",error)
        )
    )
  }
  list(lines=lines,errors=errors)
}
huffman_lines <- function(encoded) {
  lines <- character()
  for (i in seq_along(TABLE_KEYS)) {
    key <- TABLE_KEYS[[i]]
    name <- TABLE_NAMES[i]
    table <- encoded$tables[[table_key(key[1L],key[2L])]]
    frequencies <- encoded$frequencies[[table_key(key[1L],key[2L])]]
    bits <- sum(vapply(
        table$symbols,
        function(symbol) frequencies[symbol+1L]*table$codes[[as.character(symbol)]][1L],
        numeric(1)
    ))
    lines <- c(
        lines,
        words(
            "table",
            name,
            "class",
            key[1L],
            "id",
            key[2L],
            "symbols",
            length(table$symbols),
            "coded",
            sum(frequencies),
            "bits",
            bits
        ),
        paste("counts",paste(table$counts,collapse=" "))
    )
    for (symbol in table$symbols) {
      code <- table$codes[[as.character(symbol)]]
      digits <- vapply(
          seq.int(code[1L]-1L,0L),
          function(shift) as.character(bitwAnd(bitwShiftR(code[2L],shift),1L)),
          character(1)
      )
      lines <- c(
          lines,
          words(
              "symbol",
              sprintf("%02x",symbol),
              "length",
              code[1L],
              "code",
              paste(digits,collapse=""),
              "count",
              frequencies[symbol+1L]
          )
      )
    }
  }
  lines
}
thumbnail <- function(decoded) {
  layout <- decoded$layout
  dc <- list()
  for (number in seq_along(layout$blocks)) {
    block <- layout$blocks[[number]]
    dc[[paste(block$component,block$bx,block$by)]] <- decoded$coefficients[[number]][1L]
  }
  image <- array(0,c((layout$height+7L) %/% 8L,(layout$width+7L) %/% 8L,3L))
  for (y in 0:(dim(image)[1L]-1L)) for (x in 0:(dim(image)[2L]-1L)) {
    values <- numeric(3L)
    for (k in 1:3) {
      component <- layout$components[[k]]
      value <- dc[[paste(k,(x*component$h) %/% layout$hmax,(y*component$v) %/% layout$vmax)]]
      values[k] <- clamp_byte((value*decoded$quantization[[as.character(component$tq)]][
          1L,
          1L
      ]+4L) %/% 8L+128L)
    }
    image[y+1L,x+1L,] <- to_rgb(values[1L],values[2L],values[3L])
  }
  image
}
reference_report <- function(image,params,codec,original_planes,encoded,decoded,errors) {
  layout <- encoded$layout
  lines <- c(
      words("image",layout$width,layout$height),
      words("sampling",params$sampling,"mcu",8L*layout$hmax,8L*layout$vmax,"grid",layout$mx,layout$my),
      words("padded",8L*layout$hmax*layout$mx,8L*layout$vmax*layout$my),
      paste(
          "blocks",
          paste(vapply(layout$components,function(c) c$h*c$v*layout$mcus,integer(1)),collapse=" ")
      ),
      words("restart_interval",layout$restart_interval,"markers",length(layout$intervals)-1L),
      words("huffman",params$huffman),
      words("quality",params$qualities[1L])
  )
  for (id in 0:1) lines <- c(
      lines,
      words("quant",id,paste(zigzag(encoded$quantization[[as.character(id)]]),collapse=" "))
  )
  frequencies <- encoded$frequencies
  lines <- c(
      lines,
      paste(
          "symbols",
          paste(
              vapply(TABLE_KEYS,function(key) sum(frequencies[[table_key(key[1L],key[2L])]]),numeric(1)),
              collapse=" "
          )
      ),
      words(
          "eob",
          frequencies[["1,0"]][1L]+frequencies[["1,1"]][1L],
          "zrl",
          frequencies[["1,0"]][241L]+frequencies[["1,1"]][241L]
      ),
      words(
          "zero_ac_blocks",
          sum(vapply(encoded$coefficients,function(sequence) all(sequence[-1L] == 0),logical(1)))
      ),
      paste(
          "nonzero",
          paste(
              vapply(
                  seq_len(64L),
                  function(i) sum(vapply(
                      encoded$coefficients,
                      function(sequence) sequence[i] != 0,
                      logical(1)
                  )),
                  numeric(1)
              ),
              collapse=" "
          )
      )
  )
  for (k in 1:3) {
    numbers <- which(vapply(layout$blocks,function(block) block$component == k,logical(1)))
    nonzero <- sum(vapply(encoded$coefficients[numbers],function(sequence) sum(sequence != 0),numeric(1)))
    lines <- c(
        lines,
        words(
            "component",
            COMPONENT_NAMES[k],
            "bits",
            sum(encoded$block_bits[numbers]),
            "nonzero",
            nonzero,
            "sse",
            sprintf("%.0f",sum(errors[numbers]))
        )
    )
  }
  for (name in c(
      "padding_bits",
      "stuffed_bytes",
      "header_bytes",
      "scan_bytes"
  )) lines <- c(lines,words(name,encoded[[name]]))
  lines <- c(lines,words("total_bytes",length(encoded$data)))
  for (i in seq_along(encoded$intervals)) lines <- c(
      lines,
      words("interval",i-1L,paste(encoded$intervals[[i]],collapse=" "))
  )
  histogram <- integer(8L)
  differences <- abs(image_values(image)-image_values(decoded$image))
  for (value in differences) {
    index <- 1L+sum(c(1L,2L,4L,8L,16L,32L,64L) <= value)
    histogram[index] <- histogram[index]+1L
  }
  lines <- c(lines,paste("error_histogram",paste(histogram,collapse=" ")))
  for (keep in params$truncate) {
    plane <- reconstruct_component(codec,decoded$layout,1L,decoded$coefficients,decoded$quantization,keep)
    lines <- c(
        lines,
        words(
            "truncate",
            keep,
            psnr(
                plane_values(original_planes[[1L]]),
                plane_values(plane[seq_len(layout$height),seq_len(layout$width),drop=FALSE])
            )
        )
    )
  }
  lines
}
stream_report <- function(decoded,repaired,repaired_decoded) {
  layout <- decoded$layout
  lines <- vapply(
      decoded$segments,
      function(entry) words("stream_segment",entry[[1L]],entry[[2L]],entry[[3L]]),
      character(1)
  )
  lines <- c(lines,words("stream_image",layout$width,layout$height))
  for (component in layout$components) lines <- c(
      lines,
      words(
          "stream_component",
          component$identifier,
          component$h,
          component$v,
          component$tq,
          component$td,
          component$ta
      )
  )
  for (id in sort(as.integer(names(decoded$quantization)))) lines <- c(
      lines,
      words("stream_quant",id,paste(zigzag(decoded$quantization[[as.character(id)]]),collapse=" "))
  )
  keys <- do.call(rbind,strsplit(names(decoded$tables),",",fixed=TRUE))
  keys <- matrix(as.integer(keys),nrow(keys),ncol(keys))
  keys <- keys[order(keys[,1L],keys[,2L]),,drop=FALSE]
  for (i in seq_len(nrow(keys))) {
    class <- keys[i,1L]
    id <- keys[i,2L]
    table <- decoded$tables[[table_key(class,id)]]
    lines <- c(
        lines,
        words(
            "stream_huffman",
            class,
            id,
            "symbols",
            length(table$symbols),
            "longest",
            max(which(table$counts > 0L))
        )
    )
  }
  counts <- vapply(
      c("ok","damaged","lost"),
      function(state) sum(vapply(decoded$states,function(result) result$state == state,logical(1))),
      numeric(1)
  )
  lines <- c(
      lines,
      words(
          "stream_restart",
          layout$restart_interval,
          "intervals",
          length(layout$intervals),
          "ok",
          counts[["ok"]],
          "damaged",
          counts[["damaged"]],
          "lost",
          counts[["lost"]]
      )
  )
  for (i in seq_along(layout$intervals)) {
    result <- decoded$states[[i]]
    state <- if (result$state == "damaged") words(
        "damaged",
        result$kind,
        "mcu",
        result$mcu,
        "offset",
        result$offset,
        "resync",
        result$resync
    ) else result$state
    lines <- c(lines,words("stream_interval",i-1L,paste(layout$intervals[[i]],collapse=" "),state))
  }
  c(
      lines,
      words("stream_scan_bytes",decoded$scan_bytes),
      words(
          "repair",
          length(repaired$data),
          repaired$header_bytes,
          repaired$scan_bytes,
          "identical",
          if (identical(decoded$image,repaired_decoded$image)) "yes" else "no"
      )
  )
}
main <- function() {
  image <- read_ppm("input/image.ppm")
  params <- read_params("input/params.txt")
  codec <- read_tables("input/tables.txt")
  stream <- read_hex("input/stream.hex")
  width <- dim(image)[2L]
  height <- dim(image)[1L]
  quality <- params$qualities[1L]
  sampling <- params$sampling
  mode <- params$huffman
  restart_interval <- params$restart_interval
  original_planes <- split_planes(image)
  prepared <- new.env(hash=TRUE,parent=emptyenv())
  encodings <- new.env(hash=TRUE,parent=emptyenv())
  decodings <- new.env(hash=TRUE,parent=emptyenv())
  encoding <- function(q,s=sampling,m=mode) {
    key <- paste(q,s,m)
    if (!exists(key,encodings,inherits=FALSE)) {
      prep_key <- paste(q,s)
      if (!exists(prep_key,prepared,inherits=FALSE)) assign(
          prep_key,
          prepare(codec,image,q,s,restart_interval),
          prepared
      )
      assign(key,encode_prepared(codec,get(prep_key,prepared,inherits=FALSE),m),encodings)
    }
    get(key,encodings,inherits=FALSE)
  }
  decoding <- function(q,s=sampling) {
    key <- paste(q,s)
    if (!exists(key,decodings,inherits=FALSE)) assign(key,decode(codec,encoding(q,s)$data),decodings)
    get(key,decodings,inherits=FALSE)
  }
  rate_lines <- "quality,bytes_standard,bytes_optimized,bpp,psnr_y,psnr_cb,psnr_cr,psnr_rgb,max_error"
  for (q in params$qualities) {
    standard <- encoding(q,sampling,"standard")
    optimized <- encoding(q,sampling,"optimized")
    selected <- encoding(q)
    metrics <- quality_metrics(image,original_planes,decoding(q))
    rate_lines <- c(
        rate_lines,
        paste(
            c(
                q,
                length(standard$data),
                length(optimized$data),
                bits_per_pixel(length(selected$data),width,height),
                metrics$metrics,
                metrics$maximum
            ),
            collapse=","
        )
    )
  }
  reference <- encoding(quality)
  reference_decoded <- decoding(quality)
  blocks <- block_statistics(reference,reference_decoded)
  report <- reference_report(image,params,codec,original_planes,reference,reference_decoded,blocks$errors)
  for (s in c("444","422","420")) {
    metrics <- quality_metrics(image,original_planes,decoding(quality,s))
    report <- c(
        report,
        words("sampling_compare",s,length(encoding(quality,s)$data),paste(metrics$metrics[-1L],collapse=" "))
    )
  }
  previous <- image
  for (generation in seq_len(params$generations)) {
    encoded <- if (generation == 1L) reference else encode(
        codec,
        previous,
        quality,
        sampling,
        mode,
        restart_interval
    )
    decoded <- if (generation == 1L) reference_decoded else decode(codec,encoded$data)
    changed <- 0L
    for (y in seq_len(height)) for (x in seq_len(width)) if (any(previous[y,x,] != decoded$image[
        y,
        x,
    ])) changed <- changed+1L
    report <- c(
        report,
        words("generation",generation,length(encoded$data),image_psnr(image,decoded$image),changed)
    )
    previous <- decoded$image
  }
  lo <- 1L
  hi <- 100L
  while (lo < hi) {
    mid <- (lo+hi+1L) %/% 2L
    bytes <- length(encoding(mid)$data)
    report <- c(report,words("rate_control_step",mid,bytes))
    if (bytes <= params$target_bytes) lo <- mid else hi <- mid-1L
  }
  bytes <- length(encoding(lo)$data)
  report <- c(
      report,
      words(
          "rate_control",
          lo,
          bytes,
          if (bytes <= params$target_bytes) "yes" else "no",
          image_psnr(image,decoding(lo)$image)
      )
  )
  stream_decoded <- decode(codec,stream)
  repaired <- repair(codec,stream_decoded)
  report <- c(report,stream_report(stream_decoded,repaired,decode(codec,repaired$data)))
  dir.create("output",showWarnings=FALSE)
  write_ppm("output/decoded.ppm",reference_decoded$image)
  write_hex("output/bitstream.hex",reference$data)
  write_ppm("output/thumbnail.ppm",thumbnail(reference_decoded))
  write_ppm("output/stream_decoded.ppm",stream_decoded$image)
  write_hex("output/repaired.hex",repaired$data)
  outputs <- list(
      "rate_distortion.csv"=rate_lines,
      "huffman_tables.txt"=huffman_lines(reference),
      "blocks.txt"=blocks$lines,
      "report.txt"=report
  )
  for (name in names(outputs)) writeLines(outputs[[name]],file.path("output",name),useBytes=TRUE)
}
main()
