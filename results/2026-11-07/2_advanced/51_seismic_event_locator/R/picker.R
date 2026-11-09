make_pick <- function(station,sample,duration,ratio,amplitude,clipped) {
  pick <- new.env(parent=emptyenv())
  pick$station <- station
  pick$sample <- sample
  pick$duration <- duration
  pick$ratio <- ratio
  pick$amplitude <- amplitude
  pick$clipped <- clipped
  pick$state <- "unassociated"
  pick$event <- 0L
  pick$residual <- NULL
  pick$first_residual <- NULL
  pick$assigned <- FALSE
  pick
}
detect_station <- function(station,params) {
  samples <- station$samples
  n <- length(samples)
  mean <- floor(sum(samples)/n)
  detrended <- samples-mean
  energy <- detrended*detrended
  sw <- params$sta_window[1L]
  lw <- params$lta_window[1L]
  on_num <- params$trigger_on[1L]
  on_den <- params$trigger_on[2L]
  off_num <- params$trigger_off[1L]
  off_den <- params$trigger_off[2L]
  prefix <- c(0,cumsum(energy))
  picks <- list()
  triggers <- short_triggers <- 0L
  on <- FALSE
  beginning <- 0L
  peak_ratio <- 0
  finish <- function(ending) {
    triggers <<- triggers+1L
    duration <- ending-beginning
    if (duration < params$min_duration[1L]) {
      short_triggers <<- short_triggers+1L
      return(invisible(NULL))
    }
    position <- beginning
    while (position-1L >= beginning-sw+1L && energy[position] >= params$noise_level[1L]) position <- position-1L
    last_index <- min(position+params$amplitude_window[1L],n)
    indices <- seq.int(position+1L,last_index)
    amplitude <- max(abs(detrended[indices]))
    clipped <- any(abs(samples[indices]) >= params$clip_level[1L])
    picks[[length(picks)+1L]] <<- make_pick(
        station$order,
        station$start+position,
        duration,
        peak_ratio,
        amplitude,
        clipped
    )
  }
  for (i in seq.int(sw+lw-1L,n-1L)) {
    sta <- prefix[i+2L]-prefix[i-sw+2L]
    lta <- prefix[i-sw+2L]-prefix[i-sw-lw+2L]
    if (!on) {
      if (sta*lw*on_den >= on_num*lta*sw) {
        on <- TRUE
        beginning <- i
        peak_ratio <- (sta*lw)/(lta*sw)
      }
    } else if (sta*lw*off_den < off_num*lta*sw) {
      finish(i)
      on <- FALSE
    } else peak_ratio <- max(peak_ratio,(sta*lw)/(lta*sw))
  }
  if (on) finish(n)
  stats <- list(
      mean=mean,
      noise=median_value(abs(detrended)),
      peak=max(abs(detrended)),
      clipped=sum(abs(samples) >= params$clip_level[1L]),
      triggers=triggers,
      short=short_triggers
  )
  list(picks=picks,stats=stats)
}
