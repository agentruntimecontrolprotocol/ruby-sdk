---
title: Authentication
sdk: ruby
kind: guide
order: 11
spec_sections: [§6.1]
---

# Authentication

`session.hello` carries an `auth` block. The runtime's `AuthScheme`
implementation inspects it and returns an `Arcp::Auth::Principal` or
`nil` (reject).

## Bearer scheme

The bundled `Arcp::Auth::Bearer` verifier holds a static map of token
strings to principals.

```ruby
verifier = Arcp::Auth::Bearer.new(
  tokens: {
    'tk-alice' => Arcp::Auth::Principal.new(
      id: 'alice', name: 'Alice', scopes: ['jobs.submit'].freeze
    ),
    'tk-bob'   => Arcp::Auth::Principal.new(
      id: 'bob',   name: 'Bob',   scopes: [].freeze
    )
  }
)

runtime = Arcp::Runtime::Runtime.new(auth_verifier: verifier)

client = Arcp::Client.open(
  transport: t,
  auth: { 'scheme' => 'bearer', 'token' => 'tk-alice' }
)
```

The shorthand `Arcp::Auth::Bearer.from_token('tk', principal_id: 'alice')`
creates a one-entry verifier for tests.

## Custom AuthScheme

Any object with `#verify(token) -> Principal | nil` works.

```ruby
class HmacAuth
  include Arcp::Auth::AuthScheme

  def verify(token)
    return nil if token.nil?

    principal, signature = token.split(':', 2)
    return nil if principal.nil? || signature.nil?

    expected = OpenSSL::HMAC.hexdigest('SHA256', ENV.fetch('AUTH_SECRET'), principal)
    return nil unless OpenSSL.fixed_length_secure_compare(expected, signature)

    Arcp::Auth::Principal.new(id: principal, name: principal, scopes: [].freeze)
  end
end

runtime = Arcp::Runtime::Runtime.new(auth_verifier: HmacAuth.new)
```

Returning `nil` causes `session.error` with code `UNAUTHENTICATED`,
raised on the client as `Arcp::Errors::Unauthenticated`.

## See also

- `guides/sessions.md`
