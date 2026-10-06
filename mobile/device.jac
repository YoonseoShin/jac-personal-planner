# Browser build of the mobile app: use page visibility instead of AppState.

def:pub is_foreground -> bool {
    doc: any = globalThis.document;  # jac:ignore[W1037,W6001]
    return doc.visibilityState != "hidden";
}

def:pub watch_foreground(onActive: Callable[[], None]) -> Callable[[], None] {
    def handler {
        if is_foreground() { onActive(); }
    }
    doc: any = globalThis.document;  # jac:ignore[W1037,W6001]
    doc.addEventListener("visibilitychange", handler);
    return lambda { doc.removeEventListener("visibilitychange", handler); };
}

# The browser has its own reload, so there is no pull-to-refresh control.
def:pub PullToRefresh(refreshing: bool, onRefresh: Callable[[], None]) -> JsxElement | None {
    return None;
}

# Browser preview: the page's own alert box.
def:pub show_alert(title: str, message: str) {
    win: any = globalThis;  # jac:ignore[W1037]
    win.alert(title + chr(10) + chr(10) + message);
}
