require 'socket'

module Minecraft
  class Session
    
    def initialize(host, port, protocol_version)
      @host = host
      @port = port
      @protocol_version = protocol_version
    end
    
    def __connect
      @connection = TCPSocket.open(@host, @port)
    end
    
    def send_packet(arg)
      unless arg.is_a?(Packet)
        raise TypeError
      end
      
      @connection.write(arg.encode)
    end
    
    def get_packet_raw
      buf = ""
      packet_size = 0
      while b = @connection.getbyte
        buf << b.chr
        if Type::VarInt.decodable?(buf)
          packet_size, _ = Type::VarInt.decode(buf)
          break
        end
      end
      
      packet_raw = ""
      if packet_size > 0
        packet_raw = @connection.read(packet_size)
      end
      
      return packet_raw
    end
    
    def get_packet
      return Packet.decode(get_packet_raw())
    end
    
    def each_packet(&block)
      unless block_given?
        raise
      end
      
      loop do
        yield get_packet() 
      end
    end
    
    def handshake()
      __connect()
      
      m = Message.new
      m.append(Type::VarInt, @protocol_version)
      m.append(Type::String, @host)
      m.append(Type::UnsignedShort, @port)
      m.append(Type::VarInt, 1)
      
      self.send_packet(Packet.new(0x00, m))
    end
    
    def fetch_status
      self.handshake()
      self.send_packet(Packet.new(0x00))
      self.get_packet
    end
  end
end
