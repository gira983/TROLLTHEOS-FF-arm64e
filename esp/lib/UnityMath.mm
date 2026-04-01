#import "UnityMath.h"

Vector3 WorldToScreen(Vector3 obj, float *matrix, float screenX, float screenY) {
    float w = matrix[3]*obj.x + matrix[7]*obj.y + matrix[11]*obj.z + matrix[15];
    if (w < 0.5f) w = 0.5f;
    float x = (screenX/2) + (matrix[0]*obj.x + matrix[4]*obj.y + matrix[8] *obj.z + matrix[12]) / w * (screenX/2);
    float y = (screenY/2) - (matrix[1]*obj.x + matrix[5]*obj.y + matrix[9] *obj.z + matrix[13]) / w * (screenY/2);
    return {x, y, 0};
}

Vector3 getPositionExt(uint64_t transObj2) {
    uint64_t transObj = ReadAddr<uint64_t>(transObj2 + 0x10);
    if (!isVaildPtr(transObj)) return {0,0,0};

    uint64_t matrix         = ReadAddr<uint64_t>(transObj + 0x38);
    uint64_t index          = ReadAddr<uint64_t>(transObj + 0x40);
    uint64_t matrix_list    = ReadAddr<uint64_t>(matrix   + 0x18);
    uint64_t matrix_indices = ReadAddr<uint64_t>(matrix   + 0x20);

    if (!isVaildPtr(matrix_list) || !isVaildPtr(matrix_indices)) return {0,0,0};

    Vector3 result     = ReadAddr<Vector3>(matrix_list    + sizeof(TMatrix) * index);
    int transformIndex = ReadAddr<int>    (matrix_indices + sizeof(int)     * index);

    int safety = 50; // из sisi проекта — предотвращает бесконечный цикл
    while (transformIndex >= 0 && safety-- > 0) {
        TMatrix m = ReadAddr<TMatrix>(matrix_list + sizeof(TMatrix) * transformIndex);

        float rx = m.rotation.x, ry = m.rotation.y;
        float rz = m.rotation.z, rw = m.rotation.w;
        float sx = result.x * m.scale.x;
        float sy = result.y * m.scale.y;
        float sz = result.z * m.scale.z;

        result.x = m.position.x + sx + sx*(ry*ry*-2-rz*rz*2) + sy*(rw*rz*-2-ry*rx*-2) + sz*(rz*rx*2-rw*ry*-2);
        result.y = m.position.y + sy + sx*(rx*ry*2-rw*rz*-2) + sy*(rz*rz*-2-rx*rx*-2) + sz*(rw*rx*-2-rz*ry*-2);
        result.z = m.position.z + sz + sx*(rw*ry*-2-rx*rz*-2) + sy*(ry*rz*2-rw*rx*-2) + sz*(rx*rx*-2-ry*ry*-2);

        transformIndex = ReadAddr<int>(matrix_indices + sizeof(int) * transformIndex);
    }
    return result;
}

NSString* GetNickName(uint64_t PawnObject) {
    uint64_t name = ReadAddr<uint64_t>(PawnObject + 0x3C0);
    UTF8  PlayerName[32] = "";
    UTF16 buf16[16]      = {0};
    _read(name + 0x14, buf16, 28);
    Utf16_To_Utf8(buf16, PlayerName, 28, strictConversion);
    return [NSString stringWithUTF8String:(const char*)PlayerName];
}
