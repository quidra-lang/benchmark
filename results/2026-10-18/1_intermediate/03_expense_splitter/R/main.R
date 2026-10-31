fail <- function(message) stop(message,call.=FALSE)

floor_div <- function(n,d) {
    quotient <- trunc(n/d)
    remainder <- n-quotient*d
    if (remainder < 0) {
        quotient <- quotient-1
    } else if (remainder >= d) {
        quotient <- quotient+1
    }
    quotient
}

integer_text <- function(value) sprintf("%.0f",value)

amount_text <- function(value) {
    quotient <- floor_div(value,100)
    sprintf("%.0f.%02d",quotient,value-quotient*100)
}

signed_text <- function(value) {
    if (value == 0) "0.00" else paste0(if (value > 0) "+" else "-",amount_text(abs(value)))
}

rate_text <- function(value) sprintf("%.0f.%04d",floor_div(value,10000),value %% 10000)

percentage <- function(part,whole) paste0(amount_text(floor_div(part*10000,whole)),"%")

registered_names <- function(state) sort(names(state$members),method="radix")

active_names <- function(state) {
    names <- registered_names(state)
    names[vapply(names,function(name) state$members[[name]]$active,logical(1))]
}

expense_names <- function(expense) unique(c(expense$payers,expense$participants))

expense_has <- function(expense,name) name %in% expense$payers || name %in% expense$participants

currency_note <- function(record) {
    if (record$currency == "") "" else paste0(" [",amount_text(record$amount)," ",record$currency,"]")
}

chronological <- function(state) {
    expenses <- unname(state$expenses)
    indices <- order(vapply(expenses,function(e) e$day,numeric(1)),vapply(expenses,function(e) e$record,numeric(1)))
    expenses[indices]
}

parse_amount <- function(text) {
    values <- as.numeric(strsplit(text,".",fixed=TRUE)[[1]])
    values[1]*100+values[2]
}

amount_spec <- function(text) {
    parts <- strsplit(text,"@",fixed=TRUE)[[1]]
    list(amount=parse_amount(parts[1]),currency=if (length(parts) == 1) "" else parts[2])
}

converted <- function(state,amount,currency) {
    if (currency == "") return(amount)
    if (!currency %in% names(state$currencies)) fail(paste("unknown currency",currency))
    floor_div(amount*state$currencies[[currency]]+5000,10000)
}

check_member <- function(state,name,active=TRUE) {
    if (!name %in% names(state$members)) fail(paste("unknown member",name))
    if (active && !state$members[[name]]$active) fail(paste("inactive member",name))
}

expense_ref <- function(state,id,unfrozen=FALSE) {
    if (!id %in% names(state$expenses)) fail(paste("unknown expense",id))
    expense <- state$expenses[[id]]
    if (unfrozen) {
        for (name in c(expense$payers,expense$participants)) {
            if (!state$members[[name]]$active) fail(paste("inactive member",name))
        }
    }
    expense
}

equal_distribution <- function(total,k) {
    quotient <- floor_div(total,k)
    quotient+as.numeric(seq_len(k) <= total-quotient*k)
}

largest_remainder <- function(total,weights) {
    whole <- sum(weights)
    result <- vapply(weights,function(weight) floor_div(total*weight,whole),numeric(1))
    remainders <- total*weights-result*whole
    ordering <- order(-remainders,seq_along(weights))
    for (i in seq_len(total-sum(result))) {
        result[ordering[i]] <- result[ordering[i]]+1
    }
    unname(result)
}

portions <- function(expense) {
    values <- expense$values
    if (expense$mode == "EQUAL") return(equal_distribution(expense$amount,length(values)))
    if (expense$mode == "EXACT") return(values)
    if (expense$mode %in% c("PERCENT","SHARES")) return(largest_remainder(expense$amount,values))
    equal_distribution(expense$amount-sum(values),length(values))+values
}

recompute <- function(state,expense) {
    expense$total <- converted(state,expense$amount,expense$currency)
    expense$shares <- largest_remainder(expense$total,portions(expense))
    expense$contributions <- largest_remainder(expense$total,expense$payments)
    expense
}

build_expense <- function(state,id,payer,spec,category,mode,parts) {
    check_member(state,payer)
    parsed <- amount_spec(spec)
    amount <- parsed$amount
    currency <- parsed$currency
    total <- converted(state,amount,currency)
    if (amount == 0 || total == 0) fail("invalid amount")
    names <- character(0)
    values <- numeric(0)
    if (mode == "EQUAL" && identical(parts,"ALL")) {
        names <- active_names(state)
        values <- rep(0,length(names))
    } else {
        for (part in parts) {
            pieces <- strsplit(part,":",fixed=TRUE)[[1]]
            name <- pieces[1]
            check_member(state,name)
            if (name %in% names) fail(paste("duplicate member",name))
            value <- 0
            if (length(pieces) == 2) value <- if (mode %in% c("EXACT","ADJUST")) parse_amount(pieces[2]) else as.numeric(pieces[2])
            names <- c(names,name)
            values <- c(values,value)
        }
    }
    valid <- switch(mode,EXACT=sum(values) == amount,PERCENT=sum(values) == 10000,
        SHARES=sum(values) >= 1,ADJUST=sum(values) <= amount,EQUAL=TRUE)
    if (!valid) fail("splits do not add up")
    recompute(state,list(id=id,day=state$day,record=0,payers=payer,payments=amount,
        amount=amount,currency=currency,category=category,mode=mode,participants=names,
        values=values,total=total,shares=numeric(0),contributions=numeric(0),interval=0,next_day=0,copies=0))
}

expense_net <- function(expense) {
    people <- expense_names(expense)
    result <- setNames(numeric(length(people)),people)
    result[expense$payers] <- result[expense$payers]+expense$contributions
    result[expense$participants] <- result[expense$participants]-expense$shares
    result
}

balances <- function(state) {
    names <- registered_names(state)
    result <- setNames(rep(0,length(names)),names)
    for (expense in state$expenses) {
        net <- expense_net(expense)
        result[names(net)] <- result[names(net)]+net
    }
    for (settlement in state$settlements) {
        result[settlement$sender] <- result[settlement$sender]+settlement$total
        result[settlement$receiver] <- result[settlement$receiver]-settlement$total
    }
    result
}

greedy_transfers <- function(names,original) {
    remaining <- original[names]
    output <- list()
    while (length(remaining) > 0 && min(remaining) < 0) {
        sender <- names[which.min(remaining)]
        receiver <- names[which.max(remaining)]
        amount <- min(-remaining[[sender]],remaining[[receiver]])
        output[[length(output)+1]] <- list(sender=sender,receiver=receiver,amount=amount)
        remaining[sender] <- remaining[sender]+amount
        remaining[receiver] <- remaining[receiver]-amount
    }
    output
}

debts <- function(state) {
    names <- registered_names(state)
    result <- matrix(0,length(names),length(names),dimnames=list(names,names))
    for (expense in state$expenses) {
        net <- expense_net(expense)
        borrowers <- sort(names(net)[net < 0],method="radix")
        lenders <- sort(names(net)[net > 0],method="radix")
        i <- 1
        j <- 1
        while (i <= length(borrowers) && j <= length(lenders)) {
            sender <- borrowers[i]
            receiver <- lenders[j]
            amount <- min(-net[[sender]],net[[receiver]])
            result[sender,receiver] <- result[sender,receiver]+amount
            net[sender] <- net[sender]+amount
            net[receiver] <- net[receiver]-amount
            if (net[[sender]] == 0) i <- i+1
            if (net[[receiver]] == 0) j <- j+1
        }
    }
    for (s in state$settlements) {
        result[s$sender,s$receiver] <- result[s$sender,s$receiver]-s$total
    }
    result
}

net_debt <- function(table,a,b) table[a,b]-table[b,a]

category_totals <- function(state) {
    if (length(state$expenses) == 0) return(numeric(0))
    tapply(vapply(state$expenses,function(expense) expense$total,numeric(1)),
        vapply(state$expenses,function(expense) expense$category,character(1)),sum)
}

budget_warning <- function(state,category) {
    if (!category %in% names(state$budgets)) return(character(0))
    totals <- category_totals(state)
    spent <- if (category %in% names(totals)) totals[[category]] else 0
    over <- spent-state$budgets[[category]]
    if (over > 0) paste0("  WARNING ",category," over budget by ",amount_text(over)) else character(0)
}

expense_line <- function(command,expense,payers=FALSE) {
    names <- if (payers) expense$payers else expense$participants
    amounts <- if (payers) expense$contributions else expense$shares
    parts <- vapply(seq_along(names),function(i) paste(names[i],amount_text(amounts[i])),character(1))
    paste0(command," ",expense$id," ",amount_text(expense$total),currency_note(expense)," = ",paste(parts,collapse=" + "))
}

advance_day <- function(state,day) {
    if (day <= state$day) fail(paste("invalid day",integer_text(day)))
    output <- paste("DAY",integer_text(day))
    repeat {
        due <- Filter(function(e) e$interval > 0 && e$next_day <= day,state$expenses)
        if (length(due) == 0) break
        ordering <- order(vapply(due,function(e) e$next_day,numeric(1)),vapply(due,function(e) e$record,numeric(1)))
        template <- due[[ordering[1]]]
        id <- template$id
        active <- all(vapply(expense_names(template),function(name) state$members[[name]]$active,logical(1)))
        if (!active || converted(state,template$amount,template$currency) == 0) {
            state$expenses[[id]]$interval <- 0
            state$expenses[[id]]$next_day <- 0
            output <- c(output,paste("  CANCEL",id))
            next
        }
        copy_id <- paste0(id,"#",integer_text(template$copies+2))
        copy <- template
        copy$id <- copy_id
        copy$day <- template$next_day
        state$serial <- state$serial+1
        copy$record <- state$serial
        copy$interval <- 0
        copy$next_day <- 0
        copy$copies <- 0
        copy <- recompute(state,copy)
        state$expenses[[copy_id]] <- copy
        state$used <- c(state$used,copy_id)
        state$expenses[[id]]$copies <- template$copies+1
        state$expenses[[id]]$next_day <- template$next_day+template$interval
        output <- c(output,paste("  RECUR",copy_id,amount_text(copy$total)),budget_warning(state,copy$category))
    }
    state$day <- day
    output
}

vector_less <- function(a,b) {
    for (i in seq_len(min(length(a),length(b)))) {
        if (a[i] != b[i]) return(a[i] < b[i])
    }
    length(a) < length(b)
}

optimal_groups <- function(names,bal) {
    n <- length(names)
    limit <- bitwShiftL(1,n)
    sums <- rep(0,limit)
    bits <- bitwShiftL(1,seq_len(n)-1)
    for (mask in seq_len(limit-1)) {
        bit <- bitwAnd(mask,-mask)
        index <- match(bit,bits)
        sums[mask+1] <- sums[bitwXor(mask,bit)+1]+bal[[names[index]]]
    }
    memo <- rep(-1,limit)
    memo[1] <- 0
    best <- function(mask) {
        if (memo[mask+1] >= 0) return(memo[mask+1])
        first <- bitwAnd(mask,-mask)
        value <- 0
        subset <- mask
        while (subset != 0) {
            if (bitwAnd(subset,first) != 0 && sums[subset+1] == 0) value <- max(value,1+best(bitwXor(mask,subset)))
            subset <- bitwAnd(subset-1,mask)
        }
        memo[mask+1] <<- value
        value
    }
    groups <- list()
    mask <- limit-1
    while (mask != 0) {
        first <- bitwAnd(mask,-mask)
        selected <- 0
        selected_indices <- integer(0)
        target <- best(mask)
        subset <- mask
        while (subset != 0) {
            if (bitwAnd(subset,first) != 0 && sums[subset+1] == 0 && 1+best(bitwXor(mask,subset)) == target) {
                indices <- which(bitwAnd(subset,bits) != 0)
                if (selected == 0 || vector_less(indices,selected_indices)) {
                    selected <- subset
                    selected_indices <- indices
                }
            }
            subset <- bitwAnd(subset-1,mask)
        }
        groups[[length(groups)+1]] <- names[selected_indices]
        mask <- bitwXor(mask,selected)
    }
    groups
}

ledger_summary <- function(command,args,line,state) {
    output <- command
    names <- registered_names(state)
    expenses <- chronological(state)
    if (command == "BALANCES") {
        bal <- balances(state)
        for (name in active_names(state)) {
            output <- c(output,paste(" ",name,signed_text(bal[[name]])))
        }
    } else if (command == "OWES") {
        name <- args[1]
        check_member(state,name,FALSE)
        output <- paste("OWES",name)
        table <- debts(state)
        for (other in names) {
            if (other == name) next
            amount <- net_debt(table,name,other)
            if (amount > 0) output <- c(output,paste(" ",name,"owes",other,amount_text(amount)))
            if (amount < 0) output <- c(output,paste(" ",other,"owes",name,amount_text(-amount)))
        }
    } else if (command == "HISTORY") {
        name <- args[1]
        check_member(state,name,FALSE)
        output <- paste("HISTORY",name)
        records <- list()
        for (expense in expenses) {
            if (expense_has(expense,name)) records[[length(records)+1]] <- list(day=expense$day,record=expense$record,label=expense$id,change=expense_net(expense)[[name]])
        }
        for (s in state$settlements) {
            if (name %in% c(s$sender,s$receiver)) {
                change <- if (name == s$sender) s$total else -s$total
                records[[length(records)+1]] <- list(day=s$day,record=s$record,label=paste0(s$sender,"->",s$receiver),change=change)
            }
        }
        ordering <- order(vapply(records,function(r) r$day,numeric(1)),vapply(records,function(r) r$record,numeric(1)))
        running <- 0
        for (record in records[ordering]) {
            running <- running+record$change
            output <- c(output,paste("  day",integer_text(record$day),record$label,signed_text(record$change),"balance",signed_text(running)))
        }
    } else if (command == "MATRIX") {
        active <- active_names(state)
        if (length(active) == 0) return(c("MATRIX","  (none)"))
        table <- debts(state)
        cells <- lapply(active,function(a) vapply(active,function(b) if (a == b) "-" else amount_text(max(0,net_debt(table,a,b))),character(1)))
        left <- max(nchar(active))
        width <- max(left,max(nchar(unlist(cells,use.names=FALSE))))
        output <- c(output,paste0(strrep(" ",left),paste0("  ",sprintf("%*s",width,active),collapse="")))
        for (i in seq_along(active)) {
            row <- sprintf("%-*s",left,active[i])
            output <- c(output,paste0(row,paste0("  ",sprintf("%*s",width,cells[[i]]),collapse="")))
        }
    } else if (command == "CATEGORY") {
        totals <- category_totals(state)
        whole <- sum(totals)
        categories <- names(totals)[order(-totals,names(totals),method="radix")]
        for (category in categories) {
            total <- totals[[category]]
            output <- c(output,paste(" ",category,amount_text(total),percentage(total,whole)))
            shares <- setNames(rep(0,length(names)),names)
            for (expense in expenses) {
                if (expense$category == category) {
                    for (i in seq_along(expense$participants)) {
                        name <- expense$participants[i]
                        shares[name] <- shares[name]+expense$shares[i]
                    }
                }
            }
            people <- names[shares > 0]
            people <- people[order(-shares[people],people,method="radix")]
            for (name in people) {
                output <- c(output,paste("   ",name,amount_text(shares[[name]]),percentage(shares[[name]],total)))
            }
        }
    } else if (command == "BUDGETS") {
        totals <- category_totals(state)
        for (category in sort(names(state$budgets),method="radix")) {
            spent <- if (category %in% names(totals)) totals[[category]] else 0
            budget <- state$budgets[[category]]
            label <- if (spent <= budget) "left" else "over"
            output <- c(output,paste(" ",category,"spent",amount_text(spent),"budget",amount_text(budget),"used",percentage(spent,budget),label,amount_text(abs(budget-spent))))
        }
    } else if (command == "TOTALS") {
        for (name in names) {
            paid <- 0
            share <- 0
            sent <- 0
            received <- 0
            for (expense in expenses) {
                paid <- paid+sum(expense$contributions[expense$payers == name])
                share <- share+sum(expense$shares[expense$participants == name])
            }
            for (s in state$settlements) {
                if (s$sender == name) sent <- sent+s$total
                if (s$receiver == name) received <- received+s$total
            }
            output <- c(output,paste(" ",name,"paid",amount_text(paid),"share",amount_text(share),"sent",amount_text(sent),"received",amount_text(received)))
        }
        currencies <- sort(unique(vapply(expenses,function(e) e$currency,character(1))),method="radix")
        for (currency in currencies[currencies != ""]) {
            selected <- Filter(function(e) e$currency == currency,expenses)
            output <- c(output,paste("  currency",currency,"expenses",length(selected),"amount",amount_text(sum(vapply(selected,function(e) e$amount,numeric(1)))),"base",amount_text(sum(vapply(selected,function(e) e$total,numeric(1))))))
        }
        output <- c(output,paste("  expenses",length(expenses),"total",amount_text(sum(vapply(expenses,function(e) e$total,numeric(1)))),"settlements",length(state$settlements),"total",amount_text(sum(vapply(state$settlements,function(s) s$total,numeric(1))))))
    } else if (command == "MEMBERS") {
        for (name in names) {
            member <- state$members[[name]]
            status <- if (member$active) "active" else "left"
            count <- sum(vapply(expenses,function(e) expense_has(e,name),logical(1)))
            output <- c(output,paste(" ",name,status,"day",integer_text(member$day),"expenses",count))
        }
    } else if (command == "EXPENSES") {
        output <- line
        mode <- args[1]
        if (mode == "MEMBER") check_member(state,args[2],FALSE)
        selected <- Filter(function(e) {
            mode == "ALL" || (mode == "CATEGORY" && e$category == args[2]) ||
                (mode == "MEMBER" && expense_has(e,args[2])) ||
                (mode == "DAYS" && e$day >= as.numeric(args[2]) && e$day <= as.numeric(args[3]))
        },expenses)
        for (e in selected) {
            output <- c(output,paste("  day",integer_text(e$day),e$id,e$category,amount_text(e$total),"by",paste(e$payers,collapse=",")))
        }
        output <- c(output,paste("  count",length(selected),"total",amount_text(sum(vapply(selected,function(e) e$total,numeric(1))))))
    } else if (command == "PERIODS") {
        k <- as.numeric(args[1])
        output <- paste("PERIODS",integer_text(k))
        periods <- vapply(expenses,function(e) floor_div(e$day-1,k),numeric(1))
        for (i in sort(unique(periods))) {
            group <- expenses[periods == i]
            output <- c(output,paste("  days",paste0(integer_text(i*k+1),"-",integer_text(i*k+k)),"expenses",length(group),"total",amount_text(sum(vapply(group,function(e) e$total,numeric(1))))))
        }
    } else if (command == "SHOW") {
        e <- expense_ref(state,args[1])
        output <- paste("SHOW",e$id)
        output <- c(output,paste0("  day ",integer_text(e$day)," category ",e$category," mode ",e$mode," total ",amount_text(e$total),currency_note(e)))
        for (i in seq_along(e$payers)) {
            output <- c(output,paste("  paid",e$payers[i],amount_text(e$contributions[i])))
        }
        for (i in seq_along(e$participants)) {
            value <- e$values[i]
            suffix <- ""
            if (e$mode == "EXACT") suffix <- paste0(" ",amount_text(value))
            if (e$mode == "PERCENT") suffix <- paste0(" ",amount_text(value),"%")
            if (e$mode == "SHARES") suffix <- paste0(" ",integer_text(value),"/",integer_text(sum(e$values)))
            if (e$mode == "ADJUST") suffix <- paste0(" +",amount_text(value))
            output <- c(output,paste0("  share ",e$participants[i]," ",amount_text(e$shares[i]),suffix))
        }
        if (e$interval > 0) output <- c(output,paste("  recurring interval",integer_text(e$interval),"next",integer_text(e$next_day)))
    } else if (command == "SIMPLIFY") {
        bal <- balances(state)
        selected <- names[bal != 0]
        if (args[1] == "GREEDY") {
            transfers <- greedy_transfers(selected,bal)
            output <- paste("SIMPLIFY GREEDY transfers",length(transfers))
            for (t in transfers) {
                output <- c(output,paste(" ",t$sender,"->",t$receiver,amount_text(t$amount)))
            }
        } else {
            if (length(selected) > 12) fail("too many members")
            groups <- optimal_groups(selected,bal)
            transfers <- lapply(groups,greedy_transfers,bal)
            output <- paste("SIMPLIFY OPTIMAL transfers",sum(lengths(transfers)),"groups",length(groups))
            for (i in seq_along(groups)) {
                output <- c(output,paste("  group",paste(groups[[i]],collapse=" ")))
                for (t in transfers[[i]]) {
                    output <- c(output,paste("   ",t$sender,"->",t$receiver,amount_text(t$amount)))
                }
            }
        }
    }
    if (command %in% c("BALANCES","OWES","HISTORY","CATEGORY","BUDGETS","MEMBERS","PERIODS") && length(output) == 1) output <- c(output,"  (none)")
    output
}

execute <- function(line,state) {
    tokens <- strsplit(line," ",fixed=TRUE)[[1]]
    command <- tokens[1]
    args <- tokens[-1]
    if (command == "DAY") return(advance_day(state,as.numeric(args[1])))
    if (command == "MEMBER") {
        name <- args[1]
        if (name %in% names(state$members) && state$members[[name]]$active) fail(paste("duplicate member",name))
        label <- if (name %in% names(state$members)) "rejoined" else "joined"
        state$members[[name]] <- list(active=TRUE,day=state$day)
        return(paste("MEMBER",name,label))
    }
    if (command == "LEAVE") {
        name <- args[1]
        check_member(state,name)
        if (balances(state)[[name]] != 0) fail(paste("member has a balance",name))
        state$members[[name]] <- list(active=FALSE,day=state$day)
        return(paste("LEAVE",name))
    }
    if (command == "CURRENCY") {
        currency <- args[1]
        rate <- as.numeric(args[2])
        suffix <- if (currency %in% names(state$currencies)) paste0(" was ",rate_text(state$currencies[[currency]])) else ""
        state$currencies[[currency]] <- rate
        return(paste0("CURRENCY ",currency," ",rate_text(rate),suffix))
    }
    if (command %in% c("EXPENSE","EDIT")) {
        id <- args[1]
        if (command == "EXPENSE") {
            if (id %in% state$used) fail(paste("duplicate id",id))
        } else {
            original <- expense_ref(state,id,TRUE)
        }
        expense <- build_expense(state,id,args[2],args[3],args[4],args[5],args[-(1:5)])
        if (command == "EDIT") {
            for (key in c("day","record","interval","next_day","copies")) {
                expense[[key]] <- original[[key]]
            }
        } else {
            state$serial <- state$serial+1
            expense$record <- state$serial
            state$used <- c(state$used,id)
        }
        state$expenses[[id]] <- expense
        return(c(expense_line(command,expense),budget_warning(state,expense$category)))
    }
    if (command == "PAYERS") {
        expense <- expense_ref(state,args[1],TRUE)
        names <- character(0)
        payments <- numeric(0)
        for (part in args[-1]) {
            pieces <- strsplit(part,":",fixed=TRUE)[[1]]
            name <- pieces[1]
            check_member(state,name)
            if (name %in% names) fail(paste("duplicate member",name))
            names <- c(names,name)
            payments <- c(payments,parse_amount(pieces[2]))
        }
        if (sum(payments) != expense$amount) fail("payers do not add up")
        expense$payers <- names
        expense$payments <- payments
        expense$contributions <- largest_remainder(expense$total,payments)
        state$expenses[[expense$id]] <- expense
        return(expense_line(command,expense,TRUE))
    }
    if (command == "DELETE") {
        expense_ref(state,args[1],TRUE)
        state$expenses[[args[1]]] <- NULL
        return(paste("DELETE",args[1]))
    }
    if (command == "RECURRING") {
        expense <- expense_ref(state,args[1])
        interval <- as.numeric(args[2])
        expense$interval <- interval
        expense$next_day <- if (interval == 0) 0 else state$day+interval
        state$expenses[[expense$id]] <- expense
        if (interval == 0) return(paste("RECURRING",expense$id,"stopped"))
        return(paste("RECURRING",expense$id,"interval",integer_text(interval),"next",integer_text(expense$next_day)))
    }
    if (command == "SETTLE") {
        sender <- args[1]
        receiver <- args[2]
        check_member(state,sender)
        check_member(state,receiver)
        if (sender == receiver) fail(paste("same member",sender))
        parsed <- amount_spec(args[3])
        total <- converted(state,parsed$amount,parsed$currency)
        if (parsed$amount == 0 || total == 0) fail("invalid amount")
        state$serial <- state$serial+1
        settlement <- list(day=state$day,record=state$serial,sender=sender,receiver=receiver,
            amount=parsed$amount,currency=parsed$currency,total=total)
        state$settlements[[length(state$settlements)+1]] <- settlement
        return(paste0("SETTLE ",sender," -> ",receiver," ",amount_text(total),currency_note(settlement)))
    }
    if (command == "BUDGET") {
        category <- args[1]
        amount <- parse_amount(args[2])
        if (amount == 0) {
            state$budgets[[category]] <- NULL
            return(paste("BUDGET",category,"removed"))
        }
        state$budgets[[category]] <- amount
        return(paste("BUDGET",category,amount_text(amount)))
    }
    ledger_summary(command,args,line,state)
}

main <- function() {
    input <- readLines(file("stdin"),warn=FALSE)
    state <- new.env(parent=emptyenv())
    state$day <- 1
    state$serial <- 0
    state$members <- list()
    state$currencies <- list()
    state$expenses <- list()
    state$used <- character(0)
    state$settlements <- list()
    state$budgets <- list()
    for (i in seq_len(as.integer(input[1]))) {
        output <- tryCatch(execute(input[i+1],state),error=function(e) paste("ERROR",conditionMessage(e)))
        cat(paste0(output,"\n"),sep="")
    }
}
main()
