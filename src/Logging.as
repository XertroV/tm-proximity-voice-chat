void dev_trace(const string &in msg) {
#if DEV
    trace("[DEVTRACE] " + msg);
#endif
}

void dev_warn(const string &in msg) {
#if DEV
    warn("[DEV] " + msg);
#endif
}

dictionary notifiedWarnings;
void NotifyWarnOnce(const string &in msg) {
    if (!notifiedWarnings.Exists(msg)) {
        notifiedWarnings[msg] = true;
        NotifyWarning(msg);
    }
}

void DevNotifyWarning(const string &in msg) {
#if DEV
    NotifyWarning(msg);
#endif
}
