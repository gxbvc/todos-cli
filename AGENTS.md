# todos-cli

CRUD todo.gxb.vc boards and tasks with a user or admin API key. Output is always
one JSON line: `{"ok":true,"data":...}` or
`{"ok":false,"error":"...","code":"..."}`.

## Commands

```bash
todos-cli me
todos-cli users list
todos-cli users show <id|email>

todos-cli board [--user <id|email>]
todos-cli projects list --user <id|email>

todos-cli tasks list [--user <id|email>] [--project ID] [--status open|submitted|approved|canceled]
todos-cli tasks get <id> [--user <id|email>]
todos-cli tasks create --user <id|email> -t TITLE [--project ID] [--description HTML] [--due DATE] [--schema JSON|@file]
todos-cli tasks update <id> --user <id|email> [--title TITLE] [--project ID] [--description HTML] [--due DATE] [--schema JSON|@file] [--field key=value] [--notes TEXT]
todos-cli tasks destroy <id> --user <id|email>
todos-cli tasks approve <id> --user <id|email>
todos-cli tasks submit <id> [--user <id|email>] [--field key=value]
todos-cli tasks reopen <id> [--user <id|email>] [--note TEXT]
todos-cli tasks cancel <id> [--user <id|email>]
todos-cli tasks respond <id> [--user <id|email>] --field key=value [--field key=value] [--notes TEXT]
```

`--user` switches board reads and supported mutations to the admin cross-user
routes. Email references are resolved through `users list`, so they require an
admin key. Create, update, destroy, and approve always require `--user`.
`tasks submit` with `--user` is the admin route; without it, the self route.
`tasks reopen --note` requires `--user` because self reopen is silent.

## Examples

```bash
todos-cli users list
todos-cli board --user andy@andysibley.com
todos-cli tasks create --user andy@andysibley.com -t "Send W-9" --project 7
todos-cli tasks respond 99 --field ein=12-3456789 --notes "Ready for review"
todos-cli tasks submit 99
todos-cli tasks approve 99 --user andy@andysibley.com
todos-cli tasks reopen 99 --user andy@andysibley.com --note "Need clearer scan"
```

Requires a tool-local `.env` containing `TODOS_API_KEY` and `TODOS_BASE_URL`.
Keys are minted in the todo.gxb.vc Settings UI, never through this CLI. See
`.env.example`.
