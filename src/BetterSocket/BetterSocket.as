// From Dips++ with unlimited license.
// Modified to fit rust message-io library
// updated 2024-05-19 for new openplanet socket

class BetterSocket {
    Net::Socket@ s;
    bool IsConnecting = false;
    string addr;
    uint16 port;

    BetterSocket(const string &in addr, uint16 port) {
        this.addr = addr;
        this.port = port;
    }

    bool ReconnectToServer() {
        if (s !is null) {
            dev_trace('closing');
            s.Close();
            @s = null;
        }
        Connect();
        return IsUnclosed;
    }

    void StartConnect() {
        IsConnecting = true;
        startnew(CoroutineFunc(Connect));
    }

    void Connect() {
        IsConnecting = true;
        if (s !is null) {
            warn("already have a socket");
            IsConnecting = false;
            return;
        }
        Net::Socket@ socket = Net::Socket();
        if (!socket.Connect(addr, port)) {
            warn("Failed to connect to " + addr + ":" + port);
        } else {
            @s = socket;
            auto timeout = Time::Now + 8000;
            while (s !is null && !s.IsReady() && Time::Now < timeout) yield();
            if (s is null) return;
            if (!s.IsReady()) {
                warn("Failed to connect to " + addr + ":" + port + " in time");
                startnew(CoroutineFunc(StartConnect));
            }
        }
        IsConnecting = false;
    }

    void Shutdown() {
        if (s !is null) {
            trace('Shutdown:closing');
            s.Close();
            @s = null;
        }
    }

    bool get_IsClosed() {
        return s is null || s.IsHungUp();
    }

    bool get_IsUnclosed() {
        return s !is null && !s.IsHungUp();
    }

    protected bool hasWaitingAvailable = false;

    bool get_ServerDisconnected() {
        if (s is null) {
            return true;
        }
        if (s.IsHungUp()) return true;
        return false;
    }

    bool get_HasNewDataToRead() {
        if (hasWaitingAvailable) {
            hasWaitingAvailable = false;
            return true;
        }
        return s !is null && s.Available() > 0;
    }

    int get_Available() {
        return s !is null ? s.Available() : 0;
    }

    // true if last message was received more than 1 minute ago
    bool get_LastMsgRecievedLongAgo() {
        return Time::Now - lastMessageRecvTime > 40000;
    }

    protected RawMessage tmpBuf;
    uint lastMessageRecvTime = 0;

    // parse msg immediately
    RawMessage@ ReadMsg(uint timeout = 40000) {
        // read msg length
        // read msg data
        uint startReadTime = Time::Now;
        while (Available < 4 && !IsClosed && !ServerDisconnected && (timeout <= 0 || Time::Now - startReadTime < timeout)) yield();
        if (timeout > 0 && Time::Now - startReadTime >= timeout) {
            yield();
            if (Available < 4 && !IsClosed && !ServerDisconnected) {
                warn("ReadMsg timed out while waiting for length");
                warn("Disconnecting socket");
                Shutdown();
                return null;
            }
        }
        if (IsClosed || ServerDisconnected) {
            return null;
        }

        // wait for length
        uint len = VarInt::DecodeUint(s);
        // len = BigEndianToLittle(len);
        if (len > ONE_MEGABYTE) {
            error("Message too large: " + len + " bytes, max: 1 MB");
            warn("Disconnecting socket");
            Shutdown();
            return null;
        }

        startReadTime = Time::Now;
        while (Available < int(len)) {
            if (timeout > 0 && Time::Now - startReadTime >= timeout) {
                yield();
                if (Available < int(len)) {
                    warn("ReadMsg timed out while reading msg; Available: " + Available + '; len: ' + len);
                    warn("Disconnecting socket");
                    Shutdown();
                    return null;
                }
            }
            if (IsClosed || ServerDisconnected) {
                return null;
            }
            yield();
        }

        tmpBuf.ReadFromSocket(s, len);
        lastMessageRecvTime = Time::Now;
        return tmpBuf;
    }

    void WriteMsg(const string &in msgType, Json::Value@ msgDataJ) {
        auto @j = Json::Object();
        j[msgType] = msgDataJ;
        auto msgData = Json::Write(j);

        if (s is null) {
            if (msgType != "Ping")
                dev_trace("WriteMsg: dropping msg b/c socket closed/disconnected");
            return;
        }

        MemoryBuffer encodedLen = VarInt::EncodeUint(msgData.Length);
        encodedLen.Seek(0);
        auto encodedLenStr = encodedLen.ReadToHex(encodedLen.GetSize());
        warn("encodedLenStr: " + encodedLenStr + "; len: " + msgData.Length + "; msgType: " + msgType + "; msgData: " + msgData);


        bool success = true;
        success = VarInt::EncodeUint(s, msgData.Length) && success;
        success = s.WriteRaw(msgData) && success;
        if (!success) {
            warn("failure to write message? " + msgType + " / " + msgData.Length + " bytes");
            // this.Shutdown();
        }
    }
}

uint BigEndianToLittle(uint bigEndian) {
    return ((bigEndian & 0xFF) << 24) | ((bigEndian & 0xFF00) << 8) | ((bigEndian & 0xFF0000) >> 8) | ((bigEndian & 0xFF000000) >> 24);
}

const uint32 ONE_MEGABYTE = 1024 * 1024;

class RawMessage {
    string msgType;
    string msgData;
    Json::Value@ msgJson;
    uint readStrLen;

    RawMessage() {}

    void ReadFromSocket(Net::Socket@ s, uint len) {
        try {
            msgData = s.ReadRaw(len);
        } catch {
            error("Failed to read message data with len: " + len);
            return;
        }
        try {
            @msgJson = Json::Parse(msgData);
        } catch {
            error("Failed to parse message json: " + msgData);
            return;
        }
        if (msgJson.GetType() != Json::Type::Object) {
            error("Message json is not an object: " + msgData);
            return;
        }
        auto keys = msgJson.GetKeys();
        if (keys.Length != 1) {
            error("Message json has more than 1 key: " + msgData);
            return;
        }
        msgType = keys[0];
        @msgJson = msgJson[msgType];
        trace("Received message: " + msgType + " / " + msgData);
    }

    bool get_IsPing() {
        return msgType == "Ping";
    }
}
