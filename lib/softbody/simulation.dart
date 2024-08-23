import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:thermo_sim/softbody/simple_physics.dart';
import 'package:three_js/three_js.dart' as three;
import 'package:three_js_geometry/three_js_geometry.dart';
import 'package:three_js_helpers/three_js_helpers.dart';

import 'cloth.dart';

class ThermoSim extends StatefulWidget {
  const ThermoSim({
    Key? key, 
  }) : super(key: key);

  @override
  _ThermoSimPageState createState() => _ThermoSimPageState();
}

class _ThermoSimPageState extends State<ThermoSim> {
  FocusNode node = FocusNode();
  late three.ThreeJS threeJs;
  late three.OrbitControls controls;

  late ClothPhysics cloth;

  List<three.Mesh> meshs = [];
  List<three.Object3D> collided = [];
  List<three.Mesh> grounds = [];


  double ToRad = 0.0174532925199432957;
  int count = 0;

  double bendingCompliance = 0.2;
  double stretchingCompliance = 0;
  double maxStretchingCompliance = 0.2;

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

  void animate(dt) {
    cloth.simulate();
    cloth.collider.move();
    if(cloth.gPhysicsScene.vacuum){
      cloth.gPhysicsScene.heaterOn = false;
    }
    currentTime += dt;
  }

  double currentTime = 0;
  int i = 0; 

  void elastic(){
    int length = count*count;
    for(int i = 0; i < length; i++){
      if(i <= count || i%count == 0 || i > length-count || (i+1)%count == 0){
      
      }
      else{

      }
    }
  }

  Future<void> setup() async {
    threeJs.scene = three.Scene();

    threeJs.camera = three.PerspectiveCamera(60, threeJs.width / threeJs.height, 0.001, 10);
    threeJs.camera.position.setValues(0,-1.25,0.22);
    threeJs.camera.rotation = three.Euler(1.5,0,0);

    controls = three.OrbitControls(threeJs.camera, threeJs.globalKey);
    //controls.target.setValues(0,20,0);
    controls.update();

    threeJs.scene.add(three.AmbientLight( 0x3D4143 ) );
    three.DirectionalLight light = three.DirectionalLight( 0xffffff , 1.4);
    light.position.setValues( 300, 1000, 500 );
    light.target!.position.setValues( 0, 0, 0 );
    threeJs.scene.add( light );

    addCloth();

    threeJs.addAnimationEvent((dt){
      animate(dt);
    });
  }

  Future<void> addCloth() async{
    final loader = three.TextureLoader();
    three.Texture map = (await loader.fromAsset('assets/textures/uv_grid_opengl.jpg'))!;
    final mat = three.MeshPhongMaterial.fromMap({
      'shininess': 10, 
      'transparent': true, 
      'opacity':0.75, 
      "map": map,
      'side':three.DoubleSide,
      //'layers': 1,
    });
    three.Mesh mesh = three.Mesh(three.PlaneGeometry(1,1,120,120), mat);
    count = math.sqrt( mesh.geometry!.attributes['position'].length).toInt();
    threeJs.scene.add( mesh );

    TorusKnotGeometry sphereGeo = TorusKnotGeometry(0.1, 0.1/3);
    three.Material sphereMat = three.MeshPhongMaterial.fromMap({
      'color': 0x0000ff, 
      //'wireframe': true,
      'side': three.DoubleSide
    });

    final buck = three.Mesh(sphereGeo,sphereMat);
    buck.position.z = -0.19;
    cloth = ClothPhysics(Collider([buck]),mesh);
    cloth.changeBending(bendingCompliance);
    
    threeJs.scene.add(buck);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          threeJs.build(),
          if(threeJs.mounted)Positioned(
            top: 15,
            left: 15,
            child: InkWell(
              onTap: () {
                setState(() {
                  cloth.gPhysicsScene.paused = !cloth.gPhysicsScene.paused;
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
                    Icon(!cloth.gPhysicsScene.paused?Icons.play_arrow:Icons.pause),
                    Text("${!cloth.gPhysicsScene.paused?'paused':'play'} sim")
                ],) 
              ),
            ),
          ),
          if(threeJs.mounted)Positioned(
            bottom: 15,
            right: MediaQuery.of(context).size.width / 2 - 100,
            child: InkWell(
              onTap: () {
                setState(() {
                  cloth.collider.lift = !cloth.collider.lift;
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
                    Icon(cloth.collider.lift?Icons.play_arrow:Icons.pause),
                    const Text("lift buck")
                ],) 
              ),
            ),
          ),
          if(threeJs.mounted)Positioned(
            bottom: 15,
            right: MediaQuery.of(context).size.width / 2 + 100,
            child: InkWell(
              onTap: () {
                setState(() {
                  cloth.gPhysicsScene.vacuum = !cloth.gPhysicsScene.vacuum;
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
                    Icon(cloth.gPhysicsScene.vacuum?Icons.play_arrow:Icons.pause),
                    const Text("vacuum")
                ],) 
              ),
            ),
          ),
          if(threeJs.mounted)Positioned(
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
                        if(maxStretchingCompliance - 0.1 > 0){
                          maxStretchingCompliance -= 0.1;
                        }
                        else{
                          maxStretchingCompliance = 0;
                        }
                      });
                    },
                    child: const Icon(
                      Icons.arrow_back_ios_new_rounded
                    ),
                  ),
                  InkWell(
                    onTap: (){
                      setState(() {
                        maxStretchingCompliance += 0.1;
                      });
                    },
                    child: const Icon(
                      Icons.arrow_forward_ios_rounded
                    ),
                  ),
                  Text("k = $maxStretchingCompliance"),
                ],
              ),
            )
          ),
          if(threeJs.mounted)Positioned(
            bottom: 15,
            left: 145,
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
                        if(bendingCompliance - 0.1 > 0){
                          bendingCompliance -= 0.1;
                        }
                        else{
                          bendingCompliance = 0;
                        }
                      });
                    },
                    child: const Icon(
                      Icons.arrow_back_ios_new_rounded
                    ),
                  ),
                  InkWell(
                    onTap: (){
                      setState(() {
                        bendingCompliance += 0.1;
                      });
                    },
                    child: const Icon(
                      Icons.arrow_forward_ios_rounded
                    ),
                  ),
                  Text("b = $bendingCompliance"),
                ],
              ),
            )
          ),
        ],
      )
    );
  }
}