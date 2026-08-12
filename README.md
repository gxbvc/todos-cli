# todos-cli

A small Ruby CLI for reading boards and managing tasks through the
todo.gxb.vc JSON API. It is designed for agents and shell pipelines: stdout is
always a single JSON line with a stable success or failure envelope.

## Prerequisites

- Ruby with Bundler
- A todo.gxb.vc account
- An API key created in [todo.gxb.vc Settings](https://todo.gxb.vc/settings)

An admin key can access cross-user routes. A regular user key can read and
update only that user's own visible tasks. The CLI cannot mint keys.

## Setup

```bash
cd ~/tools/todos-cli
bundle install
cp .env.example .env
```

Configure the tool-local `.env`:

```env
TODOS_API_KEY=todo_...
TODOS_BASE_URL=https://todo.gxb.vc
```

For local development, use the URL printed by the todo app (normally
`http://todo.localhost:3149` or `http://127.0.0.1:3149`) and a key minted in the
local database. Production and local keys are different.

Make the command globally available:

```bash
mkdir -p ~/bin
ln -sf ~/tools/todos-cli/todos-cli ~/bin/todos-cli
todos-cli --help
```

The executable resolves its own real path, loads the Gemfile and `.env` from
the tool directory, and therefore works through the symlink from any current
directory.

## Output

Success exits 0:

```json
{"ok":true,"data":{"id":99,"title":"Send W-9"}}
```

Failure exits 1:

```json
{"ok":false,"error":"Forbidden","code":"HTTP_403"}
```

HTTP failures use `HTTP_<status>` codes. Invalid arguments, configuration,
network failures, and unexpected non-JSON responses also use the failure
envelope. Diagnostics are duplicated to stderr; stdout remains parseable.

## Command reference

### Identity and users

```bash
todos-cli me
todos-cli users list
todos-cli users show <id|email>
```

`me` extracts the authenticated user from the caller's own `/tasks.json` board.
User listing and cross-user boards require an admin key. Email references are
resolved through `users list` once per process.

### Boards, areas, and projects

```bash
todos-cli board
todos-cli board --user andy@example.com
todos-cli areas list --user andy@example.com
todos-cli areas create --user andy@example.com -t "BrightView"
todos-cli areas create --user 12 -t "BrightView" --position 1 --active true
todos-cli projects list --user andy@example.com
todos-cli projects create --user andy@example.com -t "Onboarding"
todos-cli projects create --user 12 -t "Tax filings" --area 3 --status active --position 0
```

Without `--user`, `board` reads the authenticated user's own board. `areas list`
and `projects list` require `--user` and flatten from that user's board
(`GET /users/:id.json`). Areas include `id`, `title`, `position`, `active`, and
`project_count`. Projects include `area_id` and `area_title`.

Area and project create are admin nested routes and require `--user`. Omitting
`--area` on project create lets the server assign the user's default area.
Valid project statuses are `active`, `waiting`, `someday`, and `completed`.

### Read tasks

```bash
todos-cli tasks list
todos-cli tasks list --user andy@example.com --project 7 --status open
todos-cli tasks get 99
```

Task lists are read from a board and filtered locally. Valid statuses are
`open`, `submitted`, `approved`, and `canceled`. `tasks get` always uses the
visible-task route `/tasks/:id.json`; the optional `--user` does not change
that bound route.

### Create and update tasks

```bash
todos-cli tasks create --user andy@example.com -t "Send W-9"
todos-cli tasks create --user 12 -t "Complete profile" \
  --project 7 \
  --description "<p>Please complete every field.</p>" \
  --due 2026-08-15 \
  --schema '[{"key":"ein","label":"EIN","type":"text","placeholder":""}]'
todos-cli tasks create --user 12 -t "Complete profile" --schema @schema.json

todos-cli tasks update 99 --user 12 --title "Send signed W-9" --due 2026-08-20
todos-cli tasks update 99 --user 12 --field ein=12-3456789 --notes "Received"
todos-cli tasks destroy 99 --user 12
```

Create, update, and destroy are admin nested routes and require `--user`.
`--schema` accepts either a JSON array or `@path.json`. Repeated `--field`
arguments produce the top-level `response` object accepted by nested updates.

### Status transitions

```bash
todos-cli tasks submit 99 --field ein=12-3456789
todos-cli tasks submit 99 --user andy@example.com
todos-cli tasks approve 99 --user andy@example.com
todos-cli tasks reopen 99
todos-cli tasks reopen 99 --user andy@example.com --note "Need clearer scan"
todos-cli tasks cancel 99
todos-cli tasks cancel 99 --user andy@example.com
```

Without `--user`, submit, reopen, and cancel use the authenticated user's own
task routes. With `--user`, they use admin nested routes. Admin submit does not
accept response fields; update/respond while the task is open first. A reopen
note is available only on the admin nested route because it can notify the
client.

### Responses and notes

```bash
todos-cli tasks respond 99 --field ein=12-3456789 --notes "Ready"
todos-cli tasks respond 99 --user andy@example.com \
  --field ein=12-3456789 \
  --field legal_name="Example LLC" \
  --notes "Entered from source document"
```

Responses and notes are writable only while a task is open. Without `--user`,
the CLI patches `/tasks/:id.json`; with it, the nested admin update route.

## How it works

The command dispatcher uses Ruby's `OptionParser`. `Todos::Client` uses
`Net::HTTP` with Bearer authorization, `Accept: application/json`, and JSON
request bodies. It never follows an HTML authentication redirect as success:
every non-204 success must parse as JSON.

The CLI follows the existing application routes rather than a parallel API
namespace. Cross-user task IDs are nested under the resolved user ID; direct
task reads use the server's explicit visible-task exception.

## Tests

The suite uses a local stub TCP server—no API credentials or production calls:

```bash
bundle exec ruby -Itest test/cli_test.rb
```

It covers every mutating method/path/body binding, error envelopes for common
HTTP statuses, 204, HTML responses, email resolution, schema files, filtering,
and realpath startup through a symlink from a foreign working directory.
