
funcdef void MsgHandler(Json::Value@);


class OutgoingMsg {
    string msgType;
    Json::Value@ msgPayload;
    OutgoingMsg(const string &in type, Json::Value@ payload) {
        this.msgType = type;
        @msgPayload = payload;
    }

    void WriteToSocket(BetterSocket@ socket) {
        socket.WriteMsg(msgType, msgPayload);
    }
}
