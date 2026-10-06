import from 'react-native' { Alert, AppState, RefreshControl }

# True while the app is on screen.
def:pub is_foreground -> bool {
    return AppState.currentState == "active";
}

# Calls `onActive` whenever the app comes back to the foreground; returns a
# function that stops listening.
def:pub watch_foreground(onActive: Callable[[], None]) -> Callable[[], None] {
    subscription = AppState.addEventListener("change", lambda (state: str) {
        if state == "active" { onActive(); }
    });
    return lambda { subscription.remove(); };
}

# Pull-to-refresh control for a ScrollView.
def:pub PullToRefresh(refreshing: bool, onRefresh: Callable[[], None]) -> JsxElement | None {
    return <RefreshControl refreshing={refreshing} onRefresh={onRefresh}/>;
}

# Shows a message in the system dialog box with an OK button.
def:pub show_alert(title: str, message: str) {
    Alert.alert(title, message, [{"text": "OK"}]);
}
