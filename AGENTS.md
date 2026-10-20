# todos-cli

CRUD todo.gxb.vc boards and tasks with a user or admin API key.
Output is always one JSON line: `{"ok":true,"data":...}` or `{"ok":false,"error":"...","code":"..."}`.

## Commands

```bash
todos-cli me
todos-cli users list
todos-cli users show <id|email>
todos-cli users remind <id|email>
todos-cli board [--user <id|email>]
todos-cli logbook [--kind logged|canceled] [--before DATE | --all]
todos-cli areas list --user <id|email>
todos-cli areas create --user <id|email> -t TITLE [--position N] [--active true|false]
todos-cli areas invite <id> --email EMAIL
todos-cli projects list [--user <id|email>]
todos-cli projects create --user <id|email> -t TITLE [--area ID] [--status active|waiting|someday|completed] [--position N]
todos-cli projects create -t TITLE [--area ID]
todos-cli projects invite <id> --email EMAIL
todos-cli invites list
todos-cli invites accept <id> [--area ID]
todos-cli contexts
todos-cli tasks list [--user <id|email>] [--project ID] [--status open|submitted|approved|canceled] [--context NAME,NAME] [--sort priority]
todos-cli tasks get|show <id> [--user <id|email>]
todos-cli tasks check -t TITLE [--description MARKDOWN|@file] [--schema JSON|@file]
todos-cli tasks create -t TITLE --project ID [--assignee EMAIL] [--description MARKDOWN|@file] [--due DATE] [--due-time HH:MM] [--context NAME,NAME] [--schema JSON|@file] [--star]
todos-cli tasks create --user <id|email> -t TITLE [--project ID] [--description MARKDOWN|@file] [--due DATE] [--due-time HH:MM] [--estimate N] [--source-url URL] [--context NAME,NAME] [--schema JSON|@file] [--star]
todos-cli tasks update <id> --user <id|email> [--title TITLE] [--project ID] [--description MARKDOWN|@file] [--due DATE] [--due-time HH:MM] [--estimate N] [--source-url URL] [--context NAME,NAME] [--schema JSON|@file] [--field key=value]
todos-cli tasks destroy <id> --user <id|email>
todos-cli tasks approve <id> [--user <id|email>]
todos-cli tasks send-back <id> --note TEXT
todos-cli tasks star <id> [--off] [--user <id|email>]
todos-cli tasks submit <id> [--user <id|email>] [--field key=value]
todos-cli tasks reopen <id> [--user <id|email>] [--note TEXT]
todos-cli tasks cancel <id> [--user <id|email>]
todos-cli tasks block <id> --reason TEXT
todos-cli tasks unblock <id> [--note TEXT]
todos-cli tasks remind <id> --user <id|email>
todos-cli tasks respond <id> [--user <id|email>] --field key=value [--field key=value]
# checkboxes: --field picks='["A","B"]'  or  --field picks=A --field picks=B
todos-cli tasks comment <id> ["TEXT"|@file.md] [--file PATH ...]
todos-cli tasks comments <id>
todos-cli tasks versions <id>
todos-cli tasks email <id> [--json]
todos-cli events [--after ID] [--limit N]
todos-cli webhooks list
todos-cli webhooks create --url URL [--events TYPE,TYPE|*] [--description TEXT]
todos-cli webhooks update <id> [--url URL] [--events TYPE,TYPE|*] [--description TEXT] [--active true|false]
todos-cli webhooks delete|rotate|test|deliveries <id>
```

`events` is one read of every change after `--after` (`GET /events.json?after_id=N&limit=200`, max 500), oldest first, on to-dos the key's owner can open (the admin too: no wider). It prints the whole reply `{events, next_after_id, more}`; pass `next_after_id` as the next `--after`, and call again at once while `more` is true. Each event: `type` (the webhook type), `kind`, `at`, `actor`, `via` (`web`, `api`, `oauth`, `system`, or null), `via_key` (the key's name, only on the caller's own changes), `from_status`, `to_status`, `data` (webhook keys only), `task {id, title, status, project_id, project_title, user_id, assigner_id, url}`.

`tasks remind` re-sends mail for one open to-do; `users remind` sends one email covering everything open on that user's board. Both are a re-send, not a new assignment — they never touch a to-do's assigned/pending state, so they cannot suppress a later real assignment email. Admin key required for both.

## Write next actions

Every task must be a next physical action. Rules and examples: `write-human-todos` skill.

The server scores every task on 7 checks (Jev). `tasks create`, `tasks get`/`show`, and `tasks check` print the score and each check on stderr, with the hint for each fail. The JSON has the whole `quality` object. Run `tasks check` on a draft first. While the gate is on, a task for someone else that fails a blocking check is refused: exit 1, `code` `HTTP_422`, the failed checks on stderr, and `quality` in the envelope. There is no flag that skips the check.

Email to-dos (todo plan 44): when the action is "send this email", use the email type, never a description draft. `tasks create`/`tasks update` take `--email-to` (required), `--email-subject` (required), `--email-cc`, `--email-bcc`, `--email-body` (plain text, or `@file.txt` — no markdown), and `--email-from` (a hint about which address to send from). The to-do carries exactly one email the person sends from their own mail client; the app never sends it. Every email to-do gets a built-in required radio `email_outcome` (Sent / Not a fit / Skip) Done waits for; do not add your own outcome field. The card shows Open in Outlook, Open in Gmail, and Copy buttons, and the person can edit the draft. Read what they changed with `tasks email <id>` (unified diff, the agent's draft against what they send now) or `--json` (the whole reply: email, original, revisions with who, when, via). The email text never reaches quality scoring, search, events, webhooks, or mail.

## Route rules

- `--user` selects admin cross-user routes; email lookup via `users list` requires an admin key.
- `tasks create` without `--user` is the member route (`POST /tasks.json`): a task in one of my projects, for me or for `--assignee EMAIL` (an active member of that project, or someone I invited to it or its area who has not joined yet: the task waits, `data.assignee` is null, `data.waiting_for_invite.id` names the invite, and it lands on them when they accept). `--project` is required on this route, so a forgotten `--user` fails. `--estimate` and `--source-url` need `--user`.
- Internal or external: `projects list` rows (without `--user`: my own projects, `GET /projects.json`) and each task's `project` carry `external` (someone outside my email domain can see it, or will once invites are accepted) and `audience` counts. Use an internal project unless the user names an external one. Only then pass `--allow-external` on the member `tasks create`; without it the server refuses (exit 1, `HTTP_422`). Writes in an external project print an `EXTERNAL:` line on stderr. The admin route (`--user`) is not checked and takes no flag.
- `projects create` without `--user` is the member route (`POST /projects.json`): a project I own, in one of my own areas. It prints "No --user: making the project in your own board." on stderr, so a forgotten `--user` is seen. `projects invite <id> --email EMAIL` is the owner's invite (`POST /projects/:id/invites.json`); `data.status` is `added` (a colleague at my own work email domain with an account joined at once, no link), `invited`, or `already_member`; a refusal exits 1 with the server's reason.
- `areas invite <id> --email EMAIL` shares a whole area I own (`POST /areas/:id/invites.json`): every project I own in it, now and later, never projects others shared with me that I filed there. Same reply and refusals as `projects invite`.
- `invites list` shows the project and area invites sent to my own account email (`GET /invites.json`). `invites accept <id> [--area ID]` joins one (`POST /invites/:id/accept.json`, id like `project-4` or `area-2`), filed in one of my areas, else my Shared area (project) or a new area named after it (area). Any invite I cannot accept is `HTTP_404`. Only accept an invite the user asked you to. An invited project is not on my board until I accept, so `board` and `tasks list` print `You have N open invites. Run: todos-cli invites list` on stderr when there are any.
- Update and destroy require `--user`.
- Description: `--description` is markdown, the one format todo stores (`@card.md` reads a file). Text the person must copy (a prompt, an email body, a command) goes in a fenced code block, indented under its numbered step; the card shows a Copy button. A short value goes in `inline code`, which copies on tap. Field types for `--schema`: `todos-cli help`. `recording` is a screen and voice recording: only the assignee records it, and Scribe transcribes it. A text answer cannot hold files: when the person may want to show a screenshot or PDF, add a `file` field next to the question (label like `Screenshots (optional)`); they can also attach files to a comment (`tasks comment <id> "text" --file PATH`). `tasks get` returns it as `data.description`: read that for the card text, links and file locations included. `description_html` is deprecated (one release), and HTML passed to `--description` still works for that release (the server converts it).
- My board (`board` and `tasks list` without `--user`) leaves canceled to-dos off. They are in my logbook: `logbook` lists what left my board, newest first (`kind` logged with `logged_at`, or canceled with `canceled_at` and `declined`), and `tasks list --status canceled` without `--user` reads the canceled ones from there (every week). `logbook` is one week (the 7 days before `--before DATE`, default up to today); stderr names the `--before` for the week before, and `--all` reads every week. With `--user`, the admin board still has every status.
- Due: `--due YYYY-MM-DD` is the day; `--due-time HH:MM` is a time in 24-hour Central time (America/Chicago). On create, `--due-time` needs `--due`. On update it can come alone, a new `--due` keeps the time, `--due-time ""` clears the time, and `--due ""` clears both. Never put a time in `--due` (refused). Task JSON has `due_at` (ISO 8601, Central offset) or null.
- Plan day: `--do-on DATE` (and `tasks plan --do-on`) puts a to-do in Today on that day. Set it only when the person chose that day (they said "I will do it Friday"). Never set it to today to get their attention: Today then fills with to-dos nobody planned (plan 26 found 45 of 48). For a real deadline use `--due`; for importance use `--priority`.
- Contexts (todo plan 42): `--context NAME` (repeat it, or a comma list) on `tasks create` and `tasks update` tags the to-do with a GTD context of mine — where, or with what, it gets done. On update it REPLACES my set; `--context ""` clears it. Contexts are personal: only I see them; task rows carry `contexts` (my names). `todos-cli contexts` lists mine (name, description, position); they are made on /settings. Set one when where or with what the person must be is clear: desk with the big screen and security key: `office`; a phone tap: `phone`; a voice-only answer on a ride: `bike`. An unknown name is `HTTP_422` (no auto-create, so a typo never makes a new one). `tasks list --context office,bike` keeps only rows carrying any of those names.
- `tasks list --sort priority` (todo plan 43) sorts the flat list: urgent, high, normal, low, then due date (none last; a due time breaks ties within a day), then position, then id. Sorted locally: the board tree is per project and the list spans projects.
- `approve` and `star` use my own route without `--user` (I am the reviewer, or for `star` the assignee) and the admin route with it. `send-back` is the reviewer's route only; the admin equivalent is `reopen --user --note`.
- Submit uses the admin route with `--user`, otherwise self; `reopen --note` requires `--user`.
- Blocked: `block <id> --reason TEXT` is the assignee's route only (`PATCH /tasks/:id/block.json`): when I cannot do an open to-do someone else gave me without something from them, it goes to their court (status `blocked`, never canceled) with what I need, and they get it in their email batch. `--reason` is required; there is no `--user`; on a to-do I wrote for myself, use `cancel` (`HTTP_422`). `unblock <id> [--note TEXT]` is the asker's (`PATCH /tasks/:id/unblock.json`): after they add what was needed (an `update`, or the note), it goes back to the assignee, open; the note is posted as a comment and goes in the assignee's email. `--status blocked` filters `tasks list`. Decline is gone.

- Comments (todo plan 23: notes are comments): `tasks comment <id> "TEXT"` (markdown, or `@file.md`) posts as me on the member route (`POST /tasks/:id/comments.json`); there is no `--user`. The assignee, the asker, and the reviewer may post in any status, and a comment never changes the status; anyone else on the project gets `HTTP_403`. `tasks comments <id>` lists the thread (`GET /my_tasks/:id.json`); `tasks get` prints it on stderr. `--file PATH` (repeatable, todo plan 32) attaches files: up to 10, 25 MB each, any type; with files the text may be left out. Comment JSON has `files: [{id, filename, content_type, byte_size, url}]` (url is the checked route). Talk about an existing to-do with a comment, not a new to-do. `--notes` on `update` and `respond` is deprecated (one release): it posts a comment and says so on stderr.

- No-sign-in links (todo plan 36): `tasks link <id> [--days N]` (`POST /tasks/:id/links.json`) makes a link for the current assignee, who opens one card, answers it, uploads files, and presses Done with no account. `data.url` (`https://todo.gxb.vc/l#TOKEN`) holds the secret and is in that reply only, so copy it at once; send it only to the assignee, in a message Christian approved. `--days` is 1 to 30 (14 when left out). `tasks links <id>` lists them without secrets, `tasks unlink <id> <link_id>` ends one, `tasks link-expire <id> <link_id> --at DATE` moves its end (30 days from now at most). Only the asker (reviewer) or the admin: the assignee gets `HTTP_403`, someone who cannot open the to-do `HTTP_404`. A reassign ends the open links. Never put a link in a log, ticket, or any place the assignee should not read. Writes through a link say `via: "link"` in events and `answer_sources`.

- Webhooks (todo plan 25): `webhooks create --url https://... [--events task.submitted,task.approved]` makes one of my own (`POST /webhooks.json`); todo.gxb.vc then POSTs a signed event there seconds after a change on a to-do I can open, so an agent does not poll. `create` and `rotate` print `data.secret` once (stderr says so). `test` queues a `ping`; `deliveries` shows the last 50 (status, code, error). `update --active true` turns on one that was disabled after 50 failed deliveries. Only my own webhooks: any other id is `HTTP_404`. Events, payload, and the signature check: README Webhooks. The URL must be public https: todo.gxb.vc cannot reach this Mac.

Requires a tool-local `.env` with `TODOS_API_KEY` and `TODOS_BASE_URL`; mint keys in todo.gxb.vc Settings, not via this CLI.

The skill in `skills/write-human-todos/SKILL.md` is also served by chat as the MCP resource `gxb://todos/write-human-todos`. After editing it, copy it to `~/projects/chat/app/views/mcp/skills/write_human_todos.md` (chat's `Mcp::ResourcesTest` checks that the two match). `~/.pi/agent/skills/write-human-todos` is a symlink to this folder.
