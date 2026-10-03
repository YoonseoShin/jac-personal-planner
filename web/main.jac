import from core.planner_service {
    DashboardData,
    DayLoad,
    ReservedBlockView,
    SessionView,
    TaskView,
    add_reserved_block,
    add_task,
    complete_session,
    delete_reserved_block,
    delete_task,
    get_dashboard,
    replan,
    save_planning_window,
    seed_demo,
    seed_routine,
    toggle_task,
    update_task
}
import "./styles.css";

def minute_text(total: int) -> str {
    hour = total // 60;
    minute = total % 60;
    if hour > 0 and minute > 0 { return f"{hour}h {minute}m"; }
    if hour > 0 { return f"{hour}h"; }
    return f"{minute}m";
}

def priority_label(priority: str) -> str {
    return priority[0].upper() + priority[1:];
}

def EmptyPlan(onDemo: Callable[[], None]) -> JsxElement {
    <div className="empty-state">
        <div className="empty-icon">✦</div>
        <h3>Your week is wide open</h3>
        <p>Add an assignment and StudyFlow will split the work into realistic sessions.</p>
        <button className="button secondary" onClick={lambda { onDemo(); }}>
            Load demo week
        </button>
    </div>
}

def Metric(label: str, value: str, tone: str = "") -> JsxElement {
    <div className={"metric " + tone}>
        <span>{label}</span>
        <strong>{value}</strong>
    </div>
}

def TaskCard(
    task: TaskView,
    onToggle: Callable[[str], None],
    onEdit: Callable[[TaskView], None],
    onDelete: Callable[[str], None]
) -> JsxElement {
    <article className={"task-card " + ("done" if task.completed else "")}>
        <button
            className={"check " + ("checked" if task.completed else "")}
            aria-label="Toggle task"
            onClick={lambda { onToggle(task.id); }}
        >
            {"✓" if task.completed else ""}
        </button>
        <div className="task-main">
            <div className="task-topline">
                <span className="course-chip">{task.course}</span>
                <span className={"priority " + task.priority}>
                    {priority_label(task.priority)}
                </span>
            </div>
            <h3>{task.title}</h3>
            <div className="task-meta">
                <span>{task.due_label}</span>
                <span>{minute_text(max(0, task.estimated_minutes - task.completed_minutes))} remaining</span>
            </div>
            <div className="progress-track">
                <span style={{width: str(task.progress) + "%"}}></span>
            </div>
        </div>
        <div className="task-actions">
            <button className="icon-button" title="Edit task" onClick={lambda { onEdit(task); }}>Edit</button>
            <button className="icon-button danger" title="Delete task" onClick={lambda { onDelete(task.id); }}>Delete</button>
        </div>
    </article>
}

def SessionRow(
    session: SessionView,
    onComplete: Callable[[str], None]
) -> JsxElement {
    <div className={"session-row " + ("done" if session.completed else "")}>
        <div className="session-time">
            <strong>{session.start_time}</strong>
            <span>{minute_text(session.duration)}</span>
        </div>
        <div className="session-rule"></div>
        <div className="session-copy">
            <span>{session.course}</span>
            <strong>{session.title}</strong>
        </div>
        <button
            className="session-check"
            disabled={session.completed}
            onClick={lambda { onComplete(session.id); }}
        >
            {"Done" if session.completed else "Complete"}
        </button>
    </div>
}

def WorkloadBar(load: DayLoad) -> JsxElement {
    percent = min(100, int((load.minutes * 100) / max(1, load.capacity)));
    <div className="load-column">
        <div className="load-bar-wrap">
            <span className="load-bar" style={{height: str(max(4, percent)) + "%"}}></span>
        </div>
        <strong>{load.label}</strong>
        <span>{minute_text(load.minutes)}</span>
    </div>
}

def repeat_label(value: str) -> str {
    if value == "weekdays" { return "Weekdays"; }
    if value == "weekends" { return "Weekends"; }
    return "Every day";
}

def ReservedRow(
    block: ReservedBlockView,
    onDelete: Callable[[str], None]
) -> JsxElement {
    <div className="reserved-row">
        <span className={"category-dot " + block.category}></span>
        <div className="reserved-copy">
            <strong>{block.label}</strong>
            <span>{block.start_time}–{block.end_time} · {repeat_label(block.repeat_rule)}</span>
        </div>
        <button className="remove-block" aria-label="Remove protected time" onClick={lambda { onDelete(block.id); }}>×</button>
    </div>
}

def:pub app -> JsxElement {
    has data: DashboardData | None = None,
        loading: bool = True,
        busy: bool = False,
        error: str = "",
        title: str = "",
        course: str = "",
        dueDate: str = "",
        estimate: str = "60",
        priority: str = "medium",
        editId: str = "",
        blockLabel: str = "",
        blockCategory: str = "sleep",
        blockStart: str = "23:00",
        blockEnd: str = "08:00",
        blockRepeat: str = "daily",
        startHour: str = "8",
        endHour: str = "23";

    async def loadData {
        try {
            loading = True;
            error = "";
            data = await get_dashboard();
            if data is not None {
                startHour = str(data.settings.start_hour);
                endHour = str(data.settings.end_hour);
            }
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

    async def saveTask {
        if busy { return; }
        try {
            busy = True;
            error = "";
            if editId {
                data = await update_task(
                    editId, title, course, dueDate, int(estimate), priority
                );
            } else {
                data = await add_task(
                    title, course, dueDate, int(estimate), priority
                );
            }
            clearForm();
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
    }

    async def toggleTask(id: str) {
        try { data = await toggle_task(id); }
        except Exception as e { error = str(e); }
    }

    async def removeTask(id: str) {
        try { data = await delete_task(id); }
        except Exception as e { error = str(e); }
    }

    async def finishSession(id: str) {
        try { data = await complete_session(id); }
        except Exception as e { error = str(e); }
    }

    async def runReplan {
        try { busy = True; data = await replan(); }
        except Exception as e { error = str(e); }
        finally { busy = False; }
    }

    async def loadDemo {
        try { data = await seed_demo(); }
        except Exception as e { error = str(e); }
    }

    async def savePrefs {
        try {
            busy = True;
            data = await save_planning_window(int(startHour), int(endHour));
        } except Exception as e { error = str(e); }
        finally { busy = False; }
    }

    async def saveBlock {
        if busy { return; }
        try {
            busy = True;
            data = await add_reserved_block(
                blockLabel, blockCategory, blockStart, blockEnd, blockRepeat
            );
            blockLabel = "";
        } except Exception as e { error = str(e); }
        finally { busy = False; }
    }

    async def removeBlock(id: str) {
        try { data = await delete_reserved_block(id); }
        except Exception as e { error = str(e); }
    }

    async def loadRoutine {
        try { data = await seed_routine(); }
        except Exception as e { error = str(e); }
    }

    async can with entry { await loadData(); }

    <div className="app-shell">
        <aside className="sidebar">
            <div className="brand">
                <span className="brand-mark">S</span>
                <div><strong>StudyFlow</strong><span>Personal planner</span></div>
            </div>
            <nav>
                <a className="active" href="#today"><span>◉</span> Today</a>
                <a href="#tasks"><span>□</span> Assignments</a>
                <a href="#availability"><span>◷</span> Availability</a>
            </nav>
            <div className="sidebar-note">
                <span>SMART SCHEDULING</span>
                <p>Study sessions are placed only in the open time between your protected routines.</p>
            </div>
        </aside>

        <main>
            <header className="topbar">
                <div>
                    <p className="eyebrow">ACADEMIC PLANNER</p>
                    <h1>Make time for what matters.</h1>
                    <p>{data.today if data is not None else "Loading your week…"}</p>
                </div>
                <button className="button replan" disabled={busy} onClick={runReplan}>
                    ↻ Replan my week
                </button>
            </header>

            {if error {
                <div className="alert error"><span>{error}</span><button onClick={lambda { error = ""; }}>×</button></div>
            }}
            {if data is not None and data.message {
                <div className="alert success"><span>{data.message}</span></div>
            }}

            {if loading {
                <div className="loading-card">Building your plan…</div>
            } elif data is not None {
                <section className="metrics-grid">
                    <Metric label="Active assignments" value={str(data.active_tasks)}/>
                    <Metric label="Work remaining" value={minute_text(data.remaining_minutes)}/>
                    <Metric label="Scheduled" value={minute_text(data.scheduled_minutes)}/>
                    <Metric
                        label="Needs attention"
                        value={minute_text(data.overload_minutes)}
                        tone={"warning" if data.overload_minutes > 0 else "good"}
                    />
                </section>

                <div className="dashboard-grid">
                    <div className="main-column">
                        <section id="today" className="panel today-panel">
                            <div className="section-heading">
                                <div><p className="eyebrow">FOCUS</p><h2>Today’s plan</h2></div>
                                <span>{minute_text(sum([s.duration for s in data.today_sessions]))}</span>
                            </div>
                            {if len(data.today_sessions) == 0 {
                                <EmptyPlan onDemo={loadDemo}/>
                            } else {
                                <div className="session-list">
                                    {[<SessionRow key={s.id} session={s} onComplete={finishSession}/>
                                        for s in data.today_sessions]}
                                </div>
                            }}
                        </section>

                        <section id="tasks" className="panel">
                            <div className="section-heading">
                                <div><p className="eyebrow">COURSEWORK</p><h2>Assignments</h2></div>
                                <span>{str(data.completed_tasks)} completed</span>
                            </div>
                            {if len(data.tasks) == 0 {
                                <p className="muted-copy">No assignments yet. Add your first one on the right.</p>
                            } else {
                                <div className="task-list">
                                    {[<TaskCard
                                        key={task.id}
                                        task={task}
                                        onToggle={toggleTask}
                                        onEdit={startEdit}
                                        onDelete={removeTask}
                                    /> for task in data.tasks]}
                                </div>
                            }}
                        </section>
                    </div>

                    <div className="side-column">
                        <section className="panel form-panel">
                            <div className="section-heading compact">
                                <div><p className="eyebrow">CAPTURE</p><h2>{"Edit assignment" if editId else "Add assignment"}</h2></div>
                            </div>
                            <form onSubmit={lambda (e: FormEvent) { e.preventDefault(); saveTask(); }}>
                                <label>Assignment
                                    <input value={title} required placeholder="e.g. Project milestone" onChange={lambda (e: ChangeEvent) { title = e.target.value; }}/>
                                </label>
                                <label>Course
                                    <input value={course} placeholder="e.g. CSE 449" onChange={lambda (e: ChangeEvent) { course = e.target.value; }}/>
                                </label>
                                <div className="form-row">
                                    <label>Due date
                                        <input type="date" value={dueDate} required onChange={lambda (e: ChangeEvent) { dueDate = e.target.value; }}/>
                                    </label>
                                    <label>Minutes
                                        <input type="number" min="15" max="1440" value={estimate} required onChange={lambda (e: ChangeEvent) { estimate = e.target.value; }}/>
                                    </label>
                                </div>
                                <label>Priority
                                    <select value={priority} onChange={lambda (e: ChangeEvent) { priority = e.target.value; }}>
                                        <option value="high">High</option>
                                        <option value="medium">Medium</option>
                                        <option value="low">Low</option>
                                    </select>
                                </label>
                                <button className="button primary full" disabled={busy} type="submit">
                                    {"Save changes" if editId else "+ Add and schedule"}
                                </button>
                                {if editId {
                                    <button className="button ghost full" type="button" onClick={clearForm}>Cancel edit</button>
                                }}
                            </form>
                        </section>

                        <section className="panel workload-panel">
                            <div className="section-heading compact">
                                <div><p className="eyebrow">THIS WEEK</p><h2>Study load</h2></div>
                            </div>
                            <div className="load-chart">
                                {[<WorkloadBar key={load.day} load={load}/> for load in data.loads]}
                            </div>
                            <p className="chart-note">Bars show scheduled study time against the time left after protected events.</p>
                        </section>

                        <section id="availability" className="panel availability-panel">
                            <div className="section-heading compact">
                                <div><p className="eyebrow">YOUR ROUTINE</p><h2>Protected time</h2></div>
                                <button className="text-button" onClick={loadRoutine}>Use example</button>
                            </div>
                            <p className="panel-intro">Sleep, meals, classes, exercise, and commute stay off-limits when StudyFlow builds your plan.</p>
                            {if len(data.reserved_blocks) == 0 {
                                <div className="mini-empty">No protected time yet.</div>
                            } else {
                                <div className="reserved-list">
                                    {[<ReservedRow key={b.id} block={b} onDelete={removeBlock}/>
                                        for b in data.reserved_blocks]}
                                </div>
                            }}
                            <form className="block-form" onSubmit={lambda (e: FormEvent) { e.preventDefault(); saveBlock(); }}>
                                <label>Name
                                    <input value={blockLabel} required placeholder="e.g. Morning class" onChange={lambda (e: ChangeEvent) { blockLabel = e.target.value; }}/>
                                </label>
                                <div className="form-row">
                                    <label>Type
                                        <select value={blockCategory} onChange={lambda (e: ChangeEvent) { blockCategory = e.target.value; }}>
                                            <option value="sleep">Sleep</option>
                                            <option value="meal">Meal</option>
                                            <option value="class">Class</option>
                                            <option value="exercise">Exercise</option>
                                            <option value="commute">Commute</option>
                                            <option value="other">Other</option>
                                        </select>
                                    </label>
                                    <label>Repeats
                                        <select value={blockRepeat} onChange={lambda (e: ChangeEvent) { blockRepeat = e.target.value; }}>
                                            <option value="daily">Every day</option>
                                            <option value="weekdays">Weekdays</option>
                                            <option value="weekends">Weekends</option>
                                        </select>
                                    </label>
                                </div>
                                <div className="form-row">
                                    <label>Starts<input type="time" value={blockStart} required onChange={lambda (e: ChangeEvent) { blockStart = e.target.value; }}/></label>
                                    <label>Ends<input type="time" value={blockEnd} required onChange={lambda (e: ChangeEvent) { blockEnd = e.target.value; }}/></label>
                                </div>
                                <button className="button primary full" disabled={busy} type="submit">Add protected time</button>
                            </form>
                            <div className="planning-window">
                                <div><strong>Planning window</strong><span>Study sessions are only placed inside this range.</span></div>
                                <label>From<input type="number" min="0" max="22" value={startHour} onChange={lambda (e: ChangeEvent) { startHour = e.target.value; }}/></label>
                                <label>To<input type="number" min="1" max="24" value={endHour} onChange={lambda (e: ChangeEvent) { endHour = e.target.value; }}/></label>
                                <button className="button secondary" onClick={savePrefs}>Save</button>
                            </div>
                        </section>
                    </div>
                </div>
            }}
        </main>
    </div>
}
