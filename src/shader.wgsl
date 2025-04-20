struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
};

struct Properties {
    size: vec2<f32>,    // Window size
    time: f32,          // Time elapsed
    camera_yaw: f32,
    camera_pitch: f32,
    cube_position: f32,
}

var<push_constant> push_constants: Properties;

@vertex
fn vs_main(
    @builtin(vertex_index) in_vertex_index: u32,
) -> VertexOutput {
    var out: VertexOutput;

    let positions = array<vec2<f32>, 4>(
        vec2<f32>(-1.0, 1.0),   // TL vertex 0
        vec2<f32>(-1.0, -1.0),  // BL vertex 1
        vec2<f32>(1.0, -1.0),   // BR vertex 2
        vec2<f32>(1.0, 1.0),    // TR vertex 3
    );

    let indices = array<u32, 6>(
        0, 1, 2,
        0, 2, 3
    );

    let pos = positions[indices[in_vertex_index]];
    out.clip_position = vec4<f32>(pos.x, pos.y, 0.0, 1.0);

    return out;
}

struct SdfInfo {
    dist: f32,
    material_id: i32,
};

fn smin(a: SdfInfo, b: SdfInfo, k: f32) -> SdfInfo {
    let h = max(k - abs(a.dist - b.dist), 0.0) / k;
    let m = 0.5 + 0.5 * (b.dist - a.dist) / max(abs(b.dist - a.dist), 0.0001);
    let d = min(a.dist, b.dist) - h * h * h * k * (1.0 / 6.0);

    // Make sure that both spheres have a material id
    let blend_amount = h * h * h;
    let mat_id = select(
        select(b.material_id, a.material_id, a.dist < b.dist),
        -1,
        blend_amount > 0.1
    );

    return SdfInfo(d, mat_id);
}

fn sphere_sdf(p: vec3<f32>, center: vec3<f32>, radius: f32, mat_id: i32) -> SdfInfo {
    return SdfInfo(length(p - center) - radius, mat_id);
}

fn box_sdf(p: vec3<f32>, center: vec3<f32>, b: vec3<f32>, mat_id: i32) -> SdfInfo {
    let q = abs(p - center) - b;
    return SdfInfo(
        length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0),
        mat_id
    );
}

fn plane_sdf(p: vec3<f32>, n: vec3<f32>, h: f32, mat_id: i32) -> SdfInfo {
    return SdfInfo(dot(-p, n) + h, mat_id);
}

// Material IDs
const MAT_RED_SPHERE = 0;
const MAT_BLUE_SPHERE = 1;
const MAT_GREEN_BOX = 2;
const MAT_GROUND = 3;

fn map_scene(p: vec3<f32>) -> SdfInfo {
    let time = push_constants.time;

    let sphere1_pos = vec3<f32>(
        sin(time) * 1.0,
        cos(time) * 1.0,
        2.0
    );
    let sphere1 = sphere_sdf(p, sphere1_pos, 0.5, MAT_RED_SPHERE);

    let sphere2_pos = vec3<f32>(
        cos(time * 0.5) * 1.5,
        sin(time * 0.7) * 0.8,
        2.0 + sin(time) * 0.5
    );
    let sphere2 = sphere_sdf(p, sphere2_pos, 0.7, MAT_BLUE_SPHERE);

    // Smooth blend between spheres
    let blended_spheres = smin(sphere1, sphere2, 0.8);

    let box = box_sdf(p, vec3<f32>(3.2, 0.0, push_constants.cube_position), vec3<f32>(1.0), MAT_GREEN_BOX);

    let ground = plane_sdf(p, vec3<f32>(0.0, 1.0, 0.0), 1.5, MAT_GROUND);

    // Init if statements
    var result = blended_spheres;

    if (box.dist < result.dist) {
        result = box;
    }

    if (ground.dist < result.dist) {
        result = ground;
    }

    return result;
}

fn get_normal(p: vec3<f32>) -> vec3<f32> {
    const EPSILON: f32 = 0.001;
    let e = vec2<f32>(EPSILON, 0.0);

    return normalize(vec3<f32>(
        map_scene(p + e.xyy).dist - map_scene(p - e.xyy).dist,
        map_scene(p + e.yxy).dist - map_scene(p - e.yxy).dist,
        map_scene(p + e.yyx).dist - map_scene(p - e.yyx).dist
    ));
}

fn get_material_colour(mat_id: i32, p: vec3<f32>) -> vec3<f32> {
    var colour: vec3<f32>;

    switch(mat_id) {
        case MAT_RED_SPHERE: {
            colour = vec3<f32>(0.9, 0.1, 0.1);
        }
        case MAT_BLUE_SPHERE: {
            colour = vec3<f32>(0.1, 0.2, 0.8);
        }
        case MAT_GREEN_BOX: {
            colour = vec3<f32>(0.2, 0.8, 0.2);
        }
        case MAT_GROUND: {
            // Checkerboard pattern for the ground
            let checker = (floor(p.x * 0.5) + floor(p.z * 0.5)) % 2.0;
            colour = mix(
                vec3<f32>(0.8, 0.8, 0.8),
                vec3<f32>(0.2, 0.2, 0.2),
                checker
            );
        }

        default: {
            colour = vec3<f32>(1.0, 1.0, 0.0);
        }
    }

    return colour;
}

fn soft_shadow(ro: vec3<f32>, rd: vec3<f32>, mint: f32, maxt: f32, k: f32) -> f32 {
    var res = 1.0;
    var t = mint;

    for(var i: i32 = 0; i < 32 && t < maxt; i++) {
        let h = map_scene(ro + rd * t).dist;
        if(h < 0.001) {
            return 0.0;
        }
        res = min(res, k * h / t);
        t += h;
    }

    return res;
}

fn raymarch(ray_origin: vec3<f32>, ray_direction: vec3<f32>) -> vec3<f32> {
    var t: f32 = 0.0;
    const MAX_STEPS: i32 = 512;
    const MAX_DIST: f32 = 100.0;
    const HIT_DIST: f32 = 0.01;
    const AMBIENT: f32 = 0.1;

    for(var i: i32 = 0; i < MAX_STEPS; i++) {
        let p = ray_origin + t * ray_direction;
        let scene_info = map_scene(p);
        let d = scene_info.dist;

        if(d < HIT_DIST) {
            // Hit something - calculate shading
            let normal = get_normal(p);

            // Get material colour
            let material_colour = get_material_colour(scene_info.material_id, p);

            // Light properties
            let light_pos = vec3<f32>(2.0, -4.0, -3.0);
            let light_dir = normalize(light_pos - p);
            let light_dist = length(light_pos - p);

            // Diffuse lighting
            let diff = max(dot(normal, light_dir), 0.0);

            // Shadows
            let shadow = soft_shadow(p, light_dir, 0.2, light_dist, 16.0);

            return material_colour * (AMBIENT + diff * shadow);
        }

        if(t > MAX_DIST) {
            break;
        }

        t += d;
    }

    return vec3<f32>(0.0, 0.0, 0.0);
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    let aspect_ratio = push_constants.size.x / push_constants.size.y;
    let uv = in.clip_position.xy / push_constants.size;
    let adjusted_uv = vec2<f32>(
        (uv.x - 0.7),
        (uv.y - 0.5) * aspect_ratio
    );

    let cos_yaw = cos(push_constants.camera_yaw);
    let sin_yaw = sin(push_constants.camera_yaw);
    let cos_pitch = cos(push_constants.camera_pitch);
    let sin_pitch = sin(push_constants.camera_pitch);

    let rotation_y = mat3x3<f32>(
        cos_yaw, 0.0, -sin_yaw,
        0.0, 1.0, 0.0,
        sin_yaw, 0.0, cos_yaw
    );

    let rotation_x = mat3x3<f32>(
        1.0, 0.0, 0.0,
        0.0, cos_pitch, sin_pitch,
        0.0, -sin_pitch, cos_pitch
    );

    let camera_pos = vec3<f32>(0.0, 0.0, -3.0);
    let ray_direction = normalize(rotation_y * rotation_x * vec3<f32>(adjusted_uv.x, adjusted_uv.y, 1.0));
    let colour = raymarch(camera_pos, ray_direction);

    // Simple tone mapping
    let tone_mapped = colour / (colour + 1.0);

    return vec4<f32>(tone_mapped, 1.0);
}
