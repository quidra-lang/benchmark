builtin_names <- strsplit("black maroon green olive navy purple teal silver gray red lime yellow blue magenta cyan white orange pink brown gold coral salmon violet indigo"," ")[[1]]
builtin_hex <- strsplit("000000 800000 008000 808000 000080 800080 008080 C0C0C0 808080 FF0000 00FF00 FFFF00 0000FF FF00FF 00FFFF FFFFFF FFA500 FFC0CB A52A2A FFD700 FF7F50 FA8072 EE82EE 4B0082"," ")[[1]]
builtin_colors <- lapply(builtin_hex,function(text) vapply(c(1,3,5),function(i) strtoi(substr(text,i,i+1),16),integer(1)))
signatures <- c(
    "PARSE"="c",
    "DEFINE"="name c",
    "UNDEFINE"="name",
    "LIST"="",
    "HSL"="c",
    "HSV"="c",
    "HWB"="c",
    "CMYK"="c",
    "YCBCR"="c",
    "YIQ"="c",
    "FROMHSL"="0:359 0:100 0:100",
    "FROMHSV"="0:359 0:100 0:100",
    "FROMHWB"="0:359 0:100 0:100",
    "FROMCMYK"="0:100 0:100 0:100 0:100",
    "FROMYCBCR"="0:255 0:255 0:255",
    "FROMYIQ"="0:255 -255:255 -255:255",
    "RGB565"="c",
    "FROM565"="code",
    "ANSI"="c",
    "FROMANSI"="0:255",
    "WEBSAFE"="c",
    "GRAY"="c gray",
    "INVERT"="c",
    "MIX"="c c 0:100",
    "MIXHSL"="c c 0:100",
    "GRADIENT"="c c 2:16",
    "TINTS"="c 1:10",
    "SHADES"="c 1:10",
    "TONES"="c 1:10",
    "BLEND"="blend c c",
    "ALPHA"="c 0:100 c 0:100",
    "SIMULATE"="c simulation",
    "ROTATE"="c -720:720",
    "COMPLEMENT"="c",
    "TRIADIC"="c",
    "TETRADIC"="c",
    "SPLITCOMP"="c",
    "ANALOGOUS"="c 1:6 1:60",
    "LIGHTEN"="c 0:100",
    "DARKEN"="c 0:100",
    "SATURATE"="c 0:100",
    "DESATURATE"="c 0:100",
    "NEAREST"="c",
    "DISTANCE"="c c",
    "CONTRAST"="c c",
    "ACCESSIBLE"="c c",
    "DESCRIBE"="c",
    "RANDOM"="1:999999999 1:16"
)
keywords <- list(
    gray=strsplit("LUMA AVERAGE LIGHTNESS HSP"," ")[[1]],
    blend=strsplit("MULTIPLY SCREEN OVERLAY HARDLIGHT SOFTLIGHT DARKEN LIGHTEN DIFFERENCE EXCLUSION ADD SUBTRACT COLORDODGE COLORBURN HUE SATURATION COLOR LUMINOSITY"," ")[[1]],
    simulation=strsplit("PROTANOPIA DEUTERANOPIA TRITANOPIA ACHROMATOPSIA"," ")[[1]])

require_valid <- function(condition) {
    if (!isTRUE(condition)) stop("INVALID",call.=FALSE)
}

round_ratio <- function(n,d) (2*n+d) %/% (2*d)

away_ratio <- function(n,d) ifelse(n < 0,-round_ratio(-n,d),round_ratio(n,d))

byte_clamp <- function(x) pmin(255,pmax(0,x))

hex_color <- function(color) sprintf("#%02X%02X%02X",as.integer(color[1]),as.integer(color[2]),as.integer(color[3]))

color_sequence <- function(colors) paste(vapply(colors,hex_color,character(1)),collapse=" ")

color_distance <- function(a,b) sum((a-b)^2)

integer_arg <- function(text,low,high) {
    require_valid(grepl("^-?[0-9]{1,9}$",text))
    value <- as.numeric(text)
    require_valid(value >= low && value <= high)
    value
}

parse_color <- function(text,registry) {
    if (grepl("^#[0-9a-fA-F]{6}$",text)) {
        return(vapply(c(2,4,6),function(i) strtoi(substr(text,i,i+1),16),integer(1)))
    }
    if (grepl("^#[0-9a-fA-F]{3}$",text)) {
        return(vapply(2:4,function(i) 17*strtoi(substr(text,i,i),16),numeric(1)))
    }
    if (grepl("^rgb\\([0-9]{1,3},[0-9]{1,3},[0-9]{1,3}\\)$",text)) {
        color <- as.numeric(strsplit(substr(text,5,nchar(text)-1),",",fixed=TRUE)[[1]])
        require_valid(all(color <= 255))
        return(color)
    }
    index <- match(text,builtin_names)
    if (!is.na(index)) return(builtin_colors[[index]])
    require_valid(text %in% names(registry$colors))
    registry$colors[[text]]
}

typed_arg <- function(text,kind,registry) {
    if (kind == "c") return(parse_color(text,registry))
    if (kind == "name") {
        require_valid(grepl("^[a-z]{1,12}$",text))
        return(text)
    }
    if (kind == "code") {
        require_valid(grepl("^0x[0-9a-fA-F]{4}$",text))
        return(strtoi(substring(text,3),16))
    }
    if (kind %in% names(keywords)) {
        require_valid(text %in% keywords[[kind]])
        return(text)
    }
    bounds <- as.numeric(strsplit(kind,":",fixed=TRUE)[[1]])
    integer_arg(text,bounds[1],bounds[2])
}

hue <- function(color) {
    r <- color[1]
    g <- color[2]
    b <- color[3]
    high <- max(color)
    delta <- high-min(color)
    if (delta == 0) return(0)
    if (high == r) {
        numerator <- 60*(g-b)
        if (numerator < 0) numerator <- numerator+360*delta
    } else if (high == g) {
        numerator <- 60*(b-r)+120*delta
    } else {
        numerator <- 60*(r-g)+240*delta
    }
    round_ratio(numerator,delta) %% 360
}

hsl <- function(color) {
    high <- max(color)
    low <- min(color)
    delta <- high-low
    saturation <- if (delta == 0) 0 else round_ratio(100*delta,255-abs(high+low-255))
    c(hue(color),saturation,round_ratio(100*(high+low),510))
}
base60 <- function(h) {
    sector <- h %/% 60
    fraction <- h %% 60
    x <- if (sector %% 2 == 0) fraction else 60-fraction
    list(c(60,x,0),c(x,60,0),c(0,60,x),c(0,x,60),c(x,0,60),c(60,0,x))[[sector+1]]
}

from_hsl <- function(h,s,l) {
    chroma <- (100-abs(2*l-100))*s
    offset <- 6000*l-30*chroma
    round_ratio(255*(base60(h)*chroma+offset),600000)
}

model_values <- function(model,color) {
    r <- color[1]
    g <- color[2]
    b <- color[3]
    high <- max(color)
    low <- min(color)
    if (model == "HSL") return(hsl(color))
    if (model == "HSV") {
        saturation <- if (high == 0) 0 else round_ratio(100*(high-low),high)
        return(c(hue(color),saturation,round_ratio(100*high,255)))
    }
    if (model == "HWB") return(c(hue(color),round_ratio(100*low,255),round_ratio(100*(255-high),255)))
    if (model == "CMYK") {
        if (high == 0) return(c(0,0,0,100))
        return(c(round_ratio(100*(high-color),high),round_ratio(100*(255-high),255)))
    }
    if (model == "YCBCR") {
        return(byte_clamp(c(
            round_ratio(299*r+587*g+114*b,1000),
            round_ratio(128000-169*r-331*g+500*b,1000),
            round_ratio(128000+500*r-419*g-81*b,1000))))
    }
    c(
        round_ratio(299*r+587*g+114*b,1000),
        round_ratio(596*r-274*g-322*b,1000),
        round_ratio(211*r-523*g+312*b,1000))
}

model_text <- function(model,color) {
    values <- model_values(model,color)
    if (model %in% c("HSL","HSV","HWB")) return(sprintf("%s(%d,%d%%,%d%%)",tolower(model),values[1],values[2],values[3]))
    if (model == "CMYK") return(paste0("cmyk(",paste0(values,"%",collapse=","),")"))
    paste0(tolower(model),"(",paste(values,collapse=","),")")
}

ansi_color <- function(number) {
    if (number < 16) return(builtin_colors[[number+1]])
    if (number >= 232) return(rep(8+10*(number-232),3))
    value <- number-16
    levels <- c(0,95,135,175,215,255)
    levels[c(value %/% 36+1,(value %/% 6) %% 6+1,value %% 6+1)]
}

root_ratio <- function(n,d) {
    low <- 0
    high <- 1
    while (d*high*high <= n) {
        high <- high*2
    }
    while (high-low > 1) {
        middle <- (low+high) %/% 2
        if (d*middle*middle <= n) {
            low <- middle
        } else {
            high <- middle
        }
    }
    low
}

nearest_index <- function(color,colors) which.min(vapply(colors,function(other) color_distance(color,other),numeric(1)))

contrast <- function(a,b) {
    luminance <- function(color) sum(c(2126,7152,722)*color^2)
    y1 <- luminance(a)
    y2 <- luminance(b)
    high <- max(y1,y2)+32512500
    low <- min(y1,y2)+32512500
    if (high >= 7*low) {
        verdict <- "AAA"
    } else if (2*high >= 9*low) {
        verdict <- "AA"
    } else {
        verdict <- "FAIL"
    }
    list(ratio=round_ratio(100*high,low),verdict=verdict)
}

contrast_text <- function(a,b) {
    result <- contrast(a,b)
    sprintf("%d.%02d %s",result$ratio %/% 100,result$ratio %% 100,result$verdict)
}

gradient <- function(a,b,n) lapply(0:(n-1),function(i) a+away_ratio((b-a)*i,n-1))

mean_color <- function(colors) round_ratio(Reduce(`+`,colors),length(colors))

widths <- function(colors) {
    values <- do.call(rbind,colors)
    apply(values,2,max)-apply(values,2,min)
}

palette <- function(colors,k) {
    boxes <- list(colors)
    while (length(boxes) < k) {
        selected <- 0
        best_width <- -1
        for (i in seq_along(boxes)) {
            if (length(boxes[[i]]) >= 2) {
                width <- max(widths(boxes[[i]]))
                if (width > best_width) {
                    selected <- i
                    best_width <- width
                }
            }
        }
        box <- boxes[[selected]]
        axis <- which.max(widths(box))
        indices <- order(vapply(box,function(color) color[axis],numeric(1)),seq_along(box))
        ordered <- box[indices]
        middle <- length(box) %/% 2
        left <- if (selected > 1) boxes[seq_len(selected-1)] else list()
        right <- if (selected < length(boxes)) boxes[(selected+1):length(boxes)] else list()
        boxes <- c(left,list(ordered[seq_len(middle)],ordered[(middle+1):length(box)]),right)
    }
    boxes
}

blend_component <- function(mode,x,y) {
    multiply <- (x*y) %/% 255
    screen <- 255-((255-x)*(255-y)) %/% 255
    if (mode == "MULTIPLY") return(multiply)
    if (mode == "SCREEN") return(screen)
    if (mode %in% c("OVERLAY","HARDLIGHT")) {
        lower <- if (mode == "OVERLAY") x < 128 else y < 128
        return(if (lower) (2*x*y) %/% 255 else 255-(2*(255-x)*(255-y)) %/% 255)
    }
    if (mode == "SOFTLIGHT") return(((255-x)*multiply+x*screen) %/% 255)
    if (mode == "DARKEN") return(min(x,y))
    if (mode == "LIGHTEN") return(max(x,y))
    if (mode == "DIFFERENCE") return(abs(x-y))
    if (mode == "EXCLUSION") return(x+y-(2*x*y) %/% 255)
    if (mode == "ADD") return(min(255,x+y))
    if (mode == "SUBTRACT") return(max(0,x-y))
    if (mode == "COLORDODGE") return(if (y == 255) 255 else min(255,(255*x) %/% (255-y)))
    if (y == 0) 0 else max(0,255-(255*(255-x)) %/% y)
}

execute <- function(command,raw,registry) {
    if (command %in% c("PALETTE","KMEANS","BEST","SORT","DITHER")) {
        if (command %in% c("PALETTE","KMEANS")) {
            require_valid(length(raw) >= 2 && length(raw) <= 33)
            k <- integer_arg(raw[1],1,length(raw)-1)
            args <- list(k,lapply(raw[-1],parse_color,registry))
        } else {
            require_valid(length(raw) >= (if (command == "BEST") 2 else 1) && length(raw) <= (if (command == "BEST") 33 else 32))
            args <- list(lapply(raw,parse_color,registry))
        }
    } else {
        require_valid(command %in% names(signatures))
        kinds <- if (signatures[command] == "") character(0) else strsplit(signatures[command]," ",fixed=TRUE)[[1]]
        require_valid(length(raw) == length(kinds))
        args <- lapply(seq_along(raw),function(i) typed_arg(raw[i],kinds[i],registry))
    }
    if (command == "DEFINE") {
        name <- args[[1]]
        color <- args[[2]]
        require_valid(!name %in% builtin_names)
        if (!name %in% names(registry$colors)) registry$order <- c(registry$order,name)
        registry$colors[[name]] <- color
        return(paste(name,hex_color(color)))
    }
    if (command == "UNDEFINE") {
        name <- args[[1]]
        require_valid(name %in% names(registry$colors))
        registry$colors[[name]] <- NULL
        registry$order <- registry$order[registry$order != name]
        return(paste(name,"removed"))
    }
    if (command == "LIST") {
        if (length(registry$colors) == 0) return("NONE")
        return(paste(vapply(sort(names(registry$colors),method="radix"),function(name) paste0(name,"=",hex_color(registry$colors[[name]])),character(1)),collapse=" "))
    }
    if (command %in% c("PARSE","NEAREST")) {
        color <- args[[1]]
        names <- c(builtin_names,registry$order)
        colors <- c(builtin_colors,registry$colors[registry$order])
        if (command == "NEAREST") {
            i <- nearest_index(color,colors)
            return(sprintf("%s %s %d",names[i],hex_color(colors[[i]]),color_distance(color,colors[[i]])))
        }
        exact <- which(vapply(colors,function(other) all(other == color),logical(1)))
        parts <- c(hex_color(color),paste0("rgb(",paste(color,collapse=","),")"))
        parts <- c(parts,vapply(c("HSL","HSV","HWB","CMYK","YCBCR","YIQ"),function(model) model_text(model,color),character(1)))
        return(paste(c(parts,if (length(exact) == 0) "-" else names[exact[1]]),collapse=" "))
    }
    if (command %in% c("HSL","HSV","HWB","CMYK","YCBCR","YIQ")) return(model_text(command,args[[1]]))
    if (command == "FROMHSL") {
        result <- do.call(from_hsl,args)
    } else if (command == "FROMHSV") {
        h <- args[[1]]
        s <- args[[2]]
        v <- args[[3]]
        chroma <- v*s
        result <- round_ratio(255*(base60(h)*chroma+6000*v-60*chroma),600000)
    } else if (command == "FROMHWB") {
        h <- args[[1]]
        w <- args[[2]]
        k <- args[[3]]
        if (w+k >= 100) {
            result <- rep(round_ratio(255*w,w+k),3)
        } else {
            result <- round_ratio(255*(base60(h)*(100-w-k)+60*w),6000)
        }
    } else if (command == "FROMCMYK") {
        result <- vapply(1:3,function(i) round_ratio(255*(100-args[[i]])*(100-args[[4]]),10000),numeric(1))
    } else if (command == "FROMYCBCR") {
        y <- args[[1]]
        cb <- args[[2]]
        cr <- args[[3]]
        result <- byte_clamp(round_ratio(c(
            1000*y+1402*(cr-128),
            1000*y-344*(cb-128)-714*(cr-128),
            1000*y+1772*(cb-128)),1000))
    } else if (command == "FROMYIQ") {
        y <- args[[1]]
        i <- args[[2]]
        q <- args[[3]]
        result <- byte_clamp(round_ratio(c(
            1000*y+956*i+619*q,
            1000*y-272*i-647*q,
            1000*y-1106*i+1703*q),1000))
    } else if (command == "RGB565") {
        color <- args[[1]]
        value <- 2048*round_ratio(31*color[1],255)+32*round_ratio(63*color[2],255)+round_ratio(31*color[3],255)
        return(sprintf("0x%04X",as.integer(value)))
    } else if (command == "FROM565") {
        value <- args[[1]]
        result <- c(round_ratio(255*(value %/% 2048),31),round_ratio(255*((value %/% 32) %% 64),63),round_ratio(255*(value %% 32),31))
    } else if (command == "ANSI") {
        colors <- lapply(16:255,ansi_color)
        i <- nearest_index(args[[1]],colors)
        return(sprintf("%d %s %d",i+15,hex_color(colors[[i]]),color_distance(args[[1]],colors[[i]])))
    } else if (command == "FROMANSI") {
        result <- ansi_color(args[[1]])
    } else if (command == "WEBSAFE") {
        result <- 51*round_ratio(args[[1]],51)
    } else if (command == "GRAY") {
        color <- args[[1]]
        method <- args[[2]]
        if (method == "LUMA") {
            value <- round_ratio(sum(c(299,587,114)*color),1000)
        } else if (method == "AVERAGE") {
            value <- round_ratio(sum(color),3)
        } else if (method == "LIGHTNESS") {
            value <- round_ratio(max(color)+min(color),2)
        } else {
            value <- root_ratio(sum(c(299,587,114)*color^2),1000)
        }
        result <- rep(value,3)
    } else if (command == "INVERT") {
        result <- 255-args[[1]]
    } else if (command == "MIX") {
        a <- args[[1]]
        b <- args[[2]]
        p <- args[[3]]
        result <- round_ratio(a*(100-p)+b*p,100)
    } else if (command == "MIXHSL") {
        first <- hsl(args[[1]])
        second <- hsl(args[[2]])
        p <- args[[3]]
        delta <- (second[1]-first[1]) %% 360
        if (delta > 180) delta <- delta-360
        result <- from_hsl(
            (first[1]+away_ratio(delta*p,100)) %% 360,
            first[2]+away_ratio((second[2]-first[2])*p,100),
            first[3]+away_ratio((second[3]-first[3])*p,100))
    } else if (command == "GRADIENT") {
        return(color_sequence(do.call(gradient,args)))
    } else if (command %in% c("TINTS","SHADES","TONES")) {
        n <- args[[2]]
        target <- rep(switch(command,TINTS=255,SHADES=0,TONES=128),3)
        return(color_sequence(gradient(args[[1]],target,n+2)[2:(n+1)]))
    } else if (command == "BLEND") {
        mode <- args[[1]]
        a <- args[[2]]
        b <- args[[3]]
        if (mode %in% c("HUE","SATURATION","COLOR","LUMINOSITY")) {
            first <- hsl(a)
            second <- hsl(b)
            values <- switch(mode,
                HUE=c(second[1],first[2],first[3]),
                SATURATION=c(first[1],second[2],first[3]),
                COLOR=c(second[1],second[2],first[3]),
                LUMINOSITY=c(first[1],first[2],second[3]))
            result <- from_hsl(values[1],values[2],values[3])
        } else {
            result <- vapply(1:3,function(i) blend_component(mode,a[i],b[i]),numeric(1))
        }
    } else if (command == "ALPHA") {
        a <- args[[1]]
        p <- args[[2]]
        b <- args[[3]]
        q <- args[[4]]
        opacity <- 100*p+q*(100-p)
        result <- if (opacity == 0) c(0,0,0) else round_ratio(100*p*a+q*(100-p)*b,opacity)
        return(sprintf("%s %d%%",hex_color(result),round_ratio(opacity,100)))
    } else if (command == "SIMULATE") {
        matrices <- list(
            PROTANOPIA=matrix(c(567,433,0,558,442,0,0,242,758),3,byrow=TRUE),
            DEUTERANOPIA=matrix(c(625,375,0,700,300,0,0,300,700),3,byrow=TRUE),
            TRITANOPIA=matrix(c(950,50,0,0,433,567,0,475,525),3,byrow=TRUE),
            ACHROMATOPSIA=matrix(rep(c(299,587,114),3),3,byrow=TRUE))
        result <- round_ratio(as.numeric(matrices[[args[[2]]]] %*% args[[1]]),1000)
    } else if (command %in% c("ROTATE","COMPLEMENT","TRIADIC","TETRADIC","SPLITCOMP","ANALOGOUS")) {
        values <- hsl(args[[1]])
        if (command == "ROTATE") {
            offsets <- args[[2]]
        } else if (command == "ANALOGOUS") {
            offsets <- setdiff((-args[[2]]):args[[2]],0)*args[[3]]
        } else {
            offsets <- switch(command,COMPLEMENT=180,TRIADIC=c(120,240),TETRADIC=c(90,180,270),SPLITCOMP=c(150,210))
        }
        return(color_sequence(lapply(offsets,function(d) from_hsl((values[1]+d) %% 360,values[2],values[3]))))
    } else if (command %in% c("LIGHTEN","DARKEN","SATURATE","DESATURATE")) {
        values <- hsl(args[[1]])
        p <- args[[2]]
        if (command == "LIGHTEN") {
            values[3] <- min(100,values[3]+p)
        } else if (command == "DARKEN") {
            values[3] <- max(0,values[3]-p)
        } else if (command == "SATURATE") {
            values[2] <- min(100,values[2]+p)
        } else {
            values[2] <- max(0,values[2]-p)
        }
        result <- from_hsl(values[1],values[2],values[3])
    } else if (command == "DISTANCE") {
        a <- args[[1]]
        b <- args[[2]]
        weighted <- (1024+a[1]+b[1])*(a[1]-b[1])^2+2048*(a[2]-b[2])^2+(1534-a[1]-b[1])*(a[3]-b[3])^2
        return(sprintf("%d %d",color_distance(a,b),root_ratio(weighted,512)))
    } else if (command == "CONTRAST") {
        return(contrast_text(args[[1]],args[[2]]))
    } else if (command == "ACCESSIBLE") {
        result <- args[[1]]
        bg <- args[[2]]
        if (contrast(result,bg)$verdict == "FAIL") {
            values <- hsl(result)
            found <- FALSE
            for (step in 1:100) {
                for (lightness in c(values[3]-step,values[3]+step)) {
                    if (lightness >= 0 && lightness <= 100) {
                        candidate <- from_hsl(values[1],values[2],lightness)
                        if (contrast(candidate,bg)$verdict != "FAIL") {
                            result <- candidate
                            found <- TRUE
                            break
                        }
                    }
                }
                if (found) break
            }
        }
        return(paste(hex_color(result),contrast_text(result,bg)))
    } else if (command == "BEST") {
        colors <- args[[1]]
        bg <- colors[[1]]
        ratios <- vapply(colors[-1],function(color) contrast(color,bg)$ratio,numeric(1))
        selected <- colors[[which.max(ratios)+1]]
        return(paste(hex_color(selected),contrast_text(selected,bg)))
    } else if (command == "DESCRIBE") {
        values <- hsl(args[[1]])
        h <- values[1]
        s <- values[2]
        l <- values[3]
        if (l <= 5) return("black")
        if (l >= 95) return("white")
        if (l <= 20) {
            lightness <- "very dark"
        } else if (l <= 40) {
            lightness <- "dark"
        } else if (l <= 60) {
            lightness <- "medium"
        } else if (l <= 80) {
            lightness <- "light"
        } else {
            lightness <- "very light"
        }
        if (s < 10) return(paste(lightness,"gray"))
        if (s < 40) {
            saturation <- "muted"
        } else if (s < 80) {
            saturation <- "moderate"
        } else {
            saturation <- "vivid"
        }
        names <- strsplit("red orange yellow chartreuse green spring-green cyan azure blue violet magenta rose"," ")[[1]]
        return(paste(lightness,saturation,names[((h+15) %% 360) %/% 30+1]))
    } else if (command %in% c("PALETTE","KMEANS")) {
        k <- args[[1]]
        colors <- args[[2]]
        boxes <- palette(colors,k)
        representatives <- lapply(boxes,mean_color)
        counts <- lengths(boxes)
        iterations <- 0
        if (command == "KMEANS") {
            for (iteration in 1:20) {
                assigned <- replicate(k,list(),simplify=FALSE)
                for (color in colors) {
                    j <- nearest_index(color,representatives)
                    assigned[[j]][[length(assigned[[j]])+1]] <- color
                }
                updated <- lapply(seq_len(k),function(j) {
                    if (length(assigned[[j]]) == 0) {
                        representatives[[j]]
                    } else {
                        mean_color(assigned[[j]])
                    }
                })
                counts <- lengths(assigned)
                iterations <- iteration
                unchanged <- all(vapply(seq_len(k),function(j) all(updated[[j]] == representatives[[j]]),logical(1)))
                representatives <- updated
                if (unchanged) break
            }
        }
        output <- paste(vapply(seq_len(k),function(j) paste0(hex_color(representatives[[j]]),":",counts[j]),character(1)),collapse=" ")
        return(if (command == "PALETTE") output else paste(iterations,output))
    } else if (command == "SORT") {
        colors <- args[[1]]
        values <- do.call(rbind,lapply(colors,hsl))
        indices <- order(values[,1],values[,2],values[,3],seq_along(colors))
        return(color_sequence(colors[indices]))
    } else if (command == "DITHER") {
        error <- c(0,0,0)
        output <- character(0)
        for (color in args[[1]]) {
            adjusted <- byte_clamp(color+error)
            selected <- nearest_index(adjusted,builtin_colors[1:16])
            output <- c(output,builtin_names[selected])
            error <- adjusted-builtin_colors[[selected]]
        }
        return(paste(output,collapse=" "))
    } else if (command == "RANDOM") {
        state <- args[[1]]
        output <- list()
        for (i in seq_len(args[[2]])) {
            state <- (48271*state) %% 2147483647
            u <- state
            state <- (48271*state) %% 2147483647
            v <- state
            state <- (48271*state) %% 2147483647
            output[[i]] <- from_hsl(u %% 360,40+v %% 61,25+state %% 51)
        }
        return(color_sequence(output))
    }
    hex_color(result)
}

main <- function() {
    input <- readLines(file("stdin"),warn=FALSE)
    count <- as.integer(input[1])
    registry <- new.env(parent=emptyenv())
    registry$colors <- list()
    registry$order <- character(0)
    for (i in seq_len(count)) {
        parts <- strsplit(input[i+1]," ",fixed=TRUE)[[1]]
        output <- tryCatch(execute(parts[1],parts[-1],registry),error=function(e) "INVALID")
        cat(output,"\n",sep="")
    }
}
main()
