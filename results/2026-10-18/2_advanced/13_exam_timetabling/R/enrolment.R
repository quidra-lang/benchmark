ascii_sort <- function(ids) sort(ids, method = "radix")
enrolment_count <- function(course) length(course$students)
read_records <- function(path) lapply(readLines(path, warn = FALSE)[-1L], function(line) strsplit(line, ",", fixed = TRUE)[[1L]])

load_courses <- function(path, state) {
  courses <- list()
  records <- read_records(path)
  for (index in seq_along(records)) {
    fields <- records[[index]]
    id <- fields[1L]
    if (id %in% names(courses)) {
      state$errors <- c(state$errors, sprintf("courses.csv line %d: duplicate course %s", index + 1L, id))
    } else {
      courses[[id]] <- list(id = id, duration = as.integer(fields[2L]), name = fields[3L], students = character())
    }
  }
  state$courses <- courses
}

load_enrolments <- function(path, state) {
  accepted <- character()
  students <- list()
  records <- read_records(path)
  for (index in seq_along(records)) {
    fields <- records[[index]]
    student <- fields[1L]
    id <- fields[2L]
    key <- paste(student, id, sep = ":")
    if (!id %in% names(state$courses)) {
      state$errors <- c(state$errors, sprintf("enrolments.csv line %d: unknown course %s", index + 1L, id))
    } else if (key %in% accepted) {
      state$errors <- c(state$errors, sprintf("enrolments.csv line %d: duplicate enrolment %s %s", index + 1L, student, id))
    } else {
      accepted <- c(accepted, key)
      state$courses[[id]]$students <- c(state$courses[[id]]$students, student)
      students[[student]] <- c(students[[student]], id)
    }
  }
  for (id in names(state$courses)) state$courses[[id]]$students <- ascii_sort(state$courses[[id]]$students)
  state$students <- lapply(students, ascii_sort)
}
