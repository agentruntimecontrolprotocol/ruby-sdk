# frozen_string_literal: true

module Arcp
  module MessageTypes
    SESSION_HELLO     = 'session.hello'
    SESSION_WELCOME   = 'session.welcome'
    SESSION_BYE       = 'session.bye'
    SESSION_ERROR     = 'session.error'
    SESSION_PING      = 'session.ping'
    SESSION_PONG      = 'session.pong'
    SESSION_ACK       = 'session.ack'
    SESSION_LIST_JOBS = 'session.list_jobs'
    SESSION_JOBS      = 'session.jobs'

    JOB_SUBMIT        = 'job.submit'
    JOB_ACCEPTED      = 'job.accepted'
    JOB_EVENT         = 'job.event'
    JOB_RESULT        = 'job.result'
    JOB_ERROR         = 'job.error'
    JOB_CANCEL        = 'job.cancel'
    JOB_SUBSCRIBE     = 'job.subscribe'
    JOB_SUBSCRIBED    = 'job.subscribed'
    JOB_UNSUBSCRIBE   = 'job.unsubscribe'

    ALL = [
      SESSION_HELLO, SESSION_WELCOME, SESSION_BYE, SESSION_ERROR,
      SESSION_PING, SESSION_PONG, SESSION_ACK,
      SESSION_LIST_JOBS, SESSION_JOBS,
      JOB_SUBMIT, JOB_ACCEPTED, JOB_EVENT, JOB_RESULT, JOB_ERROR,
      JOB_CANCEL, JOB_SUBSCRIBE, JOB_SUBSCRIBED, JOB_UNSUBSCRIBE
    ].freeze

    def self.known?(type) = ALL.include?(type)
  end
end
