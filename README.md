# StudyFlow

> A to-do list that schedules itself: add tasks with a deadline and an estimate, and StudyFlow places the work into your free time around classes, sleep, and meals.

**Author:** Shea Shin<br>
**UMID:** 78273912

![StudyFlow web dashboard](docs/studyflow-dashboard.png)

StudyFlow is a four-component Jac application (server, web, mobile, CLI) built for CSE 449 Extra Credit Assignment 1. Every component talks to the same planner service and the same persisted graph, so a task added from the terminal shows up on the web calendar and can be checked off on the phone.

## Main features

- **Self-scheduling to-do list.** Each task has a due date (and optional due time), an estimate, a priority, a course, and an optional location. The scheduler splits the work into blocks between now and the deadline, finishing before the due time.
- **Reserved time.** Recurring commitments (class, sleep, meals, work) on any set of weekdays (e.g. Mon/Wed/Fri). Work is never placed there, and reserved times cannot overlap each other.
- **Today checklist.** Check a block off (or undo it). Progress, missed blocks, locations, and "Rescheduled from …" history are shown inline.
- **Stable plan + Reschedule.** Checking things off never reshuffles your day. A status card tells you when a Reschedule would help (missed or overlapping blocks, work that is not planned yet, or free time that opened up) and Reschedule re-plans only unfinished work from the current time.
- **Calendar.** Day / Week / Month views with per-task colors (same course, same color), a deadline line, and a time axis that stretches busy hours and shrinks reserved or empty ones. Hover or tap any block for a detail bubble; hovering a Today item highlights its block.
- **Tasks list.** Open / Done tabs, sorted by priority then due date, with Done, Reopen, edit, and delete.
- **Readable errors.** Validation problems ("Due date cannot be in the past.") and connection problems are shown as plain sentences in every interface.

## Components

```text
Web  (planning + calendar) ─┐
Mobile (today + quick add) ├──> Planner service (core/planner_service.jac) ──> Jac persistent graph
CLI  (terminal capture)    ─┘      scheduling, validation, progress             Task, StudySession, ReservedBlock
```

- **Server** (`core/planner_service.jac`): the data model, validation, the scheduler (incremental placement, full Reschedule, and a dry-run used for the status card), calendar layout, and tests. Shared error wording lives in `core/errors.jac`.
- **Web** (`web/`): the full planning interface described above.
- **Mobile** (`mobile/main.jac`, `mobile/api_base*.jac`): today's to-do list with check/uncheck, the reschedule status and button, open tasks with Done, quick add (with due time and location), and reserved-time management.
- **CLI** (`cli/main.jac`): `add`, `today`, `list`, `done`, `task-done`, `block`, `unblock`, `routine`, `replan`, and `demo`.

## What makes it stand out

- **It plans, not just lists.** Work is placed into real free time, respecting due times, reserved time, the current time, and priority.
- **Predictable.** The plan only moves when you ask. Every moved block says where it came from, and the status card explains why a Reschedule is suggested. The suggestion comes from simulating the Reschedule without saving it.
- **One system, three interfaces.** Web, mobile, and CLI share the same service, data, validation, and error messages.
- **Tested.** 37 automated tests cover scheduling, deadlines and due times, reserved-time overlap, check/uncheck/Done/Reopen, move history, calendar layout, and error handling.

## Prerequisites

- Jac `0.37.23` (pinned in `jac.toml`)
- A modern browser
- For a native phone build: Expo-compatible Android/iOS tooling or Expo Go

```bash
jac --version
```

## Run the web app and server

From the repository root:

```bash
jac run
```

This serves the web app and the planner service together and keeps data between runs. Open the web URL that Jac prints (by default `http://localhost:8000`; the API is printed too, by default `http://localhost:8001`). If those ports are busy, Jac picks others, so use the printed values.

For hot reload while developing: `jac run --dev`.

New here? Click **Load demo tasks** in the Tasks panel and **Use a typical student routine** under Reserved time.

## Use the CLI

Keep `jac run` running. In another terminal, point the CLI at the planner service (use the API port `jac run` printed):

```bash
export JAC_APP_PLANNER_URL=http://localhost:8001/api/planner
```

Then:

```bash
jac run cli -- today
jac run cli -- list
jac run cli -- add "Finish CSE 449 project" --course "CSE 449" --due 2026-10-09 --minutes 240 --priority high
jac run cli -- add "Quiz prep" --course "EECS 482" --due 2026-10-07 --time 09:30 --minutes 90 --location "Duderstadt Library"
jac run cli -- done BLOCK_ID          # check off one block (ids are shown by `today`)
jac run cli -- task-done TASK_ID      # mark a whole task done, or reopen it
jac run cli -- block "Sleep" --category sleep --start 23:00 --end 08:00 --repeat daily
jac run cli -- block "EECS 482 lecture" --category class --start 10:30 --end 12:00 --repeat mon,wed,fri --location "1670 Beyster"
jac run cli -- routine
jac run cli -- replan                 # Reschedule
```

`jac run cli -- --help` and `jac run cli -- COMMAND --help` list every option. If the server is not reachable, the CLI says so and shows how to set `JAC_APP_PLANNER_URL`.

## Run the mobile app

The mobile app talks to the same server as the web app and CLI, so start that first.

1. Keep `jac run` running (web app + planner service, API on port `8001`).
2. In a second terminal, start the mobile app:

   ```bash
   jac run --dev mobile
   ```

3. On a phone on the same Wi-Fi as the computer, install **Expo Go** and scan the QR code (or enter the printed `exp://<computer-ip>:8081` URL in Expo Go).

The app finds the server by itself: it uses the computer it was loaded from, with API port `8001`. The screen shows the server address if it cannot connect.

Notes:

- With Jac 0.37.23, `jac run --dev mobile` also tries an Android build and stops with an *Android SDK license* message. Metro and Expo Go keep working, so you can ignore it for Expo Go testing. Accept the license only if you want an Android emulator or APK.
- If `jac run` printed a different API port than `8001`, change it in `mobile/api_base.native.jac`.
- `jac run --dev --platform web mobile` previews the mobile screens in a browser. Do not run it at the same time as the web dev server, because the two share Jac's build folder.

## Scheduling behavior

StudyFlow keeps a **stable plan**: blocks only move when you ask them to.

| Action | What happens to the plan |
|---|---|
| Add a task | Its work is placed into free time between now and the deadline. Existing blocks stay put. |
| Edit a task | Only that task's unfinished blocks are planned again. |
| Check a block | Only that block is marked done (its minutes count toward the task). Nothing else moves, and the calendar hides it. |
| Uncheck a block | The block returns to its original spot. If that spot has been taken since, it moves to the next free time instead of overlapping. |
| **Done** on a task | The whole task is finished; its remaining blocks are removed and never come back. **Reopen** plans the rest again (or asks how much more time you need). |
| Add reserved time | Only blocks that overlap it are moved. Reserved times may not overlap each other. |
| Remove reserved time | Nothing moves; the status card suggests a Reschedule to use the freed time. |
| **Reschedule** | Every unfinished block is cleared and all remaining work is placed again from now on. A block in progress right now stays. Moved blocks show "Rescheduled from …". |

When placing work, the scheduler:

1. uses any time of day that is not reserved, starting from the current time;
2. orders tasks by deadline (date, then due time) and then priority;
3. spreads each task across the days before its deadline and finishes before its due time;
4. keeps one task in as few blocks as possible (at least 30 minutes each when the work allows); and
5. reports any work that cannot fit before its deadline.

The algorithm is deterministic: the same task state produces the same plan.

## Demo workflow

1. `jac run`, open the web URL, click **Load demo tasks** and **Use a typical student routine**.
2. Look at the Week calendar: work sits between classes, lunch, and sleep, colored by course.
3. `jac run cli -- add "Reading" --due <date> --minutes 60` (with `JAC_APP_PLANNER_URL` set) and refresh the web page: the new task is planned without moving anything else.
4. Check off today's first block early. The status card says **Free time opened up**. Press **Reschedule** and later work moves up, each moved block saying where it came from.
5. Run `jac run cli -- today` to see the same plan in the terminal.

## Validation

```bash
jac check     # type-check the server, web, mobile, and CLI apps
jac test      # run the scheduler, validation, and error-message tests
```

## Project layout

```text
core/planner_service.jac   data model, API, scheduler, calendar layout, tests
core/errors.jac            readable error messages shared by web, mobile, and CLI (+ errors.test.jac)
web/main.jac               web planning interface
web/styles.css             web styles
mobile/main.jac            mobile app (@jac/mobui)
mobile/api_base*.jac       points the phone app at the `jac run` server (native) / no-op (browser)
cli/main.jac               terminal commands
jac.toml                   four-app workspace configuration
docs/                      screenshot used above
```

## Notes

- The service uses public endpoints, so all interfaces share one planner graph. This fits a single-user personal planner.
- Dates use `YYYY-MM-DD`; times use 24-hour `HH:MM`.
