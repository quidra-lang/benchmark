parse_datetime <- function(text) as.POSIXct(text,format="%Y-%m-%d %H:%M",tz="UTC")
epoch_hours <- function(epoch,instant) as.integer(difftime(instant,epoch,units="hours"))
format_datetime <- function(instant) paste0(
    sprintf("%04d",as.integer(format(instant,"%Y",tz="UTC"))),
    format(instant,"-%m-%d %H:%M",tz="UTC")
)
datetime_at_hour <- function(epoch,hour) format_datetime(epoch+3600*hour)
datetime_at_minute <- function(epoch,minute) format_datetime(epoch+60*minute)
date_at_day <- function(epoch,day) substring(format_datetime(epoch+86400*day),1L,10L)
read_all_inputs <- function() {
  lines <- readLines("input/params.txt")
  epoch <- parse_datetime(substring(lines[1L],7L))
  stations <- list()
  cursor <- 2L
  while (startsWith(lines[cursor],"station ")) {
    fields <- strsplit(lines[cursor]," ",fixed=TRUE)[[1L]]
    stations[[length(stations)+1L]] <- list(code=fields[2L],name=paste(fields[-(1:2)],collapse=" "))
    cursor <- cursor+1L
  }
  values <- list()
  for (line in lines[seq.int(cursor,length(lines))]) {
    at <- regexpr(" ",line,fixed=TRUE)[1L]
    values[[substring(line,1L,at-1L)]] <- substring(line,at+1L)
  }
  spike <- strsplit(values$spike," ",fixed=TRUE)[[1L]]
  surge <- strsplit(values$surge," ",fixed=TRUE)[[1L]]
  prediction <- strsplit(values$predict," ",fixed=TRUE)[[1L]]
  plot <- strsplit(values$plot," ",fixed=TRUE)[[1L]]
  settings <- list(
      epoch=epoch,
      stations=stations,
      reference=values$reference,
      flat_run=as.integer(values$flat_run),
      spike_window=as.integer(spike[1L]),
      spike_minimum=as.integer(spike[2L]),
      spike_factor=as.numeric(spike[3L]),
      spike_floor=as.numeric(spike[4L]),
      rayleigh=as.numeric(values$rayleigh),
      snr_min=as.numeric(values$snr_min),
      top_residuals=as.integer(values$top_residuals),
      surge_threshold=as.numeric(surge[1L]),
      surge_hours=as.integer(surge[2L]),
      prediction_start=parse_datetime(paste(prediction[1:2],collapse=" ")),
      prediction_hours=as.integer(prediction[3L]),
      grid_minutes=as.integer(values$grid_minutes),
      min_range=as.numeric(values$min_range),
      correlation_lag=as.integer(values$correlation_lag),
      plot_code=plot[1L],
      plot_hours=as.integer(plot[2L]),
      plot_top=as.integer(plot[3L]),
      plot_bottom=as.integer(plot[4L]),
      plot_step=as.integer(plot[5L])
  )
  constituents <- lapply(
      strsplit(readLines("input/constituents.txt")[-1L]," ",fixed=TRUE),
      function(fields) list(name=fields[1L],speed=as.numeric(fields[2L]))
  )
  observations <- setNames(
      lapply(stations,function(unused) list(values=numeric(),rows=0L)),
      vapply(stations,function(station) station$code,character(1))
  )
  for (line in readLines("input/observations.csv")[-1L]) {
    fields <- strsplit(line,",",fixed=TRUE)[[1L]]
    code <- fields[1L]
    t <- epoch_hours(epoch,parse_datetime(fields[2L]))
    observations[[code]]$values[as.character(t)] <- if (fields[3L] == "NA") NA_real_ else as.numeric(fields[3L])
    observations[[code]]$rows <- observations[[code]]$rows+1L
  }
  list(settings=settings,constituents=constituents,observations=observations)
}
