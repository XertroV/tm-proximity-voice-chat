const string PluginName = Meta::ExecutingPlugin().Name;
const string MenuIconColor = "\\$5f8";
const string PluginIcon = Icons::VolumeControlPhone + Icons::AssistiveListeningSystems;
const string MenuTitle = MenuIconColor + PluginIcon + "\\$z " + PluginName;

const string LATEST_LINK_APP_VERISON = "1.0.1";

string LocalPlayerInfo_Login, LocalPlayerInfo_Name;

ServerConn@ server;

void Main() {
    auto app = GetApp();
#if TMNEXT
    LocalPlayerInfo_Login = app.LocalPlayerInfo.Login;
    LocalPlayerInfo_Name = app.LocalPlayerInfo.Name;
    warn("TM NExt");
#else
    // works for mp4, not sure about turbo
    auto net = cast<CTrackManiaNetwork>(app.Network);
    while (net is null) {
        warn("Network is null, waiting for it to be initialized...");
        startnew(ThrowBecause, "network is null");
        sleep(1000);
        @net = cast<CTrackManiaNetwork>(app.Network);
    }

    while (net.PlayerInfo.Login == "00000000") yield();
    print("PlayerInfo.Login: " + net.PlayerInfo.Login);
    print("PlayerInfo.Name: " + net.PlayerInfo.Name);

    LocalPlayerInfo_Login = net.PlayerInfo.Login;
    LocalPlayerInfo_Name = net.PlayerInfo.Name;
#endif

    // in case of heavy operations (like we started TM recently, restarted script engine), wait for the frame rate to stabilize before connecting sockets to avoid timeout stuff.
    WaitForStableFrameRateBeforeConnectingSocket();
    // @server = ServerConn();
    OnEnabledUpdated();
}


// Coro to make use of menubar showing exceptions
void ThrowBecause(const string &in msg) {
    throw(msg);
}


void WaitForStableFrameRateBeforeConnectingSocket() {
    uint64 t = Time::Now;
    int loopCount = 0;
    int goodSuccessiveFrames = 0;
    while (loopCount < 200) {
        yield();
        loopCount++;
        if (Time::Now - t < 100) {
            goodSuccessiveFrames++;
        } else {
            goodSuccessiveFrames = 0;
        }
        t = Time::Now;
        if (goodSuccessiveFrames > 10) {
            break;
        }
    }
}


void OnEnabled() {
    Main();
}
void _Unload() {
    if (server !is null) {
        server.Shutdown();
        @server = null;
    }
}
void OnDisabled() { _Unload(); }
void OnDestroyed() { _Unload(); }

void RenderMenu() {
    if (UI::MenuItem(MenuTitle, "", (S_Enabled && !S_ShowWizard) || (S_ShowWizard && !WizardLater))) {
        if (S_ShowWizard && WizardLater) WizardLater = false;
        else if (S_ShowWizard) WizardLater = true;
        else {
            S_Enabled = !S_Enabled;
            OnEnabledUpdated();
        }
    }
}

void OnSettingsChanged() {
    OnEnabledUpdated();
}

void OnEnabledUpdated() {
    if (S_Enabled && !S_ShowWizard) {
        if (server !is null) {
            server.Shutdown();
        }
        @server = ServerConn();
    } else if (server !is null) {
        server.Shutdown();
        @server = null;
    }
}

string IfEmpty(const string &in v, const string &in other) {
    if (v.Length == 0) return other;
    return v;
}
const string NoneStr = "\\$<\\$999\\$iNone\\$>";


void RenderMenuMain() {
    if (server is null && !S_ShowWizard) return;

    bool serverNotNull = server !is null;
    auto lastSent = serverNotNull ? server.LastSentTimeStr() : "\\$999--:--";
    auto lastRecv = serverNotNull ? server.LastRecvTimeStr() : "\\$999--:--";
    bool isConnecting = serverNotNull && server.IsConnecting;
    bool isConnected = serverNotNull && server.IsReady;
    bool isDisconnected = !isConnected && !isConnecting;

    if (UI::BeginMenu(MenuTitle)) {
        UI::Text("Connected: " + (isConnecting ? ConnectingIcon() : IconFromBool(isConnected)));
        if (serverNotNull && !isConnected) {
            UI::SameLine();
            UI::Text("\\$i\\$999Connection Failures: " + server.connectFailureCount);
        }

#if DEV
        UI::Text("Last vec3: " + dbg_lastVec3Written.ToString());
#endif
        UI::Text("Last Msg Sent: " + lastSent);
        UI::Text("Last Msg Recv: " + lastRecv);
        UI::Text("Current Map/Room: " + IfEmpty(GetServerLogin(), NoneStr));
        UI::Text("Current Team: " + IfEmpty(GetServerTeamIfTeams(), NoneStr));
        UI::SeparatorText("");
        if (serverNotNull && UI::BeginMenu("Stats: Messages")) {
            auto @keys = server.recvCount.GetKeys();
            UI::SeparatorText("Received Messages");
            for (uint i = 0; i < keys.Length; i++) {
                auto key = keys[i];
                auto count = uint64(server.recvCount[key]);
                if (UI::MenuItem(key + " (" + count + ")")) {
                }
            }
            UI::SeparatorText("Sent Messages");
            @keys = server.sendCount.GetKeys();
            for (uint i = 0; i < keys.Length; i++) {
                auto key = keys[i];
                auto count = uint64(server.sendCount[key]);
                if (UI::MenuItem(key + " (" + count + ")")) {
                }
            }
            UI::EndMenu();
        }

        if (UI::MenuItem("Show Wizard", "", S_ShowWizard && !WizardLater)) {
            if (WizardLater) S_ShowWizard = !(WizardLater = false);
            else if (S_ShowWizard) WizardLater = true;
            else S_ShowWizard = true;
        }

        if (server !is null) {
            UI::SeparatorText("Position Settings");
            UI::Text("Current Player Status: " + tostring(server.lastPlayerStatus));
            if (server.lastPlayerStatus == PlayerStatus::Spawned) {
                S_Spawned_VoiceLoc = UI_VE_MenuSelectable("Set Voice Location", S_Spawned_VoiceLoc);
                S_Spawned_EarsLoc = UI_VE_MenuSelectable("Set Ears Location", S_Spawned_EarsLoc);
                auto setBoth = UI_VE_MenuSelectable("Set Both", S_Spawned_EarsLoc == S_Spawned_VoiceLoc ? S_Spawned_EarsLoc : VE_Loc::None_Uninitialized);
                if (setBoth != VE_Loc::None_Uninitialized) {
                    S_Spawned_VoiceLoc = S_Spawned_EarsLoc = setBoth;
                }
                if (UI::Button("Reset##spwanwed")) {
                    S_Spawned_VoiceLoc = VE_Loc::Player;
                    S_Spawned_EarsLoc = VE_Loc::Camera;
                }
            } else if (server.lastPlayerStatus == PlayerStatus::Unspawned_Player) {
                S_Unspawned_VoiceLoc = UI_VE_MenuSelectable("Set Voice Location", S_Unspawned_VoiceLoc);
                S_Unspawned_EarsLoc = UI_VE_MenuSelectable("Set Ears Location", S_Unspawned_EarsLoc);
                auto setBoth = UI_VE_MenuSelectable("Set Both", S_Unspawned_EarsLoc == S_Unspawned_VoiceLoc ? S_Unspawned_EarsLoc : VE_Loc::None_Uninitialized);
                if (setBoth != VE_Loc::None_Uninitialized) {
                    S_Unspawned_VoiceLoc = S_Unspawned_EarsLoc = setBoth;
                }
            } else if (server.lastPlayerStatus == PlayerStatus::Unspawned_Spec) {
                S_Spec_VoiceLoc = UI_VE_MenuSelectable("Set Voice Location", S_Spec_VoiceLoc);
                S_Spec_EarsLoc = UI_VE_MenuSelectable("Set Ears Location", S_Spec_EarsLoc);
                auto setBoth = UI_VE_MenuSelectable("Set Both", S_Spec_EarsLoc == S_Spec_VoiceLoc ? S_Spec_EarsLoc : VE_Loc::None_Uninitialized);
                if (setBoth != VE_Loc::None_Uninitialized) {
                    S_Spec_VoiceLoc = S_Spec_EarsLoc = setBoth;
                }
            }

            UI::SeparatorText("Controls");

            UI::BeginDisabled(server.IsShutdownClosedOrDC);
            if (UI::ButtonColored("Disconnect Link", .01)) {
                server.Shutdown();
            }
            UI::EndDisabled();

            UI::BeginDisabled(!server.IsShutdownClosedOrDC);
            if (UI::ButtonColored("Reconnect Link", .34)) {
                if (server !is null) server.Shutdown();
                @server = ServerConn();
            }
            UI::EndDisabled();

            if (server.IsShutdownClosedOrDC && UI::Button("Turn Off Plugin")) {
                S_Enabled = false;
                OnEnabledUpdated();
            }
        }

        UI::EndMenu();
    }
}

[Setting category="General" name="Plugin Enabled and Active" description="When disabled, the plugin will disconnect from the server and do nothing."]
bool S_Enabled = true;

[Setting category="General" name="Always use map chat over server chat" description="If enabled, all chat messages will be sent to the map VC room instead of the server VC room."]
bool S_AlwaysUseMapChatOverServerChat = false;

[Setting category="General" name="Manual Team Name" description="Use this as a 'team' instead of autodetecting. Leave blank to autodetect. Minimum 2 characters."]
string S_ManualTeamName = "";

string GetServerLogin() {
    auto app = GetApp();
    if (!S_AlwaysUseMapChatOverServerChat) {
        auto si = cast<CTrackManiaNetworkServerInfo>(app.Network.ServerInfo);
        if (si !is null && si.ServerLogin.Length > 0) {
            return si.ServerLogin;
        }
    }
    if (app.Editor is null && app.RootMap !is null) {
        return app.RootMap.IdName;
    }
    return "";
}

string GetServerTeamIfTeams() {
    auto app = GetApp();
    if (S_ManualTeamName.Length > 1) return S_ManualTeamName;
    auto si = cast<CTrackManiaNetworkServerInfo>(app.Network.ServerInfo);
    if (si.ServerLogin.Length > 0 && si.CurGameModeStr.Length > 0) {
        if (si.CurGameModeStr.Contains("Team")) {
            try {
                auto cp = cast<CSmArenaClient>(app.CurrentPlayground);
                auto p = cast<CSmPlayer>(cp.GameTerminals[0].ControlledPlayer);
                return tostring(p.EdClan);
            } catch {
                return "0";
            }
        }
    }
    return "All";
}

const string IconCheck = "\\$<\\$5f5" + Icons::Check + "\\$>";
const string IconTimes = "\\$<\\$f55" + Icons::Times + "\\$>";

string IconFromBool(bool v) {
    return v ? IconCheck : IconTimes;
}

string ConnectingIcon() {
    int frame = (Time::Now / 250) % 4;
    // return "\\$<\\$ff5" + Icons::X + "\\$>";
    switch (frame) {
        case 0: return "\\$<\\$ff5" + Icons::HourglassStart + "\\$>";
        case 1: return "\\$<\\$ff5" + Icons::HourglassHalf + "\\$>";
        case 2: return "\\$<\\$ff5" + Icons::HourglassEnd + "\\$>";
        case 3: return "\\$<\\$ff5" + Icons::HourglassHalf + "\\$>";
    }
    return "\\$<\\$ff5" + Icons::Hourglass + "\\$>";
}
