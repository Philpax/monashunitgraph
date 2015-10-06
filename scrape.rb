require 'open-uri'
require 'pp'
require 'nokogiri'
require 'json'

year_start = 2014
year_target = 2016
course_code = 4650

stem = 'http://www.monash.edu.au'

course_url = "#{stem}/pubs/#{year_start}handbooks/courses/4650.html"

course_page = open course_url
course_regex = /\/pubs\/#{year_start}handbooks\/units\/[A-Z0-9]+.html/

unit_urls = course_page.read.scan(course_regex).uniq.map do |e| 
	stem + e.gsub("#{year_start}handbooks", "#{year_target}handbooks")
end

class Unit
	attr_reader :code
	attr_reader :prereqs
	attr_reader :coreqs
	attr_reader :leads_to
	attr_accessor :title
	attr_accessor :url

	def initialize(code, url)
		@code = code
		@prereqs = []
		@coreqs = []
		@leads_to = []
		@title = ""
		@url = url
	end

	def add_prereq(prereq)
		@prereqs.push prereq
	end

	def add_coreq(prereq)
		@coreqs.push prereq
	end

	def add_leads_to(lead)
		@leads_to.push(lead)
	end
end

units = {}

unit_code_regex = /[A-Z]+[0-9]+/
unit_urls.each do |url|
	unit_code = unit_code_regex.match(url).to_s 
	units[unit_code] = unit = Unit.new unit_code, url
	begin
		unit_page = Nokogiri::HTML(open(url))
		unit_title = /: (.+) - 2/.match(unit_page.css('title').first.content)[1]
		unit.title = unit_title
		puts "#{unit_code}: #{unit_title}"

		prereq_links = unit_page.css('div.uge-prerequisites-content a')
		prereqs = prereq_links.map { |link| unit_code_regex.match(link['href']).to_s }
		prereqs.each do |prereq|
			units[prereq] ||= Unit.new prereq, ""
			units[prereq].add_leads_to unit_code
			unit.add_prereq prereq
		end

		coreq_links = unit_page.css('div.uge-co-requisites-content a')
		coreqs = coreq_links.map { |link| unit_code_regex.match(link['href']).to_s }
		coreqs.each do |coreq|
			units[coreq] ||= Unit.new coreq, ""
			units[coreq].add_leads_to unit_code
			unit.add_coreq coreq
		end


	rescue OpenURI::HTTPError
		puts "#{unit_code}: Doesn't exist"
	end
end

units.delete_if { |key, value| value.leads_to.empty? && value.prereqs.empty? && value.coreqs.empty? }

File.open("nodes.js", "w") do |file|
	file << "nodes = {\n"
	file << "nodes: [\n"
	first = true
	units.each_value do |unit|
		file << "," unless first
		file << "{ data: { id: \"#{unit.code}\", title: \"#{unit.title}\", url: \"#{unit.url}\" } }\n"
		first = false
	end
	file << "],\n"
	file << "edges: [\n"
	first = true
	units.each_value do |unit|
		unit.prereqs.each do |code|
			file << "," unless first
			file << "{ data: { source: \"#{code}\", target: \"#{unit.code}\", prereq: true } }\n"
			first = false
		end
		unit.coreqs.each do |code|
			file << "," unless first
			file << "{ data: { \"source\": \"#{code}\", target: \"#{unit.code}\", coreq: true } }\n"
			first = false
		end
	end
	file << "]\n"
	file << "}\n"
end