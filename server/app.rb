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

SCHEDULE_TIME = 1*60*60
$user_list = Hash.new() # username vs password
$streams = Hash.new() # stream token vs stream object
$userStreamToken = Hash.new() # username vs stream tokens
$userMsgToken  = Hash.new() # userName vs msg tokens 
$startTime = Time.now
$connections = [] # Stream object array

$messageIds = [SecureRandom.uuid]
$messageQ = { $messageIds[-1] => "data: "+ {status: "Server started: Welcome to the Low-Budget Whatsapp server!", created: Time.now.to_i}.to_json + "\n" + "event: ServerStatus\n" + "id: " + $messageIds[-1] + "\n\n"}

EventMachine.schedule do
  EventMachine.add_periodic_timer(SCHEDULE_TIME) do
    eventId = SecureRandom.uuid
    $connections.each do |connection|
      sse_event(connection,'ServerStatus', eventId=eventId)
    end
  end
end

def timestamp
  Time.now.to_i
end

def getUserList
  $userStreamToken.keys().select { |uname| !$streams[$userStreamToken[uname]].nil?}
end

def messageQput(newMessage, id)
  if $messageIds.size() > 100
    shifted = $messageIds.shift
    $messageQ.delete(shifted)
  end
  $messageQ[id] = newMessage
  $messageIds.push(id)
end

def messageQget(stream, lastEventId)
  index = 0 
  index = $messageIds.index(lastEventId)+1  if !lastEventId.nil?&&$messageIds.include?(lastEventId)

  for i in index...$messageIds.length do
    stream << $messageQ[$messageIds[i]] unless $messageQ[$messageIds[i]].include?('Join')||$messageQ[$messageIds[i]].include?('Part')
  end  
end

def sse_kick(user1, user2, stream2, strToken2)
  $connections.delete(stream2)
  stream2.close()
  $streams.delete(strToken2)
  data = {status: user1+" kicked "+user2, created: timestamp()}
  eventId = SecureRandom.uuid
  $connections.each do |conn|
    conn << "data: "<< data.to_json << "\n" << "event: ServerStatus\n" << "id: " << eventId << "\n\n"
  end
  messageQput("event: ServerStatus\n" + "data: "+ data.to_json + "\n" + "id: " + eventId + "\n\n")
end

def sse_event(stream, event, eventId, username="", message="")
  streamMessage = ""

  case event
  when 'Join'
    data = {user: username, created: timestamp()}
    streamMessage = "data: "+ data.to_json + "\n" + "event: Join\n" + "id: " + eventId + "\n\n"    
  when 'Disconnect'
    data = {created: timestamp()}
    stream << "data: "<< data.to_json << "\n" << "event: Disconnect\n" << "id: " << eventId << "\n\n"
  when 'Message'
    data = {message: message,user: username, created: timestamp()}
    streamMessage = "data: "+ data.to_json + "\n" + "event: Message\n" + "id: " + eventId + "\n\n"
  when 'Part'
    data = {user: username, created: timestamp()}
    streamMessage = "data: "+ data.to_json + "\n" + "event: Part\n" + "id: " + eventId + "\n\n"
  when 'ServerStatus'
    statusText =  "Server uptime: "+(Time.now - $startTime).round().to_s+" hours"
    data = {status: statusText, created: timestamp()}
    streamMessage = "data: "+ data.to_json + "event: ServerStatus\n" + "\n" + "id: " + eventId + "\n\n"
  when 'Users'
    data = {users: getUserList(), created: timestamp()}
    stream << "data: "<< data.to_json << "\n" << "event: Users\n" << "id: " << eventId << "\n\n"
  else
    stream << "event: error\n"<< eventId << "\n\n"
  end 

  if streamMessage!=""
    stream << streamMessage
    messageQput(streamMessage, eventId) unless $messageIds[-1]==eventId;    
  end
end

def disconnectAndPart(connection, token, username, allowRetry = true)
  sse_event(connection, "Disconnect", SecureRandom.uuid, username=username)  unless allowRetry #Disconnect sse event
  sse_event(connection, "Part", SecureRandom.uuid, username=username)   if allowRetry          #Part sse event before closing connection
  $connections.delete(connection)
  connection.close()
  $streams.delete(token)
  eventId = SecureRandom.uuid
  $connections.each do |conn|
    sse_event(conn, "Part", eventId, username=username)   #Part sse event
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
    return [409, 'Connection already exists!']
  end

  stream(:keep_open) do |connection|
    $connections << connection
    $streams[token] = connection

    lastEventId = request.env["HTTP_LAST_EVENT_ID"]
    sse_event(connection, "Users", eventId=SecureRandom.uuid)  if(lastEventId.nil? || !$messageIds.include?(lastEventId))
    messageQget(connection, lastEventId)

    eventId = SecureRandom.uuid
    $connections.each do |connection|
      sse_event(connection, "Join", eventId=eventId, username=username)  #Join sse event
    end

    connection.callback do
      disconnectAndPart(connection, token, username)
    end
  end
end

#----- /login Endpoint -------

post '/login' do
  begin
    uname = params[:username]
    pwd = params[:password]

    if(uname == '' || pwd == '') || !(params.keys.length == 2 && (params.has_key?(:username) && params.has_key?(:password)))
      return [422, 'Empty username/password']
    end

    if $userStreamToken[uname] != nil && $streams[$userStreamToken[uname]] != nil && !$streams[$userStreamToken[uname]].closed?()
      return [409, 'User already logged in']
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
    $userMsgToken[uname] = msgtoken

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
  authorization = request.env['HTTP_AUTHORIZATION']
  return [403, "Empty header"] if authorization.nil?

  authorization =  authorization.split(' ')
  if authorization.size != 2 || authorization[0] != ('Bearer') || authorization[1].nil?() || authorization[1].empty?()
    return [403, "Wrong header format"]
  end
  
  if request.params['message'].nil? || request.params['message'] == "" || !(request.params.keys.length == 1 && request.params.has_key?('message'))
    return [422, "Wrong message format"]
  end

  msgToken = authorization[1]
  if !$userMsgToken.has_value?(msgToken)
    return [403, "Invalid message token"]
  end

  user = $userMsgToken.key(msgToken)
  strToken = $userStreamToken[user]
  streamObj = $streams[strToken]
  cond409 = streamObj.nil?() || streamObj.closed?()
  return [409, "No open stream for the user " + user] if cond409
  
  message = request.params['message']
  case message    
  when "/quit"
    disconnectAndPart(streamObj, strToken, user, false)
  when "/reconnect"
    disconnectAndPart(streamObj, strToken, user) 
  else
    if message.start_with?("/kick")
      user2 = message.delete_prefix("/kick ")
      if getUserList().include?(user2) && user2 != user
        strToken2 = $userStreamToken[user2]
        streamObj2 = $streams[strToken2]
        sse_kick(user, user2, streamObj2, strToken2)
      else
        return [409, "Cannot kick yourself or offline users" + user]
      end
    else
      #Send msg to all user streams
      eventId = SecureRandom.uuid
      $connections.each do |connection| 
        sse_event(connection, "Message", eventId, username=user, message=message)  #Message sse event
      end
    end
  end

  #rotating the messageToken
  newMsgToken = SecureRandom.hex
  $userMsgToken[user] = newMsgToken

  headers 'Content-Type' => 'text/html; charset=utf-8'
  headers 'Token' => newMsgToken
  return [201, "CREATED"]
end
