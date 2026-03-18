#ifndef GameLogic_h
#define GameLogic_h

#import "MemoryUtils.h"
#import "UnityMath.h"

#pragma mark - Game

uint64_t getMatchGame(uint64_t Moudule_Base);
uint64_t getMatch(uint64_t matchgame);
uint64_t CameraMain(uint64_t matchgame);
float*   GetViewMatrix(uint64_t cameraMain);
uint64_t getLocalPlayer(uint64_t match);
int      get_CurHP(uint64_t Player);
int      get_MaxHP(uint64_t Player);
bool     isLocalTeamMate(uint64_t localPlayer, uint64_t Player);
int      GetDataUInt16(uint64_t player, int varID);

#pragma mark - Bones (verified offsets from obfuscated dump + Kuydum)

uint64_t getHead(uint64_t player);          // 0x5B8 OLCJOGDHJJJ
uint64_t getNeck(uint64_t player);          // 0x5C8 HCLMADAFLPD  ← NEW
uint64_t getHip(uint64_t player);           // 0x5C0 OLJBCONDGLO
uint64_t getLeftShoulder(uint64_t player);  // 0x620 LIBEIIIAGIK
uint64_t getRightShoulder(uint64_t player); // 0x628 HDEPJIBNIIK
uint64_t getLeftElbow(uint64_t player);     // 0x648 FGECMMJKFNC
uint64_t getRightElbow(uint64_t player);    // 0x640 JBACCHNMGNJ
uint64_t getLeftHand(uint64_t player);      // 0x638 JHIBMHEMJOL
uint64_t getRightHand(uint64_t player);     // 0x630 NJDDAPKPILB
uint64_t getLeftKnee(uint64_t player);      // 0x5F0 BMGCHFGEDDA  ← NEW (was LeftAnkle)
uint64_t getRightKnee(uint64_t player);     // 0x5F8 AGHJLIMNPJA  ← NEW (was RightAnkle)
uint64_t getLeftFoot(uint64_t player);      // 0x600 FDMBKCKMODA  ← NEW
uint64_t getRightFoot(uint64_t player);     // 0x608 CKABHDJDMAP  ← NEW

// Legacy aliases
uint64_t getLeftAnkle(uint64_t player);
uint64_t getRightAnkle(uint64_t player);
uint64_t getRightToeNode(uint64_t player);

#endif
