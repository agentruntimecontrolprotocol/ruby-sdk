# frozen_string_literal: true

module Arcp
  Credential = Data.define(:id, :scheme, :value, :endpoint, :profile, :constraints) do
    def initialize(id:, scheme:, value:, endpoint:, profile: nil, constraints: nil)
      super(
        id: id,
        scheme: scheme,
        value: value,
        endpoint: endpoint,
        profile: profile,
        constraints: constraints || {}
      )
    end

    def self.from_h(h)
      h = h.transform_keys(&:to_s)
      new(
        id: h.fetch('id'),
        scheme: h.fetch('scheme'),
        value: h.fetch('value'),
        endpoint: h.fetch('endpoint'),
        profile: h['profile'],
        constraints: h['constraints'] || {}
      )
    end

    def to_h
      out = { 'id' => id, 'scheme' => scheme, 'value' => value, 'endpoint' => endpoint }
      out['profile'] = profile if profile
      out['constraints'] = constraints if constraints && !constraints.empty?
      out
    end

    def to_redacted_h
      to_h.merge('value' => '[REDACTED]')
    end
  end

  Credential.const_set(:SCHEME_BEARER, 'bearer') unless Credential.const_defined?(:SCHEME_BEARER)

  module ModelPattern
    FLAGS = File::FNM_PATHNAME | File::FNM_EXTGLOB

    module_function

    def match?(patterns, model_id)
      Array(patterns).any? { |pattern| File.fnmatch?(pattern, model_id, FLAGS) }
    end

    def implied_by?(parent_patterns, child_pattern)
      Array(parent_patterns).any? do |parent|
        child_pattern == parent || literal_match?(parent, child_pattern)
      end
    end

    def literal_match?(parent_pattern, child_pattern)
      !glob?(child_pattern) && match?([parent_pattern], child_pattern)
    end

    def glob?(pattern)
      pattern.match?(/[*?\[\]{}]/)
    end
  end
end
