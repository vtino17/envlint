#!/usr/bin/env bash
# envlint tests. Read-only; fixtures in a temp dir.
set -uo pipefail
cd "$(dirname "$0")/.."
EL="python3 envlint.py"
pass=0; fail=0
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

assert() {   # <desc> <expect> -- <cmd...>
    local desc="$1" expect="$2"; shift 2; [[ "$1" == "--" ]] && shift
    local out; out="$("$@" 2>&1)"
    if grep -qF -- "$expect" <<<"$out"; then printf '  PASS  %s\n' "$desc"; pass=$((pass+1))
    else printf '  FAIL  %s\n        wanted: %s\n        got: %s\n' "$desc" "$expect" "$out"; fail=$((fail+1)); fi
}
refute() {   # <desc> <needle> -- <cmd...>
    local desc="$1" needle="$2"; shift 2; [[ "$1" == "--" ]] && shift
    local out; out="$("$@" 2>&1)"
    if grep -qF -- "$needle" <<<"$out"; then printf '  FAIL  %s (found %s)\n' "$desc" "$needle"; fail=$((fail+1))
    else printf '  PASS  %s\n' "$desc"; pass=$((pass+1)); fi
}
assert_exit() {  # <desc> <code> -- <cmd...>
    local desc="$1" want="$2"; shift 2; [[ "$1" == "--" ]] && shift
    "$@" >/dev/null 2>&1; local rc=$?
    if [[ "$rc" == "$want" ]]; then printf '  PASS  %s\n' "$desc"; pass=$((pass+1))
    else printf '  FAIL  %s (exit %s want %s)\n' "$desc" "$rc" "$want"; fail=$((fail+1)); fi
}

echo "== syntax =="
if python3 -c "import ast; ast.parse(open('envlint.py').read())"; then
    echo "  PASS  envlint.py parses"; pass=$((pass+1))
else echo "  FAIL  syntax"; fail=$((fail+1)); fi

echo "== .env secret detection =="
printf 'AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE\nSTRIPE=sk_live_9fJ2kLmN8pQ4rT6vX0zA\nDB_PASSWORD=changeme\nDEBUG=true\n' > "$T/.env"
assert "AWS key is critical"     "CRITICAL"                     -- $EL "$T/.env" --no-color
assert "Stripe key is high"      "Stripe live key"              -- $EL "$T/.env" --no-color
assert "weak default is warn"    "weak/default value 'changeme'" -- $EL "$T/.env" --no-color
assert_exit "leaky .env exits non-zero" 1 -- $EL "$T/.env" --no-color

printf 'PASSWORD=<your-password>\nAPI_KEY=\nDEBUG=false\n' > "$T/.env.example"
assert "template flags nothing bad" "empty/placeholder"         -- $EL "$T/.env.example" --no-color
refute "template has no HIGH"    "HIGH"                          -- $EL "$T/.env.example" --no-color
assert_exit "template exits zero" 0 -- $EL "$T/.env.example" --no-color

echo "== .gitignore coverage =="
mkdir -p "$T/proj"; printf 'SECRET_TOKEN=abc123def456ghi789\n' > "$T/proj/.env"; printf 'node_modules/\n' > "$T/proj/.gitignore"
assert "uncovered .env flagged"  "not covered by .gitignore"    -- $EL "$T/proj/.env" --no-color
printf '.env\nnode_modules/\n' > "$T/proj/.gitignore"
refute "covered .env not flagged" "not covered by .gitignore"   -- $EL "$T/proj/.env" --no-color

echo "== compose exposure =="
printf 'services:\n  db:\n    image: postgres\n    privileged: true\n    ports:\n      - "5432:5432"\n    environment:\n      POSTGRES_PASSWORD: hunter2xyz\n  cache:\n    image: redis\n    ports:\n      - "127.0.0.1:6379:6379"\n  agent:\n    volumes:\n      - /var/run/docker.sock:/var/run/docker.sock\n' > "$T/docker-compose.yml"
assert "privileged flagged"      "privileged: true gives"       -- $EL "$T/docker-compose.yml" --no-color
assert "exposed postgres HIGH"   "PostgreSQL port 5432 is published to ALL" -- $EL "$T/docker-compose.yml" --no-color
assert "loopback redis is ok"    "published on loopback only"   -- $EL "$T/docker-compose.yml" --no-color
assert "inline secret flagged"   "set inline in compose"        -- $EL "$T/docker-compose.yml" --no-color
assert "docker socket flagged"   "mounts the docker socket"     -- $EL "$T/docker-compose.yml" --no-color
assert_exit "risky compose exits non-zero" 1 -- $EL "$T/docker-compose.yml" --no-color

echo "== directory scan =="
mkdir -p "$T/clean"; printf 'DEBUG=true\nPORT=8080\n' > "$T/clean/.env"
assert_exit "clean dir exits zero" 0 -- $EL "$T/clean" --no-color
mkdir -p "$T/variants"
printf 'TOKEN=ghp_abcdefghijklmnopqrstuvwxyzABCDEFGHIJ\n' > "$T/variants/.env.production"
printf 'services:\n  db:\n    ports:\n      - "5432:5432"\n' > "$T/variants/compose.yaml"
assert "directory finds environment variants" ".env.production" -- $EL "$T/variants" --no-color
assert "directory finds compose.yaml" "PostgreSQL port 5432" -- $EL "$T/variants" --no-color

echo
echo "== $pass passed, $fail failed =="
[[ $fail -eq 0 ]]
