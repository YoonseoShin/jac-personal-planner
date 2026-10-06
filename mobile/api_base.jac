# Browser build of the mobile app: API calls already go to the page's own
# server, so there is nothing to configure.

# The API URL this app ended up using, for showing in error messages.
glob chosen: dict[str, str] = {"url": ""};

def:pub configure_api_base {
    return;
}

def:pub api_base_url -> str {
    return chosen["url"];
}
