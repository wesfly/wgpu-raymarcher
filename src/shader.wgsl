struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
};

struct Properties {
    size: vec2<f32>,
    time: f32,
    camera_yaw: f32,
    camera_pitch: f32,
}

var<push_constant> window_dimensions: Properties;

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

fn get_normal(p: vec3<f32>) -> vec3<f32> {
    const EPSILON: f32 = 0.0001;
    return normalize(vec3<f32>(
        scene_sdf(vec3<f32>(p.x + EPSILON, p.y, p.z)) - scene_sdf(vec3<f32>(p.x - EPSILON, p.y, p.z)),
        scene_sdf(vec3<f32>(p.x, p.y + EPSILON, p.z)) - scene_sdf(vec3<f32>(p.x, p.y - EPSILON, p.z)),
        scene_sdf(vec3<f32>(p.x, p.y, p.z + EPSILON)) - scene_sdf(vec3<f32>(p.x, p.y, p.z - EPSILON)),
    ));
}

fn sphere_sdf(p: vec3<f32>, radius: f32) -> f32 {
    return length(p) - radius;
}

fn scene_sdf(p: vec3<f32>) -> f32 {
    let time = window_dimensions.time;

    let sphere1_pos = vec3<f32>(
        sin(time) * 1.0,
        cos(time) * 1.0,
        2.0
    );

    let sphere2_pos = vec3<f32>(
        cos(time * 0.5) * 1.5,
        sin(time * 0.7) * 0.8,
        2.0 + sin(time) * 0.5
    );

    let sphere = sphere_sdf(p - sphere1_pos, 0.2);
    let sphere2 = sphere_sdf(p - sphere2_pos, 0.5);

    return min(sphere, sphere2);
}

fn shadow(ray_origin: vec3<f32>, ray_direction: vec3<f32>, mint: f32, maxt: f32, light_size: f32) -> f32 {
    var res: f32 = 1.0;
    var t: f32 = mint;
    for (var i: u32 = 0; i < 256 && t < maxt; i++) {
        let h = scene_sdf(ray_origin + ray_direction * t);
        res = min(res, h/(light_size * t));
        t += clamp(h, 0.001, 0.2); // Adjusted from 0.005, 0.5
        if(res < -1.0 || t > maxt) { break; }
    }
    res = max(res, -1.0);
    return 0.25*(1.0+res) * (1.0 + res) * (2.0 - res);
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    let aspect_ratio = window_dimensions.size.x / window_dimensions.size.y;
    let uv = in.clip_position.xy / window_dimensions.size;
    let adjusted_uv = vec2<f32>(
        (uv.x - 0.5),
        (uv.y - 0.5) * aspect_ratio
    );

    // Create rotation matrices
    let cos_yaw = cos(window_dimensions.camera_yaw);
    let sin_yaw = sin(window_dimensions.camera_yaw);
    let cos_pitch = cos(window_dimensions.camera_pitch);
    let sin_pitch = sin(window_dimensions.camera_pitch);

    // Create rotation matrix
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

    // Apply rotation to both ray origin and direction
    let base_ray_direction = vec3<f32>(adjusted_uv.x, adjusted_uv.y, 2.0);
    let rotated_direction = rotation_y * rotation_x * base_ray_direction;
    let ray_direction = normalize(rotated_direction);

    let base_ray_origin = vec3<f32>(0.0, 0.0, -3.0);
    let ray_origin = rotation_y * rotation_x * base_ray_origin;

    const MAX_STEPS: u32 = 128;
    const MIN_DISTANCE: f32 = 0.0001;
    const MAX_DISTANCE: f32 = 100.0;
    const GLOBAL_ILLUMINATION: f32 = 0.1;

    var depth: f32 = 0.0;
    var hit_position: vec3<f32>;
    var colour: vec4<f32>;

    for (var i: u32 = 0; i < MAX_STEPS; i++) {
        hit_position = ray_origin + ray_direction * depth;
        let distance = scene_sdf(hit_position);

        if (distance < MIN_DISTANCE) {
            let normal = get_normal(hit_position);
            let light_dir = normalize(vec3<f32>(0.0, 5.0, 2.0));
            let shadow = shadow(hit_position, light_dir, 0.001, 3.0, 0.1); // Adjusted mint from 0.01
            let diffuse = shadow * 0.9 + GLOBAL_ILLUMINATION; // Adjusted from 0.8

            colour = vec4<f32>(vec3<f32>(diffuse), 1.0);
            break;
        }

        depth += distance;
        if (depth >= MAX_DISTANCE) {
            colour = vec4<f32>(0.1, 0.2, 0.3, 1.0);
            break;
        }
    }

    return colour;
}
