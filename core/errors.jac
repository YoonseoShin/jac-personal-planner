# Turns raw bridge/server failures into short messages people can act on.
# Shared by the web, mobile, and CLI apps, so it sticks to plain string
# operations that behave the same in Python and in the browser.

glob MSG_UNREACHABLE: str = "Can't reach the StudyFlow server. Make sure `jac run` is running, then try again.",
     MSG_TIMEOUT: str = "The server took too long to respond. Please try again.",
     MSG_OUTDATED: str = "The server is running an older version of StudyFlow. Restart `jac run` and try again.",
     MSG_BUSY: str = "Too many requests at once. Wait a moment and try again.",
     MSG_GENERIC: str = "Something went wrong. Check what you entered and try again.";

def:priv field_value(text: str, key: str) -> str {
    for pattern in ["\"" + key + "\": \"", "\"" + key + "\":\""] {
        if pattern in text {
            return text.split(pattern)[1].split("\"")[0];
        }
    }
    return "";
}

# Messages we raise on purpose are full sentences ("Due date cannot be in the
# past."). Python internals ("'<' not supported ...", "add_task() missing ...")
# are not, and must never reach the user.
def:priv is_user_message(message: str) -> bool {
    if len(message) < 4 { return False; }
    first = message[0:1];
    if first == first.lower() { return False; }
    if message[len(message) - 1:] != "." { return False; }
    for marker in ["()", "NoneType", "instances of", "Traceback", "positional argument", "object has no attribute"] {
        if marker in message { return False; }
    }
    return True;
}

def friendly_error(raw: str) -> str {
    text = str(raw);
    low = text.lower();
    message = field_value(text, "message");
    if message and is_user_message(message) { return message; }
    code = field_value(text, "code");
    detail = field_value(text, "detail").lower();
    for marker in ["failed to fetch", "network request failed", "could not connect", "fetch failed", "connect call failed", "errno 61", "errno 111", "networkerror", "load failed", "connection refused", "econnrefused", "cannot connect", "unavailable", "is not registered"] {
        if marker in low { return MSG_UNREACHABLE; }
    }
    for marker in ["timed out", "timeout", "aborterror"] {
        if marker in low { return MSG_TIMEOUT; }
    }
    if code == "RATE_LIMITED" or "429" in low { return MSG_BUSY; }
    if detail == "method not allowed" or detail == "not found" or code == "NOT_FOUND" {
        return MSG_OUTDATED;
    }
    if not message and is_user_message(text) and "failed:" not in text {
        return text;
    }
    return MSG_GENERIC;
}
