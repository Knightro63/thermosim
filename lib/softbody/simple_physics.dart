import 'dart:typed_data';
import 'package:three_js/three_js.dart' as three;
import 'dart:math' as math;
import 'package:three_js_helpers/three_js_helpers.dart';

class Collider{
  Collider(this.objects){
    for(final object in objects){
      three.BoundingBox boundBox = three.BoundingBox();
      boundBox.setFromObject(object);
      boundBox.min.scale(1.01);
      boundBox.max.scale(1.01);

      boundBoxes.add(boundBox);

      // BoxHelper boxHelper = BoxHelper(object);
      // object.add(boxHelper);

      // final helper = VertexNormalsHelper(object, 0.01, 0xffffff );
      // helpers.add(helper);
      // object.add(helper);
    }
  }

  List<VertexNormalsHelper> helpers = [];
  List<three.Object3D> objects;
  List<three.BoundingBox> boundBoxes = [];

  bool lift = false;
  double speed = 0.0012;
  double maxLift = 0.04;

  void move(){
    if(lift){
      for(int i = 0;i < objects.length;i++){
        if(objects[i].position.z < maxLift){
          objects[i].position.add( three.Vector3(0, 0, speed) );
          boundBoxes[i].min.add( three.Vector3(0, 0, speed) );
          boundBoxes[i].max.add( three.Vector3(0, 0, speed) );
          //helpers[i].update();
        }
        else{
          lift = false;
        }
      }
    }
  }
  bool boxContainsPoint(three.Vector3 point){
    for(final box in boundBoxes){
      if(box.containsPoint(point)){
        return true;
      }
    }

    return false;
  }
  bool objectContainsPoint(three.Vector3 point){
    three.Raycaster raycaster = three.Raycaster(point, three.Vector3(0,0,1));
    List<three.Intersection> intersects = raycaster.intersectObjects(objects, false);
    if (intersects.isNotEmpty)  {
      return true;
    }
    return false;
  }
  bool containsPoint(three.Vector3 point){
    return boxContainsPoint(point) && objectContainsPoint(point);
  }
}

class PhysicsScene{
  List<double> gravity = [0.0, 0.0, -9.81];
  double dt = 1.0 / 60.0;
  int numSubsteps =  5;
  bool paused = true;
  bool showEdges = true;
  List<SoftObject>objects = [];
  double temperatue = 210;
  bool vacuum = false;
  bool heaterOn = true;
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
  void vecSetZero(List<double> a, int anr){
    anr *= 3;
    a[anr++] = 0.0;
    a[anr++] = 0.0;
    a[anr]   = 0.0;
  }

  void vecScale(List<double> a,int anr, double scale) {
    anr *= 3;
    a[anr++] *= scale;
    a[anr++] *= scale;
    a[anr]   *= scale;
  }

  void vecCopy(List<double> a,int anr,List<double> b,int bnr) {
    anr *= 3; bnr *= 3;
    a[anr++] = b[bnr++]; 
    a[anr++] = b[bnr++]; 
    a[anr]   = b[bnr];
  }

  void vecAdd(List<double> a,int anr,List<double> b,int bnr, [double scale = 1.0]) {
    anr *= 3; bnr *= 3;
    a[anr++] += b[bnr++] * scale; 
    a[anr++] += b[bnr++] * scale; 
    a[anr]   += b[bnr] * scale;
  }
  void vecSub(List<double> a,int anr,List<double> b,int bnr, [double scale = 1.0]) {
    anr *= 3; bnr *= 3;
    a[anr++] -= b[bnr++] * scale; 
    a[anr++] -= b[bnr++] * scale; 
    a[anr]   -= b[bnr] * scale;
  }
  void vecSetDiff(List<double> dst,int dnr,List<double> a,int anr,List<double> b,int bnr, [double scale = 1.0]) {
    dnr *= 3; anr *= 3; bnr *= 3;
    dst[dnr++] = (a[anr++] - b[bnr++]) * scale;
    dst[dnr++] = (a[anr++] - b[bnr++]) * scale;
    dst[dnr]   = (a[anr] - b[bnr]) * scale;
  }

  double vecLengthSquared(List<double> a,int anr) {
    anr *= 3;
    double a0 = a[anr], a1 = a[anr + 1], a2 = a[anr + 2];
    return a0 * a0 + a1 * a1 + a2 * a2;
  }

  double vecDistSquared(List<double> a,int anr,List<double> b,int bnr) {
    anr *= 3; bnr *= 3;
    double a0 = a[anr] - b[bnr], 
      a1 = a[anr + 1] - b[bnr + 1], 
      a2 = a[anr + 2] - b[bnr + 2];
    return a0 * a0 + a1 * a1 + a2 * a2;
  }	

  double vecDot(List<double> a,int anr,List<double> b,int bnr) {
    anr *= 3; bnr *= 3;
    return a[anr] * b[bnr] + a[anr + 1] * b[bnr + 1] + a[anr + 2] * b[bnr + 2];
  }	

  void vecSetCross(List<double> a,int anr,List<double> b,int bnr, c,int cnr) {
    anr *= 3; bnr *= 3; cnr *= 3;
    a[anr++] = b[bnr + 1] * c[cnr + 2] - b[bnr + 2] * c[cnr + 1];
    a[anr++] = b[bnr + 2] * c[cnr + 0] - b[bnr + 0] * c[cnr + 2];
    a[anr]   = b[bnr + 0] * c[cnr + 1] - b[bnr + 1] * c[cnr + 0];
  }

  // ------------------------------------------------------------------
  Int32List findTriNeighbors(List<num> triIds) {
    // create common edges

    List<EdgeId> edges = [];
    int numTris = triIds.length ~/ 3;

    for (int i = 0; i < numTris; i++) {
      for (int j = 0; j < 3; j++) {
        int id0 = triIds[3 * i + j].toInt();
        int id1 = triIds[3 * i + (j + 1) % 3].toInt();
        edges.add(EdgeId(
          id0 : math.min(id0, id1), 
          id1 : math.max(id0, id1), 
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

    return Int32List.fromList(neighbors);
  }
}

class SoftBodyProperties{
  SoftBodyProperties({
    this.currentTemperatue = 25,
    this.glassTransitionTemperature = 180,
    // this.shapeMemoryTemperature = 210,
    this.heatTransferRate = 0.05,
    this.bendingCompliance = 0, 
    this.stretchingCompliance = 0,
    this.softeningTemp = 120
  });

  double currentTemperatue; //in C
  double glassTransitionTemperature;
  // double shapeMemoryTemperature;
  double heatTransferRate;
  double stretchingCompliance;
  double bendingCompliance;
  double softeningTemp;
}

// ------------------------------------------------------------------
abstract class SoftObject{
  SoftObject(this.mesh, this.collider);

  late three.Mesh mesh;
  late three.LineSegments edgeMesh;

  ClothMath math = ClothMath();
  late int numParticles;
  late Float32List pos;
  late Float32List prevPos;
  late Float32List restPos;
  late Float32List vel;
  late Float32List invMass;
  
  Collider collider;

  late Int32List stretchingIds;
  late Int32List bendingIds;
  late Float32List stretchingLengths;
  late Float32List bendingLengths;

	SoftBodyProperties properties = SoftBodyProperties();
  List<double> temp = Float32List(4 * 3);
  List<double> grads = Float32List(4 * 3);

  void initPhysics([List<num>? triIds]){}
  void collision(){}
  void vacuum(){}
  void preSolve(double dt, List<double> gravity){}

  void solve(double dt){
    solveStretching(properties.stretchingCompliance, dt);
    solveBending(properties.bendingCompliance, dt);
  }
  void heating(double ambientTemperature){
    if(properties.currentTemperatue < ambientTemperature){
      properties.currentTemperatue += properties.heatTransferRate*10;//properties.heatTransferRate*(16*16)*(0.125/)+ambientTemperature;
    }
    
    if(properties.currentTemperatue > properties.glassTransitionTemperature){
      if(properties.stretchingCompliance <= 0.1){
        properties.stretchingCompliance = 0.1;
      }
      else {
        properties.stretchingCompliance -= 0.005;
      }
    }
    else if(properties.currentTemperatue > properties.softeningTemp){
      properties.stretchingCompliance += 0.005;
    }
    else{
      properties.stretchingCompliance = 0;
    }
  }
  void postSolve(double dt){}
  void solveStretching(double compliance, double dt){}
  void solveBending(double compliance, double dt){}

  void updateMeshes(){
    mesh.geometry!.computeVertexNormals();
    mesh.geometry!.attributes['position'].needsUpdate = true;
    mesh.geometry!.computeBoundingSphere();
  }
  void endFrame() {
    updateMeshes();
  }							
}