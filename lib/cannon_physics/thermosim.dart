import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:three_js_helpers/box_helper.dart';
import 'conversion_utils.dart';
import 'package:cannon_physics/cannon_physics.dart' as cannon;
import 'package:three_js/three_js.dart' as three;
import 'package:three_js_geometry/three_js_geometry.dart';

class Thermosim extends StatefulWidget {
  const Thermosim({
    Key? key,
    this.offset = const Offset(0,0)
  }) : super(key: key);

  final Offset offset;

  @override
  _ThermosimPageState createState() => _ThermosimPageState();
}

class _ThermosimPageState extends State<Thermosim> {
  FocusNode node = FocusNode();
  late three.ThreeJS threeJs;
  late three.OrbitControls controls;

  late three.BufferGeometry clothGeometry;
  late three.Object3D buck;

  //cannon var
  late cannon.World world;
  List<cannon.Body> bodys = [];
  late cannon.Body objectBody;
  double clothMass = 5000; // 1 kg in total
  double clothSize = 406.4; // 1 meter
  int Nx = 30; // number of horizontal particles in the cloth
  int Ny = 30; // number of vertical particles in the cloth
  late double mass;
  late double restDistance;
  //double movementRadius = 130;

  List<List<cannon.Body>> particles = [];

  bool liftBuck = false;
  bool vacuum = false;
  bool pauseSim = false;
  double liftSpeed = 12;
  double maxLift = 100;

  @override
  void initState() {
    mass = (clothMass / Nx) * Ny;
    restDistance = clothSize / Nx;

    threeJs = three.ThreeJS(
      onSetupComplete: (){setState(() {});},
      setup: setup,
      settings: three.Settings(
        // useSourceTexture: true
      )
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

  Future<void> setup() async {
    threeJs.scene = three.Scene();

    threeJs.camera = three.PerspectiveCamera(30, threeJs.width / threeJs.height, 0.5, 10000);
    threeJs.camera.position.setValues(math.cos(math.pi/4) * 800,0,math.sin(math.pi/4) * 800);

    controls = three.OrbitControls(threeJs.camera, threeJs.globalKey);
    controls.rotateUp(0.6);
    
    threeJs.scene.add(three.AmbientLight( 0x3D4143 ) );
    three.DirectionalLight light = three.DirectionalLight( 0xffffff , 0.3);
    light.position.setValues( 300, 1000, 500 );
    light.target!.position.setValues( 0, 0, 0 );
    threeJs.scene.add( light );

    // Cloth material
    three.Texture? clothTexture = await three.TextureLoader().fromAsset('assets/textures/uv_grid_opengl.jpg');
    clothTexture?.wrapS = three.RepeatWrapping;
    clothTexture?.wrapT = three.RepeatWrapping;
    clothTexture?.anisotropy = 16;
    clothTexture?.encoding = three.sRGBEncoding;

    three.MeshPhongMaterial clothMaterial = three.MeshPhongMaterial.fromMap({
      'map': clothTexture,
      'side': three.DoubleSide,
      //'wireframe': true
    });
    // Cloth geometry
    clothGeometry = ParametricGeometry(clothFunction, Nx, Ny);

    // Cloth mesh
    three.Mesh clothMesh = three.Mesh(clothGeometry, clothMaterial);
    threeJs.scene.add(clothMesh);

    // Sphere
    three.OBJLoader objLoader = three.OBJLoader();
    buck = (await objLoader.fromAsset('assets/obj/Serenity_key_Hand_Left.obj'))!;
    BoxHelper boxHelper = BoxHelper(buck);
    buck.add(boxHelper);
    print(buck.position);
    threeJs.scene.add(buck);

    initCannonPhysics();

    threeJs.addAnimationEvent((dt){
      world.fixedStep();
      updateCannonPhysics();
      controls.update();
    });
  }

  //----------------------------------
  //  cannon PHYSICS
  //----------------------------------

  void initCannonPhysics(){
    world = cannon.World(
      allowSleep: true
    );
    world.gravity.set(0, -98.1, 0);
    
    final solver = cannon.GSSolver();
    solver.iterations = 5;
    solver.tolerance = 0.00001;
    if (true) {
      world.solver = cannon.SplitSolver(solver);
    } else {
      world.solver = solver;
    }
    // Materials
    cannon.Material clothMaterial = cannon.Material(name: 'cloth');
    cannon.Material sphereMaterial = cannon.Material(name: 'sphere');
    cannon.ContactMaterial clothSphere = cannon.ContactMaterial(
      clothMaterial, 
      sphereMaterial,
      friction: 0.9,
      restitution: 0.5,
    );

    // Adjust constraint equation parameters
    // Contact stiffness - use to make softer/harder contacts
    clothSphere.contactEquationStiffness = 1e9;
    // Stabilization time in number of timesteps
    clothSphere.contactEquationRelaxation = 4;
    // Add contact material to the world
    world.addContactMaterial(clothSphere);

    // Create sphere
    // Make it a little bigger than the three.js sphere
    // so the cloth doesn't clip thruogh
    cannon.Shape objectShape = cannon.Box(cannon.Vec3(50,50,50));//ConversionUtils.geometryToShape(object.geometry!);
    //objectBody = cannon.ConvexPolyhedron.trimeshToPolyhedron(objectShape as cannon.Trimesh,cannon.Body(mass:0));//cannon.Body(mass: 1 );
    objectBody = cannon.Body(
      //type: cannon.BodyTypes.kinematic,
      mass: 0
    );
    objectBody.addShape(objectShape);
    buck.position.setFrom(objectBody.shapeOffsets[0].toVector3());
    buck.quaternion.setFrom(objectBody.quaternion.toQuaternion());
    world.addBody(objectBody);

    // Create cannon particles
    for (int i = 0; i < Nx + 1; i++) {
      particles.add([]);
      for (int j = 0; j < Ny + 1; j++) {
        late final three.Vector3 point = three.Vector3();
        clothFunction(i / (Nx + 1), j / (Ny + 1), point);
        cannon.Body particle = cannon.Body(
          mass: j == Ny || i == 0 || i == Nx || j==0? 0 : mass,
        );
        particle.addShape(cannon.Particle());
        particle.linearDamping = 0.99;
        particle.angularDamping = 0.99;
        particle.position.set(point.x, point.y+100, point.z - Ny * 0.9 * restDistance);
        //particle.velocity.set(0, 0, -0.1 * (Ny - j));

        particles[i].add(particle);
        world.addBody(particle);
      }
    }

    // Connect the particles with distance constraints
    void connect(int i1,int j1,int i2,int j2) {
      world.addConstraint(cannon.DistanceConstraint(particles[i1][j1], particles[i2][j2], restDistance,double.infinity));
    }
    for (int i = 0; i < Nx + 1; i++) {
      for (int j = 0; j < Ny + 1; j++) {
        if (i < Nx) connect(i, j, i + 1, j);
        if (j < Ny) connect(i, j, i, j + 1);
      }
    }
  }
  // Parametric function
  // https://threejs.org/docs/index.html#api/en/geometries/ParametricGeometry
  three.Vector3 clothFunction(double u, double v, three.Vector3 target) {
    double x = (u - 0.5) * restDistance * Nx;
    double z = (v + 0.5) * restDistance * Ny;
    double y = 0;

    target.setValues(x, y, z);

    return target;
  }

  void updateCannonPhysics() {
    if(!pauseSim){
      // Make the three.js cloth follow the cannon.js particles
      for (int i = 0; i < Nx + 1; i++) {
        for (int j = 0; j < Ny + 1; j++) {
          int index = j * (Nx + 1) + i;
          cannon.Vec3 v = particles[i][j].position;
          clothGeometry.attributes["position"].setXYZ(index, v.x, v.y, v.z);
        }
      }
      clothGeometry.attributes["position"].needsUpdate = true;

      clothGeometry.computeVertexNormals();
      clothGeometry.normalsNeedUpdate = true;
      clothGeometry.verticesNeedUpdate = true;

      // Move the ball in a circular motion
      double time = world.time/4;
      double delay = 1.5;
      if(liftBuck && objectBody.position.y < maxLift){
        objectBody.position.y += liftSpeed;
      }
      else if(time > delay){
        // for(int i = 0; i < particles.length;i++){
        //   for(int j = 0; j < particles[i].length;j++){
        //     final particle = particles[i][j];
        //     final forceToCenter = cannon.Vec3();
        //     forceToCenter.subVectors(
        //         objectBody.position.clone()..y -= 20, particle.position);
        //     //forceToCenter.y -= ballSize;
        //     forceToCenter.normalize();
        //     forceToCenter.scale(10000000);
        //     particle.applyForce(forceToCenter);
        //   }
        // }
      }

      buck.position.setFrom(objectBody.position.toVector3());
      buck.quaternion.setFrom(objectBody.quaternion.toQuaternion());
      print(buck.position);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
    children: [
      threeJs.build(),
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
    ],
  );
  }
}