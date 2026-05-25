# frozen_string_literal: true

# Steep targets the smallest reliable surface today: the version file
# plus the transport base contract. Bringing the rest of the implementation
# back under Steep is tracked as ongoing work — adding files here once
# their sigs are accurate keeps Steep useful instead of drowning in
# pre-existing drift from the Ruby 3.4 `Data.define` rewrite. The runtime
# sigs in `sig/arcp/runtime.rbs` are kept current so downstream consumers
# (and future Steep coverage) can rely on them.
target :lib do
  signature 'sig'

  check 'lib/arcp/version.rb'
  check 'lib/arcp/transport/base.rb'

  library 'time'
  library 'bigdecimal'
  library 'securerandom'
  library 'logger'
  library 'json'
end
