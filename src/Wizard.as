const string EM_DASH = "–";
const string WIZARD_TITLE = MenuTitle + " \\$z\\$i"+EM_DASH+" Wizard";

[Setting category="Wizard" name="Hide the Wizard" description="Hides the wizard till later. Only used when Show Wizard is true, meaning the wizard hasn't been done yet."]
bool WizardLater = false;

[Setting category="Wizard" name="Show Wizard" description="Show the setup wizard for setting up the plugin. This should only be false after the wizard has been completed."]
bool S_ShowWizard = true;

void Render() {
    if (!S_ShowWizard) return;
    if (WizardLater) return;
    if (UI::Begin(WIZARD_TITLE, S_ShowWizard, UI::WindowFlags::NoTitleBar | UI::WindowFlags::AlwaysAutoResize | UI::WindowFlags::NoCollapse)) {
        Wizard::DrawTabs();
    }
    UI::End();
}

UI::Texture@ _texAddServer = null;
UI::Texture@ _texInLobby = null;
UI::Texture@ _texInChannel = null;
UI::Texture@ _texLink = null;
UI::Texture@ _texMumblePluginSettings = null;
UI::Texture@ _texMumblePosAudioSettings = null;
UI::Texture@ _texPluginMenu = null;

UI::Texture@ get_texAddServer() {
    if (_texAddServer is null) {
        @_texAddServer = UI::LoadTexture("img/AddServer.png");
    }
    return _texAddServer;
}
UI::Texture@ get_texInLobby() {
    if (_texInLobby is null) {
        @_texInLobby = UI::LoadTexture("img/InMainLobby.png");
    }
    return _texInLobby;
}
UI::Texture@ get_texInChannel() {
    if (_texInChannel is null) {
        @_texInChannel = UI::LoadTexture("img/InServerChannel.png");
    }
    return _texInChannel;
}
UI::Texture@ get_texLink() {
    if (_texLink is null) {
        @_texLink = UI::LoadTexture("img/MumbleLink.png");
    }
    return _texLink;
}
UI::Texture@ get_texMumblePluginSettings() {
    if (_texMumblePluginSettings is null) {
        @_texMumblePluginSettings = UI::LoadTexture("img/MumblePluginSettings.png");
    }
    return _texMumblePluginSettings;
}
UI::Texture@ get_texMumblePosAudioSettings() {
    if (_texMumblePosAudioSettings is null) {
        @_texMumblePosAudioSettings = UI::LoadTexture("img/MumblePosAudioSettings.png");
    }
    return _texMumblePosAudioSettings;
}
UI::Texture@ get_texPluginMenu() {
    if (_texPluginMenu is null) {
        @_texPluginMenu = UI::LoadTexture("img/MainMenuMenu.png");
    }
    return _texPluginMenu;
}


funcdef UI::Texture@ TexGetter();


namespace Wizard {
    uint progress = 0;
    int setTab = -1;
    int selectedTabFlags = UI::TabItemFlags::SetSelected;
    int openTab = -1;

    int GetTabFs(uint tabIx) {
        return tabIx == setTab ? selectedTabFlags : 0;
    }

    int _currTabIx = -1;
    void _BeginTabBar() {
        // UI::Text("openTab: " + openTab + ", progress: " + progress + ", setTab: " + setTab + ", _currTabIx: " + _currTabIx);
        Heading("Proximity VC Setup Wizard");
        UI::BeginTabBar("WizardTabs");
        _currTabIx = 0;
        openTab = -1;
    }

    // void _EndTabBar() {
    //     UI::EndTabBar();
    // }

    bool _BeginTabItem(const string &in name) {
        if (progress < _currTabIx) return false;
        auto r = UI::BeginTabItem(name, GetTabFs(_currTabIx));
        if (setTab == _currTabIx) setTab = -1;
        if (r) openTab = _currTabIx;
        _currTabIx++;
        return r;
    }

    // void _EndTabItem() {
    //     UI::EndTabItem();
    // }

    void DrawTabs() {
        uint p = progress;

        _BeginTabBar();
        if (_BeginTabItem("Settings")) {
            DT_Mumble_Settings();
            UI::EndTabItem();
        }
        if (_BeginTabItem("Mumble")) {
            DT_Mumble_1();
            UI::EndTabItem();
        }
        if (_BeginTabItem("Channels")) {
            DT_Mumble_2();
            UI::EndTabItem();
        }
        if (_BeginTabItem("Link")) {
            DT_Link();
            UI::EndTabItem();
        }
        if (_BeginTabItem("Plugin")) {
            DT_Plugin();
            UI::EndTabItem();
        }
        UI::EndTabBar();
    }

    const string MUMBLE_SETTINGS_COL_COG = "\\$f80 " + Icons::Cogs;

    void DT_Mumble_Settings() {
        SubHeading("Mumble Settings");

        UI::SeparatorText("");
        UI::Text(WarnTriangle + " If you don't have Mumble installed, do that now.");
        // UI::SameLine();
        if (UI::ButtonColored(Icons::Download + " Download Mumble", .56, .6, .6)) {
            OpenBrowserURL("https://www.mumble.info/downloads/");
        }
        UI::SeparatorText("");

        UI::AlignTextToFramePadding();
        UI::Text("Open Mumble settings.");

        SeparatorText_Bold(MUMBLE_SETTINGS_COL_COG + " Settings > Audio Output > Positional Audio");
        UI::AlignTextToFramePadding(); UI::Text("(( " + Icons::HandPointerO + " ))"); UI::SameLine();
        UI_Padded_PillSm_Info("  " + Icons::PictureO + " Positional Audio Settings");
        AddImageTooltip(get_texMumblePosAudioSettings);

        // Positional Audio: Enable: true, Headphones: ??, Min Dist: 1.0; Max Dist: 15.0; Min Vol: 0%.
        UI::AlignTextToFramePadding();
        UI::Text("Set these Positional Audio Settings");
        UI::Indent(6.);
        Col2Text("Enable", IconFromBool(true));
        Col2Text("Headphones", "?? (are you wearing headphones?)");
        Col2Text("Min Distance", "1.0", true);
        Col2Text("Max Distance", "15.0", true);
        Col2Text("Min Volume", "0.0", true);
        Col2Text("Bloom", "50 %", true, "50");
        UI::Unindent(6.);


        SeparatorText_Bold(MUMBLE_SETTINGS_COL_COG + " Settings > Plugins");
        UI::AlignTextToFramePadding(); UI::Text("(( " + Icons::HandPointerO + " ))"); UI::SameLine();
        UI_Padded_PillSm_Info("  " + Icons::PictureO + " Plugin Settings");
        AddImageTooltip(get_texMumblePluginSettings);

        UI::AlignTextToFramePadding();
        UI::Text("Enable: \"\\$<\\$af4\\$iLink to Game and Transmit Position\\$>\" near the top.");
        UI::AlignTextToFramePadding();
        UI::TextWrapped("Under \\$<\\$af4\\$iPlugins\\$> subsection, find the \\$<\\$af4\\$iLink\\$> plugin and check the \\$<\\$af4\\$iEnable\\$> checkbox.");


        UI::SeparatorText("");
        UI::AlignTextToFramePadding();
        UI::Text(InfoTriangle + " Click OK now to save settings.");
        UI::Text("Checklist:");
        UI::Text("\t\t\t" + Icons::CheckSquareO + " Enabled Positional Audio");
        UI::Text("\t\t\t" + Icons::CheckSquareO + " Enabled Link Plugin in Mumble Settings");
        UI::SeparatorText("");
        if (BigGreenButton("Next " + Icons::ArrowRight)) Next();
        if (BigRedButton(Icons::Times + " Complete this later")) WizardLater = true;
    }

    void AddImageTooltip(TexGetter@ tex) {
        if (UI::IsItemHovered()) {
            UI::BeginTooltip();
            if (tex() !is null) {
                UI::Image(tex());
            }
            UI::EndTooltip();
        }
    }

    // About setting up mumble
    void DT_Mumble_1() {
        SubHeading("Connect to the Mumble Server");
        UI::SeparatorText("");
        UI::AlignTextToFramePadding();
        UI::Text("In Mumble:");
        UI::Text("\t\t\\$<\\$iServer -> Connect -> Add New...\\$>");
        UI::AlignTextToFramePadding();
        UI::Text("Fill in the following details:");
        UI::Indent(6.);
            Col2Text("Address", "proximity.xk.io", true);
            Col2Text("Port", "\\$99964738 (Default)", true, "64738");
            Col2Text("Username", LocalPlayerInfo_Name, true);
            Col2Text("Label", "TM Proximity Chat", true);

            UI::SeparatorText("\\$i\\$7f7\\$sSave and connect now.");

            Col2Text("Password", "iloveopenplanet", true);
        UI::Unindent(6.);
        UI::SeparatorText("");
        // if (texAddServer !is null)
        UI_Image_Padded(texAddServer);
        UI::SeparatorText("");
        if (BigGreenButton("I'm Connected " + Icons::ArrowRight)) Next();
    }

    // About channels & how they work
    void DT_Mumble_2() {
        SubHeading("How Channels Work");
        UI::SeparatorText("");
        UI::TextWrapped("You are \\$<\\$iautomatically\\$> moved into the right channel depending on your current server/map.");
        UI::Text("\\$i\\$999Contact XertroV for bug reports or custom behavior requests.");
        UI::TextWrapped(WarnTriangle + " \\$f80You cannot join channels for other maps / servers.");
        UI::TextWrapped(InfoTriangle + " Optional Setting: manual team name.");
        UI::TextWrapped(InfoTriangle + " Optional Setting: always join map VC instead of server.");
        UI::SeparatorText("\\$iMumble when not in a map");
        UI_Image_Padded(texInLobby);
        UI::SeparatorText("\\$iMumble when in a map / server");
        UI_Image_Padded(texInChannel);
        UI::AlignTextToFramePadding();
        UI::TextWrapped("\t\t\\$i" + InfoTriangle + " Map UIDs and Server Logins are hashed for privacy.");
        UI::SeparatorText("");
        if (BigGreenButton("Next " + Icons::ArrowRight)) Next();
    }

    // About the link app
    void DT_Link() {
        SubHeading("Link App");
        UI::SeparatorText("");
        UI_PaddedAlert_Pill(Icons::ExclamationTriangle + " The TM to Mumble Link app is an executable and is not audited as part of the plugin review process.", UI::HSV(.9, .6, .6));
        UI::SeparatorText("");
        UI::AlignTextToFramePadding();
        UI::TextWrapped("Download and run the link app after starting Mumble and joining the server.");
        UI::Dummy(vec2(20, 0));
        UI::SameLine();
        if (UI::ButtonColored(Icons::Download + " Open Link App Download Page", .42, .6, .4)) {
            OpenBrowserURL("https://openplanet.dev/file/122");
        }
        UI::SameLine();
        // does not work w/ align to frame padding; also is rather dark blue.
        // UI::TextLinkOpenURL(Icons::Git + " Source Code", "https://github.com/xertrov/tm-mumble-bridge");
        if (UI::ButtonColored(Icons::Git + " Source Code", .64, .3, .5)) {
            OpenBrowserURL("https://github.com/xertrov/tm-mumble-bridge");
        }
        UI::AlignTextToFramePadding();
        UI::TextWrapped("It will automatically relay your position and map/server data.");
        UI::AlignTextToFramePadding();
        UI::TextWrapped("Just leave it running in the background. If mumble needs restarting, then restart the link app, too.");
        UI::SeparatorText("");
        if (texLink !is null)
            UI_Image_Padded(texLink);
        UI_PaddedAlert_Pill(Icons::QuestionCircleO + " An error message about `cannot find the file specified. (os error 2)` means that it could not connect to Mumble.", vec4(.0, .35, .7, .7));
        UI::SeparatorText("");
        if (BigGreenButton("TM to Mumble Link is Running & Connected " + Icons::ArrowRight)) Next();
    }

    // About the plugin
    void DT_Plugin() {
        SubHeading("This Plugin");
        UI::SeparatorText("");
        UI::TextWrapped("When enabled, the plugin will try to connect to the Link app automatically.");
        UI::TextWrapped("You can see the current status and manually disconnect/reconnect via the Menu (only shows when plugin is enabled and on).");
        UI::SeparatorText("");
        UI_Image_Padded(texPluginMenu);
        UI::SeparatorText("");
        // UI::Text("Menubar");
        S_Enabled = UI::Checkbox("\\$<\\$8bf" + Icons::QuestionCircleO + "\\$> Enable Proximity VC Now", S_Enabled);
        if (!S_Enabled) {
            UI_Padded_PillSm_Info("Enable it later via Plugins menu.", true);
        }

        UI::SeparatorText("");
        if (BigGreenButton("Finish " + Icons::Check)) {
            S_ShowWizard = false;
            OnEnabledUpdated();
        }
    }

    void Next() {
        if (openTab == progress) {
            progress++;
            setTab = progress;
        } else {
            setTab = _currTabIx;
        }
    }
}


const string InfoTriangle = "\\$<\\$4f4" + Icons::ExclamationTriangle + "\\$>";
const string WarnTriangle = "\\$<\\$f80" + Icons::ExclamationTriangle + "\\$>";


/*
wiz:

- Connect to Mumble server
    - domain
    - port
    - password
    - username
- How channels work
    - Automoved when plugin updates
    - channels based on:
      - server + team
      - server (all)
      - map uid
    - settings to manually specify team or always use map uid
    - server login / map uid is obfuscated, but team name is not
- Link
    - Need to download and run app after starting mumble.
    - Will automatically relay position and map/server data.
    - Just leave it running in the background.
- Plugin
    - Will automatically try to connect to the link app.
    - Settings:
        - manual team name
        - always use map VC
*/
