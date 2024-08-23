import 'dart:typed_data';
import 'dart:math';
import 'package:three_js/three_js.dart' as three;
import 'simple_physics.dart';


class ClothPhysics{
  ClothPhysics(this.collider,this.mesh){
    initPhysics();
  }

  Collider collider;
  three.Mesh mesh;
  bool gMouseDown = false;
  int timeFrames = 0;
  double timeSum = 0;	
  PhysicsScene gPhysicsScene = PhysicsScene();

  void changeBending(double value){
    for (int i = 0; i < gPhysicsScene.objects.length; i++){
      gPhysicsScene.objects[i].properties.bendingCompliance = value;
    }
  }

  void changeStretching(double value){
    for (int i = 0; i < gPhysicsScene.objects.length; i++){
      gPhysicsScene.objects[i].properties.stretchingCompliance = value;
    }
  }

  // ------------------------------------------------------------------
  void initPhysics() {
    Cloth body = Cloth(mesh, collider);
    gPhysicsScene.objects.add(body); 
  }

  void restart() {
    //location.reload();
  }

  // ------------------------------------------------------------------
  void simulate() {
    if (gPhysicsScene.paused){
      return;
    }
    if(gPhysicsScene.heaterOn){
      gPhysicsScene.objects[0].heating(gPhysicsScene.temperatue);
    }
    if(gPhysicsScene.objects[0].properties.softeningTemp > gPhysicsScene.objects[0].properties.currentTemperatue){
      return;
    }

    int startTime = DateTime.now().millisecond;					
    double sdt = gPhysicsScene.dt / gPhysicsScene.numSubsteps;

    
    if(gPhysicsScene.vacuum){
      gPhysicsScene.objects[0].vacuum();
    }
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
      timeFrames = 0;
      timeSum = 0;
    }				
  }
}

// ------------------------------------------------------------------
class Cloth extends SoftObject{
  Cloth(three.Mesh mesh, Collider collider):super(mesh,collider){
    // particles
    three.Float32Array vertices = mesh.geometry!.attributes['position'].array;
    numParticles = vertices.length ~/ 3;
    pos = vertices.toDartList();
    prevPos = vertices.toDartList();
    //restPos = vertices.toDartList();
    vel = Float32List(3 * numParticles);
    invMass = Float32List(numParticles);

    // stretching and bending constraints
    List<num> lis = mesh.geometry!.getIndex()!.array.toDartList();
    Int32List neighbors = math.findTriNeighbors(lis);
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
          int ni = (n / 3).floor();
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

    stretchingIds = Int32List.fromList(edgeIds);
    bendingIds = Int32List.fromList(triPairIds);
    stretchingLengths = Float32List(stretchingIds.length ~/ 2);
    bendingLengths = Float32List(bendingIds.length ~/ 4);

    updateMeshes();
    initPhysics(lis);
  }

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

      double A = 0.5 * sqrt(math.vecLengthSquared(c,0));
      double pInvMass = A > 0.0 ? 1.0 / A / 10.0 : 0.0;
      invMass[id0] += pInvMass;
      invMass[id1] += pInvMass;
      invMass[id2] += pInvMass;
    }

    for(int i = 0; i < stretchingLengths.length; i++) {
      int id0 = stretchingIds[2 * i];
      int id1 = stretchingIds[2 * i + 1];
      stretchingLengths[i] = sqrt(math.vecDistSquared(pos,id0,pos,id1))/2;
    }

    for (int i = 0; i < bendingLengths.length; i++) {
      int id0 = bendingIds[4 * i + 2];
      int id1 = bendingIds[4 * i + 3];
      bendingLengths[i] = sqrt(math.vecDistSquared(pos,id0,pos,id1))/2;
    }

    int count = sqrt(numParticles).toInt();
    for (int i = 0; i < numParticles; i++) {
      if(i <= count || i%count == 0 || i > numParticles-count || (i+1)%count == 0){
        invMass[i] = 0.0;
      }
    }
  }
  @override
  void collision(){
    //var originPoint = paddle.position.clone();
    for (int i = 0; i < numParticles; i++) {
      three.Vector3 point = three.Vector3(pos[i*3], pos[(i*3)+1], pos[(i*3)+2]);

      if (collider.boxContainsPoint(point)) {
        if (invMass[i] == 0.0 && collider.lift) {
          pos[(i*3)+2] += collider.speed;
          continue;
        } 
        else if (invMass[i] == 0.0) {
          continue;
        }
        if(collider.objectContainsPoint(point)){
          invMass[i] = 0.0;
          pos[(i*3)+2] += collider.speed;
        }
      }

      // if (invMass[i] == 0.0 && collider.lift) {
      //   pos[(i*3)+2] += collider.speed;
      //   continue;
      // }
      // else if (invMass[i] == 0.0) {
      //   continue;
      // }
      // if (collider.containsPoint(point)) {
      //   invMass[i] = 0.0;
      //   pos[(i*3)+2] += collider.speed;
      // }
    } 
  }

  @override
  void vacuum(){
    for (int i = 0; i < numParticles; i++) {
      if (invMass[i] == 0.0){
        continue;
      }
      //properties.currentTemperatue -= 0.01;
      three.Vector3 point = three.Vector3(pos[i*3], pos[(i*3)+1], pos[(i*3)+2]);

      final three.Vector3 forceToCenter = three.Vector3();
      //math.vecSub(pos, vertexIndex~/3, [0,0,0.000002], 0,invMass[vertexIndex~/3]);
      forceToCenter.sub2(three.Vector3(0,0,-0.02), point);
      //forceToCenter.y -= ballSize;
      forceToCenter.normalize();
      forceToCenter.scale(1/(invMass[i]*100));

      point.add(three.Vector3().setFrom(forceToCenter).scale(invMass[i]));
      
      if (collider.containsPoint(point)) {
        invMass[i] = 0.0;
      }

      if(invMass[i] != 0.0){
        math.vecCopy(pos, i, [point.x,point.y,point.z], 0);
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
    double alpha = compliance / dt /dt;

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
      double len = sqrt(math.vecLengthSquared(grads,0));
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

      math.vecSetDiff(grads,0, pos, id0, pos,id1);
      double len = sqrt(math.vecLengthSquared(grads,0));
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
	