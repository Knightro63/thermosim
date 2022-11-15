import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:flutter_gl/flutter_gl.dart';
import 'package:three_dart/three_dart.dart' as THREE;
import 'package:three_dart/three_dart.dart' hide Texture, Color;
import 'package:three_dart_jsm/three_dart_jsm.dart';

import 'cloth.dart';
import 'softBody.dart';

class ThermoSim extends StatefulWidget {
  const ThermoSim({
    Key? key, 
  }) : super(key: key);

  @override
  _ThermoSimPageState createState() => _ThermoSimPageState();
}

class _ThermoSimPageState extends State<ThermoSim> {
  FocusNode node = FocusNode();
  // gl values
  //late Object3D object;
  bool animationReady = false;
  late FlutterGlPlugin three3dRender;
  WebGLRenderTarget? renderTarget;
  WebGLRenderer? renderer;
  int? fboId;
  late double width;
  late double height;
  Size? screenSize;
  late Scene scene;
  late Camera camera;
  late ClothPhysics cloth;
  double dpr = 1.0;
  bool verbose = false;
  bool disposed = false;
  final GlobalKey<DomLikeListenableState> _globalKey = GlobalKey<DomLikeListenableState>();
  dynamic sourceTexture;

  List<Mesh> meshs = [];
  List<VertexNormalsHelper> helpers = [];
  List<Mesh> grounds = [];

  Map<String,BufferGeometry> geos = {};
  Map<String,THREE.Material> mats = {};

  List<int> fps = [0,0,0,0];
  double ToRad = 0.0174532925199432957;
  int count = 0;

  double bendingCompliance = 0;
  double stretchingCompliance = 0;

  @override
  void initState() {
    super.initState();
  }
  @override
  void dispose() {
    disposed = true;
    three3dRender.dispose();
    super.dispose();
  }
  
  void initSize(BuildContext context) {
    if (screenSize != null) {
      return;
    }

    final mqd = MediaQuery.of(context);

    screenSize = mqd.size;
    dpr = mqd.devicePixelRatio;

    initPlatformState();
  }
  void animate() {
    if (!mounted || disposed) {
      return;
    }
    render();
    cloth.simulate(bendingCompliance,stretchingCompliance);
    simulation();

    Future.delayed(const Duration(milliseconds: 16), () {
      currentTime += 16;
      animate();
    });
  }


  double currentTime = 0;
  int i = 0; 
  void simulation(){
    if(currentTime > 5000){
      moveObjects();
    }
    else{
      heating();
    }
  }

  void heating(){
    
    if(cloth.gPhysicsScene.temperatue < 210){
    bendingCompliance -= 0;
      cloth.gPhysicsScene.temperatue += 1;
      //stretchingCompliance -= 0.00001;
    }
    else if(cloth.gPhysicsScene.temperatue < 120){
      stretchingCompliance = 10;
    }
  }
  void elastic(){
    //print(geos['plane']!.attributes['position'].length);
    int length = count*count;
    for(int i = 0; i < length; i++){
      if(i <= count || i%count == 0 || i > length-count || (i+1)%count == 0){
        //geos['plane']!.attributes['position'].setZ(i,0.1);
      }
      else{
        geos['plane']!.attributes['position'].setZ(i,0.1);
      }
    }
    geos['plane']!.attributes['position'].needsUpdate = true;
  }
  void moveObjects(){
    for(int i = 0;i < meshs.length;i++){
      if(meshs[i].position.y != 190){
        meshs[i].position.y += 1;
        helpers[i].update();
      }
    }
  }

  Future<void> initPage() async {
    scene = Scene();

    camera = PerspectiveCamera(60, width / height, 1, 10000);
    camera.position.set(0,160,500);

    OrbitControls controls = OrbitControls(camera, _globalKey);
    controls.target.set(0,20,0);
    controls.update();
    
    scene.add(AmbientLight( 0x3D4143 ) );
    DirectionalLight light = DirectionalLight( 0xffffff , 1.4);
    light.position.set( 300, 1000, 500 );
    light.target!.position.set( 0, 0, 0 );
    light.castShadow = true;

    int d = 300;
    light.shadow!.camera = OrthographicCamera( -d, d, d, -d,  500, 1600 );
    light.shadow!.bias = 0.0001;
    light.shadow!.mapSize.width = light.shadow!.mapSize.height = 1024;

    scene.add( light );

    // background
    BufferGeometry buffgeoBack = THREE.IcosahedronGeometry(3000,2);
    Mesh back = THREE.Mesh( 
      buffgeoBack, 
      THREE.MeshLambertMaterial()
    );
    scene.add( back );

    // geometrys
    geos['sphere'] = THREE.SphereGeometry(5,16,10);
    geos['box'] =  THREE.BoxGeometry(1,1,1);
    geos['cylinder'] = THREE.CylinderGeometry(1,1,1);
    geos['plane'] = THREE.PlaneGeometry(1,1,30,30);
    
    // materials
    mats['sph']    = MeshPhongMaterial({'shininess': 10, 'name':'sph'});
    
    mats['box']    = MeshPhongMaterial({'shininess': 10, 'name':'box'});
    mats['cyl']    = MeshPhongMaterial({'shininess': 10, 'name':'cyl'});
    mats['ssph']   = MeshPhongMaterial({'shininess': 10, 'name':'ssph'});
    mats['sbox']   = MeshPhongMaterial({'shininess': 10, 'name':'sbox'});
    mats['scyl']   = MeshPhongMaterial({'shininess': 10, 'name':'scyl'});
    mats['ground'] = MeshPhongMaterial({
      'shininess': 10, 
      'color':0x3D4143, 
      'transparent':false, 
      'opacity':0.5, 
      'side':THREE.DoubleSide,
      //'layers': 1,
    });
    //mats['ground']!.wireframe = true;
    
    animationReady = true;
  }

  void addStaticBox(List<double> size,List<double> position,List<double> rotation) {
    Mesh mesh = THREE.Mesh(geos['plane'], mats['ground']);
    count = Math.sqrt( geos['plane']!.attributes['position'].length).toInt();
    mesh.scale.set( size[0], size[1], size[2] );
    mesh.position.set( position[0], position[1], position[2] );
    mesh.rotation.set( rotation[0]*ToRad, rotation[1]*ToRad, rotation[2]*ToRad );

    VertexNormalsHelper helper = VertexNormalsHelper( mesh, 3, 0xffffff );
    //mesh.add(helper);

    LineBasicMaterial mat = LineBasicMaterial( { 'color': 0xffffff } );
    LineSegments wireframe = LineSegments( geos['plane']!, mat );
    mesh.add( wireframe );

    mesh.castShadow = true;
    mesh.receiveShadow = true;
    scene.add( mesh );
    cloth = ClothPhysics(scene,mesh);
    cloth.run();
    //grounds.add(mesh);
  }

  void clearMesh(){
    for(int i = 0; i < meshs.length;i++){ 
      scene.remove(meshs[i]);
    }

    for(int i = 0; i < grounds.length;i++){ 
      scene.remove(grounds[ i ]);
    }
    grounds = [];
    meshs = [];
  }

  //----------------------------------
  //  OIMO PHYSICS
  //----------------------------------

  void initOimoPhysics(){
    populate();
  }

  void populate() {
    int max = 1;

    // reset old
    clearMesh();
    addStaticBox([400, 400, 400], [0,160,0], [-90,0,0]);

    //add object
    double x, y, z, w, h, d;
    int t;
    for(int i = 0; i < max;i++){
      t = 1;
      
      x = -100 + Math.random()*200;
      z = -100 + Math.random()*200;
      y = 100 + Math.random()*1000;
      w = 10 + Math.random()*10;
      h = 10 + Math.random()*10;
      d = 10 + Math.random()*10;
      THREE.Color randColor = THREE.Color().setHex((Math.random() * 0xFFFFFF).toInt());

      if(t==1){
        THREE.Material mat = mats['sph']!;
        mat.color = randColor;
        Mesh mesh = THREE.Mesh( geos['sphere'], mat);
        mesh.scale.set( w*0.5, w*0.5, w*0.5 );
        meshs.add(mesh);
      } 
      else if(t==2){
        THREE.Material mat = mats['box']!;
        mat.color = randColor;
        meshs.add(THREE.Mesh( geos['box'], mat ));
        meshs[i].scale.set( w, h, d );
      } 
      else if(t==3){
        THREE.Material mat = mats['cyl']!;
        mat.color = randColor;
        meshs.add(THREE.Mesh( geos['cylinder'], mat));
        meshs[i].scale.set( w*0.5, h, w*0.5 );
      }

      meshs[i].castShadow = true;
      meshs[i].receiveShadow = true;

      helpers.add(VertexNormalsHelper( meshs[i], 3, 0xffffff ));

      scene.add(helpers[i]);
      scene.add(meshs[i]);
    }
  }

  void render() {
    final _gl = three3dRender.gl;
    renderer!.render(scene, camera);
    _gl.flush();
    if(!kIsWeb) {
      three3dRender.updateTexture(sourceTexture);
    }
  }
  void initRenderer() {
    Map<String, dynamic> _options = {
      "width": width,
      "height": height,
      "gl": three3dRender.gl,
      "antialias": true,
      "canvas": three3dRender.element,
    };

    if(!kIsWeb && Platform.isAndroid){
      _options['logarithmicDepthBuffer'] = true;
    }

    renderer = WebGLRenderer(_options);
    renderer!.setPixelRatio(dpr);
    renderer!.setSize(width, height, false);
    renderer!.shadowMap.enabled = true;
    renderer!.shadowMap.type = THREE.PCFShadowMap;
    //renderer!.outputEncoding = THREE.sRGBEncoding;

    if(!kIsWeb){
      WebGLRenderTargetOptions pars = WebGLRenderTargetOptions({"format": RGBAFormat,"samples": 8});
      renderTarget = WebGLRenderTarget((width * dpr).toInt(), (height * dpr).toInt(), pars);
      renderer!.setRenderTarget(renderTarget);
      sourceTexture = renderer!.getRenderTargetGLTexture(renderTarget!);
    }
    else{
      renderTarget = null;
    }
  }
  void initScene() async{
    await initPage();
    initRenderer();
    initOimoPhysics();
    animate();
  }
  Future<void> initPlatformState() async {
    width = screenSize!.width;
    height = screenSize!.height;

    three3dRender = FlutterGlPlugin();

    Map<String, dynamic> _options = {
      "antialias": true,
      "alpha": true,
      "width": width.toInt(),
      "height": height.toInt(),
      "dpr": dpr,
      'precision': 'highp'
    };
    await three3dRender.initialize(options: _options);

    setState(() {});

    // TODO web wait dom ok!!!
    Future.delayed(const Duration(milliseconds: 100), () async {
      await three3dRender.prepareContext();
      initScene();
    });
  }

  Widget threeDart() {
    return Builder(builder: (BuildContext context) {
      initSize(context);
      return Container(
        width: screenSize!.width,
        height: screenSize!.height,
        color: Theme.of(context).canvasColor,
        child: DomLikeListenable(
          key: _globalKey,
          builder: (BuildContext context) {
            FocusScope.of(context).requestFocus(node);
            return Container(
              width: width,
              height: height,
              color: Theme.of(context).canvasColor,
              child: Builder(builder: (BuildContext context) {
                if (kIsWeb) {
                  return three3dRender.isInitialized
                      ? HtmlElementView(
                          viewType:
                              three3dRender.textureId!.toString())
                      : Container();
                } else {
                  return three3dRender.isInitialized
                      ? Texture(textureId: three3dRender.textureId!)
                      : Container();
                }
              })
            );
          }
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: double.infinity,
      width: double.infinity,
      child: Stack(
        children: [
          threeDart(),
        ],
      )
    );
  }
}