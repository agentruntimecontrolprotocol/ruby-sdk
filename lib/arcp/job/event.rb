# frozen_string_literal: true

# Body classes live in `Arcp::Job::EventBody`. The `Event` constant
# below is a `Data.define` value object — it cannot also be a module,
# so the per-kind body types are namespaced separately.
require_relative 'event_body/progress'
require_relative 'event_body/result_chunk'
require_relative 'event_body/log'
require_relative 'event_body/thought'
require_relative 'event_body/tool_call'
require_relative 'event_body/tool_result'
require_relative 'event_body/status'
require_relative 'event_body/metric'
require_relative 'event_body/trace_span'
require_relative 'event_body/delegate'

module Arcp
  module Job
    module EventKind
      PROGRESS     = 'progress'
      RESULT_CHUNK = 'result_chunk'
      LOG          = 'log'
      THOUGHT      = 'thought'
      TOOL_CALL    = 'tool_call'
      TOOL_RESULT  = 'tool_result'
      STATUS       = 'status'
      METRIC       = 'metric'
      TRACE_SPAN   = 'trace_span'
      DELEGATE     = 'delegate'

      ALL = [
        PROGRESS, RESULT_CHUNK, LOG, THOUGHT, TOOL_CALL, TOOL_RESULT,
        STATUS, METRIC, TRACE_SPAN, DELEGATE
      ].freeze
    end

    BODY_CLASSES = {
      EventKind::PROGRESS => EventBody::Progress,
      EventKind::RESULT_CHUNK => EventBody::ResultChunk,
      EventKind::LOG => EventBody::Log,
      EventKind::THOUGHT => EventBody::Thought,
      EventKind::TOOL_CALL => EventBody::ToolCall,
      EventKind::TOOL_RESULT => EventBody::ToolResult,
      EventKind::STATUS => EventBody::Status,
      EventKind::METRIC => EventBody::Metric,
      EventKind::TRACE_SPAN => EventBody::TraceSpan,
      EventKind::DELEGATE => EventBody::Delegate
    }.freeze

    Event = Data.define(:kind, :body) do
      def self.from_h(h)
        h = h.transform_keys(&:to_s)
        kind = h.fetch('kind')
        body_h = h['body'] || {}
        klass = BODY_CLASSES[kind]
        body = klass ? klass.from_h(body_h) : Arcp::Envelope.deep_freeze(body_h.dup)
        new(kind: kind, body: body)
      end

      def to_h
        body_h = body.respond_to?(:to_h) ? body.to_h : body
        { 'kind' => kind, 'body' => body_h }
      end

      def known? = EventKind::ALL.include?(kind)
    end
  end
end
