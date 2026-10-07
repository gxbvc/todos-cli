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
todos-cli tasks list [--user <id|email>] [--project ID] [--status open|submitted|approved|canceled]
todos-cli tasks get|show <id> [--user <id|email>]
todos-cli tasks check -t TITLE [--description MARKDOWN|@file] [--schema JSON|@file]
todos-cli tasks create -t TITLE --project ID [--assignee EMAIL] [--description MARKDOWN|@file] [--due DATE] [--due-time HH:MM] [--schema JSON|@file] [--star]
todos-cli tasks create --user <id|email> -t TITLE [--project ID] [--description MARKDOWN|@file] [--due DATE] [--due-time HH:MM] [--estimate N] [--source-url URL] [--schema JSON|@file] [--star]
todos-cli tasks update <id> --user <id|email> [--title TITLE] [--project ID] [--description MARKDOWN|@file] [--due DATE] [--due-time HH:MM] [--estimate N] [--source-url URL] [--schema JSON|@file] [--field key=value]
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
todos-cli tasks comment <id> "TEXT"|@file.md
todos-cli tasks comments <id>
todos-cli tasks versions <id>
todos-cli webhooks list
todos-cli webhooks create --url URL [--events TYPE,TYPE|*] [--description TEXT]
todos-cli webhooks update <id> [--url URL] [--events TYPE,TYPE|*] [--description TEXT] [--active true|false]
todos-cli webhooks delete|rotate|test|deliveries <id>
```

`tasks remind` re-sends mail for one open to-do; `users remind` sends one email covering everything open on that user's board. Both are a re-send, not a new assignment — they never touch a to-do's assigned/pending state, so they cannot suppress a later real assignment email. Admin key required for both.

## Write next actions

Every task must be a next physical action. Rules and examples: `write-human-todos` skill.

The server scores every task on 7 checks (Jev). `tasks create`, `tasks get`/`show`, and `tasks check` print the score and each check on stderr, with the hint for each fail. The JSON has the whole `quality` object. Run `tasks check` on a draft first. While the gate is on, a task for someone else that fails a blocking check is refused: exit 1, `code` `HTTP_422`, the failed checks on stderr, and `quality` in the envelope. There is no flag that skips the check.

## Route rules

- `--user` selects admin cross-user routes; email lookup via `users list` requires an admin key.
- `tasks create` without `--user` is the member route (`POST /tasks.json`): a task in one of my projects, for me or for `--assignee EMAIL` (an active member of that project, or someone I invited to it or its area who has not joined yet: the task waits, `data.assignee` is null, `data.waiting_for_invite.id` names the invite, and it lands on them when they accept). `--project` is required on this route, so a forgotten `--user` fails. `--estimate` and `--source-url` need `--user`.
- Internal or external: `projects list` rows (without `--user`: my own projects, `GET /projects.json`) and each task's `project` carry `external` (someone outside my email domain can see it, or will once invites are accepted) and `audience` counts. Use an internal project unless the user names an external one. Only then pass `--allow-external` on the member `tasks create`; without it the server refuses (exit 1, `HTTP_422`). Writes in an external project print an `EXTERNAL:` line on stderr. The admin route (`--user`) is not checked and takes no flag.
- `projects create` without `--user` is the member route (`POST /projects.json`): a project I own, in one of my own areas. It prints "No --user: making the project in your own board." on stderr, so a forgotten `--user` is seen. `projects invite <id> --email EMAIL` is the owner's invite (`POST /projects/:id/invites.json`); `data.status` is `added` (a colleague at my own work email domain with an account joined at once, no link), `invited`, or `already_member`; a refusal exits 1 with the server's reason.
- `areas invite <id> --email EMAIL` shares a whole area I own (`POST /areas/:id/invites.json`): every project I own in it, now and later, never projects others shared with me that I filed there. Same reply and refusals as `projects invite`.
- `invites list` shows the project and area invites sent to my own account email (`GET /invites.json`). `invites accept <id> [--area ID]` joins one (`POST /invites/:id/accept.json`, id like `project-4` or `area-2`), filed in one of my areas, else my Shared area (project) or a new area named after it (area). Any invite I cannot accept is `HTTP_404`. Only accept an invite the user asked you to. An invited project is not on my board until I accept, so `board` and `tasks list` print `You have N open invites. Run: todos-cli invites list` on stderr when there are any.
- Update and destroy require `--user`.
- Description: `--description` is markdown, the one format todo stores (`@card.md` reads a file). Text the person must copy (a prompt, an email body, a command) goes in a fenced code block, indented under its numbered step; the card shows a Copy button. A short value goes in `inline code`, which copies on tap. Field types for `--schema`: `todos-cli help`. `tasks get` returns it as `data.description`: read that for the card text, links and file locations included. `description_html` is deprecated (one release), and HTML passed to `--description` still works for that release (the server converts it).
- My board (`board` and `tasks list` without `--user`) leaves canceled to-dos off. They are in my logbook: `logbook` lists what left my board, newest first (`kind` logged with `logged_at`, or canceled with `canceled_at` and `declined`), and `tasks list --status canceled` without `--user` reads the canceled ones from there (every week). `logbook` is one week (the 7 days before `--before DATE`, default up to today); stderr names the `--before` for the week before, and `--all` reads every week. With `--user`, the admin board still has every status.
- Due: `--due YYYY-MM-DD` is the day; `--due-time HH:MM` is a time in 24-hour Central time (America/Chicago). On create, `--due-time` needs `--due`. On update it can come alone, a new `--due` keeps the time, `--due-time ""` clears the time, and `--due ""` clears both. Never put a time in `--due` (refused). Task JSON has `due_at` (ISO 8601, Central offset) or null.
- Plan day: `--do-on DATE` (and `tasks plan --do-on`) puts a to-do in Today on that day. Set it only when the person chose that day (they said "I will do it Friday"). Never set it to today to get their attention: Today then fills with to-dos nobody planned (plan 26 found 45 of 48). For a real deadline use `--due`; for importance use `--priority`.
- `approve` and `star` use my own route without `--user` (I am the reviewer, or for `star` the assignee) and the admin route with it. `send-back` is the reviewer's route only; the admin equivalent is `reopen --user --note`.
- Submit uses the admin route with `--user`, otherwise self; `reopen --note` requires `--user`.
- Blocked: `block <id> --reason TEXT` is the assignee's route only (`PATCH /tasks/:id/block.json`): when I cannot do an open to-do someone else gave me without something from them, it goes to their court (status `blocked`, never canceled) with what I need, and they get it in their email batch. `--reason` is required; there is no `--user`; on a to-do I wrote for myself, use `cancel` (`HTTP_422`). `unblock <id> [--note TEXT]` is the asker's (`PATCH /tasks/:id/unblock.json`): after they add what was needed (an `update`, or the note), it goes back to the assignee, open; the note is posted as a comment and goes in the assignee's email. `--status blocked` filters `tasks list`. Decline is gone.

- Comments (todo plan 23: notes are comments): `tasks comment <id> "TEXT"` (markdown, or `@file.md`) posts as me on the member route (`POST /tasks/:id/comments.json`); there is no `--user`. The assignee, the asker, and the reviewer may post in any status, and a comment never changes the status; anyone else on the project gets `HTTP_403`. `tasks comments <id>` lists the thread (`GET /my_tasks/:id.json`); `tasks get` prints it on stderr. Talk about an existing to-do with a comment, not a new to-do. `--notes` on `update` and `respond` is deprecated (one release): it posts a comment and says so on stderr.

- Webhooks (todo plan 25): `webhooks create --url https://... [--events task.submitted,task.approved]` makes one of my own (`POST /webhooks.json`); todo.gxb.vc then POSTs a signed event there seconds after a change on a to-do I can open, so an agent does not poll. `create` and `rotate` print `data.secret` once (stderr says so). `test` queues a `ping`; `deliveries` shows the last 50 (status, code, error). `update --active true` turns on one that was disabled after 50 failed deliveries. Only my own webhooks: any other id is `HTTP_404`. Events, payload, and the signature check: README Webhooks. The URL must be public https: todo.gxb.vc cannot reach this Mac.

Requires a tool-local `.env` with `TODOS_API_KEY` and `TODOS_BASE_URL`; mint keys in todo.gxb.vc Settings, not via this CLI.

The skill in `skills/write-human-todos/SKILL.md` is also served by chat as the MCP resource `gxb://todos/write-human-todos`. After editing it, copy it to `~/projects/chat/app/views/mcp/skills/write_human_todos.md` (chat's `Mcp::ResourcesTest` checks that the two match). `~/.pi/agent/skills/write-human-todos` is a symlink to this folder.
