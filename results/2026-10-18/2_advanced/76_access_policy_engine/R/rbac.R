new_rbac <- function() {
  r <- new.env(parent=emptyenv())
  r$roles <- character()
  r$inherits <- r$permissions <- list()
  r$ssd <- r$dsd <- r$assignments <- r$diagnostics <- r$grants <- list()
  r
}
role_closure <- function(rbac,roles) {
  reached <- pending <- unique(roles)
  while (length(pending)) {
    role <- tail(pending,1L)
    pending <- pending[-length(pending)]
    for (junior in rbac$inherits[[role]]) if (!(junior %in% reached)) {
      reached <- c(reached,junior)
      pending <- c(pending,junior)
    }
  }
  reached
}
inheritance_path <- function(rbac,start,finish) {
  failed <- character()
  visit <- function(role) {
    if (role == finish) return(role)
    if (!(role %in% failed)) {
      for (junior in sort(rbac$inherits[[role]],method="radix")) {
        suffix <- visit(junior)
        if (!is.null(suffix)) return(c(role,suffix))
      }
      failed <<- c(failed,role)
    }
    NULL
  }
  visit(start)
}
assigned_roles <- function(rbac,user,day) unique(vapply(
    Filter(function(a) a$user == user && a$first <= day && day <= a$last,rbac$assignments),
    function(a) a$role,
    character(1)
))
authorized_roles <- function(rbac,user,day) role_closure(rbac,assigned_roles(rbac,user,day))
has_permission <- function(rbac,role,action,resource_type) any(vapply(
    rbac$permissions[[role]],
    function(p) p$action == action && p$type == resource_type,
    logical(1)
))
accept_rbac <- function(r,keyword,f) {
  if (keyword == "ROLE") {
    role <- f[1L]
    if (role %in% r$roles) return(paste("duplicate role",role))
    r$roles <- c(r$roles,role)
    r$inherits[[role]] <- character()
    r$permissions[[role]] <- list()
  } else if (keyword == "INHERITS") {
    senior <- f[1L]
    junior <- f[2L]
    for (role in c(senior,junior)) if (!(role %in% r$roles)) return(paste("unknown role",role))
    if (junior %in% r$inherits[[senior]]) return(paste("duplicate inheritance",senior,junior))
    if (senior %in% role_closure(r,junior)) return(paste(
        "cycle",
        paste(c(senior,inheritance_path(r,junior,senior)),collapse=" > ")
    ))
    r$inherits[[senior]] <- c(r$inherits[[senior]],junior)
  } else if (keyword == "PERMIT") {
    role <- f[1L]
    action <- f[2L]
    resource_type <- f[3L]
    if (!(role %in% r$roles)) return(paste("unknown role",role))
    if (has_permission(r,role,action,resource_type)) return(paste(
        "duplicate permission",
        role,
        action,
        resource_type
    ))
    r$permissions[[role]][[length(r$permissions[[role]])+1L]] <- list(action=action,type=resource_type)
    r$grants[[length(r$grants)+1L]] <- list(role=role,action=action,type=resource_type)
  } else if (keyword %in% c("SSD","DSD")) {
    name <- f[1L]
    constraints <- if (keyword == "SSD") r$ssd else r$dsd
    if (any(vapply(
        constraints,
        function(c) c$name == name,
        logical(1)
    ))) return(paste("duplicate constraint",name))
    roles <- strsplit(f[3L],",",fixed=TRUE)[[1L]]
    for (role in roles) if (!(role %in% r$roles)) return(paste("unknown role",role))
    cardinality <- as.integer(f[2L])
    if (cardinality < 2L || cardinality > length(roles)) return(paste("bad cardinality",name,cardinality))
    constraint <- list(name=name,cardinality=cardinality,roles=roles)
    if (keyword == "SSD") r$ssd[[length(r$ssd)+1L]] <- constraint else r$dsd[[length(r$dsd)+1L]] <- constraint
  } else {
    user <- f[1L]
    role <- f[2L]
    if (!(role %in% r$roles)) return(paste("unknown role",role))
    first <- as.integer(f[3L])
    last <- as.integer(f[4L])
    if (!(1L <= first && first <= last && last <= 365L)) return(paste("bad range",first,last))
    for (constraint in r$ssd) for (day in seq.int(first,last)) {
      roles <- intersect(constraint$roles,role_closure(r,union(assigned_roles(r,user,day),role)))
      if (length(roles) >= constraint$cardinality) return(paste(
          "ssd",
          constraint$name,
          "day",
          day,
          "roles",
          paste(sort(roles,method="radix"),collapse=",")
      ))
    }
    r$assignments[[length(r$assignments)+1L]] <- list(user=user,role=role,first=first,last=last)
  }
  NULL
}
read_rbac <- function() {
  r <- new_rbac()
  lines <- strsplit(readLines("input/rbac.txt",warn=FALSE)," ",fixed=TRUE)
  for (keyword in c("ROLE","INHERITS","PERMIT","SSD","DSD","ASSIGN")) for (i in seq_along(lines)) {
    f <- lines[[i]]
    if (f[1L] != keyword) next
    error <- accept_rbac(r,keyword,f[-1L])
    if (!is.null(error)) r$diagnostics[[length(r$diagnostics)+1L]] <- list(
        line=i,
        keyword=keyword,
        message=error
    )
  }
  r$diagnostics <- r$diagnostics[order(vapply(r$diagnostics,function(d) d$line,integer(1)))]
  r
}
