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
- **Live sync.** Web, phone, and CLI share one server; open screens refresh themselves every 10 seconds and when you come back to them.
- **Readable errors.** Validation problems ("Due date cannot be in the past.") and connection problems are shown as plain sentences in every interface.

## How the four components fit together

```text
Web    (plan + calendar) ─┐
Mobile (today + add)     ├──> Planner service (core/planner_service.jac) ──> Jac persistent graph
CLI    (terminal)        ─┘      scheduling, validation, progress             Task, StudySession, ReservedBlock
```

The **server** is the single source of truth. `core/planner_service.jac` holds the data model (tasks, work blocks, reserved time), stores it in Jac's persistent graph, and does all the planning: placing work into free time, Reschedule, progress, and validation. The **web app**, **mobile app**, and **CLI** hold no planning logic of their own. Each one calls the same service functions (`add_task`, `complete_session`, `replan`, `get_calendar`, …) over HTTP and shows the result in a way that suits its screen:

- **Web** (`web/`): the full planning view. Calendar, task list, reserved time, and Reschedule.
- **Mobile** (`mobile/`): today's to-do list to check off on the go, a **+** button to add tasks with a date calendar and time dropdowns, Done, Reschedule, and reserved time. `mobile/api_base*.jac` points the phone at the server; `mobile/device*.jac` holds the phone-only pieces (foreground detection, pull-to-refresh, alerts).
- **CLI** (`cli/main.jac`): quick capture and checks from the terminal (`add`, `today`, `list`, `done`, `task-done`, `block`, `unblock`, `routine`, `replan`, `demo`).

Because all three talk to one server and one database, a change made anywhere is the same change everywhere. Open screens refresh themselves, so you see it within seconds (see [Staying in sync](#staying-in-sync)). Shared code keeps them consistent too: error messages come from `core/errors.jac`, so the web app, the phone, and the terminal say the same thing.

## What makes it stand out

- **It plans, not just lists.** You give a deadline and an estimate; StudyFlow finds the free time. It works around your classes and sleep, finishes before the due time, and spreads long tasks over the days before the deadline.
- **One planner, three screens, always in sync.** Add a task from the terminal and it appears on the web calendar and on your phone within about 10 seconds, without reloading anything.
- **A Reschedule button that knows when you need it.** The status card quietly simulates a Reschedule. It tells you exactly why one would help: you missed a block, blocks overlap, work isn't planned yet, or finishing early freed up time.
- **Every change explains itself.** Moved work says where it came from ("Rescheduled from Tue, Oct 6 · 9:30 AM and 2 other blocks"). Finishing a whole task removes its remaining blocks for good.
- **A calendar built for planning.** Each course has its own color and deadlines are drawn as a line. Busy hours stretch and reserved or empty hours shrink, so nothing overlaps. Tap any block for details, and hover a to-do to find it on the calendar.
- **Fits a real student week.** Reserved time can repeat on chosen weekdays (Mon/Wed/Fri) and can't overlap. Tasks can have due times and locations. The phone app finds the server on its own.

## Prerequisites

- Jac `0.37.23` (pinned in `jac.toml`)
- A modern browser
- For a native phone build: Expo-compatible Android/iOS tooling or Expo Go

```bash
jac --version
```

## How to run

All three interfaces use **one server**: the one `jac run` starts. Start it first, keep it running, and then use the web app, the CLI, and the phone app in any order. Run every command from the repository root.

| Interface | Where it runs | Start it with | Needs |
|---|---|---|---|
| Server + web app | your computer, in a browser | `jac run` | nothing else |
| CLI | a second terminal on the same computer | `jac run cli -- <command>` | `jac run` running, `JAC_APP_PLANNER_URL` set |
| Mobile app | a phone (Expo Go) on the same Wi-Fi | `jac run --dev mobile` (in a second terminal) | `jac run` running |

### 1. Server and web app

```bash
jac run
```

- Starts the planner service (scheduling, storage) and the web app together. Data is saved and survives restarts.
- Open the web address it prints, by default `http://localhost:8000`.
- The API address is printed too, by default `http://localhost:8001`. The CLI and phone app connect to it. If a port is busy, Jac picks another one. In that case use the printed values.
- `jac run --dev` does the same with hot reload, for development.

First time? In the web app, click **Load demo tasks** (Tasks panel) and **Use a typical student routine** (Reserved time).

### 2. CLI (terminal)

In a second terminal, tell the CLI where the server's API is (once per terminal):

```bash
export JAC_APP_PLANNER_URL=http://localhost:8001/api/planner
```

Then run commands as `jac run cli -- <command> [options]`:

| Command | What it does | Example |
|---|---|---|
| `today` | Shows today's blocks (with ids), the plan status, and your reserved time | `jac run cli -- today` |
| `list` | Shows every task with progress and due date (with ids) | `jac run cli -- list` |
| `add` | Adds a task and places its work into free time. Options: `--course`, `--due YYYY-MM-DD` (required), `--time HH:MM`, `--minutes`, `--priority high\|medium\|low`, `--location` | `jac run cli -- add "Quiz prep" --course "EECS 482" --due 2026-10-09 --time 09:30 --minutes 90 --location "Duderstadt Library"` |
| `done` | Checks off one block (id from `today`) | `jac run cli -- done BLOCK_ID` |
| `task-done` | Marks a whole task done and removes its remaining blocks, or reopens it (id from `list`) | `jac run cli -- task-done TASK_ID` |
| `block` | Adds recurring reserved time. Options: `--start`/`--end HH:MM` (required), `--repeat daily\|weekdays\|weekends\|mon,wed,fri`, `--category`, `--location` | `jac run cli -- block "EECS 482 lecture" --category class --start 10:30 --end 12:00 --repeat mon,wed,fri` |
| `unblock` | Removes reserved time (id from `today`) | `jac run cli -- unblock BLOCK_ID` |
| `replan` | Reschedule: re-plans all unfinished work from now | `jac run cli -- replan` |
| `routine` | Adds an example routine (classes, lunch, workout, sleep) when none exists | `jac run cli -- routine` |
| `demo` | Adds demo tasks when the planner is empty | `jac run cli -- demo` |

`jac run cli -- --help` and `jac run cli -- <command> --help` list every option. If the server cannot be reached, the CLI says so and shows the `export` line to use.

### 3. Mobile app (phone)

1. Keep `jac run` running.
2. In a second terminal:

   ```bash
   jac run --dev mobile
   ```

   The first run installs the mobile packages and takes a few minutes.
3. On a phone on the **same Wi-Fi** as the computer, install **Expo Go**. Scan the QR code the command prints (iPhone: camera app; Android: Expo Go), or type the printed `exp://<computer-ip>:8081` address into Expo Go.

On the phone you can:

- check and uncheck today's blocks;
- see the plan status and press **Reschedule**;
- mark tasks **Done**;
- add a task with the **+** button next to *Today*, which opens a form with a calendar for the due date;
- manage reserved time.

The app finds the server by itself: it uses the computer it was loaded from with API port `8001`. If it cannot connect, the screen shows the address it tried.

Notes:

- With Jac 0.37.23, `jac run --dev mobile` also tries an Android build and ends with an *Android SDK license* message. Metro and Expo Go keep working, so ignore it when testing with Expo Go. Accept the license only if you want an Android emulator or APK.
- If `jac run` printed an API port other than `8001`, change it in `mobile/api_base.native.jac`.

## Staying in sync

The web app, phone app, and CLI read and write the same data on the same server, so a change made in one shows up in the others without any extra steps:

| Where the change shows up | When |
|---|---|
| Web app | every 10 seconds while the page is open, and right away when you switch back to the tab |
| Phone app | every 10 seconds while the app is open, right away when you return to the app, and when you pull the screen down |
| CLI | every command reads the latest data |

Example: add a task with `jac run cli -- add …`. Within about 10 seconds it appears on the web calendar and in the phone app. Check off a block on the phone, and the web app shows it done shortly after.

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
3. `jac run cli -- add "Reading" --due <date> --minutes 60` (with `JAC_APP_PLANNER_URL` set): within about 10 seconds the new task appears on the web page, planned without moving anything else.
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
mobile/device*.jac         phone-only helpers: foreground detection, pull-to-refresh (native) / browser fallbacks
cli/main.jac               terminal commands
jac.toml                   four-app workspace configuration
docs/                      screenshot used above
```

## Notes

- The service uses public endpoints, so all interfaces share one planner graph. This fits a single-user personal planner.
- Dates use `YYYY-MM-DD`; times use 24-hour `HH:MM`.
