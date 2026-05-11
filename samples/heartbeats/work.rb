# frozen_string_literal: true

# Worker work. Real version: a sidekiq/sucker_punch job, run inside
# Async to keep the event loop free.
module Work
  def self.do_work(_payload)
    raise NotImplementedError
  end
end
