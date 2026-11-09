require 'fileutils'
require_relative 'policy'

module Report
  def self.path_text(path) = path.join(',')

  def self.attribute_text(attribute)
    "path #{path_text(attribute.path)} origin #{attribute.origin} med #{attribute.med} " \
      "comm #{Policy.communities_text(attribute.communities)}"
  end

  def self.route_text(route)
    return 'NONE' unless route

    communities = Policy.communities_text(route.communities)
    return "LOCAL origin #{route.origin} comm #{communities}" if route.local?

    "next #{route.neighbor} path #{path_text(route.path)} link #{route.link.name} " \
      "lp #{route.local_pref} med #{route.med} origin #{route.origin} comm #{communities}"
  end

  def self.write(reports)
    FileUtils.mkdir_p('output')
    reports.each do |filename, lines|
      File.write(File.join('output', filename), lines.map { |line| "#{line}\n" }.join, encoding: 'ASCII')
    end
  end
end
