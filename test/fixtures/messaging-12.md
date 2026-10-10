Ref DIS-107

## Why

DIS-107 asks that no infrastructure address be fixed in a committed file, and that
`allowed_origins` stop being `["*"]`. The global stack and production name Messaging's
sidecars `messaging-*`, because Cloud Map names must be unique across the namespace. This
repository's compose keeps the bare names (`centrifugo`, `valkey`, `mongo`, `migrate`).
So `centrifugo/config.yaml` has to take its addresses from the environment: its defaults
serve this compose, and the other environments set the variables. The global stack
already does (`CENTRIFUGO_ENGINE_REDIS_ADDRESS=redis://messaging-valkey:6379`).

## What changes

- **`centrifugo/config.yaml`**:
  - The engine address and both proxy endpoints stay in the file as defaults for this
    compose, and the environment overrides them: `CENTRIFUGO_ENGINE_REDIS_ADDRESS`,
    `CENTRIFUGO_CLIENT_PROXY_CONNECT_ENDPOINT` and
    `CENTRIFUGO_CHANNEL_PROXY_SUBSCRIBE_ENDPOINT`.
  - `allowed_origins` is no longer in the file. It comes from
    `CENTRIFUGO_CLIENT_ALLOWED_ORIGINS`, space-separated, which compose sets to `*`
    through `CENTRIFUGO_ALLOWED_ORIGINS` in `.env`. When it is unset, every browser
    connection is refused, so a deployment that forgets it fails closed. A native
    client, which sends no `Origin`, is still accepted.
- **`docs/centrifugo.md`**: the options table and the environment table list all four
  variables, each with its default. **`CLAUDE.md`** and **`.env.example`** follow.

DIS-107 item 5 (Centrifugo verifying tokens with `client.token.rsa_public_key`) is not
here on purpose. #10's connect proxy made Centrifugo keyless, so the connect gate
verifies every connection and adding a key would undo that design.

## How it was checked

- `mise run check`: exit 0, every step green.
- `centrifugo defaultenv` on `centrifugo/centrifugo:v6.9.4` lists all four variable
  names exactly as documented.
- Origins, tried against that image with a WebSocket handshake:
  - set to `"http://a.test http://b.test"`: both origins get 101, `http://c.test` gets
    403, and no `Origin` gets 101.
  - unset: every `Origin` gets 403, including Centrifugo's own, and no `Origin` gets 101.
- The stack came up under a separate project name, because another worktree's stack
  holds `discordia-messaging` and its ports. `messaging`, `centrifugo`, `valkey` and
  `mongo` became healthy and `migrate` exited 0.

## Not in this PR

- The gateway forwards `/messaging/internal/*`, where the subscribe gate trusts the
  `user` field in the request body. That is DIS-114, in `discordia-api-gateway`.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

