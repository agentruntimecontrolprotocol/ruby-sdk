# frozen_string_literal: true

# Per-destination channel adapters. Real versions wrap ntfy.sh, SES,
# and the Slack web API. Each returns a value matching the request's
# `response_schema`.
module Channels
  def self.ntfy_phone(_prompt, _schema)
    raise NotImplementedError
  end

  def self.email_oncall(_prompt, _schema)
    raise NotImplementedError
  end

  def self.slack_ops(_prompt, _schema)
    raise NotImplementedError
  end

  REGISTRY = {
    'ntfy:phone' => method(:ntfy_phone),
    'email:oncall' => method(:email_oncall),
    'slack:ops' => method(:slack_ops)
  }.freeze
end
