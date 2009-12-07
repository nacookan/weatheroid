require 'open-uri'

class Lwws
  @cache

  def initialize
    @cache = {}
  end

  def load(city_id)
    if @cache[city_id] == nil
      uri = URI.parse("http://weather.livedoor.com/forecast/webservice/rest/v1?city=#{city_id}&day=today")
      puts "loading... #{uri}"
      @cache[city_id] = uri.read
      sleep 0.5
    else
      puts 'cache hit!'
    end
    return @cache[city_id]
  end

  def load_forecast
    uri = URI.parse('http://weather.livedoor.com/forecast/rss/forecastmap.xml')
    puts "loading... #{uri}"
    return uri.read
  end
end
