#import "GameLogic.h"

// XOR-обфусцированные оффсеты
#define GL_XOR_KEY 0x5A3F9C17ULL
#define GL_GAMEFACADE_TI ((uint64_t)(0x5072B57FULL ^ GL_XOR_KEY))
#define GL_GAMEFACADE_ST ((uint64_t)(0x5A3F9CAFULL ^ GL_XOR_KEY))
#define GL_MATCH ((uint64_t)(0x5A3F9C87ULL ^ GL_XOR_KEY))
#define GL_LOCALPLAYER ((uint64_t)(0x5A3F9CA7ULL ^ GL_XOR_KEY))
#define GL_CAM_MGR ((uint64_t)(0x5A3F9CCFULL ^ GL_XOR_KEY))
#define GL_CAM_MGR2 ((uint64_t)(0x5A3F9C0FULL ^ GL_XOR_KEY))
#define GL_CAM_V1 ((uint64_t)(0x5A3F9C07ULL ^ GL_XOR_KEY))
#define GL_MATRIX_D8 ((uint64_t)(0x5A3F9CCFULL ^ GL_XOR_KEY))
#define GL_TRANSNODE ((uint64_t)(0x5A3F9C07ULL ^ GL_XOR_KEY))
#define GL_HEAD ((uint64_t)(0x5A3F99AFULL ^ GL_XOR_KEY))
#define GL_HIP ((uint64_t)(0x5A3F99D7ULL ^ GL_XOR_KEY))
#define GL_LEFTANKLE ((uint64_t)(0x5A3F99E7ULL ^ GL_XOR_KEY))
#define GL_RIGHTANKLE ((uint64_t)(0x5A3F99EFULL ^ GL_XOR_KEY))
#define GL_RIGHTTOE ((uint64_t)(0x5A3F9A1FULL ^ GL_XOR_KEY))
#define GL_LSHOULDER ((uint64_t)(0x5A3F9A37ULL ^ GL_XOR_KEY))
#define GL_LELBOW ((uint64_t)(0x5A3F9A5FULL ^ GL_XOR_KEY))
#define GL_LHAND ((uint64_t)(0x5A3F9A2FULL ^ GL_XOR_KEY))
#define GL_RSHOULDER ((uint64_t)(0x5A3F9A3FULL ^ GL_XOR_KEY))
#define GL_RELBOW ((uint64_t)(0x5A3F9A57ULL ^ GL_XOR_KEY))
#define GL_RHAND ((uint64_t)(0x5A3F9A27ULL ^ GL_XOR_KEY))
#define GL_PLAYERID ((uint64_t)(0x5A3F9F2FULL ^ GL_XOR_KEY))
#define GL_HP_POOL ((uint64_t)(0x5A3F9C7FULL ^ GL_XOR_KEY))
#define GL_HP_POOL2 ((uint64_t)(0x5A3F9C07ULL ^ GL_XOR_KEY))
#define GL_HP_POOL3 ((uint64_t)(0x5A3F9C37ULL ^ GL_XOR_KEY))
#define GL_HP_POOL4 ((uint64_t)(0x5A3F9C0FULL ^ GL_XOR_KEY))

#pragma mark - Function Game

uint64_t getMatchGame(uint64_t Moudule_Base) {
    uint64_t GameFacade_TypeInfo = ReadAddr<uint64_t>(Moudule_Base + GL_GAMEFACADE_TI);
    uint64_t GameFacade_Static   = ReadAddr<uint64_t>(GameFacade_TypeInfo + GL_GAMEFACADE_ST);
    return ReadAddr<uint64_t>(GameFacade_Static + (uint64_t)0);
}

uint64_t getMatch(uint64_t matchgame) {
    return ReadAddr<uint64_t>(matchgame + GL_MATCH);
}

uint64_t getLocalPlayer(uint64_t match) {
    return ReadAddr<uint64_t>(match + GL_LOCALPLAYER);
}

uint64_t CameraMain(uint64_t matchgame) {
    uint64_t CameraControllerManager = ReadAddr<uint64_t>(matchgame + GL_CAM_MGR);
    return ReadAddr<uint64_t>(CameraControllerManager + GL_CAM_MGR2);
}

float* GetViewMatrix(uint64_t cameraMain) {
    uint64_t v1 = ReadAddr<uint64_t>(cameraMain + GL_CAM_V1);
    static float matrix[16];
    for (int i = 0; i < 16; i++) {
        matrix[i] = ReadAddr<float>(v1 + GL_MATRIX_D8 + i * 4);
    }
    return matrix;
}

uint64_t getTransNode(uint64_t BodyPart) {
    return ReadAddr<uint64_t>(BodyPart + GL_TRANSNODE);
}

uint64_t getHead(uint64_t player)         { return getTransNode(ReadAddr<uint64_t>(player + GL_HEAD)); }
uint64_t getHip(uint64_t player)          { return getTransNode(ReadAddr<uint64_t>(player + GL_HIP)); }
uint64_t getLeftAnkle(uint64_t player)    { return getTransNode(ReadAddr<uint64_t>(player + GL_LEFTANKLE)); }
uint64_t getRightAnkle(uint64_t player)   { return getTransNode(ReadAddr<uint64_t>(player + GL_RIGHTANKLE)); }
uint64_t getRightToeNode(uint64_t player) { return getTransNode(ReadAddr<uint64_t>(player + GL_RIGHTTOE)); }
uint64_t getLeftShoulder(uint64_t player) { return getTransNode(ReadAddr<uint64_t>(player + GL_LSHOULDER)); }
uint64_t getLeftElbow(uint64_t player)    { return getTransNode(ReadAddr<uint64_t>(player + GL_LELBOW)); }
uint64_t getLeftHand(uint64_t player)     { return getTransNode(ReadAddr<uint64_t>(player + GL_LHAND)); }
uint64_t getRightShoulder(uint64_t player){ return getTransNode(ReadAddr<uint64_t>(player + GL_RSHOULDER)); }
uint64_t getRightElbow(uint64_t player)   { return getTransNode(ReadAddr<uint64_t>(player + GL_RELBOW)); }
uint64_t getRightHand(uint64_t player)    { return getTransNode(ReadAddr<uint64_t>(player + GL_RHAND)); }

bool isLocalTeamMate(uint64_t localPlayer, uint64_t Player) {
    COW_GamePlay_PlayerID_o myPlayerID = ReadAddr<COW_GamePlay_PlayerID_o>(localPlayer + GL_PLAYERID);
    COW_GamePlay_PlayerID_o PlayerID   = ReadAddr<COW_GamePlay_PlayerID_o>(Player      + GL_PLAYERID);
    return myPlayerID.m_TeamID == PlayerID.m_TeamID;
}

int GetDataUInt16(uint64_t player, int varID) {
    uint64_t IPRIDataPool = ReadAddr<uint64_t>(player + GL_HP_POOL);
    if (isVaildPtr(IPRIDataPool)) {
        uint64_t v2 = ReadAddr<uint64_t>(IPRIDataPool + GL_HP_POOL2);
        uint64_t v4 = ReadAddr<uint64_t>(v2 + (uint64_t)(0x8 * varID) + GL_HP_POOL3);
        return ReadAddr<int>(v4 + GL_HP_POOL4);
    }
    return 0;
}

int get_CurHP(uint64_t Player) { return GetDataUInt16(Player, 0); }
int get_MaxHP(uint64_t Player) { return GetDataUInt16(Player, 1); }
