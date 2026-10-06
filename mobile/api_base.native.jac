import from 'react-native' { NativeModules }
import from 'expo-constants' { * as ExpoConstants }

# The API URL this app ended up using, for showing in error messages.
glob chosen: dict[str, str] = {"url": ""};

# Host (no port) of the computer this app was loaded from, or "".
def:priv dev_host -> str {
    sources: list[str] = [];
    source_code = NativeModules.SourceCode;
    if source_code {
        if source_code.scriptURL { sources.append(str(source_code.scriptURL)); }
        if source_code.getConstants {
            constants = source_code.getConstants();
            if constants and constants.scriptURL { sources.append(str(constants.scriptURL)); }
        }
    }
    consts = ExpoConstants.default or ExpoConstants;
    cfg = consts.expoConfig;
    if cfg and cfg.hostUri { sources.append(str(cfg.hostUri)); }
    go_cfg = consts.expoGoConfig;
    if go_cfg and go_cfg.debuggerHost { sources.append(str(go_cfg.debuggerHost)); }
    if consts.linkingUri { sources.append(str(consts.linkingUri)); }
    for value in sources {
        rest = value.split("://")[1] if "://" in value else value;
        host = rest.split("/")[0].split(":")[0];
        if host and host != "localhost" and host != "127.0.0.1" { return host; }
    }
    return "";
}

# Points the native app at the server that `jac run` starts (the web app +
# planner service, API port 8001), so the phone, the web app and the CLI all
# read and write the same data. Expo Go loads the app from that computer, so
# its host is the one to use. The URL `jac run --dev mobile` injects is not
# used: that server is a separate process that stops whenever the Android
# build step fails, which leaves the app pointing at nothing.
def:pub configure_api_base {
    host = dev_host();
    if host {
        url = "http://" + host + ":8001";
        globalThis.__JAC_API_BASE_URL__ = url;
        chosen["url"] = url;
    } elif globalThis.__JAC_API_BASE_URL__ {
        chosen["url"] = "injected by jac";
    }
    console.log("[studyflow] API base: " + (chosen["url"] or "not set"));
}

def:pub api_base_url -> str {
    return chosen["url"];
}
