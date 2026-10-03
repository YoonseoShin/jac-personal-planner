import from datetime { date, timedelta }

obj TaskView {
    has id: str, title: str, course: str, due_date: str,
        estimated_minutes: int, completed_minutes: int,
        priority: str, completed: bool, progress: int, due_label: str;
}

obj SessionView {
    has id: str, task_id: str, title: str, course: str, day: str,
        start_time: str, start_minute: int, duration: int,
        priority: str, completed: bool;
}

obj DayLoad {
    has day: str, label: str, minutes: int, capacity: int;
}

obj ReservedBlockView {
    has id: str, label: str, category: str, start_time: str,
        end_time: str, repeat_rule: str;
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
        overload_minutes: int, today: str, message: str;
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

def:priv valid_repeat(value: str) -> bool {
    return value in ["daily", "weekdays", "weekends"];
}

def:priv active_on(block: ReservedBlock, day_value: date) -> bool {
    weekday = day_value.weekday();
    if block.repeat_rule == "weekdays" { return weekday < 5; }
    if block.repeat_rule == "weekends" { return weekday >= 5; }
    return True;
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
    for slot in free_slots(day_value) {
        if placed >= requested { break; }
        cursor = slot[0];
        while placed < requested and slot[1] - cursor >= 15 {
            available = slot[1] - cursor;
            chunk = min(90, requested - placed, available);
            if chunk < 15 { break; }
            root ++> StudySession(
                task_id=jid(task), title=task.title, course=task.course,
                day=day_value.isoformat(), start_time=clock_label(cursor),
                start_minute=cursor, duration=chunk, priority=task.priority
            );
            placed += chunk;
            cursor += chunk;
        }
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
        completed=task.completed, progress=progress, due_label=due_label
    );
}

def:priv session_view(session: StudySession) -> SessionView {
    return SessionView(
        id=jid(session), task_id=session.task_id, title=session.title,
        course=session.course, day=session.day,
        start_time=clock_label(session.start_minute),
        start_minute=session.start_minute, duration=session.duration,
        priority=session.priority, completed=session.completed
    );
}

def:priv reserved_view(block: ReservedBlock) -> ReservedBlockView {
    return ReservedBlockView(
        id=jid(block), label=block.label, category=block.category,
        start_time=f"{block.start_minute // 60:02d}:{block.start_minute % 60:02d}",
        end_time=f"{block.end_minute // 60:02d}:{block.end_minute % 60:02d}",
        repeat_rule=block.repeat_rule
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
    scheduled = sum([s.duration for s in session_views if not s.completed]);
    return DashboardData(
        tasks=task_views, today_sessions=today_sessions,
        week_sessions=week_sessions, loads=loads, reserved_blocks=block_views,
        settings=SettingsView(
            start_hour=settings.start_hour, end_hour=settings.end_hour
        ),
        active_tasks=active, completed_tasks=completed,
        remaining_minutes=remaining, scheduled_minutes=scheduled,
        overload_minutes=max(0, remaining - scheduled),
        today=today.strftime("%A, %B %d"), message=message
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
    if session is None { raise ValueError("Study session was not found."); }
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
    return make_dashboard("Nice work — session completed.");
}

def:pub replan -> DashboardData {
    unscheduled = rebuild_schedule();
    note = "Your remaining work was redistributed from today forward.";
    if unscheduled > 0 {
        note += f" Free up protected time to place the remaining {minutes_label(unscheduled)}.";
    }
    return make_dashboard(note);
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
    if not valid_repeat(repeat_rule) { raise ValueError("Invalid repeat rule."); }
    start = parse_clock(start_time);
    finish = parse_clock(end_time);
    if start == finish { raise ValueError("Start and end time cannot match."); }
    root ++> ReservedBlock(
        label=label.strip(), category=category.strip() or "other",
        start_minute=start, end_minute=finish, repeat_rule=repeat_rule
    );
    rebuild_schedule();
    return make_dashboard("Protected time added and study sessions were moved around it.");
}

def:pub delete_reserved_block(block_id: str) -> DashboardData {
    for block in [root-->][?:ReservedBlock] {
        if jid(block) == block_id {
            del block;
            rebuild_schedule();
            return make_dashboard("Protected time removed and your week was rebuilt.");
        }
    }
    raise ValueError("Protected time was not found.");
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

test "invalid estimates are rejected" {
    with testraises(ValueError) {
        add_task("Impossible", "TEST", "2099-12-31", -10, "medium");
    }
}
