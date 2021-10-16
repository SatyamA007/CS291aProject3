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

before do
  headers 'Access-Control-Allow-Origin' => '*'
end

EventMachine.schedule do
  EventMachine.add_periodic_timer(SCHEDULE_TIME) do
    # Change this for any timed events you need to schedule.
    #puts "This message will be output to the server console every #{SCHEDULE_TIME} seconds"
  end
end

def timestamp
  Time.now.to_i
end

def sse_event(stream, event, username="", message="")
  case event
  when 'Join'
    data = {user: username, created: timestamp()}
    stream << "event: Join\n" << "data: "<< data.to_json << "\n" << "id: " << SecureRandom.uuid << "\n\n"
  when 'Disconnect'
    data = {created: timestamp()}
    stream << "event: Disconnect\n" << "data: "<< data.to_json << "\n" << "id: " << SecureRandom.uuid << "\n\n"
  when 'Message'
    data = {message: message,user: username, created: timestamp()}
    stream << "event: Message\n" << "data: "<< data.to_json << "\n" << "id: " << SecureRandom.uuid << "\n\n"
  when 'Part'
    data = {user: username, created: timestamp()}
    stream << "event: Part\n" << "data: "<< data.to_json << "\n" << "id: " << SecureRandom.uuid << "\n\n"
  when 'ServerStatus'
    data = {status: username, created: timestamp()}
    stream << "event: ServerStatus\n" << "data: "<< data.to_json << "\n" << "id: " << SecureRandom.uuid << "\n\n"
  when 'Users'
    data = {users: $stokens.keys(), created: timestamp()}
    stream << "event: Users\n" << "data: "<< data.to_json << "\n" << "id: " << SecureRandom.uuid << "\n\n"
  else
    stream << "event: error\n"<< SecureRandom.uuid << "\n\n"
  end 
end


#----- /stream Endpoint -------

get '/stream/:token', provides: 'text/event-stream' do
  headers 'Access-Control-Allow-Origin' => '*'

  token = params['token']
  if($stokens.key(token) == nil)
    return [403, 'Invalid stream token']
  end

  username = $stokens.key(token)
  strm = $streams[token]

  if(strm != nil)
    return [409, 'Connection already exists!']
  end
  
  stream(:keep_open) do |connection|
    connections << connection
    #$streams[token] = connection
    sse_event(connection, "Join", username)  #Join sse event

    connection.callback do
      sse_event(connection, "Disconnect")    #Disconnect sse event
      connections.delete(connection)
    end
  end
end

#----- /login Endpoint -------

post '/login' do
  begin
    uname = params[:username]
    pwd = params[:password]

    if(uname == '' || pwd == '')
      return [422, 'Empty username/password']
    end

    if($stokens[uname] != nil)
      return [409, 'Multiple login tabs']
    end

    if($users.has_key?(uname))
      stored_pwd = $users[uname]
      if(stored_pwd != pwd)
        return [403, 'Invalid username/password']
      end
    else
      $users[uname] = pwd
    end

    strtoken = SecureRandom.hex(32)
    msgtoken = SecureRandom.hex
    $stokens[uname] = strtoken

    body = {message_token: "#{msgtoken}", stream_token: "#{strtoken}"}
    headers 'Content-Type' => 'application/json'
    return [201, body.to_json]
  rescue
    return [422, 'Exception']
  end

end

#----- /message Endpoint -------

post '/message' do

  puts 'Headers'
  PP.pp(request.env.filter { |x| x.start_with?('HTTP_') })

  puts 'request.params:'
  PP.pp request.params

  [403, "POST /message\n"]
end

#------- Options endpoint ---------

options '/message' do
  PP.pp("-- options --")
  PP.pp(params)
  PP.pp(request.env)
  #PP.pp(request.env)
  [404,"not found"]
end
