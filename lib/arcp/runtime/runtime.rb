# frozen_string_literal: true

require 'async'

require_relative '../envelope'
require_relative '../session'
require_relative '../job'
require_relative '../lease'
require_relative '../auth'
require_relative '../clock'
require_relative '../message_types'

module Arcp
  module Runtime
    # ARCP runtime. Owns the agent registry, job manager, lease manager,
    # subscription manager, and event log. Sessions attach via
    # `#accept(transport)` which returns an `Async::Task` running the
    # `SessionActor` for that connection.
    class Runtime
      attr_reader :auth_verifier, :clock, :name, :version,
                  :heartbeat_interval_sec, :resume_window_sec,
                  :job_manager, :lease_manager, :subscription_manager, :event_log

      def initialize(auth_verifier:, name: 'arcp-runtime', version: Arcp::VERSION,
                     heartbeat_interval_sec: 30, resume_window_sec: 300,
                     clock: Arcp::SystemClock.new)
        @auth_verifier = auth_verifier
        @name = name
        @version = version
        @heartbeat_interval_sec = heartbeat_interval_sec
        @resume_window_sec = resume_window_sec
        @clock = clock

        @event_log = EventLog.new(window_sec: resume_window_sec, clock: clock)
        @lease_manager = LeaseManager.new(clock: clock)
        @subscription_manager = SubscriptionManager.new
        @job_manager = JobManager.new(
          runtime: self,
          lease_manager: @lease_manager,
          subscription_manager: @subscription_manager,
          event_log: @event_log,
          clock: clock
        )
        @sessions = {}
        @mutex = Mutex.new
      end

      def register_agent(name:, versions:, default:, handler:)
        @job_manager.register_agent(name: name, versions: versions, default: default, handler: handler)
      end

      def local_capabilities(agents_inventory: false)
        Arcp::Session::CapabilitySet.local(
          agents: agents_inventory ? @job_manager.agent_inventory : nil
        )
      end

      def accept(transport)
        actor = SessionActor.new(runtime: self, transport: transport)
        actor.run
      end

      def register_session(session_id, actor)
        @mutex.synchronize { @sessions[session_id] = actor }
      end

      def deregister_session(session_id)
        @mutex.synchronize { @sessions.delete(session_id) }
      end

      def session(session_id) = @mutex.synchronize { @sessions[session_id] }

      def shutdown(reason: nil)
        actors = @mutex.synchronize { @sessions.values.dup }
        actors.each { |a| a.send_envelope(bye_envelope(a.session_id, reason)) }
      end

      private

      def bye_envelope(session_id, reason)
        Arcp::Envelope.build(
          type: Arcp::MessageTypes::SESSION_BYE,
          session_id: session_id,
          payload: Arcp::Session::Bye.new(reason: reason).to_h
        )
      end
    end
  end
end
