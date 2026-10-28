read_inputs <- function() {
  read_integer_csv <- function(path) lapply(strsplit(readLines(path)[-1L],",",fixed=TRUE),as.numeric)
  training <- read_integer_csv("input/ratings.csv")
  tests <- read_integer_csv("input/test.csv")
  users <- sort(unique(vapply(training,`[`,numeric(1),1L)))
  items <- sort(unique(vapply(training,`[`,numeric(1),2L)))
  train <- lapply(
      training,
      function(r) list(u=match(r[1L],users),i=match(r[2L],items),rating=r[3L],time=r[4L])
  )
  test <- lapply(tests,function(r) list(u=match(r[1L],users),i=match(r[2L],items),rating=r[3L]))
  catalog <- list()
  for (row in strsplit(readLines("input/items.csv")[-1L],",",fixed=TRUE)) catalog[[row[1L]]] <-
    list(title=row[2L],genre_text=row[3L],genres=strsplit(row[3L],"|",fixed=TRUE)[[1L]])
  ratings <- matrix(0,length(users),length(items))
  for (r in train) ratings[r$u,r$i] <- r$rating
  by_user <- lapply(seq_along(users),function(u) which(ratings[u,] > 0))
  by_item <- lapply(seq_along(items),function(i) which(ratings[,i] > 0))
  user_counts <- lengths(by_user)
  item_counts <- lengths(by_item)
  user_means <- vapply(seq_along(users),function(u) sum(ratings[u,by_user[[u]]])/user_counts[u],numeric(1))
  item_means <- vapply(seq_along(items),function(i) sum(ratings[by_item[[i]],i])/item_counts[i],numeric(1))
  params <- list()
  for (line in readLines("input/params.txt")) {
    words <- strsplit(line," ",fixed=TRUE)[[1L]]
    params[[words[1L]]] <- as.numeric(words[-1L])
  }
  list(users=users,items=items,training=train,test=test,catalog=length(catalog),
    titles=vapply(items,function(id) catalog[[sprintf("%.0f",id)]]$title,character(1)),
    genre_text=vapply(items,function(id) catalog[[sprintf("%.0f",id)]]$genre_text,character(1)),
    genres=lapply(
        items,
        function(id) catalog[[sprintf("%.0f",id)]]$genres
    ),ratings=ratings,by_user=by_user,by_item=by_item,
    user_counts=user_counts,item_counts=item_counts,user_means=user_means,item_means=item_means,
    mean=sum(vapply(train,`[[`,numeric(1),"rating"))/length(train),params=params)
}
