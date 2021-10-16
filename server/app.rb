# frozen_string_literal: true

require 'eventmachine'
require 'sinatra'
require 'json'
require 'pp'
require 'securerandom'


SCHEDULE_TIME = 32
connections = []
$users = Hash.new() # username vs password
$streams = Hash.new() # stream token vs stream object
$stokens = Hash.new() # username vs stream tokens
$mtokens = Hash.new() # msg token vs stream tokens


EventMachine.schedule do
  EventMachine.add_periodic_timer(SCHEDULE_TIME) do
    # Change this for any timed events you need to schedule.
    puts "This message will be output to the server console every #{SCHEDULE_TIME} seconds"
  end
end

def timestamp
  Time.now.to_i
end

def sse_join(stream, username)
  data = {created: "#{timestamp()}", user: "#{username}"}
    stream << "event: join \n" << "data: "<< data.to_json << "\n" << "id: " << SecureRandom.uuid << "\n\n"
end

#----- /stream Endpoint -------

get '/stream/:token', provides: 'text/event-stream' do
  headers 'Access-Control-Allow-Origin' => '*'

  token = params['token']
  username = $stokens.key(token)
  if($stokens.key(token) == nil)
    return [403, 'Invalid stream token']
  end

  /strm = $streams.key(token)
  if(strm == nil)
    return [409, 'Connection already exists!']
  end/

  stream(:keep_open) do |connection|
    connections << connection

    sse_join(connection, username)  #JOIN sse event

    connection.callback do
      puts 'callback'
      connections.delete(connection)
    end
  end
end

#----- /login Endpoint -------

post '/login' do
  headers 'Access-Control-Allow-Origin' => '*'

  begin
    uname = params[:username]
    pwd = params[:password]

    if(uname == '' || pwd == '')
      return [422, 'Empty username/password']
    end

    if($stokens[uname] != nil)
      return [409, 'Multiple login tabs']
    end

    if($users.has_key?("#{uname}"))
      stored_pwd = $users.fetch("#{uname}")
      if(stored_pwd != pwd)
        return [403, 'Invalid username/password']
      end
    else
      $users["#{uname}"] = pwd
    end

    strtoken = SecureRandom.hex(32)
    msgtoken = SecureRandom.hex
    $stokens[uname] = strtoken
    #$mtokens[msgtoken] =

    body = {message_token: "#{msgtoken}", stream_token: "#{strtoken}"}
    headers 'Content-Type' => 'application/json'
    return [201, body.to_json]
  rescue
    return [422, 'Exception']
  end

end

#----- /message Endpoint -------

post '/message' do
  require 'pp'

  connections.each do |connection|
    connection << "data: Goodbye!\n\n"
    connection.close  # This call will trigger connection.callback
  end

  puts 'Headers'
  PP.pp(request.env.filter { |x| x.start_with?('HTTP_') })
  puts

  puts 'request.params:'
  PP.pp request.params
  puts

  [403, "POST /message\n"]
end

#------- Options endpoint ---------

options '/message', provides: 'text/event-stream' do
  headers 'Access-Control-Allow-Origin' => '*'

  PP.pp("-- options --")
  PP.pp(params)
  PP.pp("-----")
  #PP.pp(request.env)

end
