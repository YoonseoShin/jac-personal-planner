import from datetime { date, timedelta }

obj TaskView {
    has id: str, title: str, course: str, due_date: str,
        estimated_minutes: int, completed_minutes: int,
        priority: str, completed: bool, progress: int, due_label: str,
        color: str = "#4f46e5", days_left: int = 0;
}

obj SessionView {
    has id: str, task_id: str, title: str, course: str, day: str,
        start_time: str, start_minute: int, duration: int,
        priority: str, completed: bool, color: str = "#4f46e5",
        end_time: str = "", missed: bool = False;
}

obj DayLoad {
    has day: str, label: str, minutes: int, capacity: int;
}

obj ReservedBlockView {
    has id: str, label: str, category: str, start_time: str,
        end_time: str, repeat_rule: str, repeat_label: str = "",
        days: list[str] = [];
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
        due_this_week: int = 0;
}

obj CalendarItem {
    has id: str, kind: str, title: str, course: str = "", color: str = "",
        start_minute: int = 0, duration: int = 0, time_label: str = "",
        completed: bool = False, missed: bool = False, task_id: str = "";
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
        start_hour: int, end_hour: int;
}

node Task {
    has title: str, due_date: str, course: str = "General",
        estimated_minutes: int = 60, completed_minutes: int = 0,
        priority: str = "medium", completed: bool = False,
        created_at: str = "";
}

node StudySession {
    has task_id: str, title: str, course: str, day: str,
        start_time: str, duration: int, start_minute: int = 1080,
        priority: str = "medium",
        completed: bool = False;
}

node ReservedBlock {
    has label: str, category: str = "other", start_minute: int = 0,
        end_minute: int = 0, repeat_rule: str = "daily";
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

glob COURSE_COLORS: list[str] = [
    "#4f46e5", "#0891b2", "#059669", "#d97706",
    "#db2777", "#7c3aed", "#ea580c", "#2563eb"
];

def:priv course_color(course: str) -> str {
    total = 0;
    for ch in course.strip().upper() { total = (total * 31 + ord(ch)) % 100003; }
    return COURSE_COLORS[total % len(COURSE_COLORS)];
}

def:priv valid_priority(value: str) -> bool {
    return value in ["high", "medium", "low"];
}

def:priv clean_course(value: str) -> str {
    return value.strip() if value.strip() else "General";
}

def:priv parse_due(value: str) -> date {
    try {
        return date.fromisoformat(value);
    } except ValueError {
        raise ValueError("Due date must use YYYY-MM-DD.");
    }
}

def:priv get_settings_node -> PlannerSettings {
    found = [root-->][?:PlannerSettings];
    settings = found[0] if found else (
        (root ++> PlannerSettings()) as PlannerSettings
    );
    if not settings.availability_initialized {
        settings.start_hour = 8;
        settings.end_hour = 23;
        settings.availability_initialized = True;
    }
    return settings;
}

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
        raise ValueError("Time must use HH:MM.");
    }
    try {
        hour = int(parts[0]);
        minute = int(parts[1]);
    } except ValueError {
        raise ValueError("Time must use HH:MM.");
    }
    if hour < 0 or hour > 23 or minute < 0 or minute > 59 {
        raise ValueError("Time must use a valid 24-hour clock value.");
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

def:priv reserved_spans(day_value: date) -> list[tuple[int, int]] {
    spans: list[tuple[int, int]] = [];
    for block in [root-->][?:ReservedBlock] {
        if not active_on(block, day_value) { continue; }
        if block.end_minute > block.start_minute {
            spans.append((block.start_minute, block.end_minute));
        } else {
            spans.append((block.start_minute, 1440));
            spans.append((0, block.end_minute));
        }
    }
    return spans;
}

def:priv base_available_minutes(day_value: date) -> int {
    settings = get_settings_node();
    start = settings.start_hour * 60;
    finish = settings.end_hour * 60;
    occupied = reserved_spans(day_value);
    occupied.sort(key=lambda (span: tuple[int, int]) { span[0]; });
    cursor = start;
    available = 0;
    for span in occupied {
        blocked_start = max(start, span[0]);
        blocked_end = min(finish, span[1]);
        if blocked_end <= cursor { continue; }
        if blocked_start > cursor { available += blocked_start - cursor; }
        cursor = max(cursor, blocked_end);
    }
    if cursor < finish { available += finish - cursor; }
    return available;
}

def:priv free_slots(day_value: date) -> list[tuple[int, int]] {
    settings = get_settings_node();
    start = settings.start_hour * 60;
    finish = settings.end_hour * 60;
    occupied = reserved_spans(day_value);
    day_key = day_value.isoformat();
    for session in [root-->][?:StudySession] {
        if session.day == day_key {
            occupied.append((
                session.start_minute,
                session.start_minute + session.duration
            ));
        }
    }
    occupied.sort(key=lambda (span: tuple[int, int]) { span[0]; });
    slots: list[tuple[int, int]] = [];
    cursor = start;
    for span in occupied {
        blocked_start = max(start, span[0]);
        blocked_end = min(finish, span[1]);
        if blocked_end <= cursor { continue; }
        if blocked_start > cursor { slots.append((cursor, blocked_start)); }
        cursor = max(cursor, blocked_end);
    }
    if cursor < finish { slots.append((cursor, finish)); }
    return slots;
}

def:priv schedule_on_day(task: Task, day_value: date, requested: int) -> int {
    placed = 0;
    while placed < requested {
        need = requested - placed;
        slots = free_slots(day_value);
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
        for previous in [root-->][?:StudySession] {
            if previous.task_id == jid(task) and previous.day == day_value.isoformat()
                and not previous.completed
                and previous.start_minute + previous.duration == chosen[0] {
                previous.duration += chunk;
                extended = True;
                break;
            }
        }
        if extended { continue; }
        root ++> StudySession(
            task_id=jid(task), title=task.title, course=task.course,
            day=day_value.isoformat(), start_time=clock_label(chosen[0]),
            start_minute=chosen[0], duration=chunk, priority=task.priority
        );
    }
    return placed;
}

def:priv task_view(task: Task) -> TaskView {
    today = date.today();
    due = parse_due(task.due_date);
    delta = (due - today).days;
    due_label = "Due today" if delta == 0 else (
        "Due tomorrow" if delta == 1 else (
            f"Due in {delta} days" if delta > 1 else (
                "Overdue by 1 day" if delta == -1 else f"Overdue by {-delta} days"
            )
        )
    );
    progress = 100 if task.completed else min(
        99, int((task.completed_minutes * 100) / max(1, task.estimated_minutes))
    );
    return TaskView(
        id=jid(task), title=task.title, course=task.course,
        due_date=task.due_date, estimated_minutes=task.estimated_minutes,
        completed_minutes=task.completed_minutes, priority=task.priority,
        completed=task.completed, progress=progress, due_label=due_label,
        color=course_color(task.course), days_left=delta
    );
}

def:priv session_view(session: StudySession) -> SessionView {
    return SessionView(
        id=jid(session), task_id=session.task_id, title=session.title,
        course=session.course, day=session.day,
        start_time=clock_label(session.start_minute),
        start_minute=session.start_minute, duration=session.duration,
        priority=session.priority, completed=session.completed,
        color=course_color(session.course),
        end_time=clock_label(session.start_minute + session.duration),
        missed=(not session.completed
            and session.day < date.today().isoformat())
    );
}

def:priv reserved_view(block: ReservedBlock) -> ReservedBlockView {
    return ReservedBlockView(
        id=jid(block), label=block.label, category=block.category,
        start_time=f"{block.start_minute // 60:02d}:{block.start_minute % 60:02d}",
        end_time=f"{block.end_minute // 60:02d}:{block.end_minute % 60:02d}",
        repeat_rule=block.repeat_rule,
        repeat_label=repeat_text(block.repeat_rule),
        days=[DAY_CODES[i] for i in repeat_days(block.repeat_rule)]
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

def:priv rebuild_schedule -> int {
    today = date.today();
    for old in list([root-->][?:StudySession]) {
        if not old.completed { del old; }
    }
    tasks = [task for task in [root-->][?:Task] if not task.completed];
    tasks.sort(key=lambda (item: Task) {
        (item.due_date, priority_rank(item.priority), item.created_at)
    });
    unscheduled = 0;
    for task in tasks {
        remaining = max(0, task.estimated_minutes - task.completed_minutes);
        due = parse_due(task.due_date);
        last_day = due if due >= today else today;
        day_count = (last_day - today).days + 1;
        fair_share = max(30, (remaining + day_count - 1) // day_count);
        day_index = 0;
        while remaining > 0 and day_index < day_count {
            current = today + timedelta(days=day_index);
            placed = schedule_on_day(task, current, min(fair_share, remaining));
            remaining -= placed;
            day_index += 1;
        }
        day_index = 0;
        while remaining > 0 and day_index < day_count {
            current = today + timedelta(days=day_index);
            placed = schedule_on_day(task, current, remaining);
            remaining -= placed;
            day_index += 1;
        }
        unscheduled += remaining;
    }
    return unscheduled;
}

def:priv make_dashboard(message: str = "") -> DashboardData {
    today = date.today();
    settings = get_settings_node();
    task_views = [task_view(task) for task in [root-->][?:Task]];
    task_views.sort(key=lambda (item: TaskView) {
        (item.completed, item.due_date, priority_rank(item.priority))
    });
    session_views = [session_view(s) for s in [root-->][?:StudySession]];
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
    return DashboardData(
        tasks=task_views, today_sessions=today_sessions,
        week_sessions=week_sessions, loads=loads, reserved_blocks=block_views,
        settings=SettingsView(
            start_hour=settings.start_hour, end_hour=settings.end_hour
        ),
        active_tasks=active, completed_tasks=completed,
        remaining_minutes=remaining, scheduled_minutes=scheduled,
        overload_minutes=max(0, remaining - scheduled),
        today=today.strftime("%A, %B %d"), message=message,
        missed_sessions=len(missed),
        missed_minutes=sum([s.duration for s in missed]),
        due_this_week=due_soon
    );
}

def:pub get_dashboard -> DashboardData { return make_dashboard(); }

def:pub add_task(
    title: str, course: str, due_date: str,
    estimated_minutes: int, priority: str
) -> DashboardData {
    clean_title = title.strip();
    if not clean_title { raise ValueError("Task title is required."); }
    due = parse_due(due_date);
    if due < date.today() { raise ValueError("Due date cannot be in the past."); }
    if estimated_minutes < 15 or estimated_minutes > 1440 {
        raise ValueError("Estimate must be between 15 and 1440 minutes.");
    }
    if not valid_priority(priority) { raise ValueError("Invalid priority."); }
    root ++> Task(
        title=clean_title, course=clean_course(course),
        due_date=due.isoformat(), estimated_minutes=estimated_minutes,
        priority=priority, created_at=date.today().isoformat()
    );
    unscheduled = rebuild_schedule();
    note = "Task added and your week was rebalanced.";
    if unscheduled > 0 {
        note += f" {minutes_label(unscheduled)} could not fit before its deadline.";
    }
    return make_dashboard(note);
}

def:pub update_task(
    task_id: str, title: str, course: str, due_date: str,
    estimated_minutes: int, priority: str
) -> DashboardData {
    task = find_task(task_id);
    if task is None { raise ValueError("Task was not found."); }
    if not title.strip() { raise ValueError("Task title is required."); }
    due = parse_due(due_date);
    if due < date.today() { raise ValueError("Due date cannot be in the past."); }
    if estimated_minutes < 15 or estimated_minutes > 1440 {
        raise ValueError("Estimate must be between 15 and 1440 minutes.");
    }
    if not valid_priority(priority) { raise ValueError("Invalid priority."); }
    task.title = title.strip();
    task.course = clean_course(course);
    task.due_date = due.isoformat();
    task.estimated_minutes = estimated_minutes;
    task.priority = priority;
    rebuild_schedule();
    return make_dashboard("Task updated and the plan was refreshed.");
}

def:pub delete_task(task_id: str) -> DashboardData {
    task = find_task(task_id);
    if task is None { raise ValueError("Task was not found."); }
    for session in list([root-->][?:StudySession]) {
        if session.task_id == task_id { del session; }
    }
    del task;
    rebuild_schedule();
    return make_dashboard("Task deleted.");
}

def:pub toggle_task(task_id: str) -> DashboardData {
    task = find_task(task_id);
    if task is None { raise ValueError("Task was not found."); }
    task.completed = not task.completed;
    task.completed_minutes = task.estimated_minutes if task.completed else 0;
    rebuild_schedule();
    return make_dashboard("Task status updated.");
}

def:pub complete_session(session_id: str) -> DashboardData {
    session = find_session(session_id);
    if session is None { raise ValueError("Work block was not found."); }
    if not session.completed {
        session.completed = True;
        task = find_task(session.task_id);
        if task is not None {
            task.completed_minutes = min(
                task.estimated_minutes, task.completed_minutes + session.duration
            );
            task.completed = task.completed_minutes >= task.estimated_minutes;
        }
    }
    return make_dashboard("Nice work — block completed.");
}

def:pub replan -> DashboardData {
    today_key = date.today().isoformat();
    missed = [
        item for item in [root-->][?:StudySession]
        if not item.completed and item.day < today_key
    ];
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
                time_label=clock_label(block.start_minute) + " – " + clock_label(block.end_minute)
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

def:pub get_calendar(view: str = "week", anchor: str = "", shift: int = 0) -> CalendarData {
    if view not in ["day", "week", "month"] { raise ValueError("Unknown calendar view."); }
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
        focus = date(month_index // 12, month_index % 12 + 1, 1);
        first = focus - timedelta(days=focus.weekday());
        next_month = date(
            (month_index + 1) // 12, (month_index + 1) % 12 + 1, 1
        );
        last_of_month = next_month - timedelta(days=1);
        last = last_of_month + timedelta(days=6 - last_of_month.weekday());
        title = focus.strftime("%B %Y");
    }
    settings = get_settings_node();
    window_start = settings.start_hour * 60;
    window_end = settings.end_hour * 60;
    first_key = first.isoformat();
    last_key = last.isoformat();
    sessions = [
        session_view(s) for s in [root-->][?:StudySession]
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
                completed=s.completed, missed=s.missed, task_id=s.task_id
            ) for s in sessions if s.day == key
        ];
        day_due = [
            CalendarItem(
                id=jid(t), kind="due", title=t.title, course=t.course,
                color=course_color(t.course), completed=t.completed,
                task_id=jid(t)
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
    return CalendarData(
        view=view, anchor=focus.isoformat(), title=title, days=days,
        start_hour=settings.start_hour, end_hour=settings.end_hour
    );
}

def:pub save_planning_window(start_hour: int, end_hour: int) -> DashboardData {
    if start_hour < 0 or start_hour > 22 {
        raise ValueError("Planning start must be between 0 and 22.");
    }
    if end_hour < 1 or end_hour > 24 or end_hour <= start_hour {
        raise ValueError("Planning end must be later than the start.");
    }
    settings = get_settings_node();
    settings.start_hour = start_hour;
    settings.end_hour = end_hour;
    rebuild_schedule();
    return make_dashboard("Planning window saved and your week was rebuilt.");
}

def:pub add_reserved_block(
    label: str,
    category: str,
    start_time: str,
    end_time: str,
    repeat_rule: str
) -> DashboardData {
    if not label.strip() { raise ValueError("Reserved time needs a name."); }
    if not valid_repeat(repeat_rule) {
        raise ValueError("Pick at least one day for the reserved time to repeat on.");
    }
    start = parse_clock(start_time);
    finish = parse_clock(end_time);
    if start == finish { raise ValueError("Start and end time cannot match."); }
    root ++> ReservedBlock(
        label=label.strip(), category=category.strip() or "other",
        start_minute=start, end_minute=finish,
        repeat_rule=normalize_repeat(repeat_rule)
    );
    rebuild_schedule();
    return make_dashboard("Reserved time added and planned work was moved around it.");
}

def:pub delete_reserved_block(block_id: str) -> DashboardData {
    for block in [root-->][?:ReservedBlock] {
        if jid(block) == block_id {
            del block;
            rebuild_schedule();
            return make_dashboard("Reserved time removed and your week was rebuilt.");
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

test "long work can use multiple sessions in one free interval" {
    marker = "StudyFlow long-session test";
    for old in list([root-->][?:Task]) {
        if old.title == marker { delete_task(jid(old)); }
    }
    result = add_task(
        marker, "TEST 201", date.today().isoformat(), 300, "high"
    );
    matches = [task for task in result.tasks if task.title == marker];
    assert len(matches) == 1;
    planned = sum([
        session.duration for session in result.today_sessions
        if session.task_id == matches[0].id
    ]);
    assert planned == 300;
    delete_task(matches[0].id);
}

test "calendar views cover full weeks and months" {
    week = get_calendar("week", "2026-10-02", 0);
    assert len(week.days) == 7;
    assert week.days[0].weekday == "Mon";
    month = get_calendar("month", "2026-10-02", 1);
    assert month.anchor == "2026-11-01";
    assert len(month.days) % 7 == 0;
    assert len([d for d in month.days if d.in_range]) == 30;
    day = get_calendar("day", "2026-10-02", -1);
    assert day.days[0].date == "2026-10-01";
}

test "course colors are stable" {
    assert course_color("EECS 484") == course_color("eecs 484");
    assert course_color("EECS 484") in COURSE_COLORS;
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

test "invalid estimates are rejected" {
    with testraises(ValueError) {
        add_task("Impossible", "TEST", "2099-12-31", -10, "medium");
    }
}
