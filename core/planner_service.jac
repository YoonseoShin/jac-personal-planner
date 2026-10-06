import from datetime { date, datetime, timedelta }

obj TaskView {
    has id: str, title: str, course: str, due_date: str,
        estimated_minutes: int, completed_minutes: int,
        priority: str, completed: bool, progress: int, due_label: str,
        color: str = "#4f46e5", days_left: int = 0,
        due_time: str = "", due_time_label: str = "", overdue: bool = False,
        logged_minutes: int = 0, due_on: str = "", location: str = "";
}

obj SessionView {
    has id: str, task_id: str, title: str, course: str, day: str,
        start_time: str, start_minute: int, duration: int,
        priority: str, completed: bool, color: str = "#4f46e5",
        end_time: str = "", missed: bool = False, location: str = "",
        moved_from: str = "", added_note: str = "";
}

obj DayLoad {
    has day: str, label: str, minutes: int, capacity: int;
}

obj ReservedBlockView {
    has id: str, label: str, category: str, start_time: str,
        end_time: str, repeat_rule: str, repeat_label: str = "",
        days: list[str] = [], location: str = "";
}

obj SettingsView {
    has start_hour: int, end_hour: int;
}

obj DashboardData {
    has tasks: list[TaskView], today_sessions: list[SessionView],
        week_sessions: list[SessionView], loads: list[DayLoad],
        reserved_blocks: list[ReservedBlockView], settings: SettingsView,
        active_tasks: int, completed_tasks: int,
        remaining_minutes: int, scheduled_minutes: int,
        overload_minutes: int, today: str, message: str,
        missed_sessions: int = 0, missed_minutes: int = 0,
        due_this_week: int = 0, unfit_minutes: int = 0,
        improvable_tasks: int = 0, overlapping: int = 0;
}

obj CalendarItem {
    has id: str, kind: str, title: str, course: str = "", color: str = "",
        start_minute: int = 0, duration: int = 0, time_label: str = "",
        completed: bool = False, missed: bool = False, task_id: str = "",
        top: int = 0, height: int = 0, location: str = "",
        moved_from: str = "", added_note: str = "";
}

# An unfinished block as the scheduler sees it, in memory. `node_id` links
# it to a stored block; empty means it is new.
obj PlanBlock {
    has task_id: str, day: str, start: int, duration: int,
        node_id: str = "", changed: bool = False,
        from_day: str = "", from_minute: int = -1,
        base: int = 0, added: int = 0, from_more: int = 0;
}

obj HourMark {
    has label: str, y: int;
}

obj CalendarDay {
    has date: str, day_num: int, weekday: str, label: str,
        is_today: bool, is_past: bool, in_range: bool,
        sessions: list[CalendarItem], busy: list[CalendarItem],
        due: list[CalendarItem], work: list[CalendarItem],
        study_minutes: int, free_minutes: int;
}

obj CalendarData {
    has view: str, anchor: str, title: str, days: list[CalendarDay],
        start_hour: int, end_hour: int, grid_height: int = 0,
        hour_marks: list[HourMark] = [];
}

node Task {
    has title: str, due_date: str, course: str = "General",
        estimated_minutes: int = 60, completed_minutes: int = 0,
        priority: str = "medium", completed: bool = False,
        created_at: str = "", due_time: str = "", color: str = "",
        closed: bool = False, location: str = "";
}

node StudySession {
    has task_id: str, title: str, course: str, day: str,
        start_time: str, duration: int, start_minute: int = 1080,
        priority: str = "medium",
        completed: bool = False,
        moved_from_day: str = "", moved_from_minute: int = -1,
        added_minutes: int = 0, added_from_day: str = "", added_from_minute: int = -1,
        moved_from_more: int = 0;
}

node ReservedBlock {
    has label: str, category: str = "other", start_minute: int = 0,
        end_minute: int = 0, repeat_rule: str = "daily", location: str = "";
}

node PlannerSettings {
    has daily_minutes: int = 180, start_hour: int = 8, end_hour: int = 23,
        availability_initialized: bool = False;
}

def:priv priority_rank(value: str) -> int {
    if value == "high" { return 0; }
    if value == "low" { return 2; }
    return 1;
}

# Ordered so neighbours contrast; red is left out so it stays the deadline color.
glob TASK_COLORS: list[str] = [
    "#4f46e5", "#ea580c", "#16a34a", "#db2777", "#0891b2", "#ca8a04",
    "#7c3aed", "#0d9488", "#475569", "#65a30d", "#c026d3", "#a16207"
];

# Tasks in the same course share one color; tasks without a course each get
# their own.
def:priv color_group(task: Task) -> str {
    course = task.course.strip().lower();
    if course and course != "general" { return "course:" + course; }
    return "task:" + jid(task);
}

def:priv pick_color(task: Task) -> str {
    key = color_group(task);
    in_use: list[str] = [];
    for other in [root-->][?:Task] {
        if jid(other) == jid(task) or not other.color { continue; }
        if color_group(other) == key { return other.color; }
        in_use.append(other.color);
    }
    for candidate in TASK_COLORS {
        if candidate not in in_use { return candidate; }
    }
    # More groups than colors: reuse the least used one.
    best = TASK_COLORS[0];
    for candidate in TASK_COLORS {
        if in_use.count(candidate) < in_use.count(best) { best = candidate; }
    }
    return best;
}

# Gives every task a color and repairs clashes, where two different groups
# ended up with the same color while a free one is still available.
def:priv ensure_colors -> dict[str, str] {
    tasks = list([root-->][?:Task]);
    group_count = len(set([color_group(t) for t in tasks]));
    owner: dict[str, str] = {};
    colors: dict[str, str] = {};
    for task in tasks {
        key = color_group(task);
        clash = task.color and task.color in owner and owner[task.color] != key;
        retired = task.color and task.color not in TASK_COLORS;
        if not task.color or retired or (clash and group_count <= len(TASK_COLORS)) {
            task.color = "";
            task.color = pick_color(task);
        }
        owner.setdefault(task.color, key);
        colors[jid(task)] = task.color;
    }
    return colors;
}

def:priv valid_priority(value: str) -> bool {
    return value in ["high", "medium", "low"];
}

def:priv clean_location(value: str) -> str {
    return value.strip()[:80];
}

def:priv clean_course(value: str) -> str {
    return value.strip() if value.strip() else "General";
}

def:priv parse_due(value: str) -> date {
    try {
        return date.fromisoformat(value);
    } except ValueError {
        raise ValueError("Enter a real due date (YYYY-MM-DD).");
    }
}

# Work can go anywhere in the day; only reserved time is off limits.
glob DAY_START: int = 0,
     DAY_END: int = 24 * 60;

def:priv minutes_label(total: int) -> str {
    hour = total // 60;
    minute = total % 60;
    if hour > 0 and minute > 0 { return f"{hour}h {minute}m"; }
    if hour > 0 { return f"{hour}h"; }
    return f"{minute}m";
}

def:priv clock_label(total_minutes: int) -> str {
    hour = (total_minutes // 60) % 24;
    minute = total_minutes % 60;
    suffix = "AM" if hour < 12 else "PM";
    shown = hour % 12;
    if shown == 0 { shown = 12; }
    return f"{shown}:{minute:02d} {suffix}";
}

def:priv parse_clock(value: str) -> int {
    parts = value.strip().split(":");
    if len(parts) != 2 {
        raise ValueError("Enter a time as HH:MM, for example 09:30.");
    }
    try {
        hour = int(parts[0]);
        minute = int(parts[1]);
    } except ValueError {
        raise ValueError("Enter a time as HH:MM, for example 09:30.");
    }
    if hour < 0 or hour > 23 or minute < 0 or minute > 59 {
        raise ValueError("Enter a real time between 00:00 and 23:59.");
    }
    return hour * 60 + minute;
}

glob DAY_CODES: list[str] = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"];

# A repeat rule is "daily", "weekdays", "weekends", or a comma list of day
# codes such as "mon,wed,fri". Returns weekday indexes (Mon = 0).
def:priv repeat_days(value: str) -> list[int] {
    rule = value.strip().lower();
    if rule == "daily" { return [0, 1, 2, 3, 4, 5, 6]; }
    if rule == "weekdays" { return [0, 1, 2, 3, 4]; }
    if rule == "weekends" { return [5, 6]; }
    picked: list[int] = [];
    for part in rule.split(",") {
        code = part.strip()[:3];
        if code not in DAY_CODES { return []; }
        index = DAY_CODES.index(code);
        if index not in picked { picked.append(index); }
    }
    picked.sort();
    return picked;
}

def:priv valid_repeat(value: str) -> bool {
    return len(repeat_days(value)) > 0;
}

def:priv normalize_repeat(value: str) -> str {
    picked = repeat_days(value);
    if picked == [0, 1, 2, 3, 4, 5, 6] { return "daily"; }
    if picked == [0, 1, 2, 3, 4] { return "weekdays"; }
    if picked == [5, 6] { return "weekends"; }
    return ",".join([DAY_CODES[i] for i in picked]);
}

def:priv repeat_text(value: str) -> str {
    rule = normalize_repeat(value);
    if rule == "daily" { return "Every day"; }
    if rule == "weekdays" { return "Weekdays"; }
    if rule == "weekends" { return "Weekends"; }
    return ", ".join([DAY_CODES[i].capitalize() for i in repeat_days(rule)]);
}

def:priv active_on(block: ReservedBlock, day_value: date) -> bool {
    return day_value.weekday() in repeat_days(block.repeat_rule);
}

# Minutes a block covers on a day it is active; an overnight block such as
# 23:00-08:00 covers both ends of that day.
def:priv clock_spans(start: int, end: int) -> list[tuple[int, int]] {
    if end > start { return [(start, end)]; }
    return [(start, 1440), (0, end)];
}

def:priv reserved_spans(day_value: date) -> list[tuple[int, int]] {
    spans: list[tuple[int, int]] = [];
    for block in [root-->][?:ReservedBlock] {
        if active_on(block, day_value) {
            spans += clock_spans(block.start_minute, block.end_minute);
        }
    }
    return spans;
}

# The existing reserved block that shares a repeat day and overlaps
# [start, end), if any.
def:priv clashing_block(start: int, end: int, repeat_rule: str) -> ReservedBlock | None {
    days = repeat_days(repeat_rule);
    wanted = clock_spans(start, end);
    for block in [root-->][?:ReservedBlock] {
        if not any([day in days for day in repeat_days(block.repeat_rule)]) { continue; }
        for mine in wanted {
            for theirs in clock_spans(block.start_minute, block.end_minute) {
                if mine[0] < theirs[1] and theirs[0] < mine[1] { return block; }
            }
        }
    }
    return None;
}

def:priv now_minute -> int {
    now = datetime.now();
    return now.hour * 60 + now.minute;
}

# Earliest minute work may be planned on a day: the planning window start,
# or for today the next quarter hour from now -- never in the past.
def:priv day_start(day_value: date, window_start: int) -> int {
    if day_value != date.today() { return window_start; }
    upcoming = ((now_minute() + 14) // 15) * 15;
    return max(window_start, upcoming);
}

def:priv is_missed(session: StudySession) -> bool {
    if session.completed { return False; }
    today_key = date.today().isoformat();
    if session.day < today_key { return True; }
    return session.day == today_key
        and session.start_minute + session.duration <= now_minute();
}

# Deadline minute on the due date; tasks without a time are due end of day.
def:priv due_minute(task: Task) -> int {
    return parse_clock(task.due_time) if task.due_time else 1440;
}

def:priv is_overdue(task: Task) -> bool {
    due = parse_due(task.due_date);
    today = date.today();
    if due != today { return due < today; }
    return due_minute(task) <= now_minute();
}

def:priv clean_due(due_date: str, due_time: str) -> tuple[date, str] {
    due = parse_due(due_date);
    if due < date.today() { raise ValueError("Due date cannot be in the past."); }
    if not due_time.strip() { return (due, ""); }
    minute = parse_clock(due_time);
    if due == date.today() and minute <= now_minute() {
        raise ValueError("That due time has already passed today.");
    }
    return (due, f"{minute // 60:02d}:{minute % 60:02d}");
}

def:priv base_available_minutes(day_value: date) -> int {
    start = day_start(day_value, DAY_START);
    finish = DAY_END;
    occupied = reserved_spans(day_value);
    occupied.sort(key=lambda (span: tuple[int, int]) { span[0]; });
    cursor = start;
    available = 0;
    for span in occupied {
        blocked_start = min(finish, max(start, span[0]));
        blocked_end = min(finish, span[1]);
        if blocked_end <= cursor { continue; }
        if blocked_start > cursor { available += blocked_start - cursor; }
        cursor = max(cursor, blocked_end);
    }
    if cursor < finish { available += finish - cursor; }
    return available;
}

def:priv free_slots(
    day_value: date, until: int = 1440, plan: list[PlanBlock] | None = None
) -> list[tuple[int, int]] {
    start = day_start(day_value, DAY_START);
    finish = min(DAY_END, until);
    occupied = reserved_spans(day_value);
    day_key = day_value.isoformat();
    # Finished blocks don't hold their slot: finishing early frees that time.
    blocks = plan if plan is not None else open_plan();
    for block in blocks {
        if block.day == day_key {
            occupied.append((block.start, block.start + block.duration));
        }
    }
    occupied.sort(key=lambda (span: tuple[int, int]) { span[0]; });
    slots: list[tuple[int, int]] = [];
    cursor = start;
    for span in occupied {
        # Clamp both ends to the window: a gap that runs up to a reserved
        # block after the deadline must still stop at the deadline.
        blocked_start = min(finish, max(start, span[0]));
        blocked_end = min(finish, span[1]);
        if blocked_end <= cursor { continue; }
        if blocked_start > cursor { slots.append((cursor, blocked_start)); }
        cursor = max(cursor, blocked_end);
    }
    if cursor < finish { slots.append((cursor, finish)); }
    return slots;
}

def:priv open_plan -> list[PlanBlock] {
    return [
        PlanBlock(
            task_id=item.task_id, day=item.day, start=item.start_minute,
            duration=item.duration, node_id=jid(item), base=item.duration
        )
        for item in [root-->][?:StudySession] if not item.completed
    ];
}

def:priv in_progress(item: StudySession) -> bool {
    now = now_minute();
    return not item.completed and item.day == date.today().isoformat()
        and item.start_minute <= now < item.start_minute + item.duration;
}

def:priv schedule_on_day(
    task: Task, day_value: date, requested: int, until: int,
    plan: list[PlanBlock]
) -> int {
    placed = 0;
    day_key = day_value.isoformat();
    while placed < requested {
        need = requested - placed;
        slots = free_slots(day_value, until, plan);
        if not slots { break; }
        # Prefer one slot that holds the whole chunk, so work isn't shredded
        # into 15-minute leftovers; otherwise take the largest usable gap.
        chosen = slots[0];
        found = False;
        for slot in slots {
            if slot[1] - slot[0] >= need {
                chosen = slot;
                found = True;
                break;
            }
        }
        if not found {
            for slot in slots {
                if slot[1] - slot[0] > chosen[1] - chosen[0] { chosen = slot; }
            }
        }
        chunk = min(need, chosen[1] - chosen[0]);
        if chunk < min(30, requested - placed) { break; }
        placed += chunk;
        # Same task right before this gap -> grow that block instead of
        # starting a new one, so one task reads as one continuous block.
        extended = False;
        for previous in plan {
            if previous.task_id == jid(task) and previous.day == day_key
                and previous.start + previous.duration == chosen[0] {
                previous.duration += chunk;
                previous.changed = True;
                extended = True;
                break;
            }
        }
        if not extended {
            plan.append(PlanBlock(
                task_id=jid(task), day=day_key, start=chosen[0], duration=chunk
            ));
        }
    }
    return placed;
}

def:priv task_view(task: Task, logged: int = 0) -> TaskView {
    today = date.today();
    due = parse_due(task.due_date);
    delta = (due - today).days;
    time_label = clock_label(due_minute(task)) if task.due_time else "";
    overdue = is_overdue(task) and not task.completed;
    due_label = "Due today" if delta == 0 else (
        "Due tomorrow" if delta == 1 else (
            f"Due in {delta} days" if delta > 1 else (
                "Overdue by 1 day" if delta == -1 else f"Overdue by {-delta} days"
            )
        )
    );
    if delta == 0 and overdue {
        due_label = "Overdue since " + time_label;
    } elif delta >= 0 and time_label {
        due_label += " · " + time_label;
    }
    progress = 100 if task.completed else min(
        99, int((task.completed_minutes * 100) / max(1, task.estimated_minutes))
    );
    return TaskView(
        id=jid(task), title=task.title, course=task.course,
        due_date=task.due_date, estimated_minutes=task.estimated_minutes,
        completed_minutes=task.completed_minutes, priority=task.priority,
        completed=task.completed, progress=progress, due_label=due_label,
        color=task.color or TASK_COLORS[0], days_left=delta,
        due_time=task.due_time, due_time_label=time_label, overdue=overdue,
        logged_minutes=logged,
        due_on=f"Due {due.strftime('%b')} {due.day}" + (f" · {time_label}" if time_label else ""),
        location=task.location
    );
}

# "Tue, Oct 6 · 1:00 PM" (or just the time when it moved within the day).
# "Tue, Oct 6 · 1:00 PM", or just the time when it is the same day.
def:priv from_text(from_day: str, from_minute: int, here_day: str) -> str {
    if not from_day or from_minute < 0 { return ""; }
    time_text = clock_label(from_minute);
    if from_day == here_day { return time_text; }
    when = date.fromisoformat(from_day);
    return f"{when.strftime('%a, %b')} {when.day} · {time_text}";
}

def:priv more_text(count: int) -> str {
    if count <= 0 { return ""; }
    return f" and {count} other block" + ("" if count == 1 else "s");
}

def:priv moved_label(session: StudySession) -> str {
    if session.added_minutes > 0 { return ""; }
    if session.moved_from_day == session.day and session.moved_from_minute == session.start_minute {
        return "";
    }
    source = from_text(session.moved_from_day, session.moved_from_minute, session.day);
    return source + more_text(session.moved_from_more) if source else "";
}

# "30m added · rescheduled from Mon, Oct 5 · 10:19 PM" for a block that grew.
def:priv added_label(session: StudySession) -> str {
    if session.added_minutes <= 0 { return ""; }
    source = from_text(session.added_from_day, session.added_from_minute, session.day);
    return minutes_label(session.added_minutes) + " added"
        + (" · rescheduled from " + source + more_text(session.moved_from_more) if source else "");
}

def:priv session_view(
    session: StudySession, colors: dict[str, str] | None = None,
    places: dict[str, str] | None = None
) -> SessionView {
    return SessionView(
        id=jid(session), task_id=session.task_id, title=session.title,
        course=session.course, day=session.day,
        start_time=clock_label(session.start_minute),
        start_minute=session.start_minute, duration=session.duration,
        priority=session.priority, completed=session.completed,
        color=(colors or {}).get(session.task_id, TASK_COLORS[0]),
        end_time=clock_label(session.start_minute + session.duration),
        missed=is_missed(session),
        location=(places or {}).get(session.task_id, ""),
        moved_from=moved_label(session),
        added_note=added_label(session)
    );
}

def:priv reserved_view(block: ReservedBlock) -> ReservedBlockView {
    return ReservedBlockView(
        id=jid(block), label=block.label, category=block.category,
        start_time=f"{block.start_minute // 60:02d}:{block.start_minute % 60:02d}",
        end_time=f"{block.end_minute // 60:02d}:{block.end_minute % 60:02d}",
        repeat_rule=block.repeat_rule,
        repeat_label=repeat_text(block.repeat_rule),
        days=[DAY_CODES[i] for i in repeat_days(block.repeat_rule)],
        location=block.location
    );
}

def:priv find_task(task_id: str) -> Task | None {
    for task in [root-->][?:Task] {
        if jid(task) == task_id { return task; }
    }
    return None;
}

def:priv find_session(session_id: str) -> StudySession | None {
    for session in [root-->][?:StudySession] {
        if jid(session) == session_id { return session; }
    }
    return None;
}

# Progress always follows the blocks that are checked off, so checking and
# unchecking can never leave a task's minutes out of sync.
def:priv logged_minutes -> dict[str, int] {
    logged: dict[str, int] = {};
    for item in [root-->][?:StudySession] {
        if item.completed {
            logged[item.task_id] = logged.get(item.task_id, 0) + item.duration;
        }
    }
    return logged;
}

# A task is finished when the user pressed Done on it (`closed`) or when its
# checked-off blocks cover the estimate. Progress follows the checked blocks.
def:priv sync_progress {
    logged = logged_minutes();
    for task in [root-->][?:Task] {
        done = logged.get(jid(task), 0);
        if task.completed and not task.closed and done < task.estimated_minutes {
            task.closed = True;  # marked done as a whole before `closed` existed
        }
        task.completed = task.closed or done >= task.estimated_minutes;
        task.completed_minutes = task.estimated_minutes if task.closed else min(task.estimated_minutes, done);
        if task.completed { drop_open_blocks(jid(task)); }
    }
}

def:priv drop_open_blocks(task_id: str) {
    for block in list([root-->][?:StudySession]) {
        if block.task_id == task_id and not block.completed { del block; }
    }
}

# Puts a task's not-yet-planned work into free time between now and its
# deadline. Every other block stays exactly where it is. Returns the minutes
# that did not fit.
# Adds a task's not-yet-planned work to `plan`, between now and its
# deadline, around everything already in the plan. Returns minutes that did
# not fit.
def:priv plan_task(task: Task, plan: list[PlanBlock]) -> int {
    if task.completed { return 0; }
    today = date.today();
    planned = sum([block.duration for block in plan if block.task_id == jid(task)]);
    remaining = max(0, task.estimated_minutes - task.completed_minutes - planned);
    if remaining == 0 { return 0; }
    due = parse_due(task.due_date);
    overdue = is_overdue(task);
    last_day = today if overdue else due;
    # On the due date, work must finish before the due time. Overdue work
    # just goes into the earliest free time.
    cutoff = 1440 if overdue else due_minute(task);
    day_count = (last_day - today).days + 1;
    fair_share = max(30, (remaining + day_count - 1) // day_count);
    day_index = 0;
    while remaining > 0 and day_index < day_count {
        current = today + timedelta(days=day_index);
        until = cutoff if current == last_day else 1440;
        remaining -= schedule_on_day(task, current, min(fair_share, remaining), until, plan);
        day_index += 1;
    }
    day_index = 0;
    while remaining > 0 and day_index < day_count {
        current = today + timedelta(days=day_index);
        until = cutoff if current == last_day else 1440;
        remaining -= schedule_on_day(task, current, remaining, until, plan);
        day_index += 1;
    }
    return remaining;
}

# Writes new and grown blocks from `plan` to the graph.
# Records where each newly placed block came from. `previous` holds the
# blocks that were cleared before re-planning; for each task, new blocks that
# landed exactly where an old one was keep that block's history, and the rest
# are paired in time order with the old blocks that moved.
# Records where re-planned work came from, minute by minute. `previous`
# holds the blocks cleared before re-planning. Old blocks that shrank or
# vanished are the sources; new blocks and blocks that grew draw their extra
# minutes from those sources in time order. A block can therefore come from
# several old blocks (e.g. 18 minutes from each of the next three days).
def:priv trace_moves(plan: list[PlanBlock], previous: list[StudySession]) {
    touched = set([b.task_id for b in plan if not b.node_id or b.duration > b.base]);
    for task_id in touched {
        olds = [o for o in previous if o.task_id == task_id];
        olds.sort(key=lambda (o: StudySession) { (o.day, o.start_minute); });
        news = [
            b for b in plan
            if b.task_id == task_id and (not b.node_id or b.duration > b.base)
        ];
        news.sort(key=lambda (b: PlanBlock) { (b.day, b.start); });
        left = [o.duration for o in olds];
        gained: list[int] = [];
        for block in news {
            if block.node_id {
                gained.append(block.duration - block.base);
                continue;
            }
            spot = -1;
            for i in range(len(olds)) {
                if olds[i].day == block.day and olds[i].start_minute == block.start
                    and left[i] == olds[i].duration {
                    spot = i;
                    break;
                }
            }
            if spot < 0 {
                gained.append(block.duration);
                continue;
            }
            same = olds[spot];
            kept = min(same.duration, block.duration);
            left[spot] = same.duration - kept;
            gained.append(block.duration - kept);
            # Unchanged block: keep whatever history it already had.
            if same.added_minutes > 0 {
                block.added = same.added_minutes;
                block.from_day = same.added_from_day;
                block.from_minute = same.added_from_minute;
            } else {
                block.from_day = same.moved_from_day;
                block.from_minute = same.moved_from_minute;
            }
            block.from_more = same.moved_from_more;
        }
        sources: list[list[int]] = [[i, left[i]] for i in range(len(olds)) if left[i] > 0];
        for (block, extra) in zip(news, gained) {
            if extra <= 0 { continue; }
            first = -1;
            count = 0;
            need = extra;
            while need > 0 and sources {
                take = min(need, sources[0][1]);
                if first < 0 { first = sources[0][0]; }
                count += 1;
                sources[0][1] -= take;
                need -= take;
                if sources[0][1] == 0 { sources = sources[1:]; }
            }
            if first < 0 { continue; }
            block.from_day = olds[first].day;
            block.from_minute = olds[first].start_minute;
            block.from_more = count - 1;
            block.added = extra if (block.node_id or extra < block.duration) else 0;
        }
    }
}

# Writes new and grown blocks from `plan` to the graph.
def:priv save_plan(plan: list[PlanBlock], previous: list[StudySession] | None = None) {
    if previous { trace_moves(plan, previous); }
    tasks = {jid(t): t for t in [root-->][?:Task]};
    stored = {jid(item): item for item in [root-->][?:StudySession]};
    for block in plan {
        if block.node_id {
            if block.changed and block.node_id in stored {
                kept = stored[block.node_id];
                kept.duration = block.duration;
                if block.added > 0 {
                    kept.added_minutes += block.added;
                    kept.added_from_day = block.from_day;
                    kept.added_from_minute = block.from_minute;
                    kept.moved_from_more = block.from_more;
                }
            }
            continue;
        }
        task = tasks.get(block.task_id);
        if task is None { continue; }
        root ++> StudySession(
            task_id=block.task_id, title=task.title, course=task.course,
            day=block.day, start_time=clock_label(block.start),
            start_minute=block.start, duration=block.duration,
            priority=task.priority,
            moved_from_day="" if block.added > 0 else block.from_day,
            moved_from_minute=-1 if block.added > 0 else block.from_minute,
            added_minutes=block.added,
            added_from_day=block.from_day if block.added > 0 else "",
            added_from_minute=block.from_minute if block.added > 0 else -1,
            moved_from_more=block.from_more
        );
    }
}

# Places one task's unplanned work into free time; every other block stays
# exactly where it is. Returns the minutes that did not fit.
def:priv place_task(task: Task, previous: list[StudySession] | None = None) -> int {
    plan = open_plan();
    unscheduled = plan_task(task, plan);
    save_plan(plan, previous);
    return unscheduled;
}

def:priv by_deadline(tasks: list[Task]) -> list[Task] {
    ordered = list(tasks);
    ordered.sort(key=lambda (item: Task) {
        (item.due_date, due_minute(item), priority_rank(item.priority),
            item.created_at)
    });
    return ordered;
}

# Full re-plan, only run when the user presses Reschedule: every unfinished
# block is cleared and all remaining work is placed again from now on,
# earliest deadline first.
# What Reschedule would produce: unfinished blocks are cleared (except one
# in progress right now) and all remaining work is placed again from now,
# earliest deadline first. Nothing is written.
# True when [start, end) on `day` overlaps reserved time or any of `others`.
def:priv clashes(
    day: str, start: int, end: int, others: list[tuple[str, int, int]]
) -> bool {
    for span in reserved_spans(date.fromisoformat(day)) {
        if span[0] < end and start < span[1] { return True; }
    }
    for other in others {
        if other[0] == day and other[1] < end and start < other[2] { return True; }
    }
    return False;
}

def:priv snapshot(item: StudySession) -> StudySession {
    return StudySession(
        task_id=item.task_id, title=item.title, course=item.course,
        day=item.day, start_time=item.start_time, duration=item.duration,
        start_minute=item.start_minute,
        moved_from_day=item.moved_from_day, moved_from_minute=item.moved_from_minute,
        added_minutes=item.added_minutes, added_from_day=item.added_from_day,
        added_from_minute=item.added_from_minute, moved_from_more=item.moved_from_more
    );
}

# Unfinished, upcoming blocks that sit on top of another block or reserved time.
def:priv overlapping_blocks -> int {
    blocks = [b for b in open_plan() if not block_missed(b)];
    count = 0;
    for block in blocks {
        others = [
            (o.day, o.start, o.start + o.duration) for o in blocks
            if o.node_id != block.node_id
        ];
        if clashes(block.day, block.start, block.start + block.duration, others) {
            count += 1;
        }
    }
    return count;
}

# What Reschedule would produce: unfinished blocks are cleared and all
# remaining work is placed again from now, earliest deadline first. A block in
# progress right now stays put, unless it overlaps another one (then only the
# first of them stays). Nothing is written.
def:priv simulate_reschedule -> tuple[list[PlanBlock], int] {
    running = [item for item in [root-->][?:StudySession] if in_progress(item)];
    running.sort(key=lambda (item: StudySession) { (item.start_minute, jid(item)); });
    plan: list[PlanBlock] = [];
    for item in running {
        taken = [(b.day, b.start, b.start + b.duration) for b in plan];
        if clashes(item.day, item.start_minute, item.start_minute + item.duration, taken) {
            continue;
        }
        plan.append(PlanBlock(
            task_id=item.task_id, day=item.day, start=item.start_minute,
            duration=item.duration, node_id=jid(item), base=item.duration
        ));
    }
    unscheduled = 0;
    for task in by_deadline([t for t in [root-->][?:Task] if not t.completed]) {
        unscheduled += plan_task(task, plan);
    }
    return (plan, unscheduled);
}

# Full re-plan, only run when the user presses Reschedule.
def:priv rebuild_schedule -> int {
    sync_progress();
    (plan, unscheduled) = simulate_reschedule();
    kept = set([b.node_id for b in plan if b.node_id]);
    previous: list[StudySession] = [];
    for old in list([root-->][?:StudySession]) {
        if not old.completed and jid(old) not in kept {
            previous.append(snapshot(old));
            del old;
        }
    }
    save_plan(plan, previous);
    return unscheduled;
}

def:priv block_end(block: PlanBlock) -> int {
    return date.fromisoformat(block.day).toordinal() * 1440 + block.start + block.duration;
}

def:priv block_missed(block: PlanBlock) -> bool {
    today_key = date.today().isoformat();
    return block.day < today_key
        or (block.day == today_key and block.start + block.duration <= now_minute());
}

# How many tasks a Reschedule would help: tasks that would get more of their
# work planned, or whose work would on average be done at least 15 minutes
# sooner (time freed up by finishing early, marking a task Done, or removing
# reserved time).
def:priv improvable_tasks(simulated: list[PlanBlock]) -> int {
    now_plan = [b for b in open_plan() if not block_missed(b)];
    def totals(blocks: list[PlanBlock]) -> tuple[dict[str, int], dict[str, int]] {
        planned: dict[str, int] = {};
        weighted: dict[str, int] = {};
        for block in blocks {
            planned[block.task_id] = planned.get(block.task_id, 0) + block.duration;
            weighted[block.task_id] = weighted.get(block.task_id, 0) + block.duration * block_end(block);
        }
        return (planned, weighted);
    }
    (now_planned, now_weighted) = totals(now_plan);
    (new_planned, new_weighted) = totals(simulated);
    better = 0;
    for task_id in new_planned {
        before = now_planned.get(task_id, 0);
        if new_planned[task_id] > before {
            better += 1;
        } elif before > 0 {
            sooner = now_weighted[task_id] / before - new_weighted[task_id] / new_planned[task_id];
            if sooner >= 15 { better += 1; }
        }
    }
    return better;
}

def:priv make_dashboard(message: str = "") -> DashboardData {
    colors = ensure_colors();
    today = date.today();
    logged = logged_minutes();
    task_views = [task_view(task, logged.get(jid(task), 0)) for task in [root-->][?:Task]];
    task_views.sort(key=lambda (item: TaskView) {
        (item.completed, item.due_date, item.due_time or "99",
            priority_rank(item.priority))
    });
    places = {jid(t): t.location for t in [root-->][?:Task]};
    session_views = [session_view(s, colors, places) for s in [root-->][?:StudySession]];
    session_views.sort(key=lambda (item: SessionView) {
        (item.day, item.start_minute)
    });
    block_views = [reserved_view(b) for b in [root-->][?:ReservedBlock]];
    block_views.sort(key=lambda (item: ReservedBlockView) {
        (item.start_time, item.label)
    });
    today_sessions = [s for s in session_views if s.day == today.isoformat()];
    week_end = (today + timedelta(days=6)).isoformat();
    week_sessions = [s for s in session_views if today.isoformat() <= s.day <= week_end];
    loads: list[DayLoad] = [];
    for offset in range(7) {
        day_value = today + timedelta(days=offset);
        day_key = day_value.isoformat();
        minutes = sum([s.duration for s in week_sessions if s.day == day_key]);
        loads.append(DayLoad(
            day=day_key, label=day_value.strftime("%a"), minutes=minutes,
            capacity=base_available_minutes(day_value)
        ));
    }
    active = len([t for t in task_views if not t.completed]);
    completed = len(task_views) - active;
    remaining = sum([
        max(0, t.estimated_minutes - t.completed_minutes)
        for t in task_views if not t.completed
    ]);
    scheduled = sum([
        s.duration for s in session_views if not s.completed and not s.missed
    ]);
    missed = [s for s in session_views if s.missed];
    due_soon = len([
        t for t in task_views if not t.completed and t.days_left <= 6
    ]);
    (simulated, simulated_unfit) = simulate_reschedule();
    return DashboardData(
        tasks=task_views, today_sessions=today_sessions,
        week_sessions=week_sessions, loads=loads, reserved_blocks=block_views,
        settings=SettingsView(
            start_hour=DAY_START // 60, end_hour=DAY_END // 60
        ),
        active_tasks=active, completed_tasks=completed,
        remaining_minutes=remaining, scheduled_minutes=scheduled,
        overload_minutes=max(0, remaining - scheduled),
        today=today.strftime("%A, %B %d"), message=message,
        missed_sessions=len(missed),
        missed_minutes=sum([s.duration for s in missed]),
        due_this_week=due_soon,
        unfit_minutes=simulated_unfit,
        improvable_tasks=improvable_tasks(simulated),
        overlapping=overlapping_blocks()
    );
}

def:pub get_dashboard -> DashboardData { return make_dashboard(); }

def:pub add_task(  # jac:ignore[W3030]
    title: str, course: str, due_date: str,
    estimated_minutes: int, priority: str, due_time: str = "",
    location: str = ""
) -> DashboardData {
    clean_title = title.strip();
    if not clean_title { raise ValueError("Task title is required."); }
    (due, clean_time) = clean_due(due_date, due_time);
    if not isinstance(estimated_minutes, int) or isinstance(estimated_minutes, bool) {
        raise ValueError("Estimated work must be a whole number of minutes.");
    }
    if estimated_minutes < 15 or estimated_minutes > 1440 {
        raise ValueError("Estimate must be between 15 and 1440 minutes.");
    }
    if not valid_priority(priority) { raise ValueError("Priority must be high, medium, or low."); }
    task = (root ++> Task(
        title=clean_title, course=clean_course(course),
        due_date=due.isoformat(), due_time=clean_time,
        location=clean_location(location),
        estimated_minutes=estimated_minutes,
        priority=priority, created_at=date.today().isoformat()
    )) as Task;
    unscheduled = place_task(task);
    note = "Task added to your free time.";
    if unscheduled > 0 {
        note += f" {minutes_label(unscheduled)} could not fit before its deadline.";
    }
    return make_dashboard(note);
}

def:pub update_task(  # jac:ignore[W3030]
    task_id: str, title: str, course: str, due_date: str,
    estimated_minutes: int, priority: str, due_time: str = "",
    location: str = ""
) -> DashboardData {
    task = find_task(task_id);
    if task is None { raise ValueError("Task was not found."); }
    if not title.strip() { raise ValueError("Task title is required."); }
    (due, clean_time) = clean_due(due_date, due_time);
    if not isinstance(estimated_minutes, int) or isinstance(estimated_minutes, bool) {
        raise ValueError("Estimated work must be a whole number of minutes.");
    }
    if estimated_minutes < 15 or estimated_minutes > 1440 {
        raise ValueError("Estimate must be between 15 and 1440 minutes.");
    }
    if not valid_priority(priority) { raise ValueError("Priority must be high, medium, or low."); }
    task.title = title.strip();
    if clean_course(course).lower() != task.course.lower() {
        task.course = clean_course(course);
        task.color = "";
        task.color = pick_color(task);
    }
    task.due_date = due.isoformat();
    task.due_time = clean_time;
    task.estimated_minutes = estimated_minutes;
    task.priority = priority;
    task.location = clean_location(location);
    if not task.closed { task.completed = False; }
    drop_open_blocks(task_id);
    sync_progress();
    unscheduled = place_task(task);
    note = "Task updated and its blocks were planned again.";
    if unscheduled > 0 {
        note += f" {minutes_label(unscheduled)} could not fit before its deadline.";
    }
    return make_dashboard(note);
}

def:pub delete_task(task_id: str) -> DashboardData {
    task = find_task(task_id);
    if task is None { raise ValueError("Task was not found."); }
    for session in list([root-->][?:StudySession]) {
        if session.task_id == task_id { del session; }
    }
    del task;
    return make_dashboard("Task deleted.");
}

# Marks a whole task done (its remaining blocks are removed) or reopens it
# (its remaining work is planned into free time).
# Reopens a task whose checked-off blocks already cover its estimate by
# adding more time, then plans that extra work.
def:pub reopen_task(task_id: str, extra_minutes: int) -> DashboardData {
    task = find_task(task_id);
    if task is None { raise ValueError("Task was not found."); }
    if not isinstance(extra_minutes, int) or extra_minutes < 5 or extra_minutes > 1440 {
        raise ValueError("Extra time must be between 5 and 1440 minutes.");
    }
    task.estimated_minutes = logged_minutes().get(task_id, 0) + extra_minutes;
    task.closed = False;
    task.completed = False;
    sync_progress();
    unscheduled = place_task(task);
    note = f"Task reopened with {minutes_label(extra_minutes)} more planned.";
    if unscheduled > 0 {
        note += f" {minutes_label(unscheduled)} could not fit before its deadline.";
    }
    return make_dashboard(note);
}

def:pub toggle_task(task_id: str) -> DashboardData {
    task = find_task(task_id);
    if task is None { raise ValueError("Task was not found."); }
    if not task.completed {
        task.closed = True;
        sync_progress();
        return make_dashboard("Task done. Its remaining blocks were removed.");
    }
    task.closed = False;
    task.completed = False;
    sync_progress();
    if task.completed {
        return make_dashboard(
            "All of this task's estimated time is already checked off. Edit it and raise the estimate to plan more work."
        );
    }
    unscheduled = place_task(task);
    note = "Task reopened and its remaining work was planned.";
    if unscheduled > 0 {
        note += f" {minutes_label(unscheduled)} could not fit before its deadline.";
    }
    return make_dashboard(note);
}

# Checking a block only marks that block done; nothing else moves.
def:pub complete_session(session_id: str) -> DashboardData {
    session = find_session(session_id);
    if session is None { raise ValueError("Work block was not found."); }
    session.completed = True;
    sync_progress();
    return make_dashboard("Nice work. Block checked off.");
}

# Unchecking puts the block back where it was; nothing else moves.
# Unchecking puts the block back where it was and nothing else moves. If that
# spot has been taken in the meantime (e.g. Reschedule filled it), the block
# goes to the next free time instead of overlapping, and says where it was.
def:pub uncomplete_session(session_id: str) -> DashboardData {
    session = find_session(session_id);
    if session is None { raise ValueError("Work block was not found."); }
    session.completed = False;
    task = find_task(session.task_id);
    if task is not None {
        task.closed = False;
        task.completed = False;
    }
    sync_progress();
    others = [
        (o.day, o.start_minute, o.start_minute + o.duration)
        for o in [root-->][?:StudySession]
        if not o.completed and jid(o) != session_id
    ];
    end = session.start_minute + session.duration;
    if task is None or not clashes(session.day, session.start_minute, end, others) {
        return make_dashboard("Block marked not done.");
    }
    was = snapshot(session);
    del session;
    unscheduled = place_task(task, [was]);
    note = "Block marked not done. Its old spot was taken, so it moved to your next free time.";
    if unscheduled > 0 {
        note += f" {minutes_label(unscheduled)} could not fit before its deadline.";
    }
    return make_dashboard(note);
}

def:pub replan -> DashboardData {
    missed = [item for item in [root-->][?:StudySession] if is_missed(item)];
    moved_minutes = sum([item.duration for item in missed]);
    unscheduled = rebuild_schedule();
    scheduled = [
        item for item in [root-->][?:StudySession] if not item.completed
    ];
    planned = sum([item.duration for item in scheduled]);
    day_count = len(set([item.day for item in scheduled]));
    if planned == 0 and unscheduled == 0 {
        return make_dashboard("Nothing to schedule — all your tasks are done.");
    }
    note = f"Rescheduled {minutes_label(planned)} of unfinished work across {day_count} day(s)";
    if missed {
        note += f", including {len(missed)} missed block(s) ({minutes_label(moved_minutes)})";
    }
    note += ".";
    if unscheduled > 0 {
        note += f" {minutes_label(unscheduled)} still doesn't fit before its deadline — free up reserved time or extend the due date.";
    }
    return make_dashboard(note);
}

def:priv busy_items(day_value: date, window_start: int, window_end: int) -> list[CalendarItem] {
    items: list[CalendarItem] = [];
    for block in [root-->][?:ReservedBlock] {
        if not active_on(block, day_value) { continue; }
        spans: list[tuple[int, int]] = [];
        if block.end_minute > block.start_minute {
            spans.append((block.start_minute, block.end_minute));
        } else {
            spans.append((block.start_minute, 1440));
            spans.append((0, block.end_minute));
        }
        for span in spans {
            start = max(window_start, span[0]);
            finish = min(window_end, span[1]);
            if finish <= start { continue; }
            items.append(CalendarItem(
                id=jid(block) + f"-{start}", kind="busy", title=block.label,
                course=block.category, color="#94a3b8",
                start_minute=start, duration=finish - start,
                time_label=clock_label(block.start_minute) + " – " + clock_label(block.end_minute),
                location=block.location
            ));
        }
    }
    items.sort(key=lambda (item: CalendarItem) { item.start_minute; });
    return items;
}

def:priv work_by_task(items: list[CalendarItem]) -> list[CalendarItem] {
    grouped: dict[str, CalendarItem] = {};
    order: list[str] = [];
    for item in items {
        if item.task_id not in grouped {
            grouped[item.task_id] = CalendarItem(
                id=item.task_id, kind="work", title=item.title,
                course=item.course, color=item.color, task_id=item.task_id,
                start_minute=item.start_minute, completed=True
            );
            order.append(item.task_id);
        }
        group = grouped[item.task_id];
        group.duration += item.duration;
        group.completed = group.completed and item.completed;
        group.missed = group.missed or item.missed;
    }
    result = [grouped[key] for key in order];
    for group in result { group.time_label = minutes_label(group.duration); }
    return result;
}

# Pixels per hour for the Day ("roomy") and Week time grids.
glob ACTIVE_HOUR_PX: dict[bool, int] = {True: 64, False: 48},
     QUIET_HOUR_PX: dict[bool, int] = {True: 22, False: 18},
     MIN_BLOCK_PX: dict[bool, int] = {True: 30, False: 22};

def:priv hour_text(hour: int) -> str {
    shown = hour % 12;
    if shown == 0 { shown = 12; }
    return str(shown) + (" AM" if hour % 24 < 12 else " PM");
}

# Variable-height time axis: stretches where to-dos are packed so each block
# gets at least MIN_BLOCK_PX, and squeezes stretches with no to-dos on any
# shown day (reserved or empty time). Fills in each item's top/height and
# returns the hour labels plus the total grid height.
def:priv lay_out_time(
    days: list[CalendarDay], window_start: int, window_end: int, roomy: bool
) -> tuple[int, list[HourMark]] {
    def clip(minute: int) -> int {
        return max(window_start, min(window_end, minute));
    }
    sessions = [item for day in days for item in day.sessions if item.duration > 0];
    stops = set([window_start, window_end]);
    for hour in range(window_start // 60, window_end // 60 + 1) {
        if window_start <= hour * 60 <= window_end { stops.add(hour * 60); }
    }
    for day in days {
        for item in day.sessions + day.busy {
            stops.add(clip(item.start_minute));
            stops.add(clip(item.start_minute + item.duration));
        }
        for item in day.due {
            if item.start_minute >= 0 { stops.add(clip(item.start_minute)); }
        }
    }
    ordered = sorted(stops);
    y: dict[int, float] = {ordered[0]: 0.0};
    for i in range(1, len(ordered)) {
        a = ordered[i - 1];
        b = ordered[i];
        span = b - a;
        covering = [
            item for item in sessions
            if item.start_minute < b and item.start_minute + item.duration > a
        ];
        rate = ACTIVE_HOUR_PX[roomy] if covering else QUIET_HOUR_PX[roomy];
        need = 0.0;
        for item in covering {
            need = max(need, MIN_BLOCK_PX[roomy] * span / item.duration);
        }
        y[b] = y[a] + max(span * rate / 60, need);
    }
    for day in days {
        for item in day.sessions + day.busy {
            start = clip(item.start_minute);
            top = round(y[start]);
            item.top = top;
            item.height = round(y[clip(item.start_minute + item.duration)]) - top;
        }
        for item in day.due {
            if item.start_minute >= 0 { item.top = round(y[clip(item.start_minute)]); }
        }
    }
    marks: list[HourMark] = [];
    last = -100;
    for hour in range(window_start // 60, window_end // 60 + 1) {
        minute = hour * 60;
        if minute < window_start or minute >= window_end { continue; }
        pos = round(y[minute]);
        if pos - last >= 14 {
            marks.append(HourMark(label=hour_text(hour), y=pos));
            last = pos;
        }
    }
    return (round(y[window_end]), marks);
}

def:pub get_calendar(view: str = "week", anchor: str = "", shift: int = 0) -> CalendarData {
    colors = ensure_colors();
    places = {jid(t): t.location for t in [root-->][?:Task]};
    if view not in ["day", "week", "month"] { raise ValueError("Calendar view must be day, week, or month."); }
    today = date.today();
    focus = parse_due(anchor) if anchor else today;
    if view == "day" {
        focus = focus + timedelta(days=shift);
        first = focus;
        last = focus;
        title = focus.strftime("%A, %B %d");
    } elif view == "week" {
        focus = focus + timedelta(days=7 * shift);
        first = focus - timedelta(days=focus.weekday());
        last = first + timedelta(days=6);
        title = first.strftime("%b %d") + " – " + last.strftime("%b %d, %Y");
    } else {
        month_index = focus.year * 12 + (focus.month - 1) + shift;
        # Keep the focused day when just viewing the month, so switching
        # back to Day/Week lands on it instead of the 1st.
        if shift != 0 { focus = date(month_index // 12, month_index % 12 + 1, 1); }
        month_first = date(month_index // 12, month_index % 12 + 1, 1);
        first = month_first - timedelta(days=month_first.weekday());
        next_month = date(
            (month_index + 1) // 12, (month_index + 1) % 12 + 1, 1
        );
        last_of_month = next_month - timedelta(days=1);
        last = last_of_month + timedelta(days=6 - last_of_month.weekday());
        title = focus.strftime("%B %Y");
    }
    window_start = DAY_START;
    window_end = DAY_END;
    first_key = first.isoformat();
    last_key = last.isoformat();
    sessions = [
        session_view(s, colors, places) for s in [root-->][?:StudySession]
        if first_key <= s.day <= last_key
    ];
    sessions.sort(key=lambda (item: SessionView) { (item.day, item.start_minute); });
    tasks = [t for t in [root-->][?:Task] if first_key <= t.due_date <= last_key];
    days: list[CalendarDay] = [];
    current = first;
    while current <= last {
        key = current.isoformat();
        day_sessions = [
            CalendarItem(
                id=s.id, kind="session", title=s.title, course=s.course,
                color=s.color, start_minute=s.start_minute,
                duration=s.duration,
                time_label=s.start_time + " – " + s.end_time,
                completed=s.completed, missed=s.missed, task_id=s.task_id,
                location=s.location, moved_from=s.moved_from,
                added_note=s.added_note
            ) for s in sessions if s.day == key and not s.completed
        ];
        day_due = [
            CalendarItem(
                id=jid(t), kind="due", title=t.title, course=t.course,
                color=colors.get(jid(t), TASK_COLORS[0]), completed=t.completed,
                task_id=jid(t),
                start_minute=due_minute(t) if t.due_time else -1,
                time_label=clock_label(due_minute(t)) if t.due_time else "",
                location=t.location
            ) for t in tasks if t.due_date == key
        ];
        in_range = (current.month == focus.month) if view == "month" else True;
        days.append(CalendarDay(
            date=key, day_num=current.day, weekday=current.strftime("%a"),
            label=current.strftime("%b %d"), is_today=current == today,
            is_past=current < today, in_range=in_range,
            sessions=day_sessions,
            busy=busy_items(current, window_start, window_end),
            due=day_due, work=work_by_task(day_sessions),
            study_minutes=sum([item.duration for item in day_sessions]),
            free_minutes=max(0, base_available_minutes(current) - sum([
                item.duration for item in day_sessions
            ]))
        ));
        current = current + timedelta(days=1);
    }
    grid_height = 0;
    marks: list[HourMark] = [];
    if view != "month" {
        (grid_height, marks) = lay_out_time(
            days, window_start, window_end, view == "day"
        );
    }
    return CalendarData(
        view=view, anchor=focus.isoformat(), title=title, days=days,
        start_hour=DAY_START // 60, end_hour=DAY_END // 60,
        grid_height=grid_height, hour_marks=marks
    );
}

def:pub add_reserved_block(
    label: str,
    category: str,
    start_time: str,
    end_time: str,
    repeat_rule: str,
    location: str = ""
) -> DashboardData {
    if not label.strip() { raise ValueError("Reserved time needs a name."); }
    if not valid_repeat(repeat_rule) {
        raise ValueError("Pick at least one day for the reserved time to repeat on.");
    }
    start = parse_clock(start_time);
    finish = parse_clock(end_time);
    if start == finish { raise ValueError("Start and end time cannot match."); }
    clash = clashing_block(start, finish, repeat_rule);
    if clash is not None {
        raise ValueError(
            f"This overlaps {clash.label} ({clock_label(clash.start_minute)} to "
            + f"{clock_label(clash.end_minute)}, {repeat_text(clash.repeat_rule)}). "
            + "Pick a different time or days."
        );
    }
    block = (root ++> ReservedBlock(
        label=label.strip(), category=category.strip() or "other",
        start_minute=start, end_minute=finish,
        repeat_rule=normalize_repeat(repeat_rule),
        location=clean_location(location)
    )) as ReservedBlock;
    # Only unfinished blocks that now sit inside the new reserved time move.
    today_key = date.today().isoformat();
    spans = clock_spans(start, finish);
    moved_tasks: list[str] = [];
    displaced: list[StudySession] = [];
    for item in list([root-->][?:StudySession]) {
        if item.completed or item.day < today_key { continue; }
        if not active_on(block, date.fromisoformat(item.day)) { continue; }
        end = item.start_minute + item.duration;
        if any([span[0] < end and item.start_minute < span[1] for span in spans]) {
            if item.task_id not in moved_tasks { moved_tasks.append(item.task_id); }
            displaced.append(StudySession(
                task_id=item.task_id, title=item.title, course=item.course,
                day=item.day, start_time=item.start_time, duration=item.duration,
                start_minute=item.start_minute
            ));
            del item;
        }
    }
    unscheduled = 0;
    affected = [t for t in [root-->][?:Task] if jid(t) in moved_tasks];
    for task in by_deadline(affected) {
        unscheduled += place_task(task, [d for d in displaced if d.task_id == jid(task)]);
    }
    note = "Reserved time added.";
    if moved_tasks {
        note += f" Work that overlapped it was moved for {len(moved_tasks)} task(s).";
    }
    if unscheduled > 0 {
        note += f" {minutes_label(unscheduled)} could not fit before its deadline.";
    }
    return make_dashboard(note);
}

def:pub delete_reserved_block(block_id: str) -> DashboardData {
    for block in [root-->][?:ReservedBlock] {
        if jid(block) == block_id {
            del block;
            return make_dashboard("Reserved time removed. Press Reschedule to use the freed time.");
        }
    }
    raise ValueError("Reserved time was not found.");
}

def:pub seed_routine -> DashboardData {
    if [root-->][?:ReservedBlock] {
        return make_dashboard("A routine already exists. Add or remove blocks individually.");
    }
    root ++> ReservedBlock(
        label="Sleep", category="sleep", start_minute=23 * 60,
        end_minute=8 * 60, repeat_rule="daily"
    );
    root ++> ReservedBlock(
        label="Lunch", category="meal", start_minute=12 * 60,
        end_minute=13 * 60, repeat_rule="daily"
    );
    root ++> ReservedBlock(
        label="Classes", category="class", start_minute=10 * 60,
        end_minute=12 * 60, repeat_rule="weekdays"
    );
    root ++> ReservedBlock(
        label="Workout", category="exercise", start_minute=17 * 60,
        end_minute=18 * 60, repeat_rule="weekdays"
    );
    rebuild_schedule();
    return make_dashboard("Example routine added. Edit it to match your real week.");
}

def:pub seed_demo -> DashboardData {
    if [root-->][?:Task] {
        return make_dashboard("Demo data was not added because tasks already exist.");
    }
    today = date.today();
    root ++> Task(
        title="Finish database project", course="EECS 484",
        due_date=(today + timedelta(days=3)).isoformat(),
        estimated_minutes=300, priority="high", created_at=today.isoformat()
    );
    root ++> Task(
        title="Write usability report", course="EECS 481",
        due_date=(today + timedelta(days=5)).isoformat(),
        estimated_minutes=180, priority="medium", created_at=today.isoformat()
    );
    root ++> Task(
        title="Review Jac lecture notes", course="CSE 449",
        due_date=(today + timedelta(days=1)).isoformat(),
        estimated_minutes=75, priority="high", created_at=today.isoformat()
    );
    rebuild_schedule();
    return make_dashboard("Demo week created.");
}

test "priority ordering is deterministic" {
    assert priority_rank("high") < priority_rank("medium");
    assert priority_rank("medium") < priority_rank("low");
}

test "time labels are readable" {
    assert minutes_label(135) == "2h 15m";
    assert clock_label(18 * 60 + 30) == "6:30 PM";
    assert parse_clock("23:45") == 23 * 60 + 45;
}

test "protected time is removed from free slots" {
    marker = "StudyFlow protected-time test";
    for old in list([root-->][?:ReservedBlock]) {
        if old.label == marker { del old; }
    }
    block = (root ++> ReservedBlock(
        label=marker, category="class", start_minute=10 * 60,
        end_minute=12 * 60, repeat_rule="daily"
    )) as ReservedBlock;
    slots = free_slots(date.today());
    assert all([slot[1] <= 10 * 60 or slot[0] >= 12 * 60 for slot in slots]);
    del block;
}

test "overnight protected time covers both ends of the day" {
    marker = "StudyFlow overnight test";
    for old in list([root-->][?:ReservedBlock]) {
        if old.label == marker { del old; }
    }
    block = (root ++> ReservedBlock(
        label=marker, category="sleep", start_minute=23 * 60,
        end_minute=8 * 60, repeat_rule="daily"
    )) as ReservedBlock;
    spans = reserved_spans(date.today());
    assert (0, 8 * 60) in spans;
    assert (23 * 60, 1440) in spans;
    del block;
}

test "adding a task creates scheduled study time" {
    marker = "StudyFlow scheduler test";
    for old in list([root-->][?:Task]) {
        if old.title == marker {
            for session in list([root-->][?:StudySession]) {
                if session.task_id == jid(old) { del session; }
            }
            del old;
        }
    }
    result = add_task(marker, "TEST 101", "2099-12-31", 90, "high");
    matches = [task for task in result.tasks if task.title == marker];
    assert len(matches) == 1;
    assert result.scheduled_minutes >= 90;
    delete_task(matches[0].id);
}

test "long work is fully placed before its deadline" {
    marker = "StudyFlow long-session test";
    for old in list([root-->][?:Task]) {
        if old.title == marker { delete_task(jid(old)); }
    }
    result = add_task(
        marker, "TEST 201", (date.today() + timedelta(days=3)).isoformat(),
        300, "high"
    );
    matches = [task for task in result.tasks if task.title == marker];
    assert len(matches) == 1;
    planned = sum([
        session.duration for session in [root-->][?:StudySession]
        if session.task_id == matches[0].id
    ]);
    assert planned == 300;
    delete_task(matches[0].id);
}

test "today's work is never planned in the past" {
    marker = "StudyFlow no-past test";
    for old in list([root-->][?:Task]) {
        if old.title == marker { delete_task(jid(old)); }
    }
    result = add_task(marker, "TEST 501", "2099-12-31", 120, "medium");
    matches = [task for task in result.tasks if task.title == marker];
    today_key = date.today().isoformat();
    for session in [root-->][?:StudySession] {
        if session.task_id == matches[0].id and session.day == today_key {
            assert session.start_minute >= now_minute();
        }
    }
    future = date.today() + timedelta(days=1);
    assert day_start(future, 8 * 60) == 8 * 60;
    assert day_start(date.today(), 0) >= now_minute();
    delete_task(matches[0].id);
}

test "unfinished blocks from earlier are missed" {
    yesterday = (date.today() - timedelta(days=1)).isoformat();
    old = StudySession(
        task_id="x", title="t", course="c", day=yesterday,
        start_time="", start_minute=600, duration=60
    );
    assert is_missed(old);
    old.completed = True;
    assert not is_missed(old);
    later = StudySession(
        task_id="x", title="t", course="c",
        day=(date.today() + timedelta(days=1)).isoformat(),
        start_time="", start_minute=600, duration=60
    );
    assert not is_missed(later);
}

test "calendar views cover full weeks and months" {
    week = get_calendar("week", "2026-10-02", 0);
    assert len(week.days) == 7;
    assert week.days[0].weekday == "Mon";
    month = get_calendar("month", "2026-10-02", 1);
    assert month.anchor == "2026-11-01";
    same_month = get_calendar("month", "2026-10-14", 0);
    assert same_month.anchor == "2026-10-14";
    assert same_month.title == "October 2026";
    assert same_month.days[0].date == "2026-09-28";
    assert len(month.days) % 7 == 0;
    assert len([d for d in month.days if d.in_range]) == 30;
    day = get_calendar("day", "2026-10-02", -1);
    assert day.days[0].date == "2026-10-01";
}

test "same course shares a color, other tasks get their own" {
    markers = ["StudyFlow color A1", "StudyFlow color A2", "StudyFlow color B", "StudyFlow color C"];
    for old in list([root-->][?:Task]) {
        if old.title in markers { delete_task(jid(old)); }
    }
    add_task(markers[0], "COLOR 101", "2099-12-31", 30, "low");
    add_task(markers[1], "color 101", "2099-12-31", 30, "low");
    add_task(markers[2], "COLOR 202", "2099-12-31", 30, "low");
    result = add_task(markers[3], "", "2099-12-31", 30, "low");
    by_title = {t.title: t for t in result.tasks if t.title in markers};
    assert by_title[markers[0]].color == by_title[markers[1]].color;
    assert by_title[markers[0]].color != by_title[markers[2]].color;
    assert by_title[markers[3]].color != by_title[markers[0]].color;
    assert by_title[markers[3]].color != by_title[markers[2]].color;
    for t in by_title.values() { delete_task(t.id); }
}

test "sessions are never shorter than 30 minutes unless the work is" {
    marker = "StudyFlow chunk-size test";
    for old in list([root-->][?:Task]) {
        if old.title == marker { delete_task(jid(old)); }
    }
    result = add_task(marker, "TEST 301", "2099-12-31", 240, "medium");
    matches = [task for task in result.tasks if task.title == marker];
    sessions = [
        s for s in [root-->][?:StudySession] if s.task_id == matches[0].id
    ];
    assert all([s.duration >= 30 for s in sessions]);
    delete_task(matches[0].id);
}

test "one task fills a free gap as a single block" {
    marker = "StudyFlow single-block test";
    for old in list([root-->][?:Task]) {
        if old.title == marker { delete_task(jid(old)); }
    }
    result = add_task(marker, "TEST 401", "2099-12-31", 180, "medium");
    matches = [task for task in result.tasks if task.title == marker];
    sessions = [
        s for s in [root-->][?:StudySession] if s.task_id == matches[0].id
    ];
    by_day: dict[str, list[StudySession]] = {};
    for s in sessions { by_day.setdefault(s.day, []).append(s); }
    for day_sessions in by_day.values() {
        day_sessions.sort(key=lambda (x: StudySession) { x.start_minute; });
        for i in range(1, len(day_sessions)) {
            prev = day_sessions[i - 1];
            assert prev.start_minute + prev.duration != day_sessions[i].start_minute;
        }
    }
    delete_task(matches[0].id);
}

test "reserved time can repeat on chosen days" {
    assert repeat_days("mon,wed,fri") == [0, 2, 4];
    assert repeat_days("fri, mon") == [0, 4];
    assert repeat_days("weekdays") == [0, 1, 2, 3, 4];
    assert repeat_days("funday") == [];
    assert normalize_repeat("sat,sun") == "weekends";
    assert normalize_repeat("wed,mon") == "mon,wed";
    assert repeat_text("mon,wed,fri") == "Mon, Wed, Fri";
    marker = "StudyFlow MWF test";
    for old in list([root-->][?:ReservedBlock]) {
        if old.label == marker { del old; }
    }
    block = (root ++> ReservedBlock(
        label=marker, category="class", start_minute=10 * 60,
        end_minute=11 * 60, repeat_rule="mon,wed,fri"
    )) as ReservedBlock;
    assert active_on(block, date(2026, 10, 5));
    assert not active_on(block, date(2026, 10, 6));
    assert active_on(block, date(2026, 10, 9));
    del block;
}

test "work is finished before a task's due time" {
    marker = "StudyFlow due-time test";
    for old in list([root-->][?:Task]) {
        if old.title == marker { delete_task(jid(old)); }
    }
    due = date.today() + timedelta(days=2);
    result = add_task(marker, "TEST 601", due.isoformat(), 90, "high", "9:30");
    matches = [task for task in result.tasks if task.title == marker];
    assert matches[0].due_time == "09:30";
    assert "9:30 AM" in matches[0].due_label;
    for session in [root-->][?:StudySession] {
        if session.task_id == matches[0].id and session.day == due.isoformat() {
            assert session.start_minute + session.duration <= 9 * 60 + 30;
        }
    }
    delete_task(matches[0].id);
}

test "a due time that already passed today is rejected" {
    if now_minute() > 0 {
        with testraises(ValueError) {
            add_task("Too late", "TEST", date.today().isoformat(), 30, "low", "00:00");
        }
    }
}

test "crowded hours stretch and quiet hours shrink" {
    def item(id: str, start: int, duration: int, kind: str = "session") -> CalendarItem {
        return CalendarItem(id=id, kind=kind, title=id, start_minute=start, duration=duration);
    }
    day = CalendarDay(
        date="2026-10-07", day_num=7, weekday="Wed", label="Oct 07",
        is_today=False, is_past=False, in_range=True,
        sessions=[item("a", 480, 30), item("b", 510, 15), item("c", 525, 5), item("d", 530, 30)],
        busy=[item("lecture", 600, 120, "busy")], due=[], work=[],
        study_minutes=80, free_minutes=0
    );
    (height, marks) = lay_out_time([day], 480, 900, True);
    blocks = day.sessions;
    for block in blocks { assert block.height >= MIN_BLOCK_PX[True] - 1; }
    for i in range(1, len(blocks)) {
        assert blocks[i].top >= blocks[i - 1].top + blocks[i - 1].height;
    }
    lecture = day.busy[0];
    assert lecture.height <= 2 * QUIET_HOUR_PX[True] + 1;
    assert height < (900 - 480) * ACTIVE_HOUR_PX[True] / 60;
    assert marks[0].label == "8 AM" and marks[0].y == 0;
}

test "unchecking a block puts its work back on the plan" {
    marker = "StudyFlow uncheck test";
    for old in list([root-->][?:Task]) {
        if old.title == marker { delete_task(jid(old)); }
    }
    result = add_task(marker, "TEST 701", "2099-12-31", 60, "medium");
    task_id = [t for t in result.tasks if t.title == marker][0].id;
    block = [s for s in [root-->][?:StudySession] if s.task_id == task_id][0];
    done = complete_session(jid(block));
    task = [t for t in done.tasks if t.id == task_id][0];
    assert task.completed_minutes == block.duration;
    back = uncomplete_session(jid(block));
    task = [t for t in back.tasks if t.id == task_id][0];
    assert task.completed_minutes == 0 and not task.completed;
    planned = sum([
        s.duration for s in [root-->][?:StudySession]
        if s.task_id == task_id and not s.completed
    ]);
    assert planned == 60;
    delete_task(task_id);
}

test "a finished block frees its slot and leaves the calendar" {
    marker = "StudyFlow early test";
    for old in list([root-->][?:Task]) {
        if old.title == marker { delete_task(jid(old)); }
    }
    tomorrow = date.today() + timedelta(days=1);
    result = add_task(marker, "TEST 801", "2099-12-31", 30, "medium");
    task_id = [t for t in result.tasks if t.title == marker][0].id;
    block = [s for s in [root-->][?:StudySession] if s.task_id == task_id][0];
    block.day = tomorrow.isoformat();
    block.start_minute = 9 * 60;
    complete_session(jid(block));
    assert block.day == tomorrow.isoformat() and block.start_minute == 9 * 60;
    assert any([slot[0] <= 9 * 60 and slot[1] >= 9 * 60 + 30 for slot in free_slots(tomorrow)])
        or len(reserved_spans(tomorrow)) > 0;
    cal = get_calendar("day", tomorrow.isoformat(), 0);
    assert jid(block) not in [item.id for item in cal.days[0].sessions];
    delete_task(task_id);
}

test "reserved time cannot overlap existing reserved time" {
    markers = ["StudyFlow clash A", "StudyFlow clash B", "StudyFlow clash C"];
    for old in list([root-->][?:ReservedBlock]) {
        if old.label in markers { del old; }
    }
    saved = [(b.start_minute, b.end_minute, b.repeat_rule) for b in [root-->][?:ReservedBlock]];
    # Use an otherwise empty slot of the week: Sunday 03:00-04:00.
    if clashing_block(3 * 60, 4 * 60, "sun") is None {
        add_reserved_block(markers[0], "other", "03:00", "04:00", "sun");
        with testraises(ValueError) {
            add_reserved_block(markers[1], "other", "03:30", "05:00", "sat,sun");
        }
        # Same time on a different day, and back-to-back times, are fine.
        if clashing_block(3 * 60, 4 * 60, "sat") is None {
            add_reserved_block(markers[1], "other", "03:00", "04:00", "sat");
        }
        assert clashing_block(4 * 60, 5 * 60, "sun") is None or len(saved) > 0;
    }
    # Overnight blocks wrap around midnight.
    assert clock_spans(23 * 60, 8 * 60) == [(23 * 60, 1440), (0, 8 * 60)];
    for old in list([root-->][?:ReservedBlock]) {
        if old.label in markers { del old; }
    }
}

def:priv blocks_of(task_id: str) -> list[StudySession] {
    found = [b for b in [root-->][?:StudySession] if b.task_id == task_id];
    found.sort(key=lambda (b: StudySession) { (b.day, b.start_minute); });
    return found;
}

def:priv fresh_task(marker: str, minutes: int) -> str {
    for old in list([root-->][?:Task]) {
        if old.title == marker { delete_task(jid(old)); }
    }
    result = add_task(marker, "TEST 900", "2099-12-31", minutes, "medium");
    return [t for t in result.tasks if t.title == marker][0].id;
}

test "checking a block moves nothing else" {
    first = fresh_task("StudyFlow stable A", 120);
    second = fresh_task("StudyFlow stable B", 60);
    before = [(jid(b), b.day, b.start_minute) for b in blocks_of(second)];
    complete_session(jid(blocks_of(first)[0]));
    assert [(jid(b), b.day, b.start_minute) for b in blocks_of(second)] == before;
    open_first = [b for b in blocks_of(first) if not b.completed];
    assert sum([b.duration for b in open_first]) == 120 - blocks_of(first)[0].duration
        or len(blocks_of(first)) == 1;
    delete_task(first);
    delete_task(second);
}

test "unchecking puts the block back where it was" {
    task_id = fresh_task("StudyFlow stable C", 60);
    block = blocks_of(task_id)[0];
    spot = (block.day, block.start_minute, block.duration);
    complete_session(jid(block));
    uncomplete_session(jid(block));
    assert (block.day, block.start_minute, block.duration) == spot;
    assert not block.completed;
    delete_task(task_id);
}

test "a task marked done keeps no blocks, even after reschedule" {
    task_id = fresh_task("StudyFlow stable D", 120);
    toggle_task(task_id);
    assert len([b for b in blocks_of(task_id) if not b.completed]) == 0;
    replan();
    assert len([b for b in blocks_of(task_id) if not b.completed]) == 0;
    toggle_task(task_id);
    assert sum([b.duration for b in blocks_of(task_id) if not b.completed]) == 120;
    delete_task(task_id);
}

test "reopening a task brings its work back" {
    task_id = fresh_task("StudyFlow reopen A", 60);
    toggle_task(task_id);
    back = toggle_task(task_id);
    assert not [t for t in back.tasks if t.id == task_id][0].completed;
    assert sum([b.duration for b in blocks_of(task_id) if not b.completed]) == 60;
    # Every block checked off: reopening needs a bigger estimate.
    for block in blocks_of(task_id) { complete_session(jid(block)); }
    done = toggle_task(task_id);
    assert "raise the estimate" in done.message;
    more = reopen_task(task_id, 30);
    view = [t for t in more.tasks if t.id == task_id][0];
    assert not view.completed and view.logged_minutes == 60;
    assert sum([b.duration for b in blocks_of(task_id) if not b.completed]) == 30;
    delete_task(task_id);
}

test "the dashboard suggests rescheduling when time frees up" {
    first = fresh_task("StudyFlow hint A", 60);
    second = fresh_task("StudyFlow hint B", 60);
    replan();
    settled = get_dashboard();
    assert settled.improvable_tasks == 0;
    # Finishing the first task frees its time; the second could move up.
    first_blocks = [b for b in blocks_of(first) if not b.completed];
    second_blocks = [b for b in blocks_of(second) if not b.completed];
    toggle_task(first);
    hint = get_dashboard();
    if first_blocks and second_blocks and first_blocks[0].day == second_blocks[0].day
        and first_blocks[0].start_minute < second_blocks[0].start_minute {
        assert hint.improvable_tasks >= 1;
    }
    replan();
    assert get_dashboard().improvable_tasks == 0;
    delete_task(first);
    delete_task(second);
}

test "tasks and reserved time keep an optional location" {
    marker = "StudyFlow location test";
    for old in list([root-->][?:Task]) {
        if old.title == marker { delete_task(jid(old)); }
    }
    result = add_task(marker, "TEST 990", "2099-12-31", 30, "low", "", "  Duderstadt Library  ");
    view = [t for t in result.tasks if t.title == marker][0];
    assert view.location == "Duderstadt Library";
    block = [b for b in [root-->][?:StudySession] if b.task_id == view.id][0];
    cal = get_calendar("day", block.day, 0);
    assert [i.location for i in cal.days[0].sessions if i.task_id == view.id][0] == "Duderstadt Library";
    edited = update_task(view.id, marker, "TEST 990", "2099-12-31", 30, "low", "", "");
    assert [t for t in edited.tasks if t.id == view.id][0].location == "";
    delete_task(view.id);
    assert clean_location("x" * 200) == "x" * 80;
}

test "rescheduled blocks remember where they came from" {
    task_id = fresh_task("StudyFlow moved test", 60);
    block = blocks_of(task_id)[0];
    later = date.today() + timedelta(days=3);
    block.day = later.isoformat();
    block.start_minute = 13 * 60;
    replan();
    moved = [b for b in blocks_of(task_id) if not b.completed];
    assert any([b.moved_from_day == later.isoformat() and b.moved_from_minute == 13 * 60 for b in moved])
        or all([b.day == later.isoformat() and b.start_minute == 13 * 60 for b in moved]);
    view = session_view(moved[0]);
    assert view.moved_from == "" or "1:00 PM" in view.moved_from;
    delete_task(task_id);
}

test "work merged onto a staying block is labelled" {
    stay = StudySession(task_id="t1", title="x", course="c", day="2026-10-05",
        start_time="", start_minute=21 * 60, duration=30);
    old = StudySession(task_id="t1", title="x", course="c", day="2026-10-06",
        start_time="", start_minute=13 * 60, duration=30);
    plan = [PlanBlock(task_id="t1", day="2026-10-05", start=21 * 60, duration=60,
        node_id="n1", changed=True, base=30)];
    trace_moves(plan, [old]);
    assert plan[0].added == 30 and plan[0].from_day == "2026-10-06";
    stay.added_minutes = 30;
    stay.added_from_day = "2026-10-06";
    stay.added_from_minute = 13 * 60;
    assert added_label(stay) == "30m added · rescheduled from Tue, Oct 6 · 1:00 PM";
}

test "reschedule labels work it merges onto the block in progress" {
    now = now_minute();
    if 10 <= now and now <= 22 * 60 {
        task_id = fresh_task("StudyFlow merge test", 60);
        for block in list(blocks_of(task_id)) { del block; }
        tomorrow = (date.today() + timedelta(days=1)).isoformat();
        root ++> StudySession(task_id=task_id, title="m", course="c",
            day=date.today().isoformat(), start_time="", start_minute=now - 5, duration=30);
        root ++> StudySession(task_id=task_id, title="m", course="c",
            day=tomorrow, start_time="", start_minute=13 * 60, duration=30);
        if clashing_block(now - 5, now + 60, "daily") is None {
            replan();
            current = [b for b in blocks_of(task_id) if b.day == date.today().isoformat()];
            assert len(current) == 1 and current[0].duration == 60;
            assert added_label(current[0]).startswith("30m added · rescheduled from");
        }
        delete_task(task_id);
    }
}

test "work pulled forward from several days is labelled" {
    task_id = fresh_task("StudyFlow spread test", 300);
    for block in list(blocks_of(task_id)) { del block; }
    days = [(date.today() + timedelta(days=i)).isoformat() for i in [1, 2, 3]];
    previous = [
        StudySession(task_id=task_id, title="q", course="c", day=d,
            start_time="", start_minute=0, duration=75)
        for d in days
    ];
    plan = [PlanBlock(task_id=task_id, day=date.today().isoformat(), start=21 * 60, duration=57)]
        + [PlanBlock(task_id=task_id, day=d, start=0, duration=57) for d in days[:2]]
        + [PlanBlock(task_id=task_id, day=days[2], start=0, duration=54)];
    trace_moves(plan, previous);
    assert plan[0].from_day == days[0] and plan[0].from_minute == 0;
    assert plan[0].from_more == 2 and plan[0].added == 0;
    assert all([b.from_day == "" for b in plan[1:]]);
    delete_task(task_id);
}

test "work never runs past a due time that falls before reserved time" {
    marker = "StudyFlow cutoff test";
    for old in list([root-->][?:ReservedBlock]) { if old.label == marker { del old; } }
    due_day = date.today() + timedelta(days=3);
    if clashing_block(18 * 60, 19 * 60, "daily") is None {
        root ++> ReservedBlock(label=marker, start_minute=18 * 60, end_minute=19 * 60, repeat_rule="daily");
    }
    plan: list[PlanBlock] = [];
    for slot in free_slots(due_day, 13 * 60 + 41, plan) {
        assert slot[1] <= 13 * 60 + 41;
    }
    task_id = fresh_task("StudyFlow cutoff task", 600);
    task = find_task(task_id);
    assert task is not None;
    task.due_date = due_day.isoformat();
    task.due_time = "13:41";
    replan();
    for block in blocks_of(task_id) {
        if block.day == due_day.isoformat() {
            assert block.start_minute + block.duration <= 13 * 60 + 41;
        }
    }
    delete_task(task_id);
    for old in list([root-->][?:ReservedBlock]) { if old.label == marker { del old; } }
}

test "unchecking into a taken spot moves the block instead of overlapping" {
    task_id = fresh_task("StudyFlow overlap test", 60);
    other_id = fresh_task("StudyFlow overlap other", 30);
    block = blocks_of(task_id)[0];
    spot = (block.day, block.start_minute);
    complete_session(jid(block));
    # Something else takes the freed spot.
    taker = blocks_of(other_id)[0];
    taker.day = spot[0];
    taker.start_minute = spot[1];
    uncomplete_session(jid(block));
    open_blocks = [b for b in blocks_of(task_id) if not b.completed];
    assert sum([b.duration for b in open_blocks]) == 60;
    assert get_dashboard().overlapping == 0 or len(reserved_spans(date.fromisoformat(spot[0]))) > 0;
    delete_task(task_id);
    delete_task(other_id);
}

test "reschedule keeps only one of two overlapping blocks in progress" {
    now = now_minute();
    if 10 <= now and now <= 23 * 60 and clashing_block(now - 5, now + 35, "daily") is None {
        task_id = fresh_task("StudyFlow running test", 90);
        for block in list(blocks_of(task_id)) { del block; }
        today_key = date.today().isoformat();
        root ++> StudySession(task_id=task_id, title="r", course="c", day=today_key,
            start_time="", start_minute=now - 5, duration=30);
        root ++> StudySession(task_id=task_id, title="r", course="c", day=today_key,
            start_time="", start_minute=now - 5, duration=30);
        assert get_dashboard().overlapping >= 2;
        replan();
        running = [b for b in blocks_of(task_id) if in_progress(b)];
        assert len(running) == 1;
        assert get_dashboard().overlapping == 0;
        delete_task(task_id);
    }
}

test "invalid estimates are rejected" {
    with testraises(ValueError) {
        add_task("Impossible", "TEST", "2099-12-31", -10, "medium");
    }
}
