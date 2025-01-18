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
