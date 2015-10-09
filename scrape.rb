require 'open-uri'
require 'pp'
require 'nokogiri'
require 'json'
require 'fileutils'

YearStart = 2014
YearTarget = 2016
CourseCode = 4650

Stem = 'http://www.monash.edu.au'
UnitCodeRegex = /[A-Z]+[0-9]+/

def get_unit_stem(year)
	"/pubs/#{year}handbooks/units"
end

class Unit
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

	UnitCodeRegex = /([A-Z]{3,3}[0-9]+)/
	def self.get(code, year)
		url = "#{Stem}#{get_unit_stem(year)}/#{code}.html"
		unit_page = Nokogiri::HTML(open(url))

		unit = Unit.new code, url
		unit.title = /: (.+) - 2/.match(unit_page.css('title').first.content)[1]

		unit.prereqs = unit_page.css('div.uge-prerequisites-content').inner_html.scan(UnitCodeRegex).flatten.uniq
		unit.coreqs = unit_page.css('div.uge-co-requisites-content').inner_html.scan(UnitCodeRegex).flatten.uniq
		unit.prohibitions = unit_page.css('div.uge-prohibitions-content').inner_html.scan(UnitCodeRegex).flatten.uniq
 
		unit.faculty = unit_page.css('p.pub_admin_faculty').first.content

		if year >= 2016 then
			offered = unit_page.css('ul.pub_highlight_value_offerings').at(0)
			unit.offered = offered.children.map { |item| item.content } if offered
		else
			offered = unit_page.css('a[href="index-bycampus-clayton.html"]')
			unit.offered = offered.map { |e| e.next_sibling.text.strip }
		end

		unit.points = /([0-9]+)/.match(unit_page.css('div.content h2')[0])[1].to_i

		unit
	end

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

def get_units_for_year(year, unit_codes)
	units = {}

	puts "=== #{year}"
	unit_codes.each do |unit_code|
		begin
			units[unit_code] = unit = Unit.get(unit_code, year)
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
					new_units[prereq] = unit = Unit.get(prereq, year)
					puts "#{unit.code}: #{unit.title}"
				end
			rescue OpenURI::HTTPError
				puts "#{prereq}: Doesn't exist"
			end
		end
		unit.coreqs.each do |coreq|
			begin
				if units[coreq].nil? && new_units[coreq].nil?
					new_units[coreq] = unit = Unit.get(coreq, year)
					puts "#{unit.code}: #{unit.title}"
				end
			rescue OpenURI::HTTPError
				puts "#{coreq}: Doesn't exist"
			end
		end
	end

	units.merge! new_units

	path = File.join('units', year.to_s)
	FileUtils.mkdir_p path
	units.each do |key, value|
		File.write(File.join(path, key + '.json'), value.to_json.to_s)
	end

	units
end

course_url = "#{Stem}/pubs/#{YearStart}handbooks/courses/#{CourseCode}.html"

course_page = open course_url
course_regex = /#{Regexp.quote(get_unit_stem(YearStart))}\/[A-Z0-9]+.html/

unit_codes = course_page.read.scan(course_regex).uniq.map { |e| UnitCodeRegex.match(e).to_s }
YearStart.upto(YearTarget) { |year| get_units_for_year(year, unit_codes) }