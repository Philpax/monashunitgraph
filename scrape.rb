require 'open-uri'
require 'pp'
require 'nokogiri'
require 'json'
require 'fileutils'

YearStart = 2014
YearTarget = 2016
CourseCode = 4650

Stem = 'http://www.monash.edu.au'
UnitStartStem = "/pubs/#{YearStart}handbooks/units"
UnitTargetStem = "/pubs/#{YearTarget}handbooks/units"
UnitCodeRegex = /[A-Z]+[0-9]+/

class JSONable
    def to_json
        hash = {}
        self.instance_variables.each do |var|
            hash[var[1..-1]] = self.instance_variable_get var
        end
        hash.to_json
    end
    def from_json! string
        JSON.load(string).each do |var, val|
            self.instance_variable_set "@" + var, val
        end
    end
end

class Unit < JSONable
	attr_accessor :code
	attr_accessor :prereqs
	attr_accessor :coreqs
	attr_accessor :prohibitions
	attr_accessor :title
	attr_accessor :url
	attr_accessor :faculty
	attr_accessor :offered
	attr_accessor :points

	def initialize(code, url)
		@code = code
		@prereqs = []
		@coreqs = []
		@title = ""
		@faculty = ""
		@url = url
		@offered = []
		@points = 0
	end

	def self.get(code)
		url = "#{Stem}#{UnitTargetStem}/#{code}.html"
		unit_page = Nokogiri::HTML(open(url))

		unit = Unit.new code, url
		unit.title = /: (.+) - 2/.match(unit_page.css('title').first.content)[1]

		unit.prereqs = unit_page.css('div.uge-prerequisites-content').inner_html.scan(/([A-Z]{3,3}[0-9]+)/).flatten.uniq
		unit.coreqs = unit_page.css('div.uge-co-requisites-content').inner_html.scan(/([A-Z]{3,3}[0-9]+)/).flatten.uniq
		unit.prohibitions = unit_page.css('div.uge-prohibitions-content').inner_html.scan(/([A-Z]{3,3}[0-9]+)/).flatten.uniq
 
		unit.faculty = unit_page.css('p.pub_admin_faculty').first.content

		offered = unit_page.css('ul.pub_highlight_value_offerings').at(0)
		unit.offered = offered.children.map { |item| item.content } if offered

		unit.points = /([0-9]+)/.match(unit_page.css('div.content h2')[0])[1].to_i

		unit
	end
end

course_url = "#{Stem}/pubs/#{YearStart}handbooks/courses/#{CourseCode}.html"

course_page = open course_url
course_regex = /#{Regexp.quote(UnitStartStem)}\/[A-Z0-9]+.html/

unit_urls = course_page.read.scan(course_regex).uniq.map do |e| 
	Stem + e.gsub("#{YearStart}handbooks", "#{YearTarget}handbooks")
end

units = {}

unit_urls.each do |url|
	unit_code = UnitCodeRegex.match(url).to_s 
	begin
		units[unit_code] = unit = Unit.get(unit_code)
		puts "#{unit.code}: #{unit.title}"
	rescue OpenURI::HTTPError
		puts "#{unit_code}: Doesn't exist"
	end
end

puts "Getting additional units"
new_units = {}
units.each_value do |unit|
	unit.prereqs.each do |prereq|
		begin
			if units[prereq].nil? && new_units[prereq].nil?
				new_units[prereq] = unit = Unit.get(prereq)
				puts "#{unit.code}: #{unit.title}"
			end
		rescue OpenURI::HTTPError
			puts "#{prereq}: Doesn't exist"
		end
	end
	unit.coreqs.each do |coreq|
		begin
			if units[coreq].nil? && new_units[coreq].nil?
				new_units[coreq] = unit = Unit.get(coreq)
				puts "#{unit.code}: #{unit.title}"
			end
		rescue OpenURI::HTTPError
			puts "#{coreq}: Doesn't exist"
		end
	end
end

units.merge! new_units

FileUtils.mkdir_p 'units'
units.each do |key, value|
	File.write(File.join('units', key + '.json'), value.to_json.to_s)
end