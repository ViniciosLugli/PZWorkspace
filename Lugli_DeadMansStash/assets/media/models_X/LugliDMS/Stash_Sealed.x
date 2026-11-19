xof 0303txt 0032
template ColorRGBA {
 <35ff44e0-6c7c-11cf-8f52-0040333594a3>
 FLOAT red;
 FLOAT green;
 FLOAT blue;
 FLOAT alpha;
}

template ColorRGB {
 <d3e16e81-7835-11cf-8f52-0040333594a3>
 FLOAT red;
 FLOAT green;
 FLOAT blue;
}

template Material {
 <3d82ab4d-62da-11cf-ab39-0020af71e433>
 ColorRGBA faceColor;
 FLOAT power;
 ColorRGB specularColor;
 ColorRGB emissiveColor;
 [...]
}

template TextureFilename {
 <a42790e1-7810-11cf-8f52-0040333594a3>
 STRING filename;
}

template Frame {
 <3d82ab46-62da-11cf-ab39-0020af71e433>
 [...]
}

template Matrix4x4 {
 <f6f23f45-7686-11cf-8f52-0040333594a3>
 array FLOAT matrix[16];
}

template FrameTransformMatrix {
 <f6f23f41-7686-11cf-8f52-0040333594a3>
 Matrix4x4 frameMatrix;
}

template Vector {
 <3d82ab5e-62da-11cf-ab39-0020af71e433>
 FLOAT x;
 FLOAT y;
 FLOAT z;
}

template MeshFace {
 <3d82ab5f-62da-11cf-ab39-0020af71e433>
 DWORD nFaceVertexIndices;
 array DWORD faceVertexIndices[nFaceVertexIndices];
}

template Mesh {
 <3d82ab44-62da-11cf-ab39-0020af71e433>
 DWORD nVertices;
 array Vector vertices[nVertices];
 DWORD nFaces;
 array MeshFace faces[nFaces];
 [...]
}

template MeshNormals {
 <f6f23f43-7686-11cf-8f52-0040333594a3>
 DWORD nNormals;
 array Vector normals[nNormals];
 DWORD nFaceNormals;
 array MeshFace faceNormals[nFaceNormals];
}

template MeshMaterialList {
 <f6f23f42-7686-11cf-8f52-0040333594a3>
 DWORD nMaterials;
 DWORD nFaceIndexes;
 array DWORD faceIndexes[nFaceIndexes];
 [Material <3d82ab4d-62da-11cf-ab39-0020af71e433>]
}

template Coords2d {
 <f6f23f44-7686-11cf-8f52-0040333594a3>
 FLOAT u;
 FLOAT v;
}

template MeshTextureCoords {
 <f6f23f40-7686-11cf-8f52-0040333594a3>
 DWORD nTextureCoords;
 array Coords2d textureCoords[nTextureCoords];
}

Material Stash_Sealed_mat {
 1.000000;1.000000;1.000000;1.000000;;
 9.999999;
 0.000000;0.000000;0.000000;;
 0.000000;0.000000;0.000000;;

 TextureFilename {
  "Stash_Sealed.png";
 }
}

Frame Stash_Sealed {

 FrameTransformMatrix {
  1.000000,0.000000,0.000000,0.000000,0.000000,1.000000,0.000000,0.000000,0.000000,0.000000,1.000000,0.000000,0.000000,0.000000,0.000000,1.000000;;
 }

 Mesh Stash_Sealed {
  20;
  0.350000;0.000000;0.200000;,
  -0.350000;0.000000;0.200000;,
  -0.350000;0.328125;0.200000;,
  0.350000;0.328125;0.200000;,
  -0.350000;0.000000;-0.200000;,
  0.350000;0.000000;-0.200000;,
  0.350000;0.328125;-0.200000;,
  -0.350000;0.328125;-0.200000;,
  -0.350000;0.000000;0.200000;,
  -0.350000;0.000000;-0.200000;,
  -0.350000;0.328125;-0.200000;,
  -0.350000;0.328125;0.200000;,
  0.350000;0.000000;-0.200000;,
  0.350000;0.000000;0.200000;,
  0.350000;0.328125;0.200000;,
  0.350000;0.328125;-0.200000;,
  0.350000;0.328125;0.200000;,
  -0.350000;0.328125;0.200000;,
  -0.350000;0.328125;-0.200000;,
  0.350000;0.328125;-0.200000;;
  10;
  3;0,2,1;,
  3;0,3,2;,
  3;4,6,5;,
  3;4,7,6;,
  3;8,10,9;,
  3;8,11,10;,
  3;12,14,13;,
  3;12,15,14;,
  3;16,18,17;,
  3;16,19,18;;

  MeshNormals {
   20;
   0.000000;-1.000000;0.000000;,
   0.000000;-1.000000;0.000000;,
   0.000000;-1.000000;0.000000;,
   0.000000;-1.000000;0.000000;,
   0.000000;-1.000000;0.000000;,
   0.000000;-1.000000;0.000000;,
   0.000000;-1.000000;0.000000;,
   0.000000;-1.000000;0.000000;,
   0.000000;-1.000000;0.000000;,
   0.000000;-1.000000;0.000000;,
   0.000000;-1.000000;0.000000;,
   0.000000;-1.000000;0.000000;,
   0.000000;-1.000000;0.000000;,
   0.000000;-1.000000;0.000000;,
   0.000000;-1.000000;0.000000;,
   0.000000;-1.000000;0.000000;,
   0.000000;-1.000000;0.000000;,
   0.000000;-1.000000;0.000000;,
   0.000000;-1.000000;0.000000;,
   0.000000;-1.000000;0.000000;;
   10;
   3;0,2,1;,
   3;0,3,2;,
   3;4,6,5;,
   3;4,7,6;,
   3;8,10,9;,
   3;8,11,10;,
   3;12,14,13;,
   3;12,15,14;,
   3;16,18,17;,
   3;16,19,18;;
  }

  MeshMaterialList {
   1;
   10;
   0,
   0,
   0,
   0,
   0,
   0,
   0,
   0,
   0,
   0;
   { Stash_Sealed_mat }
  }

  MeshTextureCoords c1 {
   20;
   0.007812;0.570312;,
   0.531250;0.570312;,
   0.531250;0.324219;,
   0.007812;0.324219;,
   0.007812;0.832031;,
   0.531250;0.832031;,
   0.531250;0.585938;,
   0.007812;0.585938;,
   0.546875;0.253906;,
   0.847656;0.253906;,
   0.847656;0.007812;,
   0.546875;0.007812;,
   0.546875;0.570312;,
   0.847656;0.570312;,
   0.847656;0.324219;,
   0.546875;0.324219;,
   0.007812;0.308594;,
   0.531250;0.308594;,
   0.531250;0.007812;,
   0.007812;0.007812;;
  }
 }
}
