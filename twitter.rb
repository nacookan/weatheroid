require 'open-uri'
require 'net/http'

class Twitter
  @user_id
  @password

  def initialize(user_id, password)
    @user_id = user_id
    @password = password
  end

  def mentions(since_id)
    uri = "http://twitter.com/statuses/mentions.xml?count=200"
    uri += "&since_id=#{since_id}" if since_id != nil
    puts "loading... #{uri}"
    content = ''
    open(uri, :http_basic_authentication => [@user_id, @password]){|f|
      content = f.read
    }
    return content
  end

  def post(status, reply_to = nil)
    body = 'status=' + URI.encode(status)
    body += "&in_reply_to_status_id=#{reply_to}" if reply_to != nil
    Net::HTTP.version_1_2
    Net::HTTP.start('twitter.com', 80) do |http|
      req = Net::HTTP::Post.new('/statuses/update.xml')
      req.basic_auth @user_id, @password
      req.body = body
      res = http.request(req)
    end
    puts "post: #{status} "
    sleep 0.5
  end
end

