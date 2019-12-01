# Moku

Moku is an ActivityPub server written in Crystal and backed by Neo4j. It is primarily an experiment to see how Neo4j works as the data store for a social graph.

One primary difference between Moku and Mastodon is that Moku tries as much as possible to do everything in server-rendered HTML rather than having an API and a JS front end. This is just an experiment, so this may change in the future. We may try the "sprinkles of JS" approach or maybe even move to full-on back-end/front-end separation.

## Installation

```
git clone https://github.com/jgaskins/moku.git
shards
```

## Usage

```
crystal src/moku.cr
```

## Development

### Database

A few notes about how the database is structured:

#### Node Labels

| Label | Meaning |
|-------|---------|
| `PartialAccount` | A remote account whose data has not been fully loaded yet |
| `Account` | A fully reified account, either local or remote |
| `UnverifiedLocalAccount` | An account on this instance whose email address has not been verified |
| `LocalAccount` | An account on this instance. These can be queried by handle, which is guaranteed unique. |
| `RemoteAccount` | An account on another instance. Handles are not guaranteed unique, so they must be queried by id. |
| `Person` | Any person this instance knows about, a superset of all accounts (`Account`, `PartialAccount`, and `LocalAccount`) |
| `Moderator` | Can moderate this instance |
| `Admin` | Can administer this instance |
| `KeyPair` | A public/private keypair. For remote accounts, this is probably only going to contain a public key. |

#### Relationship types

| Type | Meaning |
|------|---------|
| `WANTS_TO_FOLLOW` | The origin account has sent a follow request to the target account |
| `FOLLOWS` | The target account has accepted the origin account's follow request |
| `HAS_KEY_PAIR` | The origin node has the target keypair |
| `POSTED` | The origin node has posted the target note |

## Contributing

1. Fork it (<https://github.com/jgaskins/moku/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Jamie Gaskins](https://github.com/jgaskins) - creator and maintainer
