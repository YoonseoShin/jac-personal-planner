import from "@jac/mobui" {
    ActivityIndicator,
    Pressable,
    ScrollView,
    StyleSheet,
    Text,
    TextInput,
    View
}
import from core.errors { friendly_error }
import from core.planner_service {
    DashboardData,
    ReservedBlockView,
    SessionView,
    TaskView,
    add_reserved_block,
    add_task,
    complete_session,
    delete_reserved_block,
    get_dashboard,
    replan,
    seed_demo,
    seed_routine,
    toggle_task,
    uncomplete_session
}

glob styles = StyleSheet.create({
    screen: {flex: 1, backgroundColor: "#f6f6f7"},
    body: {padding: 20, paddingBottom: 56, gap: 18},
    header: {paddingTop: 22, gap: 4},
    eyebrow: {fontSize: 11, letterSpacing: 2, color: "#4f46e5", fontWeight: "800"},
    title: {fontSize: 32, lineHeight: 38, color: "#18181b", fontWeight: "800"},
    subtitle: {fontSize: 14, color: "#71717a"},
    summary: {flexDirection: "row", gap: 10},
    stat: {flex: 1, backgroundColor: "#18181b", borderRadius: 14, padding: 15, gap: 7},
    statAlt: {backgroundColor: "#e4e4e7"},
    statLabel: {fontSize: 11, color: "#d4d4d8"},
    statLabelDark: {fontSize: 11, color: "#71717a"},
    statValue: {fontSize: 23, color: "#ffffff", fontWeight: "800"},
    statValueDark: {fontSize: 23, color: "#18181b", fontWeight: "800"},
    panel: {backgroundColor: "#ffffff", borderRadius: 16, padding: 18, gap: 14, borderWidth: 1, borderColor: "#e4e4e7"},
    panelHeading: {flexDirection: "row", justifyContent: "space-between", alignItems: "center"},
    panelTitle: {fontSize: 20, color: "#18181b", fontWeight: "800"},
    badge: {fontSize: 11, color: "#52525b", backgroundColor: "#f4f4f5", paddingHorizontal: 10, paddingVertical: 6, borderRadius: 999},
    session: {flexDirection: "row", alignItems: "center", gap: 12, paddingVertical: 11, borderTopWidth: 1, borderTopColor: "#f1f1f2"},
    time: {width: 70, gap: 2},
    timeStrong: {fontSize: 13, color: "#18181b", fontWeight: "700"},
    muted: {fontSize: 11, color: "#71717a"},
    sessionRule: {width: 3, alignSelf: "stretch", minHeight: 42, backgroundColor: "#60a5fa", borderRadius: 4},
    sessionCopy: {flex: 1, gap: 3},
    sessionTitle: {fontSize: 14, color: "#18181b", fontWeight: "700"},
    doneButton: {paddingHorizontal: 11, paddingVertical: 8, borderRadius: 9, backgroundColor: "#f4f4f5"},
    doneButtonText: {fontSize: 11, color: "#4f46e5", fontWeight: "800"},
    task: {flexDirection: "row", gap: 12, alignItems: "center", paddingVertical: 10, borderTopWidth: 1, borderTopColor: "#f1f1f2"},
    checkbox: {width: 25, height: 25, borderWidth: 2, borderColor: "#d4d4d8", borderRadius: 7, alignItems: "center", justifyContent: "center"},
    checkboxDone: {backgroundColor: "#4f46e5", borderColor: "#4f46e5"},
    checkmark: {color: "#ffffff", fontWeight: "800"},
    taskCopy: {flex: 1, gap: 3},
    taskTitle: {fontSize: 14, color: "#18181b", fontWeight: "700"},
    taskDone: {fontSize: 14, color: "#a1a1aa", fontWeight: "700", textDecorationLine: "line-through"},
    form: {gap: 10},
    input: {backgroundColor: "#ffffff", color: "#18181b", borderWidth: 1, borderColor: "#d4d4d8", borderRadius: 9, paddingHorizontal: 12, paddingVertical: 11},
    row: {flexDirection: "row", gap: 10},
    half: {flex: 1},
    primary: {backgroundColor: "#4f46e5", borderRadius: 10, padding: 13, alignItems: "center"},
    primaryText: {color: "#ffffff", fontWeight: "800"},
    secondary: {backgroundColor: "#f4f4f5", borderRadius: 10, padding: 11, alignItems: "center", borderWidth: 1, borderColor: "#e4e4e7"},
    secondaryText: {color: "#27272a", fontWeight: "800"},
    empty: {paddingVertical: 28, alignItems: "center", gap: 8},
    emptyTitle: {fontSize: 17, color: "#18181b", fontWeight: "800"},
    emptyText: {fontSize: 13, lineHeight: 19, color: "#71717a", textAlign: "center"},
    error: {backgroundColor: "#fff0ed", borderRadius: 11, padding: 13},
    errorText: {color: "#a83f32", fontSize: 12},
    notice: {backgroundColor: "#eff6ff", borderRadius: 11, padding: 13},
    noticeText: {color: "#1d4ed8", fontSize: 12},
    block: {flexDirection: "row", alignItems: "center", gap: 10, paddingVertical: 10, borderTopWidth: 1, borderTopColor: "#f1f1f2"},
    blockDot: {width: 8, height: 8, borderRadius: 4, backgroundColor: "#818cf8"},
    blockCopy: {flex: 1, gap: 2},
    blockTitle: {fontSize: 13, color: "#18181b", fontWeight: "700"},
    removeText: {fontSize: 12, color: "#dc2626", fontWeight: "700"},
    helper: {fontSize: 12, lineHeight: 18, color: "#71717a"},
    status: {flexDirection: "row", alignItems: "center", gap: 12, borderRadius: 14, padding: 14, borderWidth: 1},
    statusOk: {backgroundColor: "#ecfdf5", borderColor: "#bbf7d0"},
    statusWarn: {backgroundColor: "#fffbeb", borderColor: "#fcd34d"},
    statusHint: {backgroundColor: "#eef2ff", borderColor: "#c7d2fe"},
    statusCopy: {flex: 1, gap: 2},
    statusTitle: {fontSize: 14, color: "#18181b", fontWeight: "800"},
    smallButton: {backgroundColor: "#4f46e5", borderRadius: 9, paddingHorizontal: 12, paddingVertical: 9},
    smallButtonText: {color: "#ffffff", fontSize: 12, fontWeight: "800"},
    todoCheck: {width: 26, height: 26, borderRadius: 13, borderWidth: 2, alignItems: "center", justifyContent: "center", backgroundColor: "#ffffff"},
    moved: {fontSize: 11, color: "#4f46e5", fontWeight: "700"},
    missed: {fontSize: 11, color: "#b45309", fontWeight: "800"}
});

def minute_text(total: int) -> str {
    hour = total // 60;
    minute = total % 60;
    if hour > 0 and minute > 0 { return f"{hour}h {minute}m"; }
    if hour > 0 { return f"{hour}h"; }
    return f"{minute}m";
}

def MobileSession(
    session: SessionView,
    onToggle: Callable[[str, bool], None]
) -> JsxElement {
    <View style={styles.session}>
        <Pressable
            style={[styles.todoCheck, {"borderColor": session.color}, {"backgroundColor": session.color} if session.completed else {}]}
            onPress={lambda { onToggle(session.id, session.completed); }}
        >
            <Text style={styles.checkmark}>{"✓" if session.completed else ""}</Text>
        </Pressable>
        <View style={styles.sessionCopy}>
            <Text style={styles.taskDone if session.completed else styles.sessionTitle}>{session.title}</Text>
            <Text style={styles.muted}>
                {session.course + " · " + session.start_time + " – " + session.end_time + " · " + minute_text(session.duration) + (" · 📍 " + session.location if session.location else "")}
            </Text>
            {if session.moved_from and not session.completed {
                <Text style={styles.moved}>{"↪ Rescheduled from " + session.moved_from}</Text>
            }}
            {if session.added_note and not session.completed {
                <Text style={styles.moved}>{"↪ " + session.added_note}</Text>
            }}
        </View>
        {if session.missed {
            <Text style={styles.missed}>Missed</Text>
        }}
    </View>
}

def MobileTask(task: TaskView, onDone: Callable[[str], None]) -> JsxElement {
    <View style={[styles.task, {"borderLeftWidth": 3, "borderLeftColor": task.color, "paddingLeft": 10}]}>
        <View style={styles.taskCopy}>
            <Text style={styles.taskTitle}>{task.title}</Text>
            <Text style={styles.muted}>
                {task.course + " · " + task.due_label + " · " + minute_text(task.completed_minutes) + " / " + minute_text(task.estimated_minutes) + " done" + (" · 📍 " + task.location if task.location else "")}
            </Text>
        </View>
        <Pressable style={styles.doneButton} onPress={lambda { onDone(task.id); }}>
            <Text style={styles.doneButtonText}>✓ Done</Text>
        </Pressable>
    </View>
}

# Mirrors the web status card: what (if anything) Reschedule would fix.
def status_of(data: DashboardData) -> tuple[str, str] {
    if data.missed_sessions > 0 {
        return ("warn", str(data.missed_sessions) + " missed to-do(s). Reschedule to move them.");
    }
    if data.overlapping > 0 {
        return ("warn", str(data.overlapping) + " to-dos overlap. Reschedule to fix.");
    }
    if len([t for t in data.tasks if t.overdue]) > 0 {
        return ("warn", "A task is past due. Finish it or edit its due date.");
    }
    if data.unfit_minutes > 0 {
        return ("warn", minute_text(data.unfit_minutes) + " of work doesn't fit before its deadline.");
    }
    if data.overload_minutes > data.unfit_minutes {
        return ("warn", minute_text(data.overload_minutes - data.unfit_minutes) + " of work isn't planned yet. Reschedule to plan it.");
    }
    if data.improvable_tasks > 0 {
        return ("hint", "Free time opened up. Reschedule to finish earlier.");
    }
    return ("ok", "On track: your plan is up to date.");
}

def MobileBlock(block: ReservedBlockView, onDelete: Callable[[str], None]) -> JsxElement {
    <View style={styles.block}>
        <View style={styles.blockDot}/>
        <View style={styles.blockCopy}>
            <Text style={styles.blockTitle}>{block.label}</Text>
            <Text style={styles.muted}>{block.start_time}{" – "}{block.end_time}{" · "}{block.repeat_label or block.repeat_rule}{" · 📍 " + block.location if block.location else ""}</Text>
        </View>
        <Pressable onPress={lambda { onDelete(block.id); }}>
            <Text style={styles.removeText}>Remove</Text>
        </Pressable>
    </View>
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
        dueTime: str = "",
        place: str = "",
        blockLabel: str = "",
        blockPlace: str = "",
        blockStart: str = "23:00",
        blockEnd: str = "08:00";

    async def loadData {
        try { loading = True; data = await get_dashboard(); error = ""; }
        except Exception as e { error = friendly_error(str(e)); }
        finally { loading = False; }
    }

    async def toggleSession(id: str, done: bool) {
        try {
            if done { data = await uncomplete_session(id); }
            else { data = await complete_session(id); }
        } except Exception as e { error = friendly_error(str(e)); }
    }

    async def toggle(id: str) {
        try { data = await toggle_task(id); }
        except Exception as e { error = friendly_error(str(e)); }
    }

    async def quickAdd {
        if busy { return; }
        try {
            busy = True;
            data = await add_task(title, course, dueDate, int(estimate), "medium", dueTime, place);
            title = "";
            course = "";
            dueDate = "";
            dueTime = "";
            estimate = "60";
            place = "";
            error = "";
        } except Exception as e { error = friendly_error(str(e)); }
        finally { busy = False; }
    }

    async def runReplan {
        try { busy = True; data = await replan(); }
        except Exception as e { error = friendly_error(str(e)); }
        finally { busy = False; }
    }

    async def loadDemo {
        try { data = await seed_demo(); }
        except Exception as e { error = friendly_error(str(e)); }
    }

    async def addBlock {
        if busy { return; }
        try {
            busy = True;
            data = await add_reserved_block(
                blockLabel, "other", blockStart, blockEnd, "daily", blockPlace
            );
            blockLabel = "";
            blockPlace = "";
            error = "";
        } except Exception as e { error = friendly_error(str(e)); }
        finally { busy = False; }
    }

    async def removeBlock(id: str) {
        try { data = await delete_reserved_block(id); }
        except Exception as e { error = friendly_error(str(e)); }
    }

    async def loadRoutine {
        try { data = await seed_routine(); }
        except Exception as e { error = friendly_error(str(e)); }
    }

    async can with entry { await loadData(); }

    <ScrollView style={styles.screen} contentContainerStyle={styles.body} keyboardShouldPersistTaps="handled">
        <View style={styles.header}>
            <Text style={styles.eyebrow}>STUDYFLOW</Text>
            <Text style={styles.title}>Today</Text>
            <Text style={styles.subtitle}>{data.today if data is not None else "Loading your plan…"}</Text>
        </View>

        {if error {
            <View style={styles.error}><Text style={styles.errorText}>{error}</Text></View>
        }}
        {if data is not None and data.message {
            <View style={styles.notice}><Text style={styles.noticeText}>{data.message}</Text></View>
        }}

        {if loading {
            <ActivityIndicator size="large" color="#4f46e5"/>
        } elif data is not None {
            <View style={[
                styles.status,
                styles.statusWarn if status_of(data)[0] == "warn" else (styles.statusHint if status_of(data)[0] == "hint" else styles.statusOk)
            ]}>
                <View style={styles.statusCopy}>
                    <Text style={styles.statusTitle}>{status_of(data)[1]}</Text>
                    <Text style={styles.muted}>{minute_text(data.remaining_minutes) + " of work left · " + str(data.active_tasks) + " open tasks"}</Text>
                </View>
                <Pressable style={styles.smallButton} disabled={busy} onPress={runReplan}>
                    <Text style={styles.smallButtonText}>{"…" if busy else "↻ Reschedule"}</Text>
                </Pressable>
            </View>

            <View style={styles.panel}>
                <View style={styles.panelHeading}>
                    <Text style={styles.panelTitle}>To-do</Text>
                    <Text style={styles.badge}>{str(len([x for x in data.today_sessions if x.completed])) + " of " + str(len(data.today_sessions)) + " done"}</Text>
                </View>
                <Text style={styles.helper}>Tap the circle to check a block off (tap again to undo). Your plan only shifts when you press Reschedule.</Text>
                {if len(data.today_sessions) == 0 {
                    <View style={styles.empty}>
                        <Text style={styles.emptyTitle}>Nothing planned for today</Text>
                        <Text style={styles.emptyText}>Add a task below or load the demo to see the planner work.</Text>
                        <Pressable style={styles.secondary} onPress={loadDemo}>
                            <Text style={styles.secondaryText}>Load demo tasks</Text>
                        </Pressable>
                    </View>
                } else {
                    for session in data.today_sessions {
                        <MobileSession key={session.id} session={session} onToggle={toggleSession}/>
                    }
                }}
            </View>

            <View style={styles.panel}>
                <View style={styles.panelHeading}>
                    <Text style={styles.panelTitle}>Tasks</Text>
                    <Text style={styles.badge}>{str(data.active_tasks)} open</Text>
                </View>
                <Text style={styles.helper}>Press Done when a whole task is finished; its remaining blocks are removed.</Text>
                {for task in data.tasks {
                    if not task.completed {
                        <MobileTask key={task.id} task={task} onDone={toggle}/>
                    }
                }}
            </View>

            <View style={styles.panel}>
                <Text style={styles.panelTitle}>Quick add</Text>
                <View style={styles.form}>
                    <TextInput style={styles.input} value={title} placeholder="What do you need to do?" placeholderTextColor="#81908c" onChangeText={lambda (value: str) { title = value; }}/>
                    <View style={styles.row}>
                        <TextInput style={[styles.input, styles.half]} value={course} placeholder="Course" placeholderTextColor="#81908c" onChangeText={lambda (value: str) { course = value; }}/>
                        <TextInput style={[styles.input, styles.half]} value={place} placeholder="Location (optional)" placeholderTextColor="#81908c" onChangeText={lambda (value: str) { place = value; }}/>
                    </View>
                    <View style={styles.row}>
                        <TextInput style={[styles.input, styles.half]} value={dueDate} placeholder="Due YYYY-MM-DD" placeholderTextColor="#81908c" autoCapitalize="none" onChangeText={lambda (value: str) { dueDate = value; }}/>
                        <TextInput style={[styles.input, styles.half]} value={dueTime} placeholder="Time HH:MM (optional)" placeholderTextColor="#81908c" autoCapitalize="none" onChangeText={lambda (value: str) { dueTime = value; }}/>
                    </View>
                    <TextInput style={styles.input} value={estimate} placeholder="Estimated minutes" placeholderTextColor="#81908c" keyboardType="number-pad" onChangeText={lambda (value: str) { estimate = value; }}/>
                    <Pressable style={styles.primary} disabled={busy} onPress={quickAdd}>
                        <Text style={styles.primaryText}>{"Adding…" if busy else "+ Add & schedule"}</Text>
                    </Pressable>
                </View>
            </View>

            <View style={styles.panel}>
                <View style={styles.panelHeading}>
                    <Text style={styles.panelTitle}>Reserved time</Text>
                    <Text style={styles.badge}>{str(len(data.reserved_blocks))} routines</Text>
                </View>
                <Text style={styles.helper}>Planned work is never placed over sleep, meals, classes, exercise, or commuting.</Text>
                {if len(data.reserved_blocks) == 0 {
                    <Pressable style={styles.secondary} onPress={loadRoutine}>
                        <Text style={styles.secondaryText}>Use example routine</Text>
                    </Pressable>
                } else {
                    for block in data.reserved_blocks {
                        <MobileBlock key={block.id} block={block} onDelete={removeBlock}/>
                    }
                }}
                <View style={styles.form}>
                    <TextInput style={styles.input} value={blockLabel} placeholder="Name, e.g. Sleep" placeholderTextColor="#a1a1aa" onChangeText={lambda (value: str) { blockLabel = value; }}/>
                    <TextInput style={styles.input} value={blockPlace} placeholder="Location (optional)" placeholderTextColor="#a1a1aa" onChangeText={lambda (value: str) { blockPlace = value; }}/>
                    <View style={styles.row}>
                        <TextInput style={[styles.input, styles.half]} value={blockStart} placeholder="23:00" placeholderTextColor="#a1a1aa" autoCapitalize="none" onChangeText={lambda (value: str) { blockStart = value; }}/>
                        <TextInput style={[styles.input, styles.half]} value={blockEnd} placeholder="08:00" placeholderTextColor="#a1a1aa" autoCapitalize="none" onChangeText={lambda (value: str) { blockEnd = value; }}/>
                    </View>
                    <Pressable style={styles.primary} disabled={busy} onPress={addBlock}>
                        <Text style={styles.primaryText}>Add reserved time (every day)</Text>
                    </Pressable>
                </View>
            </View>
        }}
    </ScrollView>
}
