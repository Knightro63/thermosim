import 'package:flutter_gl/flutter_gl.dart';
import 'package:three_dart/three_dart.dart' hide Texture, Color;
import 'simplePhysics.dart';
class SoftBodyPhysics{
  SoftBodyPhysics(this.scene,this.mesh){
    initPhysics();
  }

  Scene scene;
  Mesh mesh;
  bool gMouseDown = false;
  int timeFrames = 0;
  double timeSum = 0;	
  PhysicsScene gPhysicsScene = PhysicsScene();

  void changeBending(double value){
    for (int i = 0; i < gPhysicsScene.objects.length; i++){
      gPhysicsScene.objects[i].bendingCompliance = value;
    }
  }

  // ------------------------------------------------------------------
  void initPhysics() {
    SoftBody body = SoftBody(mesh, scene);
    gPhysicsScene.objects.add(body); 
  }

  // make browser to call us repeatedly -----------------------------------
  void update() {
    simulate();
  }
  void run() {
    //var button = document.getElementById('buttonRun');
    if (gPhysicsScene.paused){
      print("Stop");
    }
    else{
      print("Run");
    }
    gPhysicsScene.paused = !gPhysicsScene.paused;
  }
  void restart() {
    //location.reload();
  }
  // ------------------------------------------------------------------
  void simulate() {
    if (gPhysicsScene.paused){
      return;
    }

    int startTime = DateTime.now().millisecond;					
    double sdt = gPhysicsScene.dt / gPhysicsScene.numSubsteps;

    for (int step = 0; step < gPhysicsScene.numSubsteps; step++) {
      gPhysicsScene.objects[0].preSolve(sdt, gPhysicsScene.gravity);
      gPhysicsScene.objects[0].solve(sdt);
      gPhysicsScene.objects[0].postSolve(sdt);
    }

    for (int i = 0; i < gPhysicsScene.objects.length; i++){
      gPhysicsScene.objects[i].endFrame();
    }

    int endTime = DateTime.now().millisecond;
    timeSum += endTime - startTime; 
    timeFrames++;

    if (timeFrames > 10) {
      timeSum /= timeFrames;
      //document.getElementById("ms").innerHTML = timeSum.toStringAsFixed(3);		
      timeFrames = 0;
      timeSum = 0;
    }				
  }
}
// ------------------------------------------------------------------
class SoftBody extends SoftObject{
  SoftBody(Mesh mesh, Scene scene, [double bendingCompliance = 1000, double stretchingCompliance = 0]):super(mesh,scene,bendingCompliance,stretchingCompliance){
    this.mesh = mesh;
    this.scene = scene;
    this.bendingCompliance = bendingCompliance;
    this.stretchingCompliance = stretchingCompliance;

    Float32Array vertices = mesh.geometry!.attributes['position'].array;
    numParticles = vertices.length ~/ 3;
    pos = vertices;
    prevPos = vertices;
    vel = Float32Array(3 * numParticles);

    List<num> lis = mesh.geometry!.getIndex()!.array.toDartList();
    tetIds = lis;
    Int32Array neighbors = math.findTriNeighbors(lis);
    numTets = lis.length ~/3; //tetMesh.tetIds.length / 4
    restVol = Float32Array(numTets);
    	
    invMass = Float32Array(numParticles);
    temp = Float32Array(4 * 3);
    grads = Float32Array(4 * 3);

    List<int> edges = [];

    for (int i = 0; i < numTets; i++) {
      for (int j = 0; j < 3; j++) {
        int id0 = lis[3 * i + j].toInt();
        int id1 = lis[3 * i + (j + 1) % 3].toInt();

        // each edge only once
        int n = neighbors[3 * i + j];
        if (n < 0 || id0 < id1) {
          edges.add(id0);
          edges.add(id1);
        }
      }
    }

    edgeIds = edges;
    edgeLengths = Float32Array(edgeIds.length ~/ 2);

    initPhysics();

    volIdOrder = [[1,2,0], [2,1,0], [0,1,2]];
  }

  late Float32Array edgeLengths;
  late Float32Array restVol;
  late List<num> tetIds;
  late List<int> edgeIds;
  late List<List<int>> volIdOrder;
  late int numTets;

  void translate(x, y, z){
    for (int i = 0; i < numParticles; i++) {
      math.vecAdd(pos,i, [x,y,z],0);
      math.vecAdd(prevPos,i, [x,y,z],0);
    }
  }

  double getTetVolume(int nr) {
    int id0 = tetIds[3 * nr].toInt();
    int id1 = tetIds[3 * nr + 1].toInt();
    int id2 = tetIds[3 * nr + 2].toInt();
    //int id3 = tetIds[4 * nr + 3].toInt();
    math.vecSetDiff(temp,0, pos,id1, pos,id0);
    math.vecSetDiff(temp,1, pos,id2, pos,id0);
    //math.vecSetDiff(temp,2, pos,id3, pos,id0);
    math.vecSetCross(temp,3, temp,0, temp,1);
    return math.vecDot(temp,3, temp,2) / 6.0;
  }
  void squash() {
    for (int i = 0; i < numParticles; i++) {
      pos[3 * i + 1] = 0.5;
    }
    updateMeshes();
  }
  @override
  void initPhysics([List<num>? r]){
    for (int i = 0; i < numTets; i++) {
      double vol = getTetVolume(i);
      restVol[i] = vol;
      double pInvMass = vol > 0.0 ? 1.0 / (vol / 4.0) : 0.0;
      invMass[tetIds[3 * i].toInt()] += pInvMass;
      invMass[tetIds[3 * i + 1].toInt()] += pInvMass;
      invMass[tetIds[3 * i + 2].toInt()] += pInvMass;
      //invMass[tetIds[4 * i + 3].toInt()] += pInvMass;
    }
    for (int i = 0; i < edgeLengths.length; i++) {
      int id0 = edgeIds[2 * i];
      int id1 = edgeIds[2 * i + 1];
      edgeLengths[i] = Math.sqrt(math.vecDistSquared(pos,id0, pos,id1));
    }
  }

  @override
  void preSolve(double dt, List<double> gravity){
    for (var i = 0; i < numParticles; i++) {
      if (invMass[i] == 0.0){
        continue;
      }
      math.vecAdd(vel,i, gravity,0, dt);
      math.vecCopy(prevPos,i, pos,i);
      math.vecAdd(pos,i, vel,i, dt);
      double y = pos[3 * i + 1];
      if (y < 0.0) {
        math.vecCopy(pos,i, prevPos,i);
        pos[3 * i + 1] = 0.0;
      }
    }
  }
  @override
  void postSolve(double dt){
    for (var i = 0; i < numParticles; i++) {
      if (invMass[i] == 0.0){
        continue;
      }
      math.vecSetDiff(vel,i, pos,i, prevPos,i, 1.0 / dt);
    }
    updateMeshes();
  }
  @override
  void solveStretching(double compliance, double dt) {
    double alpha = compliance / dt /dt;

    for (int i = 0; i < edgeLengths.length; i++) {
      int id0 = edgeIds[2 * i];
      int id1 = edgeIds[2 * i + 1];
      double w0 = invMass[id0];
      double w1 = invMass[id1];
      double w = w0 + w1;
      if (w == 0.0){
        continue;
      }

      math.vecSetDiff(grads,0, pos,id0, pos,id1);
      double len = Math.sqrt(math.vecLengthSquared(grads,0));
      if (len == 0.0){
        continue;
      }
      math.vecScale(grads,0, 1.0 / len);
      double restLen = edgeLengths[i];
      double C = len - restLen;
      double s = -C / (w + alpha);
      math.vecAdd(pos,id0, grads,0, s * w0);
      math.vecAdd(pos,id1, grads,0, -s * w1);
    }
  }
  @override
  void solveBending(double compliance, double dt) {
    double alpha = compliance / dt /dt;

    for (int i = 0; i < numTets; i++) {
      double w = 0.0;
      
      for (int j = 0; j < 3; j++) {
        int id0 = tetIds[3 * i + volIdOrder[j][0]].toInt();
        int id1 = tetIds[3 * i + volIdOrder[j][1]].toInt();
        int id2 = tetIds[3 * i + volIdOrder[j][2]].toInt();

        math.vecSetDiff(temp,0, pos,id1, pos,id0);
        math.vecSetDiff(temp,1, pos,id2, pos,id0);
        math.vecSetCross(grads,j, temp,0, temp,1);
        math.vecScale(grads,j, 1.0/6.0);

        w += invMass[tetIds[3 * i + j].toInt()] * math.vecLengthSquared(grads,j);
      }
      if (w == 0.0){
        continue;
      }

      double vol = getTetVolume(i);
      double restVol = this.restVol[i];
      double C = vol - restVol;
      double s = -C / (w + alpha);

      for (int j = 0; j < 4; j++) {
        int id = tetIds[4 * i + j].toInt();
        math.vecAdd(pos,id, grads,j, s * invMass[id]);
      }
    }
  }				
}