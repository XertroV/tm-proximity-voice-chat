const uint PING_PERIOD = 6789;

// mumble defaults 1m and 15m. A base of like 32m means 15 scales to 480m
const float MUMBLE_SCALE = 1. / 32.;

const float ROOT2ON2 = 0.7071067811865476;

const vec3 POINTING_AWAY_DIR = vec3(-ROOT2ON2, 0, ROOT2ON2);

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
            if (server !is this) {
                Shutdown();
                return;
            }
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
        return socket is null || _isShutdown || socket.IsClosed || socket.ServerDisconnected;
    }

    bool get_IsConnecting() {
        return socket !is null && socket.IsConnecting;
    }

    int connectFailureCount = 0;

    protected void ReconnectSocket() {
        NewRunNonce();
        auto nonce = runNonce;
        IsReady = false;
        dev_trace("ReconnectSocket");
        if (_isShutdown) return;
        if (socket.ReconnectToServer()) {
            startnew(CoroutineFuncUserdataUint64(BeginLoop), nonce);
            connectFailureCount = 0;
        } else {
            connectFailureCount++;
            dev_warn("[DEV] Failed to connect to server.");
            int sleepSec = 5 * connectFailureCount;
            trace("Failed to reconnect to server " + connectFailureCount + " time, sleeping " + sleepSec + " sec then retry.");
            if (connectFailureCount > 5) {
                NotifyWarning("Failed to connect to server after " + connectFailureCount + " attempts. Shutting down. Please re-connect Proximity VC when you have the TM to Mumble Link app running.");
                Shutdown();
                return;
            }
            sleep(sleepSec * 1000);
            if (IsBadNonce(nonce)) return;
            startnew(CoroutineFunc(ReconnectSocket));
        }
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
        dev_trace("Connected to server... setting ServerConnection::IsReady = true;");
        IsReady = true;
        QueueMsg(GetPlayerDetailsMsg());
        QueueMsg(GetServerDetailsMsg());
        startnew(CoroutineFuncUserdataUint64(ReadLoop), nonce);
        startnew(CoroutineFuncUserdataUint64(SendLoop), nonce);
        startnew(CoroutineFuncUserdataUint64(SendPingLoop), nonce);
        startnew(CoroutineFuncUserdataUint64(ReconnectWhenDisconnected), nonce);
        startnew(CoroutineFuncUserdataUint64(WatchForServerChange), nonce);
        startnew(CoroutineFuncUserdataUint64(WatchPosAndCam), nonce);
        startnew(CoroutineFunc(CheckLinkAppVersion));
        Notify("Connected to Link app.");
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
            if (Time::Now - lastPingTime > PING_PERIOD + 2000 && IsReady) {
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
        @msgHandlers["LinkAppInfo"] = MsgHandler(OnMsg_LinkAppInfo);
        @msgHandlers["ShutdownNow"] = MsgHandler(OnMsg_ShutdownNow);
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

    void UpdatePlayerPosAndCam(CSmScriptPlayer@ script) {
        if (script is null) {
            OnUpdatePPAC_NoMap();
            return;
        }
        switch (lastPlayerStatus) {
            case PlayerStatus::None_NoMap:
                OnUpdatePPAC_NoMap();
                break;
            case PlayerStatus::Unspawned_Player:
                OnUpdatePPAC_UnspawnedPlayer(script);
                break;
            case PlayerStatus::Unspawned_Spec:
                OnUpdatePPAC_UnspawnedSpec(script);
                break;
            case PlayerStatus::Spawned:
                OnUpdatePPAC_Spawned(script);
                break;
        }
    }

    void OnUpdatePPAC_NoMap() {
        // no settings for this
        // SendZeroPlayerPosAndCam();
        UpdatePPAC_From(socket.s, null, Camera::GetCurrent(), VE_Loc::NearZero, VE_Loc::NearZero);
        // auto s = socket.s;
        // auto success = PPAC_WriteHeader(s)
        //     && PPAC_WriteDefault_3xVec3(s)
        //     && PPAC_WriteDefault_3xVec3(s);
        // if (!success) warn("OnUpdatePPAC_NoMap Failed to write to socket");
        // LogSentType("Positions");
    }

    void OnUpdatePPAC_UnspawnedPlayer(CSmScriptPlayer@ script) {
        VE_Loc vl = VE_Loc_OrDefault(S_Unspawned_VoiceLoc, VE_Loc::Camera);
        VE_Loc el = VE_Loc_OrDefault(S_Unspawned_EarsLoc, VE_Loc::Camera);
        // todo: apply settings preference
        // todo: apply rules preference
        UpdatePPAC_From(socket.s, script, Camera::GetCurrent(), vl, el);
        // UpdatePPAC_FromCamOnly();
    }

    void OnUpdatePPAC_UnspawnedSpec(CSmScriptPlayer@ script) {
        VE_Loc vl = VE_Loc_OrDefault(S_Spec_VoiceLoc, VE_Loc::Camera);
        VE_Loc el = VE_Loc_OrDefault(S_Spec_EarsLoc, VE_Loc::Camera);
        // todo: apply settings preference
        // todo: apply rules preference
        UpdatePPAC_From(socket.s, script, Camera::GetCurrent(), vl, el);
        // UpdatePPAC_FromCamOnly();
    }

    void OnUpdatePPAC_Spawned(CSmScriptPlayer@ script) {
        VE_Loc vl = VE_Loc_OrDefault(S_Spawned_VoiceLoc, VE_Loc::Player);
        VE_Loc el = VE_Loc_OrDefault(S_Spawned_EarsLoc, VE_Loc::Camera);
        // todo: apply settings preference
        // todo: apply rules preference
        UpdatePPAC_From(socket.s, script, Camera::GetCurrent(), vl, el);
    }

    bool UpdatePPAC_From(Net::Socket@ s, CSmScriptPlayer@ script, CHmsCamera@ cam, VE_Loc voiceLoc, VE_Loc earsLoc) {
        bool success = PPAC_WriteHeader(s)
            && PPAC_WriteZone(s, script, cam, voiceLoc)
            && PPAC_WriteZone(s, script, cam, earsLoc);
        if (!success) {
            warn("Failed to write to socket");
        }
        LogSentType("Positions");
        return success;
    }

    bool PPAC_WriteZone(Net::Socket@ s, CSmScriptPlayer@ script, CHmsCamera@ cam, VE_Loc loc) {
        switch (loc) {
            case VE_Loc::Player:
                return PPAC_WritePlayer(s, script);
            case VE_Loc::Camera:
                return PPAC_WriteMat(s, cam.NextLocation);
            case VE_Loc::FarAwayZone1: // , -100., -100., 100.);
            case VE_Loc::FarAwayZone2: // , 100., -100., 100.);
            case VE_Loc::FarAwayZone3: // , 0, -100., 100.);
            case VE_Loc::NearZero: // , 0.01, 0.01, 0.01);
            case VE_Loc::Zero_DisablePositionalAudio: // , 0., 0., 0.);
                return WriteStaticZone(s, loc);
            default: break;
        }
        warn("Unknown VE_Loc: " + tostring(loc));
        return WriteStaticZone(s, VE_Loc::Zero_DisablePositionalAudio);
    }

    bool WriteStaticZone(Net::Socket@ s, VE_Loc loc) {
        switch (loc) {
            case VE_Loc::FarAwayZone1:
                return WriteVec3(s, -300., -300., 300.);
            case VE_Loc::FarAwayZone2:
                return WriteVec3(s, 300., -300., 300.);
            case VE_Loc::FarAwayZone3:
                return WriteVec3(s, 0, -300., 300.);
            case VE_Loc::NearZero:
                return WriteVec3(s, 0.01, 0.01, 0.01);
            case VE_Loc::Zero_DisablePositionalAudio:
                return WriteVec3(s, 0., 0., 0.);
            default: break;
        }
        throw("Non-static/Unknown VE_Loc: " + tostring(loc));
        return WriteVec3(s, 0., 0., 0.);
    }

    bool PPAC_WriteDefault_3xVec3(Net::Socket@ s) {
        return WriteVec3(s, 0.01, 0.01, 0.01)
            && WriteVec3(s, POINTING_AWAY_DIR.x, 0, POINTING_AWAY_DIR.z)
            && WriteVec3(s, 0, 1, 0);
    }

    bool PPAC_WriteMat(Net::Socket@ s, const mat4 &in m) {
        return WriteVec3(s, m.tx  * MUMBLE_SCALE, m.ty * MUMBLE_SCALE, m.tz * MUMBLE_SCALE * -1.)
            && WriteVec3(s, m.xz, m.yz, m.zz * -1.)
            && WriteVec3(s, m.xy, m.yy, m.zy * -1.);
    }

    bool PPAC_WritePlayer(Net::Socket@ s, CSmScriptPlayer@ script) {
        if (script is null) {
            return WriteStaticZone(s, VE_Loc::NearZero);
        }
        return WriteVec3(s, script.Position.x * MUMBLE_SCALE, script.Position.y * MUMBLE_SCALE, script.Position.z * MUMBLE_SCALE * -1.)
            && WriteVec3(s, script.AimDirection.x, script.AimDirection.y, script.AimDirection.z * -1.)
            && WriteVec3(s, script.UpDirection.x, script.UpDirection.y, script.UpDirection.z * -1.);
    }

    bool PPAC_WriteHeader(Net::Socket@ s) {
        return VarInt::EncodeUint(s, 73) // 1 + (4 * 3 * 3) * 2 = 73
            && s.Write(uint8(1)); // 1 - version/payload marker (json always starts with `{`)
    }

    // void UpdatePPAC_FromCamOnly() {
    //     auto cam = Camera::GetCurrent();
    //     auto mat = cam.NextLocation;
    //     auto s = socket.s;
    //     bool success = PPAC_WriteHeader(s)
    //         && PPAC_WriteMat(s, mat)
    //         && PPAC_WriteMat(s, mat);
    //     if (!success) {
    //         warn("Failed to write to socket");
    //     }
    //     LogSentType("Positions");
    // }

    // // vec3 pos, dir, up, camPos, camDir, camUp;
    // void UpdatePlayerPosAndCam_FromPlayerAndCamera(CSmScriptPlayer@ script) {
    //     // todo: VCMode

    //     auto s = socket.s;
    //     VarInt::EncodeUint(s, 73); // 1 + (4 * 3 * 3 * 2) = 73
    //     s.Write(uint8(1)); // 1
    //     // mumble proximity defaults are 1m and 15m so divide pos by 32
    //     // the server uses left handed coords, but tm uses right handed coords, so flip the z axis
    //     // s.Write(float(script.Position.x * MUMBLE_SCALE)); // 5
    //     // s.Write(float(script.Position.y * MUMBLE_SCALE)); // 9
    //     // s.Write(float(script.Position.z * MUMBLE_SCALE * -1.));  // 13
    //     // s.Write(float(script.AimDirection.x));  // 17
    //     // s.Write(float(script.AimDirection.y));  // 21
    //     // s.Write(float(script.AimDirection.z * -1.));
    //     // s.Write(float(script.UpDirection.x));
    //     // s.Write(float(script.UpDirection.y));
    //     // s.Write(float(script.UpDirection.z * -1.));
    //     PPAC_WritePlayer(s, script);
    //     auto cam = Camera::GetCurrent();
    //     bool success = PPAC_WriteMat(s, cam.NextLocation);
    //     // s.Write(float(mat.tx * MUMBLE_SCALE));
    //     // s.Write(float(mat.ty * MUMBLE_SCALE));
    //     // s.Write(float(mat.tz * MUMBLE_SCALE * -1.));
    //     // s.Write(float(mat.xz));
    //     // s.Write(float(mat.yz));
    //     // s.Write(float(mat.zz * -1.));
    //     // s.Write(float(mat.xy));
    //     // s.Write(float(mat.yy));
    //     // bool success = s.Write(float(mat.zy * -1.));
    //     if (!success) {
    //         warn("Failed to write to socket");
    //     }
    //     LogSentType("Positions");
    // }

    PlayerStatus lastPlayerStatus = PlayerStatus::None_NoMap;

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
                    bool spawned = IsSpawned(cp, gt, p, script);
                    bool spectator = script.RequestsSpectate;
                    lastPlayerStatus = spawned ? PlayerStatus::Spawned
                        : spectator ? PlayerStatus::Unspawned_Spec : PlayerStatus::Unspawned_Player;
                    UpdatePlayerPosAndCam(script);
                    // if (spawned) {
                    // } else {
                    //     SendFixedPosAndCam_PointingAway(-100., -100., -100.);
                    // }
                    wasNullCtx = false;
                } catch {
                    dev_warn("Failed to update player pos and cam: " + getExceptionInfo());
                    lastPlayerStatus = PlayerStatus::None_NoMap;
                }
            } else if (!wasNullCtx) {
                wasNullCtx = true;
                lastPlayerStatus = PlayerStatus::None_NoMap;
                SendZeroPlayerPosAndCam();
            }
            yield();
        }
    }

    void CheckLinkAppVersion() {
        sleep(500);
        if (server is null || server.IsShutdownClosedOrDC) return;
        if (g_LinkAppVersion.Length == 0) g_LinkAppVersion = "1.0.0";
        if (IsVersionLess(g_LinkAppVersion, LATEST_LINK_APP_VERISON)) {
            NotifySuccess("Link app update available:\n\t\tv" + LATEST_LINK_APP_VERISON + "\nYou have:\n\t\tv" + g_LinkAppVersion, 7500);
        }
    }
}

bool IsVersionLess(const string &in a, const string &in b) {
    auto aParts = a.Split(".");
    auto bParts = b.Split(".");
    int ia, ib;
    for (int i = 0; i < Math::Min(int(aParts.Length), int(bParts.Length)); i++) {
        if (!Text::TryParseInt(aParts[i], ia)) return true;
        if (!Text::TryParseInt(bParts[i], ib)) return false;
        if (ia < ib) return true;
        if (ia > ib) return false;
    }
    return aParts.Length < bParts.Length;
}

bool G_ConnectedToMumble = false;

void OnMsg_ConnectedStatus(Json::Value@ msg) {
    G_ConnectedToMumble = msg;
    dev_trace("Connected to server: " + G_ConnectedToMumble);
}

void OnMsg_Ping(Json::Value@ msg) {
    server.lastPingTime = Time::Now;
}

// default to ver: 1.0.0
string g_LinkAppVersion = "";
void OnMsg_LinkAppInfo(Json::Value@ msg) {
    g_LinkAppVersion = msg["version"];
    // [(string, string)]
    Json::Value@ appOptions = msg["options"];
    trace("Connected to link app, version: " + g_LinkAppVersion);
}

void OnMsg_ShutdownNow(Json::Value@ msg) {
    if (server !is null) {
        warn("Got shutdown message from server. Shutting down.");
        server.Shutdown();
    } else {
        warn("Received shutdown message but server is null?!");
    }
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


bool IsSpawned(CSmArenaClient@ cp, CGameTerminal@ gt, CSmPlayer@ p, CSmScriptPlayer@ script) {
#if DEV && DEPENDENCY_MLFEEDRACEDATA
    // return MLFeed::GetRaceData_V4().LocalPlayer.IsSpawned;
#elif DEPENDENCY_MLFEEDRACEDATA
    return MLFeed::GetRaceData_V4().LocalPlayer.IsSpawned;
#endif

    // playing = 1, finish == 11
    auto seq = int(gt.UISequence_Current);
    if (seq != 1 && seq != 11) {
        return false;
    }
    int rulesStartTime = int(cp.Arena.Rules.RulesStateStartTime);
    if (rulesStartTime < 0 || script.StartTime + 1500 < rulesStartTime) return false;
    // during 3.2.1.go
    if (p.SpawnIndex < 0) return false;
    if (script.Position.LengthSquared() < 0.01) return false;
    // Post = Char before we start racing
    return int(script.Post) == 2 || (script.StartTime > 0 && script.StartTime > int(GetApp().Network.PlaygroundInterfaceScriptHandler.GameTime));
}
