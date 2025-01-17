UI::Font@ f_DS20 = UI::LoadFont("DroidSans.ttf", 20);
UI::Font@ f_DS26 = UI::LoadFont("DroidSans.ttf", 26);
UI::Font@ f_DS16B = UI::LoadFont("DroidSans-Bold.ttf", 16);
UI::Font@ f_MonoSpace = UI::LoadFont("DroidSansMono.ttf");

void SubHeading(const string &in msg) {
    UI::PushFont(f_DS20);
    UI::Text(msg);
    UI::PopFont();
}

float g_Col2TextC1Width = 80; //  * UI::GetScale()

void Col2Text(const string &in label, const string &in value, bool allowCopy = false, const string &in toCopy = "") {
    UI::PushID(label);
    auto pos = UI::GetCursorPos();
    UI::Text(label);
    UI::SetCursorPos(pos + vec2(g_Col2TextC1Width, 0));
    UI::PushFont(f_MonoSpace);
    UI::Text(value);
    UI::PopFont();
    if (allowCopy) {
        bool doCopy = false;
        if (UI::IsItemHovered()) {
            UI::SetMouseCursor(UI::MouseCursor::Hand);
            doCopy = UI::IsItemClicked(UI::MouseButton::Left) || doCopy;
        }
        UI::SameLine();
        doCopy = SmallButton(Icons::FilesO) || doCopy;
        if (doCopy) {
            string _copy = toCopy.Length == 0 ? value : toCopy;
            IO::SetClipboard(_copy);
            Notify("Copied: " + _copy);
        }
    }
    UI::PopID();
}


bool SmallButton(const string &in label, vec2 size = vec2()) {
    UI::PushStyleVar(UI::StyleVar::FramePadding, vec2(1, 0));
    bool r = UI::Button(label, size);
    UI::PopStyleVar();
    return r;
}

bool BigGreenButton(const string &in label, bool stretch = true) {
    vec2 size;
    if (stretch) size.x = UI::GetContentRegionAvail().x;
    UI::PushFont(f_DS20);
    UI::PushStyleVar(UI::StyleVar::FramePadding, vec2(8));
    bool r = UI::ButtonColored(label, .34, .6, .6, size);
    UI::PopStyleVar();
    UI::PopFont();
    return r;
}

void UI_Image_Padded(UI::Texture@ tex, float scale = 1.0, vec2 pad = vec2(12)) {
    if (tex is null) return;
    auto pos = UI::GetCursorPos();
    auto size = tex.GetSize() * scale;
    auto paddedSize = size + pad * 2.;
    UI::Dummy(paddedSize);
    auto endPos = UI::GetCursorPos();

    auto dl = UI::GetWindowDrawList();
    auto wPos = UI::GetWindowPos();
    dl.AddRectFilled(vec4(wPos + pos, paddedSize), vec4(.415, .415, .415, .8), 8);
    dl.AddRectFilled(vec4(wPos + pos + vec2(1), paddedSize - vec2(2)), vec4(0.18f, 0.18f, 0.18f, 1), 7);

    UI::SetCursorPos(pos + pad);
    UI::Image(tex, size);
    UI::SetCursorPos(endPos);
}

void UI_PaddedAlert_Pill(const string &in msg, const vec4 &in bgColor) {
    auto pos = UI::GetCursorPos();
    auto winPos = UI::GetWindowPos();
    auto avail = UI::GetContentRegionAvail();
    UI::PushFont(f_DS16B);
    float textW = avail.x * 0.9;
    float textIndent = avail.x * 0.05;
    float textTopPad = 10;
    vec2 textBox = Draw::MeasureString(msg, f_DS16B, 16.0, textW);
    auto size = vec2(avail.x, textBox.y + textTopPad * 2);

    UI::Dummy(size);
    auto afterPos = UI::GetCursorPos();

    UI::SetCursorPos(pos);
    auto dl = UI::GetWindowDrawList();
    dl.AddRectFilled(vec4(winPos + pos, size), bgColor, 4);
    UI::SetCursorPos(pos + vec2(textIndent, textTopPad));

    if (UI::BeginChild("pillmsg##"+msg, vec2(textW, textBox.y))) {
        UI::TextWrapped(msg);
    }
    UI::EndChild();

    UI::PopFont();

    UI::SetCursorPos(pos + vec2(0, size.y));
}






void Notify(const string &in msg, uint timeout = 5000) {
	UI::ShowNotification(Meta::ExecutingPlugin().Name, msg, timeout);
	trace("Notified: " + msg);
}