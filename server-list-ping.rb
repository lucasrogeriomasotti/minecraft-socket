require_relative 'server_list_ping.rb'
require 'pp'

s = Minecraft::Session.new("localhost", 25565)

pp s.fetch_status

