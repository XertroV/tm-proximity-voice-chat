void dev_trace(const string &in msg) {
#if DEV
    trace(msg);
#endif
}

void dev_warn(const string &in msg) {
#if DEV
    warn(msg);
#endif
}
