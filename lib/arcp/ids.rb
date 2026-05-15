# frozen_string_literal: true

require 'securerandom'

module Arcp
  module Ids
    module_function

    def envelope_id = SecureRandom.uuid_v7
    def session_id  = "ses_#{SecureRandom.uuid_v7}"
    def job_id      = "job_#{SecureRandom.uuid_v7}"
    def result_id   = "res_#{SecureRandom.uuid_v7}"
    def call_id     = "call_#{SecureRandom.uuid_v7}"
    def resume_token = SecureRandom.urlsafe_base64(24)
    def trace_id    = SecureRandom.hex(16)
    def span_id     = SecureRandom.hex(8)
  end
end
