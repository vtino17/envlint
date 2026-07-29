# envlint

Catch secrets and exposure mistakes in `.env` and `docker-compose` files
**before you commit them**.

Two files leak more than their share of incidents: a `.env` with a real secret
that ends up in git history, and a `docker-compose.yml` that publishes a database
port to every interface or runs a container `privileged`. envlint scans both.

It is a single Python file with no dependencies — the scanning is pattern-based,
so it needs no YAML parser and runs anywhere. It reads files only and exits
non-zero on any HIGH or CRITICAL finding, which makes it a natural pre-commit
hook.

## Usage

```sh
envlint .env docker-compose.yml
envlint .                       # scan a directory for the usual files
```

Example:

```
$ envlint .env docker-compose.yml
== .env ==
  CRITICAL .env:3: AWS access key id detected
  HIGH     .env:5: Stripe live key detected
  WARN     .env:1: DB_PASSWORD uses a weak/default value 'changeme'
  HIGH     .env: not covered by .gitignore in its directory; risk of committing it
== docker-compose.yml ==
  HIGH     docker-compose.yml:6: PostgreSQL port 5432 is published to ALL interfaces; bind to 127.0.0.1 or drop it
  HIGH     docker-compose.yml:4: privileged: true gives the container near-root on the host
  WARN     docker-compose.yml:9: POSTGRES_PASSWORD set inline in compose; move it to a secret/.env
```

## What it flags

**`.env`**

- Concrete secret formats anywhere in the file: AWS access keys, Stripe live
  keys, GitHub tokens, Google API keys, Slack tokens, JWTs, private-key blocks.
- Secret-named keys (`*PASSWORD*`, `*SECRET*`, `*TOKEN*`, `*API_KEY*`, …) that
  hold a real-looking, high-entropy value — a probable committed secret.
- Weak or default values (`changeme`, `admin`, `postgres`, `123456`, …).
- A `.env` that its sibling `.gitignore` does **not** cover — the thing that
  turns a local secret into a committed one.
- Placeholders (`<your-password>`, empty values) are treated as fine, so
  `.env.example` templates stay quiet.

**compose**

- Sensitive service ports (PostgreSQL, MySQL, Redis, Mongo, Elasticsearch,
  RabbitMQ, the Docker API, …) published to **all** interfaces; loopback-only
  publishing is recognised as safe.
- `privileged: true`, a mounted `/var/run/docker.sock`, and `network_mode: host`.
- Secrets set inline under `environment:` instead of via a secret or `.env`.

## Caveat

Pattern-based scanning is fast and dependency-free, but it is heuristic: it can
miss an exotic secret format and it does not understand YAML structure, only
lines. Treat a clean run as "no obvious mistakes", not a proof, and read each
finding — a bastion or dev-only compose file may expose a port on purpose.

## Tests

```sh
./tests/run.sh
```

Builds throwaway `.env` and compose fixtures in a temp dir, asserts the findings,
cleans up. No root needed.

## License

MIT. See `LICENSE`.
