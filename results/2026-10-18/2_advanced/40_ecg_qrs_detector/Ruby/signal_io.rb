require "fileutils"

module SignalIO
  Annotation = Struct.new(:sample, :label, :beat, keyword_init: true)

  module_function

  def read_ecg(path = "input/ecg.csv")
    File.readlines(path, chomp: true).drop(1).map { |line| line.split(",")[1].to_i }
  end

  def read_annotations(path = "input/annotations.csv")
    File.readlines(path, chomp: true).drop(1).map do |line|
      sample, label = line.split(",")
      Annotation.new(sample: sample.to_i, label: label)
    end
  end

  def read_params(path = "input/params.txt")
    File.readlines(path, chomp: true).to_h do |line|
      name, value = line.split(" ")
      [name.to_sym, value.to_i]
    end
  end

  def write_lines(name, lines)
    FileUtils.mkdir_p("output")
    File.binwrite(File.join("output", name), lines.map { |line| "#{line}\n" }.join)
  end
end
