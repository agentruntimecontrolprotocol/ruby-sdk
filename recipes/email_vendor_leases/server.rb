# frozen_string_literal: true

# email_vendor_leases — Claude tool-use loop with a lease that denies send_reply.
#
# A triage agent receives an "inbox check" task with a lease that grants
# read-only tools but NOT send_reply. Claude reads each message, emits a
# vendor-extension event per parsed message so dashboards can render
# them specially, and eventually decides one needs a reply. When it
# tries to call send_reply the lease check denies it; Claude observes
# the PERMISSION_DENIED tool_result and degrades to drafting the reply
# for human review.
#
# Highlights: §13.4 lease violation as a *recoverable* tool_result error
# (not session-fatal), §15 / §8.2 x-vendor.* event-kind namespace, and
# a realistic Claude tool-use loop that handles a deny without crashing.

require 'anthropic'
require_relative '../../samples/_harness'

module EmailVendorLeasesRecipe
  TOOLS = [
    {
      'name' => 'inbox_list',
      'description' => 'List recent unread messages.',
      'input_schema' => { 'type' => 'object', 'properties' => {} }
    },
    {
      'name' => 'inbox_read',
      'description' => 'Read one message by id.',
      'input_schema' => {
        'type' => 'object',
        'properties' => { 'id' => { 'type' => 'string' } },
        'required' => ['id']
      }
    },
    {
      'name' => 'send_reply',
      'description' => 'Send a reply to a message.',
      'input_schema' => {
        'type' => 'object',
        'properties' => { 'id' => { 'type' => 'string' }, 'body' => { 'type' => 'string' } },
        'required' => %w[id body]
      }
    }
  ].freeze

  # stand-in inbox so the recipe is self-contained — swap for IMAP/Gmail in real use
  INBOX = {
    'm1' => { 'id' => 'm1', 'from' => 'ops@acme.dev', 'subject' => 'Status',
              'body' => 'All quiet.', 'urgency' => 'low' },
    'm2' => { 'id' => 'm2', 'from' => 'ceo@acme.dev', 'subject' => 'Outage!',
              'body' => 'Site is down — fix asap.', 'urgency' => 'high' }
  }.freeze

  def self.run_tool(name, args)
    case name
    when 'inbox_list'
      INBOX.values.map { |m| m.slice('id', 'subject', 'from') }
    when 'inbox_read'
      INBOX.fetch(args['id'])
    else
      raise "tool #{name} should have been denied before reaching run_tool"
    end
  end

  HANDLER = lambda do |ctx|
    lease_manager = $arcp_runtime.lease_manager
    anthropic = Anthropic::Client.new

    messages = [{
      role: 'user',
      content: 'Triage my inbox. Read each unread message and reply to anything urgent.'
    }]

    # tool-use loop: Claude proposes a tool call, we authorize against the
    # lease, run it (or surface a denial), feed the result back, repeat.
    loop do
      turn = anthropic.messages(
        parameters: {
          model: 'claude-sonnet-4-6',
          max_tokens: 1024,
          tools: TOOLS,
          messages: messages
        }
      )

      if turn['stop_reason'] == 'end_turn'
        text = turn['content'].find { |b| b['type'] == 'text' }&.dig('text').to_s
        ctx.finish(result: { 'drafted_reply' => text, 'sent' => false })
        return
      end

      # append the assistant turn so the next call has full context
      messages << { role: 'assistant', content: turn['content'] }
      tool_results = []

      turn['content'].each do |block|
        next unless block['type'] == 'tool_use'

        ctx.tool_call(call_id: block['id'], tool: block['name'], args: block['input'])

        begin
          # the lease grants tool.call only for the read-only tools; the
          # send_reply pattern is absent so this raises PermissionDenied
          lease_manager.check!(ctx.job_id, capability: "tool.call:#{block['name']}")
        rescue Arcp::Errors::PermissionDenied => e
          # surface the denial on the ARCP stream as a recoverable error...
          ctx.tool_result(call_id: block['id'], error: e.to_payload)
          # ...and hand it to Claude as the tool result so the model can
          # recover gracefully — lease violations are not session-fatal
          tool_results << {
            type: 'tool_result',
            tool_use_id: block['id'],
            content: "denied: #{e.message}",
            is_error: true
          }
          next
        end

        result = run_tool(block['name'], block['input'])
        if block['name'] == 'inbox_read'
          # vendor-extension event — dashboards that recognise the
          # x-vendor.acme.* namespace render parsed metadata specially
          ctx.emit(
            kind: 'x-vendor.acme.email.parsed',
            body: {
              'message_id' => result['id'],
              'from' => result['from'],
              'subject' => result['subject'],
              'urgency' => result['urgency']
            }
          )
        end
        ctx.tool_result(call_id: block['id'], result: result)
        tool_results << { type: 'tool_result', tool_use_id: block['id'], content: result.to_json }
      end

      messages << { role: 'user', content: tool_results }
    end
  end

  def self.runtime
    r = Harness.runtime(agents: { 'triage' => HANDLER })
    $arcp_runtime = r
    r
  end
end
