struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
};

struct WindowDimensions{
    size: vec2<f32>
}

var<push_constant> window_dimensions: WindowDimensions;

@vertex
fn vs_main(
    @builtin(vertex_index) in_vertex_index: u32,
) -> VertexOutput {
    var out: VertexOutput;

    let positions = array<vec2<f32>, 4>(
        vec2<f32>(-1.0, 1.0),   // TL vertex 0
        vec2<f32>(-1.0, -1.0),  // BL vertex 1
        vec2<f32>(1.0, -1.0),   // BR vertex 2
        vec2<f32>(1.0, 1.0),    // BL vertex 3
    );

    let indices = array<u32, 6>(
        0, 1, 2,
        0, 2, 3
    );

    // Get the vertex position based on the vertex index
    let pos = positions[indices[in_vertex_index]];

    // Convert from normalized device coordinates to clip space
    // vec4(x, y, z, w) where w=1 for 2D points
    out.clip_position = vec4<f32>(pos.x, pos.y, 0.0, 1.0);

    return out;
}

// Distance field functions

fn get_normal(p: vec3<f32>) -> vec3<f32> {
    const EPSILON: f32 = 0.001;
    return normalize(vec3<f32>(
        scene_sdf(vec3<f32>(p.x + EPSILON, p.y, p.z)) - scene_sdf(vec3<f32>(p.x - EPSILON, p.y, p.z)),
        scene_sdf(vec3<f32>(p.x, p.y + EPSILON, p.z)) - scene_sdf(vec3<f32>(p.x, p.y - EPSILON, p.z)),
        scene_sdf(vec3<f32>(p.x, p.y, p.z + EPSILON)) - scene_sdf(vec3<f32>(p.x, p.y, p.z - EPSILON)),
    ));
}

fn sphere_sdf(p: vec3<f32>, radius: f32) -> f32 {
    return length(p) - radius;
}



// fn box_sdf(p: vec3<f32>, b: vec3<f32>) -> f32 {
//     let q = abs(p) - b;
//     let max_x = max(q.x, 0.0);
//     let max_y = max(q.y, 0.0);
//     let max_z = max(q.z, 0.0);
//     let max_q = vec3<f32>(max_x, max_y, max_z);
//     return length(max_q) + min(max(max_x, max(max_y, max_z)), 0.0);
// }

// Combined distance field
fn scene_sdf(p: vec3<f32>) -> f32 {
    let sphere = sphere_sdf(p - vec3<f32>(0.6, 0.8, 2.0), 0.2);
    let sphere2 = sphere_sdf(p - vec3<f32>(1.0, 0.3, 2.0), 0.5);
    // let box = box_sdf(p - vec3<f32>(-2.0, 0.0, 0.0), vec3<f32>(1.0));
    return min(sphere, sphere2);
    // return sphere;
}

fn shadow(ray_origin: vec3<f32>, ray_direction: vec3<f32>, mint: f32, maxt: f32, light_size: f32) -> f32 {
    var res: f32 = 1.0;
    var t: f32 = mint;
    for (var i: u32 = 0; i < 256 && t < maxt; i++) {
        let h = scene_sdf(ray_origin + ray_direction * t);
        res = min(res, h/(light_size * t));
        t+= clamp(h, 0.005, 0.5);
        if(res < - 1.0 || t>maxt){break;}
    }
    res = max(res, -1.0);
    return 0.25*(1.0+res) * (1.0 + res) * (2.0 - res);
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    let window_size = window_dimensions.size.xy * 2;

    // Convert normalized screen coordinates to ray direction
    let uv = ((in.clip_position.xy / in.clip_position.w) * 2.0 - 1.0) / window_size;
    let ray_origin = vec3<f32>(0.0, 0.0, 0.0);
    let ray_direction = normalize(vec3<f32>(uv.x, uv.y, 1.0));

    // Raymarching parameters
    const MAX_STEPS: u32 = 64;
    const MIN_DISTANCE: f32 = 0.0001;
    const MAX_DISTANCE: f32 = 100.0;
    const GLOBAL_ILLUMINATION: f32 = 0.01;

    // March the ray
    var depth: f32 = 0.0;   // init depth at zero
    var hit_position: vec3<f32>;
    var colour: vec4<f32>;

    for (var i: u32 = 0; i < MAX_STEPS; i++) {
        hit_position = ray_origin + ray_direction * depth;
        let distance = scene_sdf(hit_position);

        if (distance < MIN_DISTANCE) {
            // Calculate normal for shading
            let normal = get_normal(hit_position);
            let light_dir = normalize(vec3<f32>(0.0, 5.0, 2.0));
            let shadow = shadow(hit_position, light_dir, 0.01, 3.0, 0.1);
            // produces weird blending effect I don't want to investigate further
            let diffuse = shadow * 0.8 + GLOBAL_ILLUMINATION;

            colour = vec4<f32>(vec3<f32>(diffuse), 1.0);
            break;
        }

        depth += distance;
        if (depth >= MAX_DISTANCE) {
            colour = vec4<f32>(0.0, 0.0, 0.0, 1.0); // Background colour
            break;
        }
    }

    return colour;
}
