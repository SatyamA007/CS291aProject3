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
$user_list = Hash.new() # username vs password
$streams = Hash.new() # stream token vs stream object
$userStreamToken = Hash.new() # username vs stream tokens
$msgTknUser  = Hash.new() # msg tokens vs userName
$startTime = Time.now
$connections = [] # Stream object array
$messageQ = []

EventMachine.schedule do
  EventMachine.add_periodic_timer(SCHEDULE_TIME) do
    $connections.each do |connection|
      sse_event(connection,'ServerStatus')
    end
  end
end

def timestamp
  Time.now.to_i
end

def date_format(timestamp) 
  time = Time.at(timestamp)
  return time.strftime("%m/%d/%Y") + " " + time.strftime("%I:%M %p");
end

def messageQput(newMessage)
  if $messageQ.size()<100
    $messageQ.push(newMessage)
  else 
    $messageQ.push(newMessage)
    $messageQ.shift()
  end
end

def messageQget(stream)
  for message in $messageQ
    stream << message
  end    
end

def sse_event(stream, event, username="", message="")
  streamMessage = ""

  case event
  when 'Join'
    data = {user: username, created: timestamp()}
    streamMessage = "event: Join\n" + "data: "+ data.to_json + "\n" + "id: " + SecureRandom.uuid + "\n\n"    
  when 'Disconnect'
    data = {created: timestamp()}
    stream << "event: Disconnect\n" << "data: "<< data.to_json << "\n" << "id: " << SecureRandom.uuid << "\n\n"
  when 'Message'
    data = {message: message,user: username, created: timestamp()}
    streamMessage = "event: Message\n" + "data: "+ data.to_json + "\n" + "id: " + SecureRandom.uuid + "\n\n"
  when 'Part'
    data = {user: username, created: timestamp()}
    streamMessage = "event: Part\n" + "data: "+ data.to_json + "\n" + "id: " + SecureRandom.uuid + "\n\n"
  when 'ServerStatus'
    statusText =  "Server uptime: "+(Time.now - $startTime).round().to_s+" seconds"
    data = {status: statusText, created: timestamp()}
    streamMessage = "event: ServerStatus\n" + "data: "+ data.to_json + "\n" + "id: " + SecureRandom.uuid + "\n\n"
  when 'Users'
    data = {users: $userStreamToken.keys(), created: timestamp()}
    stream << "event: Users\n" << "data: "<< data.to_json << "\n" << "id: " << SecureRandom.uuid << "\n\n"
  else
    stream << "event: error\n"<< SecureRandom.uuid << "\n\n"
  end 
  
  if streamMessage!=""
    stream << streamMessage
    messageQput(streamMessage) unless !$messageQ.empty?()&&$messageQ.last.split("\n")[1]==streamMessage.split("\n")[1];    
  end
end

def disconnect(connection, token, username)
  sse_event(connection, "Disconnect")  #Disconnect sse event
  $connections.delete(connection)
  connection.close()
  $streams.delete(token)
  $connections.each do |conn|
    sse_event(conn, "Part", username)  #Part sse event
  end
end
#----- /stream Endpoint -------

get '/stream/:token', provides: 'text/event-stream' do

  token = params['token']
  if($userStreamToken.key(token) == nil)
    return [403, 'Invalid stream token']
  end

  username = $userStreamToken.key(token)

  if($streams[token] != nil&&!$streams[token].closed?())
    #return [409, 'Connection already exists!']
  end


  stream(:keep_open) do |connection|

    $connections << connection

    if(request.env["HTTP_LAST_EVENT_ID"] == nil)
      if $streams[token] == nil
        messageQget(connection)
      end
      $streams[token] = connection
      sse_event(connection, "Users", token)  # Users sse event     
    end

    $connections.each do |connection|
      sse_event(connection, "Join", username)  #Join sse event
    end

    connection.callback do
      disconnect(connection, token, username)
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

    if($userStreamToken[uname] != nil)
      return [409, 'Multiple login tabs']
    end

    if($user_list.has_key?(uname))
      stored_pwd = $user_list[uname]
      if(stored_pwd != pwd)
        return [403, 'Invalid username/password']
      end
    else
      $user_list[uname] = pwd
    end

    strtoken = SecureRandom.hex(32)
    msgtoken = SecureRandom.hex
    $userStreamToken[uname] = strtoken
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
  strToken = $userStreamToken[user]
  streamObj = $streams[strToken]

  if(streamObj.nil?())
    return [409,"No open stream for the user" + user]
  end

  if(strToken.match /^\h{64}$/).nil?
    return [403,"Invalid signed token"]
  end

  message = request.params['message']
  if(message.eql?("/quit"))
    disconnect(streamObj, strToken, user)
  end

  newMsgToken = SecureRandom.hex
  $msgTknUser.delete(msgToken)
  $msgTknUser[newMsgToken] = user

  #Send msg to all user streams
  $connections.each do |connection|
    sse_event(connection, "Message",user, message)  #Message sse event
  end

  headers 'Content-Type' => 'text/html; charset=utf-8'
  headers 'Token' => newMsgToken
  return [201, "CREATED"]
end
