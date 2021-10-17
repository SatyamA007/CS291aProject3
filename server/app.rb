# frozen_string_literal: true

require 'eventmachine'
require 'sinatra'
require 'json'
require 'pp'
require 'securerandom'

configure do
  enable :cross_origin
end
before do
  response.headers['Access-Control-Allow-Origin'] = '*'
end

# routes...
options "*" do
  response.headers["Allow"] = "GET, PUT, POST, DELETE, OPTIONS"
  response.headers["Access-Control-Allow-Headers"] = "Authorization, Content-Type, Accept, X-User-Email, X-Auth-Token"
  response.headers["Access-Control-Allow-Origin"] = "*"
  200
end

SCHEDULE_TIME = 32
$users = Hash.new() # username vs password
$streams = Hash.new() # stream token vs stream object
$stokens = Hash.new() # username vs stream tokens
$msgTknUser  = Hash.new() # msg tokens vs userName
$startTime = Time.now
connections = []

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

    connections << connection

    if(request.env["HTTP_LAST_EVENT_ID"] == nil)
      $streams[token] = connection
      sse_event(connection, "Users", token)  # Users sse event
    end

    connections.each do |connection|
      sse_event(connection, "Join", username)  #Join sse event
    end

    connection.callback do
      sse_event(connection, "Disconnect")    #Disconnect sse event
      connections.delete(connection)
      $streams.delete(token)
      connections.each do |conn|
        sse_event(conn, "Part", username)  #Part sse event
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
    $msgTknUser[msgtoken] = uname

    body = {message_token: msgtoken, stream_token: strtoken}
    headers 'Content-Type' => 'application/json'
    return [201, body.to_json]
  rescue =>e
    return [422, 'Exception '+e.to_s]
  end

end

#----- /message Endpoint -------

post '/message' do
  headers 'Access-Control-Expose-Headers' => 'token'
  authorization = request.env['HTTP_AUTHORIZATION'].split(' ', 2)
  
  if authorization.size < 2 || authorization[0] != ('Bearer') || authorization[1].nil?() || authorization[1].empty?() || request.params['message'].nil?() || request.params['message'].empty?()
    return [422, "Wrong message format"]
  end

  msgToken = authorization[1]
  user = $msgTknUser[msgToken]
  strToken = $stokens[user]
  streamObj = $streams[strToken]

  if(streamObj.nil?())
    return [409,"No open stream for the user" + user]
  end

  if(strToken.match /^\h{64}$/).nil?
    return [403,"Invalid signed token"]
  end

  message = request.params['message']
  newMsgToken = SecureRandom.hex
  $msgTknUser.delete(msgToken)
  $msgTknUser[newMsgToken] = user

  connections.each do |connection|
    sse_event(connection, "Message",user, message)  #Message sse event
  end

  headers 'Content-Type' => 'text/html; charset=utf-8'
  headers 'Token' => newMsgToken
  return [201, "CREATED"]
end
