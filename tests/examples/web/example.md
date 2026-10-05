# Locale matching

Picks the **best** locale for an `Accept-Language` header, falling back
from a regional tag (`pt-BR`) to its *base language* (`pt`).

## Supported locales

| Code    | Name      |
|---------|-----------|
| `en`    | English   |
| `pt-BR` | Português |

## Usage

1. Split the header on commas.
2. Drop each tag's quality value.
3. Return the first tag that matches.

```js
const match = requestedLocale("pt-BR,pt;q=0.9,en;q=0.8");
console.log(match ? match.name : "no match");
```

```ruby
match = requested_locale("pt-BR,pt;q=0.9,en;q=0.8")
puts match ? match.name : "no match"
```

> See [RFC 4647](https://www.rfc-editor.org/rfc/rfc4647) for the full rules.
