#if TMNEXT
// Borrowed from BRM
namespace FromBRM {
    string ServerLogin;
    string ServerName;
    int ClubId = -1;
    int RoomId = -1;
    bool IsAdmin = false;
    bool FinishedLoading = false;

    void ResetClubRoom() {
        ServerLogin = "";
        ServerName = "";
        ClubId = -1;
        RoomId = -1;
        IsAdmin = false;
        FinishedLoading = false; // !loading;
        ResetServerSettings();
    }

    void OnJoinedServer() {
        ResetClubRoom();
        auto app = cast<CTrackMania>(GetApp());
        ServerLogin = app.ManiaPlanetScriptAPI.CurrentServerLogin;
        ServerName = app.ManiaPlanetScriptAPI.CurrentServerName;

        auto si = cast<CTrackManiaNetworkServerInfo>(app.Network.ServerInfo);
        auto declaredVars = string(app.Network.ClientManiaAppPlayground.Dbg_DumpDeclareForVariables(si.TeamProfile1, false));
        // wait up to Xs for club ID
        auto maxWait = 60 * 1000;
        int startedAt = Time::Now;
        while (app.Network.ClientManiaAppPlayground !is null
            && !declaredVars.Contains("Net_TMGame_DecoImage_ClubId = ")
            && Time::Now - startedAt < maxWait
            && ServerLogin == app.ManiaPlanetScriptAPI.CurrentServerLogin
        ) {
            sleep(250);
            declaredVars = string(app.Network.ClientManiaAppPlayground.Dbg_DumpDeclareForVariables(si.TeamProfile1, false));
        }
        auto parts = declaredVars.Split("Net_TMGame_DecoImage_ClubId = ");
        FinishedLoading = parts.Length <= 1;
        if (FinishedLoading) return;
        ClubId = -1;
        if (!Text::TryParseInt(parts[1].Split("\n", 3)[0], ClubId)) {
            dev_warn("Failed to parse ClubId from: " + parts[1]);
        } else {
            dev_trace("Joined server with ClubId: " + ClubId + " / ServerLogin: " + ServerLogin);
            RoomId = _GetRoomId();
        }
        FinishedLoading = true;
    }

    // adapted from BRM.
    int _GetRoomId() {
        // ClubId, ServerName, ServerLogin
        auto activities = Live::GetClubActivities(ClubId, true, 100, 0);
        auto @rooms = activities['activityList'];
        auto pages = int(activities['maxPage']);
        if (pages > 1) {
            trace("[WARN] Only checking the first page of club activities for club " + ClubId + " since there are " + pages + " pages");
        }
        int foundRoom = -1;
        for (uint i = 0; i < rooms.Length; i++) {
            auto activity = rooms[i];
            if (string(activity['activityType']) != "room") continue;
            if (string(activity['name']) != ServerName) continue;
            foundRoom = activity['id'];
            break;
        }
        dev_trace('Found room: ' + foundRoom);
        return foundRoom;
    }
}


namespace Live {
    // Ensure we aren't calling a bad path
    void AssertGoodPath(string &in path) {
        if (path.Length <= 0 || !path.StartsWith("/")) {
            throw("API Paths should start with '/'!");
        }
    }
    // Length and offset get params helper
    const string LengthAndOffset(uint length, uint offset) {
        return "length=" + length + "&offset=" + offset;
    }

    Json::Value@ CallLiveApiPath(const string &in path) {
        AssertGoodPath(path);
        return FetchLiveEndpoint(NadeoServices::BaseURLLive() + path);
    }

    // https://webservices.openplanet.dev/live/clubs/activities
    Json::Value@ GetClubActivities(uint clubId, bool active, uint length = 100, uint offset = 0) {
        return CallLiveApiPath("/api/token/club/" + clubId + "/activity?active=" + tostring(active) + "&" + LengthAndOffset(length, offset));
    }

    // https://webservices.openplanet.dev/live/clubs/room-by-id
    Json::Value@ GetClubRoom(uint clubId, uint roomId) {
        return CallLiveApiPath("/api/token/club/" + clubId + "/room/" + roomId);
    }

    Json::Value@ FetchLiveEndpoint(const string &in route) {
        trace("[FetchLiveEndpoint] Requesting: " + route);
        auto req = NadeoServices::Get("NadeoLiveServices", route);
        req.Start();
        while(!req.Finished()) { yield(); }
        return req.Json();
    }
}
#endif




void RegisterServerSetting(const string &in settingName, Json::Value@ j) {
    // settingName == j["key"]
    string value = j["value"];
    string type = j["type"];
    if (type == "text") {
        ServerSettings::RegisterText(settingName, value);
    } else if (type == "integer") {
        ServerSettings::RegisterInteger(settingName, value);
    } else {
        dev_warn("Unknown server setting type: " + type);
    }
}

void ResetServerSettings() {
    ServerSettings::Reset();
}

namespace ServerSettings {
    VE_Loc X_ProxVC_Player_VoiceLoc = VE_Loc::None_Uninitialized;
    VE_Loc X_ProxVC_Player_EarsLoc = VE_Loc::None_Uninitialized;
    VE_Loc X_ProxVC_UnspawnedPlayer_VoiceLoc = VE_Loc::None_Uninitialized;
    VE_Loc X_ProxVC_UnspawnedPlayer_EarsLoc = VE_Loc::None_Uninitialized;
    VE_Loc X_ProxVC_Spec_VoiceLoc = VE_Loc::None_Uninitialized;
    VE_Loc X_ProxVC_Spec_EarsLoc = VE_Loc::None_Uninitialized;
    string X_ProxVC_Player_Team = "";
    string X_ProxVC_UnspawnedPlayer_Team = "";
    string X_ProxVC_Spec_Team = "";

    void Reset() {
        X_ProxVC_Player_VoiceLoc = VE_Loc::None_Uninitialized;
        X_ProxVC_Player_EarsLoc = VE_Loc::None_Uninitialized;
        X_ProxVC_UnspawnedPlayer_VoiceLoc = VE_Loc::None_Uninitialized;
        X_ProxVC_UnspawnedPlayer_EarsLoc = VE_Loc::None_Uninitialized;
        X_ProxVC_Spec_VoiceLoc = VE_Loc::None_Uninitialized;
        X_ProxVC_Spec_EarsLoc = VE_Loc::None_Uninitialized;
        X_ProxVC_Player_Team = "";
        X_ProxVC_UnspawnedPlayer_Team = "";
        X_ProxVC_Spec_Team = "";
    }

    void RegisterText(const string &in settingName, const string &in value) {
        if (settingName == "X_ProxVC_Player_Team") {
            X_ProxVC_Player_Team = value;
        } else if (settingName == "X_ProxVC_UnspawnedPlayer_Team") {
            X_ProxVC_UnspawnedPlayer_Team = value;
        } else if (settingName == "X_ProxVC_Spec_Team") {
            X_ProxVC_Spec_Team = value;
        } else {
            dev_warn("Unknown server setting: " + settingName);
        }
    }

    void RegisterInteger(const string &in settingName, const string &in value) {
        int intValue;
        if (!Text::TryParseInt(value, intValue)) {
            dev_warn("Failed to parse integer from: " + value);
            return;
        }
        VE_Loc locVal = VE_Loc(intValue);
        if (settingName == "X_ProxVC_Player_VoiceLoc") {
            X_ProxVC_Player_VoiceLoc = locVal;
        } else if (settingName == "X_ProxVC_Player_EarsLoc") {
            X_ProxVC_Player_EarsLoc = locVal;
        } else if (settingName == "X_ProxVC_UnspawnedPlayer_VoiceLoc") {
            X_ProxVC_UnspawnedPlayer_VoiceLoc = locVal;
        } else if (settingName == "X_ProxVC_UnspawnedPlayer_EarsLoc") {
            X_ProxVC_UnspawnedPlayer_EarsLoc = locVal;
        } else if (settingName == "X_ProxVC_Spec_VoiceLoc") {
            X_ProxVC_Spec_VoiceLoc = locVal;
        } else if (settingName == "X_ProxVC_Spec_EarsLoc") {
            X_ProxVC_Spec_EarsLoc = locVal;
        } else {
            dev_warn("Unknown server setting: " + settingName);
        }
    }
}
