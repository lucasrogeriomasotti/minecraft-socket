require_relative '../lib/minecraft-socket.rb'
require 'pp'

s = Minecraft::Session.new("localhost", 25565, 463)

pp s.fetch_status

