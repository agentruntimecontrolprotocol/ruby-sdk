# frozen_string_literal: true

require 'dry/cli'
require 'json'
require 'logger'

require 'arcp'

module Arcp
  module CLI
    # `arcp serve` — start an ARCP runtime over the chosen transport.
    class Serve < Dry::CLI::Command
      desc 'Start an ARCP runtime'
      option :transport, default: 'stdio', values: %w[stdio ws], desc: 'Transport (stdio|ws)'
      option :bind, default: '127.0.0.1:7777', desc: 'WebSocket bind address (host:port)'
      option :token, default: nil, desc: 'Bearer token to accept (defaults to accept-any)'
      option :accept_any, type: :boolean, default: true, desc: 'Accept any non-empty bearer token'

      def call(transport:, bind:, token:, accept_any:, **)
        runtime = build_runtime(token: token, accept_any: accept_any)
        case transport
        when 'stdio'
          serve_stdio(runtime)
        when 'ws'
          serve_websocket(runtime, bind: bind)
        end
      end

      private

      def build_runtime(token:, accept_any:)
        tokens = token ? { token => 'cli-user' } : {}
        bearer = Arcp::Auth::Bearer.new(tokens: tokens, accept_any: accept_any)
        runtime = Arcp::Runtime::Runtime.new(
          schemes: [bearer],
          logger: Logger.new($stderr, level: Logger::INFO)
        )
        register_demo_tools(runtime)
        runtime
      end

      def register_demo_tools(runtime)
        runtime.register_tool('echo') { |_ctx, args| { echoed: args } }
        runtime.register_tool('progress') do |ctx, _args|
          (1..3).each do |i|
            ctx.progress(percent: i * 33, message: "step #{i}")
          end
          :done
        end
      end

      def serve_stdio(runtime)
        transport = Arcp::Transport::Stdio.new
        Sync { runtime.serve(transport) }
      end

      def serve_websocket(runtime, bind:)
        host, port = bind.split(':')
        endpoint = Async::HTTP::Endpoint.parse("ws://#{host}:#{port}/")
        warn("[arcp] serving WebSocket at ws://#{host}:#{port}/")
        Sync do
          server = Arcp::Transport::Websocket::Server.new(endpoint: endpoint)
          server.run { |transport| runtime.serve(transport) }
        end
      end
    end

    # `arcp send <type> [json]` — send a single envelope to a stdio peer
    # on stdin/stdout. Useful for scripted smoke tests.
    class Send < Dry::CLI::Command
      desc 'Send a JSON envelope on stdout and print the response'
      argument :type, required: true, desc: 'Envelope type (e.g. ping)'
      argument :json, required: false, default: '{}', desc: 'JSON payload'

      def call(type:, json: '{}', **)
        payload_hash = JSON.parse(json)
        payload_class = Arcp::MessageTypeRegistry.class_for(type)
        payload = payload_class ? payload_class.from_hash(payload_hash) : payload_hash
        envelope = Arcp::Envelope.build(type: type, payload: payload)
        puts Arcp::Json.encode_envelope(envelope)
      end
    end

    # `arcp tail <event-log.sqlite>` — print the canonical event log to stdout.
    class Tail < Dry::CLI::Command
      desc 'Print the canonical event log'
      argument :path, required: true, desc: 'Path to SQLite event log'

      def call(path:, **)
        log = Arcp::Store::EventLog.new(path: path)
        log.replay.each do |env|
          puts Arcp::Json.encode_envelope(env)
        end
      ensure
        log&.close
      end
    end

    # `arcp replay <event-log.sqlite> --after <message-id>` — replay
    # events matching the given filter to stdout.
    class Replay < Dry::CLI::Command
      desc 'Replay events from the event log after a given message id'
      argument :path, required: true, desc: 'Path to SQLite event log'
      option :after, default: nil, desc: 'Replay strictly after this message id'

      def call(path:, after: nil, **)
        log = Arcp::Store::EventLog.new(path: path)
        after_seq = after && log.seq_for(after)
        log.replay(after_seq: after_seq).each { |env| puts Arcp::Json.encode_envelope(env) }
      ensure
        log&.close
      end
    end

    # `arcp version`
    class Version < Dry::CLI::Command
      desc 'Print the gem and protocol version'

      def call(**)
        puts "arcp #{Arcp::IMPL_VERSION} (protocol #{Arcp::PROTOCOL_VERSION})"
      end
    end

    extend Dry::CLI::Registry

    register 'serve',   Serve
    register 'send',    Send
    register 'tail',    Tail
    register 'replay',  Replay
    register 'version', Version
  end
end
