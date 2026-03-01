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
// Player nodes
#define GL_HEAD_NODE        ENCRYPTOFFSET("0x5B8")
#define GL_HIP_NODE         ENCRYPTOFFSET("0x5C0")
#define GL_LEFTANKLE_NODE   ENCRYPTOFFSET("0x5F0")
#define GL_RIGHTANKLE_NODE  ENCRYPTOFFSET("0x5F8")
#define GL_RIGHTTOE_NODE    ENCRYPTOFFSET("0x608")
#define GL_LEFTARM_NODE     ENCRYPTOFFSET("0x620")
#define GL_LEFTFOREARM_NODE ENCRYPTOFFSET("0x648")
#define GL_LEFTHAND_NODE    ENCRYPTOFFSET("0x638")
#define GL_RIGHTARM_NODE    ENCRYPTOFFSET("0x628")
#define GL_RIGHTFOREARM_NODE ENCRYPTOFFSET("0x640")
#define GL_RIGHTHAND_NODE   ENCRYPTOFFSET("0x630")
#define GL_BODYPART_POS     ENCRYPTOFFSET("0x10")
// Player data
#define GL_PLAYERID         ENCRYPTOFFSET("0x338")
#define GL_IPRIDATAPOOL     ENCRYPTOFFSET("0x68")
#define GL_POOL_LIST        ENCRYPTOFFSET("0x10")
#define GL_POOL_ITEM        ENCRYPTOFFSET("0x20")
#define GL_POOL_VAL         ENCRYPTOFFSET("0x18")

#pragma mark - Function Game

uint64_t getMatchGame(uint64_t Moudule_Base) {
    uint64_t GameFacade_TypeInfo = ReadAddr<uint64_t>(Moudule_Base + GL_GAMEFACADE_TI);
    uint64_t GameFacade_Static   = ReadAddr<uint64_t>(GameFacade_TypeInfo + GL_GAMEFACADE_ST);
    return ReadAddr<uint64_t>(GameFacade_Static + 0x0);
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
    for (int i = 0; i < 16; i++) {
        matrix[i] = ReadAddr<float>(v1 + GL_MATRIX_BASE + i * 0x4);
    }
    return matrix;
}

uint64_t getTransNode(uint64_t BodyPart) {
    return ReadAddr<uint64_t>(BodyPart + GL_BODYPART_POS);
}

uint64_t getHead(uint64_t player) {
    return getTransNode(ReadAddr<uint64_t>(player + GL_HEAD_NODE));
}

uint64_t getHip(uint64_t player) {
    return getTransNode(ReadAddr<uint64_t>(player + GL_HIP_NODE));
}

uint64_t getLeftAnkle(uint64_t player) {
    return getTransNode(ReadAddr<uint64_t>(player + GL_LEFTANKLE_NODE));
}

uint64_t getRightAnkle(uint64_t player) {
    return getTransNode(ReadAddr<uint64_t>(player + GL_RIGHTANKLE_NODE));
}

uint64_t getRightToeNode(uint64_t player) {
    return getTransNode(ReadAddr<uint64_t>(player + GL_RIGHTTOE_NODE));
}

uint64_t getLeftShoulder(uint64_t player) {
    return getTransNode(ReadAddr<uint64_t>(player + GL_LEFTARM_NODE));
}

uint64_t getLeftElbow(uint64_t player) {
    return getTransNode(ReadAddr<uint64_t>(player + GL_LEFTFOREARM_NODE));
}

uint64_t getLeftHand(uint64_t player) {
    return getTransNode(ReadAddr<uint64_t>(player + GL_LEFTHAND_NODE));
}

uint64_t getRightShoulder(uint64_t player) {
    return getTransNode(ReadAddr<uint64_t>(player + GL_RIGHTARM_NODE));
}

uint64_t getRightElbow(uint64_t player) {
    return getTransNode(ReadAddr<uint64_t>(player + GL_RIGHTFOREARM_NODE));
}

uint64_t getRightHand(uint64_t player) {
    return getTransNode(ReadAddr<uint64_t>(player + GL_RIGHTHAND_NODE));
}

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

int get_CurHP(uint64_t Player) {
    return GetDataUInt16(Player, 0);
}

int get_MaxHP(uint64_t Player) {
    return GetDataUInt16(Player, 1);
}
