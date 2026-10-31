source("rbac.R")
source("expressions.R")
source("policy_parser.R")
source("combining.R")
source("analysis.R")

DEFINITE_DECISIONS <- c("PERMIT","DENY")
words <- function(...) paste(...,collapse=" ")
policy_error <- function(reason) structure(list(reason=reason),class="policy_error")
is_error <- function(value) inherits(value,"policy_error")
is_bag <- function(value) inherits(value,"policy_bag")
new_bag <- function(items) structure(list(items=items),class="policy_bag")
new_counts <- function() new.env(hash=TRUE,parent=emptyenv())
counter <- function(counts,key) {
  value <- counts[[as.character(key)]]
  if (is.null(value)) 0L else value
}
bump <- function(counts,key,amount=1L) counts[[as.character(key)]] <- counter(counts,key)+amount
input_value <- function(text) {
  if (text %in% c("true","false")) return(text == "true")
  if (startsWith(text,"[")) return(new_bag(if (text == "[]") character() else strsplit(
      substr(text,2L,nchar(text)-1L),
      ",",
      fixed=TRUE
  )[[1L]]))
  if (grepl("^-?[0-9]+$",text)) return(as.integer(text))
  text
}
read_attribute_fields <- function(fields) {
  result <- list()
  for (field in fields) {
    equals <- regexpr("=",field,fixed=TRUE)[1L]
    result[[substr(field,1L,equals-1L)]] <- input_value(substring(field,equals+1L))
  }
  result
}
value_notation <- function(value) {
  if (is.logical(value)) return(if (value) "true" else "false")
  if (is.integer(value)) return(as.character(value))
  if (is.character(value)) return(paste0('"',value,'"'))
  if (!length(value$items)) return("[]")
  paste0("[",paste(paste0('"',value$items,'"'),collapse=","),"]")
}
read_attributes <- function() {
  subjects <- resources <- domains <- reference <- list()
  for (line in readLines("input/attributes.txt",warn=FALSE)) {
    f <- strsplit(line," ",fixed=TRUE)[[1L]]
    if (f[1L] == "SUBJECT") subjects[[f[2L]]] <- read_attribute_fields(f[-c(
        1L,
        2L
    )]) else if (f[1L] == "RESOURCE") resources[[f[2L]]] <- list(
        type=f[3L],
        attributes=read_attribute_fields(f[-seq_len(3L)])
    ) else if (f[1L] == "DOMAIN") domains[[length(domains)+1L]] <- list(
        name=f[2L],
        values=lapply(f[-c(1L,2L)],input_value)
    ) else reference <- read_attribute_fields(f[-1L])
  }
  list(subjects=subjects,resources=resources,domains=domains,reference=reference)
}
read_requests <- function() {
  lapply(readLines("input/requests.txt",warn=FALSE),function(line) {
    f <- strsplit(line," ",fixed=TRUE)[[1L]]
    explain <- tail(f,1L) == "EXPLAIN"
    if (explain) f <- f[-length(f)]
    list(
        identifier=f[1L],
        user=f[2L],
        roles=f[3L],
        action=f[4L],
        resource=f[5L],
        environment=read_attribute_fields(f[-seq_len(5L)]),
        explain=explain
    )
  })
}
first_error <- function(values) {
  for (value in values) if (is_error(value)) return(value)
  NULL
}
boolean_result <- function(values,veto,name) {
  checked <- lapply(
      values,
      function(v) if (is.logical(v) || is_error(v)) v else policy_error(paste("type",name))
  )
  if (any(vapply(checked,function(v) identical(v,veto),logical(1)))) return(veto)
  error <- first_error(checked)
  if (is.null(error)) !veto else error
}
apply_operation <- function(name,operands) {
  error <- first_error(operands)
  if (!is.null(error)) return(error)
  if (name %in% c("+","-","*","<","<=",">",">=")) {
    if (all(vapply(operands,is.integer,logical(1)))) {
      if (length(operands) == 1L) return(-operands[[1L]])
      left <- operands[[1L]]
      right <- operands[[2L]]
      return(switch(
          name,
          "+"=left+right,
          "-"=left-right,
          "*"=left*right,
          "<"=left < right,
          "<="=left <= right,
          ">"=left > right,
          ">="=left >= right
      ))
    }
  } else if (name %in% c("==","!=")) {
    left <- operands[[1L]]
    right <- operands[[2L]]
    if (identical(
        typeof(left),
        typeof(right)
    ) && (is.integer(left) || is.logical(left) || is.character(left))) return(if (name == "==") identical(left,right) else !identical(
        left,
        right
    ))
  } else if (name == "in") {
    if (is.character(operands[[1L]]) && is_bag(operands[[2L]])) return(operands[[1L]] %in% operands[[2L]]$items)
  } else if (name == "not") {
    if (is.logical(operands[[1L]])) return(!operands[[1L]])
  } else if (name %in% c("starts_with","^=")) {
    if (all(vapply(operands,is.character,logical(1)))) return(startsWith(operands[[1L]],operands[[2L]]))
  } else if (name == "size") {
    if (is_bag(operands[[1L]])) return(length(operands[[1L]]$items))
  }
  policy_error(paste("type",name))
}
expression <- function(tree,attributes,current=NULL) {
  name <- tree$operation
  args <- tree$arguments
  if (name == "literal") return(args[[1L]])
  if (name == "attribute") {
    reference <- args[[1L]]
    return(if (reference %in% names(attributes)) attributes[[reference]] else policy_error(paste(
        "missing",
        reference
    )))
  }
  if (name == "it") return(current)
  if (name == "present") return(args[[1L]]$arguments[[1L]] %in% names(attributes))
  if (name %in% c("any_of","all_of")) {
    bag <- expression(args[[1L]],attributes,current)
    if (is_error(bag)) return(bag)
    if (!is_bag(bag)) return(policy_error(paste("type",name)))
    predicates <- lapply(bag$items,function(item) expression(args[[2L]],attributes,item))
    return(boolean_result(predicates,name == "any_of",name))
  }
  operands <- lapply(args,expression,attributes=attributes,current=current)
  if (name %in% c("and","or")) boolean_result(operands,name == "or",name) else apply_operation(name,operands)
}
target_result <- function(status,reason="") list(status=status,reason=reason)
target_group <- function(results,conjunction) {
  statuses <- vapply(results,function(r) r$status,character(1))
  if (conjunction) {
    if (any(statuses == "NO_MATCH")) return(target_result("NO_MATCH"))
    if (all(statuses == "MATCH")) return(target_result("MATCH"))
  } else if (any(statuses == "MATCH")) return(target_result("MATCH"))
  for (result in results) if (result$status == "INDETERMINATE") return(result)
  target_result("NO_MATCH")
}
match_clause <- function(clause,attributes) {
  if (!(clause$reference %in% names(attributes))) return(if (clause$mandatory) target_result(
      "INDETERMINATE",
      paste("missing",clause$reference)
  ) else target_result("NO_MATCH"))
  source <- attributes[[clause$reference]]
  items <- if (is_bag(source)) as.list(source$items) else list(source)
  comparison <- expression(clause$literal,attributes)
  results <- lapply(items,function(item) apply_operation(clause$operation,list(item,comparison)))
  if (any(vapply(results,function(v) identical(v,TRUE),logical(1)))) return(target_result("MATCH"))
  error <- first_error(results)
  if (is.null(error)) target_result("NO_MATCH") else target_result("INDETERMINATE",error$reason)
}
evaluate_target <- function(element,attributes) {
  lines <- lapply(
      element$targets,
      function(line) target_group(
          lapply(
              line,
              function(alternative) target_group(lapply(alternative,match_clause,attributes=attributes),TRUE)
          ),
          FALSE
      )
  )
  target_group(lines,TRUE)
}
new_evaluation <- function(element,target) {
  result <- new.env(parent=emptyenv())
  result$element <- element
  result$target <- target
  result$decision <- NOT_APPLICABLE
  result$reason <- ""
  result$decisive <- 0L
  result$condition <- NULL
  result$children <- result$obligations <- result$advice <- list()
  result
}
attachments <- function(result,supporters,elements,attributes) {
  for (supporter in supporters) {
    result$obligations <- c(result$obligations,supporter$obligations)
    result$advice <- c(result$advice,supporter$advice)
  }
  effect <- result$decision
  element <- elements[[result$element]]
  for (kind in c("obligations","advice")) for (definition in element[[kind]]) {
    if (definition$effect != effect) next
    evaluated <- lapply(
        definition$arguments,
        function(argument) list(name=argument$name,value=expression(argument$expression,attributes))
    )
    error <- first_error(lapply(evaluated,function(a) a$value))
    if (!is.null(error)) {
      if (kind == "obligations") {
        result$decision <- if (effect == "DENY") INDETERMINATE_D else INDETERMINATE_P
        result$reason <- paste0("obligation ",definition$identifier,": ",error$reason)
        result$decisive <- 0L
        result$obligations <- result$advice <- list()
        return(invisible(NULL))
      }
      next
    }
    suffix <- paste(
        vapply(evaluated,function(a) paste0(" ",a$name,"=",value_notation(a$value)),character(1)),
        collapse=""
    )
    item <- list(identifier=definition$identifier,text=paste0(definition$identifier,suffix))
    result[[kind]][[length(result[[kind]])+1L]] <- item
  }
  invisible(NULL)
}
evaluate_rule <- function(elements,index,attributes,coverage=NULL,obligations=TRUE) {
  element <- elements[[index]]
  result <- new_evaluation(index,evaluate_target(element,attributes))
  target <- result$target$status
  reason <- result$target$reason
  indeterminate <- if (element$behavior == "DENY") INDETERMINATE_D else INDETERMINATE_P
  if (target == "INDETERMINATE") {
    result$decision <- indeterminate
    result$reason <- reason
  } else if (target == "MATCH") {
    condition <- if (is.null(element$condition)) TRUE else expression(element$condition,attributes)
    if (!(is.logical(condition) || is_error(condition))) condition <- policy_error("type condition")
    result$condition <- condition
    if (is_error(condition)) {
      result$decision <- indeterminate
      result$reason <- condition$reason
    } else if (condition) {
      result$decision <- element$behavior
      result$decisive <- index
      if (obligations) attachments(result,list(),elements,attributes)
    }
  }
  if (!is.null(coverage)) {
    symbol <- "I"
    if (result$decision == "PERMIT") symbol <- "P"
    if (result$decision == "DENY") symbol <- "D"
    if (result$decision == NOT_APPLICABLE) symbol <- "-"
    coverage$symbols[index] <- symbol
  }
  result
}
evaluate_element <- function(elements,index,attributes,coverage=NULL) {
  element <- elements[[index]]
  if (element$kind == "rule") return(evaluate_rule(elements,index,attributes,coverage))
  result <- new_evaluation(index,evaluate_target(element,attributes))
  target <- result$target$status
  reason <- result$target$reason
  if (target == "NO_MATCH") return(result)
  combined <- combine_children(
      element$behavior,
      element$children,
      function(i) evaluate_element(elements,i,attributes,coverage),
      function(i) evaluate_target(elements[[i]],attributes),
      function(i) elements[[i]]$identifier
  )
  result$decision <- combined$decision
  result$reason <- combined$reason
  result$children <- combined$states
  if (target == "INDETERMINATE") {
    if (result$decision %in% DEFINITE_DECISIONS) result$decision <- if (result$decision == "DENY") INDETERMINATE_D else INDETERMINATE_P
    if (startsWith(result$decision,"INDETERMINATE")) result$reason <- reason
  }
  if (result$decision %in% DEFINITE_DECISIONS) {
    supporters <- lapply(
        Filter(
            function(state) !is.null(state) && state$kind == "evaluated" && state$result$decision == result$decision,
            result$children
        ),
        function(state) state$result
    )
    result$decisive <- if (length(supporters)) supporters[[1L]]$decisive else index
    attachments(result,supporters,elements,attributes)
  }
  result
}
decision_notation <- function(decision,reason) if (startsWith(decision,"INDETERMINATE")) paste0(
    decision,
    " (",
    reason,
    ")"
) else decision
final_notation <- function(result,elements) {
  text <- decision_notation(result$decision,result$reason)
  if (result$decision %in% DEFINITE_DECISIONS) paste(
      text,
      "by",
      elements[[result$decisive]]$identifier
  ) else text
}
tree_lines <- function(result,elements,depth=0L) {
  element <- elements[[result$element]]
  target <- result$target$status
  prefix <- strrep(" ",2L+2L*depth)
  line <- paste0(prefix,words(element$kind,element$identifier,element$behavior,"target",target))
  if (element$kind == "rule" && target == "MATCH") line <- paste(
      line,
      "condition",
      if (is_error(result$condition)) "INDETERMINATE" else if (result$condition) "TRUE" else "FALSE"
  )
  lines <- paste(line,"->",decision_notation(result$decision,result$reason))
  if (element$kind != "rule" && target != "NO_MATCH") for (i in seq_along(element$children)) {
    child <- elements[[element$children[i]]]
    state <- result$children[[i]]
    if (!is.null(state) && state$kind == "evaluated") lines <- c(
        lines,
        tree_lines(state$result,elements,depth+1L)
    ) else if (is.null(state)) lines <- c(
        lines,
        paste0(prefix,"  ",words(child$kind,child$identifier,"skipped"))
    ) else {
      checked <- state$target
      line <- paste0(prefix,"  ",words(child$kind,child$identifier,child$behavior,"target",checked$status))
      if (checked$status == "INDETERMINATE") line <- paste0(line," (",checked$reason,")")
      lines <- c(lines,line)
    }
  }
  lines
}
join_blocks <- function(blocks) {
  lines <- character()
  for (block in blocks) {
    if (length(lines)) lines <- c(lines,"")
    lines <- c(lines,block)
  }
  lines
}
new_engine <- function() {
  a <- new.env(parent=emptyenv())
  a$rbac <- read_rbac()
  a$elements <- read_policies()
  a$rules <- which(vapply(a$elements,function(e) e$kind == "rule",logical(1)))
  input <- read_attributes()
  a$subjects <- input$subjects
  a$resources <- input$resources
  a$domains <- input$domains
  a$reference <- input$reference
  a$requests <- read_requests()
  a$coverage <- lapply(a$elements,function(e) character())
  a$grant_counts <- a$decisions <- a$decisive <- a$obligations <- a$advice <- NULL
  a$grant_counts <- new_counts()
  a$decisions <- new_counts()
  a$decisive <- new_counts()
  a$obligations <- new_counts()
  a$advice <- new_counts()
  a$refused <- 0L
  a
}
check_request <- function(a,request) {
  if (!(request$user %in% names(a$subjects))) return(paste("unknown user",request$user))
  if (!(request$resource %in% names(a$resources))) return(paste("unknown resource",request$resource))
  day <- request$environment[["day"]]
  if (!is.integer(day) || day < 1L || day > 365L) return("bad day")
  NULL
}
activate <- function(a,user,specification,day) {
  authorized <- authorized_roles(a$rbac,user,day)
  candidates <- if (specification == "-") character() else if (specification == "*") sort(
      authorized,
      method="radix"
  ) else strsplit(
      specification,
      ",",
      fixed=TRUE
  )[[1L]]
  active <- seen <- character()
  activations <- list()
  for (candidate in candidates) {
    reason <- ""
    if (!(candidate %in% a$rbac$roles)) {
      reason <- "unknown"
    } else if (candidate %in% seen) {
      reason <- "duplicate"
    } else if (!(candidate %in% authorized)) {
      reason <- "unauthorized"
    } else {
      closure <- role_closure(a$rbac,c(active,candidate))
      for (constraint in a$rbac$dsd) if (length(intersect(
          constraint$roles,
          closure
      )) >= constraint$cardinality) {
        reason <- paste("dsd",constraint$name)
        break
      }
    }
    seen <- union(seen,candidate)
    if (!nzchar(reason)) active <- c(active,candidate)
    activations[[length(activations)+1L]] <- list(role=candidate,reason=reason)
  }
  list(activations=activations,roles=sort(role_closure(a$rbac,active),method="radix"))
}
prepare <- function(a,request) {
  activation <- activate(a,request$user,request$roles,request$environment[["day"]])
  roles <- activation$roles
  resource <- a$resources[[request$resource]]
  granted <- which(vapply(
      roles,
      function(role) has_permission(a$rbac,role,request$action,resource$type),
      logical(1)
  ))
  grant <- if (length(granted)) roles[granted[1L]] else ""
  attributes <- list()
  for (name in names(a$subjects[[request$user]])) attributes[[paste0(
      "subject.",
      name
  )]] <- a$subjects[[request$user]][[name]]
  attributes$subject.id <- request$user
  attributes$subject.role <- new_bag(roles)
  attributes$subject.rbac <- nzchar(grant)
  for (name in names(resource$attributes)) attributes[[paste0(
      "resource.",
      name
  )]] <- resource$attributes[[name]]
  attributes$resource.id <- request$resource
  attributes$resource.type <- resource$type
  attributes$action.id <- request$action
  for (name in names(request$environment)) attributes[[paste0(
      "environment.",
      name
  )]] <- request$environment[[name]]
  list(activations=activation$activations,roles=roles,grant=grant,attributes=attributes)
}
request_trace <- function(a,request,prepared,result) {
  lines <- c(
      paste("request",request$identifier),
      paste0(
          "  ",
          words(
              "user",
              request$user,
              "resource",
              request$resource,
              "type",
              a$resources[[request$resource]]$type,
              "action",
              request$action,
              "day",
              request$environment[["day"]]
          )
      )
  )
  for (activation in prepared$activations) lines <- c(
      lines,
      paste0(
          "  activate ",
          activation$role,
          if (nzchar(activation$reason)) paste0(" refused ",activation$reason) else " ok"
      )
  )
  lines <- c(
      lines,
      paste0("  roles ",if (length(prepared$roles)) paste(prepared$roles,collapse=",") else "-"),
      paste0("  rbac ",if (nzchar(prepared$grant)) paste("yes",prepared$grant) else "no"),
      tree_lines(result,a$elements),
      paste0("  decision ",final_notation(result,a$elements))
  )
  lines
}
grant_key <- function(role,action,type) paste(role,action,type,sep=",")
process_requests <- function(a) {
  lines <- character()
  explanations <- list()
  for (request in a$requests) {
    coverage <- new.env(parent=emptyenv())
    coverage$symbols <- rep(".",length(a$elements))
    error <- check_request(a,request)
    if (!is.null(error)) {
      lines <- c(lines,words(request$identifier,"ERROR",error))
      bump(a$decisions,"ERROR")
      if (request$explain) explanations[[length(explanations)+1L]] <- c(
          paste("request",request$identifier),
          paste0("  error ",error)
      )
    } else {
      prepared <- prepare(a,request)
      result <- evaluate_element(a$elements,1L,prepared$attributes,coverage)
      lines <- c(lines,paste(request$identifier,final_notation(result,a$elements)))
      for (activation in prepared$activations) if (nzchar(activation$reason)) {
        lines <- c(lines,paste0("  refused ",activation$role," ",activation$reason))
        a$refused <- a$refused+1L
      }
      for (kind in c("obligation","advice")) {
        items <- if (kind == "obligation") result$obligations else result$advice
        counts <- if (kind == "obligation") a$obligations else a$advice
        for (item in items) {
          lines <- c(lines,paste0("  ",kind," ",item$text))
          bump(counts,item$identifier)
        }
      }
      if (nzchar(prepared$grant)) bump(
          a$grant_counts,
          grant_key(prepared$grant,request$action,a$resources[[request$resource]]$type)
      )
      category <- if (startsWith(result$decision,"INDETERMINATE")) "INDETERMINATE" else result$decision
      bump(a$decisions,category)
      if (result$decision %in% DEFINITE_DECISIONS) bump(a$decisive,result$decisive)
      if (request$explain) explanations[[length(explanations)+1L]] <- request_trace(a,request,prepared,result)
    }
    for (rule in a$rules) a$coverage[[rule]] <- c(a$coverage[[rule]],coverage$symbols[rule])
  }
  list(decisions=lines,traces=join_blocks(explanations))
}
permission_report <- function(a) {
  blocks <- list()
  users <- sort(unique(vapply(a$rbac$assignments,function(x) x$user,character(1))),method="radix")
  for (user in users) {
    assigned <- authorized <- list()
    for (x in a$rbac$assignments) if (x$user == user) assigned[[x$role]] <- union(
        assigned[[x$role]],
        seq.int(x$first,x$last)
    )
    for (role in names(assigned)) for (inherited in role_closure(
        a$rbac,
        role
    )) authorized[[inherited]] <- union(
        authorized[[inherited]],
        assigned[[role]]
    )
    lines <- paste("user",user)
    for (kind in c("assigned","authorized")) {
      sets <- if (kind == "assigned") assigned else authorized
      for (role in sort(names(sets),method="radix")) lines <- c(
          lines,
          paste0("  ",words(kind,role,day_notation(sets[[role]])))
      )
    }
    via <- list()
    for (role in sort(names(authorized),method="radix")) for (permission in a$rbac$permissions[[role]]) {
      key <- paste(permission$action,permission$type,sep=",")
      if (is.null(via[[key]])) via[[key]] <- list(
          action=permission$action,
          type=permission$type,
          roles=character()
      )
      via[[key]]$roles <- c(via[[key]]$roles,role)
    }
    if (length(via)) via <- via[order(
        vapply(via,function(p) p$action,character(1)),
        vapply(via,function(p) p$type,character(1)),
        method="radix"
    )]
    for (permission in via) {
      days <- integer()
      for (role in permission$roles) days <- union(days,authorized[[role]])
      effective <- "-"
      if (user %in% names(a$subjects)) {
        resources <- names(a$resources)[vapply(a$resources,function(r) r$type == permission$type,logical(1))]
        permitted <- 0L
        for (resource in resources) {
          request <- list(
              identifier="",
              user=user,
              roles="*",
              action=permission$action,
              resource=resource,
              environment=a$reference,
              explain=FALSE
          )
          prepared <- prepare(a,request)
          if (evaluate_element(
              a$elements,
              1L,
              prepared$attributes
          )$decision == "PERMIT") permitted <- permitted+1L
        }
        effective <- paste(permitted,length(resources),sep="/")
      }
      lines <- c(
          lines,
          paste0(
              "  ",
              words(
                  "permission",
                  permission$action,
                  permission$type,
                  day_notation(days),
                  "via",
                  paste(permission$roles,collapse=","),
                  "effective",
                  effective
              )
          )
      )
    }
    blocks[[length(blocks)+1L]] <- lines
  }
  join_blocks(blocks)
}
domain_analysis <- function(a) {
  counts <- integer(length(a$elements))
  examples <- rep("-",length(a$elements))
  shadowed <- a$rules[vapply(
      a$rules,
      function(i) a$elements[[a$elements[[i]]$parent]]$behavior == "first-applicable",
      logical(1)
  )]
  blockers <- lapply(a$elements,function(e) integer())
  ancestors <- lapply(a$elements,function(e) integer())
  for (i in a$rules) {
    chain <- integer()
    parent <- a$elements[[i]]$parent
    while (parent != 0L) {
      chain <- c(chain,parent)
      parent <- a$elements[[parent]]$parent
    }
    ancestors[[i]] <- chain
  }
  pairs <- list()
  for (policy in a$elements) if (policy$kind == "policy") for (position in seq_along(policy$children)) {
    if (position >= length(policy$children)) next
    earlier <- policy$children[position]
    for (later in policy$children[seq.int(
        position+1L,
        length(policy$children)
    )]) if (a$elements[[earlier]]$behavior != a$elements[[later]]$behavior) pairs[[length(pairs)+1L]] <- c(
        policy$index,
        earlier,
        later
    )
  }
  conflict_counts <- integer(length(pairs))
  point_count <- 0L
  for (attributes in domain_points(a$domains)) {
    point_count <- point_count+1L
    targets <- rep("",length(a$elements))
    for (element in a$elements) if (element$kind != "rule") targets[element$index] <- evaluate_target(
        element,
        attributes
    )$status
    standalone <- rep(NOT_APPLICABLE,length(a$elements))
    for (i in a$rules) standalone[i] <- evaluate_rule(a$elements,i,attributes,obligations=FALSE)$decision
    applying <- integer()
    for (i in a$rules) {
      if (!(standalone[i] %in% DEFINITE_DECISIONS) || !all(targets[ancestors[[i]]] == "MATCH")) next
      applying <- c(applying,i)
      counts[i] <- counts[i]+1L
      if (counts[i] == 1L) examples[i] <- paste(
          vapply(
              Filter(function(d) length(d$values) >= 2L,a$domains),
              function(d) paste0(d$name,"=",value_notation(attributes[[d$name]])),
              character(1)
          ),
          collapse=" "
      )
      if (i %in% shadowed) {
        earlier <- rule_blocker(a$elements[[i]],a$elements,standalone)
        if (earlier == 0L) shadowed <- setdiff(shadowed,i) else blockers[[i]] <- union(blockers[[i]],earlier)
      }
    }
    for (i in seq_along(pairs)) if (pairs[[i]][2L] %in% applying && pairs[[i]][3L] %in% applying) conflict_counts[i] <- conflict_counts[i]+1L
  }
  lines <- paste("applicability",point_count)
  for (i in a$rules) lines <- c(lines,paste0("  ",words(a$elements[[i]]$identifier,counts[i],examples[i])))
  dead <- a$rules[counts[a$rules] == 0L]
  lines <- c(
      lines,
      paste("dead",length(dead)),
      vapply(dead,function(i) paste0("  ",a$elements[[i]]$identifier),character(1))
  )
  shadowed <- setdiff(shadowed,dead)
  lines <- c(lines,paste("shadowed",length(shadowed)))
  for (i in a$rules) if (i %in% shadowed) {
    ids <- vapply(a$rules[a$rules %in% blockers[[i]]],function(j) a$elements[[j]]$identifier,character(1))
    lines <- c(lines,paste0("  ",a$elements[[i]]$identifier," by ",paste(ids,collapse=",")))
  }
  lines <- c(lines,paste("conflicts",sum(conflict_counts > 0L)))
  for (i in seq_along(pairs)) {
    if (conflict_counts[i] == 0L) next
    pair <- pairs[[i]]
    policy <- a$elements[[pair[1L]]]
    earlier <- a$elements[[pair[2L]]]
    later <- a$elements[[pair[3L]]]
    winner <- conflict_winner(policy,earlier,later)
    lines <- c(
        lines,
        paste0(
            "  ",
            words(
                policy$identifier,
                earlier$identifier,
                later$identifier,
                conflict_counts[i],
                a$elements[[winner]]$identifier
            )
        )
    )
  }
  lines
}
analysis_report <- function(a) {
  lines <- paste("rbac",length(a$rbac$diagnostics))
  for (diagnostic in a$rbac$diagnostics) lines <- c(
      lines,
      paste0("  ",words("line",diagnostic$line,diagnostic$keyword,diagnostic$message))
  )
  grants <- a$rbac$grants
  grants <- grants[order(
      vapply(grants,function(g) g$role,character(1)),
      vapply(grants,function(g) g$action,character(1)),
      vapply(grants,function(g) g$type,character(1)),
      method="radix"
  )]
  lines <- c(lines,paste("grants",length(grants)))
  for (grant in grants) lines <- c(
      lines,
      paste0(
          "  ",
          words(
              grant$role,
              grant$action,
              grant$type,
              counter(a$grant_counts,grant_key(grant$role,grant$action,grant$type))
          )
      )
  )
  lines <- c(lines,domain_analysis(a),paste("coverage",length(a$requests)))
  uncovered <- integer()
  for (i in a$rules) {
    symbols <- a$coverage[[i]]
    n <- sum(symbols %in% c("P","D"))
    lines <- c(lines,paste0("  ",words(a$elements[[i]]$identifier,paste(symbols,collapse=""),n)))
    if (n == 0L) uncovered <- c(uncovered,i)
  }
  lines <- c(
      lines,
      paste("uncovered",length(uncovered)),
      vapply(uncovered,function(i) paste0("  ",a$elements[[i]]$identifier),character(1)),
      "summary"
  )
  for (name in c("PERMIT","DENY",NOT_APPLICABLE,"INDETERMINATE","ERROR")) lines <- c(
      lines,
      paste0("  decision ",name," ",counter(a$decisions,name))
  )
  lines <- c(lines,paste0("  refused ",a$refused))
  for (element in a$elements) {
    n <- counter(a$decisive,element$index)
    if (n > 0L) lines <- c(lines,paste0("  decisive ",element$identifier," ",n))
  }
  for (kind in c("obligation","advice")) {
    counts <- if (kind == "obligation") a$obligations else a$advice
    for (id in sort(ls(counts,all.names=TRUE),method="radix")) lines <- c(
        lines,
        paste0("  ",kind," ",id," ",counter(counts,id))
    )
  }
  lines
}
main <- function() {
  a <- new_engine()
  requests <- process_requests(a)
  outputs <- list(
      "decisions.txt"=requests$decisions,
      "traces.txt"=requests$traces,
      "permissions.txt"=permission_report(a),
      "analysis.txt"=analysis_report(a)
  )
  dir.create("output",showWarnings=FALSE)
  for (name in names(outputs)) {
    connection <- file(paste0("output/",name),"wb")
    if (length(outputs[[name]])) writeChar(
        paste0(paste(outputs[[name]],collapse="\n"),"\n"),
        connection,
        eos=NULL,
        useBytes=TRUE
    )
    close(connection)
  }
}
main()
