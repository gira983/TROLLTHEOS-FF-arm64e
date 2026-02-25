#ifndef GameLogic_h
#define GameLogic_h

#import "MemoryUtils.h"
#import "UnityMath.h"

#pragma mark - Function Game

uint64_t getMatchGame(uint64_t Moudule_Base);
uint64_t getMatch(uint64_t matchgame);
uint64_t CameraMain(uint64_t matchgame);
float* GetViewMatrix(uint64_t cameraMain);
uint64_t getTransNode(uint64_t BodyPart);
uint64_t getLocalPlayer(uint64_t match);
int get_CurHP(uint64_t Player);
int get_MaxHP(uint64_t Player);
bool isLocalTeamMate(uint64_t localPlayer, uint64_t Player);
int GetDataUInt16(uint64_t player, int varID);

// --- Cập nhật thêm cho Bone ---
uint64_t getHead(uint64_t player);      // 0x5B8
uint64_t getHip(uint64_t player);       // 0x5C0
uint64_t getLeftAnkle(uint64_t player); // 0x5F0
uint64_t getRightAnkle(uint64_t player);// 0x5F8
uint64_t getLeftShoulder(uint64_t player); // 0x620 (LeftArmNode)
uint64_t getRightShoulder(uint64_t player);// 0x628 (RightArmNode)
uint64_t getLeftElbow(uint64_t player);    // 0x648 (LeftForeArmNode)
uint64_t getRightElbow(uint64_t player);   // 0x640 (RightForeArmNode)
uint64_t getLeftHand(uint64_t player);     // 0x638
uint64_t getRightHand(uint64_t player);    // 0x630
uint64_t getRightToeNode(uint64_t player); // 0x608

#endif