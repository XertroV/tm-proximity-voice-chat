const string PluginName = Meta::ExecutingPlugin().Name;
const string MenuIconColor = "\\$5f8";
const string PluginIcon = Icons::VolumeControlPhone + Icons::AssistiveListeningSystems;
const string MenuTitle = MenuIconColor + PluginIcon + "\\$z " + PluginName;

string LocalPlayerInfo_Login, LocalPlayerInfo_Name;

ServerConn@ server;

void Main() {
    auto app = GetApp();
    LocalPlayerInfo_Login = app.LocalPlayerInfo.Login;
    LocalPlayerInfo_Name = app.LocalPlayerInfo.Name;
    // @server = ServerConn();
    OnEnabledUpdated();
}

void RenderMenu() {
    if (UI::MenuItem(MenuTitle)) {
        S_Enabled = !S_Enabled;
        OnEnabledUpdated();
    }
}

void OnSettingsChanged() {
    OnEnabledUpdated();
}

void OnEnabledUpdated() {
    if (S_Enabled) {
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
    if (server is null) return;
    if (UI::BeginMenu(MenuTitle)) {
        UI::Text("Connected: " + IconFromBool(server.IsReady));
        UI::Text("Last Msg Sent: " + server.LastSentTimeStr());
        UI::Text("Last Msg Recv: " + server.LastRecvTimeStr());
        UI::Text("Current Map/Room: " + IfEmpty(GetServerLogin(), NoneStr));
        UI::Text("Current Team: " + IfEmpty(GetServerTeamIfTeams(), NoneStr));
        UI::SeparatorText("");
        if (UI::BeginMenu("Stats: Messages")) {
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
        UI::SeparatorText("Controls");

        UI::BeginDisabled(server.IsShutdownClosedOrDC);
        if (UI::ButtonColored("Disconnect Link", .01)) {
            server.Shutdown();
        }
        UI::EndDisabled();

        UI::BeginDisabled(!server.IsShutdownClosedOrDC);
        if (UI::ButtonColored("Reconnect Link", .34)) {
            @server = ServerConn();
        }
        UI::EndDisabled();

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
