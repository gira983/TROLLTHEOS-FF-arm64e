#ifndef GameLogic_h
#define GameLogic_h

#import "MemoryUtils.h"
#import "UnityMath.h"

// ─────────────────────────────────────────────────────────────────────────────
// FRYZZ ESP — GameLogic.h
// All offsets verified against complete dump (1,833,127 lines)
// ─────────────────────────────────────────────────────────────────────────────

// ── PLAYER FIELD OFFSETS ─────────────────────────────────────────────────────
// Confirmed via IL2CPP dump, class Player (TypeDefIndex ~5927 area)

#define OFF_CAMERA_TRANSFORM    0x318   // MainCameraTransform (Transform)
#define OFF_PLAYERID            0x338   // KFMGKCJMCAM → PlayerID struct (IHAAMHPPLMG)
#define OFF_ISCADET             0x330   // IsCadet (bool)
#define OFF_ISLOCALPLAYER       0x350   // KCADLABCONA (bool)
#define OFF_TEAMINDEX           0x360   // k__BackingField (int) — team number
#define OFF_ISCLIENTBOT         0x3D0   // IsClientBot (bool) — skip bots if needed
#define OFF_NICKNAME            0x3C0   // OIAJCBLDHKP (string) — display name
#define OFF_ORIGINALNICK        0x3C8   // OriginalNickName (string)
#define OFF_ISINVEHICLE         0x428   // m_GetInVehicle (bool)
#define OFF_SPEED               0x488   // Speed (float)
#define OFF_AIMSIGHTING         0x528   // ActiveUISightingWeapon (bool) — is aiming down sights
#define OFF_AIM_ROTATION        0x53C   // k__BackingField = m_AimRotation (Quaternion, camera)
#define OFF_ISKNOCKEDDOWN       0xA0    // IsFrozenKnockDown (bool) — fast knocked check
#define OFF_ISSKILLACTIVE       0x9D0   // IsSkillActive (bool)
#define OFF_ISVISIBLE_FLAGS     0x9A8   // KAJNNEADLLJ (uint) — visibility bitmask
#define OFF_FIRING              0x750   // <LPEIEILIKGC>k__BackingField (bool) — is firing
#define OFF_ISKNOCKDOWNBLEED    0x1110  // IsKnockedDownBleed (bool) — confirmed bleed state
#define OFF_CURRENT_AIM         0x172C  // m_CurrentAimRotation (Quaternion, bullet direction)
#define OFF_STARTGLIDETIME      0x15F0  // StartGlideTime (float) — parachute/glide

// ISVISIBLE flag bits (from AvatarManager class consts)
#define ISVISIBLE_PLAYER        1u      // player model is rendering

// ── BONE OFFSETS ─────────────────────────────────────────────────────────────
#define OFF_HEAD_NODE           0x5B8   // OLCJOGDHJJJ
#define OFF_HIP_NODE            0x5C0   // OLJBCONDGLO
#define OFF_LEFTANKLE           0x5F0   // BMGCHFGEDDA
#define OFF_RIGHTANKLE          0x5F8   // AGHJLIMNPJA
#define OFF_RIGHTTOE            0x608   // CKABHDJDMAP
#define OFF_LEFTARM             0x620   // LIBEIIIAGIK
#define OFF_RIGHTARM            0x628   // HDEPJIBNIIK
#define OFF_RIGHTHAND           0x630   // NJDDAPKPILB
#define OFF_LEFTHAND            0x638   // JHIBMHEMJOL
#define OFF_RIGHTFOREARM        0x640   // JBACCHNMGNJ
#define OFF_LEFTFOREARM         0x648   // FGECMMJKFNC
// Extra body parts for precise targeting
#define OFF_NECK_NODE           0x650   // HECFNHJKOMN — neck
#define OFF_CHEST_NODE          0x658   // COLEAPKGFLK — chest/spine

// ── MATCH / GAMEFACADE CHAIN ──────────────────────────────────────────────────
// GameFacade TypeInfo offset from module base
#define OFF_GAMEFACADE_TI       0xA4D2968   // verified in both dumps
// GameFacade statics block (from TypeInfo)
#define OFF_GAMEFACADE_STATICS  0xB8
// CurrentMatchGame offset inside statics (NEW — use +0x8 directly)
#define OFF_CURRENT_MATCHGAME   0x8         // statics+0x8 = CurrentMatchGame
// MatchGame fields
#define OFF_MG_MATCH            0x90        // m_Match (NFJPHMKKEBF)
#define OFF_MG_CAMERA_MGR       0xD8        // m_CameraControllerManager
// Match (NFJPHMKKEBF) fields
#define OFF_MATCH_LOCALPLAYER   0xB0        // FJPEHEGICBO (Player)
#define OFF_MATCH_PLAYERDICT    0x118       // HJAKBBKDAPK Dict<IHAAMHPPLMG,Player>
// CameraControllerManager
#define OFF_CAM_MGR_MAIN        0x18        // → CameraMain
// CameraMain
#define OFF_CAM_VIEWMATRIX_PTR  0x10        // → v1 → matrix
#define OFF_CAM_MATRIX_OFF      0xD8        // matrix[0] = v1 + 0xD8
// BodyPart → Transform
#define OFF_BODYPART_TRANSNODE  0x10        // getTransNode

// ── HP DATA POOL ─────────────────────────────────────────────────────────────
#define OFF_HP_POOL             0x68        // IPRIDataPool ptr in Player
#define OFF_HP_POOL_ARR         0x8         // array ptr inside pool
#define OFF_HP_POOL_ITEM_STRIDE 0x8         // stride per varID entry
#define OFF_HP_POOL_ITEM_OFF    0x28        // base offset within stride block
#define OFF_HP_POOL_VALUE       0x10        // actual int value within item
// varID 0 = CurHP, 1 = MaxHP, 2 = KnockState (0=alive,1=knocked)

// ── PLAYER ID STRUCT (IHAAMHPPLMG) ───────────────────────────────────────────
// m_TeamID @ +0x19 (uint8_t/uint16_t)
#define OFF_PLAYERID_TEAMID     0x19        // team ID within PlayerID struct

// ─────────────────────────────────────────────────────────────────────────────
// STRUCTS
// ─────────────────────────────────────────────────────────────────────────────

struct COW_GamePlay_PlayerID_o {
    uint64_t padding;
    uint8_t  pad2[8];
    uint8_t  m_TeamID;   // +0x19 relative to struct start in memory
    uint8_t  _pad[3];
    uint32_t m_PlayerType; // +0x1C
};

// ─────────────────────────────────────────────────────────────────────────────
// FUNCTION DECLARATIONS
// ─────────────────────────────────────────────────────────────────────────────

// ── Chain accessors ──
uint64_t getMatchGame(uint64_t moduleBase);
uint64_t getMatch(uint64_t matchGame);
uint64_t getLocalPlayer(uint64_t match);
uint64_t CameraMain(uint64_t matchGame);
float*   GetViewMatrix(uint64_t cameraMain);
uint64_t getTransNode(uint64_t bodyPart);

// ── Player state ──
int  get_CurHP(uint64_t player);
int  get_MaxHP(uint64_t player);
int  GetDataUInt16(uint64_t player, int varID);
bool isLocalTeamMate(uint64_t localPlayer, uint64_t player);
bool isPlayerVisible(uint64_t player);   // checks KAJNNEADLLJ & ISVISIBLE_PLAYER
bool isPlayerBot(uint64_t player);       // checks IsClientBot flag
bool isPlayerInVehicle(uint64_t player); // checks m_GetInVehicle
bool isPlayerGliding(uint64_t player);   // checks StartGlideTime > 0
bool isPlayerKnocked(uint64_t player);   // IsFrozenKnockDown || IsKnockedDownBleed

// ── Player string ──
NSString* GetNickName(uint64_t player);  // reads OIAJCBLDHKP string

// ── Bone getters ──
uint64_t getHead(uint64_t player);
uint64_t getHip(uint64_t player);
uint64_t getNeck(uint64_t player);
uint64_t getChest(uint64_t player);
uint64_t getLeftAnkle(uint64_t player);
uint64_t getRightAnkle(uint64_t player);
uint64_t getRightToeNode(uint64_t player);
uint64_t getLeftShoulder(uint64_t player);
uint64_t getRightShoulder(uint64_t player);
uint64_t getLeftElbow(uint64_t player);
uint64_t getRightElbow(uint64_t player);
uint64_t getLeftHand(uint64_t player);
uint64_t getRightHand(uint64_t player);

// ── Utility ──
Vector3  getPositionExt(uint64_t transformNode);
Vector3  WorldToScreen(Vector3 worldPos, float* matrix, float screenW, float screenH);

#endif /* GameLogic_h */
