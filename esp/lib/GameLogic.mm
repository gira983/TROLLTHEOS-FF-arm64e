#import "GameLogic.h"

#pragma mark - Function Game

uint64_t getMatchGame(uint64_t Moudule_Base) {
    uint64_t GameFacade_TypeInfo = ReadAddr<uint64_t>(Moudule_Base + 0xA4D2968);
    uint64_t GameFacade_Static = ReadAddr<uint64_t>(GameFacade_TypeInfo + 0xB8);
    return ReadAddr<uint64_t>(GameFacade_Static + 0x0);
}

uint64_t getMatch(uint64_t matchgame) {
    return ReadAddr<uint64_t>(matchgame + 0x90);
}

uint64_t getLocalPlayer(uint64_t match) {
    return ReadAddr<uint64_t>(match + 0xB0);
}

uint64_t CameraMain(uint64_t matchgame) {
    uint64_t CameraControllerManager = ReadAddr<uint64_t>(matchgame + 0xD8);
    return ReadAddr<uint64_t>(CameraControllerManager + 0x18);
}

float* GetViewMatrix(uint64_t cameraMain) {
    uint64_t v1 = ReadAddr<uint64_t>(cameraMain + 0x10);
    
    static float matrix[16];
    for (int i = 0; i < 16; i++) {
        matrix[i] = ReadAddr<float>(v1 + 0xD8 + i * 0x4);
    }
    
    return matrix;
}

uint64_t getTransNode(uint64_t BodyPart) {
    return ReadAddr<uint64_t>(BodyPart + 0x10);
}

uint64_t getHead(uint64_t player) {
    uint64_t BodyPart = ReadAddr<uint64_t>(player + 0x5B8); // protected ITransformNode HeadNode;
    return getTransNode(BodyPart);
}

uint64_t getHip(uint64_t player) {
    uint64_t BodyPart = ReadAddr<uint64_t>(player + 0x5C0); // protected ITransformNode HipNode;
    return getTransNode(BodyPart);
}

uint64_t getLeftAnkle(uint64_t player) {
    uint64_t BodyPart = ReadAddr<uint64_t>(player + 0x5F0); // protected ITransformNode m_LeftAnkleNode;
    return getTransNode(BodyPart);
}

uint64_t getRightAnkle(uint64_t player) {
    uint64_t BodyPart = ReadAddr<uint64_t>(player + 0x5F8); // protected ITransformNode m_RightAnkleNode;
    return getTransNode(BodyPart);
}

uint64_t getRightToeNode(uint64_t player) {
    uint64_t BodyPart = ReadAddr<uint64_t>(player + 0x608); // protected ITransformNode m_RightToeNode;
    return getTransNode(BodyPart);
}


uint64_t getLeftShoulder(uint64_t player) {
    uint64_t BodyPart = ReadAddr<uint64_t>(player + 0x620); // protected ITransformNode m_LeftArmNode;
    return getTransNode(BodyPart);
}

uint64_t getLeftElbow(uint64_t player) {
    uint64_t BodyPart = ReadAddr<uint64_t>(player + 0x648); // protected ITransformNode m_LeftForeArmNode;
    return getTransNode(BodyPart);
}

uint64_t getLeftHand(uint64_t player) {
    uint64_t BodyPart = ReadAddr<uint64_t>(player + 0x638); // protected ITransformNode m_LeftHandNode;
    return getTransNode(BodyPart);
}

uint64_t getRightShoulder(uint64_t player) {
    uint64_t BodyPart = ReadAddr<uint64_t>(player + 0x628); // protected ITransformNode m_RightArmNode;
    return getTransNode(BodyPart);
}

uint64_t getRightElbow(uint64_t player) {
    uint64_t BodyPart = ReadAddr<uint64_t>(player + 0x640); // protected ITransformNode m_RightForeArmNode;
    return getTransNode(BodyPart);
}

uint64_t getRightHand(uint64_t player) {
    uint64_t BodyPart = ReadAddr<uint64_t>(player + 0x630); // protected ITransformNode m_RightHandNode;
    return getTransNode(BodyPart);
}

bool isLocalTeamMate(uint64_t localPlayer, uint64_t Player) {
    COW_GamePlay_PlayerID_o myPlayerID = ReadAddr<COW_GamePlay_PlayerID_o>(localPlayer + 0x338);
    COW_GamePlay_PlayerID_o PlayerID = ReadAddr<COW_GamePlay_PlayerID_o>(Player + 0x338);
    
    int myTeamID = myPlayerID.m_TeamID;
    int TeamID = PlayerID.m_TeamID;
    
    return myTeamID == TeamID;
}

int GetDataUInt16(uint64_t player, int varID) {
    uint64_t IPRIDataPool = ReadAddr<uint64_t>(player + 0x68);
    if (isVaildPtr(IPRIDataPool)) {
        uint64_t v2 = ReadAddr<uint64_t>(IPRIDataPool + 0x10);
        uint64_t v4 = ReadAddr<uint64_t>(v2 + 0x8 * varID + 0x20);
        int v6 = ReadAddr<int>(v4 + 0x18);
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


extern "C" bool get_IsFiring(uint64_t player) {
    // protected bool m_IsFiring; // 0x540
    return ReadAddr<bool>(player + 0x540);
}

extern "C" void set_aim(uint64_t player, Vector3 angle) {
    // public Vector3 AimRotation; // 0x340
    WriteAddr<Vector3>(player + 0x340, angle);
}

extern "C" Vector3 GetRotationToLocation(Vector3 targetPos, float speed, Vector3 myPos) {
    Vector3 diff = targetPos - myPos;
    float dist = Vector3::Magnitude(diff);
    
    float pitch = -asin(diff.y / dist) * (180 / M_PI);
    float yaw = atan2(diff.x, diff.z) * (180 / M_PI);
    
    return Vector3(pitch, yaw, 0);
}
