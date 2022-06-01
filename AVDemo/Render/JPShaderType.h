//
//  JPShaderType.h
//  AVDemo
//
//  Created by LJP on 2022/6/1.
//

#ifndef JPShaderType_h
#define JPShaderType_h

#include <simd/simd.h>

// 存储数据的自定义结构，用于桥接 OC 和 Metal 代码（顶点）。
typedef struct {
    // 顶点坐标，4 维向量。
    vector_float4 position;
    // 纹理坐标。
    vector_float2 textureCoordinate;
} JPVertex;

// 存储数据的自定义结构，用于桥接 OC 和 Metal 代码（顶点）。
typedef struct {
    // YUV 矩阵。
    matrix_float3x3 matrix;
    // 是否为 full range。
    bool fullRange;
} JPConvertMatrix;

// 自定义枚举，用于桥接 OC 和 Metal 代码（顶点）。
// 顶点的桥接枚举值 JPVertexInputIndexVertices。
typedef enum JPVertexInputIndex {
    JPVertexInputIndexVertices = 0,
} JPVertexInputIndex;

// 自定义枚举，用于桥接 OC 和 Metal 代码（片元）。
// YUV 矩阵的桥接枚举值 JPFragmentInputIndexMatrix。
typedef enum JPFragmentBufferIndex {
    JPFragmentInputIndexMatrix = 0,
} JPMetalFragmentBufferIndex;

// 自定义枚举，用于桥接 OC 和 Metal 代码（片元）。
// YUV 数据的桥接枚举值 JPFragmentTextureIndexTextureY、JPFragmentTextureIndexTextureUV。
typedef enum JPFragmentYUVTextureIndex {
    JPFragmentTextureIndexTextureY = 0,
    JPFragmentTextureIndexTextureUV = 1,
} JPFragmentYUVTextureIndex;

// 自定义枚举，用于桥接 OC 和 Metal 代码（片元）。
// RGBA 数据的桥接枚举值 JPFragmentTextureIndexTextureRGB。
typedef enum JPFragmentRGBTextureIndex {
    JPFragmentTextureIndexTextureRGB = 0,
} JPFragmentRGBTextureIndex;


#endif /* JPShaderType_h */
