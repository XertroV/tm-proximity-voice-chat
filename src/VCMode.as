/*
There are a few options for player/camera positions.
Assuming the player is spawned and not using cam7, we use both the real player position and the camera position.

If the player is using cam7, then by default:
- Voice comes from player position
- Ears are at camera position

Spectators & unspawned players are by default are at vec3(-3200)
- ?? Choice of ears location
-

Okay, I think probably best for user choice for location of voice and ears, unless server settings:
S_ProxVC_Player_VoiceLoc: VE_Loc
S_ProxVC_Player_EarsLoc: VE_Loc
S_ProxVC_UnspawnedPlayer_VoiceLoc: VE_Loc
S_ProxVC_UnspawnedPlayer_EarsLoc: VE_Loc
S_ProxVC_Spec_VoiceLoc: VE_Loc
S_ProxVC_Spec_EarsLoc: VE_Loc
S_ProxVC_Spec_Team: string -> Spectators are on a team
    default: no change


*/

enum VE_Loc {
    None_Uninitialized = 0,
    Player = 1,
    Camera = 2,
    FarAwayZone1 = 11,
    FarAwayZone2 = 12,
    FarAwayZone3 = 13,
    NearZero = 20,
    Zero_DisablePositionalAudio = 21,
}


VE_Loc UI_VE_Combo(const string &in label, VE_Loc loc) {
    if (UI::BeginCombo(label, tostring(loc))) {
        if (UI::Selectable("Player", loc == VE_Loc::Player)) loc = VE_Loc::Player;
        if (UI::Selectable("Camera", loc == VE_Loc::Camera)) loc = VE_Loc::Camera;
        if (UI::Selectable("Far Away Zone 1", loc == VE_Loc::FarAwayZone1)) loc = VE_Loc::FarAwayZone1;
        if (UI::Selectable("Far Away Zone 2", loc == VE_Loc::FarAwayZone2)) loc = VE_Loc::FarAwayZone2;
        if (UI::Selectable("Far Away Zone 3", loc == VE_Loc::FarAwayZone3)) loc = VE_Loc::FarAwayZone3;
        if (UI::Selectable("Near Zero", loc == VE_Loc::NearZero)) loc = VE_Loc::NearZero;
        if (UI::Selectable("Zero (Disable Positional Audio)", loc == VE_Loc::Zero_DisablePositionalAudio)) loc = VE_Loc::Zero_DisablePositionalAudio;
        UI::EndCombo();
    }
    return loc;
}

VE_Loc UI_VE_MenuSelectable(const string &in label, VE_Loc loc) {
    VE_Loc newLoc = loc;
    if (UI::BeginMenu(label + (int(loc) > 0 ? " \\$999(" + tostring(loc) + ')' : ""))) {
        if (UI::MenuItem("Player", "", loc == VE_Loc::Player)) newLoc = VE_Loc::Player;
        if (UI::MenuItem("Camera", "", loc == VE_Loc::Camera)) newLoc = VE_Loc::Camera;
        if (UI::MenuItem("Far Away Zone 1", "", loc == VE_Loc::FarAwayZone1)) newLoc = VE_Loc::FarAwayZone1;
        if (UI::MenuItem("Far Away Zone 2", "", loc == VE_Loc::FarAwayZone2)) newLoc = VE_Loc::FarAwayZone2;
        if (UI::MenuItem("Far Away Zone 3", "", loc == VE_Loc::FarAwayZone3)) newLoc = VE_Loc::FarAwayZone3;
        if (UI::MenuItem("Near Zero", "", loc == VE_Loc::NearZero)) newLoc = VE_Loc::NearZero;
        if (UI::MenuItem("Zero (Disable Positional Audio)", "", loc == VE_Loc::Zero_DisablePositionalAudio)) newLoc = VE_Loc::Zero_DisablePositionalAudio;
        UI::EndMenu();
    }
    return newLoc;
}


VE_Loc VE_Loc_OrDefault(VE_Loc loc, VE_Loc def) {
    if (loc == VE_Loc::None_Uninitialized) return def;
    return loc;
}


[Setting category="Voice Location" name="Voice When Spawned (incl. Cam 7)"]
VE_Loc S_Spawned_VoiceLoc = VE_Loc::Player;

[Setting category="Voice Location" name="Voice When Unspawned"]
VE_Loc S_Unspawned_VoiceLoc = VE_Loc::Camera;

[Setting category="Voice Location" name="Voice When Spectating"]
VE_Loc S_Spec_VoiceLoc = VE_Loc::Camera;


[Setting category="Ears Location" name="Ears When Spawned (incl. Cam 7)"]
VE_Loc S_Spawned_EarsLoc = VE_Loc::Camera;

[Setting category="Ears Location" name="Ears When Unspawned"]
VE_Loc S_Unspawned_EarsLoc = VE_Loc::Camera;

[Setting category="Ears Location" name="Ears When Spectating"]
VE_Loc S_Spec_EarsLoc = VE_Loc::Camera;


enum PlayerStatus {
    Spawned,
    Unspawned_Spec,
    Unspawned_Player,
    None_NoMap,
}
