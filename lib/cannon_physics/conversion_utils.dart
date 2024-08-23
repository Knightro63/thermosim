import 'dart:math' as math;
import 'package:cannon_physics/cannon_physics.dart' as cannon;
import 'package:three_js/three_js.dart' as three;
import 'package:three_js_geometry/three_js_geometry.dart';

extension ToVec3 on cannon.Vec3{
  three.Vector3 toVector3(){
    return three.Vector3(x,y,z);
  }
}
extension ToQuat on cannon.Quaternion{
  three.Quaternion toQuaternion(){
    return three.Quaternion(x,y,z,w);
  }
}

class GeometryCache {
  List<three.Object3D> geometries = [];
  List gone = [];

  three.Scene scene;
  Function createFunc;

  GeometryCache(this.scene, this.createFunc);

  three.Object3D request(){
    three.Object3D geometry = geometries.isNotEmpty ? geometries.removeLast() : createFunc();

    scene.add(geometry);
    gone.add(geometry);
    return geometry;
  }

  void restart(){
    while (gone.isNotEmpty) {
      geometries.add(gone.removeLast());
    }
  }

  void hideCached(){
    geometries.forEach((geometry){
      scene.remove(geometry);
    });
  }
}

class ConversionUtils{
  static three.BufferGeometry shapeToGeometry(cannon.Shape shape,{bool flatShading = true, three.Vector3? position}) {
    switch (shape.type) {
      case cannon.ShapeType.sphere: {
        shape as cannon.Sphere;
        return three.SphereGeometry(shape.radius, 8, 8);
      }

      case cannon.ShapeType.particle: {
        return three.SphereGeometry(0.1, 8, 8);
      }

      case cannon.ShapeType.plane: {
        return three.PlaneGeometry(500, 500, 4, 4);
      }

      case cannon.ShapeType.box: {
        shape as cannon.Box;
        return three.BoxGeometry(shape.halfExtents.x * 2, shape.halfExtents.y * 2, shape.halfExtents.z * 2);
      }

      case cannon.ShapeType.cylinder: {
        shape as cannon.Cylinder;
        return CylinderGeometry(shape.radiusTop, shape.radiusBottom, shape.height, shape.numSegments);
      }

      case cannon.ShapeType.convex: {
        shape as cannon.ConvexPolyhedron;
        List<three.Vector3> vertices = [];
        // Add vertices
        for (int i = 0; i < shape.vertices.length; i++) {
          final vertex = shape.vertices[i];
          vertices.add(three.Vector3(vertex.x,vertex.y,vertex.z));
        }
        final geometry = ConvexGeometry(vertices);
        geometry.computeBoundingSphere();

        if(flatShading) {
          geometry.computeFaceNormals();
        } else {
          geometry.computeVertexNormals();
        }

        return geometry;
      }
      case cannon.ShapeType.heightfield: {
        shape as cannon.Heightfield;
        final geometry = three.PlaneGeometry(
          shape.size.width,
          shape.size.height,
          shape.segments.width.toInt()-1,
          shape.segments.height.toInt()-1
        );
        
        final verts = geometry.attributes['position'].array;
        int x = 0;
        int y = -1;

        for(int i = 0; i < verts.length~/3;i++){
          if(i%shape.segments.width == 0){
            y++;
            x = 0;
          }
          verts[(i*3)+2] = shape.data[y][x];
          x++;
        }

        geometry.translate(shape.size.width/2, shape.size.height/2,0);
        geometry.rotateZ(math.pi/2);
        geometry.translate(shape.size.width, 0,0);

        geometry.computeBoundingSphere();

        if (!flatShading) {
          geometry.computeFaceNormals();
        } else {
          geometry.computeVertexNormals();
        }

        return geometry;
      }

      case cannon.ShapeType.trimesh: {
        shape as cannon.Trimesh;
        final geometry = three.BufferGeometry();
        
        geometry.setIndex(shape.indices);
        geometry.setAttributeFromString(
            'position', three.Float32BufferAttribute.fromList(shape.vertices, 3));
        if(shape.normals != null){
          geometry.setAttributeFromString(
            'normal', three.Float32BufferAttribute.fromList(shape.normals!, 3));
        }
        if(shape.uvs != null){
          geometry.setAttributeFromString(
            'uv', three.Float32BufferAttribute.fromList(shape.uvs!, 2));
        }

        geometry.computeBoundingSphere();

        if (flatShading) {
          geometry.computeFaceNormals();
        } else {
          geometry.computeVertexNormals();
        }

        return geometry;
      }

      default: {
        throw('Shape not recognized: "${shape.type}"');
      }
    }
  }

  static three.Object3D bodyToMesh(cannon.Body body, material) {
    final group = three.Group();
    group.position.setFrom(body.position.toVector3());
    group.quaternion.setFrom(three.Quaternion(body.quaternion.x,body.quaternion.y,body.quaternion.z,body.quaternion.w));

    final meshes = body.shapes.map((shape){
      final geometry = shapeToGeometry(shape);
      return three.Mesh(geometry, material);
    });
    
    int i = 0;
    meshes.forEach((three.Mesh mesh){
      final offset = body.shapeOffsets[i];
      final orientation = body.shapeOrientations[i];
      mesh.position.setFrom(offset.toVector3());
      mesh.quaternion.setFrom(three.Quaternion(orientation.x,orientation.y,orientation.z,orientation.w));
      group.add(mesh);
      i++;
    });

    return group;
  }

  static cannon.Trimesh fromGraphNode(three.Object3D group){
    List<double> vertices = [];
    List<int> indices = [];

    group.updateWorldMatrix(true, true);
    group.traverse((object){

      if(object.type == 'Mesh'){
        three.Object3D obj = object;
        late three.BufferGeometry geometry;
        bool isTemp = false;

        if(obj.geometry!.index != null){
          isTemp = true;
          geometry = obj.geometry!.clone().toNonIndexed();
        } 
        else {
          geometry = obj.geometry!;
        }

			 three.BufferAttribute positionAttribute = geometry.getAttributeFromString('position');

				for(int i = 0; i < positionAttribute.count; i += 3) {
					three.Vector3 v1 = three.Vector3().fromBuffer(positionAttribute, i);
					three.Vector3 v2 = three.Vector3().fromBuffer(positionAttribute, i + 1);
					three.Vector3 v3 = three.Vector3().fromBuffer(positionAttribute, i + 2);

					v1.applyMatrix4(obj.matrixWorld);
					v2.applyMatrix4(obj.matrixWorld);
					v3.applyMatrix4(obj.matrixWorld);

          vertices.addAll([v1.x,v1.y,v1.z]);
          vertices.addAll([v2.x,v2.y,v2.z]);
          vertices.addAll([v3.x,v3.y,v3.z]);
          
          indices.addAll([i,i+1,i+2]);
				}

        if(isTemp){
          geometry.dispose();
        }
      }
    });

    return cannon.Trimesh(vertices, indices);
  }

  static cannon.Shape geometryToShape(three.BufferGeometry geometry) {
    print(geometry.type);
    switch (geometry.type) {
      case 'BoxGeometry':
      case 'BoxBufferGeometry': {
        final width = geometry.parameters!['width'];
        final height = geometry.parameters!['height'];
        final depth = geometry.parameters!['depth'];
        final halfExtents = cannon.Vec3(width / 2, height / 2, depth / 2);
        return cannon.Box(halfExtents);
      }
      case 'PlaneGeometry':
      case 'PlaneBufferGeometry': {
        final points = geometry.attributes['position'].array;
        bool isFlat = true;
        double x = points[0];
        double y = points[1];
        double z = points[2];

        List<List<double>> matrix = [];
        int sizeX = 15;
        int sizeZ = 15;

        for(int i = 2; i < points.length;i+=3){
          bool xf = false;
          bool yf = false;
          bool zf = false;
          if(points[i] == x){
            xf = true;
          }
          else if(points[i+1] == y){
            yf = true;
          }
          else if(points[i+2] == z){
            zf = true;
          }

          if(!xf && !yf && !zf){
            isFlat = false;
          }
        }

        return isFlat?cannon.Plane():cannon.Heightfield(matrix);
      }
      case 'SphereGeometry':
      case 'SphereBufferGeometry': {
        return cannon.Sphere(geometry.parameters!['radius']);
      }
      case 'CylinderGeometry':
      case 'CylinderBufferGeometry': {
        return cannon.Cylinder(
          radiusTop: geometry.parameters!['radiusTop'], 
          radiusBottom: geometry.parameters!['radiusBottom'], 
          height: geometry.parameters!['height'].toDouble(), 
          numSegments: geometry.parameters!['radialSegments']
        );
      }
      case 'TorusGeometry':
      case 'TorusBufferGeometry': {
        return cannon.Trimesh.createTorus(
          cannon.TorusGeometry(
            geometry.parameters!['radius'].toDouble(), 
            geometry.parameters!['tube'], 
            geometry.parameters!['radialSegments'], 
            geometry.parameters!['tubularSegments'],
            geometry.parameters!['arch'] ?? math.pi*2,
          )
        );
      }
      case 'IcosahedronGeometry':
      case 'BufferGeometry':
      case 'IcosahedronBufferGeometry': {
        final points = geometry.attributes['position'].array;
        List<cannon.Vec3> verticies = [];
        List<List<int>>? faces = [];
        List<int> indicies = [];

        for(int i = 0; i < points.length; i+=3){
          verticies.add(
            cannon.Vec3(
              points[i],
              points[i+1],
              points[i+2]
            )
          );
          if(i < points.length/3){
            faces.add([i, i + 1, i + 2]);
            indicies.addAll([i, i + 1, i + 2]);
          }
        }

        return cannon.ConvexPolyhedron(
          vertices: verticies,
          faces: faces,
        );
      }
      // Create a ConvexPolyhedron with the convex hull if
      // it's none of these
      default: {
        final points = geometry.attributes['position'].array;
        final norms = geometry.attributes['normal'].array;
        final indexes = geometry.index;

        List<cannon.Vec3> verticies = [];
        List<List<int>>? faces = [];
        List<cannon.Vec3>? normals = [];
        List<int> indicies = [];
        List<double> norm = [];

        // for(int i = 0; i < points.length; i+=3){
        //   int i3 = i*3;
        //   verticies.add(
        //     cannon.Vec3(
        //       points[i],
        //       points[i+1],
        //       points[i+2]
        //     )
        //   );

        //   normals.add(cannon.Vec3(norms[i],norms[i+1],norms[i+2]));
        //   norm.addAll([norms[i],norms[i+1],norms[i+2]]);
        //   if(indexes != null && i < indexes.length){
        //     faces.add([
        //       indexes.getX(i)!.toInt(),
        //       indexes.getX(i+1)!.toInt(),
        //       indexes.getX(i+2)!.toInt(),
        //     ]);
        //     indicies.addAll([
        //       indexes.getX(i)!.toInt(),
        //       indexes.getX(i+1)!.toInt(),
        //       indexes.getX(i+2)!.toInt(),
        //     ]);
        //   }
        //   else if(i < points.length/3){
        //     faces.add([i, i + 1, i + 2]);
        //     indicies.addAll([i, i + 1, i + 2]);
        //   }
        // }

        // Construct polyhedron
        cannon.Trimesh polyhedron = cannon.Trimesh(
          points.sublist(0),
          indicies,
          norm
        );

        return polyhedron;
      }
    }
  }
}