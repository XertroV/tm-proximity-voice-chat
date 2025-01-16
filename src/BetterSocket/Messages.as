enum MessageRequestTypes {
    Positions = 1,
    PlayerDetails = 2,
    ServerDetails = 3,
    LeftServer = 4,
    Ping = 5,

}

enum MessageResponseTypes {
    ConnectedStatus = 1,
    Ping = 2,
}

OutgoingMsg@ WrapMsgJson(Json::Value@ inner, const string &in type) {
    return OutgoingMsg(type, inner);
}

// OutgoingMsg@ AuthenticateMsg(const string &in token) {
//     auto @j = Json::Object();
//     j["token"] = token;
//     return WrapMsgJson(j, MessageRequestTypes::Authenticate);
// }

// OutgoingMsg@ ResumeSessionMsg(const string &in session_token) {
//     auto @j = Json::Object();
//     j["session_token"] = session_token;
//     return WrapMsgJson(j, MessageRequestTypes::ResumeSession);
// }

// OutgoingMsg@ ReportSessionCL() {
//     auto @j = Json::Object();
//     j["cl"] = CL::GetInfo();
//     return WrapMsgJson(j, MessageRequestTypes::SessionCL);
// }

// OutgoingMsg@ ReportContextMsg(uint64 sf, uint64 mi, nat2 bi, bool relevant) {
//     auto @j = Json::Object();
//     return WrapMsgJson(j, MessageRequestTypes::ReportContext);
// }

// OutgoingMsg@ ReportGCNodMsg(const string &in gcBase64) {
//     auto @j = Json::Object();
//     return WrapMsgJson(j, MessageRequestTypes::ReportGCNodMsg);
// }

OutgoingMsg@ PingMsg() {
    return OutgoingMsg("Ping", Json::Array());
}

OutgoingMsg@ GetPlayerDetailsMsg() {
    auto @j = Json::Array();
    j.Add(LocalPlayerInfo_Name);
    j.Add(LocalPlayerInfo_Login);
    return OutgoingMsg("PlayerDetails", j);
}

OutgoingMsg@ GetServerDetailsMsg() {
    auto @j = Json::Array();
    j.Add(GetServerLogin());
    j.Add(GetServerTeamIfTeams());
    return OutgoingMsg("ServerDetails", j);
}
