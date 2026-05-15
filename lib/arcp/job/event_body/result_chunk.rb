# frozen_string_literal: true

require 'base64'

module Arcp
  module Job
    module EventBody
      ResultChunk = Data.define(:result_id, :chunk_seq, :data, :encoding, :more) do
        ENCODINGS = %w[utf8 base64].freeze

        def self.from_h(h)
          h = h.transform_keys(&:to_s)
          encoding = h.fetch('encoding')
          raise Arcp::Errors::InvalidRequest, "unknown encoding: #{encoding.inspect}" unless ENCODINGS.include?(encoding)

          new(
            result_id: h.fetch('result_id'),
            chunk_seq: h.fetch('chunk_seq'),
            data: h.fetch('data'),
            encoding: encoding,
            more: h.fetch('more')
          )
        end

        def to_h
          { 'result_id' => result_id, 'chunk_seq' => chunk_seq, 'data' => data,
            'encoding' => encoding, 'more' => more }
        end

        def decoded
          case encoding
          when 'utf8'   then data
          when 'base64' then Base64.decode64(data)
          end
        end
      end
    end
  end
end
