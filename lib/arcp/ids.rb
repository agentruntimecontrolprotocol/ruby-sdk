# frozen_string_literal: true

require 'securerandom'

module Arcp
  # Identifier helpers for protocol objects.
  module Ids
    module_function

    # @api private
    def envelope_id = SecureRandom.uuid_v7
    # @api private
    def session_id  = "ses_#{SecureRandom.uuid_v7}"
    # @api private
    def job_id      = "job_#{SecureRandom.uuid_v7}"
    # @api private
    def result_id   = "res_#{SecureRandom.uuid_v7}"
    # @api private
    def call_id     = "call_#{SecureRandom.uuid_v7}"
    # @api private
    def resume_token = SecureRandom.urlsafe_base64(24)
    # @api private
    def trace_id    = SecureRandom.hex(16)
    # @api private
    def span_id     = SecureRandom.hex(8)
  end
end
