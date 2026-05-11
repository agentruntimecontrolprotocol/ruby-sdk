# frozen_string_literal: true

# Stdout sink — production version uses a structured logger.
class StdoutSink
  def handle(_event)
    # Real version: logger.info(env['type'], **env['payload'])
    raise NotImplementedError
  end
end
