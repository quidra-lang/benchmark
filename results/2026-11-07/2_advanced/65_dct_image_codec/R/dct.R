ZIGZAG <- do.call(rbind,lapply(1:8,function(u) cbind(u,1:8)))
ZIGZAG <- ZIGZAG[
    order(rowSums(ZIGZAG),ifelse(rowSums(ZIGZAG) %% 2L == 1L,ZIGZAG[,1L],-ZIGZAG[,1L])),
    ,
    drop=FALSE
]
rounded_shift <- function(value,shift) (value+power2(shift-1L)) %/% power2(shift)
forward_dct <- function(block,transform) {
  intermediate <- result <- matrix(0,8L,8L)
  for (u in 1:8) for (x in 1:8) {
    total <- 0
    for (y in 1:8) total <- total+transform[u,y]*(block[y,x]-128)
    intermediate[u,x] <- rounded_shift(total,11L)
  }
  for (u in 1:8) for (v in 1:8) {
    total <- 0
    for (x in 1:8) total <- total+intermediate[u,x]*transform[v,x]
    result[u,v] <- rounded_shift(total,15L)
  }
  result
}
inverse_dct <- function(coefficients,transform) {
  intermediate <- result <- matrix(0,8L,8L)
  for (y in 1:8) for (v in 1:8) {
    total <- 0
    for (u in 1:8) total <- total+transform[u,y]*coefficients[u,v]
    intermediate[y,v] <- rounded_shift(total,11L)
  }
  for (y in 1:8) for (x in 1:8) {
    total <- 0
    for (v in 1:8) total <- total+intermediate[y,v]*transform[v,x]
    result[y,x] <- clamp_byte(rounded_shift(total,15L)+128)
  }
  result
}
quantization_tables <- function(basic,quality) {
  scale <- if (quality < 50L) 5000L %/% quality else 200L-2L*quality
  setNames(lapply(basic,function(table) pmin(pmax((table*scale+50L) %/% 100L,1L),255L)),c("0","1"))
}
quantize <- function(values,table) sign(values)*((abs(values)+table %/% 2L) %/% table)
zigzag <- function(values) values[ZIGZAG]
unzigzag <- function(sequence) {
  result <- matrix(0,8L,8L)
  result[ZIGZAG] <- sequence
  result
}
dequantize <- function(sequence,table,keep=64L) {
  result <- matrix(0,8L,8L)
  positions <- ZIGZAG[seq_len(keep),,drop=FALSE]
  result[positions] <- sequence[seq_len(keep)]*table[positions]
  result
}
