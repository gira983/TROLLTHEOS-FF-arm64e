#import "GameLogic.h"
#import "mahoa.h"

#pragma mark - Function Game

uint64_t getMatchGame(uint64_t Moudule_Base) {
    uint64_t GameFacade_TypeInfo = ReadAddr<uint64_t>(Moudule_Base + ENCRYPTOFFSET("0xA4D2968"));
    uint64_t GameFacade_Static   = ReadAddr<uint64_t>(GameFacade_TypeInfo + ENCRYPTOFFSET("0xB8"));
    return ReadAddr<uint64_t>(GameFacade_Static + ENCRYPTOFFSET("0x0"));
}

uint64_t getMatch(uint64_t matchgame) {
    return ReadAddr<uint64_t>(matchgame + ENCRYPTOFFSET("0x90"));
}

uint64_t getLocalPlayer(uint64_t match) {
    return ReadAddr<uint64_t>(match + ENCRYPTOFFSET("0xB0"));
}

uint64_t CameraMain(uint64_t matchgame) {
    uint64_t CameraControllerManager = ReadAddr<uint64_t>(matchgame + ENCRYPTOFFSET("0xD8"));
    return ReadAddr<uint64_t>(CameraControllerManager + ENCRYPTOFFSET("0x18"));
}

float* GetViewMatrix(uint64_t cameraMain) {
    uint64_t v1 = ReadAddr<uint64_t>(cameraMain + ENCRYPTOFFSET("0x10"));

    static float matrix[16];
    for (int i = 0; i < 16; i++) {
        matrix[i] = ReadAddr<float>(v1 + ENCRYPTOFFSET("0xD8") + i * 0x4);
    }

    return matrix;
}

uint64_t getTransNode(uint64_t BodyPart) {
    return ReadAddr<uint64_t>(BodyPart + ENCRYPTOFFSET("0x10"));
}

uint64_t getHead(uint64_t player) {
    uint64_t BodyPart = ReadAddr<uint64_t>(player + ENCRYPTOFFSET("0x5B8"));
    return getTransNode(BodyPart);
}

uint64_t getHip(uint64_t player) {
    uint64_t BodyPart = ReadAddr<uint64_t>(player + ENCRYPTOFFSET("0x5C0"));
    return getTransNode(BodyPart);
}

uint64_t getLeftAnkle(uint64_t player) {
    uint64_t BodyPart = ReadAddr<uint64_t>(player + ENCRYPTOFFSET("0x5F0"));
    return getTransNode(BodyPart);
}

uint64_t getRightAnkle(uint64_t player) {
    uint64_t BodyPart = ReadAddr<uint64_t>(player + ENCRYPTOFFSET("0x5F8"));
    return getTransNode(BodyPart);
}

uint64_t getRightToeNode(uint64_t player) {
    uint64_t BodyPart = ReadAddr<uint64_t>(player + ENCRYPTOFFSET("0x608"));
    return getTransNode(BodyPart);
}

uint64_t getLeftShoulder(uint64_t player) {
    uint64_t BodyPart = ReadAddr<uint64_t>(player + ENCRYPTOFFSET("0x620"));
    return getTransNode(BodyPart);
}

uint64_t getLeftElbow(uint64_t player) {
    uint64_t BodyPart = ReadAddr<uint64_t>(player + ENCRYPTOFFSET("0x648"));
    return getTransNode(BodyPart);
}

uint64_t getLeftHand(uint64_t player) {
    uint64_t BodyPart = ReadAddr<uint64_t>(player + ENCRYPTOFFSET("0x638"));
    return getTransNode(BodyPart);
}

uint64_t getRightShoulder(uint64_t player) {
    uint64_t BodyPart = ReadAddr<uint64_t>(player + ENCRYPTOFFSET("0x628"));
    return getTransNode(BodyPart);
}

uint64_t getRightElbow(uint64_t player) {
    uint64_t BodyPart = ReadAddr<uint64_t>(player + ENCRYPTOFFSET("0x640"));
    return getTransNode(BodyPart);
}

uint64_t getRightHand(uint64_t player) {
    uint64_t BodyPart = ReadAddr<uint64_t>(player + ENCRYPTOFFSET("0x630"));
    return getTransNode(BodyPart);
}

bool isLocalTeamMate(uint64_t localPlayer, uint64_t Player) {
    COW_GamePlay_PlayerID_o myPlayerID = ReadAddr<COW_GamePlay_PlayerID_o>(localPlayer + ENCRYPTOFFSET("0x338"));
    COW_GamePlay_PlayerID_o PlayerID   = ReadAddr<COW_GamePlay_PlayerID_o>(Player      + ENCRYPTOFFSET("0x338"));

    int myTeamID = myPlayerID.m_TeamID;
    int TeamID   = PlayerID.m_TeamID;

    return myTeamID == TeamID;
}

int GetDataUInt16(uint64_t player, int varID) {
    uint64_t IPRIDataPool = ReadAddr<uint64_t>(player + ENCRYPTOFFSET("0x68"));
    if (isVaildPtr(IPRIDataPool)) {
        uint64_t v2 = ReadAddr<uint64_t>(IPRIDataPool + ENCRYPTOFFSET("0x10"));
        uint64_t v4 = ReadAddr<uint64_t>(v2 + 0x8 * varID + ENCRYPTOFFSET("0x20"));
        int v6 = ReadAddr<int>(v4 + ENCRYPTOFFSET("0x18"));
        return v6;
    }
    return 0;
}

int get_CurHP(uint64_t Player) {
    return GetDataUInt16(Player, 0);
}

int get_MaxHP(uint64_t Player) {
    return GetDataUInt16(Player, 1);
}
