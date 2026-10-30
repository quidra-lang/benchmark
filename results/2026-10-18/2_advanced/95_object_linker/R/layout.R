align_address <- function(value, alignment) (value + alignment - 1) %/% alignment * alignment
new_output_section <- function(name, segment) {
  new_record(name = name, segment = segment, nobits = is_nobits(name), sections = list(),
             base_components = list(), components = list(), address = 0, size = 0, alignment = 1L)
}
new_segment <- function(name, base, length, fill, output_names) {
  segment <- new_record(name = name, base = base, length = length, fill = fill, outputs = list(),
                        paddr = base, filesz = 0L, memsz = 0, used = 0, image = integer())
  segment$outputs <- lapply(output_names, new_output_section, segment = segment)
  segment
}
find_output <- function(section_name, outputs) {
  for (output in outputs) if (belongs(section_name, output$name)) return(output)
  NULL
}
assign_segment <- function(segment) {
  cursor <- segment$base
  segment$filesz <- 0L
  for (output in segment$outputs) {
    output$alignment <- if (length(output$components)) max(vapply(output$components, function(component) component$alignment, integer(1L))) else 1L
    cursor <- align_address(cursor, output$alignment)
    output$address <- cursor
    for (component in output$components) {
      cursor <- align_address(cursor, component$alignment)
      component$address <- cursor
      cursor <- cursor + component$size
    }
    output$size <- cursor - output$address
    if (!output$nobits) segment$filesz <- as.integer(cursor - segment$base)
  }
  segment$memsz <- cursor - segment$base
}
