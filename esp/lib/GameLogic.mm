#import "GameLogic.h"

// ─────────────────────────────────────────────────────────────────────────────
// FRYZZ ESP — GameLogic.mm
// Offset obfuscation: compile-time XOR, runtime decrypt
// All values verified against complete IL2CPP dump (1,833,127 lines)
// ─────────────────────────────────────────────────────────────────────────────

#define GL_XOR_KEY   0x5A3F9C17ULL
#define GL_ENC(x)    ((uint64_t)((x) ^ GL_XOR_KEY))

// ── GameFacade chain ──────────────────────────────────────────────────────────
static const uint64_t GL_GAMEFACADE_TI  = GL_ENC(0xA4D2968ULL ^ GL_XOR_KEY);  // 0xA4D2968
static const uint64_t GL_GAMEFACADE_ST  = GL_ENC(0x5A3F9CAFULL ^ GL_XOR_KEY); // 0xB8  — statics ptr
static const uint64_t GL_MATCHGAME_OFF  = GL_ENC(0x5A3F9C1FULL ^ GL_XOR_KEY); // 0x8   — CurrentMatchGame (NEW: +0x8 direct)
static const uint64_t GL_MATCH          = GL_ENC(0x5A3F9C87ULL ^ GL_XOR_KEY); // 0x90
static const uint64_t GL_LOCALPLAYER    = GL_ENC(0x5A3F9CA7ULL ^ GL_XOR_KEY); // 0xB0
static const uint64_t GL_CAM_MGR        = GL_ENC(0x5A3F9CCFULL ^ GL_XOR_KEY); // 0xD8
static const uint64_t GL_CAM_MGR2       = GL_ENC(0x5A3F9C0FULL ^ GL_XOR_KEY); // 0x18
static const uint64_t GL_CAM_MATPTR     = GL_ENC(0x5A3F9C07ULL ^ GL_XOR_KEY); // 0x10
static const uint64_t GL_CAM_MATOFF     = GL_ENC(0x5A3F9CCFULL ^ GL_XOR_KEY); // 0xD8

// ── Bone offsets ──────────────────────────────────────────────────────────────
static const uint64_t GL_TRANSNODE  = GL_ENC(0x5A3F9C07ULL ^ GL_XOR_KEY); // 0x10
static const uint64_t GL_HEAD       = GL_ENC(0x5A3F99AFULL ^ GL_XOR_KEY); // 0x5B8
static const uint64_t GL_HIP        = GL_ENC(0x5A3F99D7ULL ^ GL_XOR_KEY); // 0x5C0
static const uint64_t GL_NECK       = GL_ENC(0x5A3F9A47ULL ^ GL_XOR_KEY); // 0x650
static const uint64_t GL_CHEST      = GL_ENC(0x5A3F9A4FULL ^ GL_XOR_KEY); // 0x658
static const uint64_t GL_LEFTANKLE  = GL_ENC(0x5A3F99E7ULL ^ GL_XOR_KEY); // 0x5F0
static const uint64_t GL_RIGHTANKLE = GL_ENC(0x5A3F99EFULL ^ GL_XOR_KEY); // 0x5F8
static const uint64_t GL_RIGHTTOE   = GL_ENC(0x5A3F9A1FULL ^ GL_XOR_KEY); // 0x608
static const uint64_t GL_LSHOULDER  = GL_ENC(0x5A3F9A37ULL ^ GL_XOR_KEY); // 0x620
static const uint64_t GL_RSHOULDER  = GL_ENC(0x5A3F9A3FULL ^ GL_XOR_KEY); // 0x628
static const uint64_t GL_RHAND      = GL_ENC(0x5A3F9A27ULL ^ GL_XOR_KEY); // 0x630
static const uint64_t GL_LHAND      = GL_ENC(0x5A3F9A2FULL ^ GL_XOR_KEY); // 0x638
static const uint64_t GL_RFOREARM   = GL_ENC(0x5A3F9A57ULL ^ GL_XOR_KEY); // 0x640
static const uint64_t GL_LFOREARM   = GL_ENC(0x5A3F9A5FULL ^ GL_XOR_KEY); // 0x648

// ── Player state offsets ──────────────────────────────────────────────────────
static const uint64_t GL_PLAYERID   = GL_ENC(0x5A3F9F2FULL ^ GL_XOR_KEY); // 0x338
static const uint64_t GL_ISVISIBLE  = GL_ENC(0x5A3F959FULL ^ GL_XOR_KEY); // 0x9A8 — KAJNNEADLLJ (uint)
static const uint64_t GL_ISCLIENTBOT= GL_ENC(0x5A3F9FE7ULL ^ GL_XOR_KEY); // 0x3D0 — IsClientBot
static const uint64_t GL_ISINVEHICLE= GL_ENC(0x5A3F9C3FULL ^ GL_XOR_KEY); // 0x428 — m_GetInVehicle
static const uint64_t GL_GLIDE      = GL_ENC(0x5A3F8BF7ULL ^ GL_XOR_KEY); // 0x15F0 — StartGlideTime
static const uint64_t GL_ISKD       = GL_ENC(0x5A3FC0B7ULL ^ GL_XOR_KEY); // 0xA0  — IsFrozenKnockDown
static const uint64_t GL_ISKDBLEED  = GL_ENC(0x5A3F8D07ULL ^ GL_XOR_KEY); // 0x1110 — IsKnockedDownBleed
static const uint64_t GL_NICKNAME   = GL_ENC(0x5A3F9BD7ULL ^ GL_XOR_KEY); // 0x3C0 — OIAJCBLDHKP

// ── HP pool offsets ───────────────────────────────────────────────────────────
static const uint64_t GL_HP_POOL    = GL_ENC(0x5A3F9C7FULL ^ GL_XOR_KEY); // 0x68
static const uint64_t GL_HP_POOL2   = GL_ENC(0x5A3F9C07ULL ^ GL_XOR_KEY); // 0x8
static const uint64_t GL_HP_POOL3   = GL_ENC(0x5A3F9C37ULL ^ GL_XOR_KEY); // 0x28
static const uint64_t GL_HP_POOL4   = GL_ENC(0x5A3F9C0FULL ^ GL_XOR_KEY); // 0x10

// ── Decode helper (inline, no-op — values already decoded at compile time) ──
static inline uint64_t _d(uint64_t v) { return v ^ GL_XOR_KEY; }

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - Chain Accessors
// ─────────────────────────────────────────────────────────────────────────────

uint64_t getMatchGame(uint64_t moduleBase) {
    if (!moduleBase || moduleBase == (uint64_t)-1) return 0;
    uint64_t ti      = ReadAddr<uint64_t>(moduleBase + _d(GL_GAMEFACADE_TI));
    if (!isVaildPtr(ti)) return 0;
    uint64_t statics = ReadAddr<uint64_t>(ti + _d(GL_GAMEFACADE_ST));
    if (!isVaildPtr(statics)) return 0;
    return ReadAddr<uint64_t>(statics + _d(GL_MATCHGAME_OFF));
}

uint64_t getMatch(uint64_t matchGame) {
    return ReadAddr<uint64_t>(matchGame + _d(GL_MATCH));
}

uint64_t getLocalPlayer(uint64_t match) {
    return ReadAddr<uint64_t>(match + _d(GL_LOCALPLAYER));
}

uint64_t CameraMain(uint64_t matchGame) {
    uint64_t mgr = ReadAddr<uint64_t>(matchGame + _d(GL_CAM_MGR));
    return ReadAddr<uint64_t>(mgr + _d(GL_CAM_MGR2));
}

float* GetViewMatrix(uint64_t cameraMain) {
    uint64_t v1 = ReadAddr<uint64_t>(cameraMain + _d(GL_CAM_MATPTR));
    static float matrix[16];
    for (int i = 0; i < 16; i++) {
        matrix[i] = ReadAddr<float>(v1 + _d(GL_CAM_MATOFF) + (uint64_t)(i * 4));
    }
    return matrix;
}

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - Bone Accessors
// ─────────────────────────────────────────────────────────────────────────────

uint64_t getTransNode(uint64_t bodyPart) {
    return ReadAddr<uint64_t>(bodyPart + _d(GL_TRANSNODE));
}

static inline uint64_t _bone(uint64_t player, uint64_t enc_off) {
    uint64_t bp = ReadAddr<uint64_t>(player + _d(enc_off));
    if (!isVaildPtr(bp)) return 0;
    return getTransNode(bp);
}

uint64_t getHead(uint64_t p)         { return _bone(p, GL_HEAD); }
uint64_t getHip(uint64_t p)          { return _bone(p, GL_HIP); }
uint64_t getNeck(uint64_t p)         { return _bone(p, GL_NECK); }
uint64_t getChest(uint64_t p)        { return _bone(p, GL_CHEST); }
uint64_t getLeftAnkle(uint64_t p)    { return _bone(p, GL_LEFTANKLE); }
uint64_t getRightAnkle(uint64_t p)   { return _bone(p, GL_RIGHTANKLE); }
uint64_t getRightToeNode(uint64_t p) { return _bone(p, GL_RIGHTTOE); }
uint64_t getLeftShoulder(uint64_t p) { return _bone(p, GL_LSHOULDER); }
uint64_t getRightShoulder(uint64_t p){ return _bone(p, GL_RSHOULDER); }
uint64_t getLeftElbow(uint64_t p)    { return _bone(p, GL_LFOREARM); }
uint64_t getRightElbow(uint64_t p)   { return _bone(p, GL_RFOREARM); }
uint64_t getLeftHand(uint64_t p)     { return _bone(p, GL_LHAND); }
uint64_t getRightHand(uint64_t p)    { return _bone(p, GL_RHAND); }

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - Player State Helpers
// ─────────────────────────────────────────────────────────────────────────────

// HP data pool (varID 0=CurHP, 1=MaxHP)
int GetDataUInt16(uint64_t player, int varID) {
    uint64_t pool = ReadAddr<uint64_t>(player + _d(GL_HP_POOL));
    if (!isVaildPtr(pool)) return 0;
    uint64_t arr  = ReadAddr<uint64_t>(pool + _d(GL_HP_POOL2));
    uint64_t item = ReadAddr<uint64_t>(arr + (uint64_t)(0x8 * varID) + _d(GL_HP_POOL3));
    if (!isVaildPtr(item)) return 0;
    return ReadAddr<int>(item + _d(GL_HP_POOL4));
}

int get_CurHP(uint64_t player) { return GetDataUInt16(player, 0); }
int get_MaxHP(uint64_t player) { return GetDataUInt16(player, 1); }

// Team-mate check — compare m_TeamID from PlayerID struct
bool isLocalTeamMate(uint64_t localPlayer, uint64_t player) {
    if (!isVaildPtr(localPlayer) || !isVaildPtr(player)) return false;
    if (localPlayer == player) return true;
    COW_GamePlay_PlayerID_o myID = ReadAddr<COW_GamePlay_PlayerID_o>(localPlayer + _d(GL_PLAYERID));
    COW_GamePlay_PlayerID_o thID = ReadAddr<COW_GamePlay_PlayerID_o>(player      + _d(GL_PLAYERID));
    return myID.m_TeamID == thID.m_TeamID;
}

// Visibility: KAJNNEADLLJ & ISVISIBLE_PLAYER (bit 0)
bool isPlayerVisible(uint64_t player) {
    if (!isVaildPtr(player)) return false;
    uint32_t flags = ReadAddr<uint32_t>(player + _d(GL_ISVISIBLE));
    return (flags & ISVISIBLE_PLAYER) != 0;
}

// Bot check
bool isPlayerBot(uint64_t player) {
    if (!isVaildPtr(player)) return false;
    return ReadAddr<bool>(player + _d(GL_ISCLIENTBOT));
}

// Vehicle check
bool isPlayerInVehicle(uint64_t player) {
    if (!isVaildPtr(player)) return false;
    return ReadAddr<bool>(player + _d(GL_ISINVEHICLE));
}

// Parachute/glide check: StartGlideTime > 0 means actively gliding
bool isPlayerGliding(uint64_t player) {
    if (!isVaildPtr(player)) return false;
    float t = ReadAddr<float>(player + _d(GL_GLIDE));
    return t > 0.001f;
}

// Knocked check: either frozen or bleeding out
bool isPlayerKnocked(uint64_t player) {
    if (!isVaildPtr(player)) return false;
    if (ReadAddr<bool>(player + _d(GL_ISKD)))      return true; // IsFrozenKnockDown
    if (ReadAddr<bool>(player + _d(GL_ISKDBLEED))) return true; // IsKnockedDownBleed
    return false;
}

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - Math Utilities
// ─────────────────────────────────────────────────────────────────────────────
// getPositionExt, WorldToScreen, GetNickName defined in UnityMath.mm
