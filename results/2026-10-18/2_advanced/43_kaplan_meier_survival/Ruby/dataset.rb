module Dataset
  Subject = Struct.new(:id, :group, :time, :event, :age, :sex, :stage, keyword_init: true)
  module_function

  def read(directory)
    subjects = File.readlines(File.join(directory, "subjects.csv"), chomp: true).drop(1).map do |line|
      id, group, time, event, age, sex, stage = line.split(",")
      Subject.new(id: id.to_i, group: group, time: time.to_i, event: event.to_i,
                  age: age.to_i, sex: sex, stage: stage.to_i)
    end
    subjects.sort_by!(&:id)
    fields = File.foreach(File.join(directory, "params.txt")).to_h do |line|
      name, *values = line.split
      [name, values]
    end
    params = {
      groups: fields.fetch("GROUPS"),
      report_times: fields.fetch("REPORT_TIMES").map(&:to_i),
      tau: fields.fetch("TAU").first.to_i,
      life_table: fields.fetch("LIFE_TABLE").map(&:to_i),
      strata: fields.fetch("STRATA").first,
      subgroups: fields.fetch("SUBGROUPS"),
      landmark: fields.fetch("LANDMARK").first.to_i,
      covariates: fields.fetch("COX"),
      residuals: fields.fetch("RESIDUALS").first.to_i,
      plot: fields.fetch("PLOT").map(&:to_i)
    }
    [subjects, params]
  end
end
