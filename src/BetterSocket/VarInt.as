namespace VarInt {
    MemoryBuffer EncodeUint(uint value) {
        MemoryBuffer buf;
        while (value >= 0x80) {
            buf.Write(uint8(value | 0x80));
            value >>= 7;
        }
        buf.Write(uint8(value));
        return buf;
    }

    bool EncodeUint(Net::Socket@ s, uint value) {
        uint8 b;
        while (value >= 0x80) {
            b = uint8(value) | 0x80;
            if (!s.Write(b)) return false;
            trace("wrote: " + b);
            value >>= 7;
        }
        return s.Write(uint8(value));
    }

    const uint8 DROP_MSB = 0b01111111;

    uint DecodeUint(MemoryBuffer@ buf) {
        uint result = 0;
        uint shift = 0;
        uint8 b;
        do {
            b = buf.ReadUInt8();
            result |= (b & 0x7F) << shift;
            shift += 7;
        } while ((b & 0x80) != 0);
        return result;
    }

    uint DecodeUint(Net::Socket@ s) {
        uint result = 0;
        uint shift = 0;
        uint8 b;
        do {
            b = s.ReadUint8();
            result |= (b & 0x7F) << shift;
            shift += 7;
        } while ((b & 0x80) != 0);
        return result;
    }
}
