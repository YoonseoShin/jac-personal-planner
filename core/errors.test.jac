test "validation messages from the server are shown as-is" {
    raw = "add_task: Function add_task failed: {\"ok\": false, \"type\": \"error\", \"data\": null, \"error\": {\"code\": \"EXECUTION_ERROR\", \"message\": \"That due time has already passed today.\"}}";
    assert friendly_error(raw) == "That due time has already passed today.";
}

test "python internals are hidden behind a generic message" {
    raw = "Function add_task failed: {\"error\": {\"code\": \"EXECUTION_ERROR\", \"message\": \"'<' not supported between instances of 'NoneType' and 'int'\"}}";
    assert friendly_error(raw) == MSG_GENERIC;
    missing = "Function add_task failed: {\"error\": {\"code\": \"EXECUTION_ERROR\", \"message\": \"add_task() missing 4 required positional arguments: 'course'.\"}}";
    assert friendly_error(missing) == MSG_GENERIC;
}

test "connection and server version problems get specific advice" {
    assert friendly_error("get_dashboard: TypeError: Failed to fetch") == MSG_UNREACHABLE;
    assert friendly_error("Function get_calendar failed: {\"detail\": \"Method Not Allowed\"}") == MSG_OUTDATED;
    assert friendly_error("Request timed out") == MSG_TIMEOUT;
    assert friendly_error("bridge to 'planner.add_task' failed: app 'planner' is not registered; set JAC_APP_PLANNER_URL") == MSG_UNREACHABLE;
    assert friendly_error("Function x failed: {\"error\": {\"code\": \"RATE_LIMITED\", \"message\": \"slow down\"}}") == MSG_BUSY;
}

test "plain validation errors pass through" {
    assert friendly_error("Task title is required.") == "Task title is required.";
    assert friendly_error("") == MSG_GENERIC;
}
