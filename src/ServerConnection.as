const uint PING_PERIOD = 6789;

// mumble defaults 1m and 15m. A base of like 32m means 15 scales to 480m
const float MUMBLE_SCALE = 1. / 32.;

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
        startnew(CoroutineFuncUserdataUint64(WatchForServerChange), nonce);
        startnew(CoroutineFuncUserdataUint64(WatchPosAndCam), nonce);
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
        // if (msg.msgType == "Ping") {
        //     lastPingTime = Time::Now;
        // }
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
        LogSentType(msg.msgType);
    }

    protected void LogSentType(const string &in type) {
        if (sendCount.Exists(type)) {
            sendCount[type] = int64(sendCount[type]) + 1;
        } else {
            sendCount[type] = int64(1);
        }
        socket.lastSentTime = Time::Now;
    }

    protected void LogRecvType(RawMessage@ msg) {
        if (recvCount.Exists(msg.msgType)) {
            recvCount[msg.msgType] = int64(recvCount[msg.msgType]) + 1;
        } else {
            recvCount[msg.msgType] = int64(1);
        }
        socket.lastMessageRecvTime = Time::Now;
    }

    string LastSentTimeStr() {
        if (socket is null) return "\\$<\\$999--:--\\$>";
        return Time::Format(Time::Now - socket.lastSentTime, true, true, false);
    }

    string LastRecvTimeStr() {
        if (socket is null) return "\\$<\\$999--:--\\$>";
        return Time::Format(Time::Now - socket.lastMessageRecvTime, true, true, false);
    }

    uint lastPingTime, pingTimeoutCount;
    protected void SendPingLoop(uint64 nonce) {
        pingTimeoutCount = 0;
        while (!IsBadNonce(nonce)) {
            sleep(PING_PERIOD);
            if (IsShutdownClosedOrDC) {
                return;
            }
            if (IsBadNonce(nonce)) return;
            QueueMsg(PingMsg());
            yield(2);
            if (Time::Now - lastPingTime > PING_PERIOD + 1000 && IsReady) {
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

    // server login on map uid
    string lastRoomId, lastTeam;
    void WatchForServerChange(uint64 nonce) {
        string serverLogin = GetServerLogin();
        string team = GetServerTeamIfTeams();
        while (!IsBadNonce(nonce)) {
            if (IsShutdownClosedOrDC) {
                return;
            }
            sleep(100);
            if ((serverLogin = GetServerLogin()) != lastRoomId || (team = GetServerTeamIfTeams()) != lastTeam) {
                lastRoomId = serverLogin;
                lastTeam = team;
                QueueMsg(GetServerDetailsMsg());
            }
        }
    }

    Json::Value posAndCamJ = GenEmptyPosAndCamJ();

    void SendFixedPosAndCam_PointingAway(float x, float y, float z) {
        auto s = socket.s;
        VarInt::EncodeUint(s, 73); // 1 + (4 * 3 * 3 * 2) = 73
        s.Write(uint8(1)); // 1
        bool success = WriteVec3(s, x, y, z*-1.0)
            && WriteVec3(s, -ROOT2ON2, 0, ROOT2ON2)
            && WriteVec3(s, 0, 1, 0)
            && WriteVec3(s, x, y, z*-1.0)
            && WriteVec3(s, -ROOT2ON2, 0, ROOT2ON2)
            && WriteVec3(s, 0, 1, 0);
        LogSentType("Positions");
    }

    void SendZeroPlayerPosAndCam() {
        auto s = socket.s;
        VarInt::EncodeUint(s, 73); // 1 + (4 * 3 * 3 * 2) = 73
        s.Write(uint8(1)); // 1
        // pos
        s.Write(float(0.01)); // 5
        s.Write(float(0.01));
        s.Write(float(0.01));
        // dir
        s.Write(float(0));
        s.Write(float(0));
        s.Write(float(-1));
        // up
        s.Write(float(0));
        s.Write(float(1));
        s.Write(float(0));
        // cpos
        s.Write(float(0.01));
        s.Write(float(0.01));
        s.Write(float(0.01));
        // cdir
        s.Write(float(0));
        s.Write(float(0));
        s.Write(float(-1));
        // cup
        s.Write(float(0));
        s.Write(float(1));
        s.Write(float(0));
        LogSentType("Positions");
    }

    // vec3 pos, dir, up, camPos, camDir, camUp;
    void UpdatePlayerPosAndCam(CSmScriptPlayer@ script) {
        auto s = socket.s;
        VarInt::EncodeUint(s, 73); // 1 + (4 * 3 * 3 * 2) = 73
        s.Write(uint8(1)); // 1
        // mumble proximity defaults are 1m and 15m so divide pos by 32
        // the server uses left handed coords, but tm uses right handed coords, so flip the z axis
        s.Write(float(script.Position.x * MUMBLE_SCALE)); // 5
        s.Write(float(script.Position.y * MUMBLE_SCALE)); // 9
        s.Write(float(script.Position.z * MUMBLE_SCALE * -1.));  // 13
        s.Write(float(script.AimDirection.x));  // 17
        s.Write(float(script.AimDirection.y));  // 21
        s.Write(float(script.AimDirection.z * -1.));
        s.Write(float(script.UpDirection.x));
        s.Write(float(script.UpDirection.y));
        s.Write(float(script.UpDirection.z * -1.));
        auto cam = Camera::GetCurrent();
        auto mat = cam.NextLocation;
        s.Write(float(mat.tx * MUMBLE_SCALE));
        s.Write(float(mat.ty * MUMBLE_SCALE));
        s.Write(float(mat.tz * MUMBLE_SCALE * -1.));
        s.Write(float(mat.xz));
        s.Write(float(mat.yz));
        s.Write(float(mat.zz * -1.));
        s.Write(float(mat.xy));
        s.Write(float(mat.yy));
        bool success = s.Write(float(mat.zy * -1.));
        if (!success) {
            warn("Failed to write to socket");
        }
        LogSentType("Positions");
        // camDir.x = mat.xz;
        // camDir.y = mat.yz;
        // camDir.z = mat.zz;
        // camUp.x = mat.xy;
        // camUp.y = mat.yy;
        // camUp.z = mat.zy;
        // camPos.x = mat.tx;
        // camPos.y = mat.ty;
        // camPos.z = mat.tz;
        // SetVec3J(posAndCamJ["p"]["pos"], pos.x, pos.y, pos.z);
        // SetVec3J(posAndCamJ["p"]["dir"], dir.x, dir.y, dir.z);
        // SetVec3J(posAndCamJ["p"]["up"], up.x, up.y, up.z);
        // SetVec3J(posAndCamJ["c"]["pos"], camPos.x, camPos.y, camPos.z);
        // SetVec3J(posAndCamJ["c"]["dir"], camDir.x, camDir.y, camDir.z);
        // SetVec3J(posAndCamJ["c"]["up"], camUp.x, camUp.y, camUp.z);
    }

    void WatchPosAndCam(uint64 nonce) {
        auto app = GetApp();
        bool wasNullCtx = false;
        while (!IsBadNonce(nonce)) {
            if (IsShutdownClosedOrDC) {
                return;
            }
            if (app.CurrentPlayground !is null) {
                try {
                    auto cp = cast<CSmArenaClient>(app.CurrentPlayground);
                    auto gt = cp.GameTerminals[0];
                    auto p = cast<CSmPlayer>(gt.ControlledPlayer);
                    auto script = cast<CSmScriptPlayer>(p.ScriptAPI);
                    if (IsSpawned(cp, gt, p, script)) {
                        UpdatePlayerPosAndCam(script);
                    } else {
                        SendFixedPosAndCam_PointingAway(-100., -100., -100.);
                    }
                    wasNullCtx = false;
                } catch {
                    dev_warn("Failed to update player pos and cam: " + getExceptionInfo());
                }
            } else if (!wasNullCtx) {
                wasNullCtx = true;
                SendZeroPlayerPosAndCam();
            }
            yield();
        }
    }
}

bool G_ConnectedToMumble = false;

void OnMsg_ConnectedStatus(Json::Value@ msg) {
    G_ConnectedToMumble = msg;
    dev_trace("Connected to server: " + G_ConnectedToMumble);
}

void OnMsg_Ping(Json::Value@ msg) {
    server.lastPingTime = Time::Now;
}

Json::Value GenEmptyPosAndCamJ() {
    auto j = Json::Object();
    j["p"] = GenEmptyMPosStructJ();
    j["c"] = GenEmptyMPosStructJ();
    return j;
}

Json::Value GenEmptyMPosStructJ() {
    auto j = Json::Object();
    j["pos"] = GenVec3J(0.01, 0.01, 0.01);
    j["dir"] = GenVec3J(0, 0, 1);
    j["up"] = GenVec3J(0, 1, 0);
    return j;
}

Json::Value GenEmptyVec3J() {
    auto j = Json::Array();
    j.Add(0.0);
    j.Add(0.0);
    j.Add(0.0);
    return j;
}

Json::Value GenVec3J(float x, float y, float z) {
    auto j = Json::Array();
    j.Add(x);
    j.Add(y);
    j.Add(z);
    return j;
}

void SetVec3J(Json::Value@ j, float x, float y, float z) {
    j[0] = x;
    j[1] = y;
    j[2] = z;
}

bool WriteVec3(Net::Socket@ s, float x, float y, float z) {
    return s.Write(float(x)) && s.Write(float(y)) && s.Write(float(z));
}

const float ROOT2ON2 = 0.7071067811865476;


bool IsSpawned(CSmArenaClient@ cp, CGameTerminal@ gt, CSmPlayer@ p, CSmScriptPlayer@ script) {
#if DEPENDENCY_MLFEEDRACEDATA
    // return MLFeed::GetRaceData_V4().LocalPlayer.IsSpawned;
#endif
    // playing = 1, finish == 11
    auto seq = int(gt.UISequence_Current);
    if (seq != 1 && seq != 11) {
        return false;
    }
    int rulesStartTime = int(cp.Arena.Rules.RulesStateStartTime);
    if (rulesStartTime < 0 || script.StartTime + 1500 < rulesStartTime) return false;
    // during 3.2.1.go
    if (script.StartTime > 0 && script.StartTime + 1500 > rulesStartTime) return true;
    return int(script.Post) == 2;
}
