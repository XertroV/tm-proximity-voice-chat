class ServerConn {
    // protected MsgHandler@[] msgHandlers;
    dictionary msgHandlers;
    BetterSocket@ socket;
    uint runNonce;
    bool IsReady = false;

    ServerConn() {
        Init();
    }

    void Init() {
        @socket = BetterSocket("127.0.0.1", 46323);
        AddMessageHandlers();
        startnew(CoroutineFunc(ReconnectSocket));
        startnew(CoroutineFunc(WatchForDeadSocket));
    }
    void NewRunNonce() {
        runNonce = Math::Rand(0, 1000000);
    }
    void WatchForDeadSocket() {
        uint lastDead = Time::Now;
        bool wasDead = false;
        uint connStart = Time::Now;
        while (!_isShutdown && socket.IsConnecting && Time::Now - connStart < 5000) yield();
        sleep(21230);
        while (!_isShutdown) {
            if (socket.IsConnecting) {
                connStart = Time::Now;
                while (!_isShutdown && socket.IsConnecting && Time::Now - connStart < 5000) yield();
            }
            if (IsShutdownClosedOrDC) {
                if (_isShutdown) return;
                if (!wasDead) {
                    wasDead = true;
                    lastDead = Time::Now;
                } else if (Time::Now - lastDead > 21230) {
                    lastDead = Time::Now;
                    ReconnectSocket();
                    wasDead = false;
                    sleep(21230);
                }
            } else {
                wasDead = false;
            }
            yield();
        }
    }

    void OnDisabled() {
        Shutdown();
    }

    bool _isShutdown = false;
    void Shutdown() {
        _isShutdown = true;
        G_ConnectedToMumble = false;
        if (socket !is null) socket.Shutdown();
        @socket = null;
        IsReady = false;
    }

    bool get_IsShutdownClosedOrDC() {
        return _isShutdown || socket.IsClosed || socket.ServerDisconnected;
    }


    protected void ReconnectSocket() {
        NewRunNonce();
        auto nonce = runNonce;
        IsReady = false;
        trace("ReconnectSocket");
        if (_isShutdown) return;
        socket.ReconnectToServer();
        startnew(CoroutineFuncUserdataUint64(BeginLoop), nonce);
    }

    bool IsBadNonce(uint32 nonce) {
        if (nonce != runNonce) {
            return true;
        }
        return false;
    }

    protected void BeginLoop(uint64 nonce) {
        while (!_isShutdown && socket.IsConnecting && !IsBadNonce(nonce)) yield();
        if (IsBadNonce(nonce)) return;
        if (IsShutdownClosedOrDC) {
            if (_isShutdown) return;
            // sessionToken = "";
            warn("Failed to connect to server.");
            sleep(15000);
            if (IsBadNonce(nonce)) return;
            ReconnectSocket();
            return;
        }
        print("Connected to server...");
        uint ctxStartTime = Time::Now;
        print("... server connection ready");
        IsReady = true;
        QueueMsg(GetPlayerDetailsMsg());
        QueueMsg(GetServerDetailsMsg());
        startnew(CoroutineFuncUserdataUint64(ReadLoop), nonce);
        startnew(CoroutineFuncUserdataUint64(SendLoop), nonce);
        startnew(CoroutineFuncUserdataUint64(SendPingLoop), nonce);
        startnew(CoroutineFuncUserdataUint64(ReconnectWhenDisconnected), nonce);
    }

    void ReconnectWhenDisconnected(uint64 nonce) {
        while (!IsBadNonce(nonce)) {
            if (IsShutdownClosedOrDC) {
                trace("disconnect detected.");
                ReconnectSocket();
                return;
            }
            sleep(1000);
        }
    }

    protected void ReadLoop(uint64 nonce) {
        RawMessage@ msg;
        while (!IsBadNonce(nonce) && (@msg = socket.ReadMsg()) !is null) {
            HandleRawMsg(msg);
        }
        // we disconnected
    }

    protected OutgoingMsg@[] queuedMsgs;

    void QueueMsg(OutgoingMsg@ msg) {
        queuedMsgs.InsertLast(msg);
    }
    protected void QueueMsg(const string &in type, Json::Value@ payload) {
        queuedMsgs.InsertLast(OutgoingMsg(type, payload));
        if (queuedMsgs.Length > 10) {
            trace('msg queue: ' + queuedMsgs.Length);
        }
    }

    protected void SendLoop(uint64 nonce) {
        OutgoingMsg@ next;
        uint loopStarted = Time::Now;
        while (!IsReady && Time::Now - loopStarted < 10000) yield();
        while (!IsBadNonce(nonce)) {
            if (IsShutdownClosedOrDC) break;
            int nbOutgoing = Math::Min(queuedMsgs.Length, 10);
            for (int i = 0; i < nbOutgoing; i++) {
                @next = queuedMsgs[i];
                SendMsgNow(next);
            }
            queuedMsgs.RemoveRange(0, nbOutgoing);
            // if (nbOutgoing > 0) dev_trace("sent " + nbOutgoing + " messages");
            yield();
        }
    }

    string lastStatsJson;
    protected void SendMsgNow(OutgoingMsg@ msg) {
        if (socket is null) return;
        msg.WriteToSocket(socket);
        LogSentType(msg);
    }

    MsgHandler@ GetHandler(const string &in type) {
        if (msgHandlers.Exists(type)) {
            return cast<MsgHandler>(msgHandlers[type]);
        }
        return null;
    }

    void HandleRawMsg(RawMessage@ msg) {
        if (!msgHandlers.Exists(msg.msgType) || GetHandler(msg.msgType) is null) {
            warn("Unhandled message type: " + msg.msgType + ". Handler exists: " + msgHandlers.Exists(msg.msgType));
            return;
        }
        LogRecvType(msg);
        try {
            GetHandler(msg.msgType)(msg.msgJson);
        } catch {
            warn("Failed to handle message type: " + msg.msgType + ". " + getExceptionInfo());
            warn("msg itself: " + Json::Write(msg.msgJson));
        }
    }

    dictionary recvCount;
    dictionary sendCount;

    protected void LogSentType(OutgoingMsg@ msg) {
        if (sendCount.Exists(msg.msgType)) {
            sendCount[msg.msgType] = int64(sendCount[msg.msgType]) + 1;
        } else {
            sendCount[msg.msgType] = int64(1);
        }
        if (msg.msgType != "Ping") {
            dev_trace("Sent message type: " + tostring(msg.msgType));
        }
    }

    protected void LogRecvType(RawMessage@ msg) {
        if (recvCount.Exists(msg.msgType)) {
            recvCount[msg.msgType] = int64(recvCount[msg.msgType]) + 1;
        } else {
            recvCount[msg.msgType] = int64(1);
        }
    }

    uint lastPingTime, pingTimeoutCount;
    protected void SendPingLoop(uint64 nonce) {
        pingTimeoutCount = 0;
        while (!IsBadNonce(nonce)) {
            sleep(6789);
            if (IsShutdownClosedOrDC) {
                return;
            }
            if (IsBadNonce(nonce)) return;
            QueueMsg(PingMsg());
            if (Time::Now - lastPingTime > 45000 && IsReady) {
                if (IsBadNonce(nonce)) return;
                pingTimeoutCount++;
                if (pingTimeoutCount > 3) {
                    warn("Ping timeout.");
                    lastPingTime = Time::Now;
                    socket.Shutdown();
                    return;
                }
            } else {
                pingTimeoutCount = 0;
            }
        }
    }


    void AddMessageHandlers() {
        @msgHandlers["ConnectedStatus"] = MsgHandler(OnMsg_ConnectedStatus);
        @msgHandlers["Ping"] = MsgHandler(OnMsg_Ping);
    }
}

bool G_ConnectedToMumble = false;

void OnMsg_ConnectedStatus(Json::Value@ msg) {
    G_ConnectedToMumble = msg;
    dev_trace("Connected to server: " + G_ConnectedToMumble);
}

void OnMsg_Ping(Json::Value@ msg) {
    dev_trace("Ping response: " + Json::Write(msg));
}
