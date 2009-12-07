require 'rexml/document'
require 'lwws'

include REXML

lwws = Lwws.new
xml = lwws.load_forecast

puts 'making cities...'
f = File.open('cities', 'w')

doc = Document.new xml
doc.get_elements('/rss/channel/ldWeather:source/area/pref/city').each do |city|
  id = city.attributes['id']
  name = city.attributes['title']
  f.puts "#{id},#{name}"
end

f.close
puts 'done.'
