import from core.planner_service {
    CalendarData,
    CalendarDay,
    CalendarItem,
    DashboardData,
    ReservedBlockView,
    TaskView,
    add_reserved_block,
    add_task,
    complete_session,
    delete_reserved_block,
    delete_task,
    get_calendar,
    get_dashboard,
    replan,
    seed_demo,
    seed_routine,
    reopen_task,
    toggle_task,
    uncomplete_session,
    update_task
}
import from core.errors { friendly_error }
import from "react" { useEffect }
import "./styles.css";

# How often an open page re-reads the plan, so changes made on the phone or
# in the CLI show up without a manual reload.
glob REFRESH_MS: int = 10000;

# The type stubs lack `document.visibilityState`; read it untyped.
def page_visible -> bool {
    doc: any = globalThis.document;  # jac:ignore[W1037,W6001]
    return doc.visibilityState != "hidden";
}


def minute_text(total: int) -> str {
    hour = total // 60;
    minute = total % 60;
    if hour > 0 and minute > 0 { return str(hour) + "h " + str(minute) + "m"; }
    if hour > 0 { return str(hour) + "h"; }
    return str(minute) + "m";
}

glob DAY_CODES: list[str] = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"];

def day_rule(days: list[str]) -> str {
    rule = "";
    for code in DAY_CODES {
        if code in days { rule = rule + ("," if rule else "") + code; }
    }
    return rule;
}

# When switching views, jump to today if it is in the range being looked at;
# otherwise keep the date currently in focus.
def view_anchor(cal: CalendarData | None, anchor: str) -> str {
    if cal is None { return ""; }
    for d in cal.days {
        if d.is_today and d.in_range { return ""; }
    }
    return anchor;
}

def preset_days(name: str) -> list[str] {
    if name == "Weekdays" { return ["mon", "tue", "wed", "thu", "fri"]; }
    if name == "Weekends" { return ["sat", "sun"]; }
    return list(DAY_CODES);
}

def same_days(a: list[str], b: list[str]) -> bool {
    return day_rule(a) == day_rule(b);
}

def clock_text(value: str) -> str {
    parts = value.split(":");
    hour = int(parts[0]);
    shown = hour % 12;
    if shown == 0 { shown = 12; }
    return str(shown) + ":" + parts[1] + (" AM" if hour < 12 else " PM");
}

def due_tone(task: TaskView) -> str {
    if task.completed { return "muted"; }
    if task.days_left <= 1 { return "urgent"; }
    if task.days_left <= 3 { return "soon"; }
    return "calm";
}

# ---------- Summary ----------

def PlanHealth(
    data: DashboardData,
    busy: bool,
    onReplan: Callable[[], None]
) -> JsxElement {
    # Lowest to highest priority: the last matching rule wins.
    tone = "ok";
    headline = "On track: your plan is up to date";
    detail = "";
    if data.remaining_minutes == 0 {
        headline = "All caught up";
    }
    if data.improvable_tasks > 0 {
        tone = "hint";
        headline = "Free time opened up";
        detail = "Reschedule to finish " + str(data.improvable_tasks) + " task" + ("" if data.improvable_tasks == 1 else "s") + " earlier.";
    }
    if data.overload_minutes > data.unfit_minutes {
        tone = "warn";
        headline = minute_text(data.overload_minutes - data.unfit_minutes) + " of work isn't on your calendar yet";
        detail = "There is room for it. Reschedule to plan it.";
    }
    if data.unfit_minutes > 0 {
        tone = "warn";
        headline = minute_text(data.unfit_minutes) + " of work doesn't fit";
        detail = "Not enough free time before the deadline, even after rescheduling. Remove reserved time or move the due date.";
    }
    overdue = [t for t in data.tasks if t.overdue];
    if len(overdue) > 0 {
        tone = "warn";
        headline = str(len(overdue)) + " task" + ("" if len(overdue) == 1 else "s") + " past due";
        detail = overdue[0].title + " is " + overdue[0].due_label.lower() + ". Finish it or edit its due date.";
    }
    if data.overlapping > 0 {
        tone = "warn";
        headline = str(data.overlapping) + " to-dos overlap";
        detail = "Some blocks sit on top of each other or on reserved time. Reschedule to fix.";
    }
    if data.missed_sessions > 0 {
        tone = "warn";
        headline = str(data.missed_sessions) + " missed to-do" + ("" if data.missed_sessions == 1 else "s") + " (" + minute_text(data.missed_minutes) + ")";
        detail = "You didn't finish these in time. Reschedule to move them into your next free time.";
    }
    <div className={"health " + tone}>
        <span className="health-badge">{"✓" if tone == "ok" else ("↻" if tone == "hint" else "!")}</span>
        <div className="health-copy">
            <strong>{headline}</strong>
            {if detail { <span>{detail}</span> }}
        </div>
        <button
            className={"button small " + ("outline" if tone == "ok" else "primary")}
            disabled={busy}
            onClick={lambda { onReplan(); }}
            title="Re-spreads unfinished work into your free time, earliest deadline first. Finished items stay."
        >
            {"Rescheduling…" if busy else "↻ Reschedule"}
        </button>
    </div>
}

def TodayList(
    data: DashboardData,
    focusId: str,
    onToggle: Callable[[str, bool], None],
    onFocus: Callable[[str, bool], None]
) -> JsxElement {
    items = data.today_sessions;
    done = len([s for s in items if s.completed]);
    percent = int(done * 100 / len(items)) if len(items) > 0 else 0;
    <section className="panel today">
        <div className="today-head">
            <div>
                <h2>Today</h2>
                <span className="sub">{data.today}</span>
            </div>
            {if len(items) > 0 {
                <div className="today-progress">
                    <span>{str(done) + " of " + str(len(items)) + " done"}</span>
                    <div className="bar wide"><span style={{"width": str(percent) + "%"}}></span></div>
                </div>
            }}
        </div>
        <p className="today-hint">Checking an item marks just that block. Your plan only shifts when you press Reschedule.</p>
        {if len(items) == 0 {
            <p className="quiet today-empty">Nothing planned for today.</p>
        } else {
            <ul className="todo-list">
                {[<li
                    key={s.id}
                    className={"todo" + (" done" if s.completed else "") + (" missed" if s.missed else "") + (" focus" if s.id == focusId else "")}
                    style={{"--c": s.color}}
                    onMouseEnter={lambda { onFocus(s.id, False); }}
                    onMouseLeave={lambda { onFocus("", False); }}
                    onClick={lambda { onFocus(s.id, True); }}
                >
                    <button
                        className={"todo-check" + (" on" if s.completed else "")}
                        aria-label={"Mark not done" if s.completed else "Mark done"}
                        title={"Mark not done" if s.completed else "Mark done"}
                        onClick={lambda (e: MouseEvent) { e.stopPropagation(); onToggle(s.id, s.completed); }}
                    >{"✓" if s.completed else ""}</button>
                    <div className="todo-body">
                        <strong>{s.title}</strong>
                        <span className="todo-meta">
                            <span className="course"><span className="dot"></span>{s.course}</span>
                            {if s.location { <span className="place">{"📍 " + s.location}</span> }}
                            <span>{s.start_time + " – " + s.end_time}</span>
                            <span>{minute_text(s.duration)}</span>
                        </span>
                    </div>
                    {if s.moved_from and not s.completed {
                        <span className="moved-note" title="Reschedule moved this here">{"↪ Rescheduled from " + s.moved_from}</span>
                    }}
                    {if s.added_note and not s.completed {
                        <span className="moved-note" title="Reschedule added work to this block">{"↪ " + s.added_note}</span>
                    }}
                    {if s.missed {
                        <span className="tag warn">Missed</span>
                    }}
                </li> for s in items]}
            </ul>
        }}
    </section>
}

# ---------- Calendar ----------

def SessionBlock(
    item: CalendarItem,
    compact: bool,
    onToggle: Callable[[str, bool], None],
    onTip: Callable[[CalendarItem | None, MouseEvent | None], None],
    focused: bool = False
) -> JsxElement {
    height = max(14, item.height - 2);
    # Short blocks collapse to a single line so text never spills over.
    size = "tiny" if height < 30 else ("short" if height < 46 else "");
    state = "done" if item.completed else ("missed" if item.missed else "");
    <div
        id={"block-" + item.id}
        className={"block session " + state + " " + size + (" compact" if compact else "") + (" focus" if focused else "")}
        style={{"top": str(item.top) + "px", "height": str(height) + "px", "--c": item.color}}
        onMouseEnter={lambda (e: MouseEvent) { onTip(item, e); }}
        onMouseLeave={lambda { onTip(None, None); }}
        onClick={lambda (e: MouseEvent) { e.stopPropagation(); onTip(item, e); }}
    >
        <div className="block-text">
            <strong>{item.title}</strong>
            {if not (compact and size == "tiny") {
                <span>{item.time_label if compact else item.time_label + " · " + item.course}</span>
            }}
        </div>
        {if item.missed {
            <em className="missed-tag">Missed</em>
        } else {
            <button
                className={"block-check" + (" on" if item.completed else "")}
                title={"Mark not done" if item.completed else "Mark done"}
                onClick={lambda (e: MouseEvent) { e.stopPropagation(); onToggle(item.id, item.completed); }}
            >✓</button>
        }}
    </div>
}

def BusyBlock(
    item: CalendarItem,
    onTip: Callable[[CalendarItem | None, MouseEvent | None], None]
) -> JsxElement {
    height = max(10, item.height - 2);
    <div
        className={"block busy" + (" thin" if height < 16 else "")}
        style={{"top": str(item.top) + "px", "height": str(height) + "px"}}
        onMouseEnter={lambda (e: MouseEvent) { onTip(item, e); }}
        onMouseLeave={lambda { onTip(None, None); }}
        onClick={lambda (e: MouseEvent) { e.stopPropagation(); onTip(item, e); }}
    >
        <span>{item.title}</span>
    </div>
}

def TimeGrid(
    cal: CalendarData,
    compact: bool,
    onToggle: Callable[[str, bool], None],
    onOpenDay: Callable[[str], None],
    onTip: Callable[[CalendarItem | None, MouseEvent | None], None],
    focusId: str = ""
) -> JsxElement {
    gridHeight = cal.grid_height;
    cols = "56px repeat(" + str(len(cal.days)) + ", minmax(0, 1fr))";
    focusing = focusId != "" and any([s.id == focusId for d in cal.days for s in d.sessions]);
    <div className={"timegrid " + ("week" if compact else "day") + (" focusing" if focusing else "")}>
        <div className="tg-head" style={{"gridTemplateColumns": cols}}>
            <div></div>
            {[<button
                key={d.date}
                className={"tg-day " + ("today" if d.is_today else "") + (" past" if d.is_past else "")}
                onClick={lambda { onOpenDay(d.date); }}
                title="Open this day"
            >
                <span className="tg-wd">{d.weekday}</span>
                <span className="tg-num">{d.day_num}</span>
                <span className="tg-load">
                    {minute_text(d.study_minutes) + " planned" if d.study_minutes > 0 else "free"}
                </span>
                {[<span key={due.id} className={"due-pill" + (" done" if due.completed else "")} style={{"--c": due.color}}>
                    {"Due" + (" " + due.time_label if due.time_label else "") + " · " + due.title}
                </span> for due in d.due]}
            </button> for d in cal.days]}
        </div>
        <div className="tg-body" style={{"gridTemplateColumns": cols}} onScroll={lambda { onTip(None, None); }}>
            <div className="tg-hours" style={{"height": str(gridHeight) + "px"}}>
                {[<span key={m.label} style={{"top": str(m.y) + "px"}}>{m.label}</span> for m in cal.hour_marks]}
            </div>
            {[<div
                key={d.date}
                className={"tg-col " + ("today" if d.is_today else "")}
                style={{"height": str(gridHeight) + "px"}}
                onClick={lambda { onTip(None, None); }}
            >
                {[<div key={"hl-" + m.label} className="hour-line" style={{"top": str(m.y) + "px"}}></div> for m in cal.hour_marks]}
                {[<BusyBlock key={b.id} item={b} onTip={onTip}/> for b in d.busy if b.height > 0]}
                {[<div
                    key={"line-" + due.id}
                    className={"due-line" + (" done" if due.completed else "")}
                    style={{"top": str(due.top) + "px"}}
                >
                    <span
                        onMouseEnter={lambda (e: MouseEvent) { onTip(due, e); }}
                        onMouseLeave={lambda { onTip(None, None); }}
                        onClick={lambda (e: MouseEvent) { e.stopPropagation(); onTip(due, e); }}
                    >{"Due " + due.time_label + (" · " + due.title if not compact else "")}</span>
                </div> for due in d.due if due.start_minute >= cal.start_hour * 60 and due.start_minute <= cal.end_hour * 60]}
                {[<SessionBlock
                    key={s.id}
                    item={s}
                    compact={compact}
                    onToggle={onToggle}
                    onTip={onTip}
                    focused={s.id == focusId}
                /> for s in d.sessions if s.height > 0]}
            </div> for d in cal.days]}
        </div>
    </div>
}

def MonthCell(day: CalendarDay, onOpenDay: Callable[[str], None]) -> JsxElement {
    shown = day.work[:3];
    extra = len(day.work) - len(shown);
    <button
        className={"m-cell" + (" out" if not day.in_range else "") + (" today" if day.is_today else "") + (" past" if day.is_past else "")}
        onClick={lambda { onOpenDay(day.date); }}
    >
        <div className="m-top">
            <span className="m-num">{day.day_num}</span>
            {if day.study_minutes > 0 {
                <span className="m-total">{minute_text(day.study_minutes)}</span>
            }}
        </div>
        {[<span key={due.id} className={"due-pill" + (" done" if due.completed else "")} style={{"--c": due.color}}>
            {"Due" + (" " + due.time_label if due.time_label else "") + " · " + due.title}
        </span> for due in day.due]}
        {[<span
            key={s.id}
            className={"m-chip" + (" done" if s.completed else "") + (" missed" if s.missed else "")}
            style={{"--c": s.color}}
        >
            <span className="dot"></span>{s.title}<em>{s.time_label}</em>
        </span> for s in shown]}
        {if extra > 0 {
            <span className="m-more">{"+" + str(extra) + " more"}</span>
        }}
    </button>
}

def MonthGrid(cal: CalendarData, onOpenDay: Callable[[str], None]) -> JsxElement {
    <div className="month">
        <div className="m-head">
            {[<span key={w}>{w}</span> for w in ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]]}
        </div>
        <div className="m-grid">
            {[<MonthCell key={d.date} day={d} onOpenDay={onOpenDay}/> for d in cal.days]}
        </div>
    </div>
}

def TipCard(item: CalendarItem) -> JsxElement {
    if item.kind == "busy" {
        return <div className="tip-body">
            <span className="tip-kind">Reserved time</span>
            <strong>{item.title}</strong>
            <span>{item.time_label}</span>
            {if item.location { <span className="tip-place">{"📍 " + item.location}</span> }}
            <span className="tip-note">Nothing is scheduled here.</span>
        </div>;
    } elif item.kind == "due" {
        return <div className="tip-body">
            <span className="tip-kind due">Deadline</span>
            <strong>{item.title}</strong>
            <span>{item.course + (" · due " + item.time_label if item.time_label else " · due end of day")}</span>
            {if item.location { <span className="tip-place">{"📍 " + item.location}</span> }}
            {if item.completed { <span className="tip-note">Finished ✓</span> }}
        </div>;
    }
    return <div className="tip-body">
            <span className="tip-kind work"><span className="dot"></span>{item.course}</span>
            <strong>{item.title}</strong>
            <span>{item.time_label + " · " + minute_text(item.duration)}</span>
            {if item.location { <span className="tip-place">{"📍 " + item.location}</span> }}
            {if item.moved_from { <span className="tip-moved">{"↪ Rescheduled from " + item.moved_from}</span> }}
            {if item.added_note { <span className="tip-moved">{"↪ " + item.added_note}</span> }}
            <span className={"tip-note" + (" ok" if item.completed else (" warn" if item.missed else ""))}>
                {"Done ✓" if item.completed else ("Missed — reschedule to move it" if item.missed else "Planned · tap the circle when done")}
            </span>
        </div>;
}

def CalendarPanel(  # jac:ignore[W3030]
    cal: CalendarData | None,
    view: str,
    onView: Callable[[str], None],
    onShift: Callable[[int], None],
    onToggle: Callable[[str, bool], None],
    onOpenDay: Callable[[str], None],
    onTip: Callable[[CalendarItem | None, MouseEvent | None], None],
    focusId: str = ""
) -> JsxElement {
    <section className="panel calendar">
        <div className="cal-bar">
            <div className="segmented" role="tablist">
                {[<button
                    key={v}
                    className={"seg" + (" on" if view == v else "")}
                    onClick={lambda { onView(v); }}
                >{v[0].upper() + v[1:]}</button> for v in ["day", "week", "month"]]}
            </div>
            <div className="cal-nav">
                <button className="nav-btn" aria-label="Previous" onClick={lambda { onShift(-1); }}>‹</button>
                <button className="button small outline" onClick={lambda { onShift(0); }}>Today</button>
                <button className="nav-btn" aria-label="Next" onClick={lambda { onShift(1); }}>›</button>
            </div>
            <h2 className="cal-title">{cal.title if cal is not None else ""}</h2>
        </div>
        {if cal is None {
            <div className="quiet pad">Loading calendar…</div>
        } elif cal.view == "month" {
            <MonthGrid cal={cal} onOpenDay={onOpenDay}/>
        } elif cal.view == "week" {
            <TimeGrid cal={cal} compact={True} onToggle={onToggle} onOpenDay={onOpenDay} onTip={onTip} focusId={focusId}/>
        } else {
            <TimeGrid cal={cal} compact={False} onToggle={onToggle} onOpenDay={onOpenDay} onTip={onTip} focusId={focusId}/>
        }}
    </section>
}

# ---------- Side panels ----------

def TaskItem(
    task: TaskView,
    onDone: Callable[[TaskView], None],
    onEdit: Callable[[TaskView], None],
    onDelete: Callable[[str], None]
) -> JsxElement {
    <li className={"task" + (" done" if task.completed else "")} style={{"--c": task.color}}>
        <div className="task-body">
            <div className="task-line">
                <strong>{task.title}</strong>
                {if task.completed {
                    <span className="due muted">{task.due_on}</span>
                } else {
                    <span className={"due " + due_tone(task)}>{task.due_label}</span>
                }}
            </div>
            <div className="task-meta">
                <span className="course"><span className="dot"></span>{task.course}</span>
                {if task.location { <span className="place">{"📍 " + task.location}</span> }}
                <span className={"prio " + task.priority}>{task.priority[0].upper() + task.priority[1:] + " priority"}</span>
                <span>{minute_text(task.completed_minutes) + " / " + minute_text(task.estimated_minutes) + " done"}</span>
            </div>
            <div className="bar"><span style={{"width": str(task.progress) + "%"}}></span></div>
        </div>
        <div className="task-actions">
            <button
                className={"button small " + ("outline" if task.completed else "done-btn")}
                title={"Reopen this task and plan its remaining work" if task.completed else "The whole task is finished: remove its remaining blocks"}
                onClick={lambda { onDone(task); }}
            >{"Reopen" if task.completed else "✓ Done"}</button>
            <button className="icon" title="Edit task" onClick={lambda { onEdit(task); }}>✎</button>
            <button className="icon danger" title="Delete task" onClick={lambda { onDelete(task.id); }}>🗑</button>
        </div>
    </li>
}

def task_order(task: TaskView) -> str {
    rank = "0" if task.priority == "high" else ("2" if task.priority == "low" else "1");
    return ("1" if task.completed else "0") + rank + task.due_date + (task.due_time or "99:99");
}

def BusyRow(block: ReservedBlockView, onDelete: Callable[[str], None]) -> JsxElement {
    <li className="busy-row">
        <span className={"cat " + block.category}></span>
        <div>
            <strong>{block.label}</strong>
            <span>{clock_text(block.start_time) + " – " + clock_text(block.end_time) + " · " + block.repeat_label + (" · 📍 " + block.location if block.location else "")}</span>
        </div>
        <button className="icon danger" title="Remove reserved time" onClick={lambda { onDelete(block.id); }}>×</button>
    </li>
}

# ---------- App ----------

def:pub app -> JsxElement {
    has data: DashboardData | None = None,
        cal: CalendarData | None = None,
        calView: str = "week",
        calAnchor: str = "",
        loading: bool = True,
        busy: bool = False,
        error: str = "",
        notice: str = "",
        modal: str = "",
        quickTitle: str = "",
        taskTab: str = "open",
        focusId: str = "",
        tick: int = 0,
        pollRef: Ref[int] = Ref(0),
        reopening: TaskView | None = None,
        extraMinutes: str = "30",
        tip: CalendarItem | None = None,
        tipX: int = 0,
        tipY: int = 0,
        tipBelow: bool = False,
        title: str = "",
        course: str = "",
        dueDate: str = "",
        dueTime: str = "",
        taskLocation: str = "",
        estimate: str = "60",
        priority: str = "medium",
        editId: str = "",
        blockLabel: str = "",
        blockCategory: str = "class",
        blockStart: str = "10:00",
        blockEnd: str = "11:30",
        blockDays: list[str] = ["mon", "tue", "wed", "thu", "fri"],
        blockLocation: str = "";

    def toggleDay(code: str) {
        if code in blockDays {
            blockDays = [d for d in blockDays if d != code];
        } else {
            blockDays = blockDays + [code];
        }
    }

    async def loadCalendar(view: str, anchor: str, shift: int) {
        try {
            result = await get_calendar(view, anchor, shift);
            cal = result;
            calView = view;
            calAnchor = result.anchor;
        } except Exception as e {
            error = friendly_error(str(e));
        }
    }

    async def apply(next: DashboardData) {
        data = next;
        notice = next.message;
        await loadCalendar(calView, calAnchor, 0);
    }

    async def loadData {
        try {
            loading = True;
            error = "";
            data = await get_dashboard();
            await loadCalendar(calView, "", 0);
        } except Exception as e {
            error = friendly_error(str(e));
        } finally {
            loading = False;
        }
    }

    def clearForm {
        title = "";
        course = "";
        dueDate = "";
        dueTime = "";
        taskLocation = "";
        estimate = "60";
        priority = "medium";
        editId = "";
    }

    def openNewTask {
        clearForm();
        error = "";
        modal = "task";
    }

    def quickAdd {
        clearForm();
        title = quickTitle.strip();
        quickTitle = "";
        error = "";
        modal = "task";
    }

    async def saveTask {
        if busy { return; }
        try {
            busy = True;
            error = "";
            if editId {
                next = await update_task(
                    editId, title, course, dueDate, int(estimate), priority, dueTime, taskLocation
                );
            } else {
                next = await add_task(
                    title, course, dueDate, int(estimate), priority, dueTime, taskLocation
                );
            }
            clearForm();
            modal = "";
            await apply(next);
        } except Exception as e {
            error = friendly_error(str(e));
        } finally {
            busy = False;
        }
    }

    def startEdit(task: TaskView) {
        editId = task.id;
        title = task.title;
        course = task.course;
        dueDate = task.due_date;
        dueTime = task.due_time;
        taskLocation = task.location;
        estimate = str(task.estimated_minutes);
        priority = task.priority;
        error = "";
        modal = "task";
    }


    # Done closes the task. Reopen plans its remaining work, or asks for more
    # time when every estimated minute is already checked off.
    async def finishTask(task: TaskView) {
        if task.completed and task.logged_minutes >= task.estimated_minutes {
            reopening = task;
            extraMinutes = "30";
            error = "";
            modal = "reopen";
            return;
        }
        try { await apply(await toggle_task(task.id)); }
        except Exception as e { error = friendly_error(str(e)); }
    }

    async def saveReopen {
        if busy or reopening is None { return; }
        try {
            busy = True;
            next = await reopen_task(reopening.id, int(extraMinutes) if extraMinutes else 0);
            modal = "";
            reopening = None;
            await apply(next);
        } except Exception as e { error = friendly_error(str(e)); }
        finally { busy = False; }
    }

    async def removeTask(id: str) {
        try { await apply(await delete_task(id)); }
        except Exception as e { error = friendly_error(str(e)); }
    }

    async def toggleSession(id: str, done: bool) {
        try {
            if done { await apply(await uncomplete_session(id)); }
            else { await apply(await complete_session(id)); }
        } except Exception as e { error = friendly_error(str(e)); }
    }

    async def runReplan {
        try { busy = True; await apply(await replan()); }
        except Exception as e { error = friendly_error(str(e)); }
        finally { busy = False; }
    }

    async def loadDemo {
        try { await apply(await seed_demo()); }
        except Exception as e { error = friendly_error(str(e)); }
    }

    async def saveBlock {
        if busy { return; }
        try {
            busy = True;
            next = await add_reserved_block(
                blockLabel, blockCategory, blockStart, blockEnd, day_rule(blockDays), blockLocation
            );
            blockLabel = "";
            blockLocation = "";
            modal = "";
            await apply(next);
        } except Exception as e { error = friendly_error(str(e)); }
        finally { busy = False; }
    }

    async def removeBlock(id: str) {
        try { await apply(await delete_reserved_block(id)); }
        except Exception as e { error = friendly_error(str(e)); }
    }

    async def loadRoutine {
        try { await apply(await seed_routine()); }
        except Exception as e { error = friendly_error(str(e)); }
    }

    async def openDay(day: str) { tip = None; await loadCalendar("day", day, 0); }

    # Speech-bubble details for a calendar item: hover on desktop, tap on touch.
    def showTip(item: CalendarItem, e: MouseEvent) {
        rect = e.currentTarget.getBoundingClientRect();
        width = int(window.innerWidth);
        center = int(rect.left + rect.width / 2);
        tipX = max(150, min(width - 150, center));
        tipBelow = rect.top < 170;
        tipY = int(rect.bottom + 8 if tipBelow else rect.top - 8);
        tip = item;
    }

    def hideTip { tip = None; }

    # Highlights the calendar block for a Today item. Hover just highlights
    # (and scrolls the calendar itself); a tap/click also brings the block on
    # screen, switching the calendar back to today if needed.
    def focusBlock(id: str, tap: bool) {
        focusId = id;
        if not id { return; }
        if tap and cal is not None and not any([d.is_today for d in cal.days]) {
            loadCalendar("week" if calView == "month" else calView, "", 0);
        }
        target = document.getElementById("block-" + id) as HTMLElement | None;
        if target {
            narrow = int(window.innerWidth) < 1100;
            target.scrollIntoView({
                "block": "center" if (tap and narrow) else "nearest",
                "behavior": "smooth"
            });
        }
    }

    def tipFor(item: CalendarItem | None, e: MouseEvent | None) {
        if item is None or e is None { hideTip(); } else { showTip(item, e); }
    }

    async can with entry { await loadData(); }

    # Quietly re-read the plan (no spinner, no toast changes). Skipped while
    # an action is in flight so it never races a save.
    async def refreshQuietly {
        if busy or loading { return; }
        try {
            fresh = await get_dashboard();
            data = fresh;
            if cal is not None {
                cal = await get_calendar(calView, calAnchor, 0);
            }
        } except Exception {
            return;
        }
    }

    # The timer and listeners only bump `tick`; the refresh runs in the effect
    # below so it always sees the current view and week.
    useEffect(lambda {
        def bump {
            pollRef.current = (pollRef.current or 0) + 1;
            tick = pollRef.current;
        }
        def onVisible {
            if page_visible() { bump(); }
        }
        timer = setInterval(lambda { if page_visible() { bump(); } }, REFRESH_MS);
        document.addEventListener("visibilitychange", onVisible);
        window.addEventListener("focus", onVisible);
        return lambda {
            clearInterval(timer);
            document.removeEventListener("visibilitychange", onVisible);
            window.removeEventListener("focus", onVisible);
        };
    }, []);

    async can with [tick] entry {
        if tick > 0 { await refreshQuietly(); }
    }

    <div className="page">
        <header className="top">
            <div className="brand">
                <span className="logo">S</span>
                <strong>StudyFlow</strong>
                <span className="today-text">{data.today if data is not None else ""}</span>
            </div>
            <div className="top-actions">
                <button className="button primary" onClick={openNewTask}>+ New task</button>
            </div>
        </header>

        {if error and not modal {
            <div className="toast error"><span>{error}</span><button onClick={lambda { error = ""; }}>×</button></div>
        }}
        {if notice {
            <div className="toast info"><span>{notice}</span><button onClick={lambda { notice = ""; }}>×</button></div>
        }}

        {if loading {
            <div className="panel quiet pad">Loading your plan…</div>
        } elif data is not None {
            <div className="layout">
                <main className="todo-col">
                    <div className="todo-header">
                        <div>
                            <h1>To-do</h1>
                            <span className="sub">
                                {str(data.active_tasks) + " open tasks · " + minute_text(data.remaining_minutes) + " of work left · " + str(data.due_this_week) + " due this week"}
                            </span>
                        </div>
                    </div>

                    <form className="quick-add" onSubmit={lambda (e: FormEvent) { e.preventDefault(); quickAdd(); }}>
                        <span className="quick-plus">+</span>
                        <input
                            value={quickTitle}
                            placeholder="Add a task and press Enter…"
                            onChange={lambda (e: ChangeEvent) { quickTitle = e.target.value; }}
                        />
                        <button className="button primary small" type="submit">Add</button>
                    </form>

                    <PlanHealth data={data} busy={busy} onReplan={runReplan}/>

                    <TodayList data={data} focusId={focusId} onToggle={toggleSession} onFocus={focusBlock}/>

                    <section className="panel">
                        <div className="panel-head">
                            <div>
                                <h2>Tasks</h2>
                                <span className="sub">By priority, then due date. Press Done when a whole task is finished.</span>
                            </div>
                            <div className="segmented" role="tablist">
                                <button
                                    className={"seg" + (" on" if taskTab == "open" else "")}
                                    role="tab"
                                    onClick={lambda { taskTab = "open"; }}
                                >{"Open " + str(data.active_tasks)}</button>
                                <button
                                    className={"seg" + (" on" if taskTab == "done" else "")}
                                    role="tab"
                                    onClick={lambda { taskTab = "done"; }}
                                >{"Done " + str(data.completed_tasks)}</button>
                            </div>
                        </div>
                        {if len(data.tasks) == 0 {
                            <div className="empty">
                                <p>No tasks yet. Type one above to get started.</p>
                                <button className="button small outline" onClick={loadDemo}>Load demo tasks</button>
                            </div>
                        } elif len([t for t in data.tasks if t.completed == (taskTab == "done")]) == 0 {
                            <p className="quiet tab-empty">
                                {"Nothing finished yet." if taskTab == "done" else "🎉 Every task is done."}
                            </p>
                        } else {
                            <ul className="tasks">
                                {[<TaskItem
                                    key={t.id}
                                    task={t}
                                    onDone={finishTask}
                                    onEdit={startEdit}
                                    onDelete={removeTask}
                                /> for t in sorted(data.tasks, key=task_order) if t.completed == (taskTab == "done")]}
                            </ul>
                        }}
                    </section>
                </main>

                <aside className="side">
                    <CalendarPanel
                        cal={cal}
                        view={calView}
                        onView={lambda (v: str) { loadCalendar(v, view_anchor(cal, calAnchor), 0); }}
                        onShift={lambda (n: int) { loadCalendar(calView, calAnchor if n != 0 else "", n); }}
                        onToggle={toggleSession}
                        onOpenDay={openDay}
                        onTip={tipFor}
                        focusId={focusId}
                    />

                    <section className="panel">
                        <div className="panel-head">
                            <div>
                                <h2>Reserved time</h2>
                                <span className="sub">Classes, sleep, meals — no to-dos are placed here</span>
                            </div>
                            <button className="button small outline" onClick={lambda { error = ""; modal = "busy"; }}>+ Add</button>
                        </div>
                        {if len(data.reserved_blocks) == 0 {
                            <div className="empty">
                                <p>Add classes, sleep, meals or work so planned work avoids them.</p>
                                <button className="button small outline" onClick={loadRoutine}>Use a typical student routine</button>
                            </div>
                        } else {
                            <ul className="busy-list">
                                {[<BusyRow key={b.id} block={b} onDelete={removeBlock}/> for b in data.reserved_blocks]}
                            </ul>
                        }}
                    </section>
                </aside>
            </div>
        }}

        {if modal == "task" {
            <div className="overlay" onClick={lambda { modal = ""; error = ""; clearForm(); }}>
                <div className="modal" onClick={lambda (e: MouseEvent) { e.stopPropagation(); }}>
                    <div className="modal-head">
                        <h2>{"Edit task" if editId else "New task"}</h2>
                        <button className="icon" onClick={lambda { modal = ""; error = ""; clearForm(); }}>×</button>
                    </div>
                    <p className="sub">StudyFlow places the estimated work into your free time before the due date, keeping each task in as few blocks as possible.</p>
                    <form onSubmit={lambda (e: FormEvent) { e.preventDefault(); saveTask(); }}>
                        <label>What do you need to do?
                            <input value={title} required autoFocus={True} placeholder="e.g. Project milestone 2" onChange={lambda (e: ChangeEvent) { title = e.target.value; }}/>
                        </label>
                        <div className="row">
                            <label>Course
                                <input value={course} placeholder="e.g. CSE 449" onChange={lambda (e: ChangeEvent) { course = e.target.value; }}/>
                            </label>
                            <label>
                                <span className="label-line">Location<span className="optional">optional</span></span>
                                <input value={taskLocation} maxLength={80} placeholder="e.g. Duderstadt Library" onChange={lambda (e: ChangeEvent) { taskLocation = e.target.value; }}/>
                            </label>
                        </div>
                        <div className="row">
                            <label>Due date
                                <input type="date" value={dueDate} required onChange={lambda (e: ChangeEvent) { dueDate = e.target.value; }}/>
                            </label>
                            <label>
                                <span className="label-line">
                                    Due time
                                    {if dueTime {
                                        <button type="button" className="mini-link" onClick={lambda { dueTime = ""; }}>Clear</button>
                                    } else {
                                        <span className="optional">optional</span>
                                    }}
                                </span>
                                <input type="time" step="300" value={dueTime} onChange={lambda (e: ChangeEvent) { dueTime = e.target.value; }}/>
                            </label>
                        </div>
                        <span className="field-hint">{"Work will be finished before " + (clock_text(dueTime) if dueTime else "the end of the day") + " on the due date."}</span>
                        <label>{"Estimated work · " + minute_text(int(estimate) if estimate else 0)}
                            <input type="number" min="15" max="1440" step="5" value={estimate} required onChange={lambda (e: ChangeEvent) { estimate = e.target.value; }}/>
                        </label>
                        <label>Priority
                            <div className="segmented full">
                                {[<button
                                    key={p}
                                    type="button"
                                    className={"seg" + (" on" if priority == p else "")}
                                    onClick={lambda { priority = p; }}
                                >{p[0].upper() + p[1:]}</button> for p in ["high", "medium", "low"]]}
                            </div>
                        </label>
                        {if error {
                            <div className="form-error" role="alert">{error}</div>
                        }}
                        <button className="button primary full" disabled={busy} type="submit">
                            {"Save changes" if editId else "Add & schedule"}
                        </button>
                    </form>
                </div>
            </div>
        }}

        {if modal == "reopen" and reopening is not None {
            <div className="overlay" onClick={lambda { modal = ""; error = ""; }}>
                <div className="modal" onClick={lambda (e: MouseEvent) { e.stopPropagation(); }}>
                    <div className="modal-head">
                        <h2>Reopen task</h2>
                        <button className="icon" onClick={lambda { modal = ""; error = ""; }}>×</button>
                    </div>
                    <p className="sub">
                        {"All " + minute_text(reopening.estimated_minutes) + " planned for \"" + reopening.title + "\" is already checked off. How much more time do you need?"}
                    </p>
                    <form onSubmit={lambda (e: FormEvent) { e.preventDefault(); saveReopen(); }}>
                        <label>{"More time · " + minute_text(int(extraMinutes) if extraMinutes else 0)}
                            <input type="number" min="5" max="1440" step="5" value={extraMinutes} required autoFocus={True} onChange={lambda (e: ChangeEvent) { extraMinutes = e.target.value; }}/>
                        </label>
                        {if error {
                            <div className="form-error" role="alert">{error}</div>
                        }}
                        <button className="button primary full" disabled={busy} type="submit">Reopen & plan</button>
                    </form>
                </div>
            </div>
        }}

        {if modal == "busy" {
            <div className="overlay" onClick={lambda { modal = ""; error = ""; }}>
                <div className="modal" onClick={lambda (e: MouseEvent) { e.stopPropagation(); }}>
                    <div className="modal-head">
                        <h2>Add reserved time</h2>
                        <button className="icon" onClick={lambda { modal = ""; error = ""; }}>×</button>
                    </div>
                    <p className="sub">A recurring block (class, sleep, work…). Planned work is moved around it.</p>
                    <form onSubmit={lambda (e: FormEvent) { e.preventDefault(); saveBlock(); }}>
                        <label>Name
                            <input value={blockLabel} required autoFocus={True} placeholder="e.g. EECS 482 lecture" onChange={lambda (e: ChangeEvent) { blockLabel = e.target.value; }}/>
                        </label>
                        <label>
                            <span className="label-line">Location<span className="optional">optional</span></span>
                            <input value={blockLocation} maxLength={80} placeholder="e.g. 1670 Beyster" onChange={lambda (e: ChangeEvent) { blockLocation = e.target.value; }}/>
                        </label>
                        <label>Type
                                <select value={blockCategory} onChange={lambda (e: ChangeEvent) { blockCategory = e.target.value; }}>
                                    <option value="class">Class</option>
                                    <option value="sleep">Sleep</option>
                                    <option value="meal">Meal</option>
                                    <option value="exercise">Exercise</option>
                                    <option value="commute">Commute</option>
                                    <option value="other">Other</option>
                                </select>
                        </label>
                        <div className="field">
                            <div className="field-head">
                                <span>Repeats on</span>
                                <div className="presets">
                                    {[<button
                                        key={preset}
                                        type="button"
                                        className={"preset" + (" on" if same_days(blockDays, preset_days(preset)) else "")}
                                        onClick={lambda { blockDays = preset_days(preset); }}
                                    >{preset}</button> for preset in ["Every day", "Weekdays", "Weekends"]]}
                                </div>
                            </div>
                            <div className="days">
                                {[<button
                                    key={code}
                                    type="button"
                                    aria-pressed={code in blockDays}
                                    className={"day-toggle" + (" on" if code in blockDays else "")}
                                    onClick={lambda { toggleDay(code); }}
                                >{code[0].upper() + code[1:]}</button> for code in DAY_CODES]}
                            </div>
                            {if len(blockDays) == 0 {
                                <span className="field-hint warn">Pick at least one day.</span>
                            }}
                        </div>
                        <div className="row">
                            <label>Starts<input type="time" step="300" value={blockStart} required onChange={lambda (e: ChangeEvent) { blockStart = e.target.value; }}/></label>
                            <label>Ends<input type="time" step="300" value={blockEnd} required onChange={lambda (e: ChangeEvent) { blockEnd = e.target.value; }}/></label>
                        </div>
                        {if error {
                            <div className="form-error" role="alert">{error}</div>
                        }}
                        <button className="button primary full" disabled={busy or len(blockDays) == 0} type="submit">Add reserved time</button>
                    </form>
                </div>
            </div>
        }}
        {if tip is not None {
            <div
                className={"tip " + ("below" if tipBelow else "above")}
                style={{"left": str(tipX) + "px", "top": str(tipY) + "px", "--c": tip.color or "#94a3b8"}}
                role="tooltip"
                onClick={hideTip}
            >
                <TipCard item={tip}/>
            </div>
        }}
    </div>
}
