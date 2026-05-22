# frozen_string_literal: true

require 'async'

require_relative '../envelope'
require_relative '../session'
require_relative '../job'
require_relative '../lease'
require_relative '../credential_provisioner'
require_relative '../auth'
require_relative '../clock'
require_relative '../message_types'
require_relative 'credential_registry'

module Arcp
  module Runtime
    # ARCP runtime. Owns the agent registry, job manager, lease manager,
    # subscription manager, and event log. Sessions attach via
    # `#accept(transport)` which returns an `Async::Task` running the
    # `SessionActor` for that connection.
    class Runtime
      attr_reader :auth_verifier, :clock, :name, :version,
                  :heartbeat_interval_sec, :resume_window_sec,
                  :job_manager, :lease_manager, :subscription_manager,
                  :event_log, :credential_registry, :enforce_model_use

      def initialize(auth_verifier:, name: 'arcp-runtime', version: Arcp::VERSION,
                     heartbeat_interval_sec: 30, resume_window_sec: 300,
                     clock: Arcp::SystemClock.new, credential_provisioner: nil,
                     credential_store: nil, require_durable_store: false,
                     enforce_model_use: false)
        if require_durable_store && credential_provisioner && credential_store.nil?
          raise Arcp::Errors::InvalidRequest,
                'provisioned_credentials requires a CredentialStore'
        end

        @auth_verifier = auth_verifier
        @name = name
        @version = version
        @heartbeat_interval_sec = heartbeat_interval_sec
        @resume_window_sec = resume_window_sec
        @clock = clock
        @enforce_model_use = enforce_model_use
        @credential_registry = build_credential_registry(
          credential_provisioner: credential_provisioner,
          credential_store: credential_store,
          clock: clock
        )

        @event_log = EventLog.new(window_sec: resume_window_sec, clock: clock)
        @lease_manager = LeaseManager.new(clock: clock, enforce_model_use: enforce_model_use)
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
        features = Arcp::Session::Feature::ALL.dup
        unless @credential_registry
          features -= [
            Arcp::Session::Feature::MODEL_USE,
            Arcp::Session::Feature::PROVISIONED_CREDENTIALS
          ]
        end

        Arcp::Session::CapabilitySet.local(
          features: features,
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

      def build_credential_registry(credential_provisioner:, credential_store:, clock:)
        return nil unless credential_provisioner

        store = credential_store || Arcp::Credentials::InMemoryStore.new
        CredentialRegistry.new(
          provisioner: credential_provisioner,
          store: store,
          clock: clock
        ).tap(&:reconcile_on_startup!)
      end

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
