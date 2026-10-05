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
    toggle_task,
    update_task
}
import "./styles.css";

glob HOUR_PX_DAY: int = 72,
     HOUR_PX_WEEK: int = 48;

def minute_text(total: int) -> str {
    hour = total // 60;
    minute = total % 60;
    if hour > 0 and minute > 0 { return str(hour) + "h " + str(minute) + "m"; }
    if hour > 0 { return str(hour) + "h"; }
    return str(minute) + "m";
}

def hour_label(hour: int) -> str {
    shown = hour % 12;
    if shown == 0 { shown = 12; }
    return str(shown) + (" AM" if hour % 24 < 12 else " PM");
}

glob DAY_CODES: list[str] = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"];

def day_rule(days: list[str]) -> str {
    rule = "";
    for code in DAY_CODES {
        if code in days { rule = rule + ("," if rule else "") + code; }
    }
    return rule;
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

def StatCard(icon: str, label: str, value: str, hint: str) -> JsxElement {
    <div className="stat">
        <div className="stat-icon">{icon}</div>
        <div className="stat-body">
            <span className="stat-label">{label}</span>
            <strong className="stat-value">{value}</strong>
            <span className="stat-hint">{hint}</span>
        </div>
    </div>
}

def PlanHealth(
    data: DashboardData,
    busy: bool,
    onReplan: Callable[[], None]
) -> JsxElement {
    tone = "ok";
    headline = "Everything fits before its deadline";
    detail = minute_text(data.scheduled_minutes) + " of work is on your calendar.";
    if data.remaining_minutes == 0 {
        headline = "Nothing left to schedule";
        detail = "Add a task and it will be placed into your free time.";
    }
    if data.overload_minutes > 0 {
        tone = "warn";
        headline = minute_text(data.overload_minutes) + " of work doesn't fit";
        detail = "Not enough free time before the deadline. Remove reserved time or move the due date.";
    }
    overdue = [t for t in data.tasks if not t.completed and t.days_left < 0];
    if len(overdue) > 0 {
        tone = "warn";
        headline = str(len(overdue)) + " task" + ("" if len(overdue) == 1 else "s") + " past due";
        detail = overdue[0].title + " is " + overdue[0].due_label.lower() + ". Finish it or edit its due date, then reschedule.";
    }
    if data.missed_sessions > 0 {
        tone = "warn";
        headline = str(data.missed_sessions) + " missed block" + ("" if data.missed_sessions == 1 else "s") + " (" + minute_text(data.missed_minutes) + ")";
        detail = "Earlier work blocks you didn't finish. Reschedule to move that work into upcoming free time.";
    }
    <div className={"health " + tone}>
        <div className="health-top">
            <span className="health-badge">{"✓" if tone == "ok" else "!"}</span>
            <div>
                <span className="stat-label">Schedule status</span>
                <strong>{headline}</strong>
            </div>
        </div>
        <p>{detail}</p>
        <button
            className={"button " + ("primary" if tone == "warn" else "outline")}
            disabled={busy}
            onClick={lambda { onReplan(); }}
            title="Clears unfinished sessions and re-spreads the remaining work into your free time, earliest deadline first. Completed blocks are kept."
        >
            {"Rescheduling…" if busy else "↻ Reschedule unfinished work"}
        </button>
        <span className="health-foot">Re-spreads unfinished work into free slots, earliest deadline first. Finished blocks stay.</span>
    </div>
}

# ---------- Calendar ----------

def SessionBlock(
    item: CalendarItem,
    startHour: int,
    hourPx: int,
    compact: bool,
    onComplete: Callable[[str], None]
) -> JsxElement {
    top = int((item.start_minute - startHour * 60) * hourPx / 60);
    height = max(16, int(item.duration * hourPx / 60) - 2);
    # Short sessions collapse to a single line so they never spill over
    # the block below them.
    size = "tiny" if height < 30 else ("short" if height < 46 else "");
    state = "done" if item.completed else ("missed" if item.missed else "");
    <div
        className={"block session " + state + " " + size + (" compact" if compact else "")}
        style={{"top": str(top) + "px", "height": str(height) + "px", "--c": item.color}}
        title={item.title + " · " + item.course + " · " + item.time_label}
    >
        <div className="block-text">
            <strong>{item.title}</strong>
            {if not (compact and size == "tiny") {
                <span>{item.time_label if compact else item.time_label + " · " + item.course}</span>
            }}
        </div>
        {if item.missed {
            <em className="missed-tag">Missed</em>
        } elif item.completed {
            <span className="block-done">✓</span>
        } else {
            <button
                className="block-check"
                title="Mark this block done"
                onClick={lambda { onComplete(item.id); }}
            >✓</button>
        }}
    </div>
}

def BusyBlock(item: CalendarItem, startHour: int, hourPx: int) -> JsxElement {
    top = int((item.start_minute - startHour * 60) * hourPx / 60);
    height = max(14, int(item.duration * hourPx / 60) - 2);
    <div
        className="block busy"
        style={{"top": str(top) + "px", "height": str(height) + "px"}}
        title={item.title + " · " + item.time_label}
    >
        <span>{item.title}</span>
    </div>
}

def TimeGrid(
    cal: CalendarData,
    compact: bool,
    onComplete: Callable[[str], None],
    onOpenDay: Callable[[str], None]
) -> JsxElement {
    hourPx = HOUR_PX_WEEK if compact else HOUR_PX_DAY;
    hours = list(range(cal.start_hour, cal.end_hour));
    gridHeight = (cal.end_hour - cal.start_hour) * hourPx;
    cols = "56px repeat(" + str(len(cal.days)) + ", minmax(0, 1fr))";
    <div className={"timegrid " + ("week" if compact else "day")}>
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
                    {"Due · " + due.title}
                </span> for due in d.due]}
            </button> for d in cal.days]}
        </div>
        <div className="tg-body" style={{"gridTemplateColumns": cols}}>
            <div className="tg-hours" style={{"height": str(gridHeight) + "px"}}>
                {[<span key={h} style={{"top": str((h - cal.start_hour) * hourPx) + "px"}}>{hour_label(h)}</span> for h in hours]}
            </div>
            {[<div
                key={d.date}
                className={"tg-col " + ("today" if d.is_today else "")}
                style={{"height": str(gridHeight) + "px", "backgroundSize": "100% " + str(hourPx) + "px"}}
            >
                {[<BusyBlock key={b.id} item={b} startHour={cal.start_hour} hourPx={hourPx}/> for b in d.busy]}
                {[<SessionBlock
                    key={s.id}
                    item={s}
                    startHour={cal.start_hour}
                    hourPx={hourPx}
                    compact={compact}
                    onComplete={onComplete}
                /> for s in d.sessions]}
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
            {"Due · " + due.title}
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

def DayAgenda(
    cal: CalendarData,
    onComplete: Callable[[str], None]
) -> JsxElement {
    day = cal.days[0];
    <div className="agenda">
        <h3>Work blocks</h3>
        {if len(day.sessions) == 0 {
            <p className="quiet">Nothing planned on this day.</p>
        } else {
            <ul>
                {[<li key={s.id} className={("done" if s.completed else "") + (" missed" if s.missed else "")} style={{"--c": s.color}}>
                    <span className="ag-time">{s.time_label}</span>
                    <div className="ag-copy">
                        <strong>{s.title}</strong>
                        <span>{s.course + " · " + minute_text(s.duration)}</span>
                    </div>
                    {if s.completed {
                        <span className="ag-state">Done</span>
                    } elif s.missed {
                        <span className="ag-state missed">Missed</span>
                    } else {
                        <button className="button small outline" onClick={lambda { onComplete(s.id); }}>Mark done</button>
                    }}
                </li> for s in day.sessions]}
            </ul>
        }}
        <div className="agenda-foot">
            <span>{"Planned " + minute_text(day.study_minutes)}</span>
            <span>{"Still free " + minute_text(day.free_minutes)}</span>
        </div>
    </div>
}

def CalendarPanel(
    cal: CalendarData | None,
    view: str,
    onView: Callable[[str], None],
    onShift: Callable[[int], None],
    onToday: Callable[[], None],
    onComplete: Callable[[str], None],
    onOpenDay: Callable[[str], None]
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
                <button className="button small outline" onClick={lambda { onToday(); }}>Today</button>
                <button className="nav-btn" aria-label="Next" onClick={lambda { onShift(1); }}>›</button>
            </div>
            <h2 className="cal-title">{cal.title if cal is not None else ""}</h2>
            <div className="legend">
                <span><span className="lg study"></span>Work block</span>
                <span><span className="lg busy"></span>Reserved time</span>
                <span><span className="lg due"></span>Deadline</span>
            </div>
        </div>
        {if cal is None {
            <div className="quiet pad">Loading calendar…</div>
        } elif cal.view == "month" {
            <MonthGrid cal={cal} onOpenDay={onOpenDay}/>
        } elif cal.view == "week" {
            <TimeGrid cal={cal} compact={True} onComplete={onComplete} onOpenDay={onOpenDay}/>
        } else {
            <div className="day-split">
                <TimeGrid cal={cal} compact={False} onComplete={onComplete} onOpenDay={onOpenDay}/>
                <DayAgenda cal={cal} onComplete={onComplete}/>
            </div>
        }}
    </section>
}

# ---------- Side panels ----------

def TaskItem(
    task: TaskView,
    onToggle: Callable[[str], None],
    onEdit: Callable[[TaskView], None],
    onDelete: Callable[[str], None]
) -> JsxElement {
    done_minutes = task.completed_minutes;
    <li className={"task" + (" done" if task.completed else "")} style={{"--c": task.color}}>
        <button
            className={"check" + (" on" if task.completed else "")}
            aria-label={"Mark not done" if task.completed else "Mark done"}
            title={"Mark not done" if task.completed else "Mark whole task done"}
            onClick={lambda { onToggle(task.id); }}
        >{"✓" if task.completed else ""}</button>
        <div className="task-body">
            <div className="task-line">
                <strong>{task.title}</strong>
                <span className={"due " + due_tone(task)}>{task.due_label}</span>
            </div>
            <div className="task-meta">
                <span className="course"><span className="dot"></span>{task.course}</span>
                {if task.priority == "high" {
                    <span className="prio">High priority</span>
                }}
                <span>{minute_text(done_minutes) + " / " + minute_text(task.estimated_minutes) + " done"}</span>
            </div>
            <div className="bar"><span style={{"width": str(task.progress) + "%"}}></span></div>
        </div>
        <div className="task-actions">
            <button className="icon" title="Edit task" onClick={lambda { onEdit(task); }}>✎</button>
            <button className="icon danger" title="Delete task" onClick={lambda { onDelete(task.id); }}>🗑</button>
        </div>
    </li>
}

def BusyRow(block: ReservedBlockView, onDelete: Callable[[str], None]) -> JsxElement {
    <li className="busy-row">
        <span className={"cat " + block.category}></span>
        <div>
            <strong>{block.label}</strong>
            <span>{clock_text(block.start_time) + " – " + clock_text(block.end_time) + " · " + block.repeat_label}</span>
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
        showDone: bool = False,
        title: str = "",
        course: str = "",
        dueDate: str = "",
        estimate: str = "60",
        priority: str = "medium",
        editId: str = "",
        blockLabel: str = "",
        blockCategory: str = "class",
        blockStart: str = "10:00",
        blockEnd: str = "11:30",
        blockDays: list[str] = ["mon", "tue", "wed", "thu", "fri"];

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
            error = str(e);
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
            error = "Could not reach the planner server. " + str(e);
        } finally {
            loading = False;
        }
    }

    def clearForm {
        title = "";
        course = "";
        dueDate = "";
        estimate = "60";
        priority = "medium";
        editId = "";
    }

    def openNewTask {
        clearForm();
        modal = "task";
    }

    async def saveTask {
        if busy { return; }
        try {
            busy = True;
            error = "";
            if editId {
                next = await update_task(
                    editId, title, course, dueDate, int(estimate), priority
                );
            } else {
                next = await add_task(
                    title, course, dueDate, int(estimate), priority
                );
            }
            clearForm();
            modal = "";
            await apply(next);
        } except Exception as e {
            error = str(e);
        } finally {
            busy = False;
        }
    }

    def startEdit(task: TaskView) {
        editId = task.id;
        title = task.title;
        course = task.course;
        dueDate = task.due_date;
        estimate = str(task.estimated_minutes);
        priority = task.priority;
        modal = "task";
    }

    async def toggleTask(id: str) {
        try { await apply(await toggle_task(id)); }
        except Exception as e { error = str(e); }
    }

    async def removeTask(id: str) {
        try { await apply(await delete_task(id)); }
        except Exception as e { error = str(e); }
    }

    async def finishSession(id: str) {
        try { await apply(await complete_session(id)); }
        except Exception as e { error = str(e); }
    }

    async def runReplan {
        try { busy = True; await apply(await replan()); }
        except Exception as e { error = str(e); }
        finally { busy = False; }
    }

    async def loadDemo {
        try { await apply(await seed_demo()); }
        except Exception as e { error = str(e); }
    }

    async def saveBlock {
        if busy { return; }
        try {
            busy = True;
            next = await add_reserved_block(
                blockLabel, blockCategory, blockStart, blockEnd, day_rule(blockDays)
            );
            blockLabel = "";
            modal = "";
            await apply(next);
        } except Exception as e { error = str(e); }
        finally { busy = False; }
    }

    async def removeBlock(id: str) {
        try { await apply(await delete_reserved_block(id)); }
        except Exception as e { error = str(e); }
    }

    async def loadRoutine {
        try { await apply(await seed_routine()); }
        except Exception as e { error = str(e); }
    }

    async def openDay(day: str) { await loadCalendar("day", day, 0); }

    async can with entry { await loadData(); }

    <div className="page">
        <header className="top">
            <div className="brand">
                <span className="logo">S</span>
                <strong>StudyFlow</strong>
                <span className="today-text">{data.today if data is not None else ""}</span>
            </div>
            <div className="top-actions">
                <button className="button outline" onClick={lambda { modal = "busy"; }}>+ Reserved time</button>
                <button className="button primary" onClick={openNewTask}>+ New task</button>
            </div>
        </header>

        {if error {
            <div className="toast error"><span>{error}</span><button onClick={lambda { error = ""; }}>×</button></div>
        }}
        {if notice {
            <div className="toast info"><span>{notice}</span><button onClick={lambda { notice = ""; }}>×</button></div>
        }}

        {if loading {
            <div className="panel quiet pad">Loading your plan…</div>
        } elif data is not None {
            <section className="summary">
                <StatCard
                    icon="📋"
                    label="Open tasks"
                    value={str(data.active_tasks)}
                    hint={str(data.due_this_week) + " due in the next 7 days"}
                />
                <StatCard
                    icon="⏳"
                    label="Work left"
                    value={minute_text(data.remaining_minutes)}
                    hint="estimated time still needed"
                />
                <StatCard
                    icon="📅"
                    label="Planned today"
                    value={minute_text(sum([s.duration for s in data.today_sessions]))}
                    hint={str(len([s for s in data.today_sessions if not s.completed])) + " blocks left today"}
                />
                <PlanHealth data={data} busy={busy} onReplan={runReplan}/>
            </section>

            <div className="layout">
                <CalendarPanel
                    cal={cal}
                    view={calView}
                    onView={lambda (v: str) { loadCalendar(v, calAnchor, 0); }}
                    onShift={lambda (n: int) { loadCalendar(calView, calAnchor, n); }}
                    onToday={lambda { loadCalendar(calView, "", 0); }}
                    onComplete={finishSession}
                    onOpenDay={openDay}
                />

                <aside className="side">
                    <section className="panel">
                        <div className="panel-head">
                            <div>
                                <h2>Tasks</h2>
                                <span className="sub">Assignments to be scheduled</span>
                            </div>
                            <button className="button small outline" onClick={openNewTask}>+ Add</button>
                        </div>
                        {if len(data.tasks) == 0 {
                            <div className="empty">
                                <p>No tasks yet. Add one and it will be placed into your free time automatically.</p>
                                <button className="button small outline" onClick={loadDemo}>Load demo tasks</button>
                            </div>
                        } else {
                            <ul className="tasks">
                                {[<TaskItem
                                    key={t.id}
                                    task={t}
                                    onToggle={toggleTask}
                                    onEdit={startEdit}
                                    onDelete={removeTask}
                                /> for t in data.tasks if not t.completed]}
                            </ul>
                        }}
                        {if data.completed_tasks > 0 {
                            <button className="link" onClick={lambda { showDone = not showDone; }}>
                                {("Hide" if showDone else "Show") + " completed (" + str(data.completed_tasks) + ")"}
                            </button>
                        }}
                        {if showDone {
                            <ul className="tasks">
                                {[<TaskItem
                                    key={t.id}
                                    task={t}
                                    onToggle={toggleTask}
                                    onEdit={startEdit}
                                    onDelete={removeTask}
                                /> for t in data.tasks if t.completed]}
                            </ul>
                        }}
                    </section>

                    <section className="panel">
                        <div className="panel-head">
                            <div>
                                <h2>Reserved time</h2>
                                <span className="sub">Fixed commitments — nothing is scheduled here</span>
                            </div>
                            <button className="button small outline" onClick={lambda { modal = "busy"; }}>+ Add</button>
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
            <div className="overlay" onClick={lambda { modal = ""; clearForm(); }}>
                <div className="modal" onClick={lambda (e: MouseEvent) { e.stopPropagation(); }}>
                    <div className="modal-head">
                        <h2>{"Edit task" if editId else "New task"}</h2>
                        <button className="icon" onClick={lambda { modal = ""; clearForm(); }}>×</button>
                    </div>
                    <p className="sub">StudyFlow places the estimated work into your free time before the due date, keeping each task in as few blocks as possible.</p>
                    <form onSubmit={lambda (e: FormEvent) { e.preventDefault(); saveTask(); }}>
                        <label>What do you need to do?
                            <input value={title} required autoFocus={True} placeholder="e.g. Project milestone 2" onChange={lambda (e: ChangeEvent) { title = e.target.value; }}/>
                        </label>
                        <label>Course
                            <input value={course} placeholder="e.g. CSE 449" onChange={lambda (e: ChangeEvent) { course = e.target.value; }}/>
                        </label>
                        <div className="row">
                            <label>Due date
                                <input type="date" value={dueDate} required onChange={lambda (e: ChangeEvent) { dueDate = e.target.value; }}/>
                            </label>
                            <label>{"Estimated work · " + minute_text(int(estimate) if estimate else 0)}
                                <input type="number" min="15" max="1440" step="15" value={estimate} required onChange={lambda (e: ChangeEvent) { estimate = e.target.value; }}/>
                            </label>
                        </div>
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
                        <button className="button primary full" disabled={busy} type="submit">
                            {"Save changes" if editId else "Add & schedule"}
                        </button>
                    </form>
                </div>
            </div>
        }}

        {if modal == "busy" {
            <div className="overlay" onClick={lambda { modal = ""; }}>
                <div className="modal" onClick={lambda (e: MouseEvent) { e.stopPropagation(); }}>
                    <div className="modal-head">
                        <h2>Add reserved time</h2>
                        <button className="icon" onClick={lambda { modal = ""; }}>×</button>
                    </div>
                    <p className="sub">A recurring block (class, sleep, work…). Planned work is moved around it.</p>
                    <form onSubmit={lambda (e: FormEvent) { e.preventDefault(); saveBlock(); }}>
                        <label>Name
                            <input value={blockLabel} required autoFocus={True} placeholder="e.g. EECS 482 lecture" onChange={lambda (e: ChangeEvent) { blockLabel = e.target.value; }}/>
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
                            <label>Starts<input type="time" value={blockStart} required onChange={lambda (e: ChangeEvent) { blockStart = e.target.value; }}/></label>
                            <label>Ends<input type="time" value={blockEnd} required onChange={lambda (e: ChangeEvent) { blockEnd = e.target.value; }}/></label>
                        </div>
                        <button className="button primary full" disabled={busy or len(blockDays) == 0} type="submit">Add reserved time</button>
                    </form>
                </div>
            </div>
        }}
    </div>
}
