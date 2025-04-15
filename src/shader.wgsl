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
        map_scene(vec3<f32>(p.x + EPSILON, p.y, p.z)) - map_scene(vec3<f32>(p.x - EPSILON, p.y, p.z)),
        map_scene(vec3<f32>(p.x, p.y + EPSILON, p.z)) - map_scene(vec3<f32>(p.x, p.y - EPSILON, p.z)),
        map_scene(vec3<f32>(p.x, p.y, p.z + EPSILON)) - map_scene(vec3<f32>(p.x, p.y, p.z - EPSILON)),
    ));
}

fn sphere_sdf(p: vec3<f32>, radius: f32) -> f32 {
    return length(p) - radius;
}

fn map_scene(p: vec3<f32>) -> f32 {
    let displacement = sin(10.0 * p.x) * sin(10.0 * p.y) * sin(10.0 * p.z) * 0.05;
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

    return min(sphere + displacement, sphere2 + displacement);
}

fn shadow(ray_origin: vec3<f32>, ray_direction: vec3<f32>, mint: f32, maxt: f32, light_size: f32) -> f32 {
    var res: f32 = 1.2;
    var t: f32 = mint;
    for (var i: u32 = 0; i < 256 && t < maxt; i++) {
        let h = map_scene(ray_origin + ray_direction * t);
        res = min(res, h/(light_size * t));
        t += clamp(h, 0.001, 0.2);
        if(res < -1.0 || t > maxt) { break; }
    }
    res = max(res, -1.0);
    return 0.25*(1.0+res) * (1.0 + res) * (2.0 - res);
}

fn raymarch(ray_origin: vec3<f32>, ray_direction: vec3<f32>) -> vec4<f32> {
    const MAX_STEPS: u32 = 128;
    const MIN_DISTANCE: f32 = 0.0001;
    const MAX_DISTANCE: f32 = 100.0;
    const GLOBAL_ILLUMINATION: f32 = 0.2;

    var distance_travelled: f32 = 0.0;
    var current_position: vec3<f32>;
    var colour: vec4<f32>;
    var light_position: vec3<f32> = vec3<f32>(-3.0, -5.0, 0.0);

    for (var i: u32 = 0; i < MAX_STEPS; i++) {
        current_position = ray_origin + ray_direction * distance_travelled;
        let distance_to_scene = map_scene(current_position);

        if (distance_to_scene < MIN_DISTANCE) {
            let normal = get_normal(current_position);
            let light_dir = normalize(light_position);
            let shadow = shadow(current_position, light_dir, 0.1, 3.0, 0.256);

            let diffuse = shadow * 1.0 + GLOBAL_ILLUMINATION;

            // colours don't show correctly because of linear colour spaces
            colour = vec4<f32>(vec3<f32>(diffuse * 0.93, diffuse * 0.12, diffuse * 0.12), 1.0);
            break;
        }

        distance_travelled += distance_to_scene;
        if (distance_travelled >= MAX_DISTANCE) {
            colour = vec4<f32>(0.0, 0.0, 0.0, 1.0);
            break;
        }
    }

    return colour;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    let aspect_ratio = window_dimensions.size.x / window_dimensions.size.y;
    let uv = in.clip_position.xy / window_dimensions.size;
    let adjusted_uv = vec2<f32>(
        (uv.x - 0.5),
        (uv.y - 0.5) * aspect_ratio
    );

    let cos_yaw = cos(window_dimensions.camera_yaw);
    let sin_yaw = sin(window_dimensions.camera_yaw);
    let cos_pitch = cos(window_dimensions.camera_pitch);
    let sin_pitch = sin(window_dimensions.camera_pitch);

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

    let colour = raymarch(ray_origin, ray_direction);

    return colour;
}
