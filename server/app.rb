# frozen_string_literal: true

require 'eventmachine'
require 'sinatra'

SCHEDULE_TIME = 32
connections = []

EventMachine.schedule do
  EventMachine.add_periodic_timer(SCHEDULE_TIME) do
    # Change this for any timed events you need to schedule.
    puts "This message will be output to the server console every #{SCHEDULE_TIME} seconds"
  end
end

get '/stream/:token', provides: 'text/event-stream' do
  headers 'Access-Control-Allow-Origin' => '*'
  stream(:keep_open) do |connection|
    connections << connection

    connection << "data: Welcome!\n\n"

    connection.callback do
      puts 'callback'
      connections.delete(connection)
    end
  end
end

post '/login' do
  [422, 'POST /login\n']
end

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
