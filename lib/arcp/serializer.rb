# frozen_string_literal: true

require 'json'

module Arcp
  module Serializer
    module_function

    @backend = :stdlib

    def backend = @backend

    def backend=(name)
      case name
      when :stdlib, :oj
        @backend = name
        require 'oj' if name == :oj
      else
        raise ArgumentError, "unknown serializer backend: #{name.inspect}"
      end
    end

    def dump(value)
      case @backend
      when :oj
        Oj.dump(value, mode: :compat)
      else
        JSON.generate(value)
      end
    end

    def load(bytes)
      return nil if bytes.nil? || bytes.empty?

      case @backend
      when :oj
        Oj.load(bytes, mode: :compat)
      else
        JSON.parse(bytes)
      end
    end
  end
end
