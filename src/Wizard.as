const string EM_DASH = "–";
const string WIZARD_TITLE = MenuTitle + " \\$z\\$i"+EM_DASH+" Wizard";

[Setting category="Wizard" name="Show Wizard"]
bool S_ShowWizard = true;

void Render() {
    if (!S_ShowWizard) return;
    if (UI::Begin(WIZARD_TITLE, S_ShowWizard, UI::WindowFlags::NoTitleBar | UI::WindowFlags::AlwaysAutoResize | UI::WindowFlags::NoCollapse)) {
        Wizard::DrawTabs();
    }
    UI::End();
}

UI::Texture@ _texAddServer = null;
UI::Texture@ _texInLobby = null;
UI::Texture@ _texInChannel = null;
UI::Texture@ _texLink = null;

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

namespace Wizard {
    uint progress = 0;
    int setTab = -1;
    int selectedTabFlags = UI::TabItemFlags::SetSelected;

    int GetTabFs(uint tabIx) {
        return tabIx == setTab ? selectedTabFlags : 0;
    }

    int _currTabIx = -1;
    void _BeginTabBar() {
        UI::BeginTabBar("WizardTabs");
        _currTabIx = 0;
    }

    // void _EndTabBar() {
    //     UI::EndTabBar();
    // }

    bool _BeginTabItem(const string &in name) {
        if (progress < _currTabIx) return false;
        auto r = UI::BeginTabItem(name, GetTabFs(_currTabIx));
        if (setTab == _currTabIx) setTab = -1;
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

    void DT_Mumble_Settings() {
        SubHeading("Mumble Settings");

        UI::AlignTextToFramePadding();
        UI::Text("Open Mumble settings.");

        UI::SeparatorText("Audio Output > Positional Audio");
        // Positional Audio: Enable: true, Headphones: ??, Min Dist: 1.0; Max Dist: 15.0; Min Vol: 0%.
        UI::AlignTextToFramePadding();
        UI::Text("Set these Positional Audio Settings");
        UI::Indent(6.);
        Col2Text("Enable", IconFromBool(true));
        Col2Text("Headphones", "??");
        Col2Text("Min Distance", "1.0", true);
        Col2Text("Max Distance", "15.0", true);
        Col2Text("Min Volume", "0.0", true);
        Col2Text("Bloom", "50 %", true, "50");
        UI::Unindent(6.);

        UI::SeparatorText("Plugins");
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
        UI::TextWrapped("You are automatically moved into the right channel depending on your current server/map.");
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
            Notify("Sorry link isn't added yet.");
            // OpenBrowserURL("https://openplanet.dev/files/97")
        }
        UI::AlignTextToFramePadding();
        UI::TextWrapped("It will automatically relay your position and map/server data.");
        UI::AlignTextToFramePadding();
        UI::TextWrapped("Just leave it running in the background.");
        UI::SeparatorText("");
        if (texLink !is null)
            UI_Image_Padded(texLink);
        UI::SeparatorText("");
        if (BigGreenButton("Next " + Icons::ArrowRight)) Next();
    }

    // About the plugin
    void DT_Plugin() {
        SubHeading("This Plugin");
        UI::SeparatorText("");
        UI::Text("Stuff about the plugin");
        UI::Text("Menubar");
        UI::SeparatorText("");
        S_Enabled = UI::Checkbox("Enable Proximity VC Now", S_Enabled);
        UI::SeparatorText("");
        if (BigGreenButton("Finish " + Icons::Check)) {
            S_ShowWizard = false;
        }
    }

    void Next() {
        progress++;
        setTab = progress;
    }
}


const string InfoTriangle = "\\$<\\$4f4" + Icons::ExclamationTriangle + "\\$>";


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
