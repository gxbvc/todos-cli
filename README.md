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

The executable resolves its own real path and loads `.env` from the tool
directory, so it works through the symlink from any current directory.

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
todos-cli projects create -t "TAP intake" --area 4
todos-cli projects invite 12 --email sue@example.com
todos-cli areas invite 52 --email sue@example.com
todos-cli invites list
todos-cli invites accept project-4 --area 3
todos-cli invites accept area-2
```

Without `--user`, `board` reads the authenticated user's own board. `areas list`
and `projects list` require `--user` and flatten from that user's board
(`GET /users/:id.json`). Areas include `id`, `title`, `position`, `active`, and
`project_count`. Projects include `area_id` and `area_title`.

Area create is an admin nested route and requires `--user`. Project create with
`--user` is the admin route on that person's board. Without `--user` it makes a
project you own (`POST /projects.json`) in one of your own areas (`--area`;
`GET /projects.json` rows carry your `area_id`); `--status` and `--position`
need `--user`. Omitting `--area` lets the server use the first area. It prints
"No --user: making the project in your own board." on stderr, so a forgotten
`--user` is easy to see.
Valid project statuses are `active`, `waiting`, `someday`, and `completed`.

`projects invite <id> --email EMAIL` emails a one-time link to join a project
you own (`POST /projects/:id/invites.json`). `data.status` is `invited` (sent,
or a pending invite sent again) or `already_member` (nothing sent). A refusal
(not the owner, a bad email, the 20-an-hour limit) exits 1 with the server's
reason. The reply never says whether the email has an account.

`areas invite <id> --email EMAIL` emails a one-time link to join a whole area
you own (`POST /areas/:id/invites.json`). It shares every project you own in
that area, now and later. It never shares projects other people shared with you
that you filed there. The reply and refusals work like `projects invite`.

`invites list` shows the project and area invites sent to your own account
email (`GET /invites.json`): `id` (like `project-4` or `area-2`), `kind`,
`project` or `area` `{id, title}`, the inviter by name, and `expires_at`.
`invites accept <id> [--area ID]` joins one (`POST /invites/:id/accept.json`).
A project goes in one of your areas, or in your "Shared" area; `data` is the
project as `GET /projects.json` shows it. An area's projects go in one of your
areas, or in a new area named after it ("TriGate (Ricky)"); `data` is
`{area, filed_area_id, projects}`. Any invite you cannot accept (not yours,
expired, revoked, used) is `HTTP_404`. `GET /projects.json` rows name each
project's `owner`.
An invited project is not on your board until you accept, so `board` and
`tasks list` print `You have N open invites. Run: todos-cli invites list` on
stderr when there are any.

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
todos-cli tasks create --user andy@example.com \
  -t "Upload your signed W-9 to this card" \
  --description "<p>IRS wants a W-9 before the first invoice. Open https://www.irs.gov/pub/irs-pdf/fw9.pdf, sign, upload here.</p>" \
  --estimate 5 \
  --schema '[{"key":"w9","label":"Signed W-9","type":"file"}]'
todos-cli tasks create --user 12 -t "Upload your signed W-9 to this card" --schema @schema.json

todos-cli tasks update 99 --user 12 --title "Send signed W-9" --due 2026-08-20
todos-cli tasks update 99 --user 12 --field ein=12-3456789 --notes "Received"
todos-cli tasks destroy 99 --user 12
```

`tasks create --user` is the admin nested route. Without `--user` it is the
member route (`POST /tasks.json`): a task in one of your projects, for you or
for `--assignee EMAIL` (an active member of that project). `--star` stars it.
`--estimate` and `--source-url` need `--user`.

The server scores every task on 7 checks. `tasks check -t TITLE` scores a
draft without saving it. `create`, `get`, and `show` print the score and each
check on stderr, with the hint for each fail. A refused create (422) exits 1
and puts `quality` in the envelope.

Update and destroy are admin nested routes and require `--user`.
`--schema` accepts either a JSON array or `@path.json`. Repeated `--field`
arguments produce the top-level `response` object accepted by nested updates.

### Status transitions

```bash
todos-cli tasks submit 99 --field ein=12-3456789
todos-cli tasks submit 99 --user andy@example.com
todos-cli tasks approve 99 --user andy@example.com
todos-cli tasks approve 99
todos-cli tasks send-back 99 --note "Add the invoice number"
todos-cli tasks star 99 [--off]
todos-cli tasks reopen 99
todos-cli tasks reopen 99 --user andy@example.com --note "Need clearer scan"
todos-cli tasks cancel 99
todos-cli tasks cancel 99 --user andy@example.com
```

Without `--user`, submit, reopen, cancel, approve, send-back, and star use the
authenticated user's own task routes. With `--user`, they use admin nested routes. Admin submit does not
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
