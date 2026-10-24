patterns <- c(
  NEW="iiii", OUTPUT="", INVERT="", BRIGHTNESS="i",
  CONTRAST="ii", THRESHOLD="i", LEVELS="ii", POSTERIZE="i",
  MAXVAL="i", FLIPH="", FLIPV="", ROTATE="i",
  CROP="iiii", PAD="ii", SCALE="ii", SHIFT="iii",
  TILE="ii", BLUR="", GAUSS="", SHARPEN="",
  CONVOLVE="iiiiiiiiii", SOBEL="", MEDIAN="", ERODE="", DILATE="",
  OPEN="", CLOSE="", GRADIENT="", LINE="iiiii", RECT="iiiii",
  CIRCLE="iiii", FLOOD="iii", HISTOGRAM="", EQUALIZE="", LABEL="i",
  DISTANCE="i", STATS="", REGION="iiii", DITHER="", ASCIIART="",
  STORE="n", RECALL="n", DROP="n", BLEND="nii", DIFF="n",
  PASTE="nii", SLOTS="", INFO="", UNDO="", REDO=""
)
imageless <- c("NEW","RECALL","DROP","SLOTS","INFO","UNDO","REDO")
slot_commands <- c("RECALL","DROP","BLEND","DIFF","PASTE")
neighbors4 <- matrix(c(0,-1,-1,0,1,0,0,1),ncol=2,byrow=TRUE)
shades <- strsplit("@#*+=~-:,.", "")[[1]]
kernels <- list(
  BLUR=list(c(1,1,1,1,1,1,1,1,1),9L),
  GAUSS=list(c(1,2,1,2,4,2,1,2,1,2,1),16L),
  SHARPEN=list(c(0,-1,0,-1,5,-1,0,-1,0),1L)
)

fault <- function(reason) {
  stop(structure(list(message=reason,call=NULL),
                 class=c("command_error","error","condition")))
}
check <- function(condition, reason="bad value") {
  if (!isTRUE(condition)) fault(reason)
}
clamp <- function(value, low, high) pmax(low,pmin(high,value))
within_limit <- function(...) all(abs(c(...)) <= 1000L)
picture <- function(w,h,m,p) list(w=as.integer(w),h=as.integer(h),
                                 m=as.integer(m),p=as.integer(p))
inside <- function(img,x,y) x>=0L && y>=0L && x<img$w && y<img$h
get_pixel <- function(img,x,y) img$p[y*img$w+x+1L]
with_pixels <- function(img,p) picture(img$w,img$h,img$m,p)
summary_text <- function(img) {
  paste0(img$w,"x",img$h," maxval ",img$m,
         " checksum ",sum(seq_along(img$p)*img$p))
}
transform_image <- function(img,w,h,f) {
  p <- integer(w*h)
  i <- 1L
  for (y in 0:(h-1L)) for (x in 0:(w-1L)) {
    p[i] <- f(x,y)
    i <- i+1L
  }
  picture(w,h,img$m,p)
}
crop_image <- function(img,x,y,w,h) {
  transform_image(img,w,h,function(i,j) get_pixel(img,x+i,y+j))
}
translate_image <- function(img,w,h,dx,dy,fill) {
  transform_image(img,w,h,function(x,y) {
    if(inside(img,x-dx,y-dy)) get_pixel(img,x-dx,y-dy) else fill
  })
}
neighborhood <- function(img,x,y) {
  p <- integer(9L)
  i <- 1L
  for(dy in -1:1) for(dx in -1:1) {
    p[i] <- get_pixel(img,clamp(x+dx,0L,img$w-1L),
                         clamp(y+dy,0L,img$h-1L))
    i <- i+1L
  }
  p
}
convolution <- function(img,weights,den) {
  transform_image(img,img$w,img$h,function(x,y) {
    clamp(sum(neighborhood(img,x,y)*weights)%/%den,0L,img$m)
  })
}
rank_filter <- function(img,index) {
  transform_image(img,img$w,img$h,function(x,y) {
    sort.int(neighborhood(img,x,y))[index+1L]
  })
}
sobel <- function(img) {
  transform_image(img,img$w,img$h,function(x,y) {
    q <- neighborhood(img,x,y)
    gx <- q[3L]+2L*q[6L]+q[9L]-q[1L]-2L*q[4L]-q[7L]
    gy <- q[7L]+2L*q[8L]+q[9L]-q[1L]-2L*q[2L]-q[3L]
    clamp(abs(gx)+abs(gy),0L,img$m)
  })
}
read_pgm <- function(lines) {
  stripped <- trimws(sub("#.*$","",lines))
  words <- unlist(strsplit(stripped," +"),use.names=FALSE)
  words <- words[nzchar(words)]
  check(length(words)>0L && words[1L]=="P2","bad magic")
  header <- function(i,upper,reason) {
    check(i<=length(words),"truncated header")
    check(grepl("^[0-9]+$",words[i]),"bad number")
    value <- as.integer(words[i])
    check(value>=1L && value<=upper,reason)
    value
  }
  w <- header(2L,64L,"bad size")
  h <- header(3L,64L,"bad size")
  m <- header(4L,255L,"bad maxval")
  values <- words[-seq_len(4L)]
  count <- w*h
  p <- integer(count)
  for(i in seq_len(count)) {
    x <- (i-1L)%%w
    y <- (i-1L)%/%w
    check(i<=length(values),sprintf("too few pixels (%d of %d)",length(values),count))
    check(grepl("^[0-9]+$",values[i]),sprintf("bad pixel at %d,%d",x,y))
    v <- as.integer(values[i])
    check(v<=m,sprintf("pixel out of range at %d,%d",x,y))
    p[i] <- v
  }
  check(length(values)<=count,
        sprintf("too many pixels (%d of %d)",length(values),count))
  picture(w,h,m,p)
}
line_points <- function(x0,y0,x1,y1) {
  dx <- abs(x1-x0)
  dy <- -abs(y1-y0)
  sx <- if(x0<x1) 1L else -1L
  sy <- if(y0<y1) 1L else -1L
  err <- dx+dy
  x <- x0
  y <- y0
  result <- list()
  repeat {
    result[[length(result)+1L]] <- c(x,y)
    if(x==x1 && y==y1) break
    twice <- 2L*err
    if(twice>=dy) { err <- err+dy; x <- x+sx }
    if(twice<=dx) { err <- err+dx; y <- y+sy }
  }
  do.call(rbind,result)
}
rectangle_points <- function(img,x,y,w,h,fill) {
  lo_x <- max(0L,x); hi_x <- min(img$w-1L,x+w-1L)
  lo_y <- max(0L,y); hi_y <- min(img$h-1L,y+h-1L)
  if(lo_x>hi_x || lo_y>hi_y) return(matrix(integer(0),ncol=2L))
  points <- as.matrix(expand.grid(lo_x:hi_x,lo_y:hi_y))
  if(!fill) {
    keep <- points[,1L]==x | points[,1L]==x+w-1L |
      points[,2L]==y | points[,2L]==y+h-1L
    points <- points[keep,,drop=FALSE]
  }
  points
}
circle_points <- function(cx,cy,radius) {
  a <- radius; b <- 0L; err <- 1L-radius
  points <- list()
  while(a>=b) {
    points[[length(points)+1L]] <- matrix(c(
      cx+a,cy+b, cx+b,cy+a, cx-b,cy+a, cx-a,cy+b,
      cx-a,cy-b, cx-b,cy-a, cx+b,cy-a, cx+a,cy-b
    ),ncol=2L,byrow=TRUE)
    b <- b+1L
    if(err<0L) {
      err <- err+2L*b+1L
    } else {
      a <- a-1L
      err <- err+2L*(b-a)+1L
    }
  }
  do.call(rbind,points)
}
disc_points <- function(img,outline) {
  rows <- split(outline[,1L],outline[,2L])
  points <- list()
  for(key in names(rows)) {
    y <- as.integer(key)
    if(y<0L || y>=img$h) next
    lo <- max(0L,min(rows[[key]]))
    hi <- min(img$w-1L,max(rows[[key]]))
    if(lo>hi) next
    points[[length(points)+1L]] <- cbind(lo:hi,rep.int(y,hi-lo+1L))
  }
  if(!length(points)) {
    matrix(integer(0),ncol=2L)
  } else {
    do.call(rbind,points)
  }
}
flood_points <- function(img,x,y) {
  wanted <- get_pixel(img,x,y)
  start <- y*img$w+x+1L
  seen <- rep(FALSE,length(img$p))
  seen[start] <- TRUE
  stack <- c(start)
  result <- integer(0)
  while(length(stack)) {
    index <- stack[length(stack)]
    stack <- stack[-length(stack)]
    result <- c(result,index)
    px <- (index-1L)%%img$w
    py <- (index-1L)%/%img$w
    for(k in seq_len(nrow(neighbors4))) {
      nx <- px+neighbors4[k,1L]; ny <- py+neighbors4[k,2L]
      if(!inside(img,nx,ny) || get_pixel(img,nx,ny)!=wanted) next
      other <- ny*img$w+nx+1L
      if(!seen[other]) {
        seen[other] <- TRUE
        stack <- c(stack,other)
      }
    }
  }
  cbind((result-1L)%%img$w,(result-1L)%/%img$w)
}
equalized <- function(img) {
  n <- length(img$p)
  cdf <- cumsum(tabulate(img$p+1L,nbins=img$m+1L))
  first <- cdf[min(img$p)+1L]
  if(first==n) return(with_pixels(img,img$p))
  with_pixels(img,(2L*(cdf[img$p+1L]-first)*img$m+n-first)%/%(2L*(n-first)))
}
components <- function(img,threshold) {
  seen <- rep(FALSE,length(img$p))
  groups <- list()
  for(start in seq_along(img$p)) {
    if(seen[start] || img$p[start]<threshold) next
    seen[start] <- TRUE
    stack <- c(start)
    group <- integer(0)
    while(length(stack)) {
      index <- stack[length(stack)]
      stack <- stack[-length(stack)]
      group <- c(group,index)
      x <- (index-1L)%%img$w; y <- (index-1L)%/%img$w
      for(dy in -1:1) for(dx in -1:1) {
        if(dx==0L && dy==0L) next
        nx <- x+dx; ny <- y+dy
        if(!inside(img,nx,ny)) next
        other <- ny*img$w+nx+1L
        if(!seen[other] && img$p[other]>=threshold) {
          seen[other] <- TRUE
          stack <- c(stack,other)
        }
      }
    }
    groups[[length(groups)+1L]] <- group
  }
  groups
}
component_text <- function(img,threshold,group) {
  x <- (group-1L)%%img$w
  y <- (group-1L)%/%img$w
  perimeter <- 0L
  for(i in seq_along(group)) {
    for(k in seq_len(nrow(neighbors4))) {
      nx <- x[i]+neighbors4[k,1L]; ny <- y[i]+neighbors4[k,2L]
      if(!inside(img,nx,ny) || get_pixel(img,nx,ny)<threshold) {
        perimeter <- perimeter+1L
        break
      }
    }
  }
  sprintf("area %d perimeter %d box %d %d %d %d center %d %d",
          length(group),perimeter,min(x),min(y),max(x),max(y),
          sum(x)%/%length(group),sum(y)%/%length(group))
}
distance_map <- function(img,threshold) {
  if(!any(img$p<threshold)) return(with_pixels(img,rep.int(img$m,length(img$p))))
  w <- img$w; h <- img$h
  dist <- ifelse(img$p<threshold,0L,w+h)
  for(y in 0:(h-1L)) for(x in 0:(w-1L)) {
    i <- y*w+x+1L
    if(x>0L) dist[i] <- min(dist[i],dist[i-1L]+1L)
    if(y>0L) dist[i] <- min(dist[i],dist[i-w]+1L)
  }
  for(y in (h-1L):0L) for(x in (w-1L):0L) {
    i <- y*w+x+1L
    if(x<w-1L) dist[i] <- min(dist[i],dist[i+1L]+1L)
    if(y<h-1L) dist[i] <- min(dist[i],dist[i+w]+1L)
  }
  with_pixels(img,pmin(dist,img$m))
}
statistics <- function(p,maxval) {
  ordered <- sort.int(p)
  count <- length(p)
  frequencies <- tabulate(p+1L,nbins=maxval+1L)
  sprintf("min %d max %d mean %d median %d mode %d",
          ordered[1L],ordered[count],sum(p)%/%count,
          ordered[(count-1L)%/%2L+1L],which.max(frequencies)-1L)
}
dithered <- function(img) {
  errors <- img$p
  p <- integer(length(errors))
  weights <- matrix(c(1,0,7, -1,1,3, 0,1,5, 1,1,1),ncol=3,byrow=TRUE)
  for(y in 0:(img$h-1L)) for(x in 0:(img$w-1L)) {
    i <- y*img$w+x+1L
    old <- errors[i]
    next_value <- if(2L*old>=img$m) img$m else 0L
    p[i] <- next_value
    diff <- old-next_value
    for(j in seq_len(nrow(weights))) {
      nx <- x+weights[j,1L]; ny <- y+weights[j,2L]
      if(inside(img,nx,ny)) {
        k <- ny*img$w+nx+1L
        errors[k] <- errors[k]+diff*weights[j,3L]%/%16L
      }
    }
  }
  with_pixels(img,p)
}

new_editor <- function() {
  editor <- new.env(parent=emptyenv())
  editor$current <- NULL
  editor$undo <- list()
  editor$redo <- list()
  editor$slots <- list()
  editor$output <- character(0)
  editor
}
emit <- function(e,line) e$output <- c(e$output,as.character(line))
replace_image <- function(e,img,label) {
  e$current <- img
  e$undo <- list()
  e$redo <- list()
  emit(e,paste(label,summary_text(img)))
}
commit_image <- function(e,img,painted=NULL) {
  e$undo[[length(e$undo)+1L]] <- e$current
  e$redo <- list()
  e$current <- img
  text <- paste("ok",summary_text(img))
  if(!is.null(painted)) text <- paste(text,"painted",painted)
  emit(e,text)
}
paint_image <- function(e,points,value) {
  img <- e$current
  if(!length(points)) {
    commit_image(e,img,0L)
    return()
  }
  indices <- integer(0)
  for(i in seq_len(nrow(points))) {
    x <- points[i,1L]; y <- points[i,2L]
    if(inside(img,x,y)) indices <- c(indices,y*img$w+x+1L)
  }
  indices <- unique(indices)
  p <- img$p
  p[indices] <- value
  commit_image(e,with_pixels(img,p),length(indices))
}
checked_crop <- function(e,a) {
  x<-a[1L];y<-a[2L];w<-a[3L];h<-a[4L]
  img<-e$current
  check(x>=0L && y>=0L && w>=1L && h>=1L)
  check(x+w<=img$w && y+h<=img$h)
  a
}
matching_slot <- function(e,name) {
  slot <- e$slots[[name]]
  img <- e$current
  check(slot$w==img$w && slot$h==img$h,"size mismatch")
  check(slot$m==img$m,"maxval mismatch")
  slot
}
load_command <- function(e,data) {
  tryCatch(replace_image(e,read_pgm(data),"loaded"),
           command_error=function(err) emit(e,paste0("error: load: ",err$message)))
}
execute <- function(e,words) {
  tryCatch({
    name <- words[1L]
    check(name %in% names(patterns),paste("unknown command",name))
    pattern <- patterns[[name]]
    given <- words[-1L]
    fill <- name %in% c("RECT","CIRCLE") &&
      length(given)==nchar(pattern)+1L && tail(given,1L)=="FILL"
    if(fill) given <- head(given,-1L)
    check(length(given)==nchar(pattern),"bad arguments")
    nums <- integer(0)
    slot <- ""
    for(i in seq_along(given)) {
      if(substr(pattern,i,i)=="i") {
        check(grepl("^(0|-?[1-9][0-9]{0,6})$",given[i]),"bad arguments")
        nums <- c(nums,as.integer(given[i]))
      } else {
        check(grepl("^[a-z]{1,8}$",given[i]),"bad arguments")
        slot <- given[i]
      }
    }
    if(!(name %in% imageless)) check(!is.null(e$current),"no image")
    if(name %in% slot_commands) check(!is.null(e$slots[[slot]]),paste("no slot",slot))
    run_command(e,name,nums,slot,fill)
  },command_error=function(err) emit(e,paste0("error: ",err$message)))
}
run_command <- function(e,name,a,slot,fill) {
  img <- e$current
  m <- if(is.null(img)) 0L else img$m
  if(name=="NEW") {
    w<-a[1L]; h<-a[2L]; maxval<-a[3L]; v<-a[4L]
    check(w>=1L && w<=64L && h>=1L && h<=64L)
    check(maxval>=1L && maxval<=255L && v>=0L && v<=maxval)
    replace_image(e,picture(w,h,maxval,rep.int(v,w*h)),"created")
  } else if(name=="OUTPUT") {
    emit(e,"P2"); emit(e,paste(img$w,img$h)); emit(e,as.character(m))
    for(y in 0:(img$h-1L)) {
      emit(e,paste(img$p[(y*img$w+1L):((y+1L)*img$w)],collapse=" "))
    }
  } else if(name=="INVERT") {
    commit_image(e,with_pixels(img,m-img$p))
  } else if(name=="BRIGHTNESS") {
    check(a[1L]>=-255L && a[1L]<=255L)
    commit_image(e,with_pixels(img,clamp(img$p+a[1L],0L,m)))
  } else if(name=="CONTRAST") {
    num<-a[1L];den<-a[2L]
    check(num>=0L && num<=100L && den>=1L && den<=100L)
    center <- (m+1L)%/%2L
    commit_image(e,with_pixels(img,clamp(center+(img$p-center)*num%/%den,0L,m)))
  } else if(name=="THRESHOLD") {
    check(a[1L]>=0L && a[1L]<=m)
    commit_image(e,with_pixels(img,ifelse(img$p>=a[1L],m,0L)))
  } else if(name=="LEVELS") {
    lo<-a[1L];hi<-a[2L]
    check(lo>=0L && lo<hi && hi<=m)
    commit_image(e,with_pixels(img,clamp((img$p-lo)*m%/%(hi-lo),0L,m)))
  } else if(name=="POSTERIZE") {
    levels<-a[1L];check(levels>=2L && levels<=m+1L)
    commit_image(e,with_pixels(img,(img$p*levels%/%(m+1L))*m%/%(levels-1L)))
  } else if(name=="MAXVAL") {
    maximum<-a[1L];check(maximum>=1L && maximum<=255L)
    commit_image(e,picture(img$w,img$h,maximum,
                           (2L*img$p*maximum+m)%/%(2L*m)))
  } else if(name=="FLIPH") {
    commit_image(e,transform_image(img,img$w,img$h,function(x,y) get_pixel(img,img$w-1L-x,y)))
  } else if(name=="FLIPV") {
    commit_image(e,transform_image(img,img$w,img$h,function(x,y) get_pixel(img,x,img$h-1L-y)))
  } else if(name=="ROTATE") {
    angle<-a[1L];check(angle %in% c(90L,180L,270L))
    w<-img$w;h<-img$h
    if(angle==180L) {
      result<-transform_image(img,w,h,function(x,y)get_pixel(img,w-1L-x,h-1L-y))
    } else if(angle==90L) {
      result<-transform_image(img,h,w,function(x,y)get_pixel(img,y,h-1L-x))
    } else {
      result<-transform_image(img,h,w,function(x,y)get_pixel(img,w-1L-y,x))
    }
    commit_image(e,result)
  } else if(name=="CROP") {
    a<-checked_crop(e,a);commit_image(e,crop_image(img,a[1L],a[2L],a[3L],a[4L]))
  } else if(name=="PAD") {
    n<-a[1L];v<-a[2L];check(n>=1L && v>=0L && v<=m)
    w<-img$w+2L*n;h<-img$h+2L*n
    check(w<=64L && h<=64L,"too large")
    commit_image(e,translate_image(img,w,h,n,n,v))
  } else if(name=="SCALE") {
    num<-a[1L];den<-a[2L]
    check(num>=1L && num<=16L && den>=1L && den<=16L)
    w<-img$w*num%/%den;h<-img$h*num%/%den
    check(w>0L && h>0L,"too small");check(w<=64L && h<=64L,"too large")
    commit_image(e,transform_image(img,w,h,function(x,y) {
      get_pixel(img,(2L*x+1L)*den%/%(2L*num),(2L*y+1L)*den%/%(2L*num))
    }))
  } else if(name=="SHIFT") {
    dx<-a[1L];dy<-a[2L];v<-a[3L]
    check(within_limit(dx,dy) && v>=0L && v<=m)
    commit_image(e,translate_image(img,img$w,img$h,dx,dy,v))
  } else if(name=="TILE") {
    nx<-a[1L];ny<-a[2L];check(nx>=1L && ny>=1L)
    w<-img$w*nx;h<-img$h*ny
    check(w<=64L && h<=64L,"too large")
    commit_image(e,transform_image(img,w,h,function(x,y)get_pixel(img,x%%img$w,y%%img$h)))
  } else if(name %in% c("BLUR","GAUSS","SHARPEN")) {
    kernel<-kernels[[name]];commit_image(e,convolution(img,kernel[[1L]],kernel[[2L]]))
  } else if(name=="CONVOLVE") {
    check(all(a[1:9]>=-16L & a[1:9]<=16L) && a[10L]>=1L && a[10L]<=256L)
    commit_image(e,convolution(img,a[1:9],a[10L]))
  } else if(name=="SOBEL") {
    commit_image(e,sobel(img))
  } else if(name %in% c("MEDIAN","ERODE","DILATE")) {
    ranks<-c(MEDIAN=4L,ERODE=0L,DILATE=8L)
    commit_image(e,rank_filter(img,ranks[[name]]))
  } else if(name=="OPEN") {
    commit_image(e,rank_filter(rank_filter(img,0L),8L))
  } else if(name=="CLOSE") {
    commit_image(e,rank_filter(rank_filter(img,8L),0L))
  } else if(name=="GRADIENT") {
    commit_image(e,with_pixels(img,rank_filter(img,8L)$p-rank_filter(img,0L)$p))
  } else if(name=="LINE") {
    check(within_limit(a[1:4]) && a[5L]>=0L && a[5L]<=m)
    paint_image(e,line_points(a[1L],a[2L],a[3L],a[4L]),a[5L])
  } else if(name=="RECT") {
    x<-a[1L];y<-a[2L];w<-a[3L];h<-a[4L];v<-a[5L]
    check(within_limit(x,y) && w>=1L && w<=1000L && h>=1L && h<=1000L && v>=0L && v<=m)
    paint_image(e,rectangle_points(img,x,y,w,h,fill),v)
  } else if(name=="CIRCLE") {
    x<-a[1L];y<-a[2L];r<-a[3L];v<-a[4L]
    check(within_limit(x,y) && r>=0L && r<=1000L && v>=0L && v<=m)
    points<-circle_points(x,y,r)
    paint_image(e,if(fill) disc_points(img,points) else points,v)
  } else if(name=="FLOOD") {
    x<-a[1L];y<-a[2L];v<-a[3L]
    check(inside(img,x,y) && v>=0L && v<=m)
    paint_image(e,flood_points(img,x,y),v)
  } else if(name=="HISTOGRAM") {
    bins<-(0:m)*16L%/%(m+1L)
    counts<-tabulate(img$p*16L%/%(m+1L)+1L,nbins=16L)
    top<-max(counts)
    for(b in 0:15) {
      values<-which(bins==b)-1L
      if(!length(values)) next
      bar<-paste(rep.int("#",counts[b+1L]*32L%/%top),collapse="")
      emit(e,sprintf("%3d-%3d %4d |%s",min(values),max(values),counts[b+1L],bar))
    }
  } else if(name=="EQUALIZE") {
    commit_image(e,equalized(img))
  } else if(name=="LABEL") {
    check(a[1L]>=0L && a[1L]<=m)
    groups<-components(img,a[1L])
    emit(e,paste("labels",length(groups)))
    for(i in seq_along(groups)) emit(e,paste("label",i,component_text(img,a[1L],groups[[i]])))
  } else if(name=="DISTANCE") {
    check(a[1L]>=0L && a[1L]<=m)
    commit_image(e,distance_map(img,a[1L]))
  } else if(name=="STATS") {
    emit(e,statistics(img$p,m))
  } else if(name=="REGION") {
    a<-checked_crop(e,a)
    emit(e,statistics(crop_image(img,a[1L],a[2L],a[3L],a[4L])$p,m))
  } else if(name=="DITHER") {
    commit_image(e,dithered(img))
  } else if(name=="ASCIIART") {
    for(y in 0:(img$h-1L)) {
      row<-img$p[(y*img$w+1L):((y+1L)*img$w)]
      emit(e,paste(shades[row*10L%/%(m+1L)+1L],collapse=""))
    }
  } else if(name=="STORE") {
    e$slots[[slot]]<-img;emit(e,paste("stored",slot,summary_text(img)))
  } else if(name=="RECALL") {
    replace_image(e,e$slots[[slot]],paste("recalled",slot))
  } else if(name=="DROP") {
    e$slots[[slot]]<-NULL;emit(e,paste("dropped",slot))
  } else if(name=="BLEND") {
    num<-a[1L];den<-a[2L];check(num>=0L && num<=den && den>=1L && den<=100L)
    other<-matching_slot(e,slot)
    commit_image(e,with_pixels(img,(img$p*(den-num)+other$p*num)%/%den))
  } else if(name=="DIFF") {
    other<-matching_slot(e,slot)
    commit_image(e,with_pixels(img,abs(img$p-other$p)))
  } else if(name=="PASTE") {
    x<-a[1L];y<-a[2L];check(within_limit(x,y))
    other<-e$slots[[slot]]
    check(other$m==m,"maxval mismatch")
    p<-img$p;painted<-0L
    for(j in 0:(other$h-1L)) for(i in 0:(other$w-1L)) {
      if(!inside(img,x+i,y+j)) next
      p[(y+j)*img$w+x+i+1L]<-get_pixel(other,i,j)
      painted<-painted+1L
    }
    commit_image(e,with_pixels(img,p),painted)
  } else if(name=="SLOTS") {
    if(!length(e$slots)) emit(e,"no slots")
    for(key in sort(names(e$slots))) emit(e,paste(key,summary_text(e$slots[[key]])))
  } else if(name=="INFO") {
    s<-if(is.null(img)) "none" else summary_text(img)
    emit(e,paste("image",s,"undo",length(e$undo),"redo",length(e$redo),"slots",length(e$slots)))
  } else if(name=="UNDO") {
    check(length(e$undo)>0L,"nothing to undo")
    e$redo[[length(e$redo)+1L]]<-e$current
    e$current<-e$undo[[length(e$undo)]]
    e$undo[[length(e$undo)]]<-NULL
    emit(e,paste("undo",summary_text(e$current)))
  } else if(name=="REDO") {
    check(length(e$redo)>0L,"nothing to redo")
    e$undo[[length(e$undo)+1L]]<-e$current
    e$current<-e$redo[[length(e$redo)]]
    e$redo[[length(e$redo)]]<-NULL
    emit(e,paste("redo",summary_text(e$current)))
  }
}

lines <- readLines(file("stdin"),warn=FALSE)
count <- as.integer(lines[1L])
index <- 2L
editor <- new_editor()
for(i in seq_len(count)) {
  words <- strsplit(lines[index]," ",fixed=TRUE)[[1L]]
  index <- index+1L
  if(words[1L]=="LOAD") {
    n <- as.integer(words[2L])
    load_command(editor,lines[index:(index+n-1L)])
    index <- index+n
  } else {
    execute(editor,words)
  }
}
cat(paste(editor$output,collapse="\n"),"\n",sep="")
