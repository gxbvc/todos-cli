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
todos-cli projects list
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

Without `--user`, `board` reads the authenticated user's own board, and
`projects list` reads your own projects (`GET /projects.json`: members, your
`area_id`, and `external`). `areas list` requires `--user`; it and
`projects list --user` flatten from that user's board (`GET /users/:id.json`).
Areas include `id`, `title`, `position`, `active`, and `project_count`.
Projects include `area_id` and `area_title`.

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
or a pending invite sent again) or `already_member` (nothing sent). A colleague
at your own work email domain (not gmail.com and the like) who already has an
account is `added` at once instead: `data.member` names them, they get a notice
email with no link, and stderr says "No invite was sent." Otherwise the reply
never says whether the email has an account. A refusal (not the owner, a bad
email, the 20-an-hour limit) exits 1 with the server's reason.

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

### Logbook

```bash
todos-cli logbook
todos-cli logbook --kind canceled
todos-cli logbook --before 2026-09-30
todos-cli logbook --all
todos-cli tasks list --status canceled
```

Your board leaves canceled to-dos off. They go to your logbook (`GET
/logbook.json`) with the to-dos you logged, newest first. Each entry has `kind`
(`logged` with `logged_at`, or `canceled` with `canceled_at`), `project_title`,
`reviewer`, and `declined` (`{by, at, reason}` when the assignee declined it).
The canceled entries are the canceled to-dos of every project on your board,
whoever does them. `tasks list --status canceled` without `--user` reads them
from the logbook (every week); with `--user`, the admin board still has every
status.

The logbook gives one week at a time: the 7 days before `--before DATE`
(default: up to today). The reply has `next_before`, the date for the week
before, or null when nothing is older; stderr names it. `--all` reads every
week.

### Create and update tasks

```bash
todos-cli tasks create --user andy@example.com \
  -t "Upload your signed W-9 to this card" \
  --description "IRS wants a W-9 before the first invoice. Open https://www.irs.gov/pub/irs-pdf/fw9.pdf, sign, and upload it here." \
  --estimate 5 \
  --schema '[{"key":"w9","label":"Signed W-9","type":"file"}]'
todos-cli tasks create --user 12 -t "Upload your signed W-9 to this card" --schema @schema.json

todos-cli tasks update 99 --user 12 --title "Send signed W-9" --due 2026-08-20
todos-cli tasks create -t "Call the bank at 214-555-0100 before it closes" --project 3 --due 2026-10-02 --due-time 15:30
todos-cli tasks update 99 --user 12 --due-time 09:00
todos-cli tasks update 99 --user 12 --due-time ""
todos-cli tasks update 99 --user 12 --field ein=12-3456789
todos-cli tasks destroy 99 --user 12
```

`tasks create --user` is the admin nested route. Without `--user` it is the
member route (`POST /tasks.json`): a task in one of your projects, for you or
for `--assignee EMAIL` (an active member of that project, or someone you
invited to it or its area who has not joined yet: the task waits on the invite,
`data.assignee` is null and `data.waiting_for_invite.id` names the invite, and
it lands on them when they accept). `--star` stars it.
`--estimate` and `--source-url` need `--user`.

Descriptions are markdown, the one format todo stores and the same field the
web form and the chat connector use. `--description @card.md` reads it from a
file. `tasks get` returns it as `data.description` (the card text, links
included). `description_html` is deprecated and goes away after one release;
until then, HTML passed to `--description` is converted to markdown by the
server.

Due dates: `--due YYYY-MM-DD` is the day. `--due-time HH:MM` adds a time, in
24-hour Central time (America/Chicago, the app's one time zone), for example
`--due-time 15:30`. On create it needs `--due`. On update it can come alone,
when the task already has a day; a new `--due` alone keeps the time. On update,
`--due-time ""` clears the time and keeps the day, and `--due ""` clears both.
A time inside `--due` (such as `2026-10-02T15:00`) is refused, because the
server would keep only the day. Every task JSON has `due_date` and `due_at`
(ISO 8601 with the Central offset, or null when there is no time).

Internal or external: a project is external for you when someone who can see
it, or will once invites are accepted, has an email domain other than yours
(on free mail such as gmail.com, everyone else counts). This is a guess from
email domains, not proof of who works where. `projects list` rows (without
`--user`, relative to you; with `--user`, still relative to you, not to that
person) and every
task's `project` carry `external` and `audience` (`members`, `pending`,
`outside`: counts only). On the member route the server refuses a task in an
external project (exit 1, `HTTP_422`, `audience` in the envelope) unless you
pass `--allow-external`. Use an internal project unless the user names an
external one. After any create or update in an external project, stderr says
`EXTERNAL: <project> is an external project: N people outside your email
domain can see this task.` The admin route (`--user`) is not checked, so it
takes no `--allow-external`; `tasks update` has none either, because it cannot
move a task through a checked route.

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
todos-cli tasks block 99 --reason "The Stripe login. It is not in 1Password."
todos-cli tasks unblock 99 --note "Added it to 1Password under Stripe."
```

Without `--user`, submit, reopen, cancel, approve, send-back, and star use the
authenticated user's own task routes. With `--user`, they use admin nested routes. Admin submit does not
accept response fields; update/respond while the task is open first. A reopen
note is available only on the admin nested route because it can notify the
client.

`tasks block` is for the assignee of an open to-do, when they cannot do it
without something from the person who asked. The to-do goes to their court
(status `blocked`; it is not canceled), with what is needed, and they get it
in their email batch (every to-do email waits up to 5 minutes and goes out
with the others). `--reason` is required, and there is no `--user` form. A
to-do you wrote for yourself can be blocked too: it waits in your own Your
move, with no email, until you unblock it. The reviewer and other members get
`HTTP_403`.

`tasks unblock` is for the person who asked: after they add what was needed
(with `tasks update`, or in `--note`), the to-do goes back to the assignee,
open. The note is posted as a comment on the to-do and goes in the assignee's email. The
task JSON has `blocked: {by, at, reason}` while it is blocked. Decline is gone;
past declines stay canceled, with `declined: {by, at, reason}`.

### Responses

```bash
todos-cli tasks respond 99 --field ein=12-3456789
todos-cli tasks respond 99 --user andy@example.com \
  --field ein=12-3456789 \
  --field legal_name="Example LLC"
```

Responses are writable only while a task is open. Without `--user`, the CLI
patches `/tasks/:id.json`; with it, the nested admin update route.

### Comments

```bash
todos-cli tasks comment 99 "Can you add the Tuesday batch?"
todos-cli tasks comment 99 @reply.md
todos-cli tasks comments 99
```

Notes are comments now (todo plan 23). Each to-do has a thread. The person
doing it, the person who asked, and the reviewer can comment in any status:
open, blocked, in review, done, or canceled. A comment never changes the
status. The text is markdown. `tasks comment` posts as you on the member route
(`POST /tasks/:id/comments.json`); there is no `--user`. `tasks comments` lists
the thread (`GET /my_tasks/:id.json`), and `tasks get` prints it on stderr
under the quality lines. A send back, a block reason, and an unblock note are
in the thread too, with `kind` `changes_requested`, `blocked`, or `unblocked`.

### Old text

```bash
todos-cli tasks versions 99
```

Each edit of a to-do's title, description, or fields keeps the old and the
new text (todo plan 26). `tasks versions` lists them newest first
(`GET /tasks/:id/versions.json`): `{id, created_at, by, changes}`, where
`changes` is `{"description": [old, new]}` for what that edit changed. Answers
and secrets are never kept there. Anyone who can open the to-do can read them.

`--notes` on `tasks update` and `tasks respond` still works for one release:
it posts a comment as you after the rest of the change, and prints
`--notes is now a comment. Use: todos-cli tasks comment <id> "text"` on stderr.

### Webhooks

```bash
todos-cli webhooks create --url https://example.com/todo-hook --events task.submitted,task.approved --description "my agent"
todos-cli webhooks list
todos-cli webhooks test 4
todos-cli webhooks deliveries 4
todos-cli webhooks update 4 --events "*" --active true
todos-cli webhooks rotate 4
todos-cli webhooks delete 4
```

todo.gxb.vc POSTs a signed event to your https URL a few seconds after a
change on a to-do you can open (todo plan 25), so an agent does not need to
poll. `create` and `rotate` print the secret once (`data.secret`); keep it.
Event types: `task.created`, `task.updated`, `task.submitted`,
`task.approved`, `task.reopened`, `task.canceled`, `task.blocked`,
`task.unblocked`, `task.logged`, `comment.created`, `comment.deleted`, or `*`
(all, the default). The payload is thin (the to-do id, title, status, and
link, and who made the change); read the rest with `tasks get`.

Check every request before you trust it. The header is
`X-Todo-Signature: t=<unix seconds>,v1=<hex HMAC-SHA256(secret, "<t>.<raw body>")>`:

```ruby
require "openssl"

def todo_webhook_valid?(secret, header, raw_body, now: Time.now.to_i)
  t, v1 = header.to_s.match(/\At=(\d+),v1=(\h{64})\z/)&.captures
  return false unless t && (now - t.to_i).abs <= 300

  expected = OpenSSL::HMAC.hexdigest("SHA256", secret, "#{t}.#{raw_body}")
  OpenSSL.fixed_length_secure_compare(expected, v1)
end
```

A failed delivery is tried again after 1 min, 5 min, 30 min, 2 h, 6 h, and
12 h. After 50 failed deliveries in a row the webhook is disabled;
`webhooks update <id> --active true` turns it on again. Only the owner sees a
webhook; any other id is `HTTP_404`. The URL must be `https://` and resolve to
a public address. todo.gxb.vc cannot reach a Mac on a home network: use a
public https URL (for example Tailscale Funnel or a server).

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
