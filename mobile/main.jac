import from "@jac/mobui" {
    ActivityIndicator,
    Keyboard,
    KeyboardAvoidingView,
    Modal,
    Platform,
    Pressable,
    ScrollView,
    StyleSheet,
    Text,
    TextInput,
    View
}
import from core.errors { MSG_UNREACHABLE, friendly_error }
import from mobile.api_base { api_base_url, configure_api_base }
import from "react" { useEffect }
import from mobile.device { PullToRefresh, is_foreground, show_alert, watch_foreground }

# How often an open app re-reads the plan, so changes made on the web or in
# the CLI show up without reopening the app.
glob REFRESH_MS: int = 10000;
import from core.planner_service {
    CalendarData,
    DashboardData,
    ReservedBlockView,
    SessionView,
    TaskView,
    add_reserved_block,
    add_task,
    complete_session,
    delete_reserved_block,
    get_calendar,
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
    half: {flex: 1, minWidth: 0, flexBasis: 0},
    primary: {backgroundColor: "#4f46e5", borderRadius: 10, padding: 13, alignItems: "center"},
    primaryText: {color: "#ffffff", fontWeight: "800"},
    secondary: {backgroundColor: "#f4f4f5", borderRadius: 10, padding: 11, alignItems: "center", borderWidth: 1, borderColor: "#e4e4e7"},
    secondaryText: {color: "#27272a", fontWeight: "800"},
    empty: {paddingVertical: 28, alignItems: "center", gap: 8},
    emptyTitle: {fontSize: 17, color: "#18181b", fontWeight: "800"},
    emptyText: {fontSize: 13, lineHeight: 19, color: "#71717a", textAlign: "center"},
    notice: {backgroundColor: "#eff6ff", borderRadius: 11, padding: 13},
    noticeText: {color: "#1d4ed8", fontSize: 12},
    block: {flexDirection: "row", alignItems: "center", gap: 10, paddingVertical: 10, borderTopWidth: 1, borderTopColor: "#f1f1f2"},
    blockDot: {width: 8, height: 8, borderRadius: 4, backgroundColor: "#818cf8"},
    blockCopy: {flex: 1, gap: 2},
    blockTitle: {fontSize: 13, color: "#18181b", fontWeight: "700"},
    removeText: {fontSize: 12, color: "#dc2626", fontWeight: "700"},
    helper: {fontSize: 12, lineHeight: 18, color: "#71717a"},
    tapArea: {gap: 18},
    headerRow: {flexDirection: "row", alignItems: "center", justifyContent: "space-between"},
    addButton: {width: 44, height: 44, borderRadius: 22, backgroundColor: "#4f46e5", alignItems: "center", justifyContent: "center"},
    addButtonText: {color: "#ffffff", fontSize: 26, fontWeight: "700", lineHeight: 28},
    backdrop: {flex: 1, backgroundColor: "rgba(17,24,39,0.45)", justifyContent: "flex-end"},
    sheet: {backgroundColor: "#ffffff", borderTopLeftRadius: 20, borderTopRightRadius: 20, padding: 20, paddingBottom: 34, gap: 12, maxHeight: "92%"},
    sheetHead: {flexDirection: "row", justifyContent: "space-between", alignItems: "center"},
    closeText: {fontSize: 22, color: "#9ca3af"},
    fieldLabel: {fontSize: 12, color: "#374151", fontWeight: "700"},
    calHead: {flexDirection: "row", alignItems: "center", justifyContent: "space-between"},
    calNav: {fontSize: 22, color: "#4f46e5", paddingHorizontal: 12},
    calTitle: {fontSize: 14, fontWeight: "800", color: "#111827"},
    calWeek: {flexDirection: "row"},
    calWeekday: {flex: 1, textAlign: "center", fontSize: 11, color: "#9ca3af", fontWeight: "700"},
    calDay: {width: "14.28%", height: 38, alignItems: "center", justifyContent: "center", borderRadius: 19},
    calDaySelected: {backgroundColor: "#4f46e5"},
    calDayToday: {borderWidth: 1.5, borderColor: "#4f46e5"},
    calDayText: {fontSize: 14, color: "#111827", fontWeight: "600"},
    calDayTextMuted: {color: "#d1d5db"},
    calDayTextSelected: {color: "#ffffff"},
    calGrid: {flexDirection: "row", flexWrap: "wrap"},
    timeFieldOpen: {borderColor: "#4f46e5"},
    timeValue: {fontSize: 15, color: "#111827", fontWeight: "600"},
    timePlaceholder: {fontSize: 15, color: "#9ca3af"},
    timeChip: {minWidth: 46, paddingVertical: 8, paddingHorizontal: 10, borderRadius: 8, borderWidth: 1, borderColor: "#e5e7eb", alignItems: "center", backgroundColor: "#ffffff"},
    timeChipOn: {backgroundColor: "#4f46e5", borderColor: "#4f46e5"},
    timeChipText: {fontSize: 14, color: "#111827", fontWeight: "600"},
    timeChipTextOn: {color: "#ffffff"},
    dropField: {flex: 1, minWidth: 0, borderWidth: 1, borderColor: "#d4d4d8", borderRadius: 9, paddingHorizontal: 12, paddingVertical: 11, flexDirection: "row", justifyContent: "space-between", alignItems: "center"},
    dropList: {maxHeight: 200, borderWidth: 1, borderColor: "#e5e7eb", borderRadius: 9},
    dropOption: {paddingVertical: 11, paddingHorizontal: 14, borderBottomWidth: 1, borderBottomColor: "#f3f4f6"},
    dropOptionOn: {backgroundColor: "#4f46e5"},
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

# "HH:MM" (24h) -> "9:30 AM"; "" stays "".
def time_label(value: str) -> str {
    if not value { return ""; }
    parts = value.split(":");
    hour = int(parts[0]);
    shown = hour % 12;
    if shown == 0 { shown = 12; }
    return str(shown) + ":" + parts[1] + (" AM" if hour < 12 else " PM");
}

# Builds "HH:MM" from a 12-hour clock, minutes, and AM/PM.
def to_clock(hour12: int, minute: int, pm: bool) -> str {
    hour = hour12 % 12 + (12 if pm else 0);
    return ("0" if hour < 10 else "") + str(hour) + ":" + ("0" if minute < 10 else "") + str(minute);
}

glob HOURS: list[str] = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12"],
     MINUTES: list[str] = ["00", "05", "10", "15", "20", "25", "30", "35", "40", "45", "50", "55"],
     HALVES: list[str] = ["AM", "PM"];

# One dropdown field: shows the current choice; tapping it opens or closes its
# option list (drawn by TimePicker under the row of fields).
def DropdownField(text: str, open: bool, onToggle: Callable[[], None]) -> JsxElement {
    return <Pressable style={[styles.dropField, styles.timeFieldOpen if open else {}]} onPress={lambda { Keyboard.dismiss(); onToggle(); }}>
        <Text style={styles.timeValue if text != "--" else styles.timePlaceholder}>{text}</Text>
        <Text style={styles.muted}>{"▴" if open else "▾"}</Text>
    </Pressable>;
}

# Time picker made of three dropdowns: hour, minute (5-minute steps, like the
# web app) and AM/PM. `openKey` says which list is open ("<id>-h", "-m", "-ap").
def TimePicker(
    id: str,
    value: str,
    optional: bool,
    openKey: str,
    onOpen: Callable[[str], None],
    onChange: Callable[[str], None]
) -> JsxElement {
    hour = int(value.split(":")[0]) if value else -1;
    minute = int(value.split(":")[1]) if value else 0;
    pm = hour >= 12;
    hour12 = hour % 12 if hour >= 0 else 0;
    if hour >= 0 and hour12 == 0 { hour12 = 12; }
    minute_text = ("0" if minute < 10 else "") + str(minute);
    def pick(kind: str, choice: str) {
        h = hour12 if hour12 > 0 else 9;
        m = minute;
        half_pm = pm if hour >= 0 else False;
        if kind == "h" { h = int(choice); }
        if kind == "m" { m = int(choice); }
        if kind == "ap" { half_pm = choice == "PM"; }
        onChange(to_clock(h, m, half_pm));
        onOpen("");
    }
    def toggle(kind: str) {
        onOpen("" if openKey == id + "-" + kind else id + "-" + kind);
    }
    open_kind = openKey[len(id) + 1:] if openKey.startswith(id + "-") else "";
    choices = HOURS if open_kind == "h" else (MINUTES if open_kind == "m" else HALVES);
    current = str(hour12) if open_kind == "h" else (minute_text if open_kind == "m" else ("PM" if pm else "AM"));
    return <View style={{"gap": 6}}>
        <View style={styles.row}>
            <DropdownField text={str(hour12) if value else "--"} open={open_kind == "h"} onToggle={lambda { toggle("h"); }}/>
            <DropdownField text={minute_text if value else "--"} open={open_kind == "m"} onToggle={lambda { toggle("m"); }}/>
            <DropdownField text={("PM" if pm else "AM") if value else "--"} open={open_kind == "ap"} onToggle={lambda { toggle("ap"); }}/>
        </View>
        {if open_kind {
            <ScrollView style={styles.dropList} nestedScrollEnabled={True} keyboardShouldPersistTaps="handled">
                {[<Pressable key={c} style={[styles.dropOption, styles.dropOptionOn if value and c == current else {}]} onPress={lambda { pick(open_kind, c); }}>
                    <Text style={[styles.timeChipText, styles.timeChipTextOn if value and c == current else {}]}>{c}</Text>
                </Pressable> for c in choices]}
            </ScrollView>
        }}
        {if optional and value {
            <Pressable style={[styles.timeChip, {"alignSelf": "flex-start"}]} onPress={lambda { onChange(""); onOpen(""); }}>
                <Text style={styles.timeChipText}>No time</Text>
            </Pressable>
        }}
    </View>;
}

# Month calendar for picking a due date. Days come from the server's month
# view, so the phone needs no date math; past days cannot be picked.
def MonthPicker(
    cal: CalendarData | None,
    selected: str,
    onPick: Callable[[str], None],
    onShift: Callable[[int], None]
) -> JsxElement {
    if cal is None {
        return <ActivityIndicator color="#4f46e5"/>;
    }
    return <View style={{"gap": 6}}>
        <View style={styles.calHead}>
            <Pressable onPress={lambda { onShift(-1); }}><Text style={styles.calNav}>‹</Text></Pressable>
            <Text style={styles.calTitle}>{cal.title}</Text>
            <Pressable onPress={lambda { onShift(1); }}><Text style={styles.calNav}>›</Text></Pressable>
        </View>
        <View style={styles.calWeek}>
            {[<Text key={w} style={styles.calWeekday}>{w[0]}</Text> for w in ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]]}
        </View>
        <View style={styles.calGrid}>
            {[<Pressable
                key={d.date}
                disabled={d.is_past}
                onPress={lambda { onPick(d.date); }}
                style={[styles.calDay, styles.calDaySelected if d.date == selected else (styles.calDayToday if d.is_today else {})]}
            >
                <Text style={[
                    styles.calDayText,
                    styles.calDayTextSelected if d.date == selected else (styles.calDayTextMuted if d.is_past or not d.in_range else {})
                ]}>{str(d.day_num)}</Text>
            </Pressable> for d in cal.days]}
        </View>
    </View>;
}

def:pub app -> JsxElement {
    has data: DashboardData | None = None,
        loading: bool = True,
        busy: bool = False,
        title: str = "",
        course: str = "",
        dueDate: str = "",
        estimate: str = "60",
        dueTime: str = "",
        place: str = "",
        blockLabel: str = "",
        blockPlace: str = "",
        blockStart: str = "23:00",
        blockEnd: str = "08:00",
        refreshing: bool = False,
        showAdd: bool = False,
        openTime: str = "",
        pickerCal: CalendarData | None = None,
        tick: int = 0,
        pollRef: Ref[int] = Ref(0);

    # Problems are shown in a dialog box. Connection problems also say which
    # server address the app tried.
    def showError(e: Exception) {
        message = friendly_error(str(e));
        if message == MSG_UNREACHABLE {
            show_alert("Can't connect", message + chr(10) + chr(10) + "Server: " + (api_base_url() or "not set"));
        } else {
            show_alert("Couldn't do that", message);
        }
    }

    async def loadData {
        try { loading = True; data = await get_dashboard(); }
        except Exception as e {
            console.warn("[studyflow] load failed: " + str(e));
            showError(e);
        }
        finally { loading = False; }
    }

    async def toggleSession(id: str, done: bool) {
        try {
            if done { data = await uncomplete_session(id); }
            else { data = await complete_session(id); }
        } except Exception as e { showError(e); }
    }

    async def toggle(id: str) {
        try { data = await toggle_task(id); }
        except Exception as e { showError(e); }
    }

    async def loadPicker(anchor: str, shift: int) {
        try { pickerCal = await get_calendar("month", anchor, shift); }
        except Exception as e { showError(e); }
    }

    async def openAdd {
        showAdd = True;
        await loadPicker(dueDate, 0);
    }

    def closeAdd {
        Keyboard.dismiss();
        showAdd = False;
    }

    async def quickAdd {
        if busy { return; }
        try {
            busy = True;
            Keyboard.dismiss();
            data = await add_task(title, course, dueDate, int(estimate), "medium", dueTime, place);
            title = "";
            course = "";
            dueDate = "";
            dueTime = "";
            estimate = "60";
            place = "";
            showAdd = False;
            openTime = "";
        } except Exception as e { showError(e); }
        finally { busy = False; }
    }

    async def runReplan {
        try { busy = True; data = await replan(); }
        except Exception as e { showError(e); }
        finally { busy = False; }
    }

    async def loadDemo {
        try { data = await seed_demo(); }
        except Exception as e { showError(e); }
    }

    async def addBlock {
        if busy { return; }
        try {
            busy = True;
            Keyboard.dismiss();
            data = await add_reserved_block(
                blockLabel, "other", blockStart, blockEnd, "daily", blockPlace
            );
            blockLabel = "";
            blockPlace = "";
        } except Exception as e { showError(e); }
        finally { busy = False; }
    }

    async def removeBlock(id: str) {
        try { data = await delete_reserved_block(id); }
        except Exception as e { showError(e); }
    }

    async def loadRoutine {
        try { data = await seed_routine(); }
        except Exception as e { showError(e); }
    }

    async can with entry {
        configure_api_base();
        await loadData();
    }

    # Quietly re-read the plan (no spinner). Skipped while an action is in
    # flight so it never races a save.
    async def refreshQuietly {
        if busy or loading { return; }
        try { data = await get_dashboard(); }
        except Exception { return; }
    }

    async def pullRefresh {
        refreshing = True;
        try {
            data = await get_dashboard();
        } except Exception as e {
            showError(e);
        } finally {
            refreshing = False;
        }
    }

    # Every 10 seconds, and whenever the app comes back to the foreground,
    # bump `tick`; the effect below does the refresh with current state.
    useEffect(lambda {
        def bump {
            pollRef.current = (pollRef.current or 0) + 1;
            tick = pollRef.current;
        }
        timer = setInterval(lambda { if is_foreground() { bump(); } }, REFRESH_MS);
        stop_watching = watch_foreground(bump);
        return lambda {
            clearInterval(timer);
            stop_watching();
        };
    }, []);

    async can with [tick] entry {
        if tick > 0 { await refreshQuietly(); }
    }

    <KeyboardAvoidingView style={styles.screen} behavior={"padding" if Platform.OS == "ios" else None}>
    <ScrollView
        style={styles.screen}
        contentContainerStyle={styles.body}
        keyboardShouldPersistTaps="handled"
        keyboardDismissMode="on-drag"
        refreshControl={PullToRefresh(refreshing, pullRefresh)}
    >
    <Pressable onPress={lambda { Keyboard.dismiss(); }} accessible={False} style={styles.tapArea}>
        <View style={styles.header}>
            <Text style={styles.eyebrow}>STUDYFLOW</Text>
            <View style={styles.headerRow}>
                <Text style={styles.title}>Today</Text>
                <Pressable style={styles.addButton} onPress={openAdd} accessibilityLabel="Add a task">
                    <Text style={styles.addButtonText}>+</Text>
                </Pressable>
            </View>
            <Text style={styles.subtitle}>{data.today if data is not None else "Loading your plan…"}</Text>
        </View>

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
                    <TextInput style={styles.input} value={blockLabel} returnKeyType="done" onSubmitEditing={lambda { Keyboard.dismiss(); }} placeholder="Name, e.g. Sleep" placeholderTextColor="#a1a1aa" onChangeText={lambda (value: str) { blockLabel = value; }}/>
                    <TextInput style={styles.input} value={blockPlace} returnKeyType="done" onSubmitEditing={lambda { Keyboard.dismiss(); }} placeholder="Location (optional)" placeholderTextColor="#a1a1aa" onChangeText={lambda (value: str) { blockPlace = value; }}/>
                    <Text style={styles.fieldLabel}>Starts</Text>
                    <TimePicker
                        id="start"
                        value={blockStart}
                        optional={False}
                        openKey={openTime}
                        onOpen={lambda (k: str) { openTime = k; }}
                        onChange={lambda (v: str) { blockStart = v; }}
                    />
                    <Text style={styles.fieldLabel}>Ends</Text>
                    <TimePicker
                        id="end"
                        value={blockEnd}
                        optional={False}
                        openKey={openTime}
                        onOpen={lambda (k: str) { openTime = k; }}
                        onChange={lambda (v: str) { blockEnd = v; }}
                    />
                    <Pressable style={styles.primary} disabled={busy} onPress={addBlock}>
                        <Text style={styles.primaryText}>Add reserved time (every day)</Text>
                    </Pressable>
                </View>
            </View>
        }}
    </Pressable>
    </ScrollView>
    <Modal visible={showAdd} transparent={True} animationType="slide" onRequestClose={closeAdd}>
        <KeyboardAvoidingView style={{"flex": 1}} behavior={"padding" if Platform.OS == "ios" else None}>
        <Pressable style={styles.backdrop} onPress={closeAdd}>
            <Pressable style={styles.sheet} onPress={lambda { Keyboard.dismiss(); }}>
                <ScrollView keyboardShouldPersistTaps="handled" contentContainerStyle={{"gap": 12}}>
                    <View style={styles.sheetHead}>
                        <Text style={styles.panelTitle}>New task</Text>
                        <Pressable onPress={closeAdd}><Text style={styles.closeText}>×</Text></Pressable>
                    </View>
                    <TextInput style={styles.input} value={title} returnKeyType="done" onSubmitEditing={lambda { Keyboard.dismiss(); }} placeholder="What do you need to do?" placeholderTextColor="#81908c" onChangeText={lambda (value: str) { title = value; }}/>
                    <View style={styles.row}>
                        <TextInput style={[styles.input, styles.half]} value={course} returnKeyType="done" onSubmitEditing={lambda { Keyboard.dismiss(); }} placeholder="Course" placeholderTextColor="#81908c" onChangeText={lambda (value: str) { course = value; }}/>
                        <TextInput style={[styles.input, styles.half]} value={place} returnKeyType="done" onSubmitEditing={lambda { Keyboard.dismiss(); }} placeholder="Location (optional)" placeholderTextColor="#81908c" onChangeText={lambda (value: str) { place = value; }}/>
                    </View>
                    <Text style={styles.fieldLabel}>{"Due date: " + (dueDate if dueDate else "pick a day")}</Text>
                    <MonthPicker
                        cal={pickerCal}
                        selected={dueDate}
                        onPick={lambda (day: str) { dueDate = day; }}
                        onShift={lambda (n: int) { loadPicker(pickerCal.anchor if pickerCal is not None else "", n); }}
                    />
                    <Text style={styles.fieldLabel}>Due time (optional)</Text>
                    <TimePicker
                        id="due"
                        value={dueTime}
                        optional={True}
                        openKey={openTime}
                        onOpen={lambda (k: str) { openTime = k; }}
                        onChange={lambda (v: str) { dueTime = v; }}
                    />
                    {if not dueTime {
                        <Text style={styles.muted}>No time set: due by the end of the day.</Text>
                    }}
                    <Text style={styles.fieldLabel}>Estimated work (minutes)</Text>
                    <TextInput style={styles.input} value={estimate} returnKeyType="done" onSubmitEditing={lambda { Keyboard.dismiss(); }} placeholder="Minutes" placeholderTextColor="#81908c" keyboardType="number-pad" onChangeText={lambda (value: str) { estimate = value; }}/>
                    <Pressable style={styles.primary} disabled={busy} onPress={quickAdd}>
                        <Text style={styles.primaryText}>{"Adding…" if busy else "+ Add & schedule"}</Text>
                    </Pressable>
                </ScrollView>
            </Pressable>
        </Pressable>
        </KeyboardAvoidingView>
    </Modal>
    </KeyboardAvoidingView>
}
