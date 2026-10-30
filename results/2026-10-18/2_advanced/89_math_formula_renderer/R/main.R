source("lexer.R")
source("parser.R")
source("boxes.R")
source("layout.R")
source("canvas.R")
STACKED_COMMANDS <- c("\\sum", "\\prod", "\\lim", "\\max", "\\min")
BRACE_ACCENTS <- c("overbrace", "underbrace")
DELIMITER_PAIRS <- c("("=")", "["="]", "|"="|", "\\{"="\\}")
read_formula <- function(number, text) {
    formula <- new.env(parent=emptyenv())
    formula$number <- number
    formula$text <- text
    formula$nodes <- list()
    formula$tag <- formula$label <- formula$tag_string <- formula$error <- NULL
    formula$warnings <- list()
    parsed <- tryCatch({
        tokens <- tokenize(text)
        check_braces(tokens)
        parser <- new_parser(tokens)
        nodes <- parse_formula(parser)
        list(nodes=nodes, tag=parser$tag, label=parser$label)
    }, formula_error=function(error) error)
    if (inherits(parsed, "formula_error")) {
        formula$error <- parsed
    } else {
        formula$nodes <- parsed$nodes
        formula$tag <- parsed$tag
        formula$label <- parsed$label
    }
    formula
}
reference_has <- function(references, name) exists(paste0("r:",name), references, inherits=FALSE)
reference_get <- function(references, name) {
    if (reference_has(references,name)) references[[paste0("r:",name)]] else "(??)"
}
reference_table <- function(formulas) {
    counter <- 0L
    for (formula in formulas) {
        if (!is.null(formula$error)) next
        if (!is.null(formula$tag)) {
            formula$tag_string <- paste0("(",formula$tag$value,")")
        } else if (!is.null(formula$label)) {
            counter <- counter+1L
            formula$tag_string <- paste0("(",counter,")")
        }
    }
    references <- new.env(hash=TRUE,parent=emptyenv())
    for (formula in formulas) {
        if (!is.null(formula$error) || is.null(formula$label)) next
        label <- formula$label
        if (reference_has(references,label$value)) {
            formula$warnings[[length(formula$warnings)+1L]] <- list(column=label$column,
                message=paste0("duplicate label \"",label$value,"\""))
        } else references[[paste0("r:",label$value)]] <- formula$tag_string
    }
    references
}
collect_warnings <- function(formula,references) {
    append_warning <- function(column,message) formula$warnings[[length(formula$warnings)+1L]] <- list(column=column,message=message)
    visit <- function(node) {
        if (node$kind == "identifier" && node$value %in% COMMAND_NAMES) {
            append_warning(node$column,paste0(node$value," is a command name; write ",intToUtf8(92L),node$value))
        } else if (node$kind == "reference" && !reference_has(references,node$value)) {
            append_warning(node$column,paste0("undefined reference \"",node$value,"\""))
        } else if (node$kind == "delim") {
            left <- node$value[1]
            right <- node$value[2]
            paired <- left %in% names(DELIMITER_PAIRS) && DELIMITER_PAIRS[[left]] == right
            if (left != "." && right != "." && !paired) {
                append_warning(node$column,paste0("\\left",left," closed by \\right",right))
            }
        }
        if (node$kind == "matrix") {
            for (row in node$children) for (cell in row) visit(cell)
        } else for (child in node$children) if (!is.null(child)) visit(child)
    }
    for (node in formula$nodes) visit(node)
    formula$warnings <- formula$warnings[order(vapply(formula$warnings,function(w) w$column,0L))]
}
center <- function(box,width) (width-box$width) %/% 2L
draw_delimiter <- function(box,delimiter,x,height) {
    glyph <- delimiter_glyph(delimiter,height)
    for (y in seq_along(glyph)) draw_string(box,glyph[y],x,y-1L)
}
delimiter_string <- function(delimiter) if (delimiter == ".") "" else substring(delimiter,nchar(delimiter))
delimit_box <- function(body,left,right) {
    wl <- if (left == ".") 0L else 1L
    wr <- if (right == ".") 0L else 1L
    result <- new_box(wl+body$width+wr,body$height,body$baseline,paste("delim",left,right))
    add_child(result,body,wl,0L)
    draw_delimiter(result,left,0L,body$height)
    draw_delimiter(result,right,wl+body$width,body$height)
    result
}
radical_box <- function(body,index=NULL) {
    height <- body$height
    extra <- if (is.null(index)) 0L else max(0L,index$width-1L)
    top <- if (is.null(index)) 0L else max(0L,index$height-height)
    result <- new_box(extra+height+1L+body$width,height+1L+top,body$baseline+1L+top,
        if (is.null(index)) "sqrt" else "root")
    draw_string(result,strrep("_",body$width),extra+height+1L,top)
    draw_string(result,"\\",extra,height+top)
    for (row in seq_len(height)) draw_string(result,"/",extra+height-row+1L,row+top)
    if (is.null(index)) {
        add_child(result,body,extra+height+1L,1L)
    } else {
        add_child(result,index,0L,height-index$height+top,"index: ")
        add_child(result,body,extra+height+1L,1L+top,"body: ")
    }
    result
}
typeset <- function(node,parameters,references,style="normal") {
    kind <- node$kind
    if (kind %in% c(ATOM_KINDS,"reference")) {
        description <- if (kind == "text") paste0("text \"",node$value,"\"") else if (kind == "reference") {
            paste0("eqref \"",node$value,"\"")
        } else paste0("atom \"",node$value,"\"")
        display <- if (kind == "reference") reference_get(references,node$value) else if (kind == "command") {
            COMMAND_DISPLAY[[node$value]]
        } else node$value
        if (kind == "command" && node$value %in% names(LARGE_GLYPHS) && style == "normal") {
            glyph <- LARGE_GLYPHS[[node$value]]
            result <- new_box(nchar(glyph[1]),3L,1L,description)
            for (y in seq_along(glyph)) draw_string(result,glyph[y],0L,y-1L)
        } else {
            result <- new_box(nchar(display),1L,0L,description)
            draw_string(result,display)
        }
        return(result)
    }
    if (kind == "row") {
        gaps <- spacing(node$children,style,parameters)$gaps
        return(row_box(lapply(node$children,function(child) typeset(child,parameters,references,style)),gaps))
    }
    if (kind == "script") {
        base_node <- node$children[[1]]
        sub_node <- node$children[[2]]
        sup_node <- node$children[[3]]
        base <- typeset(base_node,parameters,references,style)
        sub <- if (is.null(sub_node)) NULL else typeset(sub_node,parameters,references,"script")
        sup <- if (is.null(sup_node)) NULL else typeset(sup_node,parameters,references,"script")
        sw <- if (is.null(sub)) 0L else sub$width
        sh <- if (is.null(sub)) 0L else sub$height
        pw <- if (is.null(sup)) 0L else sup$width
        ph <- if (is.null(sup)) 0L else sup$height
        stacked <- style == "normal" && ((base_node$kind == "command" && base_node$value %in% STACKED_COMMANDS) ||
            (base_node$kind == "accent" && base_node$value %in% BRACE_ACCENTS))
        if (stacked) {
            width <- max(base$width,sw,pw)
            result <- new_box(width,ph+base$height+sh,ph+base$baseline,"limits")
            add_child(result,base,center(base,width),ph,"base: ")
            if (!is.null(sub)) add_child(result,sub,center(sub,width),ph+base$height,"sub: ")
            if (!is.null(sup)) add_child(result,sup,center(sup,width),0L,"sup: ")
        } else {
            sup_top <- (if (base$baseline == 0L) -1L else 0L)-ph+1L
            sub_top <- if (descent(base) == 0L) base$height else base$height-1L
            top <- if (is.null(sup)) 0L else min(0L,sup_top)
            bottom <- if (is.null(sub)) base$height-1L else max(base$height-1L,sub_top+sh-1L)
            result <- new_box(base$width+max(sw,pw),bottom-top+1L,base$baseline-top,"scripts")
            add_child(result,base,0L,-top,"base: ")
            if (!is.null(sub)) add_child(result,sub,base$width,sub_top-top,"sub: ")
            if (!is.null(sup)) add_child(result,sup,base$width,sup_top-top,"sup: ")
        }
        return(result)
    }
    if (kind == "frac") {
        numerator <- typeset(node$children[[1]],parameters,references,style)
        denominator <- typeset(node$children[[2]],parameters,references,style)
        if (style == "normal") {
            width <- max(numerator$width,denominator$width)+2L
            result <- new_box(width,numerator$height+1L+denominator$height,numerator$height,"frac")
            add_child(result,numerator,center(numerator,width),0L,"num: ")
            add_child(result,denominator,center(denominator,width),numerator$height+1L,"den: ")
            draw_string(result,strrep("-",width),0L,numerator$height)
            return(result)
        }
        if (node$children[[1]]$kind %in% c("row","frac")) numerator <- delimit_box(numerator,"(",")")
        if (node$children[[2]]$kind %in% c("row","frac")) denominator <- delimit_box(denominator,"(",")")
        slash <- new_box(1L,1L,0L,"atom \"/\"")
        draw_string(slash,"/")
        return(row_box(list(numerator,slash,denominator),c(0L,0L),"slash",c("num: ","","den: ")))
    }
    if (kind == "binom") {
        upper <- typeset(node$children[[1]],parameters,references,style)
        lower <- typeset(node$children[[2]],parameters,references,style)
        width <- max(upper$width,lower$width)
        height <- upper$height+1L+lower$height
        result <- new_box(width+2L,height,upper$height,"binom")
        add_child(result,upper,center(upper,width)+1L,0L,"upper: ")
        add_child(result,lower,center(lower,width)+1L,upper$height+1L,"lower: ")
        draw_delimiter(result,"(",0L,height)
        draw_delimiter(result,")",width+1L,height)
        return(result)
    }
    if (kind %in% c("overset","underset")) {
        placed <- typeset(node$children[[1]],parameters,references,"script")
        base <- typeset(node$children[[2]],parameters,references,style)
        width <- max(placed$width,base$width)
        baseline <- if (kind == "overset") placed$height+base$baseline else base$baseline
        result <- new_box(width,placed$height+base$height,baseline,kind)
        if (kind == "overset") {
            add_child(result,placed,center(placed,width),0L,"over: ")
            add_child(result,base,center(base,width),placed$height,"base: ")
        } else {
            add_child(result,base,center(base,width),0L,"base: ")
            add_child(result,placed,center(placed,width),base$height,"under: ")
        }
        return(result)
    }
    if (kind == "sqrt") return(radical_box(typeset(node$children[[1]],parameters,references,style)))
    if (kind == "root") {
        index <- typeset(node$children[[1]],parameters,references,"script")
        body <- typeset(node$children[[2]],parameters,references,style)
        return(radical_box(body,index))
    }
    if (kind == "delim") return(delimit_box(typeset(node$children[[1]],parameters,references,style),node$value[1],node$value[2]))
    if (kind == "matrix") {
        cells <- lapply(node$children,function(row) lapply(row,function(cell) typeset(cell,parameters,references,style)))
        row_count <- length(cells)
        column_count <- length(cells[[1]])
        widths <- vapply(seq_len(column_count),function(j) max(vapply(cells,function(row) row[[j]]$width,0L)),0L)
        ascents <- vapply(cells,function(row) max(vapply(row,function(c) c$baseline,0L)),0L)
        descents <- vapply(cells,function(row) max(vapply(row,descent,0L)),0L)
        heights <- ascents+descents+1L
        column_gap <- parameters$col_gap
        row_gap <- parameters$row_gap
        body_width <- sum(widths)+column_gap*(column_count-1L)
        body_height <- sum(heights)+row_gap*(row_count-1L)
        environment <- node$value
        shift <- if (environment == "matrix") 0L else 2L
        extra <- if (environment == "matrix") 0L else if (environment == "cases") 2L else 4L
        description <- paste0(environment," rows=",row_count," cols=",column_count)
        result <- new_box(body_width+extra,body_height,(body_height-1L) %/% 2L,description)
        y <- 0L
        for (i in seq_along(cells)) {
            row <- cells[[i]]
            x <- shift
            for (j in seq_along(row)) {
                cell <- row[[j]]
                offset <- if (environment == "cases") 0L else center(cell,widths[j])
                role <- paste0("cell ",i,",",j,": ")
                add_child(result,cell,x+offset,y+ascents[i]-cell$baseline,role)
                x <- x+widths[j]+column_gap
            }
            y <- y+heights[i]+row_gap
        }
        if (environment == "cases") {
            draw_delimiter(result,"\\{",0L,body_height)
        } else if (environment != "matrix") {
            pair <- list(pmatrix=c("(",")"),bmatrix=c("[","]"),vmatrix=c("|","|"))[[environment]]
            draw_delimiter(result,pair[1],0L,body_height)
            draw_delimiter(result,pair[2],body_width+3L,body_height)
        }
        return(result)
    }
    body <- typeset(node$children[[1]],parameters,references,style)
    name <- node$value
    width <- body$width
    if (name %in% c("hat","dot","tilde")) width <- max(width,1L)
    if (name == "vec") width <- max(width,2L)
    if (name %in% BRACE_ACCENTS) width <- width+2L
    baseline <- if (name == "underbrace") body$baseline else body$baseline+1L
    result <- new_box(width,body$height+1L,baseline,name)
    if (name == "underbrace") {
        add_child(result,body,1L,0L)
        draw_string(result,paste0("\\",strrep("-",body$width),"/"),0L,body$height)
    } else if (name == "overbrace") {
        add_child(result,body,1L,1L)
        draw_string(result,paste0("/",strrep("-",body$width),"\\"))
    } else {
        add_child(result,body,0L,1L)
        if (name == "overline") draw_string(result,strrep("_",width)) else if (name == "vec") {
            draw_string(result,paste0(strrep("-",width-1L),">"))
        } else draw_string(result,c(hat="^",dot=".",tilde="~")[[name]],(width-1L) %/% 2L,0L)
    }
    result
}
build_lines <- function(breaks,types,boxes,starts,parameters) {
    result <- list()
    position <- 1L
    alignment <- NULL
    while (position <= length(boxes)) {
        indentation <- if (position == 1L) 0L else if (is.null(alignment)) parameters$indent else {
            if (types[[position]][1] == "relation") alignment[1] else alignment[1]+alignment[2]+parameters$rel_space
        }
        ends <- c(sort(breaks[breaks > position]),length(boxes)+1L)
        candidates <- lapply(ends,function(stop) list(stop=stop,width=starts[stop-1L]+boxes[[stop-1L]]$width-starts[position]))
        fitting <- Filter(function(candidate) indentation+candidate$width <= parameters$width,candidates)
        chosen <- if (length(fitting)) fitting[[length(fitting)]] else candidates[[1]]
        result[[length(result)+1L]] <- list(first=position,stop=chosen$stop,indent=indentation,width=chosen$width)
        if (position == 1L) for (i in seq_len(chosen$stop-1L)) if (types[[i]][1] == "relation") {
            alignment <- c(starts[i],boxes[[i]]$width)
            break
        }
        position <- chosen$stop
    }
    result
}
place_formula <- function(formula,parameters,references) {
    nodes <- formula$nodes
    spaces <- spacing(nodes,"normal",parameters)
    types <- spaces$types
    gaps <- spaces$gaps
    boxes <- lapply(nodes,function(node) typeset(node,parameters,references))
    starts <- integer()
    x <- 0L
    for (i in seq_along(boxes)) {
        starts <- c(starts,x)
        x <- x+boxes[[i]]$width
        if (i <= length(gaps)) x <- x+gaps[i]
    }
    indices <- if (length(nodes) >= 2L) seq.int(2L,length(nodes)) else integer()
    relations <- indices[vapply(indices,function(i) types[[i]][1] == "relation",FALSE)]
    plus_minus <- indices[vapply(indices,function(i) nodes[[i]]$kind == "symbol" && nodes[[i]]$value %in% c("+","-") && types[[i]][1] == "binary",FALSE)]
    punctuation <- indices[vapply(indices,function(i) types[[i-1L]][2] == "punctuation",FALSE)]
    plan <- list()
    for (breaks in list(relations,union(relations,plus_minus),union(union(relations,plus_minus),punctuation))) {
        plan <- build_lines(breaks,types,boxes,starts,parameters)
        if (all(vapply(plan,function(entry) entry$indent+entry$width <= parameters$width,FALSE))) break
    }
    roots <- overfull <- list()
    width <- height <- 0L
    for (number in seq_along(plan)) {
        entry <- plan[[number]]
        indices <- seq.int(entry$first,entry$stop-1L)
        line_gaps <- if (length(indices) >= 2L) gaps[head(indices,-1)] else integer()
        box <- row_box(boxes[indices],line_gaps,paste("line",number))
        roots[[length(roots)+1L]] <- list(box=box,x=entry$indent,y=height)
        height <- height+box$height
        width <- max(width,entry$indent+box$width)
        if (entry$indent+entry$width > parameters$width) overfull[[length(overfull)+1L]] <- c(number,entry$indent+entry$width)
    }
    if (!is.null(formula$tag_string)) {
        tag <- formula$tag_string
        tx <- parameters$width-nchar(tag)
        last <- roots[[length(roots)]]
        if (tx >= last$x+last$box$width+2L) ty <- last$y+last$box$baseline else {
            ty <- height
            height <- height+1L
        }
        tag_box <- new_box(nchar(tag),1L,0L,paste0("tag \"",tag,"\""))
        draw_string(tag_box,tag)
        roots[[length(roots)+1L]] <- list(box=tag_box,x=tx,y=ty)
        width <- max(width,tx+tag_box$width)
    }
    list(roots=roots,lines=length(plan),width=width,height=height,overfull=overfull)
}
tree_notation <- function(node) {
    kind <- node$kind
    if (kind %in% c("identifier","number","command")) return(node$value)
    if (kind == "symbol") return(paste0("'",node$value,"'"))
    if (kind == "text") return(paste0("\"",node$value,"\""))
    if (kind == "reference") return(paste0("(eqref \"",node$value,"\")"))
    if (kind == "row") {
        children <- vapply(node$children,tree_notation,"")
        return(paste0("(row",if (length(children)) paste0(" ",paste(children,collapse=" ")) else "",")"))
    }
    if (kind == "matrix") {
        rows <- vapply(node$children,function(row) paste0("[",paste(vapply(row,tree_notation,""),collapse=" "),"]"),"")
        return(paste0("(",node$value," ",paste(rows,collapse=" "),")"))
    }
    if (kind == "delim") {
        delimiters <- vapply(node$value,function(value) if (nchar(value) == 1L) paste0("'",value,"'") else value,"")
        return(paste0("(delim ",paste(delimiters,collapse=" ")," ",tree_notation(node$children[[1]]),")"))
    }
    if (kind == "script") {
        sub <- node$children[[2]]
        sup <- node$children[[3]]
        name <- if (is.null(sub)) "sup" else if (is.null(sup)) "sub" else "subsup"
        children <- Filter(function(child) !is.null(child),node$children)
    } else {
        name <- if (kind == "accent") node$value else kind
        children <- node$children
    }
    paste0("(",name," ",paste(vapply(children,tree_notation,""),collapse=" "),")")
}
linear_row <- function(nodes,parameters,references,style) {
    gaps <- spacing(nodes,style,parameters)$gaps
    parts <- character()
    for (i in seq_along(nodes)) {
        if (i > 1L) parts <- c(parts,strrep(" ",gaps[i-1L]))
        parts <- c(parts,linear_notation(nodes[[i]],parameters,references,style))
    }
    paste(parts,collapse="")
}
parenthesize <- function(node,parameters,references,style,kinds) {
    value <- linear_notation(node,parameters,references,style)
    if (node$kind %in% kinds) paste0("(",value,")") else value
}
linear_notation <- function(node,parameters,references,style="normal") {
    kind <- node$kind
    if (kind %in% c("identifier","number","symbol","text")) return(node$value)
    if (kind == "command") return(COMMAND_DISPLAY[[node$value]])
    if (kind == "reference") return(reference_get(references,node$value))
    if (kind == "row") return(linear_row(node$children,parameters,references,style))
    if (kind == "frac") return(paste(vapply(node$children,function(child) parenthesize(child,parameters,references,style,c("row","frac")),""),collapse="/"))
    if (kind == "script") {
        result <- parenthesize(node$children[[1]],parameters,references,style,c("row","frac","script"))
        if (!is.null(node$children[[2]])) result <- paste0(result,"_",parenthesize(node$children[[2]],parameters,references,"script",c("row","frac")))
        if (!is.null(node$children[[3]])) result <- paste0(result,"^",parenthesize(node$children[[3]],parameters,references,"script",c("row","frac")))
        return(result)
    }
    if (kind == "delim") return(paste0(delimiter_string(node$value[1]),linear_notation(node$children[[1]],parameters,references,style),delimiter_string(node$value[2])))
    if (kind == "matrix") {
        rows <- vapply(node$children,function(row) paste(vapply(row,function(cell) linear_notation(cell,parameters,references,style),""),collapse=", "),"")
        return(paste0(node$value,"[",paste(rows,collapse="; "),"]"))
    }
    if (kind %in% c("root","overset","underset")) return(paste0(kind,"(",
        linear_notation(node$children[[1]],parameters,references,"script"),", ",linear_notation(node$children[[2]],parameters,references,style),")"))
    name <- if (kind == "accent") node$value else kind
    children <- vapply(node$children,function(child) linear_notation(child,parameters,references,style),"")
    paste0(name,"(",paste(children,collapse=", "),")")
}
diagnostic <- function(formula,column,message,warning=FALSE) {
    prefix <- if (warning) "warning: " else ""
    c(paste0("formula ",formula$number,", column ",column,": ",prefix,message),paste0("  ",formula$text),paste0(strrep(" ",column+1L),"^"))
}
main <- function() {
    parameters <- list()
    for (text in readLines("input/params.txt",warn=FALSE)) {
        fields <- strsplit(text," ",fixed=TRUE)[[1]]
        parameters[[fields[1]]] <- as.integer(fields[2])
    }
    lines <- readLines("input/formulas.txt",warn=FALSE)
    formulas <- lapply(seq_along(lines),function(i) read_formula(i,lines[i]))
    references <- reference_table(formulas)
    rendered <- boxes <- trees <- errors <- character()
    box_kinds <- integer()
    total_boxes <- max_depth <- valid_count <- error_count <- warning_count <- overfull_count <- 0L
    for (formula in formulas) {
        if (formula$number > 1L) rendered <- c(rendered,"")
        rendered <- c(rendered,paste("formula",formula$number))
        if (!is.null(formula$error)) {
            error_count <- error_count+1L
            rendered <- c(rendered,"(error)")
            boxes <- c(boxes,paste0("formula ",formula$number,": error"))
            trees <- c(trees,paste0("formula ",formula$number,": error"))
            errors <- c(errors,diagnostic(formula,formula$error$column,formula$error$message))
            next
        }
        valid_count <- valid_count+1L
        collect_warnings(formula,references)
        placement <- place_formula(formula,parameters,references)
        rendered <- c(rendered,draw_boxes(placement$roots,placement$width,placement$height))
        entries <- box_lines(placement$roots)
        depth <- max(vapply(entries,function(entry) entry$level,0L))+1L
        total_boxes <- total_boxes+length(entries)
        max_depth <- max(max_depth,depth)
        boxes <- c(boxes,paste0("formula ",formula$number,": lines=",placement$lines," width=",placement$width,
            " height=",placement$height," boxes=",length(entries)," depth=",depth))
        for (entry in entries) {
            boxes <- c(boxes,entry$text)
            if (!entry$kind %in% names(box_kinds)) box_kinds[entry$kind] <- 0L
            box_kinds[entry$kind] <- box_kinds[entry$kind]+1L
        }
        trees <- c(trees,paste0("formula ",formula$number,": ",paste(vapply(formula$nodes,tree_notation,""),collapse=" ")))
        linear <- sub(" +$","",linear_row(formula$nodes,parameters,references,"normal"))
        trees <- c(trees,paste0("  linear:",if (nzchar(linear)) paste0(" ",linear) else ""))
        if (!is.null(formula$tag_string)) trees <- c(trees,paste0("  tag: ",formula$tag_string))
        warning_count <- warning_count+length(formula$warnings)
        for (warning in formula$warnings) errors <- c(errors,diagnostic(formula,warning$column,warning$message,warning=TRUE))
        overfull_count <- overfull_count+length(placement$overfull)
        for (entry in placement$overfull) errors <- c(errors,paste0("formula ",formula$number,": line ",entry[1],
            " is overfull (width ",entry[2]," > ",parameters$width,")"))
    }
    boxes <- c(boxes,paste0("summary: boxes=",total_boxes," max_depth=",max_depth))
    for (kind in sort(names(box_kinds),method="radix")) boxes <- c(boxes,paste0("  ",kind,": ",box_kinds[[kind]]))
    errors <- c(errors,paste0("formulas=",length(formulas)," rendered=",valid_count," errors=",error_count,
        " warnings=",warning_count," overfull=",overfull_count))
    dir.create("output",showWarnings=FALSE)
    reports <- list(rendered.txt=rendered,boxes.txt=boxes,trees.txt=trees,errors.txt=errors)
    for (name in names(reports)) writeLines(reports[[name]],file.path("output",name),useBytes=TRUE)
}
main()
