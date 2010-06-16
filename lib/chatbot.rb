#!/usr/local/bin/ruby

require 'socket'
require 'rubygems'
require 'activesupport'
require 'lib/database'
require 'lib/quoted_link'

if !File.exists?('config/irc.yml')
  puts "\n\nYou need to configure your config/irc.yml first!\n\n"
  exit
else
  IRC_CONFIG = open('config/irc.yml') {|f| YAML.load(f) }.symbolize_keys
  IRC_CONFIG.freeze
end

# Don't allow use of "tainted" data by potentially dangerous operations
#$SAFE=1

# db exists? if not, create it
Database::create('db/quoted_links.sqlite') unless File.exists?('db/quoted_links.sqlite')

# The irc class, which talks to the server and holds the main event loop
class IRC
    
    attr_accessor :pinged_once
  
    def initialize(server, port, nick, channel)
        @server = server
        @port = port
        @nick = nick
        @channel = channel
        @pinged_once = false
        puts "initialization complete..."
    end
    def send(s)
        # Send a message to the irc server and print it to the screen
        puts "--> #{s}"
        @irc.send "#{s}\n", 0 
    end
    def connect()
        puts "starting connection... server: #{@server}, port: #{@port}"
        # Connect to the IRC server
        @irc = TCPSocket.open(@server, @port)
        $SAFE=1
        send "USER blah blah blah :blah blah"
        send "NICK #{@nick}"
        #send "JOIN #{@channel}"
        puts "connection complete..."
    end
    def evaluate(s)
        # Make sure we have a valid expression (for security reasons), and
        # evaluate it if we do, otherwise return an error message
        if s =~ /^[-+*\/\d\s\eE.()]*$/ then
            begin
                s.untaint
                return eval(s).to_s
            rescue Exception => detail
                puts detail.message()
            end
        end
        return "Error"
    end
    def handle_server_input(s)
        # This isn't at all efficient, but it shows what we can do with Ruby
        # (Dave Thomas calls this construct "a multiway if on steroids")
        case s.strip
            when /^PING :(.+)$/i
                puts "[ Server ping ]"
                send "PONG :#{$1}"
                if !pinged_once
                  @pinged_once = true
                  @pinged_once.freeze
                  send "JOIN #{@channel}"
                end
                
            when /^:(.+?)!(.+?)@(.+?)\sPRIVMSG\s.+\s:[\001]PING (.+)[\001]$/i
                puts "[ CTCP PING from #{$1}!#{$2}@#{$3} ]"
                send "NOTICE #{$1} :\001PING #{$4}\001"
            when /^:(.+?)!(.+?)@(.+?)\sPRIVMSG\s.+\s:[\001]VERSION[\001]$/i
                puts "[ CTCP VERSION from #{$1}!#{$2}@#{$3} ]"
                send "NOTICE #{$1} :\001VERSION Ruby-irc v0.042\001"
            when /^:(.+?)!(.+?)@(.+?)\sPRIVMSG\s(.+)\s:EVAL (.+)$/i
                puts "[ EVAL #{$5} from #{$1}!#{$2}@#{$3} ]"
                send "PRIVMSG #{(($4==@nick)?$1:$4)} :#{evaluate($5)}"
            when /^:(.+?)!(.+?)@(.+?) PRIVMSG #{@channel} :(.+)$/i
              # chat message sent to the channel I'm on!
              puts "[#{Time.now.strftime("%H:%M:%S%p").downcase}] <#{$1}> #{$4} (0: #{$0} 2: #{$2} 3: #{$3})"
              username = $1
              hostname = $3
              message = $4
              if message =~ /^(http|https):\/\/[a-z0-9]+([\-\.]{1}[a-z0-9]+)*\.[a-z]{2,5}(:[0-9]{1,5})?(\/.*)?$/ix
                QuotedLink.create :username => username, :hostname => hostname, :url => $~[0], :context => message, :created_at => Time.now
              end
            else
              puts s
        end
    end
    def main_loop()
        # Just keep on truckin' until we disconnect
        while true
            ready = select([@irc, $stdin], nil, nil, nil)
            next if !ready
            for s in ready[0]
                if s == $stdin then
                    return if $stdin.eof
                    s = $stdin.gets
                    send s
                elsif s == @irc then
                    return if @irc.eof
                    s = @irc.gets
                    handle_server_input(s)
                end
            end
        end
    end
end

# The main program
# If we get an exception, then print it out and keep going (we do NOT want
# to disconnect unexpectedly!)
server = IRC_CONFIG[:server]
port = IRC_CONFIG[:port].present? ? IRC_CONFIG[:port].to_i : 6667
nickname = IRC_CONFIG[:nick]
channel = "##{IRC_CONFIG[:channel]}"

irc = IRC.new( server, port, nickname, channel)
#irc = IRC.new( server, port, nickname, channel)
irc.connect()

begin
    irc.main_loop()
rescue Interrupt
rescue Exception => detail
    puts detail.message()
    print detail.backtrace.join("\n")
    retry
end