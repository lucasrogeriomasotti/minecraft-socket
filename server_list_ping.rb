require 'json'
require 'socket'

module Minecraft
  class Packet
    attr_reader :length, :packet_id, :packed_id_encoded, :data, :data_encoded

    def initialize(packet_id, message = Message.new)
      raise TypeError unless message.is_a?(Message)

      @packed_id = packet_id
      @packed_id_encoded, @packed_id_encoded_size = Type::VarInt.encode(packet_id)
      @data = message
      @data_encoded = message.encode
      @length = @data_encoded.bytesize + @packed_id_encoded_size
    end

    def encode
      raw = ''
      raw << Type::VarInt.encode(@length)[0]
      raw << @packed_id_encoded
      raw << @data_encoded
      raw
    end

    def self.decode(raw)
      return nil if !raw || raw.empty?

      packet_id, packet_id_size = Type::VarInt.decode(raw)
      data = raw.byteslice(packet_id_size, raw.bytesize)

      response = {
        packet_id: packet_id
      }

      decode_procedures = {
        0x00 => [
          [:data, Type::JSON]
        ]
      }

      proceed_bytes = 0
      decode_procedures[packet_id].each do |e|
        key, klass = e

        response[key], bytes = klass.decode(data.byteslice(proceed_bytes, data.bytesize))
        proceed_bytes += bytes
      end

      response
    end
  end

  class Session
    def initialize(host, port, protocol_version = 498)
      @host = host
      @port = port
      @protocol_version = protocol_version
    end

    def __connect
      @connection = TCPSocket.open(@host, @port)
    end

    def send_packet(arg)
      raise TypeError unless arg.is_a?(Packet)

      @connection.write(arg.encode)
    end

    def get_packet_raw
      buf = ''
      packet_size = 0
      while b = @connection.getbyte
        buf << b.chr
        if Type::VarInt.decodable?(buf)
          packet_size, = Type::VarInt.decode(buf)
          break
        end
      end

      packet_raw = ''
      packet_raw = @connection.read(packet_size) if packet_size > 0

      packet_raw
    end

    def get_packet
      Packet.decode(get_packet_raw)
    end

    def handshake
      __connect

      m = Message.new
      m.append(Type::VarInt, @protocol_version)
      m.append(Type::String, @host)
      m.append(Type::UnsignedShort, @port)
      m.append(Type::VarInt, 1)

      send_packet(Packet.new(0x00, m))
    end

    def fetch_status
      handshake
      send_packet(Packet.new(0x00))
      get_packet
    end
  end

  class Message
    class Tuple
      attr_reader :type, :value, :value_encoded, :encoded_size

      def initialize(**hash)
        if hash.key?(:value_encoded)

        else
          @type  = hash[:type]
          @value = hash[:value]

          @value_encoded, @encoded_size = hash[:type].encode(hash[:value])
        end
      end
    end

    def initialize
      @message_table = []
    end

    def append(type, value, _optional_type = nil)
      @message_table << Tuple.new(type: type, value: value)
      self
    end

    def encode
      @message_table.map(&:value_encoded).join
    end
  end

  module Type
    class UnsignedShort
      def self.encode(value)
        [[value].pack('n'), 2]
      end

      def self.decode(value)
        [value.unpack('n')[0], 2]
      end
    end

    class String
      def self.encode(value)
        encoded = ''
        encoded << VarInt.encode(value.bytesize)[0]
        encoded << value
        [encoded, encoded.bytesize]
      end

      def self.decode(value)
        string_size, size_size = VarInt.decode(value)
        [value.byteslice(size_size, string_size), string_size + size_size]
      end
    end

    class JSON
      def self.encode(_value)
        raise
      end

      def self.decode(value)
        str, str_size = String.decode(value)
        [::JSON.parse(str, symbolize_names: true), str_size]
      end
    end

    class VarInt
      @@is_variable_size = true
      @@size = 1..5

      def self.encode(original)
        #    0000-0001 0010-1100 : 300
        # ->  000-0010  010-1100 : separate 7bit
        # ->  010-1100  000-0010 : move containing LSB to head's octet
        # -> 1010-1100 0000-0010

        # -1
        #  11111111 10001111 11111111 11111111 01111111
        #
        #  1234567890
        #  01010010 10000100 11001100 11011000 10000101

        num = if original >= 0
                original
              else
                ((original * -1) ^ 0xFFFFFFFF) + 1
              end

        tmp = [num].pack('w').unpack('C*').reverse
        tmp[0] |= 0x80
        tmp[-1] &= 0x7F

        res = tmp.pack('C*')

        [res, res.bytesize]
      end

      def self.decode(bytes)
        encoded = ''
        bytes.each_byte do |b|
          encoded << b.chr
          break if (b & 0x80) >> 7 == 0x00
        end

        tmp = encoded.unpack('C*')
        tmp[-1] |= 0x80
        tmp[0] &= 0x7F
        tmp = tmp.reverse.pack('C*')

        num = tmp.unpack('w')[0]

        original = if num >> 31 == 0x01
                     ((num - 1) ^ 0xFFFFFFFF) * -1
                   else
                     num
                   end

        [original, encoded.bytesize]
      end

      def self.decodable?(bytes)
        (bytes[-1].ord & 0x80) >> 7 == 0x00
      end
    end
  end
end
