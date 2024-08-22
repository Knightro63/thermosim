import 'package:three_js_core/three_js_core.dart';
import 'package:three_js_math/three_js_math.dart';

class PlaneHelper extends Line {
  Plane plane;
  double size;

  PlaneHelper.create(this.plane, this.size, [int color = 0xffff00, BufferGeometry? geometry, Material? material]):super(geometry,material){
		this.type = 'PlaneHelper';

		this.plane = plane;

		this.size = size;

		const List<double> positions2 = [ 1, 1, 0, - 1, 1, 0, - 1, - 1, 0, 1, 1, 0, - 1, - 1, 0, 1, - 1, 0 ];

		final geometry2 = BufferGeometry();
		geometry2.setAttributeFromString( 'position', Float32BufferAttribute.fromList( positions2, 3 ) );
		geometry2.computeBoundingSphere();

		this.add(Mesh( geometry2, MeshBasicMaterial.fromMap( { 'color': color, 'opacity': 0.2, 'transparent': true, 'depthWrite': false, 'toneMapped': false } ) ) );
  }
	factory PlaneHelper(Plane plane, [size = 1, int color = 0xffff00 ]) {
		const List<double> positions = [ 1, - 1, 0, - 1, 1, 0, - 1, - 1, 0, 1, 1, 0, - 1, 1, 0, - 1, - 1, 0, 1, - 1, 0, 1, 1, 0 ];

		final geometry = BufferGeometry();
		geometry.setAttributeFromString( 'position', new Float32BufferAttribute.fromList( positions, 3 ) );
		geometry.computeBoundingSphere();

		return PlaneHelper.create(plane, size, color, geometry, LineBasicMaterial.fromMap( { 'color': color, 'toneMapped': false } ) );
	}

	void updateMatrixWorld([bool force = false]) {
		this.position.setValues( 0, 0, 0 );
		this.scale.setValues( 0.5 * this.size, 0.5 * this.size, 1 );
		this.lookAt( this.plane.normal );
		this.translateZ( - this.plane.constant );
		super.updateMatrixWorld( force );
	}

	void dispose() {
		this.geometry?.dispose();
		this.material?.dispose();
		this.children[ 0 ].geometry?.dispose();
		this.children[ 0 ].material?.dispose();
	}
}