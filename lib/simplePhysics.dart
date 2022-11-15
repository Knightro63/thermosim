import 'package:flutter_gl/flutter_gl.dart';
import 'package:three_dart/three_dart.dart' hide Texture, Color;

class PhysicsScene{
  List<double> gravity = [0.0, 0.0, -9.81];
  double dt = 1.0 / 60.0;
  int numSubsteps =  5;
  bool paused = true;
  bool showEdges = true;
  List<SoftObject> objects = [];
  double temperatue = 25;
}

class EdgeId{
  EdgeId({
    required this.id0,
    required this.id1,
    required this.edgeNr
  });

  int id0;
  int id1;
  int edgeNr; 
}

class ClothMath{
  // ----- math on vector arrays -------------------------------------------------------------
  void vecSetZero(a, int anr){
    anr *= 3;
    a[anr++] = 0.0;
    a[anr++] = 0.0;
    a[anr]   = 0.0;
  }

  void vecScale(a,int anr, double scale) {
    anr *= 3;
    a[anr++] *= scale;
    a[anr++] *= scale;
    a[anr]   *= scale;
  }

  void vecCopy(a,int anr, b,int bnr) {
    anr *= 3; bnr *= 3;
    a[anr++] = b[bnr++]; 
    a[anr++] = b[bnr++]; 
    a[anr]   = b[bnr];
  }
  
  void vecAdd(a,int anr, b,int bnr, [double scale = 1.0]) {
    anr *= 3; bnr *= 3;
    a[anr++] += b[bnr++] * scale; 
    a[anr++] += b[bnr++] * scale; 
    a[anr]   += b[bnr] * scale;
  }

  void vecSetDiff(dst,int dnr, a,int anr, b,int bnr, [double scale = 1.0]) {
    dnr *= 3; anr *= 3; bnr *= 3;
    dst[dnr++] = (a[anr++] - b[bnr++]) * scale;
    dst[dnr++] = (a[anr++] - b[bnr++]) * scale;
    dst[dnr]   = (a[anr] - b[bnr]) * scale;
  }

  double vecLengthSquared(a,int anr) {
    anr *= 3;
    double a0 = a[anr], a1 = a[anr + 1], a2 = a[anr + 2];
    return a0 * a0 + a1 * a1 + a2 * a2;
  }

  double vecDistSquared(a,int anr, b,int bnr) {
    anr *= 3; bnr *= 3;
    double a0 = a[anr] - b[bnr], a1 = a[anr + 1] - b[bnr + 1], a2 = a[anr + 2] - b[bnr + 2];
    return a0 * a0 + a1 * a1 + a2 * a2;
  }	

  double vecDot(a,int anr, b,int bnr) {
    anr *= 3; bnr *= 3;
    return a[anr] * b[bnr] + a[anr + 1] * b[bnr + 1] + a[anr + 2] * b[bnr + 2];
  }	

  void vecSetCross(a,int anr, b,int bnr, c,int cnr) {
    anr *= 3; bnr *= 3; cnr *= 3;
    a[anr++] = b[bnr + 1] * c[cnr + 2] - b[bnr + 2] * c[cnr + 1];
    a[anr++] = b[bnr + 2] * c[cnr + 0] - b[bnr + 0] * c[cnr + 2];
    a[anr]   = b[bnr + 0] * c[cnr + 1] - b[bnr + 1] * c[cnr + 0];
  }

  // ------------------------------------------------------------------
  Int32Array findTriNeighbors(List<num> triIds) {
    // create common edges

    List<EdgeId> edges = [];
    int numTris = triIds.length ~/ 3;

    for (int i = 0; i < numTris; i++) {
      for (int j = 0; j < 3; j++) {
        int id0 = triIds[3 * i + j].toInt();
        int id1 = triIds[3 * i + (j + 1) % 3].toInt();
        edges.add(EdgeId(
          id0 : Math.min(id0, id1), 
          id1 : Math.max(id0, id1), 
          edgeNr : 3 * i + j
        ));
      }
    }

    // sort so common edges are next to each other

    edges.sort((a, b) => ((a.id0 < b.id0) || (a.id0 == b.id0 && a.id1 < b.id1)) ? -1 : 1);

    // find matchign edges

    List<int> neighbors = List.filled(3 * numTris,-1);

    int nr = 0;
    while (nr < edges.length) {
      EdgeId e0 = edges[nr];
      nr++;
      if (nr < edges.length) {
        EdgeId e1 = edges[nr];
        if (e0.id0 == e1.id0 && e0.id1 == e1.id1) {
          neighbors[e0.edgeNr] = e1.edgeNr;
          neighbors[e1.edgeNr] = e0.edgeNr;
        }
        nr++;
      }
    }

    return Int32Array.fromList(neighbors);
  }
}

// ------------------------------------------------------------------
class SoftObject{
  SoftObject(this.mesh, this.scene, [this.bendingCompliance = 0, this.stretchingCompliance = 0]);

  late Mesh mesh;
  late LineSegments edgeMesh;

  ClothMath math = ClothMath();
  late int numParticles;
  late Float32Array pos;
  late Float32Array prevPos;
  late Float32Array restPos;
  late Float32Array vel;
  late Float32Array invMass;
  double bendingCompliance;
  Scene scene;

  late Int32Array stretchingIds;
  late Int32Array bendingIds;
  late Float32Array stretchingLengths;
  late Float32Array bendingLengths;
  
  double stretchingCompliance;		
  Float32Array temp = Float32Array(4 * 3);
  Float32Array grads = Float32Array(4 * 3);

  double temperatue = 25; //in C
  double glassTransitionTemperature = 180;//in C

  void initPhysics([List<num>? triIds]){

  }

  void collision(){
    
  }

  void preSolve(double dt, List<double> gravity){

  }

  void solve(double dt){
    solveStretching(stretchingCompliance, dt);
    solveBending(bendingCompliance, dt);
  }

  void postSolve(double dt){

  }

  void solveStretching(double compliance, double dt){

  }

  void solveBending(double compliance, double dt){

  }

  void updateMeshes(){
    mesh.geometry!.computeVertexNormals();
    mesh.geometry!.attributes['position'].needsUpdate = true;
    mesh.geometry!.computeBoundingSphere();
  }
  void endFrame() {
    updateMeshes();
  }							
}