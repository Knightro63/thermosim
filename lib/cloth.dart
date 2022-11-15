import 'package:flutter_gl/flutter_gl.dart';
import 'package:three_dart/three_dart.dart' hide Texture, Color;
import 'simplePhysics.dart';

class ClothProperties{
  double glassTransitionTemperature = 180;
  double softeningTemp = 120;
}

class ClothPhysics{
  ClothPhysics(this.scene,this.mesh){
    initPhysics();
  }

  Scene scene;
  Mesh mesh;
  bool gMouseDown = false;
  int timeFrames = 0;
  double timeSum = 0;	
  PhysicsScene gPhysicsScene = PhysicsScene();
  ClothProperties properties = ClothProperties();

  void changeBending(double value){
    for (int i = 0; i < gPhysicsScene.objects.length; i++){
      gPhysicsScene.objects[i].bendingCompliance = value;
    }
  }

  // ------------------------------------------------------------------
  void initPhysics() {
    Cloth body = Cloth(mesh, scene, properties);
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
  void simulate([double bendingCompliance = 0, double stretchingCompliance = 0]) {
    if (gPhysicsScene.paused || (properties.softeningTemp > gPhysicsScene.temperatue)){
      return;
    }

    gPhysicsScene.objects[0].bendingCompliance = bendingCompliance;
    gPhysicsScene.objects[0].stretchingCompliance = stretchingCompliance;
    gPhysicsScene.objects[0].temperatue = gPhysicsScene.temperatue;
     
    int startTime = DateTime.now().millisecond;					
    double sdt = gPhysicsScene.dt / gPhysicsScene.numSubsteps;
    gPhysicsScene.objects[0].collision();
    for (int step = 0; step < gPhysicsScene.numSubsteps; step++) {
      gPhysicsScene.objects[0].preSolve(sdt, gPhysicsScene.gravity);
      gPhysicsScene.objects[0].solve(sdt);
      gPhysicsScene.objects[0].postSolve(sdt);
    }

    gPhysicsScene.objects[0].endFrame();

    int endTime = DateTime.now().millisecond;
    timeSum += endTime - startTime; 
    timeFrames++;

    if (timeFrames > 2) {
      timeSum /= timeFrames;
      //document.getElementById("ms").innerHTML = timeSum.toStringAsFixed(3);		
      timeFrames = 0;
      timeSum = 0;
    }				
  }
}

// ------------------------------------------------------------------
class Cloth extends SoftObject{
  Cloth(Mesh mesh, Scene scene, this.properties,[double bendingCompliance = 0, double stretchingCompliance = 0]):super(mesh,scene,bendingCompliance,stretchingCompliance){
    this.mesh = mesh;
    this.scene = scene;
    this.bendingCompliance = bendingCompliance;
    this.stretchingCompliance = stretchingCompliance;
    
    // particles
    Float32Array vertices = mesh.geometry!.attributes['position'].array;
    numParticles = vertices.length ~/ 3;
    pos = vertices;
    prevPos = vertices;
    restPos = vertices;
    vel = Float32Array(3 * numParticles);
    invMass = Float32Array(numParticles);

    // stretching and bending constraints
    List<num> lis = mesh.geometry!.getIndex()!.array.toDartList();
    Int32Array neighbors = math.findTriNeighbors(lis);
    int numTris = lis.length ~/ 3;
    List<int> edgeIds = [];
    List<int> triPairIds = [];

    for (int i = 0; i < numTris; i++) {
      for (int j = 0; j < 3; j++) {
        int id0 = lis[3 * i + j].toInt();
        int id1 = lis[3 * i + (j + 1) % 3].toInt();

        // each edge only once
        int n = neighbors[3 * i + j];
        if (n < 0 || id0 < id1) {
          edgeIds.add(id0);
          edgeIds.add(id1);
        }
        // tri pair
        if (n >= 0) {
          // opposite ids
          int ni = Math.floor(n / 3);
          int nj = n % 3;
          int id2 = lis[3 * i + (j + 2) % 3].toInt();
          int id3 = lis[3 * ni + (nj + 2) % 3].toInt();
          triPairIds.add(id0);
          triPairIds.add(id1);
          triPairIds.add(id2);
          triPairIds.add(id3);
        }
      }
    }

    stretchingIds = Int32Array.fromList(edgeIds);
    bendingIds = Int32Array.fromList(triPairIds);
    stretchingLengths = Float32Array(stretchingIds.length ~/ 2);
    bendingLengths = Float32Array(bendingIds.length ~/ 4);

    updateMeshes();
    initPhysics(lis);
  }

  late ClothProperties properties;

  @override
  void initPhysics([List<num>? triIds]){
    int numTris = triIds!.length ~/ 3;
    List<double> e0 = [0.0, 0.0, 0.0];
    List<double> e1 = [0.0, 0.0, 0.0];
    List<double> c = [0.0, 0.0, 0.0];

    for (int i = 0; i < numTris; i++) {
      int id0 = triIds[3 * i].toInt();
      int id1 = triIds[3 * i + 1].toInt();
      int id2 = triIds[3 * i + 2].toInt();
      math.vecSetDiff(e0,0,pos,id1,pos,id0);
      math.vecSetDiff(e1,0,pos,id2,pos,id0);
      math.vecSetCross(c,0, e0,0, e1,0);

      double A = 0.5 * Math.sqrt(math.vecLengthSquared(c,0));
      double pInvMass = A > 0.0 ? 1.0 / A / 10.0 : 0.0;
      invMass[id0] += pInvMass;
      invMass[id1] += pInvMass;
      invMass[id2] += pInvMass;
    }

    for(int i = 0; i < stretchingLengths.length; i++) {
      int id0 = stretchingIds[2 * i];
      int id1 = stretchingIds[2 * i + 1];
      stretchingLengths[i] = Math.sqrt(math.vecDistSquared(pos,id0,pos,id1));
    }

    for (int i = 0; i < bendingLengths.length; i++) {
      int id0 = bendingIds[4 * i + 2];
      int id1 = bendingIds[4 * i + 3];
      bendingLengths[i] = Math.sqrt(math.vecDistSquared(pos,id0,pos,id1));
    }

    int count = Math.sqrt(numParticles).toInt();
    for (int i = 0; i < numParticles; i++) {
      if(i <= count || i%count == 0 || i > numParticles-count || (i+1)%count == 0){
        invMass[i] = 0.0;
      }
    }
  }
  @override
  void collision(){
      //var originPoint = paddle.position.clone();
      for (int vertexIndex = 0; vertexIndex < pos.length; vertexIndex+=3) {
        Vector3 origin = Vector3(pos[vertexIndex],pos[vertexIndex+1],pos[vertexIndex+2]);
          Raycaster ray = Raycaster(origin);
          List<Intersection> collisionResults = ray.intersectObjects( [scene.children[0],scene.children[1],scene.children[2],scene.children[3],scene.children[5]],false );
          if (collisionResults.isNotEmpty)  {
            print('hit');
          }
      } 
  }

  @override
  void preSolve(double dt, List<double> gravity){
    for (int i = 0; i < numParticles; i++) {
      if (invMass[i] == 0.0){
        continue;
      }
      math.vecAdd(vel,i, gravity,0, dt);
      math.vecCopy(prevPos,i, pos,i);
      math.vecAdd(pos,i, vel,i, dt);
    }
  }

  @override
  void postSolve(double dt){
    for (int i = 0; i < numParticles; i++) {
      if (invMass[i] == 0.0){
        continue;
      }
      math.vecSetDiff(vel,i, pos,i, prevPos,i, 1.0 / dt);
    }
  }
  @override
  void solveStretching(double compliance, double dt) {
    double alpha = compliance / dt/dt;

    for (int i = 0; i < stretchingLengths.length; i++) {
      int id0 = stretchingIds[2 * i];
      int id1 = stretchingIds[2 * i + 1];
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
      math.vecScale(grads,0, 1 / len);
      double restLen = stretchingLengths[i];
      double C = len - restLen;
      double s = -C / (w + alpha);
      math.vecAdd(pos,id0, grads,0, s * w0);
      math.vecAdd(pos,id1, grads,0, -s * w1);
    }
  }
  @override
  void solveBending(double compliance, double dt) {
    double alpha = compliance / dt /dt;

    for (int i = 0; i < bendingLengths.length; i++) {
      int id0 = bendingIds[4 * i + 2];
      int id1 = bendingIds[4 * i + 3];
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
      double restLen = bendingLengths[i];
      double C = len - restLen;
      double s = -C / (w + alpha);
      math.vecAdd(pos,id0, grads,0, s * w0);
      math.vecAdd(pos,id1, grads,0, -s * w1);
    }
  }		
}