import argparse;
import asyncio;
import sys;
import from jaclang.server.bridge { BridgeError }
import from core.planner_service {
    DashboardData,
    SessionView,
    TaskView,
    add_reserved_block,
    add_task,
    complete_session,
    delete_reserved_block,
    get_dashboard,
    replan,
    save_planning_window,
    seed_demo,
    seed_routine,
    toggle_task
}

glob PROG: str = "studyflow";

obj Invocation {
    has command: str = "", title: str = "", course: str = "General",
        due: str = "", minutes: int = 60, priority: str = "medium",
        item_id: str = "", start_hour: int = 8, end_hour: int = 23,
        label: str = "", category: str = "other", start_time: str = "",
        end_time: str = "", repeat_rule: str = "daily";
}

def parser -> argparse.ArgumentParser {
    root_parser = argparse.ArgumentParser(
        prog=PROG,
        description="Plan coursework from the terminal using the shared StudyFlow server."
    );
    commands = root_parser.add_subparsers(dest="command", required=True);
    commands.add_parser("today", help="show today's planned work blocks");
    commands.add_parser("list", help="show all assignments");
    commands.add_parser("replan", help="redistribute unfinished work");
    commands.add_parser("demo", help="add a sample week when the planner is empty");
    commands.add_parser("routine", help="add example reserved-time routines");

    add = commands.add_parser("add", help="add and automatically schedule an assignment");
    add.add_argument("title", help="assignment title");
    add.add_argument("--course", `default="General", help="course name");
    add.add_argument("--due", required=True, help="due date (YYYY-MM-DD)");
    add.add_argument("--minutes", `type=int, `default=60, help="estimated work in minutes");
    add.add_argument(
        "--priority", choices=["high", "medium", "low"], `default="medium"
    );

    done = commands.add_parser("done", help="complete a work block by id");
    done.add_argument("item_id", help="session id shown by `today`");
    task_done = commands.add_parser("task-done", help="toggle an assignment by id");
    task_done.add_argument("item_id", help="task id shown by `list`");

    settings = commands.add_parser("settings", help="set the daily planning window");
    settings.add_argument("--start", dest="start_hour", `type=int, `default=8);
    settings.add_argument("--end", dest="end_hour", `type=int, `default=23);

    block = commands.add_parser("block", help="reserve recurring time so no work is planned there");
    block.add_argument("label", help="name such as Sleep or Class");
    block.add_argument("--category", choices=["sleep", "meal", "class", "exercise", "commute", "other"], `default="other");
    block.add_argument("--start", dest="start_time", required=True, help="start time (HH:MM)");
    block.add_argument("--end", dest="end_time", required=True, help="end time (HH:MM)");
    block.add_argument("--repeat", dest="repeat_rule", `default="daily", help="daily, weekdays, weekends, or days like mon,wed,fri");

    unblock = commands.add_parser("unblock", help="remove reserved time by id");
    unblock.add_argument("item_id", help="reserved-time id shown by `today`");
    return root_parser;
}

def parse_args(argv: list[str]) -> Invocation {
    ns = parser().parse_args(argv);
    return Invocation(
        command=str(getattr(ns, "command", "")),
        title=str(getattr(ns, "title", "")),
        course=str(getattr(ns, "course", "General")),
        due=str(getattr(ns, "due", "")),
        minutes=int(getattr(ns, "minutes", 60)),
        priority=str(getattr(ns, "priority", "medium")),
        item_id=str(getattr(ns, "item_id", "")),
        start_hour=int(getattr(ns, "start_hour", 8)),
        end_hour=int(getattr(ns, "end_hour", 23)),
        label=str(getattr(ns, "label", "")),
        category=str(getattr(ns, "category", "other")),
        start_time=str(getattr(ns, "start_time", "")),
        end_time=str(getattr(ns, "end_time", "")),
        repeat_rule=str(getattr(ns, "repeat_rule", "daily"))
    );
}

def minute_text(total: int) -> str {
    hour = total // 60;
    minute = total % 60;
    if hour > 0 and minute > 0 { return f"{hour}h {minute}m"; }
    if hour > 0 { return f"{hour}h"; }
    return f"{minute}m";
}

def print_today(data: DashboardData) {
    print(f"\nTODAY — {data.today}");
    print("=" * 58);
    if not data.today_sessions {
        print("No sessions scheduled. Add a task or run `studyflow demo`.");
    }
    for session in data.today_sessions {
        mark = "x" if session.completed else " ";
        print(
            f"[{mark}] {session.start_time:<9} {session.course:<12} "
            f"{session.title} ({minute_text(session.duration)})"
        );
        print(f"    id: {session.id}");
    }
    total = sum([s.duration for s in data.today_sessions]);
    print("-" * 58);
    print(f"Total planned: {minute_text(total)}");
    if data.overload_minutes > 0 {
        print(f"Attention: {minute_text(data.overload_minutes)} could not fit before deadlines.");
    }
    if data.reserved_blocks {
        print("\nRESERVED TIME");
        for block in data.reserved_blocks {
            print(f"- {block.label}: {block.start_time}–{block.end_time} ({block.repeat_label or block.repeat_rule})");
            print(f"  id: {block.id}");
        }
    }
}

def print_tasks(data: DashboardData) {
    print("\nASSIGNMENTS");
    print("=" * 72);
    if not data.tasks { print("No assignments yet."); }
    for task in data.tasks {
        mark = "x" if task.completed else " ";
        print(
            f"[{mark}] {task.course:<12} {task.title:<28} "
            f"{task.progress:>3}%  {task.due_label}"
        );
        print(f"    id: {task.id}");
    }
    print("-" * 72);
    print(
        f"{data.active_tasks} active · {data.completed_tasks} completed · "
        f"{minute_text(data.remaining_minutes)} remaining"
    );
}

async def dispatch(inv: Invocation) -> int {
    try {
        if inv.command == "today" {
            print_today(await get_dashboard());
        } elif inv.command == "list" {
            print_tasks(await get_dashboard());
        } elif inv.command == "add" {
            data = await add_task(
                inv.title, inv.course, inv.due, inv.minutes, inv.priority
            );
            print(data.message);
            print_tasks(data);
        } elif inv.command == "done" {
            data = await complete_session(inv.item_id);
            print(data.message);
            print_today(data);
        } elif inv.command == "task-done" {
            data = await toggle_task(inv.item_id);
            print(data.message);
            print_tasks(data);
        } elif inv.command == "replan" {
            data = await replan();
            print(data.message);
            print_today(data);
        } elif inv.command == "settings" {
            data = await save_planning_window(inv.start_hour, inv.end_hour);
            print(data.message);
            print_today(data);
        } elif inv.command == "block" {
            data = await add_reserved_block(
                inv.label, inv.category, inv.start_time, inv.end_time, inv.repeat_rule
            );
            print(data.message);
            print_today(data);
        } elif inv.command == "unblock" {
            data = await delete_reserved_block(inv.item_id);
            print(data.message);
            print_today(data);
        } elif inv.command == "routine" {
            data = await seed_routine();
            print(data.message);
            print_today(data);
        } elif inv.command == "demo" {
            data = await seed_demo();
            print(data.message);
            print_today(data);
        }
        return 0;
    } except BridgeError as e {
        print("studyflow: planner server is unavailable: " + str(e), file=sys.stderr);
        print("hint: start it with `jac run`", file=sys.stderr);
        return 3;
    } except Exception as e {
        print("studyflow: " + str(e), file=sys.stderr);
        return 1;
    }
}

async def main(argv: list[str]) -> int {
    return await dispatch(parse_args(argv));
}

with entry:__main__ {
    sys.`exit(asyncio.run(main(sys.argv[1:])));
}
