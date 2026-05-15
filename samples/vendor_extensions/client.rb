# frozen_string_literal: true

require_relative '../_harness'

module VendorExtensionsSample
  module Client
    def self.run(client)
      handle = client.submit_job(agent: 'mapper')
      vendor = handle.subscribe(client: client).filter_map do |event|
        case event
        in { kind: String => k, body: Hash => body } if k.start_with?('x-vendor.')
          [k, body['stage'], body['percent']]
        else
          nil
        end
      end
      [handle, vendor.to_a]
    end
  end
end
