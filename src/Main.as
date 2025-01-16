const string PluginName = Meta::ExecutingPlugin().Name;
const string MenuIconColor = "\\$f5d";
const string PluginIcon = Icons::Cogs;
const string MenuTitle = MenuIconColor + PluginIcon + "\\$z " + PluginName;

string LocalPlayerInfo_Login, LocalPlayerInfo_Name;

ServerConn@ server;

void Main() {
    auto app = GetApp();
    LocalPlayerInfo_Login = app.LocalPlayerInfo.Login;
    LocalPlayerInfo_Name = app.LocalPlayerInfo.Name;
    @server = ServerConn();
}

[Setting category="General" name="Always use map chat over server chat" description="If enabled, all chat messages will be sent to the map VC room instead of the server VC room."]
bool S_AlwaysUseMapChatOverServerChat = false;

[Setting category="General" name="Manual Team Name" description="Use this as a 'team' instead of autodetecting. Leave blank to autodetect."]
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
    if (S_ManualTeamName.Length > 0) return S_ManualTeamName;
    auto si = cast<CTrackManiaNetworkServerInfo>(app.Network.ServerInfo);
    if (si.ServerLogin.Length > 0 && si.CurGameModeStr.Length > 0) {
        if (si.CurGameModeStr.Contains("Team")) {
            auto pi = cast<CTrackManiaPlayerInfo>(app.Network.PlayerInfos[0]);
            return tostring(pi.PlaygroundTeamRequested);
        }
    }
    return "All";
}
