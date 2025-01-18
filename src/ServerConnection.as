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


#if MP4
    void UpdateMp4_PPAC_InPlayground(CGameCtnApp@ app) {
        auto cp = cast<CTrackManiaRaceNew>(app.CurrentPlayground);
        if (cp is null) {
            // todo: not in TM2?
            throw("Not in TM2?");
            UpdatePPAC_From(socket.s, null, Camera::GetCurrent(), VE_Loc::NearZero, VE_Loc::NearZero);
            return;
        }
        // auto gt = cast<CTrackManiaGameTerminal>(cp.GameTerminals[0]);
        auto gt = cp.GameTerminals[0];
        auto p = cast<CTrackManiaPlayer>(gt.ControlledPlayer);
        auto script = cast<CTrackManiaScriptPlayer>(p.ScriptAPI);
        CSceneVehicleVisState@ vis = VehicleState::GetVis(app.GameScene, p);
        bool isSpec = script.RequestsSpectate;
        lastPlayerStatus = IsSpawned(cp, gt, p, script) ? PlayerStatus::Spawned : isSpec ? PlayerStatus::Unspawned_Spec : PlayerStatus::Unspawned_Player;
        UpdatePlayerPosAndCam(HasVectors(vis));
        // trace("UpdateMp4_PPAC_InPlayground, vis.Pos: " + vis.Position.ToString());
    }
#elif TMNEXT
    void UpdateTm2020_PPAC_InPlayground(CGameCtnApp@ app) {
        auto cp = cast<CSmArenaClient>(app.CurrentPlayground);
        if (cp is null) {
            // Turns out, CGamePlaygroundBasic appears for like a frame when switching maps
            // since it's just one frame, we can ignore it
            return;
            // auto ty = Reflection::TypeOf(app.CurrentPlayground);
            // NotifyWarning("CP type: " + ty.Name + " | Class ID: " + Text::Format("%08x", ty.ID));
            // lastPlayerStatus = PlayerStatus::None_NoMap;
            // UpdatePPAC_From(socket.s, null, Camera::GetCurrent(), VE_Loc::NearZero, VE_Loc::NearZero);
        }
        // if (cp.GameTerminals) {
        //     NotifyWarning("GameTerminals null!");
        //     UpdatePPAC_From(socket.s, null, Camera::GetCurrent(), VE_Loc::NearZero, VE_Loc::NearZero);
        //     return;
        // }
        if (cp.GameTerminals.Length > 0) {
            auto gt = cp.GameTerminals[0];
            if (gt !is null) {
                auto p = cast<CSmPlayer>(gt.ControlledPlayer);
                if (p !is null) {
                    auto script = cast<CSmScriptPlayer>(p.ScriptAPI);
                    if (script !is null) {
                        bool spawned = IsSpawned(cp, gt, p, script);
                        bool spectator = script.RequestsSpectate;
                        lastPlayerStatus = spawned ? PlayerStatus::Spawned
                            : spectator ? PlayerStatus::Unspawned_Spec : PlayerStatus::Unspawned_Player;
                        UpdatePlayerPosAndCam(HasVectors(script));
                        return;
                    }
                }
            }
        }
        // something was null
        // ignore the frame.
        // alternatively: UpdatePPAC_From(socket.s, null, Camera::GetCurrent(), VE_Loc::NearZero, VE_Loc::NearZero);
    }
#endif

    void UpdatePlayerPosAndCam(HasVectors@ script) {
        if (script is null) {
            warn("script is null");
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
        // dev_warn("OnUpdatePPAC_NoMap: " + tostring(VE_Loc::NearZero));
    }

    void OnUpdatePPAC_UnspawnedPlayer(HasVectors@ script) {
        VE_Loc vl = VE_Loc_OrDefault(S_Unspawned_VoiceLoc, VE_Loc::Camera);
        VE_Loc el = VE_Loc_OrDefault(S_Unspawned_EarsLoc, VE_Loc::Camera);
        // todo: apply settings preference
        // todo: apply rules preference
        UpdatePPAC_From(socket.s, script, Camera::GetCurrent(), vl, el);
        // dev_warn("OnUpdatePPAC_UnspawnedPlayer: " + tostring(vl));
    }

    void OnUpdatePPAC_UnspawnedSpec(HasVectors@ script) {
        VE_Loc vl = VE_Loc_OrDefault(S_Spec_VoiceLoc, VE_Loc::Camera);
        VE_Loc el = VE_Loc_OrDefault(S_Spec_EarsLoc, VE_Loc::Camera);
        // todo: apply settings preference
        // todo: apply rules preference
        UpdatePPAC_From(socket.s, script, Camera::GetCurrent(), vl, el);
        // dev_warn("OnUpdatePPAC_UnspawnedSpec: " + tostring(vl));
    }

    void OnUpdatePPAC_Spawned(HasVectors@ script) {
        VE_Loc vl = VE_Loc_OrDefault(S_Spawned_VoiceLoc, VE_Loc::Player);
        VE_Loc el = VE_Loc_OrDefault(S_Spawned_EarsLoc, VE_Loc::Camera);
        // todo: apply settings preference
        // todo: apply rules preference
        UpdatePPAC_From(socket.s, script, Camera::GetCurrent(), vl, el);
        // dev_warn("OnUpdatePPAC_Spawned: " + tostring(vl) + " | " + script.Pos.ToString());
    }

    bool UpdatePPAC_From(Net::Socket@ s, HasVectors@ script, CHmsCamera@ cam, VE_Loc voiceLoc, VE_Loc earsLoc) {
        bool success = PPAC_WriteHeader(s)
            && PPAC_WriteZone(s, script, cam, voiceLoc)
            && PPAC_WriteZone(s, script, cam, earsLoc);
        if (!success) {
            warn("Failed to write to socket");
        }
        LogSentType("Positions");
        return success;
    }

    bool PPAC_WriteZone(Net::Socket@ s, HasVectors@ script, CHmsCamera@ cam, VE_Loc loc) {
        switch (loc) {
            case VE_Loc::Player:
                return PPAC_WritePlayer(s, script);
            case VE_Loc::Camera:
                return PPAC_WriteMat(s, cam is null ? iso4(mat4::Identity()) : cam.NextLocation);
            case VE_Loc::FarAwayZone1:
            case VE_Loc::FarAwayZone2:
            case VE_Loc::FarAwayZone3:
            case VE_Loc::NearZero:
            case VE_Loc::Zero_DisablePositionalAudio:
                return WriteStaticZone(s, loc);
            default: break;
        }
        warn("Unknown VE_Loc: " + tostring(loc));
        return WriteStaticZone(s, VE_Loc::Zero_DisablePositionalAudio);
    }

    bool WriteStaticZone(Net::Socket@ s, VE_Loc loc) {
        switch (loc) {
            case VE_Loc::FarAwayZone1:
                return PPAC_WritePosAndDefs_3xVec3(s, vec3(-300., -300., 300.));
            case VE_Loc::FarAwayZone2:
                return PPAC_WritePosAndDefs_3xVec3(s, vec3(300., -300., 300.));
            case VE_Loc::FarAwayZone3:
                return PPAC_WritePosAndDefs_3xVec3(s, vec3(0, -300., 300.));
            case VE_Loc::NearZero:
                return PPAC_WritePosAndDefs_3xVec3(s, vec3(0.005, 0.005, 0.005));
            case VE_Loc::Zero_DisablePositionalAudio:
                return PPAC_WritePosAndDefs_3xVec3(s, vec3(0., 0., 0.));
            default: break;
        }
        throw("Non-static/Unknown VE_Loc: " + tostring(loc));
        return PPAC_WritePosAndDefs_3xVec3(s, vec3(0., 0., 0.));
    }

    bool PPAC_WriteDefault_3xVec3(Net::Socket@ s) {
        return PPAC_WritePosAndDefs_3xVec3(s, vec3(0.01, 0.01, 0.01));
    }

    bool PPAC_WritePosAndDefs_3xVec3(Net::Socket@ s, vec3 pos) {
        return WriteVec3(s, pos.x, pos.y, pos.z)
            && WriteVec3(s, POINTING_AWAY_DIR.x, 0, POINTING_AWAY_DIR.z)
            && WriteVec3(s, 0, 1, 0);
    }

    bool PPAC_WriteMat(Net::Socket@ s, const mat4 &in m) {
        return WriteVec3(s, m.tx  * MUMBLE_SCALE, m.ty * MUMBLE_SCALE, m.tz * MUMBLE_SCALE * -1.)
            && WriteVec3(s, m.xz, m.yz, m.zz * -1.)
            && WriteVec3(s, m.xy, m.yy, m.zy * -1.);
    }

    bool PPAC_WritePlayer(Net::Socket@ s, HasVectors@ script) {
        if (script is null) {
            return WriteStaticZone(s, VE_Loc::NearZero);
        }
        vec3 up = script.Up;
        vec3 pos = script.Pos;
        vec3 dir = script.Dir;
// #if TMNEXT
//         up = script.UpDirection;
// #else
//         if (script.Vehicle !is null) {
//             up = script.Vehicle.Up;
//         } else {
//             up = vec3(0, 1, 0);
//         }
// #endif
        up.z *= -1.;
        return WriteVec3(s, pos.x * MUMBLE_SCALE, pos.y * MUMBLE_SCALE, pos.z * MUMBLE_SCALE * -1.)
            && WriteVec3(s, dir.x, dir.y, dir.z * -1.)
            && WriteVec3(s, up.x, up.y, up.z);
    }

    bool PPAC_WriteHeader(Net::Socket@ s) {
        return VarInt::EncodeUint(s, 73) // 1 + (4 * 3 * 3) * 2 = 73
            && s.Write(uint8(1)); // 1 - version/payload marker (json always starts with `{`)
    }

    PlayerStatus lastPlayerStatus = PlayerStatus::None_NoMap;

    void WatchPosAndCam(uint64 nonce) {
        auto app = GetApp();
        bool wasNullCtx = false;
        while (!IsBadNonce(nonce)) {
            if (IsShutdownClosedOrDC) {
                return;
            }
            if (app.CurrentPlayground !is null) {
#if DEV
#else
#endif
                try {

#if MP4
                    UpdateMp4_PPAC_InPlayground(app);
#else
                    UpdateTm2020_PPAC_InPlayground(app);
#endif
                    wasNullCtx = false;
                } catch {
                    // dev_warn("Failed to update player pos and cam: " + getExceptionInfo());
                    DevNotifyWarning("Failed to update player pos and cam: " + getExceptionInfo());
                    // NotifyWarnOnce("Failed to update player pos and cam: " + getExceptionInfo());
                    lastPlayerStatus = PlayerStatus::None_NoMap;
                }
#if DEV
#else
#endif
            } else {
                UpdatePPAC_From(socket.s, null, Camera::GetCurrent(), VE_Loc::NearZero, VE_Loc::NearZero);
                if (!wasNullCtx) {
                    wasNullCtx = true;
                    lastPlayerStatus = PlayerStatus::None_NoMap;
                }
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

vec3 dbg_lastVec3Written;

bool WriteVec3(Net::Socket@ s, float x, float y, float z) {
#if DEV
    dbg_lastVec3Written = vec3(x, y, z);
#endif
    // turns out it wasn't jitter that was needed, but just updating the values at all. I guess there's a flag or timestamp or something.
    return s.Write(float(x)) && s.Write(float(y)) && s.Write(float(z));
}


#if TMNEXT
bool IsSpawned(CSmArenaClient@ cp, CGameTerminal@ gt, CSmPlayer@ p, CSmScriptPlayer@ script) {
#if DEV && DEPENDENCY_MLFEEDRACEDATA
    // && FALSE
    // return MLFeed::GetRaceData_V4().LocalPlayer.IsSpawned;
#elif DEPENDENCY_MLFEEDRACEDATA
    auto rd = MLFeed::GetRaceData_V4();
    if (rd !is null) {
        auto lp = rd.LocalPlayer;
        if (lp !is null) {
            return lp.SpawnStatus != MLFeed::SpawnStatus::NotSpawned;
        }
    }
#endif

    // playing = 1, finish == 11
    auto seq = int(gt.UISequence_Current);
    if (seq != 1 && seq != 11) {
        return false;
    }
    int rulesStartTime = int(cp.Arena.Rules.RulesStateStartTime);
    if (rulesStartTime < 0 || script.StartTime < 0) return false;
    // during 3.2.1.go
    if (p.SpawnIndex < 0) return false;
    if (script.Position.LengthSquared() < 0.01) return false;
    // Post = Char before we start racing
    return int(script.Post) == 2 || (script.StartTime > 0 && script.StartTime > int(GetApp().Network.PlaygroundInterfaceScriptHandler.GameTime));
}
#elif MP4
bool IsSpawned(CTrackManiaRaceNew@ cp, CGameTerminal@ gt, CTrackManiaPlayer@ p, CTrackManiaScriptPlayer@ script) {
    if (p is null) return false;
    bool raceStateSpawned = p.RaceState == CTrackManiaPlayer::ERaceState::BeforeStart
            || p.RaceState == CTrackManiaPlayer::ERaceState::Running;
    // return false when Finished to avoid
    return script.IsSpawned && raceStateSpawned;
}
#endif


#if MP4
class HasVectors {
    CSceneVehicleVisState@ vis;
    HasVectors(CSceneVehicleVisState@ vis) {
        @this.vis = vis;
    }
    vec3 get_Pos() {
        return vis.Position;
    }
    vec3 get_Dir() {
        return vis.Dir;
    }
    vec3 get_Up() {
        return vis.Up;
    }
}
#elif TMNEXT
class HasVectors {
    CSmScriptPlayer@ script;
    HasVectors(CSmScriptPlayer@ script) {
        @this.script = script;
    }
    vec3 get_Pos() {
        return script.Position;
    }
    vec3 get_Dir() {
        return script.AimDirection;
    }
    vec3 get_Up() {
        return script.UpDirection;
    }
}
#endif
