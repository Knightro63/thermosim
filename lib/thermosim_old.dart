import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:three_js_helpers/box_helper.dart';
import 'package:three_js/three_js.dart' as three;
import 'package:three_js_geometry/three_js_geometry.dart';
import 'package:three_js_helpers/plane_helper.dart';

class Thermosim extends StatefulWidget {
  const Thermosim({super.key});

  @override
  State<Thermosim> createState() => _ThermosimState();
}

class _ThermosimState extends State<Thermosim> {
  late three.ThreeJS threeJs;
  late three.OrbitControls controls;

  late Cloth cloth;
  late ParametricGeometry clothGeo;
  late three.Mesh mold;
  late three.Object3D buck;

  final double ballSize = 50.0;

  // Simulation Constants
  double grav = 981 * 1.4;
  final gravity = three.Vector3(0, -981 * 1, 0).scale(0.01);
  double trimstepSq = (18 / 1000) * (18 / 1000);
  final diff = three.Vector3();
  int k_constant = 38;

  // Debug
  List<three.Object3D> debugSpheres = [];

  bool liftBuck = false;
  bool pauseSim = true;
  double liftSpeed = 0.12;
  bool testOnce = false;
  bool vacuum = false;

  int index = 0;
  int testIndex = 0;
  int color = 0;
  bool once = false;
  bool testing = false;
  bool firstCollide = false;
  three.BoundingBox boundBox = three.BoundingBox();

  @override
  void initState() {
    threeJs = three.ThreeJS(
      onSetupComplete: (){setState(() {});},
      setup: setup,
    );

    super.initState();
  }
  @override
  void dispose() {
    threeJs.dispose();
    three.loading.clear();
    controls.dispose(); 
    super.dispose();
  }


  // this function sets up the threeJs.scene
  Future<void> setup() async {
    cloth = Cloth(xSegments, ySegments);
    threeJs.scene = three.Scene();

    // set up threeJs.camera and controls
    threeJs.camera = three.Camera();
    threeJs.camera = three.PerspectiveCamera(60, threeJs.width / threeJs.height, 1, 10000);
    threeJs.camera.position.setValues(0, 160, 500);
    threeJs.camera.lookAt(threeJs.scene.position);

    controls = three.OrbitControls(threeJs.camera, threeJs.globalKey);
    controls.target.setValues(0, 20, 0);
    controls.update();

    // add lighting
    threeJs.scene.add(three.AmbientLight(0x3D4143));
    three.DirectionalLight light = three.DirectionalLight(0xffffff, 1.4);
    light.position.setValues(300, 1000, 500);
    light.target!.position.setValues(0, 0, 0);
    threeJs.scene.add(light);

    // background
    three.BufferGeometry buffgeoBack = IcosahedronGeometry(3000, 2);
    three.Mesh back = three.Mesh(buffgeoBack, three.MeshLambertMaterial());
    threeJs.scene.add(back);

    // creating a sphere in three_dart
    //three.SphereGeometry sphereGeo = three.SphereGeometry(ballSize, 32, 16);
    three.Material sphereMat = three.MeshPhongMaterial.fromMap({'color': 0xffffff});//, 'wireframe': true});

    // import obj
    three.OBJLoader objLoader = three.OBJLoader(null);
    three.Object3D object = (await objLoader.fromAsset('assets/obj/Serenity_key_Hand_Left.obj'))!;

    // using scale might break things
    // object.scale.set(50, 50, 50);
    object.children[0].geometry!;
    object.updateMatrix();

    buck = object;

    // set up bounding box
    buck.children[0].geometry!.computeBoundingBox();
    three.Vector3 boxMin = buck.children[0].geometry!.boundingBox!.min;
    three.Vector3 boxMax = buck.children[0].geometry!.boundingBox!.max;
    boundBox.set(boxMin.scale(1.01), boxMax.scale(1.01));

    BoxHelper boxHelper = BoxHelper(buck);
    buck.add(boxHelper);

    object.children[0].material = sphereMat;

    threeJs.scene.add(object);

    // texture loader for uv grid
    final loader = three.TextureLoader();
    three.Texture map = (await loader.fromAsset('assets/textures/uv_grid_opengl.jpg'))!;

    // creating a Cloth
    clothGeo = ParametricGeometry(clothFunction, xSegments, ySegments);
    three.Material clothMat = three.MeshLambertMaterial.fromMap({
      "map": map,
      // "color": 0x00ff00,
      "side": three.DoubleSide,
      // "alphaTest": 0.5
    });
    three.Mesh clothMesh = three.Mesh(clothGeo, clothMat);
    threeJs.scene.add(clothMesh);

    threeJs.addAnimationEvent((dt){
      animate();
    });
  }

  void animate() {
    if (!pauseSim) {
      if (liftBuck) {
        if (buck.position.y > 150) liftBuck = false;
        buck.position.y += liftSpeed;
        boundBox.min.add( three.Vector3(0, liftSpeed, 0) );
        boundBox.max.add( three.Vector3(0, liftSpeed, 0) );
        buck.updateMatrix();
      }

      final List<Particle> p = cloth.particles;

      threadSimulate(p);
      //simulate(p);

      for (int i = 0, il = p.length; i < il; i++) {
        // if (cloth.rigid[i]) continue;
        final three.Vector3 v = p[i].position;
        clothGeo.attributes["position"].setXYZ(i, v.x, v.y, v.z);
      }

      clothGeo.attributes["position"].needsUpdate = true;

      clothGeo.computeVertexNormals();
    }
  }

  void simulate(List<Particle> particles) {
    if (testOnce == true) {
      three.Material matVertex1 = three.MeshBasicMaterial.fromMap({"color": 0xff0000});
      three.SphereGeometry vertex1 = three.SphereGeometry(1, 8, 8);

      // vertex1.setAttribute('positions', three.Float32BufferAttribute(verts, 3));
      three.Mesh testSphere = three.Mesh(vertex1, matVertex1);
      // testSphere.position = cloth.constraints[1950][0].position;
      testSphere.position = particles[1097].position;
      threeJs.scene.add(testSphere);

      // three.Mesh testSphere2 = three.Mesh(vertex1, matVertex1);
      // testSphere.position = particles[2500].position;
      // threeJs.scene.add(testSphere2);

      testOnce = true;
    }

    // adds gravity to cloth
    for (int i = 0, il = particles.length; i < il; i++) {
      final Particle particle = particles[i];
      final three.Vector3 adjPrev = three.Vector3();
      adjPrev.sub2(particle.defPrev, particle.position);
      adjPrev.normalize();

      particle.defPrev.setFrom(particle.position.clone().addScaled(adjPrev, 2));

      if (particle.rigid) continue;
      final three.Vector3 restoreVector = three.Vector3(0, 0, 0);

      for (Particle constraintParticle in particle.constraints) {
        three.Vector3 temp = three.Vector3(0, 0, 0);
        temp.sub2(constraintParticle.position, particle.position);
        final double length = temp.length;
        final double restoreForce = length * k_constant;
        temp.normalize().scale(restoreForce);
        restoreVector.add(temp);
        // print(restoreVector.toJSON());
      }

      if (restoreVector.y.abs() > gravity.y.abs()) continue;
      final three.Vector3 netForce = three.Vector3();

      netForce.add(gravity);
      netForce.y = netForce.y + restoreVector.y;

      particle.addForce(netForce);
      particle.integrate(trimstepSq);
      if (particle.position.y < boundBox.min.y) particle.rigid = true;
    }

    // this vacuums
    if (vacuum) {
      for (int i = 0, il = particles.length; i < il; i++) {
        final Particle particle = particles[i];
        if (particle.rigid) continue;

        final three.Vector3 forceToCenter = three.Vector3();
        forceToCenter.sub2(buck.position.clone()..y -= 20, particle.position);
        forceToCenter.y -= ballSize;
        forceToCenter.normalize();
        forceToCenter.scale(1000);
        particle.addForce(forceToCenter);
        particle.integrate(trimstepSq);
        if (particle.position.y < boundBox.min.y) particle.rigid = true;
      }
    }

    // detect collisions
    detectCollisions(particles);

    // contraints for cloth
    final constraints = cloth.constraints;
    final int il = constraints.length;

    // satisfy constraints of the cloth/plastic sheet
    for (int i = 0; i < il; i++) {
      final List constraint = constraints[i];
      satisfyConstraints(constraint[0], constraint[1], constraint[2]);
    }

    // old collision detection - only worked for spheres
    // for (int i = 0, il = particles.length; i < il; i++) {
    //   Particle particle = particles[i];
    //   // if (particle.rigid) continue;
    //   three.Vector3 pos = particle.position;

    //   // gets current particle's pos and subtracts it from the ball's position.
    //   // if the length of that vector is smaller than the radius of the
    //   // ball, we have collided
    //   diff.sub2(pos, buck.position);

    //   if (diff.length() < ballSize) {
    //     // the ball and the cloth have collided
    //     // copy the ball's postion and add the difference/distance that the
    //     // cloth traveled into the ball
    //     diff.normalize();
    //     if (particle.rigid) {
    //       diff.x = 0;
    //       // diff.y = 0;
    //       diff.z = 0;
    //     } else {
    //       particle.rigid = true;
    //     }

    //     pos.add(diff);
    //   }
    // }
  }

  void splitSim() async {
    final particles = cloth.particles;
    List<Particle> p1 = [];
    List<Particle> p2 = [];
  }

  // this should take in a sublist of total particles
  // and return their updated states
  void threadSimulate(List<Particle> particles) {
    // adds gravity to cloth
    for (int i = 0, il = particles.length; i < il; i++) {
      final particle = particles[i];
      three.Vector3 adjPrev = three.Vector3();
      adjPrev.sub2(particle.defPrev, particle.position);
      adjPrev.normalize();

      particle.defPrev.setFrom(particle.position.clone().addScaled(adjPrev, 2));

      if (particle.rigid) continue;
      three.Vector3 restoreVector = three.Vector3(0, 0, 0);

      for (Particle constraintParticle in particle.constraints) {
        three.Vector3 temp = three.Vector3(0, 0, 0);
        temp.sub2(constraintParticle.position, particle.position);
        double length = temp.length;
        double restoreForce = length * k_constant;
        temp.normalize().scale(restoreForce);
        restoreVector.add(temp);
        // print(restoreVector.toJSON());
      }

      if (restoreVector.y.abs() > gravity.y.abs()) continue;
      three.Vector3 netForce = three.Vector3();

      netForce.add(gravity);
      netForce.y = netForce.y + restoreVector.y;

      particle.addForce(netForce);
      particle.integrate(trimstepSq);
      if (particle.position.y < boundBox.min.y) particle.rigid = true;
    }

    if (vacuum) {
      for (int i = 0, il = particles.length; i < il; i++) {
        final particle = particles[i];
        if (particle.rigid) continue;

        three.Vector3 forceToCenter = three.Vector3();
        forceToCenter.sub2(
            buck.position.clone()..y -= 20, particle.position);
        forceToCenter.y -= ballSize;
        forceToCenter.normalize();
        forceToCenter.scale(1000);
        particle.addForce(forceToCenter);
        particle.integrate(trimstepSq);
        if (particle.position.y < boundBox.min.y) particle.rigid = true;
      }
    }

    detectCollisions(particles);
  }

  void detectCollisions(List<Particle> particleList) {
    List allVerts = (buck.children[0].geometry!.getAttributeFromString('position')
            as three.BufferAttribute)
        .array
        .toDartList();

    for (int i = 0; i < particleList.length; i++) {
      Particle currParticle = particleList[i];

      if (boundBox.containsPoint(currParticle.position)) {
        firstCollide = true;
        if (currParticle.rigid && liftBuck) {
          currParticle.position.y += liftSpeed;
          continue;
        } else if (currParticle.rigid) {
          continue;
        }

        bool particleCollided = false;

        for (int vertIndex = 0; vertIndex < allVerts.length; vertIndex += 9) {
          // create vertex 1 and get global vertex
          three.Vector3 vert1 = three.Vector3(allVerts[vertIndex],
              allVerts[vertIndex + 1], allVerts[vertIndex + 2]);
          vert1 = buck.children[0].localToWorld(vert1);

          // create vertex 2 and get global vertex
          three.Vector3 vert2 = three.Vector3(allVerts[vertIndex + 3],
              allVerts[vertIndex + 4], allVerts[vertIndex + 5]);
          vert2 = buck.children[0].localToWorld(vert2);

          // create vertex 3 and get global vertex
          three.Vector3 vert3 = three.Vector3(allVerts[vertIndex + 6],
              allVerts[vertIndex + 7], allVerts[vertIndex + 8]);
          vert3 = buck.children[0].localToWorld(vert3);

          // create two vectors to hold the vectors between
          // the points of the triangle
          three.Vector3 vert12 = three.Vector3();
          three.Vector3 vert13 = three.Vector3();

          // perform the vector calculation
          vert12.sub2(vert2, vert1);
          vert13.sub2(vert3, vert1);

          // find normal of plane from the
          // three points by doing cross product
          // and normalize the vector
          three.Vector3 normal = three.Vector3();
          normal.cross2(vert12, vert13);

          // calculate the distances from the plane
          three.Vector3 distanceVector = three.Vector3();
          num distanceA = distanceVector
              .sub2(currParticle.defPrev, vert1)
              .dot(normal);

          num distanceB = distanceVector
              .sub2(currParticle.position, vert1)
              .dot(normal);

          // check if there exists an intersection point
          // if the two distances are opposite signs
          // then the two points are on opposite sides of
          // the plane created by the three vertices in the
          // triangle
          // print('distanceA $distanceA');
          // print('distanceB $distanceB');
          if ((distanceA > 0 && distanceB > 0)) {
            // debugSpheres.add(createSphere(currParticle.position, 0xFF0000));
            continue;
          }

          // check to see if we are really close on the negative side of a plane
          if (distanceA < 0 && distanceB < 0) {
            if (distanceA < 5 || distanceB < 5) {
              continue;
            } else {
              print('fix - close to negative side');
              // debugSpheres.add(createSphere(currParticle.position, 0xFF0000));
              // currParticle.defPrev
              //     .add(currParticle.defPrev.clone().negate().scale(2));
              // debugSpheres.add(createSphere(currParticle.position, 0xCCCCCC));
              currParticle.rigid = true;
              continue;
            }
          }

          // plane equation used for debugging
          three.Plane planeTest = three.Plane();
          planeTest.setFromNormalAndCoplanarPoint(normal, vert1);

          // create vectors to project point onto the plane
          // helps with calculations and tolerances maybe?
          three.Vector3 intersectionPoint = three.Vector3();
          three.Vector3 tempPos = three.Vector3();
          three.Vector3 tempDefPos = three.Vector3();

          tempPos.setFrom(currParticle.position);
          tempDefPos.setFrom(currParticle.defPrev);
          intersectionPoint.sub2(tempPos.scale(distanceA),
              tempDefPos.scale(distanceB));

          // this might be causing issues
          intersectionPoint.divideScalar(distanceA - distanceB);

          // project point onto plane
          three.Vector3 v1intPoint = three.Vector3();
          v1intPoint.sub2(vert1, intersectionPoint);
          num dotProd = v1intPoint.dot(normal);

          three.Vector3 qProj = three.Vector3();
          qProj.setFrom(normal).scale(dotProd);

          three.Vector3 finalProj = three.Vector3();
          finalProj.sub2(intersectionPoint, qProj);

          intersectionPoint.setFrom(finalProj);

          // test to see if intersection is within edges of triangle
          // three.Vector3 edgeOne = three.Vector3();
          // edgeOne.sub2(vert3, vert1).cross(normal);
          // if (edgeOne.dot(intersectionPoint.clone().sub(vert1)) <= 0) {
          //   continue;
          // }

          // three.Vector3 edgeTwo = three.Vector3();
          // edgeTwo.sub2(vert1, vert2).cross(normal);
          // if (edgeTwo.dot(intersectionPoint.clone().sub(vert2)) <= 0) {
          //   continue;
          // }

          // three.Vector3 edgeThree = three.Vector3();
          // edgeThree.sub2(vert2, vert3).cross(normal);
          // if (edgeThree.dot(intersectionPoint.clone().sub(vert3)) <= 0) {
          //   continue;
          // }

          // barycentric ??
          // three.Vector3 xPrime = intersectionPoint.clone().sub(vert1);
          // three.Vector3 e1 = vert2.clone().sub(vert1);
          // three.Vector3 e2 = vert3.clone().sub(vert1);

          // three.Vector3 alphaNum = three.Vector3();
          // alphaNum.copy(xPrime);
          // three.Vector3 alphaDenom = three.Vector3();
          // alphaDenom.copy(e1);

          // double alpha = alphaNum.dot(e2) / alphaDenom.dot(e2);

          // three.Vector3 betaNum = three.Vector3();
          // betaNum.copy(xPrime);
          // three.Vector3 betaDenom = three.Vector3();
          // betaDenom.copy(e1);

          // double beta = betaNum.dot(e2) / betaDenom.dot(e2);

          // if (alpha < 0 || beta < 0 || alpha + beta > 1) {
          //   continue;
          // }
          // print(distanceA);
          // print(distanceB);

          // print(alpha);
          // print(beta);

          // something completely different

          // bool sameSide(three.Vector3 p1, three.Vector3 p2, three.Vector3 A,
          //     three.Vector3 B) {
          //   three.Vector3 BA = three.Vector3();
          //   BA.sub2(B, A);

          //   three.Vector3 p1A = three.Vector3();
          //   p1A.sub2(p1, A);

          //   three.Vector3 p2A = three.Vector3();
          //   p2A.sub2(p2, A);

          //   three.Vector3 cross1 = three.Vector3();
          //   cross1.crossVectors(BA, p1A);

          //   three.Vector3 cross2 = three.Vector3();
          //   cross2.crossVectors(BA, p2A);

          //   double check = cross1.dot(cross2).toDouble();
          //   if (check >= 0) {
          //     return true;
          //   }

          //   return false;
          // }

          // if (sameSide(intersectionPoint, vert1, vert2, vert3) &&
          //     sameSide(intersectionPoint, vert2, vert1, vert3) &&
          //     sameSide(intersectionPoint, vert3, vert1, vert2)) {
          // } else {
          //   continue;
          //

          // yet another triangle test
          // three.Vector3 crossArea = three.Vector3();
          // double areaTri = crossArea.crossVectors(vert12, vert13).length() / 2;

          // three.Vector3 crossAlpha = three.Vector3();
          // three.Vector3 crossBeta = three.Vector3();
          // three.Vector3 crossGamma = three.Vector3();

          // three.Vector3 pa = three.Vector3();
          // three.Vector3 pb = three.Vector3();
          // three.Vector3 pc = three.Vector3();

          // pa.sub2(vert1, intersectionPoint);
          // pb.sub2(vert2, intersectionPoint);
          // pc.sub2(vert3, intersectionPoint);

          // double alpha =
          //     crossAlpha.crossVectors(pb, pc).length() / (2 * areaTri);

          // double beta = crossBeta.crossVectors(pc, pa).length() / (2 * areaTri);

          // double gamma =
          //     crossGamma.crossVectors(pa, pb).length() / (2 * areaTri);

          // // double gamma = 1 - alpha - beta;

          // if (alpha > 1 ||
          //     beta > 1 ||
          //     gamma > 1 ||
          //     alpha < 0 ||
          //     beta < 0 ||
          //     gamma < 0) {
          //   // print('one of the 3 params is out of bounds');
          //   continue;
          // }

          // if ((1 - (alpha + beta + gamma)).abs() >= 0.001) {
          //   print('alpha + beta + gamma too big or too small');
          //   // createSphere(currParticle.position, 0x112233);
          //   print(alpha + beta + gamma);
          //   continue;
          // }

          // yet another another triangle test - angles
          // slow method, but seems to reliable
          // the idea here is to check the angles formed by
          // point and the three vertices. If the three angles
          // sum up to near 2pi, then we should be inside the triangle
          three.Vector3 pa = three.Vector3();
          three.Vector3 pb = three.Vector3();
          three.Vector3 pc = three.Vector3();

          pa.sub2(vert1, intersectionPoint);
          pb.sub2(vert2, intersectionPoint);
          pc.sub2(vert3, intersectionPoint);

          num aLen = pa.length;
          num bLen = pb.length;
          num cLen = pc.length;

          num adotb = pa.dot(pb);
          num bdotc = pb.dot(pc);
          num cdota = pc.dot(pa);

          double angle1 = math.acos(adotb / (aLen * bLen));
          double angle2 = math.acos(bdotc / (bLen * cLen));
          double angle3 = math.acos(cdota / (cLen * aLen));

          double totalAngle = angle1 + angle2 + angle3;

          if ((2 * math.pi - totalAngle).abs() > 0.3) {
            // print('wrong');
            // debugSpheres.add(createSphere(currParticle.position, 0x00FF00));
            continue;
          } else {
            // print('close to 2pi');
          }

          // all of this is testing - delete at some point
          if (testing && index % 5 == 0) {
            index++;
            print('collision detected');

            print('intersection point: ${intersectionPoint}');
            print('defPrev point: ${currParticle.defPrev}');
            print('currPos point: ${currParticle.position}');

            // should be really close together
            createSphere(currParticle.defPrev, 0xff00ff);
            createSphere(currParticle.position, 0x00bbff);
            createSphere(intersectionPoint, 0xffffff);

            // face
            createSphere(vert1.clone().sub(buck.position), 0xff0000,
                attach: buck);
            createSphere(vert2.clone().sub(buck.position), 0x00ff00,
                attach: buck);
            createSphere(vert3.clone().sub(buck.position), 0x0000ff,
                attach: buck);

            // visualizes plane
            PlaneHelper helper = PlaneHelper(planeTest, 50, 0xffff00);
            threeJs.scene.add(helper);

            num test1 = planeTest.distanceToPoint(currParticle.defPrev);
            num test2 = planeTest.distanceToPoint(currParticle.position);
            print('implemented distA: $test1');
            print('implemented distB: $test2');
          }

          // figure out adding correction to the particle
          three.Vector3 correction = three.Vector3();
          correction.sub2(intersectionPoint, currParticle.position);
          // .scale(5);
          currParticle.position.add(correction);
          currParticle.rigid = true;
          firstCollide = true;
          particleCollided = true;
          // debugSpheres.add(createSphere(currParticle.position, 0xCCCCCC));
        }
        // if (particleCollided) {
        //   debugSpheres.add(createSphere(currParticle.position, 0xCCCCCC));
        // } else {
        //   debugSpheres.add(createSphere(
        //       currParticle.position.clone().sub(three.Vector3(0, -1, 0)),
        //       0x222222));
        // }
      }
    }
    // if (firstCollide) {
    //   setState(() {
    //     pauseSim = true;
    //     liftBuck = true;
    //   });
    //   return;
    // }
  }
  
  void satisfyConstraints(Particle p1, Particle p2, double distance) {
    diff.sub2(p2.position, p1.position);
    double currentDist = diff.length;

    if (currentDist == 0) return; // prevents division by 0

    final correction = diff.scale(1 - distance / currentDist);

    if (correction.x.abs() < 0.001) correction.x = 0;
    if (correction.y.abs() < 0.001) correction.y = 0;
    if (correction.z.abs() < 0.001) correction.z = 0;

    final correctionHalf = correction.scale(0.5);

    if (correctionHalf.x.abs() < 0.001) correctionHalf.x = 0;
    if (correctionHalf.y.abs() < 0.001) correctionHalf.y = 0;
    if (correctionHalf.z.abs() < 0.001) correctionHalf.z = 0;

    if (correction.x.isNaN || correction.y.isNaN || correction.z.isNaN) return;

    if (correctionHalf.x.isNaN ||
        correctionHalf.y.isNaN ||
        correctionHalf.z.isNaN) return;

    if (correction.length.isNaN) return;
    if (correctionHalf.length.isNaN) return;
    if (correction.length > 5) return;

    if (!p1.rigid && p2.rigid) {
      p1.position.add(correction);
      // if (firstCollide) print(correction.toJSON());
    } else if (p1.rigid && !p2.rigid) {
      p2.position.sub(correction);
      // if (firstCollide) print(correction.toJSON());
    } else if (!p1.rigid && !p2.rigid) {
      p1.position.add(correctionHalf);
      p2.position.sub(correctionHalf);
      // if (firstCollide) print(correctionHalf.toJSON());
    }

    // if (!p1.rigid) p1.position.add(correctionHalf);
    // if (!p2.rigid) p2.position.sub(correctionHalf);
  }

  // currently an unused function - can be deleted
  void satisfyMeshConstraints(Particle p1, Particle p2) {
    three.Vector3 difference = diff.sub2(p2.position, p1.position);
    double currentDist = difference.length;
    // print(currentDist);
    if (currentDist == 0) return;

    double restoreForce = k_constant * currentDist * 0.01;

    if (currentDist > 5.5 || currentDist < 4.5) {
      if (p1.rigid && !p2.rigid) {
        p2.addForce(difference.normalize().scale(-restoreForce));
        p2.integrate(trimstepSq);
      } else if (!p1.rigid && p2.rigid) {
        p1.addForce(difference.normalize().scale(restoreForce));
        p1.integrate(trimstepSq);
      } else if (!p1.rigid && !p2.rigid) {
        p1.addForce(difference.normalize().scale(restoreForce * 0.5));
        p2.addForce(difference.normalize().scale(-restoreForce * 0.5));
        p1.integrate(trimstepSq);
        p2.integrate(trimstepSq);
      }
    }
  }

  // can be used for debugging
  three.Mesh createSphere(three.Vector3 center, int color,
      {double size = 1, three.Object3D? attach}) {
    three.SphereGeometry sphereGeo = three.SphereGeometry(size, 8, 8);
    three.Material mat = three.MeshBasicMaterial.fromMap({"color": color});
    three.Mesh sphere = three.Mesh(sphereGeo, mat);

    sphere.position = center;
    if (attach != null) {
      attach.add(sphere);
    } else {
      threeJs.scene.add(sphere);
    }
    return sphere;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          threeJs.build(),
          Positioned(
            top: 15,
            left: 15,
            child: InkWell(
              onTap: () {
                setState(() {
                  pauseSim = !pauseSim;
                });
              },
              child: Container(
                width: 120,
                height: 35,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(45/2),
                  border: Border.all(color: Theme.of(context).primaryColor,width: 3)
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Icon(!pauseSim?Icons.play_arrow:Icons.pause),
                    Text("${!pauseSim?'paused':'play'} sim")
                ],) 
              ),
            ),
          ),
          Positioned(
            top: 15,
            right: 15,
            child: ElevatedButton(
              onPressed: () {
                for (int i = 0; i < debugSpheres.length; i++) {
                  if (debugSpheres[i].parent != null &&
                      debugSpheres[i].parent != threeJs.scene) {
                    debugSpheres[i].parent!.remove(debugSpheres[i]);
                  } else {
                    threeJs.scene.remove(debugSpheres[i]);
                    debugSpheres[i].geometry?.dispose();
                    debugSpheres[i].material?.dispose();
                  }
                }
                threeJs.scene.removeList(debugSpheres);
                // }
                // render();
                debugSpheres.clear();
              },
              child: const Text("clear debug spheres"),
            ),
          ),
          Positioned(
            bottom: 15,
            right: MediaQuery.of(context).size.width / 2 - 100,
            child: InkWell(
              onTap: () {
                setState(() {
                  liftBuck = !liftBuck;
                });
              },
              child: Container(
                width: 120,
                height: 35,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(45/2),
                  border: Border.all(color: Theme.of(context).primaryColor,width: 3)
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Icon(liftBuck?Icons.play_arrow:Icons.pause),
                    Text("lift buck")
                ],) 
              ),
            ),
          ),
          Positioned(
            bottom: 15,
            right: MediaQuery.of(context).size.width / 2 + 100,
            child: InkWell(
              onTap: () {
                setState(() {
                  vacuum = !vacuum;
                });
              },
              child: Container(
                width: 120,
                height: 35,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(45/2),
                  border: Border.all(color: Theme.of(context).primaryColor,width: 3)
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Icon(vacuum?Icons.play_arrow:Icons.pause),
                    Text("vacuum")
                ],) 
              ),
            ),
          ),
          Positioned(
            bottom: 15,
            left: 15,
            child: Container(
              width: 120,
              height: 35,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(45/2),
                border: Border.all(color: Theme.of(context).primaryColor,width: 3)
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  InkWell(
                    onTap: (){
                      setState(() {
                        k_constant -= 5;
                      });
                    },
                    child: Icon(
                      Icons.arrow_back_ios_new_rounded
                    ),
                  ),
                  InkWell(
                    onTap: (){
                      setState(() {
                        k_constant += 5;
                      });
                    },
                    child: Icon(
                      Icons.arrow_forward_ios_rounded
                    ),
                  ),
                  Text("k = $k_constant"),
                ],
              ),
            )
          ),
        ],
      )
    );
  }
}

double drag = 1 - 0.03;
double damping = 1.0;
double mass = .2;
double restDistance = 3;

int xSegments = 100;
int ySegments = 100;

class Particle {
  late three.Vector3 position;
  late three.Vector3 previous;
  late three.Vector3 original;
  late three.Vector3 defPrev;
  late three.Vector3 a;
  late List<Particle> constraints;
  bool rigid = false;

  dynamic mass;
  late num invMass;

  late three.Vector3 tmp;
  late three.Vector3 tmp2;

  Particle(x, y, z, this.mass) {
    position = three.Vector3();
    previous = three.Vector3();
    original = three.Vector3();
    defPrev = three.Vector3();
    a = three.Vector3(0, 0, 0); // acceleration

    invMass = 1 / mass;
    tmp = three.Vector3();
    tmp2 = three.Vector3();

    // init
    clothFunction(x, y, position); // position
    clothFunction(x, y, previous); // previous
    clothFunction(x, y, original);
    constraints = [];
  }

  // Force -> Acceleration

  void addForce(three.Vector3 force) {
    a.add(tmp2.setFrom(force).scale(invMass));
  }

  // Performs Verlet integration
  void integrate(double timesq) {
    // final newPos = tmp.sub2(position, previous);
    tmp = position;
    three.Vector3 newPos = position.add(a.scale(timesq));
    // newPos.scale(drag).add(position);
    // newPos.add(a.scale(timesq));

    // tmp = previous;
    previous = tmp;
    position = newPos;

    a.setValues(0, 0, 0);
  }
}

class Cloth {
  late int w;
  late int h;

  late List<Particle> particles;
  late List<dynamic> constraints;
  late List<bool> rigid;
  late List<dynamic> springConstraints;

  Cloth([this.w = 10, this.h = 10]) {
    List<Particle> particles = [];
    List<dynamic> constraints = [];
    List<dynamic> springConstraints = [];
    List<bool> rigid = [];

    // Create particles
    for (int v = 0; v <= h; v++) {
      for (int u = 0; u <= w; u++) {
        particles.add(Particle(u / w, v / h, 0, mass));
        if (v == h || u == w || v == 0 || u == 0) {
          particles.last.rigid = true;
        } else {
          rigid.add(false);
        }
        // rigid.add(false);
      }
    }

    // Structural
    for (int v = 0; v <= h; v++) {
      for (int u = 0; u <= w; u++) {
        if (v + 1 < h) {
          constraints.add([particles[index(u, v)], particles[index(u, v + 1)], restDistance]);
          particles[index(u, v)].constraints.add(particles[index(u, v + 1)]);
          springConstraints.add([particles[index(u, v)], particles[index(u, v + 1)], restDistance]);
        }
        if (u + 1 < w) {
          constraints.add([particles[index(u, v)], particles[index(u + 1, v)], restDistance]);
          particles[index(u, v)].constraints.add(particles[index(u + 1, v)]);
          springConstraints.add([particles[index(u, v)], particles[index(u + 1, v)], restDistance]);
        }
        if (v + 1 < h && u + 1 < w) {
          springConstraints.add([
            particles[index(u, v)],
            particles[index(u + 1, v + 1)],
            restDistance
          ]);

          particles[index(u, v)].constraints.add(particles[index(u + 1, v + 1)]);
        }

        if (u - 1 > 0) {
          springConstraints.add([
            particles[index(u, v)],
            particles[index(u - 1, v)],
            restDistance
          ]);
          particles[index(u, v)].constraints.add(particles[index(u - 1, v)]);

          springConstraints.add([
            particles[index(u, v)],
            particles[index(u - 1, v + 1)],
            restDistance
          ]);

          particles[index(u, v)]
              .constraints
              .add(particles[index(u - 1, v + 1)]);
        }

        if (v - 1 > 0) {
          springConstraints.add([
            particles[index(u, v)],
            particles[index(u, v - 1)],
            restDistance
          ]);

          particles[index(u, v)].constraints.add(particles[index(u, v - 1)]);

          springConstraints.add([
            particles[index(u, v)],
            particles[index(u + 1, v - 1)],
            restDistance
          ]);

          particles[index(u, v)]
              .constraints
              .add(particles[index(u + 1, v - 1)]);
        }

        if (v - 1 > 0 && u - 1 > 0) {
          springConstraints.add([
            particles[index(u, v)],
            particles[index(u - 1, v - 1)],
            restDistance
          ]);
          particles[index(u, v)]
              .constraints
              .add(particles[index(u - 1, v - 1)]);
        }
      }
    }

    for (int u = w, v = 0; v < h; v++) {
      constraints.add([particles[index(u, v)], particles[index(u, v + 1)], restDistance]);
      springConstraints.add([particles[index(u, v)], particles[index(u, v + 1)], restDistance]);
    }

    for (int v = h, u = 0; u < w; u++) {
      constraints.add([particles[index(u, v)], particles[index(u + 1, v)], restDistance]);
      springConstraints.add([particles[index(u, v)], particles[index(u + 1, v)], restDistance]);
    }

    this.particles = particles;
    this.constraints = constraints;
    this.springConstraints = springConstraints;
    this.rigid = rigid;
  }

  int index(int u, int v) {
    return u + v * (w + 1);
  }
}

void clothFunction(double u, double v, three.Vector3 target) {
  double width = restDistance * xSegments;
  double height = restDistance * ySegments;

  double x = (u - 0.5) * width;
  double y = (v + 0.5) * height;
  double z = 100.0;

  target.setValues(x, z - 10, y - 300);
}
