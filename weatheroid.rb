require 'rexml/document'
require 'pstore'
require 'twitter'
require 'lwws'
load 'config.rb'
load 'messages.rb'

class Weatheroid
  include REXML

  @twitter
  @lwws
  @cities
  @weathers

  def initialize(user_id, password)
    @twitter = Twitter.new(user_id, password)
    @lwws = Lwws.new
    @cities = load_cities
    @weathers = load_weathers
  end

  def watch
    last_id = load_last_id
    puts 'last_id loaded.'

    mentions = load_mentions(last_id)
    puts "#{mentions.size.to_s} mentions loaded."
    return if mentions.empty?

    save_last_id(mentions.last[:status_id])
    puts 'last_id saved.'

    proc_empty(mentions)
    proc_register(mentions)
    proc_goodbye(mentions)
    proc_unknown(mentions)
  end

  def notify
    users = load_users
    users.each do |user|
      posted = {}
      entries = load_entries(user)
      entries.each do |entry|
        city = nil
        @cities.each do |c|
          if c[:name] == entry[:area]
            city = c
            break;
          end
        end

        next if posted[city[:id]]

        lw = load_lwws(city[:id])
        next if lw[:telop].index(entry[:weather]) == nil

        telop = lw[:telop].gsub(/時々/, 'ときどき')
        msg = gen_message(:suffix)
        post("@#{user} 今日の#{city[:name]}は#{telop}だよ！#{msg} #{lw[:link]}")
        posted[city[:id]] = true
      end
    end
  end

private

  def load_cities
    cities = []
    open('cities') do |f|
      while line = f.gets
        fields = line.chomp.split(/,/)
        next if fields.size != 2
        cities << {
          :id => fields[0],
          :name => fields[1],
        }
      end
    end
    cities.sort!{|a, b| b[:name].size - a[:name].size}
    return cities
  end

  def load_weathers
    weathers = []
    open('weathers') do |f|
      while line = f.gets
        fields = line.chomp.split(/,/)
        next if fields.size != 3
        weathers << {
          :realname => fields[0],
          :showname => fields[1],
          :nickname => fields[2],
        }
      end
    end
    return weathers
  end

  def load_last_id
    return nil if !File.exist?('last_id')
    f = open('last_id')
    id = f.read
    f.close
    return id.chomp
  end

  def save_last_id(id)
    f = File.open('last_id', 'w')
    f.puts id
    f.close
  end

  def load_mentions(since_id)
    content = @twitter.mentions(since_id)
    doc = Document.new content
    mentions = []
    doc.get_elements('/statuses/status').reverse.each do |tag|
      text = XPath.first(tag, 'text').text
      next if text !~ /^@/
      mentions << {
        :text => text,
        :user => XPath.first(tag, 'user/screen_name').text,
        :status_id => XPath.first(tag, 'id').text,
        :done => false,
      }
    end
    return mentions
  end

  def load_lwws(city_id)
    content = @lwws.load(city_id)
    doc = Document.new content
    return {
        :telop => XPath.first(doc, '/lwws/telop').text,
        :link => XPath.first(doc, '/lwws/link').text,
    }
  end

  def load_users
    db = PStore.new('userdata')
    db.transaction do
      return db.roots
    end
  end

  def load_entries(user)
    db = PStore.new('userdata')
    db.transaction do
      return db[user]
    end
  end

  def gen_message(key)
    list = $messages[key]
    return list[rand(list.size)]
  end

  def proc_empty(mentions)
    db = PStore.new('userdata')
    db.transaction do
      mentions.each do |mention|
        next if mention[:done]
        text = mention[:text]
        user = mention[:user]
        status_id = mention[:status_id]
        next unless text =~ /状態/

        mention[:done] = true;

        # reply
        entries = db[user]
        if entries == nil
          msg = gen_message(:empty)
          reply("@#{user} #{msg}", status_id)
          next
        end

        list = []
        entries.each do |entry|
          weather = ''
          @weathers.each do |w|
            if entry[:weather] == w[:realname]
              weather = w[:showname]
            end
          end
          list << "#{entry[:area]}が#{weather}のとき"
        end
        body = list.join('と')
        reply("@#{user} #{body}おしえるよ！", status_id)
      end
    end
  end

  def proc_register(mentions)
    db = PStore.new('userdata')
    db.transaction do
      mentions.each do |mention|
        next if mention[:done]
        text = mention[:text]
        user = mention[:user]
        status_id = mention[:status_id]

        # find city
        found_city = nil
        @cities.each do |city|
          if text.index(city[:name]) != nil
            found_city = city[:name]
            break
          end
        end
        next if found_city == nil

        # find weather
        found_weather = nil
        @weathers.each do |weather|
          if text.index(weather[:nickname]) != nil
            found_weather = weather
            break
          end
        end
        next if found_weather == nil

        mention[:done] = true;

        # register
        if db[user] == nil
          db[user] = []
        else
          cancel = false
          db[user].each do |entry|
            if entry[:area] == found_city && entry[:weather] == found_weather[:realname]
              msg = gen_message(:exist)
              reply("@#{user} #{msg}", status_id)
              cancel = true
              break;
            end
          end
          next if cancel
        end
        db[user] << {
          :area => found_city,
          :weather => found_weather[:realname],
        }

        # reply
        msg = gen_message(:ok)
        reply("@#{user} #{msg}#{found_city}が#{found_weather[:showname]}のときおしえるね！", status_id)
      end
    end
  end

  def proc_goodbye(mentions)
    db = PStore.new('userdata')
    db.transaction do
      mentions.each do |mention|
        next if mention[:done]
        text = mention[:text]
        user = mention[:user]
        status_id = mention[:status_id]
        next unless text =~ /もういい/

        mention[:done] = true;

        db.delete(user)
        msg = gen_message(:goodbye)
        reply("@#{user} #{msg}", status_id)
      end
    end
  end

  def proc_unknown(mentions)
    mentions.each do |mention|
      next if mention[:done]
      user = mention[:user]
      status_id = mention[:status_id]

      msg = gen_message(:unknown)
      reply("@#{user} #{msg}", status_id)
    end
  end

  def reply(status, status_id)
    status += " #{Time.now.strftime('%H:%M')}"
    @twitter.post(status, status_id)
  end

  def post(status)
    status += " #{Time.now.strftime('%H:%M')}"
    @twitter.post(status)
  end
end

cmd = ARGV[0]

if cmd == 'watch'
  w = Weatheroid.new($user_id, $password)
  w.watch
elsif cmd == 'notify'
  w = Weatheroid.new($user_id, $password)
  w.notify
else
  puts 'Usage: ruby weatheroid.rb [watch|notify]'
end

