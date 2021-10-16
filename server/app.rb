# frozen_string_literal: true

require 'eventmachine'
require 'sinatra'
require 'json'
require 'pp'
require 'securerandom'


SCHEDULE_TIME = 32
$users = Hash.new() # username vs password
$streams = Hash.new() # stream token vs stream object
$stokens = Hash.new() # username vs stream tokens
$mtokens = Hash.new() # msg token vs stream tokens
$startTime = Time.now
connections = []

before do
  headers 'Access-Control-Allow-Origin' => '*'
end

EventMachine.schedule do
  EventMachine.add_periodic_timer(SCHEDULE_TIME) do
    connections.each do |connection|
      sse_event(connection,'ServerStatus')
    end
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
    data = {status: "Server uptime: "+(Time.now - $startTime).round().to_s+" seconds", created: timestamp()}
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

  if($streams[token] != nil&&!$streams[token].closed?())
    return [409, 'Connection already exists!']
  end

  
  stream(:keep_open) do |connection|
    connections<<connection
    if(request.env["HTTP_LAST_EVENT_ID"] == nil)
      $streams[token] = connection
      sse_event(connection, "Users", token)  # Users sse event
      connections.each do |connection|
      sse_event(connection, "Join", username)  #Join sse event
    end

    connection.callback do
      sse_event(connection, "Disconnect")    #Disconnect sse e.delete(connecti.each do |conn|
      sse_event(connection, "Part", username)  #Part sse event
      end
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
  rescue =>e
    return [422, 'Exception '+e.to_s]
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