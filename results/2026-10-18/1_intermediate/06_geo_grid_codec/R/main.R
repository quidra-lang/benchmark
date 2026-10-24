precs <- list(GEOHASH = 1:9, MAIDENHEAD = c(2,4,6,8), PLUSCODE = c(2,4,6,8,10,11), GARS = 5:7,
              GEOREF = c(2,4,8,10,12), MESH = c(4,6,8,9,10,11))
gh <- "0123456789bcdefghjkmnpqrstuvwxyz"
l24 <- "ABCDEFGHJKLMNPQRSTUVWXYZ"
pc <- "23456789CFGHJMPQRVWX"
mh <- c("ABCDEFGHIJKLMNOPQR", "0123456789", "abcdefghijklmnopqrstuvwx", "0123456789")
bands <- "CDEFGHJKLMNPQRSTUVWX"
os_letters <- "ABCDEFGHJKLMNOPQRSTUVWXYZ"
columns <- c("STUVWXYZ", "ABCDEFGH", "JKLMNPQR")
rows <- "ABCDEFGHJKLMNPQRSTUV"
invalid <- function() stop("INVALID", call. = FALSE)
# Inputs and correction products are exact integers below 2^53.
# Correct a rounded quotient against products before making any grid decision.
fd <- function(a, b) {
  q <- floor(a / b)
  while (q * b > a) q <- q - 1
  while ((q + 1) * b <= a) q <- q + 1
  q
}
md <- function(a, b) a - fd(a, b) * b
num <- function(v) format(v, scientific = FALSE, trim = TRUE, digits = 22)
char_at <- function(set, i) substring(set, i + 1, i + 1)
chars <- function(text) strsplit(text, "", fixed = TRUE)[[1L]]
index_char <- function(set, char) {
  i <- match(char, chars(set))
  if (nchar(char, type = "bytes") != 1L || is.na(i)) invalid()
  i - 1
}
integer_arg <- function(text, lo, hi) {
  if (!grepl("^-?[0-9]{1,9}$", text, perl = TRUE)) invalid()
  v <- as.numeric(text)
  if (v < lo || v > hi) invalid()
  v
}
coordinate <- function(text, latitude) {
  if (!grepl("^-?[0-9]{1,3}(\\.[0-9]{1,6})?$", text, perl = TRUE)) invalid()
  negative <- substr(text, 1L, 1L) == "-"
  if (negative) text <- substring(text, 2L)
  parts <- strsplit(text, ".", fixed = TRUE)[[1L]]
  fraction <- if (length(parts) == 2L) parts[2L] else ""
  v <- as.numeric(parts[1L]) * 1000000 + as.numeric(paste0(fraction, strrep("0", 6L - nchar(fraction))))
  if (negative) v <- -v
  if (latitude) {
    if (v < -90000000 || v > 90000000) invalid()
  } else {
    if (v < -180000000 || v >= 180000000) invalid()
  }
  v
}
system_name <- function(sys) {
  if (is.null(precs[[sys]])) invalid()
  sys
}
precision <- function(sys, text) {
  p <- integer_arg(text, 1, 12)
  if (!(p %in% precs[[sys]])) invalid()
  p
}
grid <- function(sys, p) {
  if (sys == "GEOHASH") return(c(2^fd(5*p+1,2), 2^fd(5*p,2)))
  sizes <- switch(sys,
    MAIDENHEAD = list(c(18,18), c(180,180), c(4320,4320), c(43200,43200)),
    PLUSCODE = list(c(18,9), c(360,180), c(7200,3600), c(144000,72000), c(2880000,1440000), c(11520000,7200000)),
    GARS = list(c(720,360), c(1440,720), c(4320,2160)),
    GEOREF = list(c(24,12), c(360,180), c(21600,10800), c(216000,108000), c(2160000,1080000)),
    MESH = list(c(360,270), c(2880,2160), c(28800,21600), c(57600,43200), c(115200,86400), c(230400,172800)))
  sizes[[match(p, precs[[sys]])]]
}
radix_digits <- function(v, radices) {
  out <- numeric(length(radices))
  for (i in rev(seq_along(radices))) {
    out[i] <- md(v, radices[i])
    v <- fd(v, radices[i])
  }
  out
}
encode <- function(sys, p, x, y) {
  if (sys == "GEOHASH") {
    a <- fd(5*p+1, 2)
    b <- fd(5*p, 2)
    value <- 0
    out <- ""
    for (i in seq_len(5*p) - 1) {
      if (i %% 2 == 0) {
        a <- a - 1
        bit <- md(fd(x, 2^a), 2)
      } else {
        b <- b - 1
        bit <- md(fd(y, 2^b), 2)
      }
      value <- 2*value + bit
      if (i %% 5 == 4) {
        out <- paste0(out, char_at(gh, value))
        value <- 0
      }
    }
    return(out)
  }
  if (sys == "MAIDENHEAD") {
    k <- p/2
    radices <- c(18,10,24,10)[seq_len(k)]
    xs <- radix_digits(x, radices)
    ys <- radix_digits(y, radices)
    return(paste0(char_at(mh[seq_len(k)], xs), char_at(mh[seq_len(k)], ys), collapse = ""))
  }
  if (sys == "PLUSCODE") {
    tail <- ""
    if (p == 11) {
      tail <- char_at(pc, 4*md(y,5) + md(x,4))
      x <- fd(x,4)
      y <- fd(y,5)
    }
    k <- fd(min(p,10),2)
    radices <- rep(20, k)
    radices[1L] <- 18
    xs <- radix_digits(x, radices)
    radices[1L] <- 9
    ys <- radix_digits(y, radices)
    out <- paste0(paste0(char_at(pc, ys), char_at(pc, xs), collapse = ""), tail)
    if (p < 8) return(paste0(out, strrep("0", 8-p), "+"))
    return(paste0(substr(out,1,8), "+", substring(out,9)))
  }
  if (sys == "GARS") {
    tail <- ""
    if (p == 7) {
      tail <- num(1 + md(x,3) + 3*(2-md(y,3)))
      x <- fd(x,3)
      y <- fd(y,3)
    }
    if (p >= 6) {
      tail <- paste0(num(1 + md(x,2) + 2*(1-md(y,2))), tail)
      x <- fd(x,2)
      y <- fd(y,2)
    }
    return(paste0(sprintf("%03d", as.integer(x+1)), char_at(l24,fd(y,24)), char_at(l24,md(y,24)), tail))
  }
  if (sys == "GEOREF") {
    tail <- ""
    if (p >= 8) {
      m <- (p-4)/2
      scale <- 6*10^(m-1)
      tail <- sprintf("%0*d%0*d", as.integer(m), as.integer(md(x,scale)), as.integer(m), as.integer(md(y,scale)))
      x <- fd(x,scale)
      y <- fd(y,scale)
    }
    if (p >= 4) {
      tail <- paste0(char_at(l24,md(x,15)), char_at(l24,md(y,15)), tail)
      x <- fd(x,15)
      y <- fd(y,15)
    }
    return(paste0(char_at(l24,x), char_at(l24,y), tail))
  }
  level <- match(p, precs$MESH)
  scale <- c(1,8,80,160,320,640)[level]
  u <- x - 280*scale
  v <- y - 135*scale
  if (u < 0 || u >= 80*scale || v < 0 || v >= 100*scale) return("-")
  radices <- c(80,8,10,2,2,2)[seq_len(level)]
  us <- radix_digits(u, radices)
  radices[1L] <- 100
  vs <- radix_digits(v, radices)
  out <- sprintf("%02d%02d", as.integer(vs[1L]), as.integer(us[1L]))
  if (level >= 2L) {
    for (i in 2:level) {
      if (i <= 3L) out <- paste0(out, num(vs[i]), num(us[i])) else out <- paste0(out, num(1+us[i]+2*vs[i]))
    }
  }
  out
}
decode <- function(sys, code) {
  p <- nchar(code, type = "bytes")
  x <- y <- 0
  if (sys != "PLUSCODE" && !(p %in% precs[[sys]])) invalid()
  if (sys == "GEOHASH") {
    bit_index <- 0
    for (char in chars(code)) {
      value <- index_char(gh, char)
      for (i in 4:0) {
        bit <- md(fd(value,2^i),2)
        if (bit_index %% 2 == 0) x <- 2*x+bit else y <- 2*y+bit
        bit_index <- bit_index + 1
      }
    }
  } else if (sys == "MAIDENHEAD") {
    for (i in seq_len(p/2)) {
      radix <- nchar(mh[i])
      x <- x*radix + index_char(mh[i], substr(code,2*i-1,2*i-1))
      y <- y*radix + index_char(mh[i], substr(code,2*i,2*i))
    }
  } else if (sys == "PLUSCODE") {
    plus <- gregexpr("+", code, fixed = TRUE)[[1L]]
    if (length(plus) != 1L || plus[1L] != 9L) invalid()
    before <- substr(code,1,8)
    after <- substring(code,10)
    zero <- regexpr("0", before, fixed = TRUE)[1L]
    prefix <- if (zero < 0L) 8L else zero-1L
    if (!(prefix %in% c(2,4,6,8))) invalid()
    if (prefix < 8L && (substring(before,prefix+1L) != strrep("0",8L-prefix) || after != "")) invalid()
    if (prefix == 8L && !(nchar(after) %in% c(0,2,3))) invalid()
    sequence <- paste0(substr(before,1,prefix),after)
    p <- nchar(sequence)
    values <- vapply(chars(sequence), function(char) index_char(pc,char), numeric(1L))
    if (values[1L] > 8 || values[2L] > 17) invalid()
    for (i in seq_len(fd(min(p,10),2))) {
      y <- y*(if (i == 1L) 9 else 20) + values[2*i-1]
      x <- x*(if (i == 1L) 18 else 20) + values[2*i]
    }
    if (p == 11L) {
      x <- 4*x + md(values[11L],4)
      y <- 5*y + fd(values[11L],4)
    }
  } else if (sys == "GARS") {
    if (!grepl("^[0-9]{3}", code, perl = TRUE)) invalid()
    x <- as.numeric(substr(code,1,3)) - 1
    y <- 24*index_char(substr(l24,1,15),substr(code,4,4)) + index_char(l24,substr(code,5,5))
    if (p >= 6L) {
      q <- index_char("1234",substr(code,6,6))
      x <- 2*x + md(q,2)
      y <- 2*y + 1-fd(q,2)
    }
    if (p == 7L) {
      q <- index_char("123456789",substr(code,7,7))
      x <- 3*x + md(q,3)
      y <- 3*y + 2-fd(q,3)
    }
  } else if (sys == "GEOREF") {
    x <- index_char(l24,substr(code,1,1))
    y <- index_char(substr(l24,1,12),substr(code,2,2))
    if (p >= 4L) {
      x <- 15*x + index_char(substr(l24,1,15),substr(code,3,3))
      y <- 15*y + index_char(substr(l24,1,15),substr(code,4,4))
    }
    if (p >= 8L) {
      m <- (p-4)/2
      tail <- substring(code,5)
      if (!grepl("^[0-9]+$",tail,perl=TRUE)) invalid()
      scale <- 6*10^(m-1)
      e <- as.numeric(substr(tail,1,m))
      n <- as.numeric(substring(tail,m+1))
      if (e >= scale || n >= scale) invalid()
      x <- x*scale + e
      y <- y*scale + n
    }
  } else {
    if (!grepl("^[0-9]+$",code,perl=TRUE)) invalid()
    level <- match(p,precs$MESH)
    u <- as.numeric(substr(code,3,4))
    v <- as.numeric(substr(code,1,2))
    if (u > 79) invalid()
    if (level >= 2L) {
      for (i in 2:level) {
        if (i <= 3L) {
          base <- if (i == 2L) 8 else 10
          a <- as.numeric(substr(code,2*i+1,2*i+1))
          b <- as.numeric(substr(code,2*i+2,2*i+2))
          if (a >= base || b >= base) invalid()
          v <- v*base + a
          u <- u*base + b
        } else {
          q <- index_char("1234",substr(code,i+5,i+5))
          u <- 2*u + md(q,2)
          v <- 2*v + fd(q,2)
        }
      }
    }
    scale <- c(1,8,80,160,320,640)[level]
    x <- u + 280*scale
    y <- v + 135*scale
  }
  size <- grid(sys,p)
  if (x < 0 || x >= size[1L] || y < 0 || y >= size[2L] || encode(sys,p,x,y) != code) invalid()
  c(p,x,y)
}
point_cell <- function(sys,p,lat,lon) {
  size <- grid(sys,p)
  c(fd((lon+180000000)*size[1L],360000000), min(fd((lat+90000000)*size[2L],180000000),size[2L]-1))
}
ancestor <- function(sys,cell,q) {
  size <- grid(sys,cell[1L])
  target <- grid(sys,q)
  c(q,fd(cell[2L]*target[1L],size[1L]),fd(cell[3L]*target[2L],size[2L]))
}
cell_code <- function(sys,cell) encode(sys,cell[1L],cell[2L],cell[3L])
coord_text <- function(v) paste0(if (v < 0) "-" else "", sprintf("%d.%06d",as.integer(fd(abs(v),1000000)),as.integer(md(abs(v),1000000))))
decimal_suffix <- function(e,n,d) {
  if (d == 0) return("")
  paste0(" ",substr(sprintf("%05d",as.integer(md(e,100000))),1,d)," ",substr(sprintf("%05d",as.integer(md(n,100000))),1,d))
}
square_digits <- function(args,offset) {
  if (length(args) == offset) return(c(0,0,100000))
  a <- args[offset+1L]
  b <- args[offset+2L]
  if (!grepl("^[0-9]{1,5}$",a,perl=TRUE) || !grepl("^[0-9]{1,5}$",b,perl=TRUE) || nchar(a) != nchar(b)) invalid()
  size <- 10^(5-nchar(a))
  c(as.numeric(a)*size,as.numeric(b)*size,size)
}
cell_key <- function(cell) paste(vapply(cell,num,character(1L)),collapse=":")
compact_cells <- function(sys,cells) {
  set <- new.env(hash=TRUE,parent=emptyenv())
  for (cell in cells) set[[cell_key(cell)]] <- cell
  repeat {
    changed <- FALSE
    for (key in ls(set,all.names=TRUE)) {
      cell <- set[[key]]
      index <- match(cell[1L],precs[[sys]])
      for (i in seq_len(index-1L)) {
        if (!is.null(set[[cell_key(ancestor(sys,cell,precs[[sys]][i]))]])) {
          rm(list=key,envir=set)
          changed <- TRUE
          break
        }
      }
    }
    for (index in rev(seq_len(length(precs[[sys]])-1L)+1L)) {
      p <- precs[[sys]][index]
      q <- precs[[sys]][index-1L]
      size <- grid(sys,p)
      target <- grid(sys,q)
      needed <- fd(size[1L],target[1L])*fd(size[2L],target[2L])
      groups <- list()
      parents <- list()
      for (key in ls(set,all.names=TRUE)) {
        cell <- set[[key]]
        if (cell[1L] == p) {
          parent <- ancestor(sys,cell,q)
          pk <- cell_key(parent)
          groups[[pk]] <- c(groups[[pk]],key)
          parents[[pk]] <- parent
        }
      }
      for (key in names(groups)) {
        if (length(groups[[key]]) == needed) {
          rm(list=groups[[key]],envir=set)
          set[[key]] <- parents[[key]]
          changed <- TRUE
        }
      }
    }
    if (!changed) break
  }
  cells <- lapply(ls(set,all.names=TRUE),function(key) set[[key]])
  p <- vapply(cells,function(cell) cell[1L],numeric(1L))
  x <- vapply(cells,function(cell) cell[2L],numeric(1L))
  y <- vapply(cells,function(cell) cell[3L],numeric(1L))
  cells[order(p,-y,x,method="radix")]
}
execute <- function(line) {
  all <- strsplit(line," ",fixed=TRUE)[[1L]]
  command <- all[1L]
  t <- all[-1L]
  counts <- list(ENCODE=4L,DECODE=2L,NEIGHBORS=2L,PARENT=2L,CHILDREN=2L,COMMON=3L,CONTAINS=4L,COVER=6L,
                 CONVERT=5L,STEPS=3L,PATH=3L,RELATE=4L,SIZE=2L,SHORTEN=3L,RECOVER=3L,UTMZONE=2L,
                 OSGB=3L,UNOSGB=c(1L,3L),MGRS=5L,UNMGRS=c(2L,4L),QUADKEY=3L,UNQUADKEY=1L)
  if (command == "COMPACT") {
    if (length(t) < 2L || length(t) > 101L) invalid()
  } else if (is.null(counts[[command]]) || !(length(t) %in% counts[[command]])) invalid()
  if (command == "UTMZONE") {
    lat <- coordinate(t[1L],TRUE)
    lon <- coordinate(t[2L],FALSE)
    if (lat < -80000000 || lat >= 84000000) return("NONE")
    band <- char_at(bands,min(fd(lat+80000000,8000000),19))
    zone <- fd(lon+180000000,6000000)+1
    if (band == "V" && lon >= 3000000 && lon < 12000000) zone <- 32
    if (band == "X" && lon >= 0 && lon < 42000000) {
      if (lon < 9000000) {
        zone <- 31
      } else if (lon < 21000000) {
        zone <- 33
      } else if (lon < 33000000) {
        zone <- 35
      } else {
        zone <- 37
      }
    }
    return(paste0(num(zone),band))
  }
  if (command == "OSGB") {
    e <- integer_arg(t[1L],0,699999)
    n <- integer_arg(t[2L],0,1299999)
    d <- integer_arg(t[3L],0,5)
    letters <- paste0(char_at(os_letters,5*(3-fd(n,500000))+2+fd(e,500000)),char_at(os_letters,5*(4-md(fd(n,100000),5))+md(fd(e,100000),5)))
    return(paste0(letters,decimal_suffix(e,n,d)))
  }
  if (command == "UNOSGB") {
    if (nchar(t[1L],type="bytes") != 2L) invalid()
    a <- index_char(os_letters,substr(t[1L],1,1))
    b <- index_char(os_letters,substr(t[1L],2,2))
    e <- 500000*(md(a,5)-2)+100000*md(b,5)
    n <- 500000*(3-fd(a,5))+100000*(4-fd(b,5))
    if (e < 0 || e >= 700000 || n < 0 || n >= 1300000) invalid()
    extra <- square_digits(t,1L)
    return(paste0("sw=",num(e+extra[1L]),",",num(n+extra[2L])," size=",num(extra[3L])))
  }
  if (command == "MGRS") {
    zone <- integer_arg(t[1L],1,60)
    if (nchar(t[2L],type="bytes") != 1L) invalid()
    index_char(bands,t[2L])
    e <- integer_arg(t[3L],100000,899999)
    n <- integer_arg(t[4L],0,9999999)
    d <- integer_arg(t[5L],0,5)
    letters <- paste0(char_at(columns[md(zone,3)+1],fd(e,100000)-1),char_at(rows,md(fd(n,100000)+(if (md(zone,2)==0) 5 else 0),20)))
    return(paste0(num(zone),t[2L]," ",letters,decimal_suffix(e,n,d)))
  }
  if (command == "UNMGRS") {
    if (!grepl("^[1-9][0-9]?[CDEFGHJKLMNPQRSTUVWX]$",t[1L],perl=TRUE)) invalid()
    zone <- as.numeric(substr(t[1L],1,nchar(t[1L])-1L))
    if (zone > 60 || nchar(t[2L],type="bytes") != 2L) invalid()
    c <- index_char(columns[md(zone,3)+1],substr(t[2L],1,1))
    r <- index_char(rows,substr(t[2L],2,2))
    e <- 100000*(c+1)
    n <- 100000*md(r-(if (md(zone,2)==0) 5 else 0),20)
    extra <- square_digits(t,2L)
    return(paste0(t[1L]," sw=",num(e+extra[1L]),",",num(n+extra[2L])," size=",num(extra[3L])))
  }
  if (command == "QUADKEY") {
    z <- integer_arg(t[3L],1,23)
    x <- integer_arg(t[1L],0,2^z-1)
    y <- integer_arg(t[2L],0,2^z-1)
    out <- ""
    for (i in (z-1):0) out <- paste0(out,num(md(fd(x,2^i),2)+2*md(fd(y,2^i),2)))
    return(out)
  }
  if (command == "UNQUADKEY") {
    if (!grepl("^[0-3]{1,23}$",t[1L],perl=TRUE)) invalid()
    x <- y <- 0
    for (char in chars(t[1L])) {
      v <- as.numeric(char)
      x <- 2*x+md(v,2)
      y <- 2*y+fd(v,2)
    }
    return(paste0("x=",num(x)," y=",num(y)," z=",nchar(t[1L])))
  }
  if (command %in% c("SHORTEN","RECOVER")) {
    lat <- coordinate(t[2L],TRUE)
    lon <- coordinate(t[3L],FALSE)
    if (command == "SHORTEN") {
      cell <- decode("PLUSCODE",t[1L])
      p <- cell[1L]
      x <- cell[2L]
      y <- cell[3L]
      if (p < 8) invalid()
      size <- grid("PLUSCODE",p)
      w <- size[1L]
      h <- size[2L]
      dy <- abs((-90000000-lat)*2*h+180000000*(2*y+1))
      dx <- abs((-180000000-lon)*2*w+360000000*(2*x+1))
      if (dy < 15000*2*h && dx < 15000*2*w) return(substring(t[1L],7))
      if (dy < 300000*2*h && dx < 300000*2*w) return(substring(t[1L],5))
      return(t[1L])
    }
    if (!grepl("^([23456789CFGHJMPQRVWX]{2}|[23456789CFGHJMPQRVWX]{4})\\+([23456789CFGHJMPQRVWX]{2,3})?$",t[1L],perl=TRUE)) invalid()
    r <- 9L-regexpr("+",t[1L],fixed=TRUE)[1L]
    point <- point_cell("PLUSCODE",10,lat,lon)
    full <- paste0(substr(encode("PLUSCODE",10,point[1L],point[2L]),1,r),t[1L])
    cell <- decode("PLUSCODE",full)
    p <- cell[1L]
    x <- cell[2L]
    y <- cell[3L]
    size <- grid("PLUSCODE",p)
    w <- size[1L]
    h <- size[2L]
    d <- if (r == 4L) 1000000 else 50000
    my <- fd(d*h,180000000)
    mx <- fd(d*w,360000000)
    cy <- 180000000*(2*y+1)
    cx <- 360000000*(2*x+1)
    if ((lat+d/2+90000000)*2*h < cy && cy >= d*2*h) {
      y <- y-my
    } else if ((lat-d/2+90000000)*2*h > cy && cy <= (180000000-d)*2*h) {
      y <- y+my
    }
    if ((lon+d/2+180000000)*2*w < cx) {
      x <- md(x-mx,w)
    } else if ((lon-d/2+180000000)*2*w > cx) {
      x <- md(x+mx,w)
    }
    return(encode("PLUSCODE",p,x,y))
  }
  sys <- system_name(t[1L])
  if (command %in% c("SIZE","ENCODE","COVER")) {
    p <- precision(sys,t[if (command == "ENCODE") 4L else 2L])
    size <- grid(sys,p)
    w <- size[1L]
    h <- size[2L]
    if (command == "SIZE") {
      cells <- w*h
      if (sys == "MESH") {
        scale <- c(1,8,80,160,320,640)[match(p,precs[[sys]])]
        cells <- 8000*scale*scale
      }
      return(paste0("w=",coord_text(fd(360000000,w))," h=",coord_text(fd(180000000,h))," cells=",num(cells)))
    }
    if (command == "ENCODE") {
      point <- point_cell(sys,p,coordinate(t[2L],TRUE),coordinate(t[3L],FALSE))
      code <- encode(sys,p,point[1L],point[2L])
      return(if (code == "-") "OUT OF AREA" else code)
    }
    lat1 <- coordinate(t[3L],TRUE)
    lon1 <- coordinate(t[4L],FALSE)
    lat2 <- coordinate(t[5L],TRUE)
    lon2 <- coordinate(t[6L],FALSE)
    if (lat1 > lat2) invalid()
    first <- point_cell(sys,p,lat1,lon1)
    last <- point_cell(sys,p,lat2,lon2)
    columns_count <- if (lon1 <= lon2) last[1L]-first[1L]+1 else min(w,last[1L]-first[1L]+1+w)
    if ((last[2L]-first[2L]+1)*columns_count > 100) return("TOO MANY")
    out <- character()
    for (y in seq.int(last[2L],first[2L])) {
      for (i in seq_len(columns_count)-1) out <- c(out,encode(sys,p,md(first[1L]+i,w),y))
    }
    return(paste(out,collapse=" "))
  }
  if (command == "COMPACT") {
    cells <- lapply(t[-1L],function(code) decode(sys,code))
    return(paste(vapply(compact_cells(sys,cells),function(cell) cell_code(sys,cell),character(1L)),collapse=" "))
  }
  cell <- decode(sys,t[2L])
  p <- cell[1L]
  x <- cell[2L]
  y <- cell[3L]
  size <- grid(sys,p)
  w <- size[1L]
  h <- size[2L]
  index <- match(p,precs[[sys]])
  if (command == "DECODE") {
    south <- -90000000+fd(180000000*y,h)
    west <- -180000000+fd(360000000*x,w)
    north <- -90000000+fd(180000000*(y+1),h)
    east <- -180000000+fd(360000000*(x+1),w)
    cy <- -90000000+fd(180000000*(2*y+1),2*h)
    cx <- -180000000+fd(360000000*(2*x+1),2*w)
    return(paste0("sw=",coord_text(south),",",coord_text(west)," ne=",coord_text(north),",",coord_text(east)," c=",coord_text(cy),",",coord_text(cx)))
  }
  if (command == "CONTAINS") {
    point <- point_cell(sys,p,coordinate(t[3L],TRUE),coordinate(t[4L],FALSE))
    return(if (all(point == cell[2:3])) "YES" else "NO")
  }
  if (command == "NEIGHBORS") {
    offsets <- list(c(0,1),c(1,1),c(1,0),c(1,-1),c(0,-1),c(-1,-1),c(-1,0),c(-1,1))
    out <- vapply(offsets,function(delta) {
      yy <- y+delta[2L]
      if (yy < 0 || yy >= h) return("-")
      encode(sys,p,md(x+delta[1L],w),yy)
    },character(1L))
    return(paste(out,collapse=" "))
  }
  if (command == "PARENT") {
    if (index == 1L) return("NONE")
    return(cell_code(sys,ancestor(sys,cell,precs[[sys]][index-1L])))
  }
  if (command == "CHILDREN") {
    if (index == length(precs[[sys]])) return("NONE")
    q <- precs[[sys]][index+1L]
    target <- grid(sys,q)
    rx <- fd(target[1L],w)
    ry <- fd(target[2L],h)
    if (rx*ry > 100) return("TOO MANY")
    out <- character()
    for (j in (ry-1):0) {
      for (i in seq_len(rx)-1) out <- c(out,encode(sys,q,rx*x+i,ry*y+j))
    }
    return(paste(out,collapse=" "))
  }
  if (command == "CONVERT") {
    if (t[3L] != "TO") invalid()
    sys2 <- system_name(t[4L])
    q <- precision(sys2,t[5L])
    target <- grid(sys2,q)
    code <- encode(sys2,q,fd((2*x+1)*target[1L],2*w),fd((2*y+1)*target[2L],2*h))
    return(if (code == "-") "OUT OF AREA" else code)
  }
  if (command == "RELATE") {
    sys2 <- system_name(t[3L])
    second <- decode(sys2,t[4L])
    target <- grid(sys2,second[1L])
    a <- second[2L]
    b <- second[3L]
    v <- target[1L]
    u <- target[2L]
    l1 <- x*v
    r1 <- (x+1)*v
    l2 <- a*w
    r2 <- (a+1)*w
    s1 <- y*u
    n1 <- (y+1)*u
    s2 <- b*h
    n2 <- (b+1)*h
    if (l1 == l2 && r1 == r2 && s1 == s2 && n1 == n2) return("EQUAL")
    if (l1 >= l2 && r1 <= r2 && s1 >= s2 && n1 <= n2) return("INSIDE")
    if (l2 >= l1 && r2 <= r1 && s2 >= s1 && n2 <= n1) return("CONTAINS")
    if (max(l1,l2) < min(r1,r2) && max(s1,s2) < min(n1,n2)) return("OVERLAP")
    latitude_touch <- max(s1,s2) <= min(n1,n2)
    date_line <- (x == 0 && a+1 == v) || (a == 0 && x+1 == w)
    if (latitude_touch && (max(l1,l2) <= min(r1,r2) || date_line)) return("TOUCH")
    return("DISJOINT")
  }
  second <- decode(sys,t[3L])
  if (command == "COMMON") {
    limit <- min(index,match(second[1L],precs[[sys]]))
    for (i in rev(seq_len(limit))) {
      a <- ancestor(sys,cell,precs[[sys]][i])
      if (all(a == ancestor(sys,second,precs[[sys]][i]))) return(cell_code(sys,a))
    }
    return("NONE")
  }
  if (p != second[1L]) return("MISMATCH")
  dx <- md(second[2L]-x,w)
  if (2*dx > w) dx <- dx-w
  dy <- second[3L]-y
  if (command == "STEPS") return(paste0("dx=",num(dx)," dy=",num(dy)))
  n <- max(abs(dx),abs(dy))
  if (n+1 > 100) return("TOO MANY")
  if (n == 0) return(cell_code(sys,cell))
  out <- character()
  for (i in 0:n) out <- c(out,encode(sys,p,md(x+fd(2*i*dx+n,2*n),w),y+fd(2*i*dy+n,2*n)))
  paste(out,collapse=" ")
}
input <- file("stdin",open="r")
count <- as.integer(readLines(input,n=1L))
for (i in seq_len(count)) {
  line <- readLines(input,n=1L)
  output <- tryCatch(execute(line),error=function(error) "INVALID")
  cat(output,"\n",sep="")
}
close(input)
