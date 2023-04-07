import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ignore: depend_on_referenced_packages
import 'package:flutter_gl/flutter_gl.dart';
import 'package:three_dart/three_dart.dart' as three;
import 'package:three_dart_jsm/three_dart_jsm.dart' as three_jsm;

class Thermosim extends StatefulWidget {
  const Thermosim({super.key});

  @override
  State<Thermosim> createState() => _ThermosimState();
}

class _ThermosimState extends State<Thermosim> {
  // Screen setup
  Size? screenSize;
  double dpr = 1.0;
  late double width;
  late double height;

  // Flutter GL Plugin
  late FlutterGlPlugin three3dRender;
  three.WebGLRenderer? renderer;
  late three.WebGLMultisampleRenderTarget renderTarget;
  dynamic sourceTexture;
  bool loaded = false;
  bool disposed = false;

  // World objects
  late three.Scene scene;
  late three.Camera camera;
  final GlobalKey<three_jsm.DomLikeListenableState> _globalKey =
      GlobalKey<three_jsm.DomLikeListenableState>();

  late Cloth cloth;
  late three.ParametricGeometry clothGeo;
  late three.Mesh mold;
  late three.Object3D buck;

  var ballSize = 50;

  // Simulation Constants
  var grav = 981 * 1.4;
  var gravity = three.Vector3(0, -981 * 1, 0).multiplyScalar(0.01);

  var trimstepSq = (18 / 1000) * (18 / 1000);

  var diff = three.Vector3();

  int k_constant = 38;

  // Debug
  bool verbose = false;
  List<three.Object3D> debugSpheres = [];

  @override
  void dispose() {
    print(" disposing three3drender ");

    disposed = true;
    three3dRender.dispose();

    super.dispose();
  }

  void initSize() {
    if (screenSize != null) {
      return;
    }

    final mqd = MediaQuery.of(context);
    // screen size and device pixel ratio
    screenSize = mqd.size;
    dpr = mqd.devicePixelRatio;

    initPlatformState();
  }

  void initPlatformState() async {
    width = screenSize!.width;
    height = screenSize!.height;

    three3dRender = FlutterGlPlugin();

    Map<String, dynamic> options = {
      "antialias": true,
      "alpha": false,
      "width": width.toInt(),
      "height": height.toInt(),
      "dpr": dpr
    };

    await three3dRender.initialize(options: options);

    setState(() {});
    Future.delayed(const Duration(milliseconds: 100), () async {
      await three3dRender.prepareContext();

      initScene();
    });
  }

  void initScene() {
    initRenderer();
    initPage();
  }

  void initRenderer() {
    Map<String, dynamic> options = {
      "width": width,
      "height": height,
      "gl": three3dRender.gl,
      "antialias": true,
      "canvas": three3dRender.element
    };
    renderer = three.WebGLRenderer(options);
    renderer!.setPixelRatio(dpr);
    renderer!.setSize(width, height, false);
    renderer!.shadowMap.enabled = true;

    if (!kIsWeb) {
      var pars = three.WebGLRenderTargetOptions({"format": three.RGBAFormat});
      renderTarget = three.WebGLMultisampleRenderTarget(
          (width * dpr).toInt(), (height * dpr).toInt(), pars);
      renderTarget.samples = 4;
      renderer!.setRenderTarget(renderTarget);
      sourceTexture = renderer!.getRenderTargetGLTexture(renderTarget);
    }
  }

  // this function sets up the scene
  void initPage() async {
    cloth = Cloth(xSegments, ySegments);
    scene = three.Scene();

    // set up camera and controls
    camera = three.Camera();
    camera = three.PerspectiveCamera(60, width / height, 1, 10000);
    camera.position.set(0, 160, 500);
    camera.lookAt(scene.position);

    three_jsm.OrbitControls controls =
        three_jsm.OrbitControls(camera, _globalKey);
    controls.target.set(0, 20, 0);
    controls.update();

    // add lighting
    scene.add(three.AmbientLight(0x3D4143));
    three.DirectionalLight light = three.DirectionalLight(0xffffff, 1.4);
    light.position.set(300, 1000, 500);
    light.target!.position.set(0, 0, 0);
    light.castShadow = true;

    int d = 300;
    light.shadow!.camera = three.OrthographicCamera(-d, d, d, -d, 500, 1600);
    light.shadow!.bias = 0.0001;
    light.shadow!.mapSize.width = light.shadow!.mapSize.height = 1024;

    scene.add(light);

    // background
    three.BufferGeometry buffgeoBack = three.IcosahedronGeometry(3000, 2);
    three.Mesh back = three.Mesh(buffgeoBack, three.MeshLambertMaterial());
    scene.add(back);

    // creating a sphere in three_dart
    three.SphereGeometry sphereGeo = three.SphereGeometry(ballSize, 32, 16);
    three.Material sphereMat =
        three.MeshPhongMaterial({'color': 0xffffff, 'wireframe': true});

    // import obj
    three_jsm.OBJLoader objLoader = three_jsm.OBJLoader(null);
    three.Object3D object =
        await objLoader.loadAsync('assets/obj/big_sphere.obj');

    // using scale might break things
    // object.scale.set(50, 50, 50);
    object.children[0].geometry!;
    object.updateMatrix();

    buck = object;

    // set up bounding box
    buck.children[0].geometry!.computeBoundingBox();
    three.Vector3 boxMin = buck.children[0].geometry!.boundingBox!.min;
    three.Vector3 boxMax = buck.children[0].geometry!.boundingBox!.max;
    boundBox.set(boxMin.multiplyScalar(1.01), boxMax.multiplyScalar(1.01));

    three.BoxHelper boxHelper = three.BoxHelper(buck);
    buck.add(boxHelper);

    object.children[0].material = sphereMat;

    scene.add(object);

    // texture loader for uv grid
    var loader = three.TextureLoader(null);
    three.Texture map =
        await loader.loadAsync('assets/textures/uv_grid_opengl.jpg', null);

    // creating a Cloth
    clothGeo = three.ParametricGeometry(clothFunction, xSegments, ySegments);
    three.Material clothMat = three.MeshLambertMaterial({
      "map": map,
      // "color": 0x00ff00,
      "side": three.DoubleSide,
      // "alphaTest": 0.5
    });
    three.Mesh clothMesh = three.Mesh(clothGeo, clothMat);
    scene.add(clothMesh);

    // wireframe for the cloth
    three.LineBasicMaterial wireMat =
        three.LineBasicMaterial({"color": 0xffffff});
    three.LineSegments wireframe =
        three.LineSegments(clothMesh.geometry!, wireMat);
    clothMesh.add(wireframe);

    // clothMesh.add(createSphere(cloth.particles[1198].position, 0x0000ff));

    loaded = true;

    animate();
  }

  bool liftBuck = false;
  bool pauseSim = false;
  double liftSpeed = 0.12;

  void animate() {
    if (!mounted || disposed) return;

    if (!loaded) return;

    if (!pauseSim) {
      if (liftBuck) {
        if (buck.position.y > 150) liftBuck = false;
        buck.position.y += liftSpeed;
        boundBox.translate(three.Vector3(0, liftSpeed, 0));

        buck.updateMatrix();
      }

      simulate();

      var p = cloth.particles;

      for (var i = 0, il = p.length; i < il; i++) {
        // if (cloth.rigid[i]) continue;
        var v = p[i].position;

        clothGeo.attributes["position"].setXYZ(i, v.x, v.y, v.z);
      }

      clothGeo.attributes["position"].needsUpdate = true;

      clothGeo.computeVertexNormals();
    }

    render();

    Future.delayed(
      const Duration(milliseconds: 15),
      () {
        animate();
      },
    );
  }

  bool testOnce = false;
  bool vacuum = false;

  void simulate() {
    var particles = cloth.particles;

    if (testOnce == true) {
      three.Material matVertex1 = three.MeshBasicMaterial({"color": 0xff0000});
      three.SphereGeometry vertex1 = three.SphereGeometry(1, 8, 8);

      // vertex1.setAttribute('positions', three.Float32BufferAttribute(verts, 3));
      three.Mesh testSphere = three.Mesh(vertex1, matVertex1);
      // testSphere.position = cloth.constraints[1950][0].position;
      testSphere.position = particles[1097].position;
      scene.add(testSphere);

      // three.Mesh testSphere2 = three.Mesh(vertex1, matVertex1);
      // testSphere.position = particles[2500].position;
      // scene.add(testSphere2);

      testOnce = true;
    }

    // adds gravity to cloth
    for (var i = 0, il = particles.length; i < il; i++) {
      var particle = particles[i];
      three.Vector3 adjPrev = three.Vector3();
      adjPrev.subVectors(particle.defPrev, particle.position);
      adjPrev.normalize();

      particle.defPrev
          .copy(particle.position.clone().addScaledVector(adjPrev, 2));

      if (particle.rigid) continue;
      three.Vector3 restoreVector = three.Vector3(0, 0, 0);

      for (Particle constraintParticle in particle.constraints) {
        three.Vector3 temp = three.Vector3(0, 0, 0);
        temp.subVectors(constraintParticle.position, particle.position);
        double length = temp.length();
        double restoreForce = length * k_constant;
        temp.normalize().multiplyScalar(restoreForce);
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

    // this vacuums
    if (vacuum) {
      for (var i = 0, il = particles.length; i < il; i++) {
        var particle = particles[i];
        if (particle.rigid) continue;

        three.Vector3 forceToCenter = three.Vector3();
        forceToCenter.subVectors(
            buck.position.clone()..y -= 20, particle.position);
        forceToCenter.y -= ballSize;
        forceToCenter.normalize();
        forceToCenter.multiplyScalar(1000);
        particle.addForce(forceToCenter);
        particle.integrate(trimstepSq);
        if (particle.position.y < boundBox.min.y) particle.rigid = true;
      }
    }

    // detect collisions
    detectCollisions(particles);

    // contraints for cloth
    var constraints = cloth.constraints;
    var il = constraints.length;

    // satisfy constraints of the cloth/plastic sheet
    for (var i = 0; i < il; i++) {
      List constraint = constraints[i];
      satisfyConstraints(constraint[0], constraint[1], constraint[2]);
    }

    // old collision detection - only worked for spheres
    // for (var i = 0, il = particles.length; i < il; i++) {
    //   Particle particle = particles[i];
    //   // if (particle.rigid) continue;
    //   three.Vector3 pos = particle.position;

    //   // gets current particle's pos and subtracts it from the ball's position.
    //   // if the length of that vector is smaller than the radius of the
    //   // ball, we have collided
    //   diff.subVectors(pos, buck.position);

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
    var particles = cloth.particles;
    List<Particle> p1 = [];
    List<Particle> p2 = [];
  }

  // this should take in a sublist of total particles
  // and return their updated states
  threadSimulate(List<Particle> particles) {
    // adds gravity to cloth
    for (var i = 0, il = particles.length; i < il; i++) {
      var particle = particles[i];
      three.Vector3 adjPrev = three.Vector3();
      adjPrev.subVectors(particle.defPrev, particle.position);
      adjPrev.normalize();

      particle.defPrev
          .copy(particle.position.clone().addScaledVector(adjPrev, 2));

      if (particle.rigid) continue;
      three.Vector3 restoreVector = three.Vector3(0, 0, 0);

      for (Particle constraintParticle in particle.constraints) {
        three.Vector3 temp = three.Vector3(0, 0, 0);
        temp.subVectors(constraintParticle.position, particle.position);
        double length = temp.length();
        double restoreForce = length * k_constant;
        temp.normalize().multiplyScalar(restoreForce);
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
      for (var i = 0, il = particles.length; i < il; i++) {
        var particle = particles[i];
        if (particle.rigid) continue;

        three.Vector3 forceToCenter = three.Vector3();
        forceToCenter.subVectors(
            buck.position.clone()..y -= 20, particle.position);
        forceToCenter.y -= ballSize;
        forceToCenter.normalize();
        forceToCenter.multiplyScalar(1000);
        particle.addForce(forceToCenter);
        particle.integrate(trimstepSq);
        if (particle.position.y < boundBox.min.y) particle.rigid = true;
      }
    }

    detectCollisions(particles);
  }

  int index = 0;
  int color = 0;
  bool once = false;
  bool testing = false;
  bool firstCollide = false;
  three.Box3 boundBox = three.Box3();
  detectCollisions(List<Particle> particleList) {
    List allVerts = (buck.children[0].geometry!.getAttribute('position')
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
          vert12.subVectors(vert2, vert1);
          vert13.subVectors(vert3, vert1);

          // find normal of plane from the
          // three points by doing cross product
          // and normalize the vector
          three.Vector3 normal = three.Vector3();
          normal.crossVectors(vert12, vert13);

          // calculate the distances from the plane
          three.Vector3 distanceVector = three.Vector3();
          num distanceA = distanceVector
              .subVectors(currParticle.defPrev, vert1)
              .dot(normal);

          num distanceB = distanceVector
              .subVectors(currParticle.position, vert1)
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
              //     .add(currParticle.defPrev.clone().negate().multiplyScalar(2));
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

          tempPos.copy(currParticle.position);
          tempDefPos.copy(currParticle.defPrev);
          intersectionPoint.subVectors(tempPos.multiplyScalar(distanceA),
              tempDefPos.multiplyScalar(distanceB));

          // this might be causing issues
          intersectionPoint.divideScalar(distanceA - distanceB);

          // project point onto plane
          three.Vector3 v1intPoint = three.Vector3();
          v1intPoint.subVectors(vert1, intersectionPoint);
          num dotProd = v1intPoint.dot(normal);

          three.Vector3 qProj = three.Vector3();
          qProj.copy(normal).multiplyScalar(dotProd);

          three.Vector3 finalProj = three.Vector3();
          finalProj.subVectors(intersectionPoint, qProj);

          intersectionPoint.copy(finalProj);

          // test to see if intersection is within edges of triangle
          // three.Vector3 edgeOne = three.Vector3();
          // edgeOne.subVectors(vert3, vert1).cross(normal);
          // if (edgeOne.dot(intersectionPoint.clone().sub(vert1)) <= 0) {
          //   continue;
          // }

          // three.Vector3 edgeTwo = three.Vector3();
          // edgeTwo.subVectors(vert1, vert2).cross(normal);
          // if (edgeTwo.dot(intersectionPoint.clone().sub(vert2)) <= 0) {
          //   continue;
          // }

          // three.Vector3 edgeThree = three.Vector3();
          // edgeThree.subVectors(vert2, vert3).cross(normal);
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
          //   BA.subVectors(B, A);

          //   three.Vector3 p1A = three.Vector3();
          //   p1A.subVectors(p1, A);

          //   three.Vector3 p2A = three.Vector3();
          //   p2A.subVectors(p2, A);

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

          // pa.subVectors(vert1, intersectionPoint);
          // pb.subVectors(vert2, intersectionPoint);
          // pc.subVectors(vert3, intersectionPoint);

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

          pa.subVectors(vert1, intersectionPoint);
          pb.subVectors(vert2, intersectionPoint);
          pc.subVectors(vert3, intersectionPoint);

          num aLen = pa.length();
          num bLen = pb.length();
          num cLen = pc.length();

          num adotb = pa.dot(pb);
          num bdotc = pb.dot(pc);
          num cdota = pc.dot(pa);

          double angle1 = acos(adotb / (aLen * bLen));
          double angle2 = acos(bdotc / (bLen * cLen));
          double angle3 = acos(cdota / (cLen * aLen));

          double totalAngle = angle1 + angle2 + angle3;

          if ((2 * pi - totalAngle).abs() > 0.3) {
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

            print('intersection point: ${intersectionPoint.toJSON()}');
            print('defPrev point: ${currParticle.defPrev.toJSON()}');
            print('currPos point: ${currParticle.position.toJSON()}');

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
            three.PlaneHelper helper =
                three.PlaneHelper(planeTest, 50, 0xffff00);
            scene.add(helper);

            num test1 = planeTest.distanceToPoint(currParticle.defPrev);
            num test2 = planeTest.distanceToPoint(currParticle.position);
            print('implemented distA: $test1');
            print('implemented distB: $test2');
          }

          // figure out adding correction to the particle
          three.Vector3 correction = three.Vector3();
          correction.subVectors(intersectionPoint, currParticle.position);
          // .multiplyScalar(5);
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

  int testIndex = 0;
  satisfyConstraints(Particle p1, Particle p2, distance) {
    diff.subVectors(p2.position, p1.position);
    double currentDist = diff.length();

    if (currentDist == 0) return; // prevents division by 0

    var correction = diff.multiplyScalar(1 - distance / currentDist);

    if (correction.x.abs() < 0.001) correction.x = 0;
    if (correction.y.abs() < 0.001) correction.y = 0;
    if (correction.z.abs() < 0.001) correction.z = 0;

    var correctionHalf = correction.multiplyScalar(0.5);

    if (correctionHalf.x.abs() < 0.001) correctionHalf.x = 0;
    if (correctionHalf.y.abs() < 0.001) correctionHalf.y = 0;
    if (correctionHalf.z.abs() < 0.001) correctionHalf.z = 0;

    if (correction.x.isNaN || correction.y.isNaN || correction.z.isNaN) return;

    if (correctionHalf.x.isNaN ||
        correctionHalf.y.isNaN ||
        correctionHalf.z.isNaN) return;

    if (correction.length().isNaN) return;
    if (correctionHalf.length().isNaN) return;
    if (correction.length() > 5) return;

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
  satisfyMeshConstraints(Particle p1, Particle p2) {
    three.Vector3 difference = diff.subVectors(p2.position, p1.position);
    double currentDist = difference.length();
    // print(currentDist);
    if (currentDist == 0) return;

    double restoreForce = k_constant * currentDist * 0.01;

    if (currentDist > 5.5 || currentDist < 4.5) {
      if (p1.rigid && !p2.rigid) {
        p2.addForce(difference.normalize().multiplyScalar(-restoreForce));
        p2.integrate(trimstepSq);
      } else if (!p1.rigid && p2.rigid) {
        p1.addForce(difference.normalize().multiplyScalar(restoreForce));
        p1.integrate(trimstepSq);
      } else if (!p1.rigid && !p2.rigid) {
        p1.addForce(difference.normalize().multiplyScalar(restoreForce * 0.5));
        p2.addForce(difference.normalize().multiplyScalar(-restoreForce * 0.5));
        p1.integrate(trimstepSq);
        p2.integrate(trimstepSq);
      }
    }
  }

  // can be used for debugging
  createSphere(three.Vector3 center, int color,
      {double size = 1, three.Object3D? attach}) {
    three.SphereGeometry sphereGeo = three.SphereGeometry(size, 8, 8);
    three.Material mat = three.MeshBasicMaterial({"color": color});
    three.Mesh sphere = three.Mesh(sphereGeo, mat);

    sphere.position = center;
    if (attach != null) {
      attach.add(sphere);
    } else {
      scene.add(sphere);
    }
    return sphere;
  }

  // this handles rendering the screen
  render() {
    int t = DateTime.now().millisecondsSinceEpoch;

    final gl = three3dRender.gl;

    renderer!.render(scene, camera);

    int t1 = DateTime.now().millisecondsSinceEpoch;

    if (verbose) {
      print("render cost: ${t1 - t} ");
      print(renderer!.info.memory);
      print(renderer!.info.render);
    }

    gl.flush();

    if (verbose) print(" render: sourceTexture: $sourceTexture ");

    if (!kIsWeb) {
      three3dRender.updateTexture(sourceTexture);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (BuildContext context) {
        initSize();
        return SingleChildScrollView(
          child: _build(),
        );
      },
    );
  }

  Widget _build() {
    return Column(
      children: [
        Stack(
          children: [
            three_jsm.DomLikeListenable(
              key: _globalKey,
              builder: (BuildContext context) {
                return Container(
                    width: width,
                    height: height,
                    color: Colors.black,
                    child: Builder(builder: (BuildContext context) {
                      if (kIsWeb) {
                        return three3dRender.isInitialized
                            ? HtmlElementView(
                                viewType: three3dRender.textureId!.toString())
                            : Container();
                      } else {
                        return three3dRender.isInitialized
                            ? Texture(textureId: three3dRender.textureId!)
                            : Container();
                      }
                    }));
              },
            ),
            Positioned(
              top: 15,
              left: 15,
              child: ElevatedButton(
                onPressed: () {
                  setState(() {
                    pauseSim = !pauseSim;
                  });
                },
                child: const Text("pause/unpause sim"),
              ),
            ),
            Positioned(
              top: 15,
              right: 15,
              child: ElevatedButton(
                onPressed: () {
                  for (int i = 0; i < debugSpheres.length; i++) {
                    if (debugSpheres[i].parent != null &&
                        debugSpheres[i].parent != scene) {
                      debugSpheres[i].parent!.remove(debugSpheres[i]);
                    } else {
                      scene.remove(debugSpheres[i]);
                      debugSpheres[i].geometry!.dispose();
                      debugSpheres[i].material.dispose();
                    }
                  }
                  scene.removeList(debugSpheres);
                  // }
                  // render();
                  debugSpheres.clear();
                },
                child: const Text("clear debug spheres"),
              ),
            ),
            Positioned(
              bottom: 15,
              right: 15,
              child: ElevatedButton(
                onPressed: () {
                  setState(() {
                    k_constant += 5;
                  });
                },
                child: const Text("increase k"),
              ),
            ),
            Positioned(
              bottom: 15,
              right: MediaQuery.of(context).size.width / 2 - 100,
              child: ElevatedButton(
                onPressed: () {
                  setState(() {
                    liftBuck = !liftBuck;
                  });
                },
                child: const Text("lift buck"),
              ),
            ),
            Positioned(
              bottom: 15,
              right: MediaQuery.of(context).size.width / 2 + 100,
              child: ElevatedButton(
                onPressed: () {
                  setState(() {
                    vacuum = !vacuum;
                  });
                },
                child: const Text("vacuum"),
              ),
            ),
            Positioned(
              bottom: 15,
              left: 15,
              child: ElevatedButton(
                onPressed: () {
                  setState(() {
                    k_constant -= 5;
                  });
                },
                child: const Text("decrease k"),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

var drag = 1 - 0.03;
var damping = 1.0;
var mass = .2;
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

  addForce(force) {
    a.add(tmp2.copy(force).multiplyScalar(invMass));
  }

  // Performs Verlet integration
  integrate(timesq) {
    // var newPos = tmp.subVectors(position, previous);
    tmp = position;
    three.Vector3 newPos = position.add(a.multiplyScalar(timesq));
    // newPos.multiplyScalar(drag).add(position);
    // newPos.add(a.multiplyScalar(timesq));

    // tmp = previous;
    previous = tmp;
    position = newPos;

    a.set(0, 0, 0);
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
    for (var v = 0; v <= h; v++) {
      for (var u = 0; u <= w; u++) {
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
    for (var v = 0; v < h; v++) {
      for (var u = 0; u < w; u++) {
        constraints.add(
            [particles[index(u, v)], particles[index(u, v + 1)], restDistance]);
        particles[index(u, v)].constraints.add(particles[index(u, v + 1)]);

        constraints.add(
            [particles[index(u, v)], particles[index(u + 1, v)], restDistance]);
        particles[index(u, v)].constraints.add(particles[index(u + 1, v)]);

        springConstraints.add(
            [particles[index(u, v)], particles[index(u, v + 1)], restDistance]);

        springConstraints.add(
            [particles[index(u, v)], particles[index(u + 1, v)], restDistance]);

        springConstraints.add([
          particles[index(u, v)],
          particles[index(u + 1, v + 1)],
          restDistance
        ]);

        particles[index(u, v)].constraints.add(particles[index(u + 1, v + 1)]);

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

    for (var u = w, v = 0; v < h; v++) {
      constraints.add(
          [particles[index(u, v)], particles[index(u, v + 1)], restDistance]);

      springConstraints.add(
          [particles[index(u, v)], particles[index(u, v + 1)], restDistance]);
    }

    for (var v = h, u = 0; u < w; u++) {
      constraints.add(
          [particles[index(u, v)], particles[index(u + 1, v)], restDistance]);

      springConstraints.add(
          [particles[index(u, v)], particles[index(u + 1, v)], restDistance]);
    }

    this.particles = particles;
    this.constraints = constraints;
    this.springConstraints = springConstraints;
    this.rigid = rigid;
  }

  index(u, v) {
    return u + v * (w + 1);
  }
}

clothFunction(u, v, target) {
  double width = restDistance * xSegments;
  double height = restDistance * ySegments;

  double x = (u - 0.5) * width;
  double y = (v + 0.5) * height;
  double z = 100.0;

  target.set(x, z - 10, y - 300);
}
