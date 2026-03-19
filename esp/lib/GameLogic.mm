#import "GameLogic.h"
#import "../../mahoa.h"

// --- Obfuscated offsets ---
// GameFacade
#define GL_GAMEFACADE_TI    ENCRYPTOFFSET("0xA4D2968")
#define GL_GAMEFACADE_ST    ENCRYPTOFFSET("0xB8")
// Match/game
#define GL_MATCH            ENCRYPTOFFSET("0x90")
#define GL_LOCALPLAYER      ENCRYPTOFFSET("0xB0")
#define GL_CAMERA_MGR       ENCRYPTOFFSET("0xD8")
#define GL_CAMERA_MGR2      ENCRYPTOFFSET("0x18")
#define GL_CAM_V1           ENCRYPTOFFSET("0x10")
#define GL_MATRIX_BASE      ENCRYPTOFFSET("0xD8")

// ─── Player bone nodes (verified against obfuscated dump + Kuydum) ────────────
// Offset  OldName              ObfName        KuydumName
// 0x5B8   m_LeftArmNode(OLD)   OLCJOGDHJJJ    Head
// 0x5C0   m_RightArmNode(OLD)  OLJBCONDGLO    Hip
// 0x5C8   m_RightHandNode(OLD) HCLMADAFLPD    Neck
// 0x5E0   m_LeftForeArm(OLD)   MPJBGDJJJMJ    Root
// 0x5F0   —                    BMGCHFGEDDA    LeftKnee
// 0x5F8   —                    AGHJLIMNPJA    RightKnee
// 0x600   —                    FDMBKCKMODA    LeftFoot
// 0x608   —                    CKABHDJDMAP    RightFoot
// 0x620   —                    LIBEIIIAGIK    LeftShoulder
// 0x628   —                    HDEPJIBNIIK    RightShoulder
// 0x630   —                    NJDDAPKPILB    RightHand
// 0x638   —                    JHIBMHEMJOL    LeftHand
// 0x640   —                    JBACCHNMGNJ    RightElbow
// 0x648   —                    FGECMMJKFNC    LeftElbow
#define GL_HEAD_NODE         ENCRYPTOFFSET("0x5B8")
#define GL_HIP_NODE          ENCRYPTOFFSET("0x5C0")
#define GL_NECK_NODE         ENCRYPTOFFSET("0x5C8")  // NEW — real Neck joint
#define GL_ROOT_NODE         ENCRYPTOFFSET("0x5E0")
#define GL_LEFT_KNEE_NODE    ENCRYPTOFFSET("0x5F0")  // was wrongly named LeftAnkle
#define GL_RIGHT_KNEE_NODE   ENCRYPTOFFSET("0x5F8")  // was wrongly named RightAnkle
#define GL_LEFT_FOOT_NODE    ENCRYPTOFFSET("0x600")  // NEW — real foot/ankle
#define GL_RIGHT_FOOT_NODE   ENCRYPTOFFSET("0x608")  // NEW — real foot/ankle
#define GL_LEFTARM_NODE      ENCRYPTOFFSET("0x620")  // LeftShoulder
#define GL_RIGHTARM_NODE     ENCRYPTOFFSET("0x628")  // RightShoulder
#define GL_RIGHTHAND_NODE    ENCRYPTOFFSET("0x630")
#define GL_LEFTHAND_NODE     ENCRYPTOFFSET("0x638")
#define GL_RIGHTFOREARM_NODE ENCRYPTOFFSET("0x640")  // RightElbow
#define GL_LEFTFOREARM_NODE  ENCRYPTOFFSET("0x648")  // LeftElbow

#define GL_BODYPART_POS     ENCRYPTOFFSET("0x10")
// Player data
#define GL_PLAYERID         ENCRYPTOFFSET("0x338")
#define GL_IPRIDATAPOOL     ENCRYPTOFFSET("0x68")
#define GL_POOL_LIST        ENCRYPTOFFSET("0x10")
#define GL_POOL_ITEM        ENCRYPTOFFSET("0x20")
#define GL_POOL_VAL         ENCRYPTOFFSET("0x18")

#pragma mark - Function Game

// ─── GameFacade static fields (from dump) ────────────────────────────────────
// GameFacade_Static + 0x0 = CurrentGame      (BaseGame)
// GameFacade_Static + 0x8 = CurrentMatchGame (MatchGame) ← in-match indicator
#define GL_GAMEFACADE_CURRENT_GAME       ENCRYPTOFFSET("0x0")
#define GL_GAMEFACADE_CURRENT_MATCHGAME  ENCRYPTOFFSET("0x8")

uint64_t getMatchGame(uint64_t Moudule_Base) {
    uint64_t GameFacade_TypeInfo = ReadAddr<uint64_t>(Moudule_Base + GL_GAMEFACADE_TI);
    uint64_t GameFacade_Static   = ReadAddr<uint64_t>(GameFacade_TypeInfo + GL_GAMEFACADE_ST);
    return ReadAddr<uint64_t>(GameFacade_Static + GL_GAMEFACADE_CURRENT_GAME);
}

// Returns CurrentMatchGame — non-zero only while inside a match
uint64_t getCurrentMatchGame(uint64_t Moudule_Base) {
    uint64_t GameFacade_TypeInfo = ReadAddr<uint64_t>(Moudule_Base + GL_GAMEFACADE_TI);
    uint64_t GameFacade_Static   = ReadAddr<uint64_t>(GameFacade_TypeInfo + GL_GAMEFACADE_ST);
    return ReadAddr<uint64_t>(GameFacade_Static + GL_GAMEFACADE_CURRENT_MATCHGAME);
}

uint64_t getMatch(uint64_t matchgame) {
    return ReadAddr<uint64_t>(matchgame + GL_MATCH);
}

uint64_t getLocalPlayer(uint64_t match) {
    return ReadAddr<uint64_t>(match + GL_LOCALPLAYER);
}

uint64_t CameraMain(uint64_t matchgame) {
    uint64_t CameraControllerManager = ReadAddr<uint64_t>(matchgame + GL_CAMERA_MGR);
    return ReadAddr<uint64_t>(CameraControllerManager + GL_CAMERA_MGR2);
}

float* GetViewMatrix(uint64_t cameraMain) {
    uint64_t v1 = ReadAddr<uint64_t>(cameraMain + GL_CAM_V1);
    static float matrix[16];
    if (!_read(v1 + GL_MATRIX_BASE, matrix, sizeof(matrix)))
        memset(matrix, 0, sizeof(matrix));
    return matrix;
}

// Read position from ITransformNode pointer stored at player+offset
static inline uint64_t getTransNode(uint64_t BodyPart) {
    return ReadAddr<uint64_t>(BodyPart + GL_BODYPART_POS);
}

static inline uint64_t boneNode(uint64_t player, uint64_t offset) {
    return getTransNode(ReadAddr<uint64_t>(player + offset));
}

uint64_t getHead(uint64_t player)         { return boneNode(player, GL_HEAD_NODE); }
uint64_t getNeck(uint64_t player)         { return boneNode(player, GL_NECK_NODE); }
uint64_t getHip(uint64_t player)          { return boneNode(player, GL_HIP_NODE); }
uint64_t getLeftShoulder(uint64_t player) { return boneNode(player, GL_LEFTARM_NODE); }
uint64_t getRightShoulder(uint64_t player){ return boneNode(player, GL_RIGHTARM_NODE); }
uint64_t getLeftElbow(uint64_t player)    { return boneNode(player, GL_LEFTFOREARM_NODE); }
uint64_t getRightElbow(uint64_t player)   { return boneNode(player, GL_RIGHTFOREARM_NODE); }
uint64_t getLeftHand(uint64_t player)     { return boneNode(player, GL_LEFTHAND_NODE); }
uint64_t getRightHand(uint64_t player)    { return boneNode(player, GL_RIGHTHAND_NODE); }
uint64_t getLeftKnee(uint64_t player)     { return boneNode(player, GL_LEFT_KNEE_NODE); }
uint64_t getRightKnee(uint64_t player)    { return boneNode(player, GL_RIGHT_KNEE_NODE); }
uint64_t getLeftFoot(uint64_t player)     { return boneNode(player, GL_LEFT_FOOT_NODE); }
uint64_t getRightFoot(uint64_t player)    { return boneNode(player, GL_RIGHT_FOOT_NODE); }

// Legacy aliases kept for any remaining references
uint64_t getLeftAnkle(uint64_t player)    { return getLeftFoot(player); }
uint64_t getRightAnkle(uint64_t player)   { return getRightFoot(player); }
uint64_t getRightToeNode(uint64_t player) { return getRightFoot(player); }

bool isLocalTeamMate(uint64_t localPlayer, uint64_t Player) {
    COW_GamePlay_PlayerID_o myPlayerID = ReadAddr<COW_GamePlay_PlayerID_o>(localPlayer + GL_PLAYERID);
    COW_GamePlay_PlayerID_o PlayerID   = ReadAddr<COW_GamePlay_PlayerID_o>(Player + GL_PLAYERID);
    return myPlayerID.m_TeamID == PlayerID.m_TeamID;
}

int GetDataUInt16(uint64_t player, int varID) {
    uint64_t IPRIDataPool = ReadAddr<uint64_t>(player + GL_IPRIDATAPOOL);
    if (isVaildPtr(IPRIDataPool)) {
        uint64_t v2 = ReadAddr<uint64_t>(IPRIDataPool + GL_POOL_LIST);
        uint64_t v4 = ReadAddr<uint64_t>(v2 + 0x8 * varID + GL_POOL_ITEM);
        return ReadAddr<int>(v4 + GL_POOL_VAL);
    }
    return 0;
}

int get_CurHP(uint64_t Player) { return GetDataUInt16(Player, 0); }
int get_MaxHP(uint64_t Player) { return GetDataUInt16(Player, 1); }
