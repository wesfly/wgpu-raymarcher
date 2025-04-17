struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
};

struct Properties {
    size: vec2<f32>,
    time: f32,          // Time elapsed
    camera_yaw: f32,
    camera_pitch: f32,
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

// Object info structure
// struct SceneObject {
//     dist: f32,
//     material_id: i32,
// }

fn get_normal(p: vec3<f32>) -> vec3<f32> {
    const EPSILON: f32 = 0.001;
    let e = vec2<f32>(EPSILON, 0.0);

    return normalize(vec3<f32>(
        map_scene(p + e.xyy).r - map_scene(p - e.xyy).r,
        map_scene(p + e.yxy).r - map_scene(p - e.yxy).r,
        map_scene(p + e.yyx).r - map_scene(p - e.yyx).r
    ));
}

fn sphere_sdf(p: vec3<f32>, radius: f32) -> f32 {
    return length(p) - radius;
}

fn box_sdf(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

// returns distance, colour
fn map_scene(p: vec3<f32>) -> vec4<f32> {
    let displacement = sin(5.0 * p.x) * sin(5.0 * p.y) * sin(5.0 * p.z) * 0.25;
    let time = push_constants.time;

    let sphere1_pos = vec3<f32>(
        sin(time) * 1.0,
        cos(time) * 1.0,
        2.0
    );
    let sphere1 = sphere_sdf(p - sphere1_pos, 0.5);

    let sphere2_pos = vec3<f32>(
        cos(time * 0.5) * 1.5,
        sin(time * 0.7) * 0.8,
        2.0 + sin(time) * 0.5
    );
    let sphere2 = sphere_sdf(p - sphere2_pos, 0.7);

    let ground = -p.y + 1.5;

    let box = box_sdf(p - vec3<f32>(3.2, 0.0, -0.5), vec3<f32>(1.0));

    var result = vec4<f32>(min(sphere1, box), 1.0, 0.0, 1.0);

    return result;
}


// case 3: {
//     // Checkerboard pattern for the ground
//     let checker = (floor(p.x * 0.5) + floor(p.z * 0.5)) % 2.0;
//     return mix(
//         vec3<f32>(0.8, 0.8, 0.8),  // Light gray
//         vec3<f32>(0.2, 0.2, 0.2),  // Dark gray
//         checker
//     );
// }


fn soft_shadow(ro: vec3<f32>, rd: vec3<f32>, mint: f32, maxt: f32, k: f32) -> f32 {
    var res = 1.0;
    var t = mint;

    for(var i: i32 = 0; i < 64 && t < maxt; i++) {
        let h = map_scene(ro + rd * t).r;
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
    const MAX_STEPS: i32 = 128; // higher value will eliminate no-hit artifacts
    const MAX_DIST: f32 = 100.0;
    const HIT_DIST: f32 = 0.01;
    const AMBIENT: f32 = 0.075;

    for(var i: i32 = 0; i < MAX_STEPS; i++) {
        let p = ray_origin + t * ray_direction;
        let scene_info = map_scene(p).r;
        let d = scene_info;

        if(d < HIT_DIST) {
            // Hit something - calculate shading
            let normal = get_normal(p);

            // Light properties
            let light_pos = vec3<f32>(2.0, -4.0, -3.0);
            let light_dir = normalize(light_pos - p);
            let light_dist = length(light_pos - p);

            // Diffuse
            let diff = max(dot(normal, light_dir), 0.0);

            // Shadows
            let shadow = soft_shadow(p, light_dir, 0.1, light_dist, 16.0);

            // Material color based on object ID
            // let material_color = vec3<f32>(1.0);
            let material_color = map_scene(p).gba;

            // Final color calculation
            let final_color = material_color * (AMBIENT + diff * shadow);

            return final_color;
        }

        if(t > MAX_DIST) {
            break;
        }

        t += d;
    }

    // Return background color if no hit
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

    let color = raymarch(camera_pos, ray_direction);

    return vec4<f32>(color, 1.0);
}
