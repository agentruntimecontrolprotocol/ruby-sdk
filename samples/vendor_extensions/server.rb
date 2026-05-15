# frozen_string_literal: true

require_relative '../_harness'

module VendorExtensionsSample
  HANDLER = lambda do |ctx|
    ctx.emit(kind: 'x-vendor.acme.progress', body: { 'stage' => 'mapping', 'percent' => 50 })
    ctx.emit(kind: 'x-vendor.acme.progress', body: { 'stage' => 'mapping', 'percent' => 100 })
    ctx.finish(result: 'done')
  end

  def self.runtime = Harness.runtime(agents: { 'mapper' => HANDLER })
end
